-- int_mta__user_journey.sql
-- Maps all touchpoints (impressions + clicks) to conversions (installs)
-- This is the foundation for multi-touch attribution calculations
-- Grain: One row per device + touchpoint + install combination

{{
    config(
        materialized='incremental',
        unique_key=['DEVICE_ID', 'PLATFORM', 'TOUCHPOINT_TIMESTAMP', 'TOUCHPOINT_TYPE', 'NETWORK_NAME'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        tags=['mta', 'attribution']
    )
}}

-- Configuration parameters for attribution
{% set lookback_window_days = 7 %}  -- Only consider touchpoints within 7 days of install
{% set click_weight_multiplier = 2.0 %}  -- Clicks are worth 2x impressions

-- Get all installs
WITH installs AS (
    SELECT DEVICE_ID
         , PLATFORM
         , NETWORK_NAME AS INSTALL_NETWORK
         , AD_PARTNER AS INSTALL_AD_PARTNER
         , CAMPAIGN_NAME AS INSTALL_CAMPAIGN_NAME
         , CAMPAIGN_ID AS INSTALL_CAMPAIGN_ID
         , INSTALL_TIMESTAMP
    FROM {{ ref('v_stg_adjust__installs') }}
    {% if is_incremental() %}
        -- Process installs from last 10 days (lookback + buffer)
        WHERE INSTALL_TIMESTAMP >= DATEADD(day, -10, (SELECT MAX(INSTALL_TIMESTAMP) FROM {{ this }}))
    {% endif %}
)

-- Get all touchpoints
, touchpoints AS (
    SELECT DEVICE_ID
         , PLATFORM
         , TOUCHPOINT_TYPE
         , NETWORK_NAME
         , AD_PARTNER
         , CAMPAIGN_NAME
         , CAMPAIGN_ID
         , ADGROUP_NAME
         , ADGROUP_ID
         , CREATIVE_NAME
         , TOUCHPOINT_TIMESTAMP
    FROM {{ ref('v_stg_adjust__touchpoints') }}
    {% if is_incremental() %}
        -- Match touchpoint window to install window
        WHERE TOUCHPOINT_TIMESTAMP >= DATEADD(day, -17, (SELECT MAX(INSTALL_TIMESTAMP) FROM {{ this }}))
    {% endif %}
)

-- Join touchpoints to installs within lookback window
, touchpoints_with_install AS (
    SELECT t.DEVICE_ID
         , t.PLATFORM
         , t.TOUCHPOINT_TYPE
         , t.NETWORK_NAME
         , t.AD_PARTNER
         , t.CAMPAIGN_NAME
         , t.CAMPAIGN_ID
         , t.ADGROUP_NAME
         , t.ADGROUP_ID
         , t.CREATIVE_NAME
         , t.TOUCHPOINT_TIMESTAMP
         , i.INSTALL_TIMESTAMP
         , i.INSTALL_NETWORK
         , i.INSTALL_AD_PARTNER
         , i.INSTALL_CAMPAIGN_ID
         -- Calculate hours between touchpoint and install
         , DATEDIFF(hour, t.TOUCHPOINT_TIMESTAMP, i.INSTALL_TIMESTAMP) AS HOURS_TO_INSTALL
         -- Calculate days between touchpoint and install
         , DATEDIFF(day, t.TOUCHPOINT_TIMESTAMP, i.INSTALL_TIMESTAMP) AS DAYS_TO_INSTALL
    FROM touchpoints t
    INNER JOIN installs i
        ON t.DEVICE_ID = i.DEVICE_ID
        AND t.PLATFORM = i.PLATFORM
        -- Touchpoint must be BEFORE install
        AND t.TOUCHPOINT_TIMESTAMP < i.INSTALL_TIMESTAMP
        -- Touchpoint must be within lookback window
        AND t.TOUCHPOINT_TIMESTAMP >= DATEADD(day, -{{ lookback_window_days }}, i.INSTALL_TIMESTAMP)
)

-- Calculate touchpoint position in the journey
, journey_with_position AS (
    SELECT *
         -- Position from first touchpoint (1 = first)
         , ROW_NUMBER() OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
               ORDER BY TOUCHPOINT_TIMESTAMP ASC
           ) AS TOUCHPOINT_POSITION
         -- Position from last touchpoint (1 = last)
         , ROW_NUMBER() OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
               ORDER BY TOUCHPOINT_TIMESTAMP DESC
           ) AS REVERSE_POSITION
         -- Total touchpoints in journey
         , COUNT(*) OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
           ) AS TOTAL_TOUCHPOINTS
         -- Is this the first touchpoint?
         , CASE WHEN ROW_NUMBER() OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
               ORDER BY TOUCHPOINT_TIMESTAMP ASC
           ) = 1 THEN 1 ELSE 0 END AS IS_FIRST_TOUCH
         -- Is this the last touchpoint?
         , CASE WHEN ROW_NUMBER() OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
               ORDER BY TOUCHPOINT_TIMESTAMP DESC
           ) = 1 THEN 1 ELSE 0 END AS IS_LAST_TOUCH
    FROM touchpoints_with_install
)

SELECT DEVICE_ID
     , PLATFORM
     , TOUCHPOINT_TYPE
     , NETWORK_NAME
     , AD_PARTNER
     , CAMPAIGN_NAME
     , CAMPAIGN_ID
     , ADGROUP_NAME
     , ADGROUP_ID
     , CREATIVE_NAME
     , TOUCHPOINT_TIMESTAMP
     , INSTALL_TIMESTAMP
     , INSTALL_NETWORK
     , INSTALL_AD_PARTNER
     , INSTALL_CAMPAIGN_ID
     , HOURS_TO_INSTALL
     , DAYS_TO_INSTALL
     , TOUCHPOINT_POSITION
     , REVERSE_POSITION
     , TOTAL_TOUCHPOINTS
     , IS_FIRST_TOUCH
     , IS_LAST_TOUCH
     -- Base weight: clicks are worth more than impressions
     , CASE
           WHEN TOUCHPOINT_TYPE = 'click' THEN {{ click_weight_multiplier }}
           ELSE 1.0
       END AS BASE_TYPE_WEIGHT
FROM journey_with_position
