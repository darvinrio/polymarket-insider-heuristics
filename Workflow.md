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
* check market creator trading same market
* check multi market exposure
* check multi tag exposure

* shares to usd ratio for yield farming
* filter out yield farming and volume farm trades so they do not affect thresholds and averages

## questions

* find the point of no comeback, at what price, time to resolution is there no 
* plot time to resolution vs price and check how often a price resolves in its favour

## todo

* insiderFinder and polysights
check afee google insider - 0xee50a31c3f5a7c77824b12a941a54388a2827ed6

## stuff to write

sanity checks:
* agg test
* quite alot of fixes to work around double counting, split and merge trades

## improvements

* threshold choices were arbitrary and not based on statistical analysis
* doesn't account how different markets might tie together
* ignore certain markets, that require external data providers as input - resolution is not the end - eg tweet markets where certain number is crossed but wont resolve immediately
* detects only distinct outliers, not group of wallets acting in unison - requires clustering analysis 
*

## sample txs:
* mint split - https://polygonscan.com/tx/0xa5e79271aceadbcd24d11590c6853de0b54a06d3d005d8f3ea010da02d3411c4#eventlog 
* burn merge - https://polygonscan.com/tx/0x257af7cb519b379df4f0a31916e7d9e197cf8e5538dc5963a10a6090d61a8d7b#eventlog
* one transfer batch - https://polygonscan.com/tx/0x22bab7042c3e4db919c553f37bf3adedf25b7f26cbda2770101b30e48b424ca4#eventlog
