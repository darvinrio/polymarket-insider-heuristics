with
user_stats as (
    select * from query_7743051
),
sus_score as (
    select
        maker,
        -- sum(maker_usd) as total_vol,
        -- count(*) as trades,
        sum(sus_score) as total_sus_score,
        count(if(sus_score>2, sus_score, null)) as sus_trades,
        sum(fresh_wallet_trade) as sum_fresh_wallet_trade,
        sum(market_betsize_anomaly) as sum_market_betsize_anomaly,
        sum(user_betsize_anomaly) as sum_user_betsize_anomaly,
        sum(market_spread_anomaly) as sum_market_spread_anomaly,
        sum(user_spread_anomaly) as sum_user_spread_anomaly,
        sum(contrarian_trade) as sum_contrarian_trade
    from query_7789265
    group by 1
),
combined_data as (
    select
        u.*,
        total_sus_score,
        sum_fresh_wallet_trade,
        sum_market_betsize_anomaly,
        sum_user_betsize_anomaly,
        sum_market_spread_anomaly,
        sum_user_spread_anomaly,
        sum_contrarian_trade
    from user_stats u
        join sus_score s
            on u.user = s.maker
            -- and s.total_sus_score > u.total_trades
            -- and s.sus_trades > 2
            and u.usd_vol > 10000
)

select
    count(*)
from combined_data


-- select *,
--     cast(total_sus_score as double)/trades as sus_ratio
-- from (
-- )
-- where total_sus_score > trades
-- and total_vol > 1000
