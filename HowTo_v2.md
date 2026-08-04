# How to build a Polymarket Resolution dataset on Dune

## 1.Introduction
About a month ago, I started working on a framework to detect insider trading on polymarket. I decided to use Dune as the source of data, since its easier to verify the data, by building it from first principles, rather than relying on the Polymarket API. One of the main features I wanted to use was PnL per position. However, I couldn't find a reliable source of this data. There are multiple existing methodologies that looks reasonable, but breakdown the moment you run some basic sanity checks. The integrity of the PnL data is important to anything thats build on top of it. Hence I decided to delve deeper into the task of building a reliable PnL dataset on Dune, with auditable ledger, straight up from onchain data. 
This report is a documentation of the process: what are the obvious approaches, the flaws in them, where they break and how to fix them. We use example to pin point how each assumption breaks, and how the same example gets fixed at the end of the process.
We will build an event-ledger that tracks all the onchain events associated with polymarket positions, using it to reconstruct wallet-market level shares, USD flows and PnL. We will normailize all events into a common accounting model, and the resulting ledger can be used beyond just PnL calculations, and can be used to build downstream features such as execution behaviour and fill price dispersion.

## 2. The drawbacks of the obvious source
Choosing Dune as my data source was a major decision, esp when pretty much every other analytics framework from explorers to twitter bots utilize Polymarket's API source. This decision, is made worse by the fact that quite alot of Dune's prediction market data is now closed and available only to Enterprise customers. 

Polymarket's own API provides three endpoints that are in-general used to pull the required data. 

| Endpoint | What it gives you | What it's missing |
|---|---|---|
| `/v1/market-positions` | Current position snapshot | No history, no cost basis |
| `/positions` | Position snapshot | No trade-level breakdown, no spread |
| `/closed-positions` | Final resolved snapshot | No entry price, no path taken to get there |
The problem with these endpoint is that, 
1. They are closed source and blackboxed
2. What you get is what you have - you get a final state, no historical data, no 2nd order analytics. (the same problem faced by every GraphQL endpoint)
Important info like, entry and exit prices, fill spreads are condensed into a single `avgPrice` data point.
One can assume they can circumnavigate the lack of historical data, utilizing the `/trades` endpoint. But as you will soon see, there is more to a position than trades alone.
With respect to close source, building the dataset from onchain data gives the dataset verifiability, each action auditable and the ability to combine it with other onchain data.

## 3. The naive methodologies on Dune

Now that I have chosen the source of Data, I look at existing works. 

### 3.1. CLOB only position reconstruction

The most common approach is to aggregate USD delta from CLOB trades, built on top of `OrderFilled` events and combine it with USD withdrawn from `PayoutRedemption` events. As someone looking at Polymarket data structure for the first time, this sounds like a sound methodology.
> *A user can enter or exit positions through the CLOB and exit on Redemption*

A position in Polymarket is stored as a ERC-1155 token share. Since this is a token share, this share cannot be negative. In order to validate the above assumption, we hence try to compute the shares delta from each CLOB trade or `OrderFilled` event.

Lets look at an example (its a chosen case for demonstration and you will soon see this is a very common case), where the wallet `0xce296aaf92ecc022cc6608a54c622bb1c445b71b` trades the `Will Gemini 3.0 be released on November 17 2025?` market. The market has two tokens:
| Token Side  | Token  |
| ----------- | ------ |
| YES         | `46687945077176076830096477597797725250961514733182621481405351828163193903577`|
| NO          | `113016318552201794810557514937858326971831314187777686552865771003364240784846`|

If you take a look at all the CLOB trades of the user in the market:

