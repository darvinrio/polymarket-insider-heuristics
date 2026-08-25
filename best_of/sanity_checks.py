"""Sanity checks on the best_of events data joined with market metadata."""

import sys
from decimal import Decimal
from pathlib import Path

import polars as pl
from loguru import logger

DATA_DIR = Path("data/parquets")
EVENTS_PATH = DATA_DIR / "best_of_2025.parquet"
MARKETS_PATH = DATA_DIR / "best_of_2025_markets.parquet"
LOG_DIR = Path("logs/sanity_checks")

TAG_FILTER = "Google Search"
MIN_RUNNING_SHARES = -0.01


def configure_logging() -> None:
    """Configure loguru sinks for debug file logs and info terminal output."""
    logger.remove()
    logger.add(
        LOG_DIR / "sanity_checks_{time:YYYY-MM-DD}.log",
        rotation="5MB",
        level="DEBUG",
    )
    logger.add(sys.stderr, level="INFO")


def join_and_filter(events: pl.LazyFrame, markets: pl.LazyFrame) -> pl.LazyFrame:
    """Inner-join events with markets and keep only Google Search markets.

    Logs joined, kept, and dropped counts from a one-row aggregate collect;
    the event data itself stays lazy.

    Args:
        events: LazyFrame of trade events.
        markets: LazyFrame of market metadata.

    Returns:
        LazyFrame with events on markets tagged `Google Search`.
    """
    joined = events.join(
        markets.select("token_id", "question", "tags"), on="token_id", how="inner"
    )
    counts = joined.select(
        pl.len().alias("n_joined"),
        pl.col("tags").str.contains(TAG_FILTER).sum().alias("n_kept"),
    ).collect()
    n_joined = int(counts["n_joined"].item())
    n_kept = int(counts["n_kept"].item())
    logger.info(f"Joined events: {n_joined:,}")
    logger.info(f"Kept ({TAG_FILTER!r} markets): {n_kept:,}")
    logger.info(f"Dropped by tag filter: {n_joined - n_kept:,}")
    return joined.filter(pl.col("tags").str.contains(TAG_FILTER))


def compute_running_shares(df: pl.LazyFrame) -> pl.LazyFrame:
    """Compute the running share balance per trader and token.

    Args:
        df: Joined and filtered event LazyFrame.

    Returns:
        LazyFrame sorted within each group with a ``running_shares`` column.
    """
    return df.sort("trader", "token_id", "block_time", "evt_index").with_columns(
        pl.col("shares_delta")
        .cum_sum()
        .over("trader", "token_id")
        .alias("running_shares")
    )


def check_running_shares(df: pl.LazyFrame) -> bool:
    """Verify running share balances never drop to the allowed floor or below.

    Only small aggregate results are collected for reporting; the event data
    itself stays lazy.

    Args:
        df: LazyFrame with a ``running_shares`` column.

    Returns:
        True if the check passes, False otherwise.
    """
    n_violations = int(
        df.select((pl.col("running_shares") <= MIN_RUNNING_SHARES).sum().alias("n"))
        .collect()
        .item()
    )
    if n_violations == 0:
        logger.success(
            f"Check 1 passed: no running share balance <= {MIN_RUNNING_SHARES:,}"
        )
        return True
    violating_groups = (
        df.group_by("trader", "token_id")
        .agg(pl.col("running_shares").min(), pl.col("question").first())
        .filter(pl.col("running_shares") <= MIN_RUNNING_SHARES)
        .sort("running_shares")
    )
    n_groups = int(violating_groups.select(pl.len()).collect().item())
    worst = violating_groups.head(10).collect()
    logger.error(
        f"Check 1 failed: {n_violations:,} rows across {n_groups:,} "
        f"trader/token groups reached <= {MIN_RUNNING_SHARES:,}"
    )
    logger.debug(f"Worst offenders:\n{worst}")
    return False


def check_usd_totals(df: pl.LazyFrame) -> bool:
    """Verify total realized USD does not exceed total invested USD globally.

    Args:
        df: Joined and filtered event LazyFrame.

    Returns:
        True if the check passes, False otherwise.
    """
    totals = df.select(
        pl.col("usd_invested").sum().alias("total_invested"),
        pl.col("usd_realized").sum().alias("total_realized"),
    ).collect()
    total_invested: Decimal = totals["total_invested"].item()
    total_realized: Decimal = totals["total_realized"].item()
    logger.info(f"Total USD invested: {total_invested:,.2f}")
    logger.info(f"Total USD realized: {total_realized:,.2f}")
    if total_realized > total_invested:
        logger.error(
            f"Check 2 failed: usd_realized exceeds usd_invested by "
            f"{total_realized - total_invested:,.2f}"
        )
        return False
    logger.success("Check 2 passed: sum(usd_realized) <= sum(usd_invested)")
    return True


def main() -> None:
    """Run the full sanity-check pipeline."""
    configure_logging()
    events = pl.scan_parquet(EVENTS_PATH)
    markets = pl.scan_parquet(MARKETS_PATH)
    df = compute_running_shares(join_and_filter(events, markets))
    check_one = check_running_shares(df)
    check_two = check_usd_totals(df)
    if check_one and check_two:
        logger.success("All sanity checks passed")
    else:
        logger.error("One or more sanity checks failed")


if __name__ == "__main__":
    main()
