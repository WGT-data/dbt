-- v_stg_adjust__installs.sql
-- Unified view of all app installs from Adjust
-- Grain: One row per device (first install only)
--
-- NOTE: IP_ADDRESS included for iOS MTA matching since iOS touchpoints lack device IDs

WITH IOS_INSTALLS AS (
    SELECT IDFV AS DEVICE_ID
         , IDFA  -- For deterministic matching when user consented to tracking
         , 'iOS' AS PLATFORM
         , NETWORK_NAME
         , TRIM(REGEXP_REPLACE(CAMPAIGN_NAME, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([a-zA-Z0-9_-]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , TRIM(REGEXP_REPLACE(ADGROUP_NAME, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([a-zA-Z0-9_-]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
         , CREATIVE_NAME
         , TRACKER_NAME
         , COUNTRY
         , IP_ADDRESS
         , TO_TIMESTAMP(INSTALLED_AT) AS INSTALL_TIMESTAMP
         , INSTALLED_AT AS INSTALL_EPOCH
         , TO_TIMESTAMP(CREATED_AT) AS CREATED_TIMESTAMP
    FROM {{ source('adjust', 'IOS_ACTIVITY_INSTALL') }}
    WHERE IDFV IS NOT NULL
      AND INSTALLED_AT IS NOT NULL
)

, ANDROID_INSTALLS AS (
    SELECT UPPER(GPS_ADID) AS DEVICE_ID
         , NULL AS IDFA  -- Android doesn't have IDFA
         , 'Android' AS PLATFORM
         , NETWORK_NAME
         , TRIM(REGEXP_REPLACE(CAMPAIGN_NAME, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([a-zA-Z0-9_-]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , TRIM(REGEXP_REPLACE(ADGROUP_NAME, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([a-zA-Z0-9_-]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
         , CREATIVE_NAME
         , NULL AS TRACKER_NAME
         , NULL AS COUNTRY
         , NULL AS IP_ADDRESS  -- Android install table does not have IP_ADDRESS
         , TO_TIMESTAMP(INSTALLED_AT) AS INSTALL_TIMESTAMP
         , INSTALLED_AT AS INSTALL_EPOCH
         , TO_TIMESTAMP(CREATED_AT) AS CREATED_TIMESTAMP
    FROM {{ source('adjust', 'ANDROID_ACTIVITY_INSTALL') }}
    WHERE GPS_ADID IS NOT NULL
      AND INSTALLED_AT IS NOT NULL
)

, COMBINED AS (
    SELECT * FROM IOS_INSTALLS
    UNION ALL
    SELECT * FROM ANDROID_INSTALLS
)

, DEDUPED AS (
    SELECT *
    FROM COMBINED
    QUALIFY ROW_NUMBER() OVER (PARTITION BY DEVICE_ID, PLATFORM ORDER BY INSTALL_TIMESTAMP ASC) = 1
)

SELECT DEVICE_ID
     , IDFA
     , PLATFORM
     , NETWORK_NAME
     , {{ map_ad_partner('NETWORK_NAME') }} AS AD_PARTNER
     , CAMPAIGN_NAME
     , CAMPAIGN_ID
     , ADGROUP_NAME
     , ADGROUP_ID
     , CREATIVE_NAME
     , TRACKER_NAME
     , COUNTRY
     , IP_ADDRESS
     , INSTALL_TIMESTAMP
     , INSTALL_EPOCH
     , CREATED_TIMESTAMP
FROM DEDUPED
