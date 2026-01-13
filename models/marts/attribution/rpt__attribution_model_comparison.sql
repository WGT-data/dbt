-- rpt__attribution_model_comparison.sql
-- DASHBOARD-READY: Side-by-side comparison of Last-Touch (current) vs Multi-Touch Attribution
-- Use this to evaluate which attribution model to adopt
--
-- Grain: One row per AD_PARTNER + PLATFORM + DATE

{{
    config(
        materialized='incremental',
        unique_key=['AD_PARTNER', 'PLATFORM', 'DATE'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        tags=['dashboard', 'attribution']
    )
}}

-- Current Last-Touch Attribution (from existing models)
WITH current_attribution AS (
    SELECT AD_PARTNER
         , PLATFORM
         , DATE
         , SUM(COST) AS COST
         , SUM(ATTRIBUTION_INSTALLS) AS INSTALLS_CURRENT
         , SUM(REVENUE) AS REVENUE_CURRENT
         , SUM(PURCHASERS) AS PURCHASERS_CURRENT
    FROM {{ ref('attribution__campaign_performance') }}
    {% if is_incremental() %}
        WHERE DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3
)

-- New Multi-Touch Attribution
, mta_attribution AS (
    SELECT AD_PARTNER
         , PLATFORM
         , DATE
         , SUM(INSTALLS_LAST_TOUCH) AS MTA_INSTALLS_LAST_TOUCH
         , SUM(INSTALLS_FIRST_TOUCH) AS MTA_INSTALLS_FIRST_TOUCH
         , SUM(INSTALLS_LINEAR) AS MTA_INSTALLS_LINEAR
         , SUM(INSTALLS_TIME_DECAY) AS MTA_INSTALLS_TIME_DECAY
         , SUM(INSTALLS_POSITION_BASED) AS MTA_INSTALLS_POSITION_BASED
         , SUM(D7_REVENUE_TIME_DECAY) AS MTA_D7_REVENUE_TIME_DECAY
         , SUM(D30_REVENUE_TIME_DECAY) AS MTA_D30_REVENUE_TIME_DECAY
         , SUM(TOTAL_REVENUE_TIME_DECAY) AS MTA_TOTAL_REVENUE_TIME_DECAY
         , SUM(D7_REVENUE_LAST_TOUCH) AS MTA_D7_REVENUE_LAST_TOUCH
         , SUM(D30_REVENUE_LAST_TOUCH) AS MTA_D30_REVENUE_LAST_TOUCH
    FROM {{ ref('mta__campaign_performance') }}
    {% if is_incremental() %}
        WHERE DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3
)

-- Join current vs MTA
, combined AS (
    SELECT COALESCE(c.AD_PARTNER, m.AD_PARTNER) AS AD_PARTNER
         , COALESCE(c.PLATFORM, m.PLATFORM) AS PLATFORM
         , COALESCE(c.DATE, m.DATE) AS DATE

         -- Spend (same for both)
         , COALESCE(c.COST, 0) AS COST

         -- =============================================
         -- CURRENT MODEL (Last-Touch via Adjust)
         -- =============================================
         , COALESCE(c.INSTALLS_CURRENT, 0) AS INSTALLS_CURRENT
         , COALESCE(c.REVENUE_CURRENT, 0) AS REVENUE_CURRENT
         , COALESCE(c.PURCHASERS_CURRENT, 0) AS PURCHASERS_CURRENT

         -- =============================================
         -- MTA MODELS
         -- =============================================
         , COALESCE(m.MTA_INSTALLS_LAST_TOUCH, 0) AS MTA_INSTALLS_LAST_TOUCH
         , COALESCE(m.MTA_INSTALLS_FIRST_TOUCH, 0) AS MTA_INSTALLS_FIRST_TOUCH
         , COALESCE(m.MTA_INSTALLS_LINEAR, 0) AS MTA_INSTALLS_LINEAR
         , COALESCE(m.MTA_INSTALLS_TIME_DECAY, 0) AS MTA_INSTALLS_TIME_DECAY
         , COALESCE(m.MTA_INSTALLS_POSITION_BASED, 0) AS MTA_INSTALLS_POSITION_BASED

         -- MTA Revenue
         , COALESCE(m.MTA_D7_REVENUE_TIME_DECAY, 0) AS MTA_D7_REVENUE_TIME_DECAY
         , COALESCE(m.MTA_D30_REVENUE_TIME_DECAY, 0) AS MTA_D30_REVENUE_TIME_DECAY
         , COALESCE(m.MTA_TOTAL_REVENUE_TIME_DECAY, 0) AS MTA_TOTAL_REVENUE_TIME_DECAY
         , COALESCE(m.MTA_D7_REVENUE_LAST_TOUCH, 0) AS MTA_D7_REVENUE_LAST_TOUCH
         , COALESCE(m.MTA_D30_REVENUE_LAST_TOUCH, 0) AS MTA_D30_REVENUE_LAST_TOUCH

    FROM current_attribution c
    FULL OUTER JOIN mta_attribution m
        ON c.AD_PARTNER = m.AD_PARTNER
        AND c.PLATFORM = m.PLATFORM
        AND c.DATE = m.DATE
)

SELECT *
     -- =============================================
     -- CURRENT MODEL METRICS
     -- =============================================
     , IFF(INSTALLS_CURRENT > 0, COST / INSTALLS_CURRENT, NULL) AS CPI_CURRENT
     , IFF(COST > 0, REVENUE_CURRENT / COST, NULL) AS ROAS_CURRENT

     -- =============================================
     -- MTA TIME-DECAY METRICS (Recommended)
     -- =============================================
     , IFF(MTA_INSTALLS_TIME_DECAY > 0, COST / MTA_INSTALLS_TIME_DECAY, NULL) AS CPI_TIME_DECAY
     , IFF(COST > 0, MTA_D7_REVENUE_TIME_DECAY / COST, NULL) AS D7_ROAS_TIME_DECAY
     , IFF(COST > 0, MTA_D30_REVENUE_TIME_DECAY / COST, NULL) AS D30_ROAS_TIME_DECAY
     , IFF(COST > 0, MTA_TOTAL_REVENUE_TIME_DECAY / COST, NULL) AS ROAS_TIME_DECAY

     -- =============================================
     -- COMPARISON METRICS: Current vs Time-Decay
     -- =============================================
     -- Install difference (positive = MTA gives MORE credit)
     , MTA_INSTALLS_TIME_DECAY - INSTALLS_CURRENT AS INSTALL_DIFF_VS_CURRENT

     -- Percentage difference in installs
     , IFF(INSTALLS_CURRENT > 0,
           (MTA_INSTALLS_TIME_DECAY - INSTALLS_CURRENT) / INSTALLS_CURRENT * 100,
           NULL) AS INSTALL_DIFF_PCT

     -- CPI difference (negative = MTA shows LOWER CPI / better efficiency)
     , IFF(MTA_INSTALLS_TIME_DECAY > 0 AND INSTALLS_CURRENT > 0,
           (COST / MTA_INSTALLS_TIME_DECAY) - (COST / INSTALLS_CURRENT),
           NULL) AS CPI_DIFF_VS_CURRENT

     -- ROAS difference (positive = MTA shows HIGHER ROAS / better performance)
     , IFF(COST > 0,
           (MTA_TOTAL_REVENUE_TIME_DECAY / COST) - (REVENUE_CURRENT / COST),
           NULL) AS ROAS_DIFF_VS_CURRENT

FROM combined
WHERE DATE IS NOT NULL
ORDER BY DATE DESC, COST DESC
