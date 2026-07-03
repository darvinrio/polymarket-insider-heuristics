-- https://dune.com/queries/7868235

WITH
insiders as (
    select * from (
        values
        (0xe56526b27b96f009b31ddb46558a134047bfce48,'zachxbt'),
        (0x054ec2f0ccfdae941886a3ed306635068c716639,'zachxbt'),
        (0x6d6affce1ed04a0e9611484daf1cef5cbcf3fb40,'zachxbt'),
        (0x581f34349babaf03b2d3c8f5f60cf44ffbe19a3a,'zachxbt'),
        (0x5e524f43357198fa815e6766f02fe686b444b064,'zachxbt'),
        (0x572c8005aa033237175f16de725969b044cd0383,'zachxbt'),
        (0xaab29084bcc42daff9e11b4a5a4cc55cda3eb306,'zachxbt'),
        (0x98a96619e482700e83e8486e4f3727dba17f5381,'zachxbt'),
        (0xeeff2d748ad5efcfbbb3c8858f608d6b6321a398,'zachxbt'),
        (0xd9eab53eaba81333045da5bd84ce6c833f721e89,'zachxbt'),
        (0xff55beaf369387d7748a31213699a51f1ca8b877,'zachxbt'),
        (0xdde15ebd95330ce69136dc0ccd810d22382e02c5,'us_iran'),
        (0x56efadc9defe5b7a21af751e0d026f2cf54136db,'us_iran'),
        (0x38745db27f7360a287f6ca3c9b6a6a9c76149801,'us_iran'),
        (0x1caa6a7ad0c6916aef7b67946de2e57ad24846a0,'us_iran'),
        (0xa4eb52229991c074bc560f825bf2776d77acd010,'us_iran'),
        (0x3811e09bb2fa30aff16d9be28c09ee9bba478f61,'us_iran'),
        (0x06d38e8941afa9d90551cc8c8f1a705fd9b159aa,'us_iran'),
        (0x438a83235d1284346283cca70dfd3333595062e5,'us_iran'),
        (0x47dcc568e33970cfd99d0924300195d2d8f24342,'us_iran'),
        (0x75f3f61e4d0686f18d4e2f3a38785642a6d5a0d0,'us_iran'),
        (0x031d98aa60916870a6b90ad5bd635ec5936277e1,'us_iran'),
        (0x43886f07460ab4fd9a54b569e8aedc0df47be9a1,'us_iran'),
        (0x9aec7caebac3baa4078f2b2c27552910a6b09ecd,'us_iran'),
        (0xa25c6a3a28c922f6fc8322a76d209f943b026430,'us_iran'),
        (0x0e4530e02a589879b5da57b5ba50a711ed555b3f,'us_iran'),
        (0x25000eb121dab875bed95f94d3d8d485f5c1e812,'us_iran'),
        (0xee50a31c3f5a7c77824b12a941a54388a2827ed6,'google'),
        (0x31a56e9E690c621eD21De08Cb559e9524Cdb8eD9,'maduro'),
        (0xa72DB1749e9AC2379D49A3c12708325ED17FeBd4,'maduro'),
        (0x6baf05d193692bb208d616709e27442c910a94c5,'maduro')
    ) as t(wallet, label)
),
trades AS (
    SELECT
        *,
        if(lower(maker_token_outcome) = lower(final_outcome), 1, 0) as is_correct_outcome,
        least(market_betsize_anomaly_score, 100) as market_betsize_anomaly_score_2,
        least(user_betsize_anomaly_score, 50) as user_betsize_anomaly_score_2,
        least(market_spread_anomaly_score, 100) as market_spread_anomaly_score_2,
        least(user_spread_anomaly_score, 50) as user_spread_anomaly_score_2,
        fresh_wallet_trade * 25 as fresh_wallet_trade_2,
        contrarian_trade * 75 as contrarian_trade_2
    FROM dune.maybeyonas.result_polymarket_sus_trades
),
new_score as (
    select *,
        is_correct_outcome * (
            market_betsize_anomaly_score_2 +
            user_betsize_anomaly_score_2 +
            market_spread_anomaly_score_2 +
            user_spread_anomaly_score_2 +
            fresh_wallet_trade_2 +
            contrarian_trade_2
        ) as total_score_2
    from trades
),
agg_scores as (
    select
        maker as trader,
        sum(total_score_2) as total_score,
        sum(maker_usd) as total_volume,
        approx_percentile(total_score_2, 0.99) as top_percentile,
        count(*) as trade_count
    from new_score
    group by 1
)

select
    a.*,
    dense_rank() over(order by a.top_percentile desc) as wallet_rank,
    i.label
from agg_scores a
    left join insiders i
        on a.trader = i.wallet
where total_volume > 1000
order by 2 desc
