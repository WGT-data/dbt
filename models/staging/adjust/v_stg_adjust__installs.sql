WITH IOS_INSTALLS AS (
    SELECT IDFV AS DEVICE_ID
         , 'iOS' AS PLATFORM
         , NETWORK_NAME
         , CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
         , CREATIVE_NAME
         , TRACKER_NAME
         , COUNTRY
         , TO_TIMESTAMP(INSTALLED_AT) AS INSTALL_TIMESTAMP
         , TO_TIMESTAMP(CREATED_AT) AS CREATED_TIMESTAMP
    FROM ADJUST_S3.PROD_DATA.IOS_ACTIVITY_INSTALL
    WHERE IDFV IS NOT NULL
      AND INSTALLED_AT IS NOT NULL
)

, ANDROID_INSTALLS AS (
    SELECT GPS_ADID AS DEVICE_ID
         , 'Android' AS PLATFORM
         , NETWORK_NAME
         , CAMPAIGN_NAME
         , REGEXP_SUBSTR(CAMPAIGN_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS CAMPAIGN_ID
         , ADGROUP_NAME
         , REGEXP_SUBSTR(ADGROUP_NAME, '\\(([0-9]+)\\)$', 1, 1, 'e') AS ADGROUP_ID
         , CREATIVE_NAME
         , NULL AS TRACKER_NAME
         , NULL AS COUNTRY
         , TO_TIMESTAMP(INSTALLED_AT) AS INSTALL_TIMESTAMP
         , TO_TIMESTAMP(CREATED_AT) AS CREATED_TIMESTAMP
    FROM ADJUST_S3.PROD_DATA.ANDROID_ACTIVITY_INSTALL
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
     , INSTALL_TIMESTAMP
     , CREATED_TIMESTAMP
FROM DEDUPED
