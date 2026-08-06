"""
Fetch closed positions for a Polymarket trader, with per-(trader, conditionId)
disk caching so long condition_id lists can be paused and resumed later.
"""

import json
import os
import time

import requests

# --- Constants ---------------------------------------------------------

CACHE_DIR = "data/cache/cache_closed_positions"
API_URL = "https://data-api.polymarket.com/closed-positions"
PAGE_LIMIT = 50  # API max for `limit`
DEFAULT_CHUNK = 20  # how many conditionIds to request per API call
REQUEST_SLEEP = 0.15  # small delay between API calls to be polite


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


def _chunked(seq, size):
    for i in range(0, len(seq), size):
        yield seq[i : i + size]


def _fetch_chunk(trader: str, market_chunk: list) -> list:
    """Fetch ALL closed positions for a chunk of conditionIds, paginating
    through the API (limit=50 per page) until exhausted."""
    all_items = []
    offset = 0
    market_param = ",".join(market_chunk)

    while True:
        params = {
            "user": trader,
            "market": market_param,
            "limit": PAGE_LIMIT,
            "offset": offset,
        }
        resp = requests.get(API_URL, params=params, timeout=30)
        resp.raise_for_status()
        page = resp.json()

        if not isinstance(page, list):
            raise ValueError(f"Unexpected API response: {page}")

        all_items.extend(page)

        if len(page) < PAGE_LIMIT:
            break  # last page

        offset += PAGE_LIMIT
        if offset > 100000:  # API's documented max offset
            break

        time.sleep(REQUEST_SLEEP)

    return all_items


# --- Main function ---------------------------------------------------------


def get_closed_positions(
    trader: str,
    condition_ids: list,
    chunk: int = DEFAULT_CHUNK,
    use_cache: bool = True,
) -> list:
    """
    Get closed positions for a trader across a list of conditionIds.

    Args:
        trader: 0x-prefixed wallet address of the trader.
        condition_ids: list of 0x-prefixed 64-hex conditionIds to look up.
        chunk: how many conditionIds to send per API request (batching).
        use_cache: if True (default), reuse cached results per
            (trader, conditionId) and only fetch what's missing. Safe to
            interrupt and re-run later; results already cached are skipped.

    Returns:
        List of closed-position JSON objects (dicts) across all requested
        conditionIds.
    """
    trader = trader.lower()
    condition_ids = [c.lower() for c in condition_ids]

    results = []
    to_fetch = []

    # 1. Pull whatever is already cached.
    for cid in condition_ids:
        cached = _load_from_cache(trader, cid) if use_cache else None
        if cached is not None:
            results.extend(cached)
        else:
            to_fetch.append(cid)

    if not to_fetch:
        return results

    # 2. Fetch the rest in chunks, then split & cache per conditionId.
    for market_chunk in _chunked(to_fetch, chunk):
        items = _fetch_chunk(trader, market_chunk)

        # Group returned items by conditionId so each id gets its own
        # cache entry (some ids in the chunk may have zero positions).
        by_condition = {cid: [] for cid in market_chunk}
        for item in items:
            cid = item.get("conditionId", "").lower()
            if cid in by_condition:
                by_condition[cid].append(item)
            else:
                # Defensive: unexpected conditionId, still keep the data.
                by_condition.setdefault(cid, []).append(item)

        for cid, cid_items in by_condition.items():
            _save_to_cache(trader, cid, cid_items)
            results.extend(cid_items)

        time.sleep(REQUEST_SLEEP)

    return results


if __name__ == "__main__":
    # Example usage
    trader_address = "0xce296aaf92ecc022cc6608a54c622bb1c445b71b"
    condition_ids_example = [
        "0x45932bc66b00af152e158b1f4c916d9f1e7639b5641c7e8c2a6901a7efa905a9",
    ]
    positions = get_closed_positions(
        trader=trader_address,
        condition_ids=condition_ids_example,
        chunk=20,
        use_cache=True,
    )
    print(json.dumps(positions, indent=2))
