-- rpt__user_journey_insights.sql
-- DASHBOARD-READY: User journey analytics showing touchpoint patterns
-- Helps understand customer journey complexity by network
--
-- Grain: One row per AD_PARTNER + PLATFORM + DATE

{{
    config(
        materialized='incremental',
        unique_key=['AD_PARTNER', 'PLATFORM', 'DATE'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        tags=['dashboard', 'attribution', 'journey']
    )
}}

WITH user_journeys AS (
    SELECT DEVICE_ID
         , PLATFORM
         , INSTALL_TIMESTAMP
         , CAST(INSTALL_TIMESTAMP AS DATE) AS INSTALL_DATE
         -- First touch info
         , FIRST_VALUE(AD_PARTNER) OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
               ORDER BY TOUCHPOINT_TIMESTAMP ASC
           ) AS FIRST_TOUCH_PARTNER
         , FIRST_VALUE(NETWORK_NAME) OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
               ORDER BY TOUCHPOINT_TIMESTAMP ASC
           ) AS FIRST_TOUCH_NETWORK
         -- Last touch info
         , FIRST_VALUE(AD_PARTNER) OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
               ORDER BY TOUCHPOINT_TIMESTAMP DESC
           ) AS LAST_TOUCH_PARTNER
         , FIRST_VALUE(NETWORK_NAME) OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
               ORDER BY TOUCHPOINT_TIMESTAMP DESC
           ) AS LAST_TOUCH_NETWORK
         -- Journey metrics
         , TOTAL_TOUCHPOINTS
         , TOUCHPOINT_TYPE
         , HOURS_TO_INSTALL
         , DAYS_TO_INSTALL
         , IS_FIRST_TOUCH
         , IS_LAST_TOUCH
    FROM {{ ref('int_mta__user_journey') }}
    {% if is_incremental() %}
        WHERE CAST(INSTALL_TIMESTAMP AS DATE) >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
)

-- Dedupe to one row per install (using last touch partner as the key)
, installs_deduped AS (
    SELECT DEVICE_ID
         , PLATFORM
         , INSTALL_DATE
         , FIRST_TOUCH_PARTNER
         , FIRST_TOUCH_NETWORK
         , LAST_TOUCH_PARTNER
         , LAST_TOUCH_NETWORK
         , MAX(TOTAL_TOUCHPOINTS) AS TOTAL_TOUCHPOINTS
         , SUM(CASE WHEN TOUCHPOINT_TYPE = 'impression' THEN 1 ELSE 0 END) AS IMPRESSION_COUNT
         , SUM(CASE WHEN TOUCHPOINT_TYPE = 'click' THEN 1 ELSE 0 END) AS CLICK_COUNT
         , MAX(HOURS_TO_INSTALL) AS MAX_HOURS_TO_INSTALL
         , MIN(HOURS_TO_INSTALL) AS MIN_HOURS_TO_INSTALL
    FROM user_journeys
    GROUP BY 1, 2, 3, 4, 5, 6, 7
)

