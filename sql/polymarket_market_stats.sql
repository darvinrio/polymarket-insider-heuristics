with
trades as (
    select
        -- *
        maker,
        taker,
        price,
        amount,
        shares,
        token_outcome,
        condition_id,
        polymarket_link,
        question,
        asset_id
    from polymarket_polygon.market_trades
    where block_month >= date'2025-11-01'
    and block_month < date'2026-04-28'
    and taker not in (
        0x4bfb41d5b3570defd03c39a9a4d8de6bd8b8982e, -- ctf exchange v1
        0xc5d563a36ae78145c45a50134d48a1215220f80a  -- negrisk v1
    )
    and price <= 1
),
market_aggregation as (

    select -- *
        -- polymarket_link,
        condition_id,
        -- question,
        -- token_outcome,
        -- count(distinct condition_id),
        -- question,
        count(*) as trades,
        sum(shares) as share_vol,
        floor(log10(
            sum(shares)
        )) as share_log_floor
    from trades
    group by 1
),
market_vol_dist as (
    select
        pow(10, share_log_floor+1) as vol_bucket,
        count(*) as markets,
        sum(share_vol) as vol,
        sum(trades) as trades,
        sum(count(*) ) over (order by share_log_floor) as cum_markets,
        sum(sum(trades)) over (order by share_log_floor) as cum_trades,
        sum(sum(share_vol)) over (order by share_log_floor) as cum_vol
    from market_aggregation
    group by 1, share_log_floor
    order by 2 desc
)

select *,
    cast(cum_markets as double)/max(cum_markets) over() as percent_markets,
    cast(cum_trades as double)/max(cum_trades) over() as percent_trades,
    cum_vol/max(cum_vol) over() as percent_vol
from market_vol_dist

-- select
--     approx_percentile(share_vol, [0.1, 0.25, 0.5, 0.75]) as percentile
-- from market_aggregation
-- limit 100

-- quantiles - [0.1, 0.25, 0.5, 0.75]
-- 130.56529416507786, 488.5198512070318, 3942.520314372647, 30455.52222941329
