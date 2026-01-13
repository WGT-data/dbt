-- rpt__attribution_weekly_summary.sql
-- DASHBOARD-READY: Weekly summary comparing attribution models
-- Perfect for executive dashboards and weekly reporting
--
-- Grain: One row per AD_PARTNER + PLATFORM + WEEK

{{
    config(
        materialized='incremental',
        unique_key=['AD_PARTNER', 'PLATFORM', 'WEEK_START'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        tags=['dashboard', 'attribution', 'weekly']
    )
}}

WITH daily_comparison AS (
    SELECT *
         , DATE_TRUNC('week', DATE) AS WEEK_START
    FROM {{ ref('rpt__attribution_model_comparison') }}
    {% if is_incremental() %}
        WHERE DATE >= DATEADD(week, -2, (SELECT MAX(WEEK_START) FROM {{ this }}))
    {% endif %}
)

, weekly_aggregated AS (
    SELECT AD_PARTNER
         , PLATFORM
         , WEEK_START

         -- Spend
         , SUM(COST) AS COST

         -- Current Model
         , SUM(INSTALLS_CURRENT) AS INSTALLS_CURRENT
         , SUM(REVENUE_CURRENT) AS REVENUE_CURRENT

         -- MTA Models
         , SUM(MTA_INSTALLS_LAST_TOUCH) AS MTA_INSTALLS_LAST_TOUCH
         , SUM(MTA_INSTALLS_FIRST_TOUCH) AS MTA_INSTALLS_FIRST_TOUCH
         , SUM(MTA_INSTALLS_LINEAR) AS MTA_INSTALLS_LINEAR
         , SUM(MTA_INSTALLS_TIME_DECAY) AS MTA_INSTALLS_TIME_DECAY
         , SUM(MTA_INSTALLS_POSITION_BASED) AS MTA_INSTALLS_POSITION_BASED

         -- MTA Revenue
         , SUM(MTA_D7_REVENUE_TIME_DECAY) AS MTA_D7_REVENUE
         , SUM(MTA_D30_REVENUE_TIME_DECAY) AS MTA_D30_REVENUE
         , SUM(MTA_TOTAL_REVENUE_TIME_DECAY) AS MTA_TOTAL_REVENUE

    FROM daily_comparison
    GROUP BY 1, 2, 3
)

SELECT AD_PARTNER
     , PLATFORM
     , WEEK_START
     , DATEADD(day, 6, WEEK_START) AS WEEK_END
     , COST

     -- =============================================
     -- INSTALL COMPARISON
     -- =============================================
     , INSTALLS_CURRENT
     , MTA_INSTALLS_TIME_DECAY AS INSTALLS_MTA_RECOMMENDED
     , MTA_INSTALLS_TIME_DECAY - INSTALLS_CURRENT AS INSTALL_VARIANCE
     , IFF(INSTALLS_CURRENT > 0,
           ROUND((MTA_INSTALLS_TIME_DECAY - INSTALLS_CURRENT) / INSTALLS_CURRENT * 100, 1),
           NULL) AS INSTALL_VARIANCE_PCT

     -- =============================================
     -- CPI COMPARISON
     -- =============================================
     , IFF(INSTALLS_CURRENT > 0, ROUND(COST / INSTALLS_CURRENT, 2), NULL) AS CPI_CURRENT
     , IFF(MTA_INSTALLS_TIME_DECAY > 0, ROUND(COST / MTA_INSTALLS_TIME_DECAY, 2), NULL) AS CPI_MTA_RECOMMENDED
     , IFF(INSTALLS_CURRENT > 0 AND MTA_INSTALLS_TIME_DECAY > 0,
           ROUND((COST / MTA_INSTALLS_TIME_DECAY) - (COST / INSTALLS_CURRENT), 2),
           NULL) AS CPI_VARIANCE

     -- =============================================
     -- REVENUE COMPARISON
     -- =============================================
     , REVENUE_CURRENT
     , MTA_TOTAL_REVENUE AS REVENUE_MTA_RECOMMENDED
     , MTA_D7_REVENUE
     , MTA_D30_REVENUE

     -- =============================================
     -- ROAS COMPARISON
     -- =============================================
     , IFF(COST > 0, ROUND(REVENUE_CURRENT / COST, 2), NULL) AS ROAS_CURRENT
     , IFF(COST > 0, ROUND(MTA_TOTAL_REVENUE / COST, 2), NULL) AS ROAS_MTA_RECOMMENDED
     , IFF(COST > 0, ROUND(MTA_D7_REVENUE / COST, 2), NULL) AS D7_ROAS_MTA
     , IFF(COST > 0, ROUND(MTA_D30_REVENUE / COST, 2), NULL) AS D30_ROAS_MTA

     -- =============================================
     -- ALL MTA MODELS (for detailed analysis)
     -- =============================================
     , MTA_INSTALLS_LAST_TOUCH
     , MTA_INSTALLS_FIRST_TOUCH
     , MTA_INSTALLS_LINEAR
     , MTA_INSTALLS_POSITION_BASED

     -- =============================================
     -- NETWORK CHARACTERIZATION
     -- Shows if network is better at prospecting or retargeting
     -- =============================================
     , IFF(MTA_INSTALLS_LAST_TOUCH > 0,
           ROUND((MTA_INSTALLS_FIRST_TOUCH - MTA_INSTALLS_LAST_TOUCH) / MTA_INSTALLS_LAST_TOUCH * 100, 1),
           NULL) AS PROSPECTING_INDEX
     -- Positive = better at prospecting/awareness
     -- Negative = better at retargeting/conversion

FROM weekly_aggregated
WHERE WEEK_START IS NOT NULL
ORDER BY WEEK_START DESC, COST DESC
