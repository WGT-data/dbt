-- reconciliation_09_adjust_vs_wgt_revenue.sql
-- Compares Adjust API revenue vs WGT.EVENTS.REVENUE for mobile platforms only.
--
-- This isolates the difference between the two revenue raw sources
-- (Adjust API vs direct event table) on the same platform scope.
-- Helps determine if Adjust API revenue lags or leads the event table.

WITH adjust AS (
    SELECT
        DATE,
        SUM(REVENUE) AS ADJ_PURCHASE,
        SUM(ALL_REVENUE) AS ADJ_ALL,
        SUM(AD_REVENUE) AS ADJ_AD
    FROM {{ ref('stg_adjust__report_daily') }}
    WHERE DATE >= '2025-01-01'
      AND PLATFORM IN ('iOS', 'Android')
    GROUP BY 1
),

events AS (
    SELECT
        DATE(EVENTTIME) AS DATE,
        SUM(REVENUE) AS EVT_TOTAL,
        SUM(CASE WHEN REVENUETYPE = 'direct' THEN REVENUE END) AS EVT_PURCHASE,
        SUM(CASE WHEN REVENUETYPE = 'indirect' THEN REVENUE END) AS EVT_AD
    FROM WGT.EVENTS.REVENUE
    WHERE PLATFORM IN ('iOS', 'Android')
      AND DATE(EVENTTIME) >= '2025-01-01'
    GROUP BY 1
)

SELECT
    COALESCE(a.DATE, e.DATE) AS DATE,
    a.ADJ_ALL,
    e.EVT_TOTAL,
    a.ADJ_ALL - e.EVT_TOTAL AS ALL_REV_DELTA,
    a.ADJ_PURCHASE,
    e.EVT_PURCHASE,
    a.ADJ_PURCHASE - e.EVT_PURCHASE AS PURCHASE_DELTA
FROM adjust a
FULL OUTER JOIN events e ON a.DATE = e.DATE
ORDER BY 1 DESC
