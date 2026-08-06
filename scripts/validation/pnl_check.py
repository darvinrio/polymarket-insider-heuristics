import polars as pl

from scripts.validation.closed_positions import get_closed_positions
from scripts.validation.schema import CLOSED_POSITIONS_SCHEMA, SAMPLE_SCHEMA

samples_file = "data/csvs/polymarket_resolutions_stratified_sampling.csv"

samples_df = pl.scan_csv(samples_file, schema_overrides=SAMPLE_SCHEMA)

# print(samples_df.head().collect())

# EDA
# Count of Distinct Traders - Column `trader`
# Count of Distinct Condition ID - Column `condition_id`
eda_df = samples_df.select(
    [
        pl.col("trader").count().alias("trader_count"),
        pl.col("trader").n_unique().alias("trader_unique_count"),
        pl.col("condition_id").count().alias("condition_id_count"),
        pl.col("condition_id").n_unique().alias("condition_id_unique_count"),
    ]
)
print(eda_df.collect())

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
print(trader_condition_df.sort(pl.col("condition_id_count")).collect())

all_positions = []
for (
    trader,
    condition_id_list,
    condition_id_count,
) in trader_condition_df.collect().iter_rows():
    print(f"Trader: {trader}, Conditions: {condition_id_count}")
    trader_closed_positions = get_closed_positions(
        trader=trader,
        condition_ids=condition_id_list,
    )
    all_positions.extend(trader_closed_positions)

all_positions_df = pl.LazyFrame(all_positions, schema_overrides=CLOSED_POSITIONS_SCHEMA)
print(all_positions_df.collect())

# Check
# Traders in Sample DF match Traders in Closed Positions DF
# Condition IDs in Sample DF match Condition IDs in Closed Positions DF
