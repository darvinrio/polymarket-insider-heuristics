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
* burn merge - https://polygonscan.com/tx/0x257af7cb519b379df4f0a31916e7d9e197cf8e5538dc5963a10a6090d61a8d7b#eventlog
* one transfer batch - https://polygonscan.com/tx/0x22bab7042c3e4db919c553f37bf3adedf25b7f26cbda2770101b30e48b424ca4#eventlog
* position convert - https://polygonscan.com/tx/0x5ff247bce26e8c3f66325a64dc25bc0e9bcaeac10a92213f5a919a9105633c56#eventlog
* no order position split - https://polygonscan.com/tx/0xa5e79271aceadbcd24d11590c6853de0b54a06d3d005d8f3ea010da02d3411c4#eventlog
* single transfers - https://polygonscan.com/tx/0x8ef8f40527122be70189cce3767c5985484d2e320d8b40654da706db46e2f446#eventlog
* standalone batch transfer - https://polygonscan.com/tx/0xcf7db889831038876557559c9c405f1fadec660ddacf0b74a8a0298c932c2c9b#eventlog
* redemption - https://polygonscan.com/tx/0xb67f5bd8636c0b92ab521b3e3ea48ee7c70842ce0ed8ade4a4bb834c0658fc0b#eventlog
* convert with usdc - https://polygonscan.com/tx/0x3a2e7f588e1b67afd2cc03f854bfe8b8f1ec2e9762d16da6fd89b56b8bd60689#eventlog
* another convert with usdc - https://polygonscan.com/tx/0x76dd910235767078e08138c9d20cd45e7024e4fd31c24d37094b90da27cf18b6#eventlog
* weird trade - https://polygonscan.com/tx/0xae9ce3b1971fc9c0d3731c6fa5eb7d930eeb2c5cd169dc395bec0271acfe9195#eventlog

refs:
* [Polymarket Volume Is Being Double-Counted - Storm Slivkoff - Paradigm](https://www.paradigm.xyz/2025/12/polymarket-volume-is-being-double-counted)
* [U.S. Soldier Charged With Using Classified Information To Profit From Prediction Market Bets - Office of Public Affairs](https://www.justice.gov/opa/pr/us-soldier-charged-using-classified-information-profit-prediction-market-bets)
* [Google Employee Charged With Insider Trading](https://www.justice.gov/usao-sdny/pr/google-employee-charged-insider-trading)
* [Polymarket bettors put $3 million on which crypto firm ZachXBT will expose next - Coindesk](https://www.coindesk.com/markets/2026/02/24/polymarket-bettors-put-usd3-million-on-which-crypto-firm-zachxbt-will-expose-next)
* [Insiders cashed in before Axiom reveal, Wallets bagged $1M on Polymarket](https://www.cryptopolitan.com/insiders-cashed-in-before-axiom-reveal-wallets-bagged-1m-on-polymarket)
* [Polymarket PnL Calculation: Why Your Profit Numbers Are Probably Wrong](https://leolabs.me/blog/pnl-calculation/en/)
* [Decoding the Digital Tea Leaves: A Guide to Analyzing Polymarket’s On-Chain Order Data](https://yzc.me/x01Crypto/decoding-polymarket)
