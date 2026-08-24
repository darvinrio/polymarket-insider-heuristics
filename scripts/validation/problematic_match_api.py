import polars as pl

from scripts.validation.schema import (
    API_POSITIONS_SCHEMA,
    AUDIT_SCHEMA,
    PROBLEMATIC_FILE_SCHEMA,
    USER_ACTIVITY_SCHEMA,
)

API_POSITIONS_FILE = "scripts/validation/outputs/api_positions.csv"
PROBLEMATIC_FILE = "scripts/validation/outputs/problematic_df.csv"
PROBLEMATIC_USER_ACTIVITY_FILE = (
    "scripts/validation/outputs/problematic_user_activity.csv"
)
LEDGER_FILE = "data/csvs/polymarket_resolutions_v7_full_sample_positions.csv"

api_positions_df = pl.scan_csv(
    API_POSITIONS_FILE, schema_overrides=API_POSITIONS_SCHEMA
)
problematic_df = pl.scan_csv(PROBLEMATIC_FILE, schema_overrides=PROBLEMATIC_FILE_SCHEMA)
problematic_user_activity_df = pl.scan_csv(
    PROBLEMATIC_USER_ACTIVITY_FILE, schema_overrides=USER_ACTIVITY_SCHEMA
)
ledger_df = pl.scan_csv(LEDGER_FILE, schema_overrides=AUDIT_SCHEMA)

# first from ledger, we filter for problematic positions
# then we run a quick labelling of each position based on
# number of `convert_from_no` and `transfer_out`
# we recalculate pnl by ignoring `convert_from_no` and `transfer_out`
# compare the results with api positions df, see if problematic positions persist

ledger_columns = ledger_df.collect_schema().names()
problematic_ledger_df = ledger_df.join(
    problematic_df,
    left_on=["trader", "token_id"],
    right_on=["trader", "token_id"],
    suffix="_right",
    how="inner",
).select(ledger_columns)

print(problematic_ledger_df.collect_schema().names())

problematic_ledger_df.collect().write_csv(
    "scripts/validation/outputs/problematic_ledger_df.csv"
)
