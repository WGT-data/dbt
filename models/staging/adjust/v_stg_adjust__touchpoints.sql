-- v_stg_adjust__touchpoints.sql
-- Unified view of all marketing touchpoints (impressions + clicks) for multi-touch attribution
-- Grain: One row per touchpoint event
--
-- MATCHING IDENTIFIERS (in priority order for iOS):
-- 1. IDFA - deterministic match when user consented to tracking (~11% of clicks)
-- 2. IP_ADDRESS - probabilistic match for remaining touchpoints
-- Android uses GPS_ADID (DEVICE_ID) as primary identifier

{{
    config(
        materialized='incremental',
        unique_key=['PLATFORM', 'TOUCHPOINT_TYPE', 'TOUCHPOINT_EPOCH', 'NETWORK_NAME', 'CAMPAIGN_ID', 'IP_ADDRESS', 'LOAD_TIMESTAMP'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

-- iOS Impressions
-- Note: IDFA available for ~4% of impressions (user consented), IP for 95%
WITH ios_impressions AS (
    SELECT NULL AS DEVICE_ID  -- iOS impressions have no IDFV
         , IDFA  -- Available when user consented to tracking
         , IP_ADDRESS
         , 'iOS' AS PLATFORM
         , 'impression' AS TOUCHPOINT_TYPE
         , NETWORK_NAME
         , TRIM(REGEXP_REPLACE(CAMPAIGN_NAME, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([a-zA-Z0-9_-]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , TRIM(REGEXP_REPLACE(ADGROUP_NAME, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([a-zA-Z0-9_-]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
         , CREATIVE_NAME
         , TO_TIMESTAMP(CREATED_AT) AS TOUCHPOINT_TIMESTAMP
         , CREATED_AT AS TOUCHPOINT_EPOCH
         , LOAD_TIMESTAMP
    FROM {{ source('adjust', 'IOS_ACTIVITY_IMPRESSION') }}
    WHERE (IDFA IS NOT NULL OR IP_ADDRESS IS NOT NULL)
      AND CREATED_AT IS NOT NULL
      AND CREATED_AT >= 1704067200  -- 2024-01-01 in epoch
    {% if is_incremental() %}
      AND CREATED_AT > (SELECT MAX(TOUCHPOINT_EPOCH) FROM {{ this }} WHERE PLATFORM = 'iOS' AND TOUCHPOINT_TYPE = 'impression')
    {% endif %}
)

-- iOS Clicks
-- Note: IDFA available for ~11% of clicks (user consented), IP for 100%
, ios_clicks AS (
    SELECT NULL AS DEVICE_ID  -- iOS clicks have no IDFV
         , IDFA  -- Available when user consented to tracking
         , IP_ADDRESS
         , 'iOS' AS PLATFORM
         , 'click' AS TOUCHPOINT_TYPE
         , NETWORK_NAME
         , TRIM(REGEXP_REPLACE(CAMPAIGN_NAME, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([a-zA-Z0-9_-]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , TRIM(REGEXP_REPLACE(ADGROUP_NAME, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([a-zA-Z0-9_-]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
         , CREATIVE_NAME
         , TO_TIMESTAMP(CREATED_AT) AS TOUCHPOINT_TIMESTAMP
         , CREATED_AT AS TOUCHPOINT_EPOCH
         , LOAD_TIMESTAMP
    FROM {{ source('adjust', 'IOS_ACTIVITY_CLICK') }}
    WHERE (IDFA IS NOT NULL OR IP_ADDRESS IS NOT NULL)
      AND CREATED_AT IS NOT NULL
      AND CREATED_AT >= 1704067200  -- 2024-01-01 in epoch
    {% if is_incremental() %}
      AND CREATED_AT > (SELECT MAX(TOUCHPOINT_EPOCH) FROM {{ this }} WHERE PLATFORM = 'iOS' AND TOUCHPOINT_TYPE = 'click')
    {% endif %}
)

-- Android Impressions
-- Note: Android has device IDs (GPS_ADID) - use both device ID and IP for flexibility
, android_impressions AS (
    SELECT UPPER(GPS_ADID) AS DEVICE_ID
         , NULL AS IDFA  -- Android doesn't have IDFA
         , NULL AS IP_ADDRESS  -- Android tables do not have IP_ADDRESS
         , 'Android' AS PLATFORM
         , 'impression' AS TOUCHPOINT_TYPE
         , NETWORK_NAME
         , TRIM(REGEXP_REPLACE(CAMPAIGN_NAME, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([a-zA-Z0-9_-]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , TRIM(REGEXP_REPLACE(ADGROUP_NAME, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([a-zA-Z0-9_-]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
         , CREATIVE_NAME
         , TO_TIMESTAMP(CREATED_AT) AS TOUCHPOINT_TIMESTAMP
         , CREATED_AT AS TOUCHPOINT_EPOCH
         , LOAD_TIMESTAMP
    FROM {{ source('adjust', 'ANDROID_ACTIVITY_IMPRESSION') }}
    WHERE GPS_ADID IS NOT NULL
      AND CREATED_AT IS NOT NULL
      AND CREATED_AT >= 1704067200  -- 2024-01-01 in epoch
    {% if is_incremental() %}
      AND CREATED_AT > (SELECT MAX(TOUCHPOINT_EPOCH) FROM {{ this }} WHERE PLATFORM = 'Android' AND TOUCHPOINT_TYPE = 'impression')
    {% endif %}
)

-- Android Clicks
, android_clicks AS (
    SELECT UPPER(GPS_ADID) AS DEVICE_ID
         , NULL AS IDFA  -- Android doesn't have IDFA
         , NULL AS IP_ADDRESS  -- Android tables do not have IP_ADDRESS
         , 'Android' AS PLATFORM
         , 'click' AS TOUCHPOINT_TYPE
         , NETWORK_NAME
         , TRIM(REGEXP_REPLACE(CAMPAIGN_NAME, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([a-zA-Z0-9_-]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , TRIM(REGEXP_REPLACE(ADGROUP_NAME, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([a-zA-Z0-9_-]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
         , CREATIVE_NAME
         , TO_TIMESTAMP(CREATED_AT) AS TOUCHPOINT_TIMESTAMP
         , CREATED_AT AS TOUCHPOINT_EPOCH
         , LOAD_TIMESTAMP
    FROM {{ source('adjust', 'ANDROID_ACTIVITY_CLICK') }}
    WHERE GPS_ADID IS NOT NULL
      AND CREATED_AT IS NOT NULL
      AND CREATED_AT >= 1704067200  -- 2024-01-01 in epoch
    {% if is_incremental() %}
      AND CREATED_AT > (SELECT MAX(TOUCHPOINT_EPOCH) FROM {{ this }} WHERE PLATFORM = 'Android' AND TOUCHPOINT_TYPE = 'click')
    {% endif %}
)

-- Union all touchpoints
, all_touchpoints AS (
    SELECT * FROM ios_impressions
    UNION ALL
    SELECT * FROM ios_clicks
    UNION ALL
    SELECT * FROM android_impressions
    UNION ALL
    SELECT * FROM android_clicks
)

-- Add standardized AD_PARTNER mapping (matches v_stg_adjust__installs.sql)
SELECT DEVICE_ID
     , IDFA
     , IP_ADDRESS
     , PLATFORM
     , TOUCHPOINT_TYPE
     , NETWORK_NAME
     , {{ map_ad_partner('NETWORK_NAME') }} AS AD_PARTNER
     , CAMPAIGN_NAME
     , CAMPAIGN_ID
     , ADGROUP_NAME
     , ADGROUP_ID
     , CREATIVE_NAME
     , TOUCHPOINT_TIMESTAMP
     , TOUCHPOINT_EPOCH
     , LOAD_TIMESTAMP
FROM all_touchpoints
