with
trades as (
    select *,
        if(is_full_order, tx_hash, null) as tx_hash_full_order,
        if(is_full_order, null, tx_hash) as tx_hash_fill,
        if(is_full_order, null, maker_usd) as fill_size,
        if(is_full_order, maker_usd, null) as bet_size,
        -- ^ cause taker is maker in full order
        if(is_full_order, spread, null) as order_spread
    from query_7778683
    -- where true
    -- and taker not in (
    --     0x4bfb41d5b3570defd03c39a9a4d8de6bd8b8982e, -- ctf exchange v1
    --     0xc5d563a36ae78145c45a50134d48a1215220f80a  -- negrisk v1
    -- )
    -- and price <= 1
),
maker_stats as (
    select
        maker,
        sum(maker_usd) as total_filled_usd,
        count(tx_hash_fill) as maker_fills,
        approx_distinct(tx_hash_fill) as maker_trades,
        sum(shares) as shares_filled,
        -- approx_percentile(shares, [0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95]) as percentiles_maker_usd,
        avg(maker_usd) as avg_fill,
        max(maker_usd) as max_fill,
        min(maker_usd) as min_fill,
        min(block_time) as first_fill_time
        -- count(distinct condition_id) as maker_condition_ids,
        -- count(distinct polymarket_link) as maker_links
    from trades
    -- only limit fills
    where true
    and taker not in (
        0x4bfb41d5b3570defd03c39a9a4d8de6bd8b8982e, -- ctf exchange v1
        0xc5d563a36ae78145c45a50134d48a1215220f80a  -- negrisk v1
    )
    group by 1
),
taker_stats as (
    select
        if(is_full_order, maker, taker) as taker,
        sum(taker_usd) as total_taker_usd,
        sum(bet_size) as total_bet_size,
        count(tx_hash_fill) as taker_fills,
        count(tx_hash_full_order) as taker_trades,
        sum(shares) as taker_shares,
        -- approx_percentile(shares, [0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95]) as percentiles_taker_usd,
        avg(bet_size) as avg_bet_size,
        max(bet_size) as max_bet_size,
        min(bet_size) as min_bet_size,
        approx_percentile(bet_size, 0.5) as median_bet_size,
        approx_percentile(bet_size, 0.9) as p90_bet_size,
        stddev_pop(bet_size) as stddev_bet_size,
        avg(order_spread) as avg_spread,
        approx_percentile(order_spread, 0.5) as median_spread,
        approx_percentile(order_spread, 0.9) as p90_spread,
        stddev_pop(order_spread) as stddev_spread,
        min(block_time) as first_taker_trade_time,
        count(
            if(is_yield_farm_trade, tx_hash_full_order, null)
        ) as taker_yield_trades,
        count(
            if(is_notional_farm_trade, tx_hash_full_order, null)
        ) as taker_notional_farm_trades,
        sum(
            if(is_yield_farm_trade, taker_usd, 0)
        ) as taker_yield_vol,
        sum(
            if(is_notional_farm_trade, shares, 0)
        ) as taker_notional_farm_shares
        -- count(distinct condition_id) as taker_condition_ids,
        -- count(distinct polymarket_link) as taker_links
    from trades
    group by 1
),
user_joined as (
    select
        coalesce(m.maker, t.taker) as user,
        m.*,
        t.*,
        coalesce(total_filled_usd,0) + coalesce(total_taker_usd,0) as usd_vol,
        coalesce(maker_trades,0) + coalesce(taker_trades,0) as total_trades,
        coalesce(shares_filled,0) + coalesce(taker_shares,0) as total_shares
    from maker_stats m
        full join taker_stats t
            on m.maker = t.taker
)

select
    user,
    usd_vol,
    total_trades,
    coalesce(
        least(first_fill_time, first_taker_trade_time),
        first_fill_time,
        first_taker_trade_time
    ) as first_trade,

    -- maker stats
    total_filled_usd,
    maker_fills,
    maker_trades,
    shares_filled,
    avg_fill,
    max_fill,
    min_fill,
    first_fill_time,
    coalesce(cast(total_filled_usd as double)/nullif(usd_vol,0),0) as fill_vol_dominance,
    coalesce(cast(maker_trades as double)/nullif(total_trades,0),0) as maker_trades_dominance,

    -- taker stats
    total_taker_usd,
    total_bet_size,
    taker_trades,
    taker_shares,
    avg_bet_size,
    max_bet_size,
    min_bet_size,
    median_bet_size,
    p90_bet_size,
    stddev_bet_size,
    avg_spread,
    median_spread,
    p90_spread,
    first_taker_trade_time,

    coalesce(cast(total_taker_usd as double)/nullif(usd_vol,0),0) as taker_vol_dominance,
    coalesce(cast(taker_trades as double)/nullif(total_trades,0),0) as taker_trades_dominance,
    taker_yield_trades,
    taker_notional_farm_trades,
    taker_yield_vol,
    taker_notional_farm_shares,
    coalesce(cast(taker_yield_trades as double)/nullif(taker_trades,0),0) as taker_yield_trades_dominance,
    coalesce(cast(taker_notional_farm_trades as double)/nullif(taker_trades,0),0) as taker_notional_farm_trades_dominance,
    coalesce(cast(taker_yield_vol as double)/nullif(usd_vol,0),0) as taker_yield_vol_dominance,
    coalesce(cast(taker_notional_farm_shares as double)/nullif(total_shares,0),0) as taker_notional_farm_shares_dominance,
    coalesce(cast((taker_yield_trades + taker_notional_farm_trades) as double)/nullif(taker_trades,0),0) as non_directional_trade_dominance
from user_joined
where true
-- and total_trades > 100 and usd_vol > 10000
-- and user = 0xdb595e005ce61994f85df5cb7f6ab663804f0f16
-- order by non_directional_trade_dominance desc, total_trades desc
-- limit 10
