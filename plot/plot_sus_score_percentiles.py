import plotly.graph_objects as go
from plotly.subplots import make_subplots
import polars as pl

# ── config ──────────────────────────────────────────────────────────
CSV_PATH = "plot/polymarket_sus_score_precentiles.csv"
OUTPUT_PATH = "plot/sus_score_percentiles.html"

BOX_PERCENTILES = {"p10", "p25", "p50", "p75", "p90"}
TAIL_PERCENTILES = ["p95", "p99", "p99_9", "p99_99", "p100"]
TAIL_LABELS = ["P95", "P99", "P99.9", "P99.99", "P100"]
# ────────────────────────────────────────────────────────────────────

data = pl.read_csv(CSV_PATH)

fig = make_subplots(
    rows=1,
    cols=2,
    subplot_titles=(
        "Anomaly score distributions by metric (P10 – P90)",
        "Tail percentiles (P95 – P100)",
    ),
    horizontal_spacing=0.12,
    column_widths=[0.45, 0.55],
)

# ── Left panel: box plots ───────────────────────────────────────────
for row in data.to_dicts():
    metric = row["metric"]
    fig.add_trace(
        go.Box(
            x=[metric],
            q1=[row["p25"]],
            q3=[row["p75"]],
            median=[row["p50"]],
            lowerfence=[row["p10"]],
            upperfence=[row["p90"]],
            jitter=0,
            pointpos=0,
            marker=dict(size=6),
            name=metric,
            showlegend=False,
        ),
        row=1,
        col=1,
    )

# ── Right panel: tail-percentile markers with annotations ──────────
for row in data.to_dicts():
    metric = row["metric"]
    values = [row[p] for p in TAIL_PERCENTILES]
    text_labels = [
        f"{label}: {val:.2f}" for label, val in zip(TAIL_LABELS, values)
    ]

    fig.add_trace(
        go.Scatter(
            x=TAIL_LABELS,
            y=values,
            mode="markers+text",
            text=text_labels,
            textposition="top center",
            name=metric.replace("_anomaly_score", "").replace("_", " ").title(),
            marker=dict(size=10, line=dict(width=1, color="white")),
            hovertemplate=(
                "<b>%{fullData.name}</b><br>"
                "Percentile: %{x}<br>"
                "Score: %{y:.4f}<extra></"
            ),
        ),
        row=1,
        col=2,
    )

# ── Layout ─────────────────────────────────────────────────────────
fig.update_xaxes(title_text="Metric", row=1, col=1)
fig.update_yaxes(title_text="Score", row=1, col=1)
fig.update_yaxes(title_text="Score", type="log", row=1, col=2)
fig.update_xaxes(title_text="Percentile", row=1, col=2)

fig.update_layout(
    title=dict(
        text="Anomaly score distributions by metric",
        subtitle=dict(text="P10 to P100"),
    ),
    legend_title="Metric",
    height=600,
)

fig.write_html(OUTPUT_PATH)
print(f"Saved → {OUTPUT_PATH}")
