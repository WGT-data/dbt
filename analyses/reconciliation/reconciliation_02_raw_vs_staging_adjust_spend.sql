-- reconciliation_02_raw_vs_staging_adjust_spend.sql
-- Validates that stg_adjust__report_daily preserves raw Adjust API spend without loss or inflation.
--
-- Only rows with non-zero DELTA are returned.
-- A zero-row result means raw and staging match perfectly.

WITH raw AS (
    SELECT
        CAST(DAY AS DATE) AS DATE,
        SUM(COALESCE(NETWORK_COST, 0)) AS RAW_SPEND
    FROM ADJUST.API_DATA.REPORT_DAILY_RAW
    WHERE DAY >= '2025-01-01'
    GROUP BY 1
),

staging AS (
    SELECT
        DATE,
        SUM(NETWORK_COST) AS STG_SPEND
    FROM {{ ref('stg_adjust__report_daily') }}
    WHERE DATE >= '2025-01-01'
    GROUP BY 1
)

SELECT
    r.DATE,
    r.RAW_SPEND,
    s.STG_SPEND,
    r.RAW_SPEND - s.STG_SPEND AS DELTA
FROM raw r
FULL OUTER JOIN staging s ON r.DATE = s.DATE
WHERE ABS(COALESCE(r.RAW_SPEND, 0) - COALESCE(s.STG_SPEND, 0)) > 0.01
ORDER BY 1 DESC
