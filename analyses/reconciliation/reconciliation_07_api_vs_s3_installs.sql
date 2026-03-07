-- reconciliation_07_api_vs_s3_installs.sql
-- Compares Adjust API installs (pre-aggregated, includes reinstalls) vs
-- S3 device-level installs (first install per device only).
--
-- Expected: API > S3 always. PCT_DELTA shows reinstall inflation rate.
-- Typical delta is 10-30%. If delta is negative, S3 dedup may have issues.

WITH api AS (
    SELECT
        DATE,
        SUM(INSTALLS) AS API_INSTALLS
    FROM {{ ref('stg_adjust__report_daily') }}
    WHERE DATE >= '2025-01-01'
      AND PLATFORM IN ('iOS', 'Android')
    GROUP BY 1
),

s3 AS (
    SELECT
        DATE(INSTALL_TIMESTAMP) AS DATE,
        COUNT(DISTINCT DEVICE_ID) AS S3_INSTALLS
    FROM {{ ref('v_stg_adjust__installs') }}
    WHERE DATE(INSTALL_TIMESTAMP) >= '2025-01-01'
    GROUP BY 1
)

SELECT
    a.DATE,
    a.API_INSTALLS,
    s.S3_INSTALLS,
    a.API_INSTALLS - s.S3_INSTALLS AS DELTA,
    (a.API_INSTALLS - s.S3_INSTALLS)::FLOAT / NULLIF(a.API_INSTALLS, 0) AS PCT_DELTA
FROM api a
FULL OUTER JOIN s3 s ON a.DATE = s.DATE
ORDER BY 1 DESC
