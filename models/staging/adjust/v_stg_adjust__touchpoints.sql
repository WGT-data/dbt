-- v_stg_adjust__touchpoints.sql
-- Unified view of all marketing touchpoints (impressions + clicks) for multi-touch attribution
-- Grain: One row per device + touchpoint event
--
-- IMPORTANT: Device IDs are UPPER() to match the format in int_adjust_amplitude__device_mapping

{{
    config(
        materialized='incremental',
        unique_key=['DEVICE_ID', 'PLATFORM', 'TOUCHPOINT_TYPE', 'TOUCHPOINT_TIMESTAMP', 'NETWORK_NAME', 'CAMPAIGN_ID'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

-- iOS Impressions
-- Note: UPPER() applied to match device mapping format
WITH ios_impressions AS (
    SELECT UPPER(IDFV) AS DEVICE_ID
         , 'iOS' AS PLATFORM
         , 'impression' AS TOUCHPOINT_TYPE
         , NETWORK_NAME
         , CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
         , CREATIVE_NAME
         , TO_TIMESTAMP(CREATED_AT) AS TOUCHPOINT_TIMESTAMP
         , LOAD_TIMESTAMP
    FROM {{ source('adjust', 'IOS_ACTIVITY_IMPRESSION') }}
    WHERE IDFV IS NOT NULL
      AND CREATED_AT IS NOT NULL
      AND CREATED_AT >= '2025-01-01'
    {% if is_incremental() %}
      AND LOAD_TIMESTAMP >= DATEADD(day, -3, (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }} WHERE PLATFORM = 'iOS'))
    {% endif %}
)

-- iOS Clicks
, ios_clicks AS (
    SELECT UPPER(IDFV) AS DEVICE_ID
         , 'iOS' AS PLATFORM
         , 'click' AS TOUCHPOINT_TYPE
         , NETWORK_NAME
         , CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
         , CREATIVE_NAME
         , TO_TIMESTAMP(CREATED_AT) AS TOUCHPOINT_TIMESTAMP
         , LOAD_TIMESTAMP
    FROM {{ source('adjust', 'IOS_ACTIVITY_CLICK') }}
    WHERE IDFV IS NOT NULL
      AND CREATED_AT IS NOT NULL
      AND CREATED_AT >= '2025-01-01'
    {% if is_incremental() %}
      AND LOAD_TIMESTAMP >= DATEADD(day, -3, (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }} WHERE PLATFORM = 'iOS'))
    {% endif %}
)

-- Android Impressions
-- Note: UPPER() applied to match device mapping format
, android_impressions AS (
    SELECT UPPER(GPS_ADID) AS DEVICE_ID
         , 'Android' AS PLATFORM
         , 'impression' AS TOUCHPOINT_TYPE
         , NETWORK_NAME
         , CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
         , CREATIVE_NAME
         , TO_TIMESTAMP(CREATED_AT) AS TOUCHPOINT_TIMESTAMP
         , LOAD_TIMESTAMP
    FROM {{ source('adjust', 'ANDROID_ACTIVITY_IMPRESSION') }}
    WHERE GPS_ADID IS NOT NULL
      AND CREATED_AT IS NOT NULL
      AND CREATED_AT >= '2025-01-01'
    {% if is_incremental() %}
      AND LOAD_TIMESTAMP >= DATEADD(day, -3, (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }} WHERE PLATFORM = 'Android'))
    {% endif %}
)

-- Android Clicks
, android_clicks AS (
    SELECT UPPER(GPS_ADID) AS DEVICE_ID
         , 'Android' AS PLATFORM
         , 'click' AS TOUCHPOINT_TYPE
         , NETWORK_NAME
         , CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
         , CREATIVE_NAME
         , TO_TIMESTAMP(CREATED_AT) AS TOUCHPOINT_TIMESTAMP
         , LOAD_TIMESTAMP
    FROM {{ source('adjust', 'ANDROID_ACTIVITY_CLICK') }}
    WHERE GPS_ADID IS NOT NULL
      AND CREATED_AT IS NOT NULL
      AND CREATED_AT >= '2025-01-01'
    {% if is_incremental() %}
      AND LOAD_TIMESTAMP >= DATEADD(day, -3, (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }} WHERE PLATFORM = 'Android'))
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
     , PLATFORM
     , TOUCHPOINT_TYPE
     , NETWORK_NAME
     , CASE
           WHEN NETWORK_NAME IN ('Facebook Installs', 'Instagram Installs', 'Off-Facebook Installs', 'Facebook Messenger Installs') THEN 'Meta'
           WHEN NETWORK_NAME IN ('Google Ads ACE', 'Google Ads ACI', 'Google Organic Search', 'google') THEN 'Google'
           WHEN NETWORK_NAME IN ('TikTok SAN', 'TikTok_Paid_Ads_iOS', 'Tiktok Installs') THEN 'TikTok'
           WHEN NETWORK_NAME = 'Apple Search Ads' THEN 'Apple'
           WHEN NETWORK_NAME LIKE 'AppLovin%' THEN 'AppLovin'
           WHEN NETWORK_NAME LIKE 'UnityAds%' THEN 'Unity'
           WHEN NETWORK_NAME LIKE 'Moloco%' THEN 'Moloco'
           WHEN NETWORK_NAME LIKE 'Smadex%' THEN 'Smadex'
           WHEN NETWORK_NAME LIKE 'AdAction%' THEN 'AdAction'
           WHEN NETWORK_NAME LIKE 'Vungle%' THEN 'Vungle'
           WHEN NETWORK_NAME = 'Organic' THEN 'Organic'
           WHEN NETWORK_NAME = 'Unattributed' THEN 'Unattributed'
           WHEN NETWORK_NAME = 'Untrusted Devices' THEN 'Untrusted'
           WHEN NETWORK_NAME IN ('wgtgolf', 'WGT_Events_SocialPosts_iOS', 'WGT_GiftCards_Social') THEN 'WGT'
           WHEN NETWORK_NAME LIKE 'Phigolf%' THEN 'Phigolf'
           WHEN NETWORK_NAME LIKE 'Ryder%' THEN 'Ryder Cup'
           ELSE 'Other'
       END AS AD_PARTNER
     , CAMPAIGN_NAME
     , CAMPAIGN_ID
     , ADGROUP_NAME
     , ADGROUP_ID
     , CREATIVE_NAME
     , TOUCHPOINT_TIMESTAMP
     , LOAD_TIMESTAMP
FROM all_touchpoints
