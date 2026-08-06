# Polymarket Insider Trading Detection — Methodology Report

## Executive Summary

This report presents a framework for detecting and ranking potential insider trading behavior on Polymarket — the leading onchain prediction markets platform — using exclusively public, onchain data sourced from Dune Analytics. The analysis covers the period November 1, 2025 to May 1, 2026. Between this timeframe, over 1.03 billion trade entries were recorded, involving approximately 1.7 million unique participants.[1]

The approach is framed as an **investigation prioritization tool**, not a definitive legal finding. The framework produces a ranked list of wallets ordered by the concentration of unusual, correctly-directed, and contextually suspicious trading behavior under an onchain-only lens. All methodology decisions are made explicit and defensible, and the system is validated against publicly reported cases of confirmed or alleged insider trading.[1]

***

## 1. Problem Definition

### 1.1 What Is Insider Trading on Prediction Markets?

Prediction market insider trading occurs when a participant trades with material non-public information (MNPI) — information about the outcome of an event that has not yet been disseminated to the public — giving them a systematic informational edge over other market participants.[1]

Unlike equity markets, prediction markets have no formal regulatory enforcement mechanism or formal definition of MNPI. However, observable behavioral patterns can signal informed trading: unusual position sizing relative to the market, abnormally low entry prices shortly before a market resolves correctly, use of freshly created wallets, or large contrarian bets made just before resolution.[1]

### 1.2 Scope and Intent

This framework:
- Estimates the **likelihood** that a given wallet exhibits insider-consistent trading behavior
- Uses an **onchain-only** data source (Dune Analytics Polymarket tables)
- Produces a **ranking of wallets** by composite anomaly score, not a binary "guilty/not guilty" classification
- Makes no claim about legal culpability or intent

The framework operates on a subset of the full Polymarket universe, intentionally excluding market categories where structural noise would dominate the signal (see Section 2.2).

***

## 2. Analytical Scope

### 2.1 Timeframe

All trades are analyzed between November 1, 2025 and May 1, 2026. An additional warm-up buffer is applied: wallets with their first trade before November 20, 2025 are not flagged as "fresh wallets" for trades made in the early days of the observation window, to avoid false positives caused by the dataset start date.[1]

### 2.2 Market Exclusions

Not all Polymarket markets are equally informative for insider detection. Markets with high structural noise — where automated or opportunistic trading dominates — are excluded from the primary analysis. The following market categories are excluded:[1]

| Category Excluded | Reason for Exclusion |
|---|---|
| Crypto Prices / Up or Down | Oracle-driven; dominated by arbitrage bots hedging against external venues |
| Sports / Esports | Require live event data unavailable in onchain sources; high volatility |
| Recurring Markets | Structurally repetitive; strong automation incentive |
| Tweet Markets | Resolution relies on external event counts, not onchain observable |
| Games | High-frequency and low-signal category for informed trading |

These exclusions are **scope decisions**, not assertions that insider trading is absent in these categories. They reflect the observability constraints of a purely onchain methodology.[1]

### 2.3 Volume Filter

Markets with total resolved volume below 100,000 USDC are excluded to focus signal on liquid markets where significant capital commitment makes insider-consistent behavior more financially meaningful and more statistically distinguishable from noise.[1]

After applying these filters, the dataset reduces from 1.03 billion raw trade entries to approximately 18.3 million trades across 191,860 makers and 609,310 takers.[1]

***

## 3. Dataset Construction

### 3.1 Data Sources

The primary data sources are two Dune Analytics curated tables:

| Table | Contents |
|---|---|
| `polymarket.trades` | All `OrderFilled` events emitted by Polymarket CTF and Neg Risk contracts |
| `polymarket.marketdetails` | Market metadata: questions, outcomes, categories, resolution dates, resolved outcomes |

