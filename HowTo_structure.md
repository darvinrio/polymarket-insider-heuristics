## ChatGPT
1. ~~Introduction~~
2. Dataset objective
3. ~~Why API snapshots~~ and CLOB-only PnL are insufficient
4. The unified accounting model
5. Reconstructing CLOB Trades
    1. Full orders versus maker-taker fills - Why full-order events are insufficient
    2. Why maker-side events are retained - Individual maker-taker fills and double counting
    3. Identifying swap, split, and merge fills - The three CLOB trade structures
      - Swap
      - Split
      - Merge
    > Important: CLOB split/merge trades are distinct from standalone
    > PositionSplit and PositionsMerge operations.
    4. Reconstructing the complementary/taker-side asset
    5. Normalizing fills into share and USD deltas
    6. Validation against full-order volume
    7. Optional fill-level features
      - Taker execution price
      - Price range / spread
6. Non-CLOB position changes
   1. Standalone splits
   2. Standalone merges
   3. NegRisk conversions
   4. External ERC-1155 transfers
7. Unified event ledger
8. Validation
9. Limitations

## Claude
1. ~~Motivation — insider-trading framework, need for PnL (keep, tighten)~~
2. What "Resolution" means here — one clear definition
3. ~~Why the obvious sources fail — turn your one-line API dismissal into a short table: endpoint → what it gives → what it's missing (snapshot-only, no cost basis, no spread, etc.)~~
4. The naive on-chain methodology and its two failure modes
    * double counting (cite Slivikoff, maker-only fix)
    * negative balances (the give-away that something's structurally missing)
5. First-principles ground truth: ERC1155 balances can't go negative — shares-only reconstruction, and why it's necessary-but-insufficient (no cost basis)
6. The missing event types, one at a time — Swap / Split / Merge / Convert / stray transfer, each with: what it is, the on-chain event(s), the heuristic for attributing the trader, the pricing rule. (Your current doc interleaves definition and heuristic-fixing; separating "what is it" from "how do I detect it" from "how do I price it" will make this much easier to follow, and lets you use a consistent template per event type.)
7. NegRisk convert deep-dive — this is your most complex piece, keep the diagram, but also add one for split/merge if feasible, and state the event-offset assumptions explicitly (see point 2 above) as callouts, so future-you (or a reader) can spot when they'd break.
8. Assembling the ledger — union of the five components → aggregate to shares_delta/usd_invested/usd_realized per (trader, token)
9. Resolution & final PnL formula — the two-line formula you end with, given its own section since it's the payoff
10. Validation — see enhancement suggestions below; this section doesn't exist yet and is arguably the most persuasive one you could add
11. Bonus: farm-trade heuristics — pull is_yield_farm_trade/is_notional_farm_trade out of the SQL into their own short section
12. Limitations & future work — taker-side coverage caveat, event-offset fragility for fee-enabled markets, category exclusions/selection bias, v1-only contract scope
13. Refs

## Enhancement ideas
Add a validation section — this is the biggest gap. Right now the doc asserts the fix works but never shows evidence. Concretely: "before this fix, X% of wallets had negative balances at some point; after, 0%" is a great before/after number if you have it. Spot-checking 2–3 known wallets' computed PnL against Polymarket's own UI/activity feed would be strong external validation too.
A worked numeric example. One wallet, half a dozen rows (a split, a couple of swaps, a convert, resolution) walked through by hand — this would make the pricing rules concrete in a way prose can't.
A small comparison table of the three API endpoints vs. this approach (columns: historical cost basis, spread, trade-level breakdown, verifiability).
State the maker-only-coverage assumption explicitly as a "how we verified this" callout, per point 3 above — it's the single most likely thing a technical reader will question.
Tie back to the stated goal. The doc opens with "insider trading detection" but ends at PnL with no bridge — even two sentences on how PnL, bet size, and spread combine into the actual insider-trading signal would close the loop nicely.
Note the v1-only scope (contract_version = 'v1') and what changes for v2/fee-enabled markets, since you already have neg_risk fee wallets in your filter list, suggesting you're aware fee handling is incomplete.
