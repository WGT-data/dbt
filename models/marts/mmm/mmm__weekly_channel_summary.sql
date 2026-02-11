{{ config(
    materialized='table',
    tags=['mmm', 'mart', 'summary', 'weekly']
) }}

-- mmm__weekly_channel_summary.sql
-- Weekly rollup of daily channel summary for MMM tools preferring weekly data
-- Some MMM implementations (especially with limited history) work better at weekly grain
-- Grain: one row per WEEK_START_DATE + PLATFORM + CHANNEL

SELECT
    DATE_TRUNC('week', DATE) AS WEEK_START_DATE,
    PLATFORM,
    CHANNEL,

    -- Spend metrics (sum over week)
    SUM(SPEND) AS SPEND,
    SUM(IMPRESSIONS) AS IMPRESSIONS,
    SUM(CLICKS) AS CLICKS,
    SUM(PAID_INSTALLS_SUPERMETRICS) AS PAID_INSTALLS_SUPERMETRICS,

    -- Install metrics (sum over week)
    SUM(INSTALLS) AS INSTALLS,

    -- Revenue metrics (sum over week)
    SUM(REVENUE) AS REVENUE,
    SUM(ALL_REVENUE) AS ALL_REVENUE,
    SUM(AD_REVENUE) AS AD_REVENUE,
    SUM(INSTALLS_API) AS INSTALLS_API,

    -- Weekly KPIs (recomputed, not averaged)
    CASE WHEN SUM(INSTALLS) > 0
         THEN SUM(SPEND) / SUM(INSTALLS)
         ELSE NULL
    END AS CPI,

    CASE WHEN SUM(SPEND) > 0
         THEN SUM(REVENUE) / SUM(SPEND)
         ELSE NULL
    END AS ROAS,

    CASE WHEN SUM(SPEND) > 0
         THEN SUM(ALL_REVENUE) / SUM(SPEND)
         ELSE NULL
    END AS ALL_ROAS,

    -- Data coverage for the week
    SUM(HAS_SPEND_DATA) AS DAYS_WITH_SPEND,
    SUM(HAS_INSTALL_DATA) AS DAYS_WITH_INSTALLS,
    SUM(HAS_REVENUE_DATA) AS DAYS_WITH_REVENUE,
    COUNT(*) AS DAYS_IN_WEEK

FROM {{ ref('mmm__daily_channel_summary') }}
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 2, 3
