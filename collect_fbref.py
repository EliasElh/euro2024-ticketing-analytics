"""
collect_fbref.py — Parses UEFA EURO 2024 match data from a locally saved
FBref page (FBref blocks automated HTTP access via Cloudflare, so the page
is downloaded manually through the browser — using the source's own
authorized access channel rather than bypassing its bot protection).
Step 2.1 of the Event Ticketing & Attendance Analytics project.
Input : fbref_euro2024.html (saved manually from the browser, Ctrl+S)
Output: euro2024_matches_raw.csv (raw data, cleaning happens in step 2.3)
"""

import pandas as pd
from pathlib import Path

HTML_FILE = Path("fbref_euro2024.html")

if not HTML_FILE.exists():
    raise FileNotFoundError(
        f"{HTML_FILE} not found. Open the FBref EURO 2024 fixtures page "
        "in a browser and save it (Ctrl+S, 'HTML only') into this folder."
    )

# read_html parses every <table> in the file -> list of DataFrames.
tables = pd.read_html(HTML_FILE)
print(f"Number of tables found in the file: {len(tables)}")

# Identify the schedule table: the one containing
# the Home, Away and Attendance columns.
schedule = None
for i, t in enumerate(tables):
    cols = [str(c) for c in t.columns]
    if "Home" in cols and "Away" in cols and "Attendance" in cols:
        schedule = t
        print(f"Schedule table identified: index {i}, {len(t)} rows")
        break

if schedule is None:
    raise ValueError(
        "Schedule table not found. Check that the saved page displays "
        "EURO 2024 and inspect the column lists of the tables found."
    )

print("\nColumns:", list(schedule.columns))
print("\nPreview of the first 5 rows:")
print(schedule.head())
print(f"\nTotal rows (raw, including separator rows): {len(schedule)}")
print(f"Rows with a recorded attendance: {schedule['Attendance'].notna().sum()}")

schedule.to_csv("euro2024_matches_raw.csv", index=False)
print("\nFile written: euro2024_matches_raw.csv")