The `polymarket.trades` table is built from `OrderFilled` on-chain events emitted by both the CTF (Collateralized Trading Facility, used for binary YES/NO markets) and Neg Risk contracts (used for multi-outcome markets). This event carries: order hash, maker address, taker address, maker asset ID, taker asset ID, maker amount filled, taker amount filled, and fee.[1]

### 3.2 Full-Order vs. Fill-Level Events

Polymarket emits two distinct `OrderFilled` events per trade:[1]

1. **Fill-level events**: One event per individual taker-maker pair that fulfills part of a taker's order. The `taker` field contains the actual taker's wallet address.
2. **Full-order events**: One event summarizing the complete order fulfillment. The `taker` field contains the CTF or Neg Risk contract address.

A common pre-processing step in the literature (Paradigm / Slivkoff) removes fill-level events and retains only full-order events to avoid double-counting. **This analysis deliberately retains fill-level events**, as they are needed to compute the realized spread — the price difference across the fills comprising a single order — which is a key anomaly signal.[1]

### 3.3 Split and Merge Trade Reconstruction

Fill-level events can represent three distinct trade types:[1]

- **Swap trades**: Standard exchange of a YES or NO token for USDC
- **Split trades**: A taker and maker jointly deposit USDC and receive YES and NO tokens respectively
- **Merge trades**: A taker and maker combine YES and NO tokens to redeem USDC

For split and merge trades, the `OrderFilled` event emits information from the maker's perspective only. The taker-side price is therefore reconstructed as \(1 - p_{\text{maker}}\), since YES and NO shares are complementary (they sum to 1 in expectation at resolution). The USD volume of a fill is then computed as:

\[\text{USD volume} = \text{shares} \times (1 - p_{\text{maker}})\]

A sanity check aggregates fill-level maker USD volume and compares it against the full-order event volume to confirm consistency.[1]

### 3.4 Derived Fields

The following fields are derived from raw events and used throughout the analysis:

| Derived Field | Description |
|---|---|
| `side` | BUY or SELL, inferred from taker asset type |
| `price` | Implied price from shares and USD volume |
| `usd_betsize` | USD value of the trade |
| `spread` | Max price – min price across all fills in a single taker order |
| `time_to_resolution` | Seconds between trade timestamp and market resolution |
| `correct_direction` | Boolean: whether the traded outcome matches resolved outcome |

***

## 4. Controls and Confounder Labeling

Before applying detection heuristics, trades likely driven by non-informational motives are labeled and optionally excluded from signal scoring. These are **confounder controls**, not insider signals.

### 4.1 Notional Farming

Notional farming involves buying large quantities of shares at near-zero prices to inflate reported notional volume, a behavior associated with airdrop farming rather than genuine conviction. A trade is labeled as **notional farming** if:[1]

- The trader buys tokens priced **below 0.05**
- The trade occurs at most 48 hours before resolution
- The trade is in the **opposite** direction of the resolved outcome (i.e., buying a loser)

### 4.2 Yield Farming

Yield farming involves buying near-certain outcomes at prices close to 1.0 to capture the small residual gap at resolution. A trade is labeled as **yield farming** if:[1]

- The trader buys tokens priced **above 0.95**
- The trade occurs at most 48 hours before resolution
- The trade is in the **correct** direction of the resolved outcome (i.e., buying a winner)

These labels cover approximately 50% of trades in their respective price ranges and ensure that near-resolution activity near price extremes is not automatically flagged as insider-driven.[1]

***

## 5. Detection Heuristics

Six heuristics form the core of the insider detection framework — two behavioral (qualitative) and four size/execution (quantitative). Each heuristic captures a distinct dimension of informed trading behavior.[1]

### 5.1 Behavioral Heuristics

#### H1: Fresh Wallet Trade

**Intuition**: Insiders frequently use newly created wallets to avoid connecting suspicious trades to their primary identity or trade history.[1]

**Definition**: A trade is flagged as a fresh wallet trade if it occurs within the first **24 hours** of the wallet's first ever trade on Polymarket. Wallets whose first trade predates November 20, 2025 are exempt to prevent the dataset boundary from generating spurious flags.[1]

**False positives**: New legitimate retail participants, wallets set up to participate in a specific high-profile market, or wallets migrated from other platforms.

#### H2: Contrarian Trade

**Intuition**: An insider who knows the outcome of an event will buy the correct token even when the market overwhelmingly disagrees, generating a contrarian signal against prevailing market pricing near resolution.[1]

**Definition**: A trade is flagged as a contrarian trade if it occurs **at most 24 hours before market resolution**, and one of the following holds:
- A **BUY** at price **below 0.40** in the direction of the resolved outcome (buying against the market favorite and being correct)
- A **SELL** at price **above 0.70** of the outcome that resolves correctly (shorting the eventual winner at high prices)

**False positives**: Mispriced markets, thin liquidity at extremes, or users making intentional long-shot bets with no privileged information.

### 5.2 Size and Execution Heuristics

All four quantitative heuristics use **P90 percentile-based anomaly scoring** rather than z-scores. Z-scores are inappropriate here because both bet sizes and spread sizes are heavily right-skewed — assuming normality would systematically underweight extreme outliers. The anomaly score formula for a trade with value \(x\) against a reference distribution \(\{x_1, \ldots, x_n\}\) is:

\[\text{anomaly score} = \frac{x}{P_{90}(x_1, \ldots, x_n)} - 1\]

This measures how many multiples of P90 the trade exceeds the P90 threshold — a natural outlier measure for power-law-distributed financial data.[1]

#### H3: Market Bet-Size Anomaly

**Intuition**: Insiders entering a market with privileged knowledge tend to size their positions significantly larger than the typical participant, since their perceived edge justifies greater capital commitment. A trade that is anomalously large relative to what the rest of the market is wagering may reflect access to non-public information rather than ordinary speculation.[1]

**Definition**: The anomaly score compares a trade's USD bet size against the distribution of all bet sizes within the **same market**. The reference distribution includes all taker trades in that market. The score is:

\[\text{score}_{\text{market-bet}} = \frac{\text{betsize}}{P_{90}(\text{betsizes in market})} - 1\]

Scores are capped at **100 points**.[1]

**False positives**: Wealthy retail participants or institutional speculators who naturally trade large; markets with thin participation where even modest bets exceed P90; arbitrageurs closing large positions near resolution.

***

#### H4: User Bet-Size Anomaly

**Intuition**: A trader who consistently makes modest bets but suddenly places an unusually large trade on a specific market may be expressing heightened conviction — potentially driven by non-public information. By normalizing against the user's own history rather than the market, this signal captures intra-wallet behavioral change rather than absolute size.[1]

**Definition**: The anomaly score compares a trade's USD bet size against the distribution of all bet sizes made **by the same wallet** across all markets in the dataset. The score is:

\[\text{score}_{\text{user-bet}} = \frac{\text{betsize}}{P_{90}(\text{betsizes by wallet})} - 1\]

The key difference from H3 is the **partition**: H3 asks "is this trade large for this market?", while H4 asks "is this trade large for this user?". Both can fire independently — a whale's large trade may not trigger H3, but a small wallet's unusually large trade will trigger H4. Scores are capped at **50 points**.[1]

**False positives**: Wallets that progressively increase trade sizes over time; users who deliberately test markets with small trades before committing large amounts; wallets with very few historical trades where P90 is estimated from a thin distribution.

***

#### H5: Market Spread Anomaly

**Intuition**: Realized spread — the price range across the individual fills that constitute a single order — proxies for execution urgency. An insider racing to build a position before information becomes public may accept higher slippage than a patient, uninformed trader, resulting in an unusually wide spread relative to other executions in the same market.[1]

