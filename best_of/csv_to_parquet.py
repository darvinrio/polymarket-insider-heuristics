import polars as pl
from schema import EVENTS_SCHEMA, MARKETS_SCHEMA


def date_parse(date_col: pl.Expr) -> pl.Expr:
    return date_col.str.to_datetime("%Y-%m-%d %H:%M:%S%.3f UTC")


events_df = pl.scan_csv(
    "data/best_of_2025.csv", schema_overrides=EVENTS_SCHEMA
).with_columns(
    date_parse(pl.col("block_time")),
)

markets_df = pl.scan_csv(
    "data/best_of_2025_markets.csv", schema_overrides=MARKETS_SCHEMA
).with_columns(
    date_parse(pl.col("market_start_time")),
    date_parse(pl.col("market_end_time")),
    date_parse(pl.col("resolved_on_timestamp")),
    date_parse(pl.col("orders_end_time")),
)

print(markets_df.head().collect())
# events_df.collect().write_parquet("data/best_of_2025.parquet")
markets_df.collect().write_parquet("data/best_of_2025_markets.parquet")
