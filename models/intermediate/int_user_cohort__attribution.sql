-- int_user_cohort__attribution.sql
-- Links users to their install attribution source (network, campaign, adgroup)
-- Grain: One row per user_id/platform combination

{{ config(
    materialized='incremental',
    unique_key=['USER_ID', 'PLATFORM'],
    incremental_strategy='merge',
    tags=['cohort', 'attribution'],
    on_schema_change='append_new_columns'
) }}

-- iOS installs with attribution
WITH ios_installs AS (
    SELECT 
        dm.AMPLITUDE_USER_ID AS USER_ID
        , dm.PLATFORM
        , UPPER(dm.ADJUST_DEVICE_ID) AS ADJUST_DEVICE_ID
        , i.NETWORK_NAME
        , i.CAMPAIGN_NAME
        , i.ADGROUP_NAME
        , i.CREATIVE_NAME
        , i.COUNTRY
        , TO_TIMESTAMP(i.INSTALLED_AT) AS INSTALL_TIME
        , DATE(TO_TIMESTAMP(i.INSTALLED_AT)) AS INSTALL_DATE
        , ROW_NUMBER() OVER (
            PARTITION BY dm.AMPLITUDE_USER_ID, dm.PLATFORM 
            ORDER BY TO_TIMESTAMP(i.INSTALLED_AT) ASC
        ) AS RN
    FROM {{ ref('int_adjust_amplitude__device_mapping') }} dm
    INNER JOIN {{ source('adjust', 'IOS_ACTIVITY_INSTALL') }} i
        ON UPPER(dm.ADJUST_DEVICE_ID) = UPPER(i.IDFV)
    WHERE dm.PLATFORM = 'iOS'
    AND dm.AMPLITUDE_USER_ID IS NOT NULL
    AND i.INSTALLED_AT IS NOT NULL
)

-- Android installs with attribution
-- Note: Android table has different schema, no COUNTRY column
, android_installs AS (
    SELECT 
        dm.AMPLITUDE_USER_ID AS USER_ID
        , dm.PLATFORM
        , dm.ADJUST_DEVICE_ID
        , i.NETWORK_NAME
        , i.CAMPAIGN_NAME
        , i.ADGROUP_NAME
        , i.CREATIVE_NAME
        , NULL AS COUNTRY
        , TO_TIMESTAMP(i.INSTALLED_AT) AS INSTALL_TIME
        , DATE(TO_TIMESTAMP(i.INSTALLED_AT)) AS INSTALL_DATE
        , ROW_NUMBER() OVER (
            PARTITION BY dm.AMPLITUDE_USER_ID, dm.PLATFORM 
            ORDER BY TO_TIMESTAMP(i.INSTALLED_AT) ASC
        ) AS RN
    FROM {{ ref('int_adjust_amplitude__device_mapping') }} dm
    INNER JOIN {{ source('adjust', 'ANDROID_ACTIVITY_INSTALL') }} i
        ON dm.ADJUST_DEVICE_ID = i.GPS_ADID
    WHERE dm.PLATFORM = 'Android'
    AND dm.AMPLITUDE_USER_ID IS NOT NULL
    AND i.INSTALLED_AT IS NOT NULL
)

-- Union and dedupe to first install per user
, all_installs AS (
    SELECT 
        USER_ID
        , PLATFORM
        , ADJUST_DEVICE_ID
        , NETWORK_NAME
        , CAMPAIGN_NAME
        , ADGROUP_NAME
        , CREATIVE_NAME
        , COUNTRY
        , INSTALL_TIME
        , INSTALL_DATE
    FROM ios_installs
    WHERE RN = 1
    
    UNION ALL
    
    SELECT 
        USER_ID
        , PLATFORM
        , ADJUST_DEVICE_ID
        , NETWORK_NAME
        , CAMPAIGN_NAME
        , ADGROUP_NAME
        , CREATIVE_NAME
        , COUNTRY
        , INSTALL_TIME
        , INSTALL_DATE
    FROM android_installs
    WHERE RN = 1
)

-- Join with network mapping for standardized partner names
, attributed AS (
    SELECT 
        a.USER_ID
        , a.PLATFORM
        , a.ADJUST_DEVICE_ID
        , COALESCE(nm.SUPERMETRICS_PARTNER_NAME, a.NETWORK_NAME) AS AD_PARTNER
        , a.NETWORK_NAME
        , a.CAMPAIGN_NAME
        , a.ADGROUP_NAME
        , a.CREATIVE_NAME
        , a.COUNTRY
        , a.INSTALL_TIME
        , a.INSTALL_DATE
    FROM all_installs a
    LEFT JOIN {{ ref('network_mapping') }} nm
        ON a.NETWORK_NAME = nm.ADJUST_NETWORK_NAME
)

SELECT
    USER_ID
    , PLATFORM
    , ADJUST_DEVICE_ID
    , AD_PARTNER
    , NETWORK_NAME
    , CAMPAIGN_NAME
    , ADGROUP_NAME
    , CREATIVE_NAME
    , COUNTRY
    , INSTALL_TIME
    , INSTALL_DATE
FROM attributed
{% if is_incremental() %}
    -- Only process users with recent installs (7-day lookback)
    WHERE INSTALL_TIME >= DATEADD(day, -7, (SELECT MAX(INSTALL_TIME) FROM {{ this }}))
{% endif %}
