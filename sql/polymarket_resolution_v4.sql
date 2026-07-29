with
short_list_wallets as (
    select * from dune.pyor_xyz.dataset_polymarket_sus_score_test
),
short_list_markets as (
    select distinct
        -- *,
        token_id,
        question,
        event_market_name,
        from_hex(condition_id) as condition_id,
        tags,
        from_iso8601_timestamp(market_start_time) as market_start_time,
        from_iso8601_timestamp(market_end_time) as market_end_time,
        resolved_on_timestamp,
        outcome,
        token_outcome
    from polymarket_polygon.market_details
    where true
        and from_iso8601_timestamp(market_start_time) > date'2025-10-01'
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
        -- ensure that outcome of token matches final outcome
        -- and lower(token_outcome) = lower(outcome)
        and token_id in (
            uint256'80172139326701765108593354605737918733332031006149436614549251803199576580256',
            uint256'7195773232487043266978476530577454342538487460595382033047573657844322304414',
            uint256'74552596225669253620878472148189203079227772907726247409482369584444874921155',
            uint256'5623316591615451597601053453950462135219854616785584711264969061701991288999',
            uint256'44725091126499333899568177448038860509765437354247408321452950536416452787104',
            uint256'113384067667705168345314119917208860058593041651598365026330742747798385341969',
            uint256'26837980823508254470249280319475503386893494717052596977838170518162147923721',


            --
            uint256'104759514460241892139371002205428862441630463557129279399757469741241677798219',
            uint256'50934272987968315458423599988438377587631614891292186397039214412260765171905',
            uint256'101510735805402334165766528202764835790000213929369598932788615758835645874547',
            uint256'66232512034857544876752159572610185845353012140655737948053748904523938013701',
            uint256'17305557643465067329253011405539831465600699322982179786670382602003786940905',
            uint256'105822451351258779373414887922960431462248423534899454345965193715068300731564',
            uint256'68284740559688870130006994131102415275712442208886316027960220135102135302927',


            uint256'35123492166352861493939502586229936226942118018972695076283528793811859916330',

            0
        )
),
trades_level_1 as (
    select
        t.*,
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
        last_value(t.token_outcome) over(
            partition by tx_hash
            order by evt_index
            rows between unbounded preceding and unbounded following
        ) as taker_token_outcome,
        case when taker=contract_address
            then true
            else false
        end as is_full_order,
        least(
            resolved_on_timestamp,
            market_end_time
      ) as orders_end_time
    from polymarket_polygon.market_trades t
        join short_list_markets s
            on t.condition_id = s.condition_id
            and t.asset_id = s.token_id
    where true
        -- and block_month >= date'2024-08-01'
        and block_month >= date'2025-10-01'
        and block_month <= date'2026-05-01'
        -- and block_month < date'2025-12-01'
        and contract_version = 'v1'
        and t.condition_id in (select condition_id from short_list_markets)
        and t.maker in (select maker from short_list_wallets)
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
            and date_diff('hour', block_time, orders_end_time) <= 24
        then True
        else False end as is_yield_farm_trade,
        case when taker_price < 0.05
            and lower(final_outcome) != lower(taker_token_outcome)
            and date_diff('hour', block_time, orders_end_time) <= 24
        then True
        else False end as is_notional_farm_trade
    from trades_level_3
),
batch_transfers as (
    select
        evt_block_time,
        evt_block_number,
        evt_index,
        evt_tx_hash,
        operator,
        "from" as sender,
        "to" as recipient,
        u.token_id,
        u.shares_raw/1e6 as shares,
        s.question,
        s.event_market_name
    from polymarket_polygon.ctf_evt_transferbatch b
        cross join unnest(b.ids, b."values") as u(token_id, shares_raw)
        left join short_list_markets s
            on u.token_id = s.token_id
    where true
    and evt_block_date >= date'2025-10-01'
    and evt_block_date <= date'2026-05-01'
    -- and evt_block_date < date'2025-12-01'
    and (
        -- split -> mint to contract, then transfer from contract
        "to" not in (
            0x4bfb41d5b3570defd03c39a9a4d8de6bd8b8982e, -- ctf exchange v1
            0xc5d563a36ae78145c45a50134d48a1215220f80a,  -- negrisk v1
            0xd91e80cf2e7be2e162c6513ced06f1dd0da35296 -- negrisk adapter
        )
        or
        -- merge -> burn
        "to" = 0x0000000000000000000000000000000000000000
    )
    -- filter out
    and u.token_id in (select token_id from short_list_markets)
    -- and b.ids[1] in (select token_id from short_list_markets)
    and b.evt_tx_hash not in (select tx_hash from trades_level_1)
),
splits as (
    select
        p.evt_block_time,
        p.evt_block_number,
        p.evt_index,
        p.evt_tx_hash,
        p.conditionId as condition_id,
        p.amount,
        b.recipient as trader,
        b.token_id,
        b.shares,
        'split' as trade_type,
        b.question,
        b.event_market_name
    from polymarket_polygon.ctf_evt_positionsplit p
        join batch_transfers b
            on p.evt_tx_hash = b.evt_tx_hash
            and (
                p.evt_index + 1 = b.evt_index
                or
                p.evt_index - 1 = b.evt_index
            )
        -- join short_list_markets s
        --     on p.conditionId = s.condition_id
        -- join trades t
        --     on p.evt_tx_hash != t.tx_hash
    where true
    and evt_block_date >= date'2025-10-01'
    and evt_block_date <= date'2026-05-01'
    -- and evt_block_date < date'2025-12-01'
    and p.conditionId in (select condition_id from short_list_markets)
    and p.evt_tx_hash not in (select tx_hash from trades_level_1)
    and b.recipient in (select maker from short_list_wallets)
),
merges as (
    select
        p.evt_block_time,
        p.evt_block_number,
        p.evt_index,
        p.evt_tx_hash,
        p.conditionId as condition_id,
        p.amount,
        b.sender as trader,
        b.token_id,
        -b.shares as shares,
        'merge' as trade_type,
        b.question,
        b.event_market_name
    from polymarket_polygon.ctf_evt_positionsmerge p
        join batch_transfers b
            on p.evt_tx_hash = b.evt_tx_hash
            and p.evt_index = b.evt_index + 2
        -- join short_list_markets s
        --     on p.conditionId = s.condition_id
        -- join trades t
        --     on p.evt_tx_hash != t.tx_hash
    where true
    and evt_block_date >= date'2025-10-01'
    and evt_block_date <= date'2026-05-01'
    -- and evt_block_date < date'2025-12-01'
    and p.conditionId in (select condition_id from short_list_markets)
    and p.evt_tx_hash not in (select tx_hash from trades_level_1)
    and b.recipient in (select maker from short_list_wallets)
),
converts_to_yes as (
    select
        p.evt_block_time,
        p.evt_block_number,
        p.evt_index,
        p.evt_tx_hash,
        -- p.conditionId as condition_id,
        p.marketId as condition_id,
        p.amount,
        b.recipient as trader,
        b.token_id,
        b.shares as shares,
        'convert to yes' as trade_type,
        b.question,
        b.event_market_name
    from polymarket_polygon.negriskadapter_evt_positionsconverted p
        join batch_transfers b
            on p.evt_tx_hash = b.evt_tx_hash
            and p.evt_index = b.evt_index + 1
            -- and b.operator = 0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296 -- not necessary imo
            and b.recipient = p.stakeholder
        -- join short_list_markets s
        --     on p.conditionId = s.condition_id
        -- join trades t
        --     on p.evt_tx_hash != t.tx_hash
    where true
    and evt_block_date >= date'2025-10-01'
    and evt_block_date <= date'2026-05-01'
    -- and evt_block_date < date'2025-12-01'
    -- and p.conditionId in (select condition_id from short_list_markets)
    and p.evt_tx_hash not in (select tx_hash from trades_level_1)
    and b.recipient in (select maker from short_list_wallets)
),
converts_from_no as (
    select
        p.evt_block_time,
        p.evt_block_number,
        p.evt_index,
        p.evt_tx_hash,
        -- p.conditionId as condition_id,
        p.marketId as condition_id,
        p.amount,
        b.sender as trader,
        b.token_id,
        - b.shares as shares,
        'convert from no' as trade_type,
        b.question,
        b.event_market_name
    from polymarket_polygon.negriskadapter_evt_positionsconverted p
        join batch_transfers b
            on p.evt_tx_hash = b.evt_tx_hash
            and b.operator = 0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296
            and b.sender = p.stakeholder
            -- and p.evt_index <= b.evt_index + 6
            -- event list: sender no, minted no, fee colat, colat, fee yes, yes, position converted
            and p.evt_index <= b.evt_index + 4
            -- v1 has no fees, so lets ignore fee colat and fee yes
        -- join short_list_markets s
        --     on p.conditionId = s.condition_id
        -- join trades t
        --     on p.evt_tx_hash != t.tx_hash
    where true
    and evt_block_date >= date'2025-10-01'
    and evt_block_date <= date'2026-05-01'
    -- and evt_block_date < date'2025-12-01'
    -- and p.conditionId in (select condition_id from short_list_markets)
    and p.evt_tx_hash not in (select tx_hash from trades_level_1)
    and b.sender in (select maker from short_list_wallets)
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
        block_number,
        tx_hash,
        maker,
        maker_asset,
        maker_token_outcome,
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
    -- only trades that resolve in direction of trader are worth
    -- and lower(maker_token_outcome) = lower(final_outcome)
),
merges_splits_converts as (
    select
        evt_block_time as block_time,
        evt_index,
        evt_block_number as block_number,
        evt_tx_hash as tx_hash,
        trader,
        token_id,
        null as maker_token_outcome,
        null as condition_id,
        null as neg_risk,
        question,
        null as final_outcome,
        null as market_start_time,
        null as market_end_time,
        null as orders_end_time,
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
        evt_block_number as block_number,
        evt_tx_hash as tx_hash,
        trader,
        token_id,
        null as maker_token_outcome,
        null as condition_id,
        null as neg_risk,
        question,
        null as final_outcome,
        null as market_start_time,
        null as market_end_time,
        null as orders_end_time,
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
        evt_block_number as block_number,
        evt_tx_hash as tx_hash,
        trader,
        token_id,
        null as maker_token_outcome,
        null as condition_id,
        null as neg_risk,
        question,
        null as final_outcome,
        null as market_start_time,
        null as market_end_time,
        null as orders_end_time,
        event_market_name,
        0 as usd,
        shares as shares_delta,
        shares as shares_bought,
        0 as shares_sold,
        0 as usd_invested,
        0 as usd_realized,
        trade_type
    from converts
),
audit_txs as (
    select *
    from merges_splits_converts
    union all
    select *,
        'clob' as trade_type
    from trade_deltas
),
trader_stats as (
    select
        maker,
        maker_asset,
        condition_id,
        neg_risk,

        question,
        market_start_time,
        market_end_time,
        orders_end_time,
        final_outcome,
        maker_token_outcome,

        event_market_name,
        sum(shares_delta) as final_shares,
        sum(shares_bought) as shares_bought,
        sum(shares_sold) as shares_sold,
        sum(usd_invested) as usd_invested,
        sum(usd_realized) as usd_realized,
        count(*) as trades
    from trade_deltas
    group by 1,2,3,4,5,6,7,8,9,10,11
),
merges_stats as (
    select
        trader,
        token_id,
        condition_id,
        sum(shares) as merge_shares,
        count(*) as merges
    from merges
    group by 1,2,3
),
splits_stats as (
    select
        trader,
        token_id,
        condition_id,
        sum(shares) as split_shares,
        count(*) as splits
    from splits
    where trade_type = 'split'
    group by 1,2,3
),
converts_stats as (
    select
        trader,
        token_id,
        -- condition_id,
        sum(shares) as convert_shares,
        count(*) as converts
    from converts
    group by 1,2 --,3
),
resolutions as (
    select
        t.*,
        m.merge_shares,
        m.merges,
        s.split_shares,
        s.splits,
        c.convert_shares,
        c.converts,
        t.shares_bought
            - t.shares_sold
            + coalesce(m.merge_shares,0)
            + coalesce(s.split_shares,0)
            + coalesce(c.convert_shares,0)
        as total_shares
    from trader_stats t
        left join merges_stats m
            on t.maker = m.trader
            and t.maker_asset = m.token_id
            and t.condition_id = m.condition_id
        left join splits_stats s
            on t.maker = s.trader
            and t.maker_asset = s.token_id
            and t.condition_id = s.condition_id
        left join converts_stats c
            on t.maker = c.trader
            and t.maker_asset = c.token_id
            -- and t.condition_id = c.condition_id
)

