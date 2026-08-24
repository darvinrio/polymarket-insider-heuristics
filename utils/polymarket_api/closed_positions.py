"""
Fetch closed positions for a Polymarket trader, with per-(trader, conditionId)
disk caching so long condition_id lists can be paused and resumed later.
"""

import json
import os
import time

import requests
from loguru import logger

from utils.polymarket_api import common

# --- Constants ---------------------------------------------------------

API_URL = "https://data-api.polymarket.com/closed-positions"
CACHE_DIR = os.path.join(common.REPO_ROOT, "data", "cache", "cache_closed_positions")
PAGE_LIMIT = 50  # API max for `limit`
OFFSET_CAP = 100_000  # API's documented max offset
DEFAULT_CHUNK = 20  # how many conditionIds to request per API call


# --- Public helpers ------------------------------------------------------


def is_cached(trader: str, condition_id: str) -> bool:
    return common.is_cached(CACHE_DIR, trader, condition_id)


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
    cached_positions = 0

    # 1. Pull whatever is already cached.
    for cid in condition_ids:
        cached = common.load_from_cache(CACHE_DIR, trader, cid) if use_cache else None
        if cached is not None:
            results.extend(cached)
            cached_positions += len(cached)
        else:
            to_fetch.append(cid)

    if not to_fetch:
        return results

    # 2. Fetch the rest in chunks, then split & cache per conditionId.
    interrupted = False
    for market_chunk in common.chunked(to_fetch, chunk):
        try:
            items, chunk_interrupted = common.fetch_chunk(
                API_URL,
                base_params={"user": trader},
                market_chunk=market_chunk,
                page_limit=PAGE_LIMIT,
                max_offset=OFFSET_CAP,
            )
        except (requests.RequestException, ValueError) as exc:
            logger.error(
                f"{trader}: skipping chunk of {len(market_chunk)} cids after "
                f"{common.MAX_RETRIES} attempts ({exc}); re-run later to retry them"
            )
            time.sleep(common.REQUEST_SLEEP)
            continue

        by_condition = common.group_by_condition(items, market_chunk)
        fetched_positions = 0
        for cid, cid_items in by_condition.items():
            common.save_to_cache(CACHE_DIR, trader, cid, cid_items)
            results.extend(cid_items)
            fetched_positions += len(cid_items)

        logger.info(
            f"{trader}: chunk {len(market_chunk)} cids -> {fetched_positions} positions"
        )

        if chunk_interrupted:
            interrupted = True
            break

        time.sleep(common.REQUEST_SLEEP)

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
    positions = get_closed_positions(
        trader=trader_address,
        condition_ids=condition_ids_example,
        chunk=20,
        use_cache=True,
    )
    print(json.dumps(positions, indent=2))
