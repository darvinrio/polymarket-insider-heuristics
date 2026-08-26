import polars as pl
from schema import EVENTS_SCHEMA, TRADE_TYPE_ENUM


def date_parse(date_col: pl.Expr) -> pl.Expr:
    return date_col.str.to_datetime("%Y-%m-%d %H:%M:%S%.3f UTC")


no_clob_df = pl.scan_csv(
    "data/wc_no_clob.csv", schema_overrides=EVENTS_SCHEMA
).with_columns(date_parse(pl.col("block_time")))
batch_2_df = pl.scan_csv("data/wc_b2.csv", schema_overrides=EVENTS_SCHEMA).with_columns(
    date_parse(pl.col("block_time"))
)
ADJ_EVENT_SCHEMA = {k: v for k, v in EVENTS_SCHEMA.items() if k != "trade_type"}
split_buy_df = pl.scan_csv(
    "data/wc_clob__buy__split.csv", schema_overrides=ADJ_EVENT_SCHEMA
).with_columns(
    date_parse(pl.col("block_time")),
    pl.lit("clob__buy__split").cast(TRADE_TYPE_ENUM).alias("trade_type"),
)
full_order_buy_df = pl.scan_csv(
    "data/wc_clob__buy__full_order.csv", schema_overrides=ADJ_EVENT_SCHEMA
).with_columns(
    date_parse(pl.col("block_time")),
    pl.lit("clob__buy__full_order").cast(TRADE_TYPE_ENUM).alias("trade_type"),
)
events_df = pl.concat([no_clob_df, batch_2_df, split_buy_df, full_order_buy_df])


print(events_df.head().collect())


events_df.collect().write_parquet("wc/data/wc_events.parquet")
