How to Build a Polymarket Positions and Resolution Dataset on Dune
==================================================================

Abstract
--------

Polymarket position and PnL analysis is often built from CLOB trade data alone. This approach is incomplete because Polymarket positions are ERC-1155 assets whose balances can change through protocol operations beyond ordinary CLOB trades.

A wallet may acquire or dispose of positions through splits, merges, Negative Risk conversions, or direct ERC-1155 transfers. As a result, reconstructing positions exclusively from `OrderFilled` events can produce impossible negative balances, incomplete cost bases, and incorrect resolution PnL.

This report presents an event-ledger approach for building a Polymarket positions and resolution dataset on Dune. The methodology reconstructs wallet-level share and USD deltas from:

*   CLOB maker-taker fills,
    
*   standalone position splits,
    
*   standalone position merges,
    
*   Negative Risk conversions,
    
*   external ERC-1155 transfers,
    
*   and market settlement.
    

All event types are normalized into a common accounting model. The resulting ledger can be used to reconstruct historical position balances, calculate resolution value, estimate PnL, and derive downstream features such as bet size, execution behavior, and fill-level price dispersion.

* * *

1\. Motivation
==============

While building a framework to analyze potentially informed trading on Polymarket, I needed to construct wallet-level features such as:

*   position size,
    
*   capital deployed,
    
*   realized proceeds,
    
*   profit and loss,
    
*   and execution characteristics.
    

The first challenge was not calculating PnL itself. It was constructing a reliable record of how a wallet acquired, transferred, and disposed of its positions.

Existing approaches often aggregate CLOB activity from `OrderFilled` events and combine the resulting trade flows with settlement or redemption events. This can work for positions that are opened and closed entirely through ordinary CLOB trades. However, it does not capture every mechanism through which Polymarket positions can change.

Polymarket outcome positions are represented as ERC-1155 assets. Therefore, a complete position history must account for all relevant token movements rather than only CLOB trades.

The central principle of this dataset is:

> Build a complete event-level position ledger before calculating position-level PnL.

* * *

2\. Dataset objective
=====================

The dataset is designed to reconstruct the historical position and economic activity of a wallet across Polymarket markets.

Each normalized event contains conceptually:

Field

Description

Wallet

Wallet whose position changes

Market

Polymarket market or condition

Outcome token

YES, NO, or another outcome token

Event type

Trade, split, merge, conversion, or transfer

Share delta

Change in the wallet’s outcome-token balance

USD delta

Collateral spent or received

Transaction hash

On-chain transaction identifier

Event index

Position of the event within the transaction

Block time

Timestamp of the event

The event ledger supports two related forms of accounting.

2.1 Share accounting
--------------------

For each wallet, market, and outcome token:

St\=∑i≤tΔSiS\_t = \\sum\_{i \\leq t}\\Delta S\_iSt​\=i≤t∑​ΔSi​

where:

*   StS\_tSt​ is the reconstructed share balance at time ttt;
    
*   ΔSi\\Delta S\_iΔSi​ is the share change associated with event iii.
    

A reconstructed balance should not become negative. A negative balance indicates that the event ledger is incomplete or that an event has been incorrectly attributed.

2.2 USD accounting
------------------

Each event also contributes a USD delta:

Ut\=∑i≤tΔUiU\_t = \\sum\_{i \\leq t}\\Delta U\_iUt​\=i≤t∑​ΔUi​

The sign convention used in this report is:

*   USD spent by the wallet: negative;
    
*   USD received by the wallet: positive.
    

At resolution, the settlement value can be combined with the accumulated USD flows to calculate the position’s economic result.

* * *

3\. Why API snapshots are insufficient
======================================

Polymarket provides position-related API endpoints that can be used to retrieve current or final position information.

However, historical position snapshots do not provide a complete event-level accounting history. Important information may be unavailable, including:

*   the cost of acquiring individual positions;
    
*   the sequence of trades;
    
*   historical position balances;
    
*   entry and exit behavior;
    
*   execution prices;
    
*   fill-level price dispersion;
    
*   the source of position changes;
    
*   and the interaction between CLOB activity and other on-chain operations.
    

Building the dataset from on-chain events provides two advantages.

First, the calculations are auditable. Each share or USD change can be traced to an on-chain transaction and event.

Second, the position dataset can be combined with other on-chain information, including wallet activity, funding behavior, transaction timing, and cross-market behavior.

* * *

