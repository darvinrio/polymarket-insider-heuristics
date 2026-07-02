# Polymarket Insider Ranking

The Aim of this report is to create a framework for Ranking Polymarket Insiders based on their polymarket trading activity derived completely from onchain data. The focus of this report is on whats onchain, as Polymarket access is restricted in my country of origin India. 

## Data Prep

### Understanding whats Onchain
We will specifically utilize Dune Analytics `polymarket.trades` and `polymarket.market_details` tables. 
Polymarket enables prediction markets by creating YES/NO pair tokens that represent the outcome of a given question. There are two types of questions, CTF and Neg Risk.
CTF (Collateralized Trading Facility) contracts are used to resolve binary questions, while Neg Risk contracts are used to resolve non-binary multi-outcome questions.
`polymarket.trades` table is built from the `OrderFilled` events emitted by the Polymarket CTF and Neg Risk contracts, utilizing the `polymarket_details` table to map trade outcomes to market questions and other relevant metadata. 
```solidity
OrderFilled (
  index_topic_1 bytes32 orderHash,
  index_topic_2 address maker,
  index_topic_3 address taker,
  uint256 makerAssetId,
  uint256 takerAssetId,
  uint256 makerAmountFilled,
  uint256 takerAmountFilled,
  uint256 fee
)
```

![Contract flow](imgs/contract_control_flow.png)

Other than just Polymarket being banned in my country, Polymarket API itself is harder to scrape due to the vast size of the polymarket dataset. 
Between November 01, 2025 and April 28, 2026, a total of 1.03 Billion trade entries were recorded, by approximately 1.7 Million takers and makers.
Processing this massive dataset without any initial filtering, on Dune Analytics on a free tier is extremely slow, expensive, and borderline impossible with the 2 minute query limit.


### Initial Filtering
Since the data set is too large to process,we will use EDA and qualitative analysis to reduce the dataset size. 
We will employ a qualitative filter first, aiming to reduce the number of trades to process.
1. We first filter out markets that are likely to have high volume due to arbitrage. Markets that are trading on Crypto and Stock Prices, tend to follow oracle prices and consist of alot of arbitrage bots looking to trade inefficienies against external markets. These categories extremely have high volume and highly recurrent markets, inviting strong automations. Moreover, users can actively hedge positions across various venues to protect downside risk, thus making it harder to signal.
2. Markets that are trading on sports outcomes, tend to have strong volatility and follow live events closely. Live event data is the most important signal for these markets. Since the data utilized for this analysis is strictly onchain, the lack of access to offchain event data, that must be curated from dedicated APIs, is a significant effort. Thus, we will ignore these markets for the initial filter.
3. A sane $100K threshold for total volume processed is also used

We specifically ignore any market with one of the following tags:
```sql
[
  'Crypto Prices', 'Up or Down', 
  'Esports', 'Recurring', 
  'Games', 'Sports',
  'Tweet Markets'
]
```

Filtering for shortlisted markets with volume > $100k, gives us a 98% reduction in the number of trades.

| label | trades | makers | takers |
--- | --- | --- | --- |
| 1. all trades | 1.03b | 1.73m | 1.68m |
| 2. ignore full-order trades | 646.81m | 812.92k | 1.68m |
| 3. shortlisted markets | 25.09m | 224.25k | 676.51k |
| 4. shortlisted markets (volume > $100k) | 18.30m | 191.86k | 609.31k |

### Cleaning Dune Polymarket Trades
The most common filter amongst existing literature is to ignore maker fills and only include full-order trades. 
This has its origins from Paradigm's research [Polymarket Volume Is Being Double-Counted](https://www.paradigm.xyz/2025/12/polymarket-volume-is-being-double-counted), where Storm Slivkoff noted that two kinds of `OrderFilled` events are emitted by the Polymarket CTF and Neg Risk contracts. When a user makes a market order, the `OrderFilled` event is emitted for both individual taker-maker fills and to the the complete order that is fulfilled. The two events can be distinguished by checking the `taker` field, which is the CTF or Neg Risk contract address for a full order. 
This filter, when added at a early stage of the data cleaning process, would remove maker-taker fills. These fills are extremely valuable, as they contain individual taker-maker fills that can be utilized to calculate the spread of a trade thats realized by the taker. The spread can be calulated as the difference between the min price and max price of the all the taker fills. A quick sanity check is performed on the spread to ensure that spread is always positive.

