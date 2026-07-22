# UEFA EURO 2024, Ticketing & Attendance Analytics

End-to-end analytics pipeline: web-collected attendance data, Python validation, Snowflake star-schema modelling, SQL analytical views, interactive Tableau dashboard.

**[Live dashboard on Tableau Public](https://public.tableau.com/app/profile/elias.el.hamdaoui1383/viz/UEFAEURO2024TicketingAttendanceAnalytics/UEFAEURO2024TicketingAttendanceAnalytics)**

## Architecture

FBref (official attendances)
    → collect_fbref.py        (collection)
    → clean_data.py           (cleaning + blocking validation checks)
    → data/*.csv              (star-schema-ready files)
    → Snowflake               (FACT_MATCHES + DIM_STADIUMS, 4 SQL views)
    → exports/*.csv           (materialized views)
    → Tableau Public          (interactive dashboard)

## Data model

Star schema in Snowflake: one fact table, FACT_MATCHES (one row per match: attendance, score, phase, date, stadium foreign key), and one dimension table, DIM_STADIUMS (one row per stadium: capacity, city, names). Facts hold measurable events; dimensions hold descriptive attributes. A phase_order column encodes tournament chronology so downstream tools sort phases correctly.

## Data quality & engineering decisions

- **Cloudflare 403 on FBref.** Automated requests were blocked even with a
  browser user-agent. Rather than bypassing the bot protection, the page is
  saved manually from the browser and parsed locally, using the source's
  authorized access channel.
- **Stuttgart capacity conflict.** Wikipedia listed 51,000; all 5 Stuttgart
  matches recorded an identical attendance of 54,000. Five identical
  sell-outs indicate the real tournament capacity was 54,000, so the
  reference table was corrected to match the observed data, internal
  consistency arbitrated between conflicting sources.
- **Blocking validation checks** in clean_data.py, the script fails if any
  is violated: exactly 51 matches; no orphan venues after the stadium join;
  no null or non-positive attendance; no attendance above stadium capacity
  (this check caught the Stuttgart conflict); known phase labels only;
  unique match_id.
- **Rounding propagation.** CSV extracts carry per-match rates rounded to
  1 decimal, so re-averaging them can diverge up to 0.1pt from the exact
  SQL ratios. Inside Tableau, a row-level calculated field
  (100 * attendance / capacity) restores exact computation; the extract
  limitation is known and accepted.

## Analytical views

- **V_STADIUM_UTILIZATION** per-stadium fill rate, total attendance and
  sell-out count (threshold: ≥99.5% of capacity).
- **V_PHASE_TRENDS** average attendance and fill rate per tournament
  phase, in chronological order.
- **V_ATTENDANCE_ANOMALIES** per-match z-score computed with window
  functions (AVG/STDDEV OVER PARTITION BY stadium): each match is compared
  to its own stadium's norm, not the global average. Stuttgart's five
  identical sell-outs yield zero variance, NULLIF guards the division.
- **V_TEAM_DRAW** per-team average fill rate; a UNION ALL unpivot makes
  each match count once per team.

Note: Tableau's {FIXED} LOD expressions used in the dashboard are the
direct equivalent of SQL window functions (PARTITION BY), same per-group
aggregation logic, implemented once in each layer.

## Dashboard design decisions

- **Axes truncated to 90–101%.** All fill rates sit between 92 and 100; a
  0-based axis would render every bar visually identical. The truncation
  is stated on the dashboard.
- **Fill rate over raw attendance.** Raw attendance follows stadium size
  (Poland out-drew Germany in absolute numbers only because it played in
  bigger stadiums). Fill rate controls for capacity and is used as the
  ranking measure everywhere; raw attendance stays in tooltips.
- **Diverging palette centered on zero** for anomaly deviations, the
  orange/blue flip matches the business zero (below/above the stadium's
  norm), not the midpoint of the data range.
- **ATTR aggregation** on row-unique values as a granularity guard: it
  displays "*" if duplicates ever appear instead of silently aggregating.
- **Anomalies table sorted by absolute deviation** so the most abnormal
  matches (the final, low-draw group games) surface at the top.
- **Cross-filters** on Stadium Utilization and Phase Trends. Team Draw is
  excluded: it is built on a pre-aggregated extract (stadium detail is
  lost) and team filtering would need to match two fields (home/away),
  documented trade-off rather than a partial implementation.

## Limitations & production notes

- Tableau Public has no native Snowflake connector → the dashboard reads
  CSV extracts of the views (see sql/export.sql). Production setup:
  direct live or scheduled-extract connection to the views.
- Data was loaded through the UI (one-shot); recurring loads would use
  stages + COPY INTO.
- Attendance is a public proxy for ticket usage; real ticketing data
  (sales, transfers, activations) is not public. The pipeline and the
  anomaly logic transfer directly to such data.

## Reproducing

1. `python -m venv .venv`, activate it, `pip install -r requirements.txt`.
2. Open the FBref EURO 2024 fixtures page in a browser and save it as
   `fbref_euro2024.html` (HTML only) in the project root, manual save is
   required because of Cloudflare bot protection.
3. `python collect_fbref.py`, then `python clean_data.py`.
4. On any Snowflake trial: run `sql/setup_snowflake.sql`, load
   `data/stadiums.csv` then `data/matches.csv` via the UI, run
   `sql/export.sql` and download each result as CSV.
5. Point Tableau at `exports/matches_enriched.csv` (main source) and
   `exports/team_draw.csv`.