**Definition**: The spread of a trade is defined as the difference between the maximum and minimum fill prices across all taker-maker fills comprising that order. The anomaly score compares this spread against the distribution of **non-zero spreads** in the **same market**:

\[\text{score}_{\text{market-spread}} = \frac{\text{spread}}{P_{90}(\text{non-zero spreads in market})} - 1\]

Only non-zero spread values above 1e-6 are included in the reference distribution to exclude single-fill orders and floating-point artifacts. The key difference from H3 is the **measured quantity**: H3 measures capital committed, while H5 measures execution cost accepted — two different dimensions of informed urgency. Scores are capped at **50 points**.[1]

**False positives**: Legitimate large orders that naturally cross multiple price levels; thin order books where any market order produces a wide spread; algorithmic traders deliberately sweeping the book for reasons unrelated to insider information.

***

#### H6: User Spread Anomaly

**Intuition**: A trader who typically executes cleanly — single fill or tight multi-fill spread — but suddenly shows a wide spread on a specific market may have prioritized speed over price for that particular trade. This relative sloppiness compared to the user's own baseline can be a behavioral signal of urgency.[1]

**Definition**: The anomaly score compares a trade's realized spread against the distribution of **non-zero spreads** across **all trades by the same wallet**:

\[\text{score}_{\text{user-spread}} = \frac{\text{spread}}{P_{90}(\text{non-zero spreads by wallet})} - 1\]

The relationship between H5 and H6 mirrors that between H3 and H4: H5 asks "is this spread wide for this market?", while H6 asks "is this spread wide for this user?". A trade can trigger both, either, or neither. Scores are capped at **50 points**.[1]

**False positives**: Wallets with very few spread-generating trades, making P90 unstable; users who happen to trade during periods of low liquidity; wallets that routinely sweep books as part of a systematic (but non-insider) strategy.

***

## 6. Composite Scoring Framework

### 6.1 Trade-Level Score

Each trade receives a composite score that combines all six heuristic signals. Raw quantitative scores are **capped** to prevent extreme outliers from dominating the composite, and qualitative signals receive fixed point weights:[1]

| Signal | Type | Cap / Weight |
|---|---|---|
| Market bet-size anomaly | Quantitative | Capped at 100 pts |
| User bet-size anomaly | Quantitative | Capped at 50 pts |
| Market spread anomaly | Quantitative | Capped at 50 pts |
| User spread anomaly | Quantitative | Capped at 50 pts |
| Fresh wallet trade | Qualitative | Fixed 25 pts |
| Contrarian trade | Qualitative | Fixed 75 pts |
| **Maximum composite** | | **350 pts** |

Caps are set at the P99–P99.9 range of the non-zero score distribution, meaning at most 2,000–20,000 trades in the dataset are affected by any individual cap. These thresholds are chosen heuristically and represent a tuning parameter that should be revisited if score distributions shift with different market universes.[1]

Trades with zero score on all signals are dropped before wallet-level aggregation, reducing the working dataset from 18.3 million to approximately 1.84 million suspicious trades covering 54,478 unique wallets.[1]

### 6.2 Wallet-Level Score

Aggregating trade-level scores to a wallet-level rank requires care. A naive sum would heavily favor high-volume traders who make many small but slightly anomalous bets, rather than traders with a few concentrated, highly suspicious trades.[1]

The wallet-level score is computed as follows:
1. Only trades that were **in the correct direction of resolution** (winning trades) are included in the aggregation — trades against the resolved outcome cannot be insider-driven.
2. The **P99 percentile score** of all qualifying trades by the wallet is used as the wallet's final score. This ensures a wallet's ranking reflects its most anomalous activity, not its total trading activity.[1]

This design rewards wallets with even a single extremely suspicious, correctly-directed trade, while penalizing prolific traders with mostly ordinary activity.

