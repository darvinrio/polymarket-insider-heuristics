import polars as pl
from loguru import logger

from utils.polymarket_api.closed_positions import get_closed_positions
from scripts.validation.schema import CLOSED_POSITIONS_SCHEMA, SAMPLE_SCHEMA

samples_file = "data/csvs/polymarket_resolutions_stratified_sampling.csv"
rectified_samples = "data/csvs/polymarket_resolutions_v5_sample_positions_rectified.csv"

keys = ["trader", "token_id", "condition_id"]

samples_df = (
    pl.scan_csv(samples_file, schema_overrides=SAMPLE_SCHEMA)
    .with_columns(pl.concat_str(keys, separator="|").alias("key"))
    .drop(["h", "pnl_bucket", "rn"])
)
rectified_samples_df = pl.scan_csv(
    rectified_samples, schema_overrides=SAMPLE_SCHEMA
).with_columns(pl.concat_str(keys, separator="|").alias("key"))

samples_key = samples_df.select("key")
rectified_samples_key = rectified_samples_df.with_columns(
    pl.concat_str(keys, separator="|").alias("key")
).select("key")
keys_to_rectify = samples_key.join(rectified_samples_key, on="key", how="inner")

logger.debug(f"keys_to_rectify head: {keys_to_rectify.collect()}")

# # Replace entries of samples_df with entries in rectified_samples_df
rows_in_samples = samples_df.collect().shape[0]
samples_df = pl.concat(
    [
        samples_df.join(rectified_samples_df, on="key", how="anti"),
        rectified_samples_df.join(keys_to_rectify, on="key", how="inner"),
    ]
)
rows_in_rectified = samples_df.collect().shape[0]
if rows_in_rectified != rows_in_samples:
    logger.warning(
        f"Rows in Orginal samples do not match rectified samples {rows_in_rectified} != {rows_in_samples}"
    )
else:
    logger.success(
        f"Rectified samples match original samples {rows_in_rectified} = {rows_in_samples}"
    )


# print(samples_df.head().collect())

# EDA
# Count of Distinct Traders - Column `trader`
# Count of Distinct Condition ID - Column `condition_id`
# Count of Distinct Trader + TokenId combos
eda_df = samples_df.with_columns(
    pl.concat_str([pl.col("trader"), pl.col("token_id")], separator="_").alias(
        "trader_token_id"
    )
).select(
    [
        pl.col("trader").count().alias("trader_count"),
        pl.col("trader").n_unique().alias("trader_unique_count"),
        pl.col("condition_id").count().alias("condition_id_count"),
        pl.col("condition_id").n_unique().alias("condition_id_unique_count"),
        pl.col("trader_token_id").n_unique().alias("trader_token_id_count"),
    ]
)
logger.info(eda_df.collect())
logger.info(
    f"Total positions: {eda_df.collect().select('trader_token_id_count').item()}"
)

# DeDupe for API - Extract Trader + Condition ID unique combinations
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
# print(trader_condition_df.sort(pl.col("condition_id_count")).collect())

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
# .rename(
#     {
#         "proxyWallet": "trader",
#         "conditionId": "condition_id",
#         "asset": "token_id",
#         "realizedPnl": "final_profit",
#     }
# )
# print(all_positions_df.collect())

# Check
# Traders in Sample DF match Traders in Closed Positions DF
# Condition IDs in Sample DF match Condition IDs in Closed Positions DF
traders_in_all_positions = (
    all_positions_df.select(pl.col("proxyWallet"))
    .unique()
    .collect()
    .to_series()
    .to_list()
)
traders_in_sample = (
    samples_df.select(pl.col("trader")).unique().collect().to_series().to_list()
)
missing_traders = [
    trader for trader in traders_in_sample if trader not in traders_in_all_positions
]

condition_ids_in_all_positions = (
    all_positions_df.select(pl.col("conditionId"))
    .unique()
    .collect()
    .to_series()
    .to_list()
)
condition_ids_in_sample = (
    samples_df.select(pl.col("condition_id")).unique().collect().to_series().to_list()
)
missing_condition_ids = [
    condition_id
    for condition_id in condition_ids_in_sample
    if condition_id not in condition_ids_in_all_positions
]

logger.info(f"Missing traders count: {len(missing_traders)}")
logger.info(f"Missing condition IDs count: {len(missing_condition_ids)}")

# Check PnL
combined_df = (
    samples_df.join(
        all_positions_df,
        left_on=["trader", "token_id"],
        right_on=["proxyWallet", "asset"],
        how="left",
    )
    .select("trader", "token_id", "condition_id", "final_profit", "realizedPnl")
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
        pl.when(pl.col("final_profit").eq(0.00)).then(1).otherwise(0).alias("is_inf"),
    )
    # .drop("condition_id")
)

# logger.debug(f"Sample of combined_df: {combined_df.collect().head()}")

# Stats
# PnL diff percent - Max, Average, Median, P75, P90, P99, P99.99
pnl_diff_percent_stats = combined_df.select(pl.col("pnl_diff_percent")).describe(
    percentiles=(0.25, 0.5, 0.75, 0.9, 0.99, 0.9999)
)
logger.info(f"PnL diff percent stats: {pnl_diff_percent_stats}")

# logger.debug(
#     combined_df.filter((pl.col("is_available") == 1) & (pl.col("is_inf") == 0))
#     .sort("pnl_diff_percent", descending=True)
#     .collect()
#     .head()
# )

problematic_df = combined_df.filter(
    (pl.col("pnl_diff_percent").ge(1)) & (pl.col("pnl_diff").ge(10))
).sort("pnl_diff_percent", descending=True)

logger.info(f"Problematic positions count: {problematic_df.collect().shape[0]}")
problematic_df.collect().write_csv(
    "scripts/validation/outputs/pnl_diff_percent_above_1.csv"
)