4\. Why CLOB-only position reconstruction fails
===============================================

A common approach is to aggregate CLOB activity from `OrderFilled` events and combine it with settlement or redemption events.

This approach makes an implicit assumption:

> Positions are acquired through CLOB buys and disposed of through CLOB sells or market resolution.

That assumption is incomplete.

Polymarket positions can also change through:

*   collateral splits;
    
*   position merges;
    
*   Negative Risk conversions;
    
*   and direct ERC-1155 transfers.
    

If these events are excluded, a trade-based reconstruction can produce negative share balances.

For example, a wallet may:

1.  deposit collateral;
    
2.  mint a YES/NO pair through a split;
    
3.  sell the NO position through the CLOB.
    

A trade-only ledger observes the NO sale but does not observe the NO tokens created during the split. The reconstructed NO balance may therefore become negative even though the wallet’s actual ERC-1155 balance never did.

Similarly, a wallet may:

1.  hold a YES position;
    
2.  buy the corresponding NO position;
    
3.  merge the YES and NO positions;
    
4.  receive collateral.
    

A CLOB-only ledger observes the NO purchase but may not observe the burn of both positions during the merge.

These examples show that trade data alone does not provide a complete position history.

* * *

5\. Reconstructing CLOB trades from `OrderFilled`
=================================================

5.1 Full-order events and individual fills
------------------------------------------

Polymarket order execution can emit more than one `OrderFilled` event for a market order.

The events represent two different levels of execution:

1.  individual maker-taker fills;
    
2.  the completed order.
    

The full-order event can be identified by the `taker` field, which contains the relevant Polymarket contract address.

Existing volume calculations often retain only full-order events. This avoids double counting when aggregating total volume because the individual fills and the completed order represent overlapping execution information.

However, retaining only full-order events removes the underlying fill-level data.

Individual maker-taker fills contain information that can be used to analyze:

*   individual execution prices;
    
*   fill-level position changes;
    
*   price dispersion across an order;
    
*   and execution behavior.
    

For this dataset, individual fills are retained and full-order events are used as an aggregate validation target.

* * *

5.2 CLOB trade structures
-------------------------

Maker-taker fills can be classified into three economic structures.

### Swap

A standard exchange in which an outcome token is exchanged for collateral.

For example:

*   one participant transfers YES;
    
*   the other transfers USD collateral.
    

### Split trade

A split trade creates complementary outcome positions.

Both sides contribute collateral, a YES/NO pair is minted, and the resulting positions are distributed between the participants.

### Merge trade

A merge trade combines complementary outcome positions.

The YES and NO positions are combined and redeemed for collateral.

> **Important:** CLOB split and merge trades are not the same as standalone `PositionSplit` and `PositionsMerge` operations. The CLOB structures are inferred from `OrderFilled` events, while standalone protocol operations are reconstructed separately from their corresponding events and ERC-1155 transfers.

* * *

5.3 Maker-oriented event data
-----------------------------

The individual `OrderFilled` event is expressed relative to the maker side of the fill.

For ordinary swap trades, the maker-side information is sufficient to interpret the transaction.

Split and merge fills are more complex because the complementary asset associated with the taker may not be directly represented in the same way as a conventional asset-for-collateral exchange.

The final full-order event can be used to infer the complementary asset involved in the fill.

Because the YES and NO positions involved in a split or merge represent complementary claims on one unit of collateral:

Pcomplement\=1−PloggedP\_{\\text{complement}} = 1 - P\_{\\text{logged}}Pcomplement​\=1−Plogged​

where:

*   PloggedP\_{\\text{logged}}Plogged​ is the price recorded in the maker-oriented fill event;
    
*   PcomplementP\_{\\text{complement}}Pcomplement​ is the inferred price of the complementary outcome position.
    

The share quantities are equal because the complementary positions must be paired to mint or redeem collateral.

The inferred complementary price can be used to calculate the fill’s corresponding USD value:

Vfill\=Qshares×(1−Plogged)V\_{\\text{fill}} = Q\_{\\text{shares}} \\times (1-P\_{\\text{logged}})Vfill​\=Qshares​×(1−Plogged​)

* * *

5.4 Taker-side reconstruction
-----------------------------

The taker-side interpretation is reconstructed primarily to preserve fill-level information.

It can support downstream calculations such as:

*   taker execution prices;
    
*   order-level price dispersion;
    
*   and execution-quality features.
    

