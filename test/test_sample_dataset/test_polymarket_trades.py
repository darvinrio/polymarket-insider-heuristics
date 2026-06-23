import matplotlib.pyplot as plt
import polars as pl
import seaborn as sns

from utils import invariant_log

sns.set_theme(style="darkgrid")

trades_schema = pl.Schema(
    {
        "block_month": pl.String,
        "block_time": pl.String,
        "block_number": pl.UInt64,
        "tx_hash": pl.String,
        "evt_index": pl.UInt32,
        "action": pl.String,
        "contract_address": pl.String,
        "condition_id": pl.String,
        "event_market_name": pl.String,
        "question": pl.String,
        "polymarket_link": pl.String,
        "token_outcome": pl.String,
        "neg_risk": pl.String,
        "asset_id": pl.String,
        "price": pl.Float64,
        "amount": pl.Float64,
        "shares": pl.Float64,
        "fee": pl.Float64,
        "maker": pl.String,
        "taker": pl.String,
        "is_taker_side": pl.String,
        "maker_side": pl.String,
        "taker_side": pl.String,
        "contract_version": pl.String,
        "builder": pl.String,
        "metadata": pl.String,
        "unique_key": pl.String,
        "token_outcome_name": pl.String,
        "_updated_at": pl.String,
        "maker_price": pl.Float64,
        "maker_usd": pl.Float64,
        "taker_asset": pl.String,
        "is_full_order": pl.String,
        "maker_side_corrected": pl.String,
        "taker_side_corrected": pl.String,
        "taker_price": pl.Float64,
        "taker_usd": pl.Float64,
    }
)

trades_df = pl.scan_csv(
    "test/test_sample_dataset/polymarket_trades_v2.csv", schema_overrides=trades_schema
)

agg_df = (
    trades_df.with_columns(
        pl.when(pl.col("is_full_order").eq("true"))
        .then(pl.col("taker_usd").neg())
        .otherwise(pl.col("taker_usd"))
        .alias("agg_test")
    )
    .group_by("tx_hash")
    .agg(pl.col("agg_test").sum())
)

sns.violinplot(data=agg_df.collect(), x="agg_test")
plt.suptitle("Analyzing taker_usd distribution")
plt.title("Checking the distribution of residuals after aggregated sum of taker_usd")
plt.savefig("test/test_sample_dataset/agg_test_violinplot.png")

# print(trades_df.head(10).collect())

# sanity checks
#
# check if maker_side_corrected equals taker_side_corrected for full orders
s = (
    trades_df.filter(pl.col("is_full_order").eq("true"))
    .with_columns(
        pl.col("maker_side_corrected")
        .eq(pl.col("taker_side_corrected"))
        .alias("maker_side_corrected_equals_taker_side_corrected")
    )
    .select(pl.col("maker_side_corrected_equals_taker_side_corrected"))
    .sum()
    .collect()
    .item()
)

invariant_log(
    s == 0,
    "maker_side_corrected equals taker_side_corrected for full orders",
    "maker_side_corrected does not equal taker_side_corrected for full orders",
)