> **Important caveat on look-ahead bias**: The winning-trade filter is applied ex post (using resolved outcomes) and is appropriate for an investigative, retrospective prioritization tool. This framework does not simulate a real-time detector; it ranks wallets for post-hoc investigation.[1]

***

## 7. Validation Against Known Public Cases

The framework is validated against three publicly reported insider trading events within the observation window. These cases serve as external sanity checks, not training labels.

### 7.1 AlphaRacoon — Google Gemini Insider

AlphaRacoon (`0xee50a31c3f5a7c77824b12a941a54388a2827ed6`) is a publicly identified insider who made approximately $1 million USD in profits by betting on Google Gemini release dates and the "Most Searched Person on Google 2025?" market. The wallet's strategy involved correctly predicting d4vd as the winner and buying NO on all competing candidates (Trump, Pope Leo XIV, Bianca Censori, Zohran Mamdani).[1]

**Framework result**: The wallet ranks **652nd** with a P99 score of **101.55**. Its highest-scored trade — a large NO bet on "What day will Gemini 3.0 be released?" — receives a composite score of **101.56**, driven primarily by market bet-size anomaly.[1]

The relatively moderate rank (652nd out of 54,478) reflects a limitation of the current framework: cross-market coordinated betting — where a single insider takes positions across multiple correlated markets — is not yet detected as a cluster. Each market is scored independently.[1]

### 7.2 Venezuela/Maduro — U.S. Military Insider

On January 3, 2026, President Trump announced the military capture of Venezuelan President Maduro. A cluster of wallets placed bets on Maduro removal markets hours before the public announcement. One wallet (`0x31a56e9E690c621eD21De08Cb559e9524Cdb8eD9`) was later linked to active-duty Army Special Forces Sergeant Gannon Ken Van Dyke, who was charged under the Commodity Exchange Act.[1]

**Framework results**:

| Wallet | P99 Score | Rank |
|---|---|---|
| `0x31a56e9E...` (Van Dyke) | 65.50 | 2,612 |
| `0xa72DB174...` | 86.39 | 1,243 |
| `0x6baf05d1...` | 126.19 | 102 |
| `0x168b100d...` | 85.13 | 1,273 |

Three of the four wallets score above 80 and rank within the top 2,500 wallets. The wallet later confirmed as belonging to Van Dyke ranks 2,612 — somewhat lower than expected — in part because the trade amounts (e.g., 7,000–7,215 USD per trade) were smaller relative to the overall market, reducing the market bet-size anomaly contribution.[1]

### 7.3 ZachXBT / Axiom Insider Trading Cluster

On February 26, 2026, ZachXBT exposed an Axiom employee (Broox Bauer) for orchestrating insider trading on Polymarket's "Which crypto company will ZachXBT expose?" market. The market had initially priced Meteora at 43% probability; the Axiom-connected wallets entered at low prices (~0.28–0.30) before the announcement drove prices to near-1.[1]

**Framework results** for the ten Axiom-linked wallets:

| Wallet | USD Volume | P99 Score | Rank |
|---|---|---|---|
| `0xe56526b2...` | 100,500.00 | 125.00 | 142 |
| `0x054ec2f0...` | 692,243.85 | 102.15 | 592 |
| `0x581f3434...` | 4,978.05 | 86.93 | 1,230 |
| `0x98a96619...` | 19,117.34 | 86.08 | 1,253 |
| `0x5e524f43...` | 16,247.87 | 76.45 | 1,745 |

The top two wallets rank within the top 600 globally, and the full cluster of ten wallets appears concentrated within the top 10,000 — providing strong evidence that the framework successfully surfaces this pattern.[1]

***

## 8. Error Analysis

### 8.1 False Positives

One of the highest-scoring trades in the dataset is a **"Nuclear weapon detonation by June 30?" NO purchase** of 20,000 USD, scoring 176 points (100 market bet-size + 50 user bet-size + 25 fresh wallet + 1 spread). This is almost certainly not insider-driven: buying NO on nuclear detonation is a low-information trade that large-dollar rational actors would make without any privileged knowledge.[1]

