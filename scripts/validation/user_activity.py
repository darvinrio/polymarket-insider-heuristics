"""
Fetch user activity for a Polymarket trader across conditionIds, with per-
(trader, conditionId) disk caching so long condition_id lists can be paused
and resumed later. Pagination walks forward in time and rolls into fresh
start/end windows whenever the API's per-window offset budget runs out, so
the full history for each (user, conditionId) pair is retrieved.
"""

import json
import os
import time

import requests
from loguru import logger

# --- Constants ---------------------------------------------------------

_REPO_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
CACHE_DIR = os.path.join(_REPO_ROOT, "data", "cache", "cache_user_activity")
API_URL = "https://data-api.polymarket.com/activity"
PAGE_LIMIT = 500  # API max for `limit`
OFFSET_CAP = 5000  # API max `offset`; deeper history needs time windows
DEFAULT_CHUNK = 20  # how many conditionIds to request per API call
REQUEST_SLEEP = 0.15  # small delay between API calls to be polite
MAX_RETRIES = 3
RETRY_BACKOFF = 2.0  # seconds, doubles per retry


# --- Helpers -------------------------------------------------------------


def _cache_path(trader: str, condition_id: str) -> str:
    trader_dir = os.path.join(CACHE_DIR, trader.lower())
    os.makedirs(trader_dir, exist_ok=True)
    return os.path.join(trader_dir, f"{condition_id.lower()}.json")


def _load_from_cache(trader: str, condition_id: str):
    path = _cache_path(trader, condition_id)
    if not os.path.exists(path):
        return None
    with open(path, "r") as f:
        return json.load(f)


def _save_to_cache(trader: str, condition_id: str, activity: list):
    path = _cache_path(trader, condition_id)
    with open(path, "w") as f:
        json.dump(activity, f, indent=2)


def is_cached(trader: str, condition_id: str) -> bool:
    return os.path.exists(_cache_path(trader.lower(), condition_id.lower()))


def _chunked(seq, size):
    for i in range(0, len(seq), size):
        yield seq[i : i + size]


def _get_page(params: dict) -> list:
    last_exc = None
    for attempt in range(MAX_RETRIES):
        try:
            resp = requests.get(API_URL, params=params, timeout=30)
            resp.raise_for_status()
            page = resp.json()
            if not isinstance(page, list):
                raise ValueError(f"Unexpected API response: {page}")
            return page
        except (requests.RequestException, ValueError) as exc:
            last_exc = exc
            if attempt < MAX_RETRIES - 1:
                sleep_for = RETRY_BACKOFF * (2**attempt)
                logger.warning(
                    f"Request failed ({exc}); retry {attempt + 1}/{MAX_RETRIES - 1} "
                    f"in {sleep_for:.0f}s"
                )
                time.sleep(sleep_for)
    raise last_exc


def _row_key(row: dict) -> tuple:
    """Composite identity of an activity row; used to drop boundary rows that
    two overlapping time windows both serve."""
    return (
        row.get("timestamp"),
        row.get("transactionHash"),
        row.get("type"),
        (row.get("conditionId") or "").lower(),
        row.get("asset"),
        row.get("side"),
        row.get("outcomeIndex"),
        row.get("price"),
        row.get("size"),
    )


def _fetch_chunk(trader: str, market_chunk: list) -> tuple[list, bool]:
    """Fetch ALL activity for a chunk of conditionIds, paginating through the
    API (limit=500/page, oldest first) until exhausted. The endpoint rejects
    offsets past OFFSET_CAP within one query window, so when the budget runs
    out the fetcher rolls into a new window starting at the newest timestamp
    seen; boundary rows re-served by the next window are deduped away.

    Returns (items, interrupted). If KeyboardInterrupt hits mid-pagination,
    whatever pages were collected so far are returned with interrupted=True
    so the caller can persist them before stopping."""
    all_items = []
    seen = set()
    window_start = None  # None -> omit `start`; ASC then reads full history

    while True:
        offset = 0
        window_max_ts = None

        while True:
            params = {
                "user": trader,
                "market": ",".join(market_chunk),
                "limit": PAGE_LIMIT,
                "offset": offset,
                "sortBy": "TIMESTAMP",
                "sortDirection": "ASC",
            }
            if window_start is not None:
                params["start"] = window_start

            try:
                page = _get_page(params)
            except KeyboardInterrupt:
                logger.warning(
                    f"Interrupted mid-chunk; keeping {len(all_items)} items fetched so far"
                )
                return all_items, True

            for row in page:
                key = _row_key(row)
                if key not in seen:
                    seen.add(key)
                    all_items.append(row)

            if len(page) < PAGE_LIMIT:
                return all_items, False  # short page -> end of final window

            page_max_ts = max(int(r.get("timestamp", 0)) for r in page)
            if window_max_ts is None or page_max_ts > window_max_ts:
                window_max_ts = page_max_ts

            offset += PAGE_LIMIT
            if offset > OFFSET_CAP:
                break  # window's offset budget exhausted -> roll over

            time.sleep(REQUEST_SLEEP)

        if window_max_ts is None or (
            window_start is not None and window_max_ts <= window_start
        ):
            logger.warning(
                f"{trader}: no timestamp progress past start={window_start}; "
                f"stopping chunk with {len(all_items)} items"
            )
            return all_items, False

        window_start = window_max_ts