Furthermore, taker-maker fills can be put into 3 buckets: 
1. **Swap trades** - trades where the YES/NO contract is traded directly, with USD exchanged
2. **Merge trades** - where a between a maker and taker, one side provide YES and the other side provides NO, combine their YES and NO contracts to redeem USD and receive USD
3. **Split trades** - where a maker and taker deposit USD, mint YES and NO pairs in equal numbers and one side receives YES and the other side receives NO. 

These however are not flagged by the Dune dataset. Moreover, these trades tend to show different data in the columns that what is expected. 
This is because, for a maker-taker trade, the `OrderFilled` event always emits the information wrt to the maker side. In the case of split and merge trades, this causes a discrepancy as the taker side is not present in the event data. Hence, some extra calculations based on some heuristics are needed to get the maker info of these fills. 
For these split and merge fills, we can obtain the correct taker asset by getting the info from the final `OrderFilled` event.
Since the `shares` required to redeem or mint YES/NO pairs are same, the split and merge fills always have the same amount of shares for the maker and taker. Since these assets are to be combined to redeem or mint, the price of the maker asset can be obtained as `(1-price)` where `price` is the asset price logged in the `OrderFilled` event. 
Using this, `(1 - price)` as the maker asset price, we can now calculate the usd volume of a fill as `shares * (1-price)`. 
We can sanity check this by aggregating the maker usd volume of all fills and comparing it to the volume of all full order fills, ensuring it matches.

### Initial trade labelling
With Polymarket Airdrop speculation in mind, there are two main types of trades, that can be filtered, where directionality is inconsequential and the trader is trading on the inefficiency for before the market reaches a resolution. These are:
1. **Notional Farming** - Trades where users buy shares close to 0 price. This pumps up their notional volume in exchange for small USD volume. eg: buying 100000 YES shares at 0.0001 price for 100 USD. 
2. **Yield Farming** - Traders where users buy shares close to 1 price. This captures the small difference between the market price and resolution price. eg: buying 100000 YES shares at 0.98 price for 98000 USD and booking 2000 USD profit upon redemption.

