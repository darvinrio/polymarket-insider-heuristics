-- Leaderboard v5.2: trading_pnl / maker_rebate / net_realized_cashflow
-- Fix: total_volume 只含 BUY/SELL（不含 MERGE/REDEEM/SPLIT）
WITH
-- wash AS (
--     SELECT address
--     FROM dune.polymarket.dataset_potential_wash_traders
-- ),
cashflows AS (
    SELECT
        mt.maker AS address,
        CASE
            WHEN
                ABS(mt.amount - CAST(r.maker_amount_raw AS double)/1e6)
                =
                ABS(mt.amount - CAST(r.taker_amount_raw AS double)/1e6)
            THEN 'BUY'
            ELSE 'SELL'
    END AS action,
    mt.amount AS amount_usdc,
    mt.fee,
    mt.condition_id,
    'TRADE' AS source
    FROM polymarket_polygon.market_trades mt
    JOIN polymarket_polygon.market_trades_raw r
        ON mt.tx_hash = r.tx_hash
        AND mt.evt_index = r.evt_index
        AND mt.block_month = r.block_month
    WHERE mt.block_month >= DATE '2024-01-01'
    -- AND mt.maker NOT IN (SELECT address FROM wash)
    AND mt.maker != 0x4bfb41d5b3570defd03c39a9a4d8de6bd8b8982e
    AND mt.maker != 0xc5d563a36ae78145c45a50134d48a1215220f80a
    AND mt.maker != mt.taker

    UNION ALL
    SELECT
        CASE
            WHEN stakeholder = 0xd91e80cf2e7be2e162c6513ced06f1dd0da35296
            THEN evt_tx_from
            ELSE stakeholder
        END,
        'SPLIT',
        CAST(amount AS double)/1e6,
        0, conditionId, 'SPLIT'
    FROM polymarket_polygon.ctf_evt_positionsplit
    WHERE evt_block_time >= TIMESTAMP '2024-01-01'
        AND stakeholder != 0x4bfb41d5b3570defd03c39a9a4d8de6bd8b8982e
        -- AND (
        --     CASE
        --         WHEN stakeholder = 0xd91e80cf2e7be2e162c6513ced06f1dd0da35296
        --         THEN evt_tx_from
        --         ELSE stakeholder
        --     END
        -- ) NOT IN (SELECT address FROM wash)

    UNION ALL
    SELECT
        CASE
            WHEN stakeholder = 0xd91e80cf2e7be2e162c6513ced06f1dd0da35296
            THEN evt_tx_from
            ELSE stakeholder
        END,
        'MERGE',
        CAST(amount AS double)/1e6,
        0, conditionId, 'MERGE'
    FROM polymarket_polygon.ctf_evt_positionsmerge
    WHERE evt_block_time >= TIMESTAMP '2024-01-01'
        AND stakeholder != 0x4bfb41d5b3570defd03c39a9a4d8de6bd8b8982e
        -- AND (
        --     CASE
        --         WHEN stakeholder = 0xd91e80cf2e7be2e162c6513ced06f1dd0da35296
        --         THEN evt_tx_from
        --         ELSE stakeholder
        --     END
        -- ) NOT IN (SELECT address FROM wash)

    UNION ALL
    SELECT
        redeemer,
        'REDEEM',
        CAST(payout AS double)/1e6,
        0, conditionId, 'REDEEM'
    FROM polymarket_polygon.ctf_evt_payoutredemption
    WHERE evt_block_time >= TIMESTAMP '2024-01-01'
        AND CAST(payout AS double) > 0
        AND redeemer != 0xd91e80cf2e7be2e162c6513ced06f1dd0da35296
        -- AND redeemer NOT IN (SELECT address FROM wash)

    UNION ALL
    SELECT
        evt_tx_from,
        'REDEEM',
        CAST(payout AS double)/1e6,
        0, conditionId, 'REDEEM'
    FROM polymarket_polygon.ctf_evt_payoutredemption
    WHERE evt_block_time >= TIMESTAMP '2024-01-01'
        AND CAST(payout AS double) > 0
        AND redeemer = 0xd91e80cf2e7be2e162c6513ced06f1dd0da35296
        -- AND evt_tx_from NOT IN (SELECT address FROM wash)

    UNION ALL
    SELECT
        "to",
        'REBATE',
        CAST(refund AS double)/1e6,
        0, NULL, 'REBATE'
    FROM polymarket_polygon.feemodule_evt_feerefunded
    WHERE evt_block_time >= TIMESTAMP '2024-01-01'
        AND CAST(refund AS double) > 0
        -- AND "to" NOT IN (SELECT address FROM wash)

    UNION ALL
    SELECT
        "to",
        'REBATE',
        CAST(refund AS double)/1e6,
        0, NULL, 'REBATE'
    FROM polymarket_polygon.negriskfeemodule_evt_feerefunded
    WHERE evt_block_time >= TIMESTAMP '2024-01-01'
        AND CAST(refund AS double) > 0
        -- AND "to" NOT IN (SELECT address FROM wash)
),
rebate_totals AS (
  SELECT address, SUM(amount_usdc) AS maker_rebate_income
  FROM cashflows
  WHERE source = 'REBATE'
  GROUP BY address
),
addr_filter AS (
  SELECT address
  FROM cashflows
  WHERE action IN ('BUY','SPLIT')
  GROUP BY address
  HAVING SUM(amount_usdc) >= 100
),
per_market AS (
  SELECT
      cf.address, cf.condition_id,
    -- trading_volume: 只含 BUY/SELL
    SUM(CASE WHEN cf.action IN ('BUY','SELL') THEN cf.amount_usdc ELSE 0 END) AS trading_vol,
    SUM(CASE
        WHEN cf.action = 'SELL' THEN cf.amount_usdc - cf.fee
        WHEN cf.action IN ('MERGE','REDEEM') THEN cf.amount_usdc
        WHEN cf.action IN ('BUY','SPLIT') THEN -cf.amount_usdc
        ELSE 0
    END) AS pnl,
    CASE
        WHEN SUM(CASE
            WHEN cf.action = 'SELL' THEN cf.amount_usdc - cf.fee
            WHEN cf.action IN ('MERGE','REDEEM') THEN cf.amount_usdc
            WHEN cf.action IN ('BUY','SPLIT') THEN -cf.amount_usdc
            ELSE 0
            END
        ) > 0 THEN 'win'
        WHEN SUM(CASE
            WHEN cf.action = 'SELL' THEN cf.amount_usdc - cf.fee
            WHEN cf.action IN ('MERGE','REDEEM') THEN cf.amount_usdc
            WHEN cf.action IN ('BUY','SPLIT') THEN -cf.amount_usdc
            ELSE 0
            END
        ) < 0 THEN 'loss'
        ELSE 'breakeven'
    END AS result
  FROM cashflows cf JOIN addr_filter af ON cf.address = af.address
  WHERE cf.condition_id IS NOT NULL
  GROUP BY cf.address, cf.condition_id HAVING SUM(cf.amount_usdc) >= 1
),
profiles AS (
  SELECT
    p.address,
    SUM(p.trading_vol) AS trading_volume,
    SUM(p.pnl) AS trading_pnl,
    COALESCE(MAX(rt.maker_rebate_income), 0) AS maker_rebate_income,
    SUM(p.pnl) + COALESCE(MAX(rt.maker_rebate_income), 0) AS net_realized_cashflow,
    COUNT(DISTINCT p.condition_id) AS markets,
    COUNT(CASE WHEN p.result = 'win' THEN 1 END) AS wins,
    COUNT(CASE WHEN p.result = 'loss' THEN 1 END) AS losses,
    ROUND(
        CAST(COUNT(CASE WHEN p.result = 'win' THEN 1 END) AS double)
        /
        NULLIF(COUNT(CASE WHEN p.result IN ('win','loss') THEN 1 END), 0)
    , 3) AS win_rate,
    ROUND(
        CASE
            WHEN
                SUM(CASE WHEN p.result = 'loss' THEN ABS(p.pnl) END) > 0
            THEN
                SUM(CASE WHEN p.result = 'win' THEN p.pnl END)
                /
                SUM(CASE WHEN p.result = 'loss' THEN ABS(p.pnl) END)
            ELSE NULL
            END
    , 2) AS profit_factor
  FROM per_market p
    LEFT JOIN rebate_totals rt
        ON p.address = rt.address
  GROUP BY p.address
  -- HAVING COUNT(CASE WHEN p.result IN ('win','loss') THEN 1 END) >= {{min_resolved}}
)

SELECT
    ROW_NUMBER() OVER (ORDER BY trading_pnl DESC) AS rank, address,
    ROUND(trading_pnl, 2) AS trading_pnl,
    ROUND(maker_rebate_income, 2) AS maker_rebate_income,
    ROUND(net_realized_cashflow, 2) AS net_realized_cashflow,
    ROUND(trading_volume, 2) AS trading_volume,
    markets, wins, losses, win_rate, profit_factor
FROM profiles
ORDER BY trading_pnl DESC
-- LIMIT {{top_n}}
