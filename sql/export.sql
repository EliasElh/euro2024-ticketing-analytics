-- ============================================================
-- export.sql — Materializes the analytical views as CSV extracts
-- for Tableau Public (no native Snowflake connector on Public).
-- Run each SELECT, then download the result via the results
-- panel (↓ → Download as CSV).
-- ============================================================

USE WAREHOUSE COMPUTE_WH;
USE DATABASE TICKETING_ANALYTICS;
USE SCHEMA EURO2024;

-- Export 1 → stadium_utilization.csv
SELECT * FROM V_STADIUM_UTILIZATION;

-- Export 2 → phase_trends.csv
SELECT * FROM V_PHASE_TRENDS ORDER BY phase_order;

-- Export 3 → attendance_anomalies.csv
SELECT * FROM V_ATTENDANCE_ANOMALIES;

-- Export 4 → team_draw.csv
SELECT * FROM V_TEAM_DRAW ORDER BY avg_fill_rate_pct DESC;

-- Export 5 → matches_enriched.csv (main Tableau data source:
-- finest grain, lets Tableau re-aggregate under interactive filters)
SELECT
    f.match_id, f.match_date, f.phase, f.phase_order,
    f.home_team, f.away_team, f.score, f.attendance,
    s.stadium_name_official, s.city, s.capacity_euro2024,
    ROUND(100 * f.attendance / s.capacity_euro2024, 1) AS fill_rate_pct
FROM FACT_MATCHES f
JOIN DIM_STADIUMS s USING (stadium_id)
ORDER BY f.match_id;