select *,
    if(
        lower(final_outcome) = lower(maker_token_outcome),
        total_shares,
        0
    ) as resolution_profit,
    if(
        lower(final_outcome) = lower(maker_token_outcome),
        total_shares,
        0
    ) - usd_invested + usd_realized as final_profit
from resolutions
-- where maker = 0xee50a31c3f5a7c77824b12a941a54388a2827ed6
where true
-- -- total_shares < 0
-- -- and neg_risk = 'False'
and maker = 0x0c4b64af62a0ac3dd477e9f80ec3eaa18e92f6db
-- order by total_shares desc
-- limit 10

-- select * from audit_txs
-- where trader = 0x0c4b64af62a0ac3dd477e9f80ec3eaa18e92f6db
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
-- order by block_time, evt_index

-- where maker = 0xcE296aAf92Ecc022CC6608A54c622Bb1c445b71B
-- and condition_id = 0x45932bc66b00af152e158b1f4c916d9f1e7639b5641c7e8c2a6901a7efa905a9

-- where trader = 0x0c4b64af62a0ac3dd477e9f80ec3eaa18e92f6db
-- and token_id = uint256'80172139326701765108593354605737918733332031006149436614549251803199576580256'
-- order by block_time, evt_index

-- -- 0x793e67beddb49b1c4ea8819c74644056a5d8baef
-- 17729640410767428830891271907670356081389789554536307716651081291770350315708
-- 0x97f7e9d839a3d94158c16ae7a1ccfd494a66ff980131ad0fc87bc98b7b1dc1c1
-- False
-- Over $300M committed to the Monad public sale?
