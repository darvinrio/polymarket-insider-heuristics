# Code Used

## 1. Polymarket Trades

`polymarket_trades_v2.sql`

Extends `polymarket_polygon.market_trades` and `polymarket_polygon.market_details` to 
1. add extra context to classify trades as `swap`, `split`, `merge` trades and also `full order` trades.  
2. add info on both taker and maker sides of the trade.
3. calculate spreads of a `full order`.
4. label trades as `yield farming` or `notional farming`

## 2. Polymarket User Stats

`polymarket_user_stats.sql`

Aggregates data by wallet and calculates features to label wallets as describe wallet behaviours
1. Fill sizing
2. Spreads accepted
3. Measures of Central Tendency of features
4. Dominance of labelled trades - eg: Notional farming

## 3. Polymarket Market Stats

`polymarket_market_stats.sql`

Aggregates data by market and calculates features to label markets as describe average behaviour of users in a market
1. Bet sizing
2. Spreads accepted
3. Measures of Central Tendency of features

## 4. Trade Labelling and Scoring

`polymarket_trade_labelling.sql`

Labels and scores each trade by comparing a trade against User stats of the Taker and Market stats of the Market.

## 5. Polymarket Sus Score

`polymarket_sus_score.sql`

Calculates an aggregate of sus scores from suspicious trades labelled as such in `polymarket_trade_labelling.sql`. This is aggregate on a per-wallet basis and ranked.