However, the current position and resolution accounting does not require taker-side values as its primary accounting source.

The wallet-level dataset is built from normalized share and USD deltas. Taker-side reconstruction is therefore an additional analytical capability rather than a dependency of the final PnL calculation.

* * *

5.5 Fill-level price dispersion
-------------------------------

Retaining individual maker-taker fills enables features that cannot be recovered from full-order events alone.

For an order executed across multiple fills:

Price Range\=max⁡(Pfill)−min⁡(Pfill)\\text{Price Range} = \\max(P\_{\\text{fill}}) - \\min(P\_{\\text{fill}})Price Range\=max(Pfill​)−min(Pfill​)

This value can be used as a measure of execution-price dispersion.

A non-negative result provides a basic sanity check on the reconstructed fill prices.

This feature is not required for the positions and resolution dataset, but it may be useful for downstream analysis of:

*   execution quality;
    
*   order aggressiveness;
    
*   market impact;
    
*   and potentially informed trading.
    

* * *

5.6 CLOB validation
-------------------

The reconstructed fill-level USD volume can be aggregated and compared with the volume represented by full-order events.

The expected relationship is:

∑Vindividual fills≈∑Vfull orders\\sum V\_{\\text{individual fills}} \\approx \\sum V\_{\\text{full orders}}∑Vindividual fills​≈∑Vfull orders​

Any differences should be investigated for:

*   missing fills;
    
*   duplicate events;
    
*   incorrect trade classification;
    
*   incorrect complementary-price reconstruction;
    
*   or incomplete market coverage.
    

This comparison provides an aggregate validation of the trade reconstruction pipeline.

* * *

6\. Reconstructing non-CLOB position changes
============================================

CLOB fills do not capture all changes to a wallet’s ERC-1155 balances.

The remaining event classes are reconstructed separately and then normalized into the same accounting schema.

* * *

6.1 Standalone position splits
------------------------------

A position split deposits collateral and creates complementary outcome positions.

Conceptually:

1 USD→1 YES+1 NO1\\text{ USD} \\rightarrow 1\\text{ YES} + 1\\text{ NO}1 USD→1 YES+1 NO

The dataset identifies standalone splits using:

*   `PositionSplit` events;
    
*   nearby `BatchTransfer` events.
    

Some split operations occur as part of CLOB trade execution. To avoid counting those events twice, transactions containing `OrderFilled` events are excluded from the standalone split reconstruction.

The wallet receiving the split positions is identified from the recipient of an adjacent `BatchTransfer`.

The resulting accounting entries are:

Component

Delta

YES shares

Positive

NO shares

Positive

USD

Negative

For accounting purposes, the one unit of deposited collateral is allocated equally between the complementary positions:

PYES\=PNO\=0.50P\_{\\text{YES}} = P\_{\\text{NO}} = 0.50PYES​\=PNO​\=0.50

This is a **cost-basis allocation convention**, not an observed market price.

* * *

6.2 Standalone position merges
------------------------------

A position merge burns complementary outcome positions and releases collateral.

Conceptually:

1 YES+1 NO→1 USD1\\text{ YES} + 1\\text{ NO} \\rightarrow 1\\text{ USD}1 YES+1 NO→1 USD

Standalone merges are identified using:

*   `PositionsMerge` events;
    
*   nearby `BatchTransfer` events.
    

Transactions containing `OrderFilled` events are excluded to avoid overlap with CLOB trade execution.

The wallet participating in the merge is identified from the sender of the adjacent transfer.

The resulting accounting entries are:

Component

Delta

YES shares

Negative

NO shares

Negative

USD

Positive

The complementary positions are assigned the same $0.50 accounting allocation used for splits.

* * *

7\. Negative Risk conversions
=============================

Negative Risk markets contain multiple related markets in which only one outcome can resolve positively.

A wallet holding multiple NO positions may therefore hold collateral value that can be released before final market resolution.

The conversion process can involve:

*   burning NO positions;
    
*   releasing collateral value;
    
*   minting or transferring YES positions.
    

The dataset begins with the `PositionsConverted` event and reconstructs the surrounding token movements from nearby ERC-1155 transfer events.

The event ordering observed in the contract execution is used to identify:

1.  NO positions burned from the trader;
    
2.  YES positions received by the trader;
    
3.  collateral transferred to the trader.
    

These relationships are implemented as event-index heuristics.

The conversion value is calculated from the number of mutually exclusive NO positions participating in the conversion.

If:

*   nnn is the number of participating NO positions;
    
*   qqq is the matched share quantity;
    

then the collateral value released is:

Vconversion\=(n−1)×qV\_{\\text{conversion}} = (n-1)\\times qVconversion​\=(n−1)×q

The implementation should define whether qqq is the common quantity across all participating positions or another normalized share quantity.

### Example

Suppose a Negative Risk group contains four mutually exclusive markets and a wallet holds 100 NO shares in each market.

The wallet can convert the guaranteed value associated with three of the four positions:

(4−1)×100\=300 USD(4-1)\\times100 = 300\\text{ USD}(4−1)×100\=300 USD

The remaining position continues to represent exposure to the final outcome.

* * *

8\. External ERC-1155 transfers
===============================

Polymarket positions are ERC-1155 assets and can be transferred outside the normal CLOB and protocol flows.

These transfers affect ownership and must therefore be included in the share ledger.

External transfers are identified by excluding transfers associated with known Polymarket protocol contracts.

The accounting entries are:

Wallet

Share delta

USD delta

Sender

Negative

0

Receiver

Positive

0

A zero USD delta means that no collateral transfer is observed through the tracked Polymarket events.

It does **not** mean that the transferred position had zero economic value.

The transfer may have involved:

*   an off-chain payment;
    
*   an OTC agreement;
    
*   another smart contract;
    
*   or an unobserved exchange of value.
    

Therefore, external transfers can provide complete ownership accounting while leaving the transferred position’s economic cost basis unknown.

* * *

9\. Building the unified event ledger
=====================================

Each event source is normalized into the same schema.

    CLOB maker-taker fills
                +
    Standalone splits
                +
    Standalone merges
                +
    Negative Risk conversions
                +
    External ERC-1155 transfers
                +
    Settlement and redemption
                ↓
    Unified event-level ledger
                ↓
    Running share balances
                +
    Cumulative USD flows
                ↓
    Position settlement value
                ↓
    Resolution PnL

The unified ledger allows every position change to be processed using the same aggregation logic.

For each wallet, market, and outcome token:

Running Shares\=∑Share Delta\\text{Running Shares} = \\sum \\text{Share Delta}Running Shares\=∑Share Delta

For each wallet and market:

Net USD Flow\=∑USD Delta\\text{Net USD Flow} = \\sum \\text{USD Delta}Net USD Flow\=∑USD Delta

At resolution:

PnL\=Settlement Value+Net USD Flow\\text{PnL} = \\text{Settlement Value} + \\text{Net USD Flow}PnL\=Settlement Value+Net USD Flow

Under the sign convention used here:

*   capital deployed contributes a negative USD value;
    
*   proceeds contribute a positive USD value;
    
*   settlement value contributes a positive USD value.
    

* * *

10\. Mapping the SQL pipeline to the accounting model
=====================================================

The SQL query can be understood as a sequence of normalization layers.

SQL layer

Purpose

`short_list_markets`

Define the market universe and settlement information

`trades_level_1`

Separate and prepare individual fills and full-order events

`trades_level_2`

Classify and interpret trade structures

`trades_level_3`

Reconstruct complementary/taker-side information

`trades_level_4`

Produce normalized trade-level values

`batch_transfers`

Decode ERC-1155 batch token movements

`single_transfers`

Decode individual ERC-1155 transfers

`splits`

Identify standalone position splits

`merges`

Identify standalone position merges

`converts_*`

Reconstruct Negative Risk conversion legs

`trade_deltas`

Convert CLOB activity into share and USD deltas

`merges_splits_converts`

Normalize protocol operations

`single_transfer_deltas`

Normalize external transfers

`non_trade_txs`

Combine non-CLOB activity

`audit_txs`

Construct transaction-level validation data

`audit_aggr`

Aggregate validation results

The exact CTE names may change as the query evolves, but the conceptual layers should remain separate.

* * *

11\. Validation
===============

A dataset of this type should be validated at multiple levels.

11.1 Non-negative share balances
--------------------------------

For every wallet, market, and outcome:

St≥0S\_t \\geq 0St​≥0

A negative reconstructed balance indicates:

*   a missing split;
    
*   a missing transfer;
    
*   an incorrectly attributed merge;
    
*   an incomplete conversion;
    
*   or an error in trade reconstruction.
    

Report:

*   negative-balance count using CLOB trades only;
    
*   negative-balance count after adding splits and merges;
    
*   negative-balance count after adding conversions and external transfers.
    

**Results placeholder:**

Dataset version

Negative balances

CLOB only

`[X]`

CLOB + splits/merges

`[Y]`

Full event ledger

`[Z]`

* * *

11.2 Fill-volume reconciliation
-------------------------------

Compare the aggregate USD value reconstructed from individual fills with the corresponding full-order volume.

∑Vfills≈∑Vfull orders\\sum V\_{\\text{fills}} \\approx \\sum V\_{\\text{full orders}}∑Vfills​≈∑Vfull orders​

**Results placeholder:**

Metric

Value

Full-order volume

`$[X]`

Reconstructed fill volume

`$[Y]`

Difference

`$[Z]`

Relative difference

`[Z]%`

* * *

11.3 Final position reconciliation
----------------------------------

For resolved markets, compare:

*   reconstructed final share balances;
    
*   settlement or redemption events;
    
*   available final position snapshots.
    

Any unresolved differences should be categorized.

* * *

11.4 Event coverage
-------------------

Report the number and proportion of events contributed by each source.

Event type

Events

Share volume

USD volume

CLOB trades

`[X]`

`[X]`

`[X]`

Splits

`[X]`

`[X]`

`[X]`

Merges

`[X]`

`[X]`

`[X]`

NegRisk conversions

`[X]`

`[X]`

`[X]`

External transfers

`[X]`

`[X]`

`0`

This helps demonstrate whether non-CLOB operations are a minor edge case or a material part of the dataset.

* * *

12\. Limitations and assumptions
================================

The dataset uses several reconstruction assumptions.

Event-ordering heuristics
-------------------------

Split, merge, and conversion attribution relies on nearby event ordering.

These patterns are based on observed contract behavior and should be revalidated if contract implementations change.

Split and merge valuation
-------------------------

The $0.50 allocation assigns the $1 collateral value equally between complementary outcome positions.

This is an accounting convention and not an observed market execution price.

External transfer cost basis
----------------------------

External transfers are assigned zero observable USD flow.

This preserves ownership accounting but may not recover the actual economic cost basis.

Market and contract coverage
----------------------------

The dataset is limited to:

*   the selected market universe;
    
*   the configured date range;
    
*   and the contract versions included in the SQL.
    

Any excluded market types or contract versions should be documented.

Fees
----

The treatment of trading and protocol fees should be stated explicitly.

The final PnL definition should clarify whether fees are:

*   included in USD flows;
    
*   excluded;
    
*   or calculated separately.
    

Realized versus mark-to-market PnL
----------------------------------

The dataset is designed primarily for position and settlement accounting.

It should not be interpreted as a continuous mark-to-market PnL series unless an external market-price series is added.

* * *

13\. Extensions
===============

Once the event ledger is constructed, additional features can be derived without rebuilding the underlying position history.

Possible extensions include:

*   total capital deployed;
    
*   maximum position size;
    
*   average entry price;
    
*   realized PnL;
    
*   settlement PnL;
    
*   holding duration;
    
*   number of trades;
    
*   number of fills;
    
*   fill-level price dispersion;
    
*   execution-price features;
    
*   market concentration;
    
*   cross-market exposure;
    
*   wallet-level win rate;
    
*   and timing-based indicators of potentially informed trading.
    

The event ledger can also support a reusable feature layer for downstream models.

* * *

14\. Conclusion
===============

Reliable Polymarket PnL begins with reliable position accounting.

CLOB trades provide an important part of the position history, but they do not capture every way a wallet can acquire, dispose of, or transfer outcome positions.

A complete reconstruction requires combining:

*   individual CLOB fills;
    
*   standalone splits;
    
*   standalone merges;
    
*   Negative Risk conversions;
    
*   external ERC-1155 transfers;
    
*   and settlement events.
    

By normalizing these operations into a common share-and-USD ledger, the dataset provides an auditable foundation for position reconstruction and resolution PnL.

The resulting table is not only useful for calculating profits. It can serve as the underlying data model for broader analysis of Polymarket trading behavior, execution quality, wallet activity, and potentially informed trading.

* * *

References
----------

*   Paradigm — _Polymarket Volume Is Being Double-Counted_
    
*   Polymarket documentation on splits and merges
    
*   Polymarket documentation on Negative Risk conversion
    
*   Dune Polymarket event tables
    
*   Relevant Polymarket contract documentation
