# data/parquets

Parquet datasets used by the Polymarket investigation ("Best of 2025" /
Google Search insider-trading case). Both files are converted from CSV dumps
by [best_of/csv_to_parquet.py](../../best_of/csv_to_parquet.py), which applies
the schemas defined in [best_of/schema.py](../../best_of/schema.py).

| File | Grain | Rows |
| --- | --- | --- |
| `best_of_2025.parquet` | One row per on-chain trade/position event per trader | ~1.04M |
| `best_of_2025_markets.parquet` | One row per outcome token | 1,732 |

Join key: `token_id` (present in both files).

## best_of_2025.parquet (events)

Order-fill and position events emitted by the Polymarket CTF exchange
(Polygon). Each row reflects a change to one trader's position in one outcome
token. Monetary and share columns are `Decimal(38, 6)`; signed columns are
positive for inflows (buys/receipts) and negative for outflows
(sales/sends).

| Column | Type | Description |
| --- | --- | --- |
| `block_time` | Datetime (ms) | Timestamp of the Polygon block containing the event. |
| `evt_index` | Int64 | Log index of the event within its block; tie-breaker for ordering events that share a `block_time`. |
| `batch_evt_index` | Int64 | Index matching batch transfer (e.g. a split/merge/convert) that produced the event; `0` for plain order fills and transfers. |
| `token_index` | Int64 | Position of the event within its batch operation. |
| `block_number` | Int64 | Polygon block number containing the event. |
| `tx_hash` | String | Hash of the transaction that emitted the event. |
| `trader` | String | Wallet address whose position changed. |
| `counterparty` | String | Address on the other side of the event (taker for clobs, recipient or sender for transfers, 0xff for others). Never null. |
| `token_id` | String | ERC-1155 id of the outcome token involved; join key to `best_of_2025_markets.parquet`. |
| `usd` | Decimal(38,6) | Signed USD value of the event from the trader's perspective. |
| `shares_delta` | Decimal(38,6) | Signed change in the trader's share balance for this token (`shares_bought - shares_sold`). Cumulative sum per `(trader, token_id)` reconstructs the running position. |
| `shares_bought` | Decimal(38,6) | Gross shares acquired in the event (0 for sells). |
| `shares_sold` | Decimal(38,6) | Gross shares disposed of in the event (0 for buys). |
| `usd_invested` | Decimal(38,6) | USD spent acquiring shares in this event (0 for sells). |
| `usd_realized` | Decimal(38,6) | USD received from selling or redeeming shares in this event (0 for buys). |
| `trade_type` | String | Event classification. Observed values: `clob__buy__full_order`, `clob__buy__split`, `clob__sell__swap_fill`, `clob__sell__full_order`, `clob__sell__merge`, `convert_to_yes`, `merge`, `split`, `transfer_in`, `transfer_out`. |

## best_of_2025_markets.parquet (markets)

Static metadata for every outcome token referenced by the events file.
Each market has exactly two rows (one `Yes`, one `No` token).

| Column | Type | Description |
| --- | --- | --- |
| `token_id` | String | ERC-1155 id of the outcome token; join key to the events file. |
| `question` | String | Full market question text. |
| `event_market_name` | String | Name of the parent event page grouping related markets. |
| `event_market_id` | String | Identifier of the parent event page. |
| `condition_id` | String | Conditional Tokens Framework condition id for the market. |
| `tags` | String | Bracketed list of category tags, e.g. `[Music Culture Best of 2025]`; filter with `str.contains("Google Search")` for the insider-trading subset (930 of 1,732 tokens). |
| `neg_risk` | Boolean | Whether the market belongs to a negative-risk (mutually exclusive multi-outcome) group. |
| `market_start_time` | Datetime (ms) | When trading opened. |
| `market_end_time` | Datetime (ms) | Scheduled end of trading. |
| `resolved_on_timestamp` | Datetime (ms) | When the market actually resolved. |
| `orders_end_time` | Datetime (ms) | Deadline after which orders can no longer be placed. |
| `final_outcome` | String | Winning outcome at resolution. |
| `token_outcome` | String | Outcome this token represents (`Yes` or `No`). |
| `settlement_value` | Decimal(38,6) | Payout per winning share at resolution (typically 1 or 0, can also be 0.5). |

## Usage notes

- Events are not guaranteed to be globally sorted; sort by
  `(trader, token_id, block_time, evt_index)` before computing running
  positions.
- `split` / `merge` / `convert_to_yes` rows move shares between paired
  outcome tokens without USD flow, so `sum(usd_realized) <= sum(usd_invested)`
  holds globally but not necessarily per market.
