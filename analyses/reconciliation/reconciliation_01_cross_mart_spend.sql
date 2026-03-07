-- reconciliation_01_cross_mart_spend.sql
-- Cross-mart spend comparison: surfaces discrepancies between 4 different spend definitions.
--
-- Expected behavior:
--   EXEC_SPEND = BIZ_SPEND (both use Adjust API only)
--   PLAT_SPEND > EXEC_SPEND (includes desktop Fivetran spend)
--   DESKTOP_SPEND_DELTA = Fivetran FB + Google spend
--   ADJUST_VS_UNIFIED_DELTA shows dedup impact (positive = Adjust has more)
--
-- Run first — this is the top-level spend reconciliation.

WITH exec AS (
    SELECT DATE, SUM(COST) AS EXEC_SPEND
    FROM {{ ref('mart_exec_summary') }}
    WHERE DATE >= '2025-01-01'
    GROUP BY 1
),

biz AS (
    SELECT DATE, TOTAL_SPEND AS BIZ_SPEND
    FROM {{ ref('mart_daily_business_overview') }}
    WHERE DATE >= '2025-01-01'
),

plat AS (
    SELECT DATE, SUM(COST) AS PLAT_SPEND
    FROM {{ ref('mart_daily_overview_by_platform') }}
    WHERE DATE >= '2025-01-01'
    GROUP BY 1
),

mmm AS (
    SELECT DATE, SUM(SPEND) AS MMM_SPEND
    FROM {{ ref('mmm__daily_channel_summary') }}
    WHERE DATE >= '2025-01-01'
    GROUP BY 1
)

SELECT
    COALESCE(e.DATE, b.DATE, p.DATE, m.DATE) AS DATE,
    e.EXEC_SPEND,       -- Adjust API only
    b.BIZ_SPEND,        -- Adjust API only
    p.PLAT_SPEND,       -- Adjust + Fivetran FB + Google (no dedup)
    m.MMM_SPEND,        -- Unified deduped
    p.PLAT_SPEND - e.EXEC_SPEND AS DESKTOP_SPEND_DELTA,
    e.EXEC_SPEND - m.MMM_SPEND AS ADJUST_VS_UNIFIED_DELTA
FROM exec e
FULL OUTER JOIN biz b ON e.DATE = b.DATE
FULL OUTER JOIN plat p ON e.DATE = p.DATE
FULL OUTER JOIN mmm m ON e.DATE = m.DATE
ORDER BY 1 DESC
