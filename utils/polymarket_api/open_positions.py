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

from utils.polymarket_api import common

# --- Constants ---------------------------------------------------------

API_URL = "https://data-api.polymarket.com/positions"
CACHE_DIR = os.path.join(common.REPO_ROOT, "data", "cache", "cache_open_positions")
PAGE_LIMIT = 500  # API max for `limit`
OFFSET_CAP = 10_000  # API's documented max offset
DEFAULT_CHUNK = 20  # how many conditionIds to request per API call

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


def _project_to_closed_columns(item: dict) -> dict:
    """Keep only the closed-positions columns, mapping `realizedPnl` <- `cashPnl`."""
    return {col: item.get(_OPEN_SOURCE_FIELD.get(col, col)) for col in _CLOSED_COLUMNS}


def is_cached(trader: str, condition_id: str) -> bool:
    return common.is_cached(CACHE_DIR, trader, condition_id)


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
        cached = common.load_from_cache(CACHE_DIR, trader, cid) if use_cache else None
        if cached is not None:
            results.extend(_project_to_closed_columns(item) for item in cached)
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
                base_params={"user": trader, "sizeThreshold": 0},
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
            results.extend(_project_to_closed_columns(item) for item in cid_items)
            fetched_positions += len(cid_items)

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
    positions = get_open_positions(
        trader=trader_address,
        condition_ids=condition_ids_example,
        chunk=20,
        use_cache=True,
    )
    print(json.dumps(positions, indent=2))
