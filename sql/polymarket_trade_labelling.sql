-- https://dune.com/queries/7789265

with
trades as (
    select * from query_7778683
    -- focus only on full orders
    where taker in (
        0x4bfb41d5b3570defd03c39a9a4d8de6bd8b8982e, -- ctf exchange v1
        0xc5d563a36ae78145c45a50134d48a1215220f80a  -- negrisk v1
    )
    -- filter out inconsequential trades
    -- and not(is_yield_farm_trade)
    -- and not(is_notional_farm_trade)
),
user_stats as (
    select * from query_7743051
),
market_stats as (
    select * from query_7786298
),
labelling_trades as (
    select
        t.*,
        u.first_trade,
        if(
            u.first_trade > date'2025-11-20' and
            date_diff('hour', u.first_trade, t.block_time) <= 24,
            1, 0
        ) as fresh_wallet_trade,
        if(t.maker_usd > m.p90_bet_size, 1, 0) as market_betsize_anomaly,
        if(
            t.maker_usd > m.p90_bet_size,
            (maker_usd / m.p90_bet_size) - 1,
            0
        ) as market_betsize_anomaly_score,
        if(t.maker_usd > u.p90_bet_size, 1, 0) as user_betsize_anomaly,
        if(
            t.maker_usd > u.p90_bet_size,
            (maker_usd / u.p90_bet_size) - 1,
            0
        ) as user_betsize_anomaly_score,
        if(
            t.spread > m.p90_spread and m.p90_spread > 0 and t.spread > 1e-6,
            1, 0
        ) as market_spread_anomaly,
        if(
            t.spread > m.p90_spread and m.p90_spread > 0 and t.spread > 1e-6,
            (t.spread / m.p90_spread) - 1, 0
        ) as market_spread_anomaly_score,
        if(
            t.spread > u.p90_spread and u.p90_spread > 0 and t.spread > 1e-6,
            1, 0
        ) as user_spread_anomaly,
        if(
            t.spread > u.p90_spread and u.p90_spread > 0 and t.spread > 1e-6,
            (t.spread / u.p90_spread) - 1, 0
        ) as user_spread_anomaly_score,
        if(
            date_diff('hour', t.block_time, t.orders_end_time) <= 24
            and maker_price < 0.4
            and lower(t.final_outcome) = lower(t.maker_token_outcome),
            1, 0
        ) as contrarian_trade
    from trades t
        join user_stats u
            on t.maker = u.user
        join market_stats m
            on t.condition_id = m.condition_id
)

select *,
    (
        fresh_wallet_trade +
        market_betsize_anomaly +
        user_betsize_anomaly +
        market_spread_anomaly +
        user_spread_anomaly +
        contrarian_trade
    ) as sus_flags,
    (
        -- fresh_wallet_trade +
        market_betsize_anomaly_score +
        user_betsize_anomaly_score +
        market_spread_anomaly_score +
        user_spread_anomaly_score
        -- contrarian_trade
    ) as sus_score
from labelling_trades
where true
-- and maker = 0x67ebe6df2ebb84f64868f47c2209a0d30c4c7ed0

-- select * from trades
-- where true
-- and maker = 0xdb595e005ce61994f85df5cb7f6ab663804f0f16
-- and (
--     fresh_wallet_trade +
--     market_betsize_anomaly +
--     user_betsize_anomaly +
--     market_spread_anomaly +
--     user_spread_anomaly +
--     contrarian_trade
-- ) > 2
-- and fresh_wallet_trade
-- and block_time > date'2025-11-27'
-- limit 100
