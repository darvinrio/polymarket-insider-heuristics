# How to build a Polymarket Resolution dataset on Dune

About a month ago, I started working on a framework to detect insider trading on polymarket. I decided to use Dune as the source of data, since its easier to verify the data, by building it from first principles, rather than relying on the Polymarket API. One of the main features I wanted to use was PnL per position. However, I couldn't find a reliable source of this data. There are multiple existing methodologies that looks reasonable, but breakdown the moment you run some basic sanity checks. The integrity of the PnL data is important to anything thats build on top of it. Hence I decided to delve deeper into the task of building a reliable PnL dataset on Dune, with auditable ledger, straight up from onchain data. 
This report is a documentation of the process: what are the obvious approaches, the flaws in them, where they break and how to fix them. We use example to pin point how each assumption breaks, and how the same example gets fixed at the end of the process.
We will build an event-ledger that tracks all the onchain events associated with polymarket positions, using it to reconstruct wallet-market level shares, USD flows and PnL. We will normailize all events into a common accounting model, and the resulting ledger can be used beyond just PnL calculations, and can be used to build downstream features such as execution behaviour and fill price dispersion.

## The drawbacks of the obvious source
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
Important info like, entry and exit prices, fill spreads are condensed into a single data point.
One can assume they can circumnavigate the lack of historical data, utilizing the `/trades` endpoint. But as you will soon see, there is more to a position than trades alone.
With respect to close source, building the dataset from onchain data gives the dataset verifiability, each action auditable and the ability to combine it with other onchain data.

## The naive methodologies on Dune

Now that I have chosen the source of Data, I look at existing works. 

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

Our main north star should be the eventual sum of all share deltas must be non-negative.