def _group_by_condition(items: list, market_chunk: list) -> dict:
    """Group returned rows by conditionId so each id gets its own cache entry
    (some ids in the chunk may have zero activity)."""
    by_condition = {cid: [] for cid in market_chunk}
    for item in items:
        cid = item.get("conditionId", "").lower()
        by_condition.setdefault(cid, []).append(item)
    return by_condition


# --- Main function ---------------------------------------------------------


def get_user_activity(
    user: str,
    condition_ids: list,
    chunk: int = DEFAULT_CHUNK,
    use_cache: bool = True,
) -> list:
    """
    Get full activity history for a user across a list of conditionIds.

    Args:
        user: 0x-prefixed wallet address of the trader.
        condition_ids: list of 0x-prefixed 64-hex conditionIds to look up.
        chunk: how many conditionIds to send per API request (batching).
        use_cache: if True (default), reuse cached results per
            (user, conditionId) and only fetch what's missing. Safe to
            interrupt and re-run later; results already cached are skipped.

    Returns:
        List of activity JSON objects (dicts) across all requested
        conditionIds.
    """
    user = user.lower()
    condition_ids = [c.lower() for c in condition_ids]

    results = []
    to_fetch = []

    # 1. Pull whatever is already cached.
    for cid in condition_ids:
        cached = _load_from_cache(user, cid) if use_cache else None
        if cached is not None:
            results.extend(cached)
        else:
            to_fetch.append(cid)

    # logger.info(
    #     f"{user}: {len(condition_ids) - len(to_fetch)}/{len(condition_ids)} "
    #     f"conditionIds from cache, {len(to_fetch)} to fetch"
    # )

    if not to_fetch:
        return results

    # 2. Fetch the rest in chunks, then split & cache per conditionId.
    interrupted = False
    for market_chunk in _chunked(to_fetch, chunk):
        try:
            items, chunk_interrupted = _fetch_chunk(user, market_chunk)
        except (requests.RequestException, ValueError) as exc:
            logger.error(
                f"{user}: skipping chunk of {len(market_chunk)} cids after "
                f"{MAX_RETRIES} attempts ({exc}); re-run later to retry them"
            )
            time.sleep(REQUEST_SLEEP)
            continue

        by_condition = _group_by_condition(items, market_chunk)
        fetched_rows = 0
        for cid, cid_items in by_condition.items():
            _save_to_cache(user, cid, cid_items)
            results.extend(cid_items)
            fetched_rows += len(cid_items)

        logger.info(
            f"{user}: chunk of {len(market_chunk)} cids -> {fetched_rows} activity rows"
        )

        if chunk_interrupted:
            interrupted = True
            break

        time.sleep(REQUEST_SLEEP)

    if interrupted:
        raise KeyboardInterrupt(
            f"Fetch interrupted; progress for {user} saved to cache, re-run to resume"
        )

    return results


if __name__ == "__main__":
    # Example usage
    trader_address = "0xce296aaf92ecc022cc6608a54c622bb1c445b71b"
    condition_ids_example = [
        "0x45932bc66b00af152e158b1f4c916d9f1e7639b5641c7e8c2a6901a7efa905a9",
    ]
    activity = get_user_activity(
        user=trader_address,
        condition_ids=condition_ids_example,
        chunk=20,
        use_cache=True,
    )
    print(json.dumps(activity, indent=2))
