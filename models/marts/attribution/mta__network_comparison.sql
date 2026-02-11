-- ============================================================================
-- LIMITATION NOTICE (documented Phase 3, 2026-02)
--
-- This model is part of the Multi-Touch Attribution (MTA) pipeline.
-- Phase 2 audit (Feb 2026) found that MTA has structural coverage limitations:
--   - Android: 0% device match rate (Amplitude SDK uses random UUID, not GPS_ADID)
--   - iOS IDFA: 7.37% availability (Apple ATT framework)
--   - SANs (Meta, Google, Apple, TikTok): 0% touchpoint data (never shared)
--
-- This model is PRESERVED for iOS tactical analysis only.
-- For strategic budget allocation, use MMM models in marts/mmm/.
--
-- To fix Android: Amplitude SDK must be configured with useAdvertisingIdForDeviceId()
-- See: .planning/phases/03-device-id-normalization-fix/mta-limitations.md
-- ============================================================================

-- mta__network_comparison.sql
-- High-level comparison of attribution models by ad network
-- Use this to see which networks gain or lose credit under different models
-- Helps identify prospecting vs retargeting effectiveness
--
-- Grain: One row per AD_PARTNER + PLATFORM + DATE

{{
    config(
        materialized='incremental',
        unique_key=['AD_PARTNER', 'PLATFORM', 'DATE'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        tags=['mta', 'attribution', 'mart']
    )
}}

WITH campaign_performance AS (
    SELECT *
    FROM {{ ref('mta__campaign_performance') }}
    {% if is_incremental() %}
        WHERE DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
)

-- Aggregate to network level
, network_aggregated AS (
    SELECT AD_PARTNER
         , PLATFORM
         , DATE

         -- Spend
         , SUM(COST) AS COST
         , SUM(CLICKS) AS CLICKS
         , SUM(IMPRESSIONS) AS IMPRESSIONS

         -- Installs by model
         , SUM(INSTALLS_LAST_TOUCH) AS INSTALLS_LAST_TOUCH
         , SUM(INSTALLS_FIRST_TOUCH) AS INSTALLS_FIRST_TOUCH
         , SUM(INSTALLS_LINEAR) AS INSTALLS_LINEAR
         , SUM(INSTALLS_TIME_DECAY) AS INSTALLS_TIME_DECAY
         , SUM(INSTALLS_POSITION_BASED) AS INSTALLS_POSITION_BASED
         , SUM(INSTALLS_RECOMMENDED) AS INSTALLS_RECOMMENDED

         -- D7 Revenue by model
         , SUM(D7_REVENUE_LAST_TOUCH) AS D7_REVENUE_LAST_TOUCH
         , SUM(D7_REVENUE_FIRST_TOUCH) AS D7_REVENUE_FIRST_TOUCH
         , SUM(D7_REVENUE_LINEAR) AS D7_REVENUE_LINEAR
         , SUM(D7_REVENUE_TIME_DECAY) AS D7_REVENUE_TIME_DECAY
         , SUM(D7_REVENUE_POSITION_BASED) AS D7_REVENUE_POSITION_BASED
         , SUM(D7_REVENUE_RECOMMENDED) AS D7_REVENUE_RECOMMENDED

         -- D30 Revenue by model
         , SUM(D30_REVENUE_LAST_TOUCH) AS D30_REVENUE_LAST_TOUCH
         , SUM(D30_REVENUE_FIRST_TOUCH) AS D30_REVENUE_FIRST_TOUCH
         , SUM(D30_REVENUE_LINEAR) AS D30_REVENUE_LINEAR
         , SUM(D30_REVENUE_TIME_DECAY) AS D30_REVENUE_TIME_DECAY
         , SUM(D30_REVENUE_POSITION_BASED) AS D30_REVENUE_POSITION_BASED
         , SUM(D30_REVENUE_RECOMMENDED) AS D30_REVENUE_RECOMMENDED

         -- Total Revenue by model
         , SUM(TOTAL_REVENUE_LAST_TOUCH) AS TOTAL_REVENUE_LAST_TOUCH
         , SUM(TOTAL_REVENUE_FIRST_TOUCH) AS TOTAL_REVENUE_FIRST_TOUCH
         , SUM(TOTAL_REVENUE_LINEAR) AS TOTAL_REVENUE_LINEAR
         , SUM(TOTAL_REVENUE_TIME_DECAY) AS TOTAL_REVENUE_TIME_DECAY
         , SUM(TOTAL_REVENUE_POSITION_BASED) AS TOTAL_REVENUE_POSITION_BASED
         , SUM(TOTAL_REVENUE_RECOMMENDED) AS TOTAL_REVENUE_RECOMMENDED

         , SUM(UNIQUE_DEVICES) AS UNIQUE_DEVICES

    FROM campaign_performance
    GROUP BY 1, 2, 3
)

SELECT *
     -- =============================================
     -- CPI BY MODEL
     -- =============================================
     , IFF(INSTALLS_LAST_TOUCH > 0, COST / INSTALLS_LAST_TOUCH, NULL) AS CPI_LAST_TOUCH
     , IFF(INSTALLS_FIRST_TOUCH > 0, COST / INSTALLS_FIRST_TOUCH, NULL) AS CPI_FIRST_TOUCH
     , IFF(INSTALLS_LINEAR > 0, COST / INSTALLS_LINEAR, NULL) AS CPI_LINEAR
     , IFF(INSTALLS_TIME_DECAY > 0, COST / INSTALLS_TIME_DECAY, NULL) AS CPI_TIME_DECAY
     , IFF(INSTALLS_POSITION_BASED > 0, COST / INSTALLS_POSITION_BASED, NULL) AS CPI_POSITION_BASED
     , IFF(INSTALLS_RECOMMENDED > 0, COST / INSTALLS_RECOMMENDED, NULL) AS CPI_RECOMMENDED

     -- =============================================
     -- D7 ROAS BY MODEL
     -- =============================================
     , IFF(COST > 0, D7_REVENUE_LAST_TOUCH / COST, NULL) AS D7_ROAS_LAST_TOUCH
     , IFF(COST > 0, D7_REVENUE_FIRST_TOUCH / COST, NULL) AS D7_ROAS_FIRST_TOUCH
     , IFF(COST > 0, D7_REVENUE_LINEAR / COST, NULL) AS D7_ROAS_LINEAR
     , IFF(COST > 0, D7_REVENUE_TIME_DECAY / COST, NULL) AS D7_ROAS_TIME_DECAY
     , IFF(COST > 0, D7_REVENUE_POSITION_BASED / COST, NULL) AS D7_ROAS_POSITION_BASED
     , IFF(COST > 0, D7_REVENUE_RECOMMENDED / COST, NULL) AS D7_ROAS_RECOMMENDED

     -- =============================================
     -- D30 ROAS BY MODEL
     -- =============================================
     , IFF(COST > 0, D30_REVENUE_LAST_TOUCH / COST, NULL) AS D30_ROAS_LAST_TOUCH
     , IFF(COST > 0, D30_REVENUE_FIRST_TOUCH / COST, NULL) AS D30_ROAS_FIRST_TOUCH
     , IFF(COST > 0, D30_REVENUE_LINEAR / COST, NULL) AS D30_ROAS_LINEAR
     , IFF(COST > 0, D30_REVENUE_TIME_DECAY / COST, NULL) AS D30_ROAS_TIME_DECAY
     , IFF(COST > 0, D30_REVENUE_POSITION_BASED / COST, NULL) AS D30_ROAS_POSITION_BASED
     , IFF(COST > 0, D30_REVENUE_RECOMMENDED / COST, NULL) AS D30_ROAS_RECOMMENDED

     -- =============================================
     -- MODEL COMPARISON: % difference from Last-Touch
     -- Positive = model gives MORE credit than last-touch
     -- Negative = model gives LESS credit than last-touch
     -- =============================================
     , IFF(INSTALLS_LAST_TOUCH > 0,
           (INSTALLS_FIRST_TOUCH - INSTALLS_LAST_TOUCH) / INSTALLS_LAST_TOUCH * 100,
           NULL) AS FIRST_TOUCH_VS_LAST_TOUCH_PCT

     , IFF(INSTALLS_LAST_TOUCH > 0,
           (INSTALLS_LINEAR - INSTALLS_LAST_TOUCH) / INSTALLS_LAST_TOUCH * 100,
           NULL) AS LINEAR_VS_LAST_TOUCH_PCT

     , IFF(INSTALLS_LAST_TOUCH > 0,
           (INSTALLS_TIME_DECAY - INSTALLS_LAST_TOUCH) / INSTALLS_LAST_TOUCH * 100,
           NULL) AS TIME_DECAY_VS_LAST_TOUCH_PCT

     , IFF(INSTALLS_LAST_TOUCH > 0,
           (INSTALLS_POSITION_BASED - INSTALLS_LAST_TOUCH) / INSTALLS_LAST_TOUCH * 100,
           NULL) AS POSITION_BASED_VS_LAST_TOUCH_PCT

FROM network_aggregated
WHERE DATE IS NOT NULL
ORDER BY DATE DESC, COST DESC