| Timestamp           | Shares | Token Side | Direction | Shares Delta | Shares Cumulative | Flag | Token Price | USD Volume | Tx Link |  
| ------------------- | ------ | ---------- | --------- | ------------ | ----------------- | ---- | ---- | ---- | ----    |
| 2025-11-14 19:45:32 | 362.10 | NO         | BUY       | 362.10       | 362.10            | ✅   | 0.952 |	344.92 | [🔗](https://polygonscan.com/tx/0xb5c4db10463d7a05665e06794afe8400868baab79731296c0581df491ac5708a#eventlog) | 
| 2025-11-15 02:53:26 | 100    | NO         | SELL      | -100         | 262.10            | ✅   | 0.962 |	96.20 | [🔗](https://polygonscan.com/tx/0xc992ae2be4d33a2846dfcce465085ada3b9579f8e163281d00b7e25b18c6e0e3#eventlog) | 
| 2025-11-15 02:53:40 | 100    | NO         | SELL      | -100         | 162.10            | ✅   | 0.962 |	96.20 | [🔗](https://polygonscan.com/tx/0x4b67a585377cedcb7bc33f64dda9f72329d12c586365244c9ea53fc9f9a99b51#eventlog) | 
| 2025-11-15 02:56:36 | 162.1  | NO         | SELL      | -162.1       | 0.00              | ✅   | 0.954 |	154.64 | [🔗](https://polygonscan.com/tx/0x8c274aaeecacabd2f5e8d16de0c7cc1590035f6e5a4d5937308068f5a0727796#eventlog) | 
| 2025-11-15 03:29:28 | 100    | YES        | SELL      | -100         | -100              | 🚩   | 0.030	| 3.00 | [🔗](https://polygonscan.com/tx/0x76e3dc9817333f189a3526485a1538c0ddc33f74ace05e144036ae8a2b37af13#eventlog) | 
| 2025-11-15 03:32:04 | 250    | YES        | SELL      | -250         | -350              | 🚩   | 0.030 |	7.50 | [🔗](https://polygonscan.com/tx/0x42424044aed3d4bc83ab792bab84cf890d40a694fb7584df30810b7cfaea02d4#eventlog) | 

You can see how the 5th transaction sells YES token, that the user never bought.

Some approaches attempt to sidestep this by including wallets whose books will close cleanly using CLOB trades alone, i.e balances are non-negative. This is an approach that doesn't explain or explore the consequences of this missed section.

[TODO: STRUCTURE THIS BETTER]
A bigger issue with this methodology is that, the methodology doesn't understand the trade being placed, and the larger context behind the trade. To a new analyst, it looks like the user is selling YES tokens, but in reality, this trade was a 2nd leg of a trade where they were increasing their NO position. 
A key tell is, if you look at the above example, you might notice that that the trader buys NO around 95 cents and sells NO around 96 cents. This is a known yield farming strategy on Polymarket, where wallets buy tokens close to resolution to take advantage of the last bit of price movement, which is highly likely to close at 1 dollar. This wallet in particular has been making such trades quite frequently, thus the low price selling is very odd.

### 3.2. ERC 1155 balance reconstruction

This is the default way that enterprise customers of Dune, very likely get their position historical data. In now removed (closed source) Spells, Dune reconstructs ERC 1155 balances by aggregating `SingleTransfer` and `BatchTransfer` event deltas. 
This is the correct way to reconstruct position balances. However, it misses alot of of key features, the most important being the USD invested in gaining the position and USD realized upon selling. This approach also doesn't discern between a normal Wallet to Wallet transfer and a Trade or many of the other Ledger update events.
One might suggest building this balance from ERC1155 transfer events, and then combining it with CLOB trades would solve the problem, but it still wouldn't be enough.

This on the other hand, would help us solve the problem of what all could be possibly missing outside of CLOB trades.

## Reconstructing the CLOB

This is a section, that can be skipped if your only concern is to recreate Resolution balances. If you are however interested in understanding fill events, and what the onchain doesn't tell you about the Fills, this section is for you.

Storm Slivkoff discovered in [Polymarket Volume Is Being Double-Counted](https://www.paradigm.xyz/2025/12/polymarket-volume-is-being-double-counted) that a single market order trigger multiple `OrderFilled` events: one for each individual maker fill, and a single final `OrderFilled` event that summarizes all the fills.


## Objective of the Dataset

Our ledger dataset should be of the following structure:

| Field            | Description                                  |
| ---------------- | -------------------------------------------- |
| Wallet           | Wallet whose position changes                |
| Market           | Polymarket market or condition               |
| Outcome token    | YES, NO, or another outcome token            |
| Event type       | Trade, split, merge, conversion, or transfer |
| Share delta      | Change in the wallet’s outcome-token balance |
| USD delta        | Collateral spent or received                 |
| Transaction hash | On-chain transaction identifier              |
| Event index      | Position of the event within the transaction |
| Block time       | Timestamp of the event                       |

Our main north star should be that at all points, the running sum of all share deltas must be non-negative.
