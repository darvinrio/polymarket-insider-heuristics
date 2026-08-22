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

api_positions_df = pl.read_csv(
    API_POSITIONS_FILE, schema_overrides=API_POSITIONS_SCHEMA
)
problematic_df = pl.read_csv(PROBLEMATIC_FILE, schema_overrides=PROBLEMATIC_FILE_SCHEMA)
problematic_user_activity_df = pl.read_csv(
    PROBLEMATIC_USER_ACTIVITY_FILE, schema_overrides=USER_ACTIVITY_SCHEMA
)
ledger_df = pl.read_csv(LEDGER_FILE, schema_overrides=AUDIT_SCHEMA)

# first from ledger, we filter for problematic positions
# then we run a quick labelling of each position based on
# number of `convert_from_no` and `transfer_out`
# we recalculate pnl by ignoring `convert_from_no` and `transfer_out`
# compare the results with api positions df, see if problematic positions persist