For our analysis, we will label a trade as : 
1. **Notional Farming** - If the trader buys Tokens priced under 0.05 at most 48 hours before resolution in the opposite direction of resolution (i.e if "YES" is bought and final outcome is "NO")
2. **Yield Farming** - If the trader buys Tokens priced over 0.95 at most 48 hours before resolution in the same direction of resolution (i.e if 'YES" is bought and final outcome is "YES")

This labelling helps label around 50% of the trades in these price ranges.
![notional_and_yield_farming](imgs/notional_and_yield_farmers.png)

## Signals 

Inorder to label potential insider traders, we will use the following well-known signals and aggregate them to score each trade and eventually aggregate it per trader. Once again, we can use qualitative and quantitative signals to score each trade.
We will go with well-known qualitative signals such as: 
* **Fresh wallet Trade** - A trade that is made by a new wallet
* **Contrarian Trade** - A trade that is made against the prevailing market trend

On the quantitative side, we will go with:
* **Betsize anomaly** - Trades where the size of the position is an outlier when compared to a subset of the trades in the same market or same user
* **Spread anomaly** - Trades where the spread is an outlier when compared to a subset of the trades in the same market or same user

We will define these signals as follows:
* **Fresh wallet trade** - A trade made within the first 24 hours of a wallet's first trade. Since our dataset is focussing on data after Nov 2025, we add a extra filter to ensure trades made in November are all not logged as fresh wallet trades. We do this by selectively ignoring first trades before 20th November 2025.
* **Contrarian trade** - A trade made atmost 24 hours before the resolution of a market, that is either a BUY trade below 0.4 in the direction of resolution of the market or a SELL trade above 0.7 in the direction opposite to the resolution of the market.
* **Bet size anomaly** - We define two kinds of anomaly, one with respect to the market and one with respect to the user, i.e how a trade betsize compares to other traders in the same market or trades by the same user. In both cases, we will use measures of central tendency (median, 90th percentile) and dispersion (quartile ranges) to define the anomaly threshold and also quantify it. To quantify the anomaly, first we define p90 percentile as the threshold. Since trading tends to be extremely right skewed, we then measure how many times p90 percentile, does the actual betsize exceed the p90 percentile. If the actual betsize is `x` and `[x1 ... xn]` is all the betsizes in a market or user partition, then the anomaly score is
  ```
  (x / p90_percentile([x1 ... xn])) - 1
  ```
* **Spread size anomaly** - A similar anomaly score is computed for the spread size of a trade. Since spread size contains a lot of zero values, we particularly filter for only non-zero values when computing the anomaly score. If the actual spread size is `x` and `[x1 ... xn]` is all the spread sizes in a market or user partition, then the anomaly score is
  ```
  (x / p90_percentile([x1 ... xn] where xi > 0)) - 1
  ```

#### Why `z-score` was not utilized ? 
`z-score` was not utilized because it assumes a normal distribution of data. Both bet-size and spread size are extremely right skewed, so `z-score` is not a suitable measure for these variables.
A more robust alternative such as MAD (Median Absolute Deviation) based z-score was explored. However the underlying Dune-SQL doesn't have a built in function and hence calculating MAD based z-score would require multiple passes over the data, increasing computing time.

#### Why no `PNL` signal?
PNL was another frequently used signal by other literatures. Existing work to rebuild PnL from onchain data (eg [blackhamm3r query](https://dune.com/queries/7440670)) create PNL from trade data by aggregating USD flow and PayoutRedemption values. A quick sanity check, is to compute per trader shares balances from these trades and check for negative values. Since Polymarket stores YES/NO positions separately in the form of ERC 1155, these positions can never be negative.

Example:

Lets check the trades posted by `0xce296aaf92ecc022cc6608a54c622bb1c445b71b` in the `Will Gemini 3.0 be released on November 17 2025?` market.

| key | value |
| --- | --- |
|market name|Will Gemini 3.0 be released on November 17 2025?|
|condition id|0x45932bc66b00af152e158b1f4c916d9f1e7639b5641c7e8c2a6901a7efa905a9|
| YES token | 46687945077176076830096477597797725250961514733182621481405351828163193903577 | 
| NO token | 113016318552201794810557514937858326971831314187777686552865771003364240784846 |

Lets consider the first 5 trades 

| maker_asset |	delta |	balance |	direction | 
| - | - | - | - |
113016318552201794810557514937858326971831314187777686552865771003364240784846 |	362.104711 |	362.104711 |	BUY |
113016318552201794810557514937858326971831314187777686552865771003364240784846 |	-100 |	262.104711 |	SELL |
113016318552201794810557514937858326971831314187777686552865771003364240784846 |	-100 |	162.104711 |	SELL |
113016318552201794810557514937858326971831314187777686552865771003364240784846 |	-162.1 |	0.004711 |	SELL |
46687945077176076830096477597797725250961514733182621481405351828163193903577	| **-100**	|	-100 | SELL |

You can see how the wallet sells `YES` token, when it never bought it. Turns out unaccounted by other research pieces, a wallet can get `NO` exposure by depositing USD, minting `YES` + `NO` pair and then market selling `YES` tokens. The fix looks straightforward at first, as you need to track ERC1155 transfers instead of trades. However this creates a couple of major complications: 
1. ERC1155 have `batchTransfers` which need to be unwrapped, involving a cross join. This increases computational expense, esp alot of the markets we focus on are NegRisk, with multiple options and multiple YES/NO pairs transfered in a single batch. 
2. Tracking ERC1155 transfers only gives us the balance at resolution or at any chose instant. However, to calculate PnL we still need trades to compute invested amounts and realized profits. This means combining two 100+ GB datasets, and potentially joining them. Since these combined data need to be further combined with other datasets for aggregations, this would creap up the compute expense extremely. 

For these two reasons, I ignore PnL as a signal.