This false positive highlights a structural gap in the current framework: **market-decision context is not factored into scoring**. A NO trade on an existential-risk market carries fundamentally different informational implications than a NO trade on a corporate earnings market. A market-type-aware decision filter could substantially reduce this class of error.[1]

### 8.2 False Negatives

The AlphaRacoon case demonstrates the framework's primary false negative mode: coordinated cross-market positioning is not detected. A user making small-to-medium bets across five correlated markets may individually fall below scoring thresholds in each market, even though their aggregate behavior — correctly betting on a single underlying event across multiple surfaces — is strongly indicative of insider knowledge.[1]

***

## 9. Limitations

### 9.1 Onchain-Only Observability

The framework has no access to offchain event feeds, news timing data, social media activity, or IP-level data. This means trades made in response to publicly available breaking news cannot be distinguished from trades made on MNPI without additional data sources.[1]

### 9.2 Incomplete Position and PnL Reconstruction

PnL-based signals — frequently used in academic literature — are deliberately excluded from this framework. The root cause is that accurate PnL reconstruction requires tracking ERC-1155 token balances, which involves unwrapping batch transfers and combining two datasets (trades + transfers) at significant computational cost. Additionally, wallets can obtain exposure to an outcome by minting YES/NO pairs and selling one side, creating negative trade balances that break naive PnL calculations.[1]

### 9.3 Scoring Threshold Sensitivity

All scoring thresholds — the 0.40/0.70 contrarian price cutoffs, the P90 anomaly base, the percentile caps at P99–P99.9, the 25/75 qualitative weights — are heuristically chosen. The resulting rankings are sensitive to these parameters. A more principled alternative would be to:
- Learn thresholds from labeled examples using a supervised or semi-supervised model
- Use Median Absolute Deviation (MAD)-based robust z-scores to better handle extreme outliers

The current implementation avoids MAD-based scoring because Dune SQL lacks a native MAD function, which would require multiple costly data passes.[1]

### 9.4 Missing Wallet Context

Onchain wallet metadata — date of first transaction on any chain, source of funds, DeFi experience, cross-chain activity — could add meaningful signal. Fresh-wallet detection currently uses only the Polymarket first trade date; a wallet that has been active on Ethereum for three years before appearing on Polymarket carries different risk than one created 24 hours prior.[1]

***

## 10. Future Improvements

### 10.1 Position-State Tracking

Injecting past trading context per wallet — current position size, previous trades in the same market — would enable a **conviction signal**: how strongly is the current trade increasing or changing the wallet's exposure? A position increase on a market with high composite score would be a stronger signal than a first-time entry.[1]

### 10.2 Cross-Market Clustering

Multiple related markets often resolve on the same underlying event (e.g., all "Most Searched Person?" sub-markets, all "Maduro removal by date X?" variants). Grouping these into clusters and scoring wallet behavior at the cluster level would substantially improve recall for cases like AlphaRacoon.[1]

### 10.3 Wallet Clustering

The Axiom investigation revealed that a cluster of smaller wallets — each below individual score thresholds — collectively participated in the same trade. Graph-based wallet clustering using features like source of funds, trade timestamps, and entry prices could surface sybil-style coordinated insider networks that evade individual-wallet scoring.[1]

### 10.4 Better Outlier Scoring

Quantile-based capping can be replaced with a more expressive scoring function: identify a lower threshold above which a value is definitively an outlier, then apply log-scaled quantile normalization to preserve discrimination between extreme outliers while keeping the score bounded.[1]

### 10.5 Improved Market-Decision Filters

A market taxonomy that classifies each market as "insider-asymmetric" (where YES bets are more suspicious than NO bets, and vice versa) would reduce false positives from trades like the nuclear detonation case and improve score precision across politically sensitive or existential-risk markets.[1]
