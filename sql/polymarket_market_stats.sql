-- https://dune.com/queries/7786298

with
trades as (
    select *,
        -- for stats
        if(is_full_order, tx_hash, null) as tx_hash_full_order,
        if(is_full_order, null, tx_hash) as tx_hash_fill,
        if(is_full_order, null, maker_usd) as fill_size,
        if(is_full_order, maker_usd, null) as bet_size,
        -- ^ cause taker is maker in full order
        if(is_full_order and spread > 0, spread, null) as order_spread
    from query_7778683
    where true
    -- filter out inconsequential trades
    and not(is_yield_farm_trade)
    and not(is_notional_farm_trade)
    -- and taker not in (
    --     0x4bfb41d5b3570defd03c39a9a4d8de6bd8b8982e, -- ctf exchange v1
    --     0xc5d563a36ae78145c45a50134d48a1215220f80a  -- negrisk v1
    -- )
    -- and price <= 1
),
market_stats as (
    select
        condition_id,
        event_market_name,
        market_start_time,
        market_end_time,
        resolved_on_timestamp,
        final_outcome,

        count(tx_hash_full_order) as trades,
        count(tx_hash_fill) as fills,
        sum(fill_size) as maker_vol,
        avg(fill_size) as avg_fill_size,
        approx_percentile(fill_size, 0.5) as median_fill_size,
        approx_percentile(fill_size, 0.9) as p90_fill_size,
        approx_percentile(fill_size, 0.9) - approx_percentile(fill_size, 0.5) as p90_p50_range_fill_size,
        stddev_pop(fill_size) as stddev_fill_size,
        sum(bet_size) as taker_vol,
        avg(bet_size) as avg_bet_size,
        approx_percentile(bet_size, 0.5) as median_bet_size,
        approx_percentile(bet_size, 0.9) as p90_bet_size,
        approx_percentile(bet_size, 0.9) - approx_percentile(bet_size, 0.5) as p90_p50_range_bet_size,
        stddev_pop(bet_size) as stddev_bet_size,
        avg(order_spread) as avg_spread,
        approx_percentile(order_spread, 0.5) as median_spread,
        approx_percentile(order_spread , 0.9) as p90_spread,
        approx_percentile(order_spread, 0.9) - approx_percentile(order_spread, 0.5) as p90_p50_range_spread,
        stddev_pop(order_spread) as stddev_spread
        -- approx_percentile(shares, [0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95]) as percentiles_maker_usd,
    from trades
    group by 1,2,3,4,5,6
)
select
    condition_id,
    event_market_name,
    market_start_time,
    market_end_time,
    resolved_on_timestamp,
    final_outcome,
    trades,
    fills,
    maker_vol,
    avg_fill_size,
    median_fill_size,
    p90_fill_size,
    p90_p50_range_fill_size,
    stddev_fill_size,
    taker_vol,
    avg_bet_size,
    median_bet_size,
    p90_bet_size,
    p90_p50_range_bet_size,
    stddev_bet_size,
    avg_spread,
    median_spread,
    p90_spread,
    p90_p50_range_spread,
    stddev_spread
from market_stats
-- where condition_id = 0x8da87130e69d35b9dc413374209b4aa1cc858d0f4727098a456b707eac4be007
-- limit 10
