"""
clean_data.py — Cleans and validates the raw EURO 2024 match data,
joins it with the stadium reference table, and exports Snowflake-ready CSVs.
Step 2.3 of the Event Ticketing & Attendance Analytics project.
Inputs : euro2024_matches_raw.csv, data/stadiums.csv
Outputs: data/matches.csv, data/stadiums.csv (unchanged, validated)
"""

import pandas as pd
from pathlib import Path

RAW_FILE = Path("euro2024_matches_raw.csv")
STADIUMS_FILE = Path("data/stadiums.csv")
OUTPUT_FILE = Path("data/matches.csv")

PHASE_ORDER = ["Group stage", "Round of 16", "Quarter-finals",
               "Semi-finals", "Final"]

# ---------- Load ----------
raw = pd.read_csv(RAW_FILE)
stadiums = pd.read_csv(STADIUMS_FILE)
print(f"Raw matches: {len(raw)} rows | Stadiums: {len(stadiums)} rows")

# ---------- Clean ----------
# 1. Drop FBref separator rows (fully empty lines between matchdays).
df = raw.dropna(subset=["Attendance"]).copy()

# 2. Strip the "(Neutral Site)" suffix so venue names match the
#    stadium reference table (our join key).
df["Venue"] = df["Venue"].str.replace(r"\s*\(Neutral Site\)", "", regex=True).str.strip()

# 2b. Strip the country codes FBref glues onto team names:
#     trailing code for home teams ("Slovenia si"),
#     leading code for away teams ("dk Denmark").
df["Home"] = df["Home"].str.replace(r"\s+[a-z]{2,3}$", "", regex=True).str.strip()
df["Away"] = df["Away"].str.replace(r"^[a-z]{2,3}\s+", "", regex=True).str.strip()

# 3. Enforce types: attendance as integer, date as datetime.
df["Attendance"] = df["Attendance"].astype(int)
df["Date"] = pd.to_datetime(df["Date"])

# 4. Standardize the phase column with its business order
#    (tournament chronology, not alphabetical order).
df["Round"] = df["Round"].str.strip()
df["Round"] = pd.Categorical(df["Round"], categories=PHASE_ORDER, ordered=True)
df["phase_order"] = df["Round"].cat.codes + 1  # 1..5, lets Tableau sort correctly

# 5. Sort chronologically and assign a surrogate match_id (1..51).
df = df.sort_values(["Date", "Time"]).reset_index(drop=True)
df["match_id"] = df.index + 1

# 6. Join with the stadium dimension; indicator=True tags each row's
#    origin so we can detect orphan venues (typos, unmapped stadiums).
df = df.merge(
    stadiums[["stadium_id", "stadium_name_fbref", "capacity_euro2024"]],
    left_on="Venue", right_on="stadium_name_fbref",
    how="left", indicator=True,
)

# ---------- Validate (blocking checks) ----------
orphans = df[df["_merge"] != "both"]
assert len(df) == 51, f"Expected 51 matches, got {len(df)}"
assert orphans.empty, f"Orphan venues (no stadium match): {orphans['Venue'].unique()}"
assert df["Attendance"].notna().all(), "Null attendance found"
assert (df["Attendance"] > 0).all(), "Non-positive attendance found"
over_capacity = df[df["Attendance"] > df["capacity_euro2024"]]
assert over_capacity.empty, (
    "Attendance exceeds stadium capacity:\n"
    f"{over_capacity[['Date', 'Home', 'Away', 'Venue', 'Attendance', 'capacity_euro2024']]}"
)
assert df["Round"].notna().all(), "Unknown phase label found (check PHASE_ORDER)"
assert df["match_id"].is_unique, "Duplicate match_id"
print("All validation checks passed.")

# ---------- Export ----------
out = df[["match_id", "Date", "Round", "phase_order", "Home", "Away",
          "Score", "Attendance", "stadium_id"]].rename(columns={
    "Date": "match_date", "Round": "phase", "Home": "home_team",
    "Away": "away_team", "Score": "score", "Attendance": "attendance",
})
out.to_csv(OUTPUT_FILE, index=False)
print(f"File written: {OUTPUT_FILE} ({len(out)} rows)")

# Quick sanity summary: fill rate by venue (preview of the KPI to come).
summary = df.groupby("Venue").apply(
    lambda g: round(100 * g["Attendance"].sum() / (g["capacity_euro2024"].iloc[0] * len(g)), 1),
    include_groups=False,
).sort_values(ascending=False)
print("\nFill rate by venue (%):")
print(summary.to_string())