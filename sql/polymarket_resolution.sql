with
-- short_list_wallets as (
--     select * from dune.pyor_xyz.dataset_polymarket_sus_score_test
-- ),
filter_wallets as (
    select * from (
        values
        (0xe3f18acc55091e2c48d883fc8c8413319d4ab7b0), -- fee module
        (0xd4aa6f8e91cfea29b66a48ebff523aafbdbbd40c), -- fee main
        (0xf21a25DD01ccA63A96adF862F4002d1A186DecB2), -- fee old
        (0x525e4001f6DaD9406dFd84f3331D2B9b95c40b73), -- negRisk fee
        (0x78769D50Be1763ed1CA0D5E878D93f05aabff29e), -- negrisk fee old
        (0xb768891e3130f6df18214ac804d4db76c2c37730), -- negrisk fee new
        (0x4bfb41d5b3570defd03c39a9a4d8de6bd8b8982e), -- ctf exchange v1
        (0x4D97DCd97eC945f40cF65F87097ACe5EA0476045), -- ctf
        (0xc5d563a36ae78145c45a50134d48a1215220f80a), -- negrisk v1
        (0xd91e80cf2e7be2e162c6513ced06f1dd0da35296), -- negrisk adapter
        (0x3A3BD7bb9528E159577F7C2e685CC81A765002E2), -- wcol
        (0x05cD9922A5d37faE921Fc5Dee280A9dBc4C3b393), -- auto redemption
        (0xa5ef39c3d3e10d0b270233af41cac69796b12966), -- negrisk burn
        (0xAdA100Db00Ca00073811820692005400218FcE1f), -- ctf collateral adapter
        (0xadA2005600Dec949baf300f4C6120000bDB6eAab), -- negrisk collateral adapter

        -- v2
        (0xE111180000d2663C0091e4f400237545B87B996B), -- v2 ctf
        (0xe2222d279d744050d28e00520010520000310F59), -- v2 negrisk
        (0xa1200000d0002264C9a1698e001292D00E1b00af), -- auto redemption
        (0xADa100874d00e3331D00F2007a9c336a65009718), -- ctf collateral adapter
        (0xAdA200001000ef00D07553cEE7006808F895c6F1), -- neg risk collateral adapter

        -- combos
        (0x006F54F7f9A22e0000CC2AB60031000000ae9fEF), -- PositionManager
    	(0x1000008dD9001B968442c1000017eaE6E0dA00Ba), -- BinaryModule
    	(0x200000900045e3B6259600682756002200028933), -- NegRiskModule
    	(0x30000034706C7d8e12009DAB006Be20000c031A8), -- CombinatorialModule
    	(0xe3333700cA9d93003F00f0F71f8515005F6c00Aa), -- Exchange
    	(0xa1200000d0002264C9a1698e001292D00E1b00af), -- AutoRedeemer

        (0x0000000000000000000000000000000000000000)
    ) as v(wallet)
),
short_list_markets as (
    select distinct
        -- *,
        token_id,
        question,
        event_market_name,
        from_hex(condition_id) as condition_id,
        tags,
        neg_risk,
        market_start_time,
        market_end_time,
        resolved_on_timestamp,
        least(
            resolved_on_timestamp,
            market_end_time
        ) as orders_end_time,
        outcome as final_outcome,
        token_outcome,
        settlement_value
    from polymarket_polygon.market_details
    where true
        and market_start_time >= date'2026-05-01'
        and resolved_on_timestamp < date'2026-08-01'
        -- and resolved_on_timestamp < date'2025-12-01'
        and cardinality(array_intersect(
            tags,
            [
                'Crypto Prices', 'Up or Down',
                'Esports', 'Recurring',
                'Games', 'Sports',
                'Tweet Markets'
            ]
        )) = 0
),
trades_level_1 as (
    select
        t.*,
        s.tags,
        s.market_start_time,
        s.market_end_time,
        s.resolved_on_timestamp,
        s.final_outcome,
        settlement_value,
        price as maker_price,
        amount as maker_usd,
        last_value(asset_id) over(
            partition by tx_hash
            order by evt_index
            rows between unbounded preceding and unbounded following
        ) as taker_asset,
        last_value(t.token_outcome) over(
            partition by tx_hash
            order by evt_index
            rows between unbounded preceding and unbounded following
        ) as taker_token_outcome,
        case when taker=contract_address
            then true
            else false
        end as is_full_order,
        s.orders_end_time
    from polymarket_polygon.market_trades t
        join short_list_markets s
            on t.condition_id = s.condition_id
            and t.asset_id = s.token_id
    where true
        -- and block_month >= date'2024-08-01'
        and block_month >= date'2026-05-01'
        and block_month < date'2026-08-01'
        -- and block_month < date'2025-12-01'
        and contract_version = 'v1'
        -- and t.maker in (select maker from short_list_wallets)
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
),
trades_level_4 as (
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
        settlement_value,
        cast(neg_risk as boolean) as neg_risk,
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
        round(max_taker_price-min_taker_price, 6) as spread
        -- This is redundant and incorrect
        -- case when taker_price > 0.95
        --     and lower(final_outcome) = lower(taker_token_outcome)
        --     and date_diff('hour', block_time, orders_end_time) <= 24
        -- then True
        -- else False end as is_yield_farm_trade,
        -- case when taker_price < 0.05
        --     and lower(final_outcome) != lower(taker_token_outcome)
        --     and date_diff('hour', block_time, orders_end_time) <= 24
        -- then True
        -- else False end as is_notional_farm_trade
    from trades_level_3
),
batch_transfers as (
    select
        evt_block_time,
        evt_block_number,
        evt_index,
        token_index,
        evt_tx_hash,
        operator,
        "from" as sender,
        "to" as recipient,
        u.token_id,
        u.shares_raw/1e6 as shares,
        cardinality(b.ids) as ids_count,

        s.question,
        s.event_market_name,
        s.final_outcome,
        s.token_outcome,
        s.condition_id,
        s.neg_risk,
        s.market_start_time,
        s.market_end_time,
        s.orders_end_time,
        s.settlement_value
    from polymarket_polygon.ctf_evt_transferbatch b
        cross join unnest(b.ids, b."values") with ordinality as u(token_id, shares_raw, token_index)
        join short_list_markets s
            on u.token_id = s.token_id
    where true
    and evt_block_date >= date'2026-05-01'
    and evt_block_date < date'2026-08-01'
    -- and evt_block_date < date'2025-12-01'
    and (
        -- split -> mint to contract, then transfer from contract
        "to" not in (
            0x4bfb41d5b3570defd03c39a9a4d8de6bd8b8982e, -- ctf exchange v1
            0xc5d563a36ae78145c45a50134d48a1215220f80a  -- negrisk exchange v1
            -- 0xd91e80cf2e7be2e162c6513ced06f1dd0da35296 -- negrisk adapter
        )
    )
    -- and (
    --     "from" in (select maker from short_list_wallets)
    --     or
    --     "to" in (select maker from short_list_wallets)
    -- )
),
stray_batch_transfers as (
    select
        evt_block_time,
        evt_block_number,
        evt_index,
        evt_tx_hash,
        operator,
        sender,
        recipient,
        token_id,
        shares,
        ids_count,

        question,
        event_market_name,
        final_outcome,
        token_outcome,
        condition_id,
        neg_risk,
        market_start_time,
        market_end_time,
        orders_end_time,
        settlement_value
    from batch_transfers b
    where true
    and operator not in (select wallet from filter_wallets)
    and sender not in (select wallet from filter_wallets)
    and recipient not in (select wallet from filter_wallets)
    -- and (
    --     sender in (select maker from short_list_wallets)
    --     or
    --     recipient in (select maker from short_list_wallets)
    -- )
),
single_transfers as (
    select
        evt_block_time,
        evt_block_number,
        evt_index,
        evt_tx_hash,
        operator,
        "from" as sender,
        "to" as recipient,
        b.id as token_id,
        b.value/1e6 as shares,
        1 as ids_count,

        s.question,
        s.event_market_name,
        s.final_outcome,
        s.token_outcome,
        s.condition_id,
        s.neg_risk,
        s.market_start_time,
        s.market_end_time,
        s.orders_end_time,
        s.settlement_value
    from polymarket_polygon.ctf_evt_transfersingle b
        join short_list_markets s
            on b.id = s.token_id
    where true
    and evt_block_date >= date'2026-05-01'
    and evt_block_date < date'2026-08-01'
    -- and evt_block_date < date'2025-12-01'
    and operator not in (select wallet from filter_wallets)
    and "to" not in (select wallet from filter_wallets)
    and "from" not in (select wallet from filter_wallets)
    -- and (
    --     "from" in (select maker from short_list_wallets)
    --     or
    --     "to" in (select maker from short_list_wallets)
    -- )
),
all_single_transfers as (
    select * from single_transfers
    union all
    select * from stray_batch_transfers
),
splits as (
    select
        p.evt_block_time,
        p.evt_block_number,
        p.evt_index,
        b.token_index,
        p.evt_tx_hash,
        b.condition_id,
        p.amount,
        b.recipient as trader,
        b.token_id,
        b.shares,
        'split' as trade_type,
        b.question,
        b.event_market_name,
        b.final_outcome,
        b.token_outcome,
        -- b.condition_id,
        b.neg_risk,
        b.market_start_time,
        b.market_end_time,
        b.orders_end_time,
        b.settlement_value
    from polymarket_polygon.ctf_evt_positionsplit p
        join batch_transfers b
            on p.evt_tx_hash = b.evt_tx_hash
            and (
                (
                    p.evt_index + 1 = b.evt_index -- negrisk
                    and
                    b.sender = 0xd91e80cf2e7be2e162c6513ced06f1dd0da35296 -- negrisk adapter
                )
                or
                (
                    p.evt_index - 1 = b.evt_index -- ctf
                    and
                    b.sender != 0xd91e80cf2e7be2e162c6513ced06f1dd0da35296
                )
            )
    where true
    and evt_block_date >= date'2025-10-01'
    and evt_block_date <= date'2026-05-01'
    -- and evt_block_date < date'2025-12-01'
    -- and b.recipient in (select maker from short_list_wallets)
),
merges as (
    select
        p.evt_block_time,
        p.evt_block_number,
        p.evt_index,
        b.token_index,
        p.evt_tx_hash,
        b.condition_id,
        p.amount,
        b.sender as trader,
        b.token_id,
        b.shares as shares,
        'merge' as trade_type,
        b.question,
        b.event_market_name,
        b.final_outcome,
        b.token_outcome,
        -- b.condition_id,
        b.neg_risk,
        b.market_start_time,
        b.market_end_time,
        b.orders_end_time,
        b.settlement_value
    from polymarket_polygon.ctf_evt_positionsmerge p
        join batch_transfers b
            on p.evt_tx_hash = b.evt_tx_hash
            and (
                (
                    p.evt_index = b.evt_index + 2 -- ctf
                    and
                    b.recipient != 0xd91e80cf2e7be2e162c6513ced06f1dd0da35296
                )
                or
                (
                    p.evt_index = b.evt_index + 3 -- negrisk
                    and
                    b.recipient = 0xd91e80cf2e7be2e162c6513ced06f1dd0da35296 -- negrisk adapter
                )
            )
    where true
    and evt_block_date >= date'2026-05-01'
    and evt_block_date < date'2026-08-01'
    -- and evt_block_date < date'2025-12-01'
    -- and b.recipient in (select maker from short_list_wallets)
),
converts_to_yes as (
    select
        p.evt_block_time,
        p.evt_block_number,
        p.evt_index,
        b.token_index,
        p.evt_tx_hash,
        -- p.conditionId as condition_id,
        b.condition_id,
        p.amount,
        b.recipient as trader,
        b.token_id,
        b.shares as shares,
        1 as ids_count,
        'convert_to_yes' as trade_type,
        b.question,
        b.event_market_name,
        b.final_outcome,
        b.token_outcome,
        -- b.condition_id,
        b.neg_risk,
        b.market_start_time,
        b.market_end_time,
        b.orders_end_time,
        b.settlement_value
    from polymarket_polygon.negriskadapter_evt_positionsconverted p
        join batch_transfers b
            on p.evt_tx_hash = b.evt_tx_hash
            and p.evt_index = b.evt_index + 1
            -- and b.operator = 0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296 -- not necessary imo
            and b.recipient = p.stakeholder
    where true
    and evt_block_date >= date'2026-05-01'
    and evt_block_date < date'2026-08-01'
    -- and evt_block_date < date'2025-12-01'
    -- and b.recipient in (select maker from short_list_wallets)
),
converts_from_no as (
    select
        p.evt_block_time,
        p.evt_block_number,
        p.evt_index,
        b.token_index,
        p.evt_tx_hash,
        -- p.conditionId as condition_id,
        b.condition_id,
        p.amount,
        b.sender as trader,
        b.token_id,
        - b.shares as shares,
        ids_count,
        'convert_from_no' as trade_type,
        b.question,
        b.event_market_name,
        b.final_outcome,
        b.token_outcome,
        -- b.condition_id,
        b.neg_risk,
        b.market_start_time,
        b.market_end_time,
        b.orders_end_time,
        b.settlement_value
    from polymarket_polygon.negriskadapter_evt_positionsconverted p
        join batch_transfers b
            on p.evt_tx_hash = b.evt_tx_hash
            and b.operator = 0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296
            and b.sender = p.stakeholder
            -- b.evt_index + 3 <= p.evt_index <= b.evt_index + 6
            and p.evt_index >= b.evt_index + 3
            and p.evt_index <= b.evt_index + 6
            and p.evt_index > b.evt_index
    where true
    and evt_block_date >= date'2026-05-01'
    and evt_block_date < date'2026-08-01'
    -- and evt_block_date < date'2025-12-01'
    -- and b.sender in (select maker from short_list_wallets)
),
converts as (
    select *
    from converts_to_yes
    union all
    select *
    from converts_from_no
),
trade_deltas as (
    -- one can only include maker since
    -- the taker orders are wrapped in a final event
    -- with the taker as maker and exchange as taker
    select
        block_time,
        evt_index,
        0 as token_index,
        block_number,
        tx_hash,
        maker,
        maker_asset,
        maker_token_outcome,
        settlement_value,
        condition_id,
        neg_risk,

        question,
        final_outcome,
        market_start_time,
        market_end_time,
        orders_end_time,

        event_market_name,
        maker_usd,
        case
            when maker_side_corrected = 'BUY'
            then shares
            when maker_side_corrected = 'SELL'
            then -shares
        end as shares_delta,
        case
            when maker_side_corrected = 'BUY'
            then shares
            else 0
        end as shares_bought,
        case
            when maker_side_corrected = 'SELL'
            then shares
            else 0
        end as shares_sold,
        case
            when maker_side_corrected = 'BUY'
            then maker_usd
            else 0
        end as usd_invested,
        case
            when maker_side_corrected = 'SELL'
            then maker_usd
            else 0
        end as usd_realized
    from trades_level_4
    where true
),
merges_splits_converts as (
    select
        evt_block_time as block_time,
        evt_index,
        token_index,
        evt_block_number as block_number,
        evt_tx_hash as tx_hash,
        trader,
        token_id,
        token_outcome as maker_token_outcome,
        settlement_value,
        condition_id,
        neg_risk,
        question,
        final_outcome,
        market_start_time,
        market_end_time,
        orders_end_time,
        event_market_name,
        shares/2 as usd,
        -shares as shares_delta,
        0 as shares_bought,
        shares as shares_sold,
        0 as usd_invested,
        shares/2 as usd_realized,
        trade_type
    from merges
    union all
    select
        evt_block_time as block_time,
        evt_index,
        token_index,
        evt_block_number as block_number,
        evt_tx_hash as tx_hash,
        trader,
        token_id,
        token_outcome as maker_token_outcome,
        settlement_value,
        condition_id,
        neg_risk,
        question,
        final_outcome,
        market_start_time,
        market_end_time,
        orders_end_time,
        event_market_name,
        shares/2 as usd,
        shares as shares_delta,
        shares as shares_bought,
        0 as shares_sold,
        shares/2 as usd_invested,
        0 as usd_realized,
        trade_type
    from splits
    union all
    select
        evt_block_time as block_time,
        evt_index,
        token_index,
        evt_block_number as block_number,
        evt_tx_hash as tx_hash,
        trader,
        token_id,
        token_outcome as maker_token_outcome,
        settlement_value,
        condition_id,
        neg_risk,
        question,
        final_outcome,
        market_start_time,
        market_end_time,
        orders_end_time,
        event_market_name,
        (ids_count - 1) * abs(shares) / ids_count  as usd,
        shares as shares_delta,
        shares as shares_bought,
        0 as shares_sold,
        0 as usd_invested,
        (ids_count - 1) * abs(shares) / ids_count as usd_realized,
        trade_type
    from converts
),
single_transfer_deltas as (
    select
        evt_block_time as block_time,
        evt_index,
        0 as token_index,
        evt_block_number as block_number,
        evt_tx_hash as tx_hash,
        sender as trader,
        token_id,
        token_outcome as maker_token_outcome,
        settlement_value,
        condition_id,
        neg_risk,
        question,
        final_outcome,
        market_start_time,
        market_end_time,
        orders_end_time,
        event_market_name,
        0 as usd,
        -shares as shares_delta,
        0 as shares_bought,
        0 as shares_sold,
        0 as usd_invested,
        0 as usd_realized,
        'transfer_out' as trade_type
    from all_single_transfers
    union all

    select
        evt_block_time as block_time,
        evt_index,
        0 as token_index,
        evt_block_number as block_number,
        evt_tx_hash as tx_hash,
        recipient as trader,
        token_id,
        token_outcome as maker_token_outcome,
        settlement_value,
        condition_id,
        neg_risk,
        question,
        final_outcome,
        market_start_time,
        market_end_time,
        orders_end_time,
        event_market_name,
        0 as usd,
        shares as shares_delta,
        0 as shares_bought,
        0 as shares_sold,
        0 as usd_invested,
        0 as usd_realized,
        'transfer_in' as trade_type
    from all_single_transfers
),
non_trade_txs as (
    select *
    from merges_splits_converts
    union all
    select *
    from single_transfer_deltas
),
audit_txs as (
    select *
    from non_trade_txs
    where tx_hash not in (select tx_hash from trades_level_1)
    union all
    select *,
        'clob' as trade_type
    from trade_deltas
),
audit_aggr as (
    select
        trader,
        token_id,
        question,
        event_market_name,
        maker_token_outcome,
        settlement_value,
        final_outcome,
        condition_id,
        neg_risk,
        market_start_time,
        market_end_time,
        orders_end_time,
        sum(if(trade_type='clob', shares_delta, 0)) as shares_delta,
        sum(if(trade_type='clob', shares_bought, 0)) as shares_bought,
        sum(if(trade_type='clob', shares_sold, 0)) as shares_sold,
        sum(if(trade_type='clob', usd_invested, 0)) as trade_usd_invested,
        sum(if(trade_type='clob', usd_realized, 0)) as trade_usd_realized,
        count(if(trade_type='clob', 1, null)) as trades,

        sum(if(trade_type='merge', shares_delta, 0)) as merge_shares_delta,
        count(if(trade_type='merge', 1, null)) as merges,
        sum(if(trade_type='merge', usd_invested, 0)) as merge_usd_invested,
        sum(if(trade_type='merge', usd_realized, 0)) as merge_usd_realized,

        sum(if(trade_type='split', shares_delta, 0)) as split_shares_delta,
        count(if(trade_type='split', 1, null)) as splits,
        sum(if(trade_type='split', usd_invested, 0)) as split_usd_invested,
        sum(if(trade_type='split', usd_realized, 0)) as split_usd_realized,

        sum(if(trade_type='convert_to_yes', shares_delta, 0)) as convert_to_yes_shares_delta,
        count(if(trade_type='convert_to_yes', 1, null)) as convert_to_yes_s,

        sum(if(trade_type='convert_from_no', shares_delta, 0)) as convert_from_no_shares_delta,
        count(if(trade_type='convert_from_no', 1, null)) as convert_from_no_s,
        sum(if(trade_type='convert_from_no', usd_realized, 0)) as convert_from_no_usd_realized,

        sum(if(trade_type='transfer_in', shares_delta, 0)) as transfer_in_shares_delta,
        count(if(trade_type='transfer_in', 1, null)) as transfer_ins,

        sum(if(trade_type='transfer_out', shares_delta, 0)) as transfer_out_shares_delta,
        count(if(trade_type='transfer_out', 1, null)) as transfer_outs,

        sum(usd_invested) as usd_invested,
        sum(usd_realized) as usd_realized,
        sum(shares_delta) as total_shares
    from audit_txs
    group by 1,2,3,4,5,6,7,8,9,10,11,12
)

select *,
    total_shares * settlement_value as resolution_profit,
    (total_shares * settlement_value) - usd_invested + usd_realized as final_profit
from audit_aggr
where true
-- and total_shares < -1
-- and trader in (select maker from short_list_wallets)
-- and trader = 0x84571f1bf97a5c710cbe51daff2dd4556cc887fd
-- -- and neg_risk = 'False'
-- and trader = 0xC4D5a24a240eC9f52669e3251E0473FD0c5687cf
-- and trader = 0xee50a31c3f5a7c77824b12a941a54388a2827ed6
-- and trader = 0x0c4b64af62a0ac3dd477e9f80ec3eaa18e92f6db
-- and trader = 0xd058d668771b6f4d0f8ee4c345089e369d98c532
-- and trader = 0xce296aaf92ecc022cc6608a54c622bb1c445b71b
-- and condition_id = 0x45932bc66b00af152e158b1f4c916d9f1e7639b5641c7e8c2a6901a7efa905a9
and trader not in (select wallet from filter_wallets)
-- order by total_shares desc
limit 10

-- select * from audit_txs
-- where trader = 0xC4D5a24a240eC9f52669e3251E0473FD0c5687cf
-- -- and condition_id = 0x45932bc66b00af152e158b1f4c916d9f1e7639b5641c7e8c2a6901a7efa905a9
-- order by block_time, evt_index
-- where trader = 0x0c4b64af62a0ac3dd477e9f80ec3eaa18e92f6db
-- where trader = 0xce296aaf92ecc022cc6608a54c622bb1c445b71b
-- and token_id in (
--     uint256'80172139326701765108593354605737918733332031006149436614549251803199576580256',
--     uint256'7195773232487043266978476530577454342538487460595382033047573657844322304414',
--     uint256'74552596225669253620878472148189203079227772907726247409482369584444874921155',
--     uint256'5623316591615451597601053453950462135219854616785584711264969061701991288999',
--     uint256'44725091126499333899568177448038860509765437354247408321452950536416452787104',
--     uint256'113384067667705168345314119917208860058593041651598365026330742747798385341969',
--     uint256'26837980823508254470249280319475503386893494717052596977838170518162147923721',

--     --
--     uint256'104759514460241892139371002205428862441630463557129279399757469741241677798219',
--     uint256'50934272987968315458423599988438377587631614891292186397039214412260765171905',
--     uint256'101510735805402334165766528202764835790000213929369598932788615758835645874547',
--     uint256'66232512034857544876752159572610185845353012140655737948053748904523938013701',
--     uint256'17305557643465067329253011405539831465600699322982179786670382602003786940905',
--     uint256'105822451351258779373414887922960431462248423534899454345965193715068300731564',
--     uint256'68284740559688870130006994131102415275712442208886316027960220135102135302927',

--     0
-- )
-- where token_id = uint256'13381326949921541597165699364493406669808285479989037075263368166849756643315'

-- where trader = 0x793e67beddb49b1c4ea8819c74644056a5d8baef
-- and token_id = uint256'17729640410767428830891271907670356081389789554536307716651081291770350315708'

-- where maker = 0xcE296aAf92Ecc022CC6608A54c622Bb1c445b71B
-- and condition_id = 0x45932bc66b00af152e158b1f4c916d9f1e7639b5641c7e8c2a6901a7efa905a9

-- where trader = 0x0c4b64af62a0ac3dd477e9f80ec3eaa18e92f6db
-- and token_id = uint256'80172139326701765108593354605737918733332031006149436614549251803199576580256'
-- order by block_time, evt_index
-- limit 10
-- -- 0x793e67beddb49b1c4ea8819c74644056a5d8baef
-- 17729640410767428830891271907670356081389789554536307716651081291770350315708
-- 0x97f7e9d839a3d94158c16ae7a1ccfd494a66ff980131ad0fc87bc98b7b1dc1c1
-- False
-- Over $300M committed to the Monad public sale?

-- 0x84571f1bf97a5c710cbe51daff2dd4556cc887fd - 15772492675271690004224774579529648001354106136177152441934501654602602558586
