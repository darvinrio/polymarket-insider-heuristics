-- https://dune.com/queries/7793332

with
user_stats as (
    select * from query_7743051
),
sus_score as (
    select
        maker,
        -- sum(maker_usd) as total_vol,
        -- count(*) as trades,
        sum(sus_flags) as sum_sus_flags,
        sum(sus_score) as total_sus_score,
        count(if(sus_score>0,sus_score, null)) as sus_scores_gt_0,
        approx_percentile(if(sus_score>0,sus_score, null), 0.5) as median_sus_scores_gt_0,
        count(if(sus_score>100,sus_score, null)) as sus_scores_gt_100,
        approx_percentile(if(sus_score>100,sus_score, null), 0.5) as median_sus_scores_gt_100,
        count(if(sus_score>2, sus_score, null)) as sus_trades,
        sum(fresh_wallet_trade) as sum_fresh_wallet_trades,
        sum(market_betsize_anomaly) as sum_market_betsize_anomaly,
        sum(market_betsize_anomaly_score) as sum_market_betsize_anomaly_score,
        sum(user_betsize_anomaly) as sum_user_betsize_anomaly,
        sum(user_betsize_anomaly_score) as sum_user_betsize_anomaly_score,
        sum(market_spread_anomaly) as sum_market_spread_anomaly,
        sum(market_spread_anomaly_score) as sum_market_spread_anomaly_score,
        sum(user_spread_anomaly) as sum_user_spread_anomaly,
        sum(user_spread_anomaly_score) as sum_user_spread_anomaly_score,
        sum(contrarian_trade) as sum_contrarian_trades
    from query_7789265
    group by 1
),
combined_data as (
    select
        u.*,
        sum_sus_flags,
        total_sus_score,
        sus_scores_gt_0,
        median_sus_scores_gt_0,
        sus_scores_gt_100,
        median_sus_scores_gt_100,
        sus_trades,
        sum_fresh_wallet_trades,
        sum_market_betsize_anomaly,
        sum_market_betsize_anomaly_score,
        sum_user_betsize_anomaly,
        sum_user_betsize_anomaly_score,
        sum_market_spread_anomaly,
        sum_market_spread_anomaly_score,
        sum_user_spread_anomaly,
        sum_user_spread_anomaly_score,
        sum_contrarian_trades
    from user_stats u
        join sus_score s
            on u.user = s.maker
            -- and s.sum_sus_flags > (u.total_trades/2)
            -- and s.sus_trades > 2
            and u.usd_vol > 10000
)

select *
from combined_data
-- where total_sus_score > 100


-- select *
-- from combined_data
--     cast(total_sus_score as double)/trades as sus_ratio
-- from (
-- )
-- where total_sus_score > trades
-- and total_vol > 1000
