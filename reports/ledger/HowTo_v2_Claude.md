# Building a Polymarket Positions & Resolutions Dataset on Dune

## 1. Motivation

About a month ago, I was building a framework to detect insider trading on Polymarket. One of the core features required was **profit and loss (PnL)** per trader, alongside others such as bet size and spread crossed. While building the PnL dataset, I couldn't find a single reliable source. Dune is littered with AI-agent-generated attempts that brute-force the calculation, so even if there was alpha in any of them, it's lost in the noise.

Sanity-checking the existing methodologies that at least *looked* reasonable, I kept running into negative balances and PnL numbers that couldn't be right. I like to build a single master table of raw actions before computing any KPI or feature — the integrity of the underlying event data matters more than anything built on top of it. This report documents that process: what breaks in the obvious approach, why it breaks, and how to fix it using on-chain ERC-1155 events directly.

## 2. What "Resolution" Means Here

Resolution data is the ground-truth PnL for every position a wallet has ever held on Polymarket — built trade by trade, not read off a snapshot.

## 3. Why the Obvious Sources Don't Work

Polymarket's own API exposes three endpoints that could, in principle, be used to pull this data:

| Endpoint | What it gives you | What it's missing |
|---|---|---|
| `/v1/market-positions` | Current position snapshot | No history, no cost basis |
| `/positions` | Position snapshot | No trade-level breakdown, no spread |
| `/closed-positions` | Final resolved snapshot | No entry price, no path taken to get there |

All three only return the **final state** of a position. Cost basis, spread crossed, and individual trade breakdown are unavailable. Building the dataset from on-chain data instead gives it two things a snapshot never can: **verifiability**, and the ability to combine it with other on-chain data (wallet clustering, funding sources, timing relative to news, etc.) for the insider-trading framework this was originally built for.

## 4. The Naive On-Chain Methodology, and Why It Breaks

The most common approach in existing literature: aggregate the USD delta from CLOB trades (built from `OrderFilled` events) and combine it with `PayoutRedemption` events on resolution. The assumption is that users enter and increase positions by buying on the CLOB, and exit or decrease positions by selling on the CLOB or holding to resolution.

This breaks in three ways:

