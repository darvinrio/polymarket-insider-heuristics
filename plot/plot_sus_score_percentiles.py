import plotly.graph_objects as go
import polars as pl

fig = go.Figure()
data = pl.read_csv("plot/polymarket_sus_score_precentiles.csv")

# plot_list = ["market_betsize_anomaly_score", "user_betsize_anomaly_score"]
for row in data.to_dicts():
    metric = row.get("metric")
    # if metric not in plot_list:
    #     continue
    fig.add_trace(
        go.Box(
            x=[metric],
            q1=[row.get("p25")],
            q3=[row.get("p75")],
            median=[row.get("p50")],
            lowerfence=[row.get("p10")],
            upperfence=[row.get("p90")],
            jitter=0,
            pointpos=0,
            marker=dict(size=6),
            # hovertemplate="%{y:.4f}<extra>" + metric + "</extra>",
        )
    )


fig.update_yaxes(title_text="Score")
fig.update_xaxes(title_text="Metric")
fig.update_layout(
    title=dict(
        text="Anomaly score distributions by metric",
        subtitle=dict(text="P10 to P90"),
    )
)
fig.write_html("plot/sus_score_percentiles.html")

# print(data.to_dicts())
