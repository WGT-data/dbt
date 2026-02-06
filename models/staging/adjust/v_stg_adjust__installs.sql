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
         , CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
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
    SELECT GPS_ADID AS DEVICE_ID
         , NULL AS IDFA  -- Android doesn't have IDFA
         , 'Android' AS PLATFORM
         , NETWORK_NAME
         , CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
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
     , TRACKER_NAME
     , COUNTRY
     , IP_ADDRESS
     , INSTALL_TIMESTAMP
     , INSTALL_EPOCH
     , CREATED_TIMESTAMP
FROM DEDUPED
