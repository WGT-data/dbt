-- int_mta__user_journey.sql
-- Maps all touchpoints (impressions + clicks) to conversions (installs)
-- This is the foundation for multi-touch attribution calculations
-- Grain: One row per device + touchpoint + install combination
--
-- MATCHING STRATEGY (deterministic only, GDPR compliant):
-- - iOS: IDFA match (deterministic, ATT-consented users only)
-- - Android: Device ID match (GPS_ADID, deterministic)
--
-- NOTE: IP-based probabilistic matching for iOS was removed for GDPR compliance.
-- IP addresses are personal data under GDPR and cannot be used for attribution
-- without explicit consent. Analysis showed IP matching also produced unreliable
-- data (median 270 touchpoints/journey, max 25,500 due to carrier NAT collisions).

{{
    config(
        materialized='incremental',
        unique_key='JOURNEY_ROW_KEY',
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        tags=['mta', 'attribution']
    )
}}

-- Configuration parameters for attribution
{% set lookback_window_days = 7 %}  -- Only consider touchpoints within 7 days of install
{% set lookback_window_seconds = lookback_window_days * 24 * 60 * 60 %}
{% set click_weight_multiplier = 2.0 %}  -- Clicks are worth 2x impressions

-- Get all installs with identifiers for matching
WITH installs AS (
    SELECT DEVICE_ID
         , IDFA  -- For iOS deterministic matching when user consented
         , PLATFORM
         , NETWORK_NAME AS INSTALL_NETWORK
         , AD_PARTNER AS INSTALL_AD_PARTNER
         , CAMPAIGN_NAME AS INSTALL_CAMPAIGN_NAME
         , CAMPAIGN_ID AS INSTALL_CAMPAIGN_ID
         , INSTALL_TIMESTAMP
         , INSTALL_EPOCH
    FROM {{ ref('v_stg_adjust__installs') }}
    {% if is_incremental() %}
        -- Process installs from last 10 days (lookback + buffer)
        WHERE INSTALL_TIMESTAMP >= DATEADD(day, -10, (SELECT MAX(INSTALL_TIMESTAMP) FROM {{ this }}))
    {% endif %}
)

-- Get all touchpoints with identifiers for matching
, touchpoints AS (
    SELECT DEVICE_ID
         , IDFA  -- For iOS deterministic matching when user consented
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
         , TOUCHPOINT_EPOCH
    FROM {{ ref('v_stg_adjust__touchpoints') }}
    {% if is_incremental() %}
        -- Match touchpoint window to install window
        WHERE TOUCHPOINT_TIMESTAMP >= DATEADD(day, -17, (SELECT MAX(INSTALL_TIMESTAMP) FROM {{ this }}))
    {% endif %}
)

-- iOS touchpoint matching: IDFA only (deterministic, ATT-consented users)
, ios_touchpoints_matched AS (
    SELECT i.DEVICE_ID
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
         , DATEDIFF(hour, t.TOUCHPOINT_TIMESTAMP, i.INSTALL_TIMESTAMP) AS HOURS_TO_INSTALL
         , DATEDIFF(day, t.TOUCHPOINT_TIMESTAMP, i.INSTALL_TIMESTAMP) AS DAYS_TO_INSTALL
         , 'IDFA' AS MATCH_TYPE
    FROM touchpoints t
    INNER JOIN installs i
        ON t.IDFA = i.IDFA  -- Deterministic IDFA match
        AND t.PLATFORM = 'iOS'
        AND i.PLATFORM = 'iOS'
        -- Touchpoint must be BEFORE install
        AND t.TOUCHPOINT_EPOCH < i.INSTALL_EPOCH
        -- Touchpoint must be within lookback window
        AND t.TOUCHPOINT_EPOCH >= i.INSTALL_EPOCH - {{ lookback_window_seconds }}
    WHERE t.IDFA IS NOT NULL
      AND i.IDFA IS NOT NULL
)

-- Android touchpoint matching via Device ID (deterministic)
, android_touchpoints_matched AS (
    SELECT i.DEVICE_ID
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
         , DATEDIFF(hour, t.TOUCHPOINT_TIMESTAMP, i.INSTALL_TIMESTAMP) AS HOURS_TO_INSTALL
         , DATEDIFF(day, t.TOUCHPOINT_TIMESTAMP, i.INSTALL_TIMESTAMP) AS DAYS_TO_INSTALL
         , 'DEVICE_ID' AS MATCH_TYPE  -- Android always uses deterministic device ID matching
    FROM touchpoints t
    INNER JOIN installs i
        ON t.DEVICE_ID = i.DEVICE_ID  -- Match on Device ID
        AND t.PLATFORM = 'Android'
        AND i.PLATFORM = 'Android'
        -- Touchpoint must be BEFORE install
        AND t.TOUCHPOINT_EPOCH < i.INSTALL_EPOCH
        -- Touchpoint must be within lookback window
        AND t.TOUCHPOINT_EPOCH >= i.INSTALL_EPOCH - {{ lookback_window_seconds }}
    WHERE t.DEVICE_ID IS NOT NULL
)

-- Combine iOS and Android matches
, touchpoints_with_install AS (
    SELECT * FROM ios_touchpoints_matched
    UNION ALL
    SELECT * FROM android_touchpoints_matched
)

-- Deduplicate before calculating positions so counts and flags are accurate
, journey_deduped AS (
    SELECT *
    FROM touchpoints_with_install
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY DEVICE_ID
                   , PLATFORM
                   , TOUCHPOINT_TIMESTAMP
                   , TOUCHPOINT_TYPE
                   , COALESCE(NETWORK_NAME, '')
                   , INSTALL_TIMESTAMP
                   , COALESCE(CAMPAIGN_ID, '')
                   , COALESCE(ADGROUP_ID, '')
                   , COALESCE(CREATIVE_NAME, '')
                   , MATCH_TYPE
        ORDER BY TOUCHPOINT_TIMESTAMP DESC
    ) = 1
)

-- Calculate touchpoint position in the journey (after dedup)
, journey_with_position AS (
    SELECT *
         -- Position from first touchpoint (1 = first)
         -- Secondary sort keys break ties when timestamps are identical
         , ROW_NUMBER() OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
               ORDER BY TOUCHPOINT_TIMESTAMP ASC, TOUCHPOINT_TYPE DESC, NETWORK_NAME ASC, CAMPAIGN_NAME ASC
           ) AS TOUCHPOINT_POSITION
         -- Position from last touchpoint (1 = last)
         , ROW_NUMBER() OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
               ORDER BY TOUCHPOINT_TIMESTAMP DESC, TOUCHPOINT_TYPE ASC, NETWORK_NAME DESC, CAMPAIGN_NAME DESC
           ) AS REVERSE_POSITION
         -- Total touchpoints in journey
         , COUNT(*) OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
           ) AS TOTAL_TOUCHPOINTS
         -- Is this the first touchpoint?
         , CASE WHEN ROW_NUMBER() OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
               ORDER BY TOUCHPOINT_TIMESTAMP ASC, TOUCHPOINT_TYPE DESC, NETWORK_NAME ASC, CAMPAIGN_NAME ASC
           ) = 1 THEN 1 ELSE 0 END AS IS_FIRST_TOUCH
         -- Is this the last touchpoint?
         , CASE WHEN ROW_NUMBER() OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
               ORDER BY TOUCHPOINT_TIMESTAMP DESC, TOUCHPOINT_TYPE ASC, NETWORK_NAME DESC, CAMPAIGN_NAME DESC
           ) = 1 THEN 1 ELSE 0 END AS IS_LAST_TOUCH
    FROM journey_deduped
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
     , MATCH_TYPE  -- IDFA (deterministic, iOS) or DEVICE_ID (deterministic, Android)
     , MD5(
         CONCAT(
             COALESCE(DEVICE_ID, '')
             , '||', COALESCE(PLATFORM, '')
             , '||', COALESCE(TOUCHPOINT_TYPE, '')
             , '||', COALESCE(NETWORK_NAME, '')
             , '||', COALESCE(TO_VARCHAR(TOUCHPOINT_TIMESTAMP), '')
             , '||', COALESCE(TO_VARCHAR(INSTALL_TIMESTAMP), '')
             , '||', COALESCE(CAMPAIGN_ID, '')
             , '||', COALESCE(ADGROUP_ID, '')
             , '||', COALESCE(CREATIVE_NAME, '')
             , '||', COALESCE(MATCH_TYPE, '')
         )
       ) AS JOURNEY_ROW_KEY
     -- Base weight: clicks are worth more than impressions
     , CASE
           WHEN TOUCHPOINT_TYPE = 'click' THEN {{ click_weight_multiplier }}
           ELSE 1.0
       END AS BASE_TYPE_WEIGHT
FROM journey_with_position
