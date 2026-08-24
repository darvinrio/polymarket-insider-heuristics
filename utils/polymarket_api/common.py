"""
Shared helpers for Polymarket data-api clients: retrying HTTP GETs,
paginated chunk fetching, conditionId grouping, and per-(trader, conditionId)
disk caching.
"""

import json
import os
import time

import requests
from loguru import logger

# --- Constants ---------------------------------------------------------

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REQUEST_SLEEP = 0.15  # small delay between API calls to be polite
MAX_RETRIES = 3
RETRY_BACKOFF = 2.0  # seconds, doubles per retry


# --- Disk cache ----------------------------------------------------------


def cache_path(cache_dir: str, trader: str, condition_id: str) -> str:
    trader_dir = os.path.join(cache_dir, trader.lower())
    os.makedirs(trader_dir, exist_ok=True)
    return os.path.join(trader_dir, f"{condition_id.lower()}.json")


def load_from_cache(cache_dir: str, trader: str, condition_id: str):
    path = cache_path(cache_dir, trader, condition_id)
    if not os.path.exists(path):
        return None
    with open(path, "r") as f:
        return json.load(f)


def save_to_cache(cache_dir: str, trader: str, condition_id: str, positions: list):
    path = cache_path(cache_dir, trader, condition_id)
    with open(path, "w") as f:
        json.dump(positions, f, indent=2)


def is_cached(cache_dir: str, trader: str, condition_id: str) -> bool:
    return os.path.exists(cache_path(cache_dir, trader.lower(), condition_id.lower()))


# --- Fetching ------------------------------------------------------------


def chunked(seq, size):
    for i in range(0, len(seq), size):
        yield seq[i : i + size]


def get_page(url: str, params: dict) -> list:
    last_exc = None
    for attempt in range(MAX_RETRIES):
        try:
            resp = requests.get(url, params=params, timeout=30)
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


def fetch_chunk(
    url: str,
    base_params: dict,
    market_chunk: list,
    page_limit: int,
    max_offset: int,
) -> tuple[list, bool]:
    """Fetch ALL positions for a chunk of conditionIds, paginating through the
    API (limit=`page_limit` per page) until exhausted.

    `base_params` holds endpoint-specific query params (e.g. {"user": trader},
    optionally plus things like "sizeThreshold").

    Returns (items, interrupted). If KeyboardInterrupt hits mid-pagination,
    whatever pages were collected so far are returned with interrupted=True
    so the caller can persist them before stopping."""
    all_items = []
    offset = 0
    market_param = ",".join(market_chunk)

    while True:
        params = {
            **base_params,
            "market": market_param,
            "limit": page_limit,
            "offset": offset,
        }
        try:
            page = get_page(url, params)
        except KeyboardInterrupt:
            logger.warning(
                f"Interrupted mid-chunk; keeping {len(all_items)} items fetched so far"
            )
            return all_items, True

        all_items.extend(page)

        if len(page) < page_limit:
            break  # last page

        offset += page_limit
        if offset > max_offset:
            break  # API's documented max offset

        time.sleep(REQUEST_SLEEP)

    return all_items, False


def group_by_condition(items: list, market_chunk: list) -> dict:
    """Group returned items by conditionId so each id gets its own cache entry
    (some ids in the chunk may have zero positions)."""
    by_condition = {cid: [] for cid in market_chunk}
    for item in items:
        cid = item.get("conditionId", "").lower()
        by_condition.setdefault(cid, []).append(item)
    return by_condition
