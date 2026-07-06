# Simplify: separate annotations onto own line per metric, stagger vertically, larger fonts, remove clutter by shortening tail labels

import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots

df = pd.read_csv("data/polymarket_sus_score_precentiles.csv", index_col=0)
metrics = df.index.tolist()
short_names = {
    "market_betsize_anomaly_score": "Mkt-Bet",
    "market_spread_anomaly_score": "Mkt-Spr",
    "user_betsize_anomaly_score": "Usr-Bet",
    "user_spread_anomaly_score": "Usr-Spr",
}
colors = ["#5B8FF9", "#61DDAA", "#F6BD16", "#F97C7C"]
eps = 1e-4


def fmt(v):
    if v == 0:
        return "0"
    if abs(v) >= 1000:
        return f"{v:,.0f}"
    if abs(v) >= 1:
        return f"{v:.2f}"
    return f"{v:.1e}"


fig = make_subplots(
    rows=1,
    cols=2,
    subplot_titles=("Core Percentiles: P10-P90", "Full Range: P10-P100 (Tail Marked)"),
    horizontal_spacing=0.18,
)

for i, m in enumerate(metrics):
    x = short_names[m]
    color = colors[i]
    p10, p25, p50, p75, p90 = df.loc[m, ["p10", "p25", "p50", "p75", "p90"]]
    p10e, p25e, p50e, p75e, p90e = [max(v, eps) for v in (p10, p25, p50, p75, p90)]

    fig.add_trace(
        go.Box(
            x=[x],
            lowerfence=[p10e],
            q1=[p25e],
            median=[p50e],
            q3=[p75e],
            upperfence=[p90e],
            name=x,
            marker_color=color,
            showlegend=False,
            width=0.35,
            line=dict(width=3),
        ),
        row=1,
        col=1,
    )

    pts = [("P10", p10), ("P25", p25), ("P50", p50), ("P75", p75), ("P90", p90)]
    for k, (label, val) in enumerate(pts):
        fig.add_annotation(
            x=x,
            y=max(val, eps),
            text=f"{fmt(val)}",
            showarrow=True,
            arrowhead=0,
            arrowwidth=1,
            arrowcolor=color,
            ax=40 if k % 2 == 0 else -40,
            ay=0,
            xanchor="left" if k % 2 == 0 else "right",
            font=dict(size=12, color="#ffffff"),
            row=1,
            col=1,
        )

    fig.add_trace(
        go.Box(
            x=[x],
            lowerfence=[p10e],
            q1=[p25e],
            median=[p50e],
            q3=[p75e],
            upperfence=[p90e],
            name=x,
            marker_color=color,
            showlegend=False,
            width=0.35,
            line=dict(width=3),
        ),
        row=1,
        col=2,
    )

    tail_vals = df.loc[m, ["p95", "p99", "p99_9", "p99_99", "p100"]]
    tail_e = tail_vals.clip(lower=eps)
    fig.add_trace(
        go.Scatter(
            x=[x] * len(tail_vals),
            y=tail_e.values,
            mode="markers",
            marker=dict(
                color=color,
                size=11,
                symbol="diamond",
                line=dict(width=1.5, color="white"),
            ),
            name=x,
            showlegend=False,
        ),
        row=1,
        col=2,
    )

    labels_map = {
        "p95": "P95",
        "p99": "P99",
        "p99_9": "P99.9",
        "p99_99": "P99.99",
        "p100": "P100",
    }
    ax_pattern = [55, -55, 55, -55, 55]
    for j, (label, val) in enumerate(tail_vals.items()):
        fig.add_annotation(
            x=x,
            y=max(val, eps),
            text=f"{labels_map[label]}:{fmt(val)}",
            showarrow=True,
            arrowhead=0,
            arrowwidth=1,
            arrowcolor=color,
            ax=ax_pattern[j],
            ay=0,
            xanchor="left" if ax_pattern[j] > 0 else "right",
            font=dict(size=11, color="#ffffff"),
            row=1,
            col=2,
        )

fig.update_yaxes(
    title_text="Score (log)", type="log", row=1, col=1, tickfont=dict(size=14)
)
fig.update_yaxes(
    title_text="Score (log)", type="log", row=1, col=2, tickfont=dict(size=14)
)
fig.update_xaxes(title_text="Metric", row=1, col=1, tickfont=dict(size=14))
fig.update_xaxes(title_text="Metric", row=1, col=2, tickfont=dict(size=14))

fig.update_layout(
    title={
        "text": "Anomaly Score Percentile Distributions Across Metrics<br><span style='font-size: 16px; font-weight: normal;'>Left: quartile box plots (P10-P90) | Right: adds extreme tail percentiles P95-P100</span>"
    },
    font=dict(size=15),
    margin=dict(l=100, r=100, t=140, b=70),
)

fig.write_html("plot/anomaly_score_boxplots_final.html")

# fig.write_image(
#     "plot/anomaly_score_boxplots_final.png", width=2200, height=950, scale=1
# )
# with open("plot/anomaly_score_boxplots_final.png.meta.json", "w") as f:
#     json.dump(
#         {
#             "caption": "Anomaly score percentile distributions (log scale)",
#             "description": "Side by side box plots of four anomaly score metrics: core percentiles P10-P90 (left) and full range with tail percentiles P95-P100 marked (right)",
#         },
#         f,
#     )
# print("done")
