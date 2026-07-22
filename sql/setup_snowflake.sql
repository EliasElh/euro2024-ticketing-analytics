-- ============================================================
-- Event Ticketing & Attendance Analytics — Snowflake setup
-- Step 3A: warehouse, database structure, load validation
-- ============================================================

-- Compute setup: XSMALL is ample for this volume; AUTO_SUSPEND = 60
-- shuts the warehouse down after 60 idle seconds (trial credit hygiene).
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

ALTER WAREHOUSE COMPUTE_WH SET AUTO_SUSPEND = 60;

USE WAREHOUSE COMPUTE_WH;

CREATE DATABASE IF NOT EXISTS TICKETING_ANALYTICS;
USE DATABASE TICKETING_ANALYTICS;

CREATE SCHEMA IF NOT EXISTS EURO2024;
USE SCHEMA EURO2024;

-- Dimension table: one row per stadium, descriptive attributes.
CREATE OR REPLACE TABLE DIM_STADIUMS (
    stadium_id            INTEGER      PRIMARY KEY,
    stadium_name_fbref    VARCHAR(100) NOT NULL,
    stadium_name_official VARCHAR(100) NOT NULL,
    city                  VARCHAR(50)  NOT NULL,
    capacity_euro2024     INTEGER      NOT NULL
);

-- Fact table: one row per match, measures + foreign keys.
-- Note: Snowflake stores PRIMARY KEY / REFERENCES constraints as model
-- documentation but does not enforce them (NOT NULL excepted) —
-- integrity is guaranteed upstream by the Python validation checks.
CREATE OR REPLACE TABLE FACT_MATCHES (
    match_id    INTEGER      PRIMARY KEY,
    match_date  DATE         NOT NULL,
    phase       VARCHAR(30)  NOT NULL,
    phase_order INTEGER      NOT NULL,
    home_team   VARCHAR(50)  NOT NULL,
    away_team   VARCHAR(50)  NOT NULL,
    score       VARCHAR(15),
    attendance  INTEGER      NOT NULL,
    stadium_id  INTEGER      NOT NULL REFERENCES DIM_STADIUMS(stadium_id)
);

-- ---------- Load validation ----------
SELECT COUNT(*) AS n_matches  FROM FACT_MATCHES;   -- expected: 51
SELECT COUNT(*) AS n_stadiums FROM DIM_STADIUMS;   -- expected: 10

-- Join integrity: every match must resolve to exactly one stadium.
SELECT COUNT(*) AS unmatched
FROM FACT_MATCHES f
LEFT JOIN DIM_STADIUMS s ON f.stadium_id = s.stadium_id
WHERE s.stadium_id IS NULL;                        -- expected: 0

-- Star schema in action: fill rate by stadium.
-- Must reproduce the Python summary (Stuttgart 100.0 on top, range 96–100).
SELECT
    s.stadium_name_official,
    s.city,
    COUNT(*)                                                AS matches_hosted,
    ROUND(100 * AVG(f.attendance / s.capacity_euro2024), 1) AS avg_fill_rate_pct
FROM FACT_MATCHES f
JOIN DIM_STADIUMS s ON f.stadium_id = s.stadium_id
GROUP BY s.stadium_name_official, s.city
ORDER BY avg_fill_rate_pct DESC;

-- ============================================================
-- Step 3B: analytical views (business logic layer for Tableau)
-- ============================================================

-- V1 — Stadium utilization: the core ops KPI.
CREATE OR REPLACE VIEW V_STADIUM_UTILIZATION AS
SELECT
    s.stadium_name_official,
    s.city,
    s.capacity_euro2024                                      AS capacity,
    COUNT(*)                                                 AS matches_hosted,
    SUM(f.attendance)                                        AS total_attendance,
    ROUND(100 * AVG(f.attendance / s.capacity_euro2024), 1)  AS avg_fill_rate_pct,
    SUM(CASE WHEN f.attendance >= s.capacity_euro2024 * 0.995
             THEN 1 ELSE 0 END)                              AS sellout_matches
FROM FACT_MATCHES f
JOIN DIM_STADIUMS s USING (stadium_id)
GROUP BY s.stadium_name_official, s.city, s.capacity_euro2024;

-- V2 — Fill rate by tournament phase: does demand rise in knockouts?
CREATE OR REPLACE VIEW V_PHASE_TRENDS AS
SELECT
    f.phase,
    f.phase_order,
    COUNT(*)                                                 AS matches,
    ROUND(AVG(f.attendance), 0)                              AS avg_attendance,
    ROUND(100 * AVG(f.attendance / s.capacity_euro2024), 1)  AS avg_fill_rate_pct
FROM FACT_MATCHES f
JOIN DIM_STADIUMS s USING (stadium_id)
GROUP BY f.phase, f.phase_order;

-- V3 — Attendance anomalies: matches whose fill rate deviates from
-- their stadium's norm. Z-score computed with window functions:
-- each match is compared to the mean/stddev of ITS OWN stadium,
-- not the global average (a 96% fill is normal in Berlin,
-- anomalous in Stuttgart where every match sold out).
CREATE OR REPLACE VIEW V_ATTENDANCE_ANOMALIES AS
WITH match_rates AS (
    SELECT
        f.match_id,
        f.match_date,
        f.phase,
        f.home_team,
        f.away_team,
        s.stadium_name_official,
        f.attendance,
        s.capacity_euro2024,
        f.attendance / s.capacity_euro2024                   AS fill_rate,
        AVG(f.attendance / s.capacity_euro2024)
            OVER (PARTITION BY f.stadium_id)                 AS stadium_avg_rate,
        STDDEV(f.attendance / s.capacity_euro2024)
            OVER (PARTITION BY f.stadium_id)                 AS stadium_stddev_rate
    FROM FACT_MATCHES f
    JOIN DIM_STADIUMS s USING (stadium_id)
)
SELECT
    match_id, match_date, phase, home_team, away_team,
    stadium_name_official,
    attendance,
    ROUND(100 * fill_rate, 1)                                AS fill_rate_pct,
    ROUND(100 * stadium_avg_rate, 1)                         AS stadium_avg_pct,
    ROUND((fill_rate - stadium_avg_rate)
          / NULLIF(stadium_stddev_rate, 0), 2)               AS z_score
FROM match_rates
ORDER BY ABS(z_score) DESC NULLS LAST;

-- V4 — Team draw: average attendance when a given team plays.
-- UNION ALL unpivots home/away so each match counts once per team.
CREATE OR REPLACE VIEW V_TEAM_DRAW AS
WITH team_matches AS (
    SELECT home_team AS team, attendance, stadium_id FROM FACT_MATCHES
    UNION ALL
    SELECT away_team AS team, attendance, stadium_id FROM FACT_MATCHES
)
SELECT
    t.team,
    COUNT(*)                                                 AS matches_played,
    ROUND(AVG(t.attendance), 0)                              AS avg_attendance,
    ROUND(100 * AVG(t.attendance / s.capacity_euro2024), 1)  AS avg_fill_rate_pct
FROM team_matches t
JOIN DIM_STADIUMS s USING (stadium_id)
GROUP BY t.team;

-- 3B validation

SELECT * FROM V_PHASE_TRENDS ORDER BY phase_order;
SELECT * FROM V_ATTENDANCE_ANOMALIES LIMIT 5;
SELECT * FROM V_TEAM_DRAW ORDER BY avg_attendance DESC LIMIT 5;