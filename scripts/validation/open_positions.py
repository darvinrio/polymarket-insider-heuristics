"""
Fetch open positions for a Polymarket trader, with per-(trader, conditionId)
disk caching so long condition_id lists can be paused and resumed later.

Responses are projected onto the closed-positions column set, with `cashPnl`
from /positions used as the `realizedPnl` column.
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
CACHE_DIR = os.path.join(_REPO_ROOT, "data", "cache", "cache_open_positions")
API_URL = "https://data-api.polymarket.com/positions"
PAGE_LIMIT = 500  # API max for `limit`
DEFAULT_CHUNK = 20  # how many conditionIds to request per API call
REQUEST_SLEEP = 0.15  # small delay between API calls to be polite
MAX_RETRIES = 3
RETRY_BACKOFF = 2.0  # seconds, doubles per retry

# Columns kept from each open position, matching closed_positions' output.
# `realizedPnl` does not exist on /positions; it is sourced from `cashPnl`.
_CLOSED_COLUMNS = [
    "proxyWallet",
    "asset",
    "conditionId",
    "avgPrice",
    "totalBought",
    "realizedPnl",
    "curPrice",
    "title",
    "slug",
    "icon",
    "eventSlug",
    "outcome",
    "outcomeIndex",
    "oppositeOutcome",
    "oppositeAsset",
    "endDate",
]
_OPEN_SOURCE_FIELD = {"realizedPnl": "cashPnl"}


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


def _save_to_cache(trader: str, condition_id: str, positions: list):
    path = _cache_path(trader, condition_id)
    with open(path, "w") as f:
        json.dump(positions, f, indent=2)


def is_cached(trader: str, condition_id: str) -> bool:
    return os.path.exists(_cache_path(trader.lower(), condition_id.lower()))


def _chunked(seq, size):
    for i in range(0, len(seq), size):
        yield seq[i : i + size]


def _project_to_closed_columns(item: dict) -> dict:
    """Keep only the closed-positions columns, mapping `realizedPnl` <- `cashPnl`."""
    return {
        col: item.get(_OPEN_SOURCE_FIELD.get(col, col)) for col in _CLOSED_COLUMNS
    }


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


def _fetch_chunk(trader: str, market_chunk: list) -> tuple[list, bool]:
    """Fetch ALL open positions for a chunk of conditionIds, paginating
    through the API (limit=500 per page) until exhausted.

    Returns (items, interrupted). If KeyboardInterrupt hits mid-pagination,
    whatever pages were collected so far are returned with interrupted=True
    so the caller can persist them before stopping."""
    all_items = []
    offset = 0
    market_param = ",".join(market_chunk)

    while True:
        params = {
            "user": trader,
            "market": market_param,
            "sizeThreshold": 0,
            "limit": PAGE_LIMIT,
            "offset": offset,
        }
        try:
            page = _get_page(params)
        except KeyboardInterrupt:
            logger.warning(
                f"Interrupted mid-chunk; keeping {len(all_items)} items fetched so far"
            )
            return all_items, True

        all_items.extend(page)

        if len(page) < PAGE_LIMIT:
            break  # last page

        offset += PAGE_LIMIT
        if offset > 10000:  # API's documented max offset
            break

        time.sleep(REQUEST_SLEEP)

    return all_items, False


def _group_by_condition(items: list, market_chunk: list) -> dict:
    """Group returned items by conditionId so each id gets its own cache entry
    (some ids in the chunk may have zero positions)."""
    by_condition = {cid: [] for cid in market_chunk}
    for item in items:
        cid = item.get("conditionId", "").lower()
        by_condition.setdefault(cid, []).append(item)
    return by_condition


# --- Main function ---------------------------------------------------------


def get_open_positions(
    trader: str,
    condition_ids: list,
    chunk: int = DEFAULT_CHUNK,
    use_cache: bool = True,
) -> list:
    """
    Get open positions for a trader across a list of conditionIds.

    Args:
        trader: 0x-prefixed wallet address of the trader.
        condition_ids: list of 0x-prefixed 64-hex conditionIds to look up.
        chunk: how many conditionIds to send per API request (batching).
        use_cache: if True (default), reuse cached results per
            (trader, conditionId) and only fetch what's missing. Safe to
            interrupt and re-run later; results already cached are skipped.

    Returns:
        List of position dicts projected onto the closed-positions columns,
        where `realizedPnl` holds the API's `cashPnl`.
    """
    trader = trader.lower()
    condition_ids = [c.lower() for c in condition_ids]

    results = []
    to_fetch = []
    cached_positions = 0

    # 1. Pull whatever is already cached.
    for cid in condition_ids:
        cached = _load_from_cache(trader, cid) if use_cache else None
        if cached is not None:
            results.extend(_project_to_closed_columns(item) for item in cached)
            cached_positions += len(cached)
        else:
            to_fetch.append(cid)

    # logger.info(
    #     f"{trader}: {len(condition_ids) - len(to_fetch)}/{len(condition_ids)} "
    #     f"conditionIds from cache ({cached_positions} positions), "
    #     f"{len(to_fetch)} to fetch"
    # )

    if not to_fetch:
        return results

    # 2. Fetch the rest in chunks, then split & cache per conditionId.
    interrupted = False
    for market_chunk in _chunked(to_fetch, chunk):
        try:
            items, chunk_interrupted = _fetch_chunk(trader, market_chunk)
        except (requests.RequestException, ValueError) as exc:
            logger.error(
                f"{trader}: skipping chunk of {len(market_chunk)} cids after "
                f"{MAX_RETRIES} attempts ({exc}); re-run later to retry them"
            )
            time.sleep(REQUEST_SLEEP)
            continue

        by_condition = _group_by_condition(items, market_chunk)
        fetched_positions = 0
        for cid, cid_items in by_condition.items():
            _save_to_cache(trader, cid, cid_items)
            results.extend(_project_to_closed_columns(item) for item in cid_items)
            fetched_positions += len(cid_items)

        logger.info(
            f"{trader}: chunk {len(market_chunk)} cids -> {fetched_positions} positions"
        )

        if chunk_interrupted:
            interrupted = True
            break

        time.sleep(REQUEST_SLEEP)

    if interrupted:
        raise KeyboardInterrupt(
            f"Fetch interrupted; progress for {trader} saved to cache, re-run to resume"
        )

    return results


if __name__ == "__main__":
    # Example usage
    trader_address = "0xce296aaf92ecc022cc6608a54c622bb1c445b71b"
    condition_ids_example = [
        "0x45932bc66b00af152e158b1f4c916d9f1e7639b5641c7e8c2a6901a7efa905a9",
    ]
    positions = get_open_positions(
        trader=trader_address,
        condition_ids=condition_ids_example,
        chunk=20,
        use_cache=True,
    )
    print(json.dumps(positions, indent=2))
