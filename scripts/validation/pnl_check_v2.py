import polars as pl
from loguru import logger

from scripts.validation.closed_positions import get_closed_positions
from scripts.validation.schema import CLOSED_POSITIONS_SCHEMA, SAMPLE_SCHEMA

logger.success("START")

samples_file = "data/csvs/polymarket_resolutions_stratified_sampling.csv"
rectified_samples = "data/csvs/polymarket_resolutions_v5_sample_positions_rectified.csv"

keys = ["trader", "token_id", "condition_id"]

samples_df = (
    pl.scan_csv(samples_file, schema_overrides=SAMPLE_SCHEMA)
    .with_columns(pl.concat_str(keys, separator="|").alias("key"))
    .drop(["h", "pnl_bucket", "rn"])
)

samples_keys = samples_df.select(pl.col("key")).collect()
logger.info(f"Number of samples: {len(samples_keys)}")

# Trader + List of Condition IDs
trader_condition_df = (
    samples_df.select(
        [
            pl.col("trader"),
            pl.col("condition_id"),
        ]
    )
    .unique()
    .group_by(pl.col("trader"))
    .agg(
        pl.col("condition_id").alias("condition_id_list"),
        pl.col("condition_id").len().alias("condition_id_count"),
    )
)

all_positions = []
for (
    trader,
    condition_id_list,
    condition_id_count,
) in trader_condition_df.collect().iter_rows():
    # logger.debug(f"Trader: {trader}, Conditions: {condition_id_count}")
    trader_closed_positions = get_closed_positions(
        trader=trader,
        condition_ids=condition_id_list,
    )
    all_positions.extend(trader_closed_positions)

all_positions_df = pl.LazyFrame(all_positions, schema_overrides=CLOSED_POSITIONS_SCHEMA)


def get_pnl_df(
    samples_df: pl.LazyFrame, all_positions_df: pl.LazyFrame
) -> pl.LazyFrame:

    return (
        samples_df.join(
            all_positions_df,
            left_on=["trader", "token_id"],
            right_on=["proxyWallet", "asset"],
            how="left",
        )
        .select(
            "trader", "token_id", "condition_id", "final_profit", "realizedPnl", "key"
        )
        .with_columns(
            pl.col("realizedPnl").sub(pl.col("final_profit")).alias("pnl_diff"),
            (pl.col("realizedPnl").sub(pl.col("final_profit")))
            .mul(100.00)
            .truediv(pl.col("final_profit"))
            .abs()
            .alias("pnl_diff_percent"),
            pl.when(pl.col("realizedPnl").is_null())
            .then(0)
            .otherwise(1)
            .alias("is_available"),
        )
        .with_columns(
            pl.when(pl.col("final_profit").round(2).eq(pl.col("realizedPnl").round(2)))
            .then(0)
            .otherwise(pl.col("pnl_diff_percent"))
            .alias("pnl_diff_percent"),
            pl.when(pl.col("final_profit").eq(0.00))
            .then(1)
            .otherwise(0)
            .alias("is_inf"),
        )
    )


combined_df = get_pnl_df(samples_df, all_positions_df)
combined_keys = (
    combined_df.filter(pl.col("is_available").eq(1)).select(pl.col("key")).collect()
)
logger.info(f"Number of API matches: {len(combined_keys)}")

missing_entries = combined_df.filter(pl.col("is_available").eq(0))
logger.info(f"Number of missing entries: {missing_entries.collect().shape[0]}")

polymarket_contract_entries = combined_df.filter(
    pl.col("trader").is_in(
        [
            "0xa5ef39c3d3e10d0b270233af41cac69796b12966",
            "0x05cd9922a5d37fae921fc5dee280a9dbc4c3b393",
        ]
    )
)
logger.info(
    f"Number of polymarket contract entries: {polymarket_contract_entries.collect().shape[0]}"
)

missing_entries = missing_entries.filter(
    ~pl.col("trader").is_in(
        [
            "0xa5ef39c3d3e10d0b270233af41cac69796b12966",
            "0x05cd9922a5d37fae921fc5dee280a9dbc4c3b393",
        ]
    )
)
logger.info(
    f"Number of missing entries (excluding polymarket contracts): {missing_entries.collect().shape[0]}"
)
missing_entries.drop("key").sort(pl.col("final_profit")).collect().write_csv(
    "scripts/validation/outputs/missing_entries.csv"
)


problematic_df = combined_df.filter(
    (pl.col("pnl_diff_percent").ge(1)) & (pl.col("pnl_diff").ge(10))
).sort("pnl_diff_percent", descending=True)

logger.info(f"Problematic positions: {problematic_df.collect().shape[0]}")

## ROUND 2
logger.success("ROUND 2")

problematic_keys = problematic_df.select("key").collect().to_series().to_list()
rectified_samples_df = (
    pl.scan_csv(rectified_samples, schema_overrides=SAMPLE_SCHEMA)
    .with_columns(pl.concat_str(keys, separator="|").alias("key"))
    .filter(pl.col("key").is_in(problematic_keys))
)

rectified_combined_df = get_pnl_df(rectified_samples_df, all_positions_df)
problematic_rectified_df = rectified_combined_df.filter(
    (pl.col("pnl_diff_percent").ge(1)) & (pl.col("pnl_diff").ge(10))
).sort("pnl_diff_percent", descending=True)

logger.info(
    f"Problematic post rectification: {problematic_rectified_df.collect().shape[0]}"
)

problematic_rectified_df.drop("key").collect().write_csv(
    "scripts/validation/outputs/pnl_diff_percent_above_1_v2.csv"
)
