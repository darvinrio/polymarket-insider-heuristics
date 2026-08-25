import polars as pl

EVENTS_SCHEMA = {
    "block_time": pl.String,
    "evt_index": pl.Int64,
    "batch_evt_index": pl.Int64,
    "token_index": pl.Int64,
    "block_number": pl.Int64,
    "tx_hash": pl.String,
    "trader": pl.String,
    "counterparty": pl.String,
    "token_id": pl.String,
    "usd": pl.Decimal(scale=6),
    "shares_delta": pl.Decimal(scale=6),
    "shares_bought": pl.Decimal(scale=6),
    "shares_sold": pl.Decimal(scale=6),
    "usd_invested": pl.Decimal(scale=6),
    "usd_realized": pl.Decimal(scale=6),
    "trade_type": pl.String,
}

MARKETS_SCHEMA = {
    "token_id": pl.String,
    "question": pl.String,
    "event_market_name": pl.String,
    "event_market_id": pl.String,
    "condition_id": pl.String,
    "tags": pl.String,
    "neg_risk": pl.Boolean,
    "market_start_time": pl.String,
    "market_end_time": pl.String,
    "resolved_on_timestamp": pl.String,
    "orders_end_time": pl.String,
    "final_outcome": pl.String,
    "token_outcome": pl.String,
    "settlement_value": pl.Decimal(scale=6),
}
