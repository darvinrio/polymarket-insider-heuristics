# workflow

documenting the entire process.

1. check total trades [DUNE]
2. price distribution to check if 99 and 0 can be ignored [DUNE]
3. volume distribution to see volume dominance around 0 and 99 [DUNE]
4. aggregate market data and analyze volume distribution to filter low volume markets [DUNE]

## features:

* wallet freshness
* bet size anomalies (vs market average)
* bet size anomalies (vs trader average)
* order spread
* resolution proximity
* ✅ is yield (close to resolution, resolves equals buy direction, price above 0.9) - need heuristic proof
* ✅ is volume farm (close to resolution, resolve opposite of buy, price below 0.1) - need heuristic proof

* shares to usd ratio for yield farming

## questions

* find the point of no comeback, at what price, time to resolution is there no 
* plot time to resolution vs price and check how often a price resolves in its favour

## todo

*

## stuff to write

sanity checks:
* agg test

quite alot of fixes to work around double counting, split and merge trades