-- Aggregate by last-touch partner (for comparison with current model)
, aggregated AS (
    SELECT LAST_TOUCH_PARTNER AS AD_PARTNER
         , PLATFORM
         , INSTALL_DATE AS DATE

         -- Volume
         , COUNT(DISTINCT DEVICE_ID) AS TOTAL_INSTALLS

         -- Journey complexity
         , AVG(TOTAL_TOUCHPOINTS) AS AVG_TOUCHPOINTS_PER_INSTALL
         , MEDIAN(TOTAL_TOUCHPOINTS) AS MEDIAN_TOUCHPOINTS
         , MAX(TOTAL_TOUCHPOINTS) AS MAX_TOUCHPOINTS

         -- Touchpoint mix
         , AVG(IMPRESSION_COUNT) AS AVG_IMPRESSIONS_PER_INSTALL
         , AVG(CLICK_COUNT) AS AVG_CLICKS_PER_INSTALL
         , SUM(IMPRESSION_COUNT) AS TOTAL_IMPRESSIONS
         , SUM(CLICK_COUNT) AS TOTAL_CLICKS

         -- Time to convert
         , AVG(MAX_HOURS_TO_INSTALL) AS AVG_HOURS_FIRST_TOUCH_TO_INSTALL
         , AVG(MIN_HOURS_TO_INSTALL) AS AVG_HOURS_LAST_TOUCH_TO_INSTALL

         -- Cross-network journeys (first touch != last touch)
         , SUM(CASE WHEN FIRST_TOUCH_PARTNER != LAST_TOUCH_PARTNER THEN 1 ELSE 0 END) AS CROSS_NETWORK_INSTALLS
         , SUM(CASE WHEN FIRST_TOUCH_PARTNER = LAST_TOUCH_PARTNER THEN 1 ELSE 0 END) AS SINGLE_NETWORK_INSTALLS

         -- Single touchpoint installs (direct conversion)
         , SUM(CASE WHEN TOTAL_TOUCHPOINTS = 1 THEN 1 ELSE 0 END) AS SINGLE_TOUCH_INSTALLS
         -- Multi-touch installs
         , SUM(CASE WHEN TOTAL_TOUCHPOINTS > 1 THEN 1 ELSE 0 END) AS MULTI_TOUCH_INSTALLS

    FROM installs_deduped
    GROUP BY 1, 2, 3
)

SELECT AD_PARTNER
     , PLATFORM
     , DATE
     , TOTAL_INSTALLS

     -- =============================================
     -- JOURNEY COMPLEXITY METRICS
     -- =============================================
     , ROUND(AVG_TOUCHPOINTS_PER_INSTALL, 1) AS AVG_TOUCHPOINTS
     , MEDIAN_TOUCHPOINTS
     , MAX_TOUCHPOINTS

     -- =============================================
     -- TOUCHPOINT MIX
     -- =============================================
     , ROUND(AVG_IMPRESSIONS_PER_INSTALL, 1) AS AVG_IMPRESSIONS
     , ROUND(AVG_CLICKS_PER_INSTALL, 1) AS AVG_CLICKS
     , TOTAL_IMPRESSIONS
     , TOTAL_CLICKS
     , IFF(TOTAL_IMPRESSIONS + TOTAL_CLICKS > 0,
           ROUND(TOTAL_CLICKS::FLOAT / (TOTAL_IMPRESSIONS + TOTAL_CLICKS) * 100, 1),
           NULL) AS CLICK_RATE_PCT

     -- =============================================
     -- TIME TO CONVERT
     -- =============================================
     , ROUND(AVG_HOURS_FIRST_TOUCH_TO_INSTALL, 1) AS AVG_HOURS_FROM_FIRST_TOUCH
     , ROUND(AVG_HOURS_LAST_TOUCH_TO_INSTALL, 1) AS AVG_HOURS_FROM_LAST_TOUCH
     , ROUND(AVG_HOURS_FIRST_TOUCH_TO_INSTALL / 24, 1) AS AVG_DAYS_FROM_FIRST_TOUCH

     -- =============================================
     -- CROSS-NETWORK ANALYSIS
     -- =============================================
     , CROSS_NETWORK_INSTALLS
     , SINGLE_NETWORK_INSTALLS
     , ROUND(CROSS_NETWORK_INSTALLS::FLOAT / NULLIF(TOTAL_INSTALLS, 0) * 100, 1) AS CROSS_NETWORK_PCT
     -- High % = users see ads from multiple networks before converting

     -- =============================================
     -- SINGLE vs MULTI-TOUCH
     -- =============================================
     , SINGLE_TOUCH_INSTALLS
     , MULTI_TOUCH_INSTALLS
     , ROUND(MULTI_TOUCH_INSTALLS::FLOAT / NULLIF(TOTAL_INSTALLS, 0) * 100, 1) AS MULTI_TOUCH_PCT
     -- High % = MTA will show different results than last-touch

FROM aggregated
WHERE DATE IS NOT NULL
ORDER BY DATE DESC, TOTAL_INSTALLS DESC
