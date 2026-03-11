{{
    config(
        materialized='view',
        schema='staging'
    )
}}

/*
    Staging model for Adjust API network-level daily report data
    Source: ADJUST.API_DATA.REPORT_DAILY_NETWORK_RAW

    This provides accurate network-level install totals by using only 4 API
    dimensions (day, partner_name, os_name, platform) instead of 17.
    Used by int_mmm__daily_channel_installs for MMM input.
*/

SELECT DAY AS DATE
     , APP
     , OS_NAME
     , CASE
         WHEN UPPER(OS_NAME) = 'IOS' THEN 'iOS'
         WHEN UPPER(OS_NAME) = 'ANDROID' THEN 'Android'
         ELSE OS_NAME
       END AS PLATFORM
     , TRIM(REGEXP_REPLACE(NETWORK, '\\s*\\([a-zA-Z0-9_ -]+\\)\\s*$', '')) AS PARTNER_NAME
     , COALESCE(INSTALLS, 0) AS INSTALLS
     , COALESCE(CLICKS, 0) AS CLICKS
     , COALESCE(IMPRESSIONS, 0) AS IMPRESSIONS
     , COALESCE(COST, 0) AS COST
     , COALESCE(NETWORK_COST, 0) AS NETWORK_COST
     , COALESCE(ADJUST_COST, 0) AS ADJUST_COST
     , COALESCE(PAID_INSTALLS, 0) AS PAID_INSTALLS
     , COALESCE(PAID_CLICKS, 0) AS PAID_CLICKS
     , COALESCE(PAID_IMPRESSIONS, 0) AS PAID_IMPRESSIONS
     , COALESCE(SESSIONS, 0) AS SESSIONS
     , COALESCE(REATTRIBUTIONS, 0) AS REATTRIBUTIONS
FROM {{ source('adjust_api_data', 'REPORT_DAILY_NETWORK_RAW') }}
WHERE DAY IS NOT NULL
