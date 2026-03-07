-- reconciliation_06_cross_mart_installs.sql
-- Cross-mart install comparison: surfaces discrepancies between 6 install definitions.
--
-- Expected relationships:
--   EXEC_API_INSTALLS > MMM_S3_SKAN (API includes reinstalls)
--   EXEC_ATTRIBUTION < EXEC_API_INSTALLS (Amplitude requires SDK sync)
--   BIZ_INSTALLS = EXEC_API_INSTALLS (both use Adjust API)
--
-- Run alongside query 5.1 for a complete spend+installs picture.

WITH exec AS (
    SELECT
        DATE,
        SUM(ADJUST_INSTALLS) AS API,
        SUM(SKAN_INSTALLS) AS SKAN,
        SUM(ADJUST_INSTALLS + SKAN_INSTALLS) AS TOTAL,
        SUM(ATTRIBUTION_INSTALLS) AS ATTRIBUTION
    FROM {{ ref('mart_exec_summary') }}
    WHERE DATE >= '2025-01-01'
    GROUP BY 1
),

mmm AS (
    SELECT
        DATE,
        SUM(INSTALLS) AS S3_SKAN,
        SUM(INSTALLS_API) AS API
    FROM {{ ref('mmm__daily_channel_summary') }}
    WHERE DATE >= '2025-01-01'
    GROUP BY 1
),

biz AS (
    SELECT DATE, TOTAL_INSTALLS
    FROM {{ ref('mart_daily_business_overview') }}
    WHERE DATE >= '2025-01-01'
)

SELECT
    COALESCE(e.DATE, m.DATE, b.DATE) AS DATE,
    e.API AS EXEC_API_INSTALLS,
    e.SKAN AS EXEC_SKAN,
    e.TOTAL AS EXEC_TOTAL,
    e.ATTRIBUTION AS EXEC_ATTRIBUTION,
    m.S3_SKAN AS MMM_S3_SKAN,
    m.API AS MMM_API,
    b.TOTAL_INSTALLS AS BIZ_INSTALLS
FROM exec e
FULL OUTER JOIN mmm m ON e.DATE = m.DATE
FULL OUTER JOIN biz b ON e.DATE = b.DATE
ORDER BY 1 DESC