1. **Double counting.** As Storm Slivkoff documented in [Polymarket Volume Is Being Double-Counted](https://www.paradigm.xyz/2025/12/polymarket-volume-is-being-double-counted), a single market (taker) order can trigger multiple `OrderFilled` events: one per individual maker fill it's matched against, *and* one synthetic event for the completed order as a whole, where the taker's own order appears in the maker fields and `taker` is set to the CTF/NegRisk contract address itself. Summing both naively overcounts volume.
2. **The CLOB isn't the only way to enter or exit a position.** This is verifiable directly: compute share deltas from CLOB trades alone and run a balance sanity check. Wallets show negative balances — a mathematical impossibility for an ERC-1155 token — which means the CLOB-only view is missing real economic activity.
3. **Some existing approaches sidestep this by only including wallets whose books close using CLOB trades alone.** This silently drops exactly the wallets doing the most interesting (and least well-behaved) things, and doesn't explain *why* the books don't close for everyone else.

## 5. First-Principles Ground Truth: Shares Can't Go Negative

Every Polymarket position is an ERC-1155 token. Balances can be reconstructed exactly, like a traditional ERC-20 balance, by unwrapping `TransferSingle` and `TransferBatch` events. This is the objectively *correct* way to compute a wallet's historical share balance at any point in time — and it's also how you catch the naive methodology being wrong: any transaction sequence that implies a negative share balance means some inflow was missed.

The catch: raw transfer events tell you nothing about the USD cost of acquiring that balance. Getting shares right is necessary but not sufficient — we still need cost basis and realized value per event.

## 6. CLOB Trades — Two Layers, Not One

This is the piece most write-ups get only half right. A "CLOB trade" on Polymarket is actually two structurally different things, both routed through `OrderFilled`.

### 6.1 Exchange-embedded Split/Merge orders

A maker order itself can be *typed* as a Split or a Merge, not just a plain Swap (see `_executeMatchCall` in Fig. 1 below). Depending on the order type, the contract branches into minting a new YES/NO pair, merging an existing pair back into collateral, or emitting nothing extra at all for a plain swap.

![Contract control flow: matchOrders → fillMakerOrder → fillFacingExchange → executeMatchCall, branching by order type](imgs/contract_control_flow.png)
*Fig. 1 — Order matching call flow. The bottom-left table shows how event index `i-2, i-1, i` differs by order type: a Normal trade emits `Transfer` + `OrderFilled`; a Split additionally emits `Mint`; a Merge additionally emits `Merge` — all still driven from the same maker-side data.*

The key point: these are fully captured by the ordinary maker-side fields on `OrderFilled` — no extra event tracking is needed, because the logged `price`/`amount` on the maker leg already reflect the true economics of the mint/merge. (Worth a spot-check: for a known split-typed order, confirm raw `maker_usd` for the fill matches `shares × 0.5` before trusting this at scale.)

### 6.2 Standalone Split/Merge/Convert

Separately, a user can call `splitPosition`, `mergePositions`, or `convertPositions` directly — outside the matching engine entirely. These fire `PositionSplit` / `PositionsMerge` / `PositionsConverted` events with no `OrderFilled` counterpart, and — critically — the event itself doesn't always name the trader receiving or sending shares. That has to be recovered from adjacent `TransferBatch` events (see §7).

### 6.3 Taker-side reconstruction — used for spread, not PnL

The common filter in existing literature is to discard partial maker-taker fills and keep only full-order fills, discarding valuable information in the process. Those partial fills are what let you compute **spread**: for a market (taker) order matched against several resting maker orders, each partial fill logs the *maker's* asset and price, not the taker's. A full order's outer `OrderFilled` event is distinguishable because `taker` is set to the CTF/NegRisk contract address (`is_full_order`); this event carries the taker's own resulting asset.

Since split/merge/swap fills always transfer equal shares on both sides, the taker's implied price is simply `(1 − maker_price)`, and the taker's asset can be recovered by walking to the terminal `OrderFilled` event of the same transaction. From here, min and max taker price across all fills in a transaction gives the **spread crossed** by that order: `max_taker_price − min_taker_price`, sanity-checked to always be non-negative.

**This branch is not consumed by the final PnL ledger.** Only the maker-side fields are read for the profit calculation, per the double-counting fix in §4 — the taker reconstruction exists purely to compute spread as a separate feature, and to sanity-check that `asset_id != taker_asset` heuristic is firing sensibly.

## 7. Standalone Split, Merge, and Convert — Heuristics

To track standalone Split/Merge, we watch `PositionSplit`/`PositionsMerge` directly. Two problems complicate this:

1. These events can *also* fire inside a matched trade (§6.1) — we don't want to double-count those.
2. The events don't always name the trader sending or receiving shares.

**Fix for (1):** exclude any transaction that also contains an `OrderFilled` event, applied once at final assembly across every non-CLOB event type (split, merge, convert, stray transfer) rather than per-event-type. This is a transaction-level exclusion, not an event-level one — see the caveat in §10.

**Fix for (2):**
- **Split** → trader is the *recipient* of the adjacent `BatchTransfer` (previous or next event index).
- **Merge** → trader is the *sender* of the `BatchTransfer` two events prior (`evt_index + 2` relative to the batch transfer).

### 7.1 NegRisk Convert

NegRisk markets bundle several mutually exclusive outcomes (e.g. 10 markets, only one resolves YES). Holding NO across `n` of them guarantees `n − 1` resolutions regardless of outcome. `convertPositions` lets a user burn `n` NO tokens for `n − 1` units of collateral, plus 1 YES token for free — and optionally trade that collateral for more YES.

Two legs need to be tracked from a single `PositionsConverted` event: the NO burn and the YES mint, each recovered from adjacent `BatchTransfer` events.

![convertPositions call flow and event-index table across fee/collateral configurations](imgs/conv.png)
*Fig. 2 — `convertPositions` flow. The right-hand table shows event offsets relative to the terminal `PositionsConverted` event (`i`) across four fee/collateral configurations. For the no-fee, v1 case used here: the trader's NO burn (`BatchTransfer`) falls between `i-3` and `i-6`; the YES mint to the trader is always at `i-1`.*

- **YES mint leg** → recipient of the `BatchTransfer` at `evt_index + 1` relative to `PositionsConverted`.
- **NO burn leg** → sender of the `BatchTransfer` from `operator = NegRisk Adapter`, found within `evt_index + 1` to `evt_index + 4` of `PositionsConverted` (v1 contracts carry no fee legs, so the offset collapses from the theoretical 6-event, fee-inclusive window down to 4).

> **Note:** this 4-event offset is fee-schedule-dependent — it holds for fee-free v1 NegRisk markets only. Fig. 2 shows the offset shifts under the "Both Fee & Collateral" and "No Collateral" configurations. Any extension of this dataset to fee-enabled markets needs to re-derive this window.

## 8. Pricing the Non-Swap Events

| Event | USD logic | Why |
|---|---|---|
| Split | `shares × 0.5` | $1 of collateral mints 1 YES + 1 NO — priced at parity |
| Merge | `shares × 0.5` | 1 YES + 1 NO burns for $1 of collateral — same parity |
| Convert (NO burn leg) | `(n − 1) × shares / n` | Of `n` NO tokens burned, `n − 1` convert straight to USD |
| Convert (YES mint leg) | `$0` | The 1 remaining unit converts to YES "for free" — the USD value already realized on the burn leg |
| Stray transfer | `$0` | No USD changes hands; pure share movement between wallets |

**Stray transfers** are `TransferSingle`/`TransferBatch` events where operator, sender, and recipient are *all* outside the known Polymarket contract set (CTF Exchange, NegRisk Adapter, fee modules, zero address). Since the position is an ERC-1155 token, holders can freely move it between their own wallets — this captures that without misattributing it as a trade.

## 9. Assembling the Ledger

Union five components into one trader-level table of `(trader, token, shares_delta, usd_invested, usd_realized)`:

- CLOB swaps (maker-side only, §4 / §6)
- Exchange-embedded splits/merges (§6.1 — already inside the CLOB swap rows)
- Standalone splits/merges (§7)
- NegRisk converts (§7.1)
- Stray transfers (§8)

Aggregated per `(trader, token_id)`, this gives `total_shares`, `usd_invested`, and `usd_realized`. Joined against `settlement_value` from the market-details table:

```
resolution_profit = total_shares × settlement_value
final_profit       = resolution_profit − usd_invested + usd_realized
```

A trader invests USD by (1) swapping into a position, or (2) depositing collateral to mint shares (Split). A trader realizes USD by (1) swapping out, (2) redeeming via Merge, (3) resolution payout, or (4) NegRisk conversion. `final_profit` is simply the sum of all realized and resolution USD, minus all invested USD.

## 10. Validation & Known Limitations

**Validation to run before trusting this at scale:**
- Balance check: the share-delta aggregation (§5) should never go negative for any `(trader, token_id)` at any point in time. Track the negative-balance rate before and after adding each event type (CLOB-only → +split/merge → +convert → +stray) as a concrete before/after metric.
- Spot-check 2–3 known wallets' computed `final_profit` against Polymarket's own activity feed / PnL display.
- Count transactions containing more than one distinct event type among `{OrderFilled, PositionSplit, PositionsMerge, PositionsConverted}` — this bounds the exposure of the transaction-level exclusion described below.
- Compare aggregate maker-side USD volume against full-order-fill volume as an internal consistency check (they should reconcile).

**Known limitations:**
- **Transaction-level exclusion granularity.** The filter that prevents double-counting exchange-embedded splits/merges (§7, fix for problem 1) excludes an entire transaction if it contains *any* `OrderFilled` event, not just the specific event pair. If a wallet ever batches an unrelated standalone split/merge together with a CLOB trade in the same transaction (plausible under Polymarket's relayer/meta-transaction pattern), that standalone action would be silently dropped. Rare, but checkable via the validation query above.
- **Fee-schedule fragility.** The NegRisk convert event-offset heuristic (§7.1) is derived for fee-free v1 contracts. It will silently produce wrong or missing legs on fee-enabled (v2) markets without re-deriving the offsets shown in Fig. 2.
- **Contract version scope.** The dataset is currently scoped to `contract_version = 'v1'`.
- **Market category exclusions.** Categories such as Crypto Prices, Up or Down, Esports, Recurring, Games, Sports, and Tweet Markets are excluded from the market universe. This is a deliberate noise/relevance filter for the insider-trading use case, not a methodology limitation — but it does mean this dataset is not a complete picture of all Polymarket volume, and that's a real selection-bias caveat for anyone reusing it for a different purpose.

## 11. References

- [Polymarket Volume Is Being Double-Counted — Storm Slivkoff, Paradigm](https://www.paradigm.xyz/2025/12/polymarket-volume-is-being-double-counted)
- [U.S. Soldier Charged With Using Classified Information To Profit From Prediction Market Bets — DOJ](https://www.justice.gov/opa/pr/us-soldier-charged-using-classified-information-profit-prediction-market-bets)
- [Google Employee Charged With Insider Trading — DOJ](https://www.justice.gov/usao-sdny/pr/google-employee-charged-insider-trading)
- [Polymarket bettors put $3 million on which crypto firm ZachXBT will expose next — CoinDesk](https://www.coindesk.com/markets/2026/02/24/polymarket-bettors-put-usd3-million-on-which-crypto-firm-zachxbt-will-expose-next)
- [Insiders cashed in before Axiom reveal, wallets bagged $1M on Polymarket — Cryptopolitan](https://www.cryptopolitan.com/insiders-cashed-in-before-axiom-reveal-wallets-bagged-1m-on-polymarket)
- [Polymarket PnL Calculation: Why Your Profit Numbers Are Probably Wrong](https://leolabs.me/blog/pnl-calculation/en/)
- [Decoding the Digital Tea Leaves: A Guide to Analyzing Polymarket's On-Chain Order Data](https://yzc.me/x01Crypto/decoding-polymarket)
- [Splitting — startpolymarket.com](https://startpolymarket.com/learn/splitting/)
- [Merging — startpolymarket.com](https://startpolymarket.com/learn/merging/)
- [Neg Risk and Converting — startpolymarket.com](https://startpolymarket.com/learn/converting-negative-risk/)
