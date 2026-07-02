-- https://dune.com/queries/7778683

with
short_list_markets as (
    select distinct
        -- *,
        from_hex(condition_id) as condition_id,
        tags,
        from_iso8601_timestamp(market_start_time) as market_start_time,
        from_iso8601_timestamp(market_end_time) as market_end_time,
        resolved_on_timestamp,
        outcome
    from polymarket_polygon.market_details
    where true
    and from_iso8601_timestamp(market_start_time) > date'2025-11-01'
    and resolved_on_timestamp < date'2026-04-28'
    -- and resolved_on_timestamp < date'2025-12-01'
    and cardinality(array_intersect(
        split(tags, ', '),
        [
            'Crypto Prices', 'Up or Down',
            'Esports', 'Recurring',
            'Games', 'Sports',
            'Tweet Markets'
        ]
    )) = 0
),
trades_level_1 as (
    select t.*,
        s.tags,
        s.market_start_time,
        s.market_end_time,
        s.resolved_on_timestamp,
        s.outcome as final_outcome,
        price as maker_price,
        amount as maker_usd,
        last_value(asset_id) over(
            partition by tx_hash
            order by evt_index
            rows between unbounded preceding and unbounded following
        ) as taker_asset,
        last_value(token_outcome) over(
            partition by tx_hash
            order by evt_index
            rows between unbounded preceding and unbounded following
        ) as taker_token_outcome,
        case when taker=contract_address
            then true
            else false
        end as is_full_order,
        coalesce(
            least(
                resolved_on_timestamp,
                market_end_time
            ),
            resolved_on_timestamp,
            market_end_time
        ) as orders_end_time
    from polymarket_polygon.market_trades t
        join short_list_markets s
            on t.condition_id = s.condition_id
    where true
        -- and block_month >= date'2024-08-01'
        and block_month >= date'2025-11-01'
        and block_month <= date'2026-05-01'
        -- and block_month < date'2025-12-01'
        and contract_version = 'v1'
        -- and condition_id in (select condition_id from short_list_markets)
        -- and block_month <= date'2024-08-01'
        -- and block_time >= date'2024-08-18'
        -- and block_time <= date'2024-08-20'
        -- and block_number = 60785839
        -- and tx_hash in (
        --     0x4fce56dff16a86e8c55e04ebb9406026553e11f5236e7210b7b51803f093dc76,
        --     0x12ded42a9e2384d12053326cb167fdcaf20d6bc8139f518e5dd689a3ace2dce5,
        --     0x000850bd7a62320e9d9c665fd7b0112c75743000d6646f38b413628893febda1
        -- )
),
trades_level_2 as (
    select
        *,
        maker_side as maker_side_corrected,
        case when asset_id = taker_asset
            then taker_side
            else
                case
                    when taker_side = 'SELL' then 'BUY'
                    when taker_side = 'BUY' then 'SELL'
                end
        end as taker_side_corrected,
        case when asset_id != taker_asset
            then 1-maker_price
            else maker_price
        end as taker_price
    from trades_level_1
),
trades_level_3 as (
    select
        *,
        shares*taker_price as taker_usd,

        case when is_full_order
            then min(taker_price) over(
                partition by tx_hash
                rows between unbounded preceding and unbounded following
            )
            else taker_price
        end as min_taker_price,

        case when is_full_order
            then max(taker_price) over(
                partition by tx_hash
                rows between unbounded preceding and unbounded following
            )
            else taker_price
        end as max_taker_price
    from trades_level_2
)

select
    block_number,
    block_time,
    tx_hash,
    evt_index,
    -- contract_address,
    condition_id,
    event_market_name,
    question,
    polymarket_link,
    tags,
    market_start_time,
    market_end_time,
    orders_end_time,
    resolved_on_timestamp,
    final_outcome,
    neg_risk,
    shares,
    builder,
    metadata,
    unique_key,
    is_full_order,
    maker,
    taker,
    token_outcome as maker_token_outcome,
    asset_id as maker_asset,
    maker_side_corrected,
    maker_price,
    maker_usd,
    taker_token_outcome,
    taker_asset,
    taker_side_corrected,
    taker_price,
    taker_usd,
    max_taker_price,
    min_taker_price,
    round(max_taker_price-min_taker_price, 6) as spread,
    case when taker_price > 0.95
        and lower(final_outcome) = lower(taker_token_outcome)
        and date_diff('hour', block_time, orders_end_time) <= 48
    then True
    else False end as is_yield_farm_trade,
    case when taker_price < 0.05
        and lower(final_outcome) != lower(taker_token_outcome)
        and date_diff('hour', block_time, orders_end_time) <= 48
    then True
    else False end as is_notional_farm_trade
from trades_level_3
-- limit 10

-- some sample txs:
-- 0x000850bd7a62320e9d9c665fd7b0112c75743000d6646f38b413628893febda1
-- 0x4fce56dff16a86e8c55e04ebb9406026553e11f5236e7210b7b51803f093dc76
