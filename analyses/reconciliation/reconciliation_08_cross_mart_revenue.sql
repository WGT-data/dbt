-- reconciliation_08_cross_mart_revenue.sql
-- Cross-mart revenue comparison: surfaces discrepancies between 4 revenue definitions.
--
-- Key differences to watch:
--   EXEC_TOTAL = Adjust API ALL_REVENUE (mobile, event-date) — definition R2
--   EXEC_D7 = Cohort D7 from WGT.EVENTS (mobile, install-date) — definition R4
--   BIZ_TOTAL = WGT.EVENTS all-platform (event-date) — definition R3
--   DESKTOP_WEB_REVENUE_DELTA = BIZ - EXEC = desktop + web revenue
--
-- Run alongside query 5.1 and 5.6 for the complete picture.

WITH exec AS (
    SELECT
        DATE,
        SUM(TOTAL_REVENUE) AS EXEC_TOTAL,
        SUM(TOTAL_PURCHASE_REVENUE) AS EXEC_PURCHASE,
        SUM(D7_REVENUE) AS EXEC_D7
    FROM {{ ref('mart_exec_summary') }}
    WHERE DATE >= '2025-01-01'
    GROUP BY 1
),

biz AS (
    SELECT
        DATE,
        TOTAL_REVENUE AS BIZ_TOTAL,
        PURCHASE_REVENUE AS BIZ_PURCHASE
    FROM {{ ref('mart_daily_business_overview') }}
    WHERE DATE >= '2025-01-01'
),

plat AS (
    SELECT
        DATE,
        SUM(TOTAL_REVENUE) AS PLAT_TOTAL
    FROM {{ ref('mart_daily_overview_by_platform') }}
    WHERE DATE >= '2025-01-01'
    GROUP BY 1
),

mmm AS (
    SELECT
        DATE,
        SUM(REVENUE) AS MMM_PURCHASE,
        SUM(ALL_REVENUE) AS MMM_ALL
    FROM {{ ref('mmm__daily_channel_summary') }}
    WHERE DATE >= '2025-01-01'
    GROUP BY 1
)

SELECT
    COALESCE(e.DATE, b.DATE) AS DATE,
    e.EXEC_TOTAL,       -- Adjust API ALL_REVENUE (mobile, event-date)
    e.EXEC_PURCHASE,    -- Adjust API REVENUE (mobile, event-date)
    e.EXEC_D7,          -- Cohort D7 from WGT.EVENTS (mobile, install-date)
    b.BIZ_TOTAL,        -- WGT.EVENTS all platforms (event-date)
    p.PLAT_TOTAL,       -- WGT.EVENTS by platform (event-date)
    m.MMM_ALL,          -- Adjust API ALL_REVENUE (mobile, event-date)
    b.BIZ_TOTAL - e.EXEC_TOTAL AS DESKTOP_WEB_REVENUE_DELTA
FROM exec e
FULL OUTER JOIN biz b ON e.DATE = b.DATE
FULL OUTER JOIN plat p ON e.DATE = p.DATE
FULL OUTER JOIN mmm m ON e.DATE = m.DATE
ORDER BY 1 DESC
