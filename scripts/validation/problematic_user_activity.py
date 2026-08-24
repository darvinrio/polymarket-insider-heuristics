"""
Pull full user activity for every (trader, condition_id) combo listed in
scripts/validation/outputs/problematic_df.csv via GET /activity, and store the
combined raw rows as one CSV. Reuses the per-(trader, conditionId) disk cache
so re-runs are cheap and resumable.
"""

import polars as pl
from loguru import logger
from tqdm import tqdm

from scripts.validation.user_activity import get_user_activity

logger.success("START")

PROBLEMATIC_FILE = "scripts/validation/outputs/problematic_df.csv"
OUTPUT_FILE = "scripts/validation/outputs/problematic_user_activity.csv"

pairs_df = (
    pl.scan_csv(PROBLEMATIC_FILE, infer_schema_length=0)
    .select(pl.col("trader"), pl.col("condition_id"))
    .unique()
    .collect()
)
logger.info(f"Unique (trader, conditionId) combos: {pairs_df.height}")

trader_condition_df = pairs_df.group_by(pl.col("trader")).agg(
    pl.col("condition_id").alias("condition_id_list")
)

all_activity = []
for trader, condition_id_list in tqdm(
    trader_condition_df.iter_rows(named=False),
    total=trader_condition_df.height,
    desc="Traders",
):
    all_activity.extend(get_user_activity(trader, condition_id_list))

activity_df = pl.DataFrame(all_activity, infer_schema_length=None)
logger.info(f"Total activity rows pulled: {activity_df.height}")

activity_df.write_csv(OUTPUT_FILE)
logger.success(f"DONE -> {OUTPUT_FILE}")
