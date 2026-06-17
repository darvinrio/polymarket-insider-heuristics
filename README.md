# Insider Trading Detection on Polymarket

## Task
The objective of this challenge is to investigate potential informed or insider trading behavior on Polymarket.

You are expected to collect public Polymarket data, build a scoped dataset, design explainable heuristics, and identify accounts that may show insider trading patterns.

**Timeframe of analysis**: November 1, 2025 - May 1, 2026 (you are free to pick any examples
within this timeframe)

**Task**:
1. Collect necessary data for the analysis within the required timeframe.
2. Create and explain a list of heuristics that will be used to identify a potential insider
behavior.
3. Apply the heuristics on the traders data and produce a concise report describing your
findings.
4. Develop a ranking system showing a likelihood of each trader exhibiting an insider
behavior. Explain your methodology.

**Outputs**:
1. Written report describing both the methodology and the findings.
2. Code that was used to collect and analyze the data.
3. Investigation artifacts in CSV format

Please email your results to Courtney.fisher@inca.digital

## Commands

env commands:
```sh
set -a       # variable export
source .env  # load environment variables
set +a       # variable export disable
```

git commands:
```sh
# delete local merged branches
git branch --merged | grep -v '\*' | xargs -n 1 git branch -d

# prune origin deleted branches
git remote prune origin
```
