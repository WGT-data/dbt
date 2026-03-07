{{
    config(
        materialized='view',
        schema='staging'
    )
}}

/*
    Google Ads country-level spend staging model.
    Uses CAMPAIGN_COUNTRY_REPORT for country-granular spend data.
    Joins with campaign and account history for names.
    Converts COST_MICROS to USD (divide by 1,000,000).

    COUNTRY_CRITERION_ID uses ISO 3166-1 numeric codes (e.g., 2840 = US).
    Mapped to full country names via country_codes seed.
*/

SELECT
    ccr.DATE
    , acc.ACCOUNT_ID AS CUSTOMER_ID
    , acc.ACCOUNT_NAME
    , cam.CAMPAIGN_ID
    , cam.CAMPAIGN_NAME
    , COALESCE(cc.COUNTRY_NAME, '__none__') AS COUNTRY
    , CASE
        WHEN UPPER(cam.CAMPAIGN_NAME) LIKE '%IOS%'
          OR UPPER(cam.CAMPAIGN_NAME) LIKE '%IPHONE%'
          OR UPPER(cam.CAMPAIGN_NAME) LIKE '%GOLFI OS%'
          THEN 'iOS'
        WHEN UPPER(cam.CAMPAIGN_NAME) LIKE '%ANDROID%'
          THEN 'Android'
        WHEN UPPER(cam.CAMPAIGN_NAME) LIKE '%DESKTOP%'
          OR UPPER(cam.CAMPAIGN_NAME) LIKE '%WEB %'
          OR UPPER(cam.CAMPAIGN_NAME) LIKE 'WEB %'
          OR cam.ADVERTISING_CHANNEL_TYPE IN ('SEARCH', 'DISPLAY', 'DEMAND_GEN')
          THEN 'Desktop'
        ELSE 'Unknown'
      END AS PLATFORM
    , ccr.COST_MICROS / 1000000.0 AS SPEND
    , ccr.IMPRESSIONS
    , ccr.CLICKS
FROM {{ source('google_ads', 'CAMPAIGN_COUNTRY_REPORT') }} ccr
LEFT JOIN {{ ref('v_stg_google_ads__campaigns') }} cam
    ON ccr.CAMPAIGN_ID = cam.CAMPAIGN_ID
LEFT JOIN {{ ref('v_stg_google_ads__accounts') }} acc
    ON cam.CUSTOMER_ID = acc.ACCOUNT_ID
LEFT JOIN {{ ref('country_codes') }} cc
    ON ccr.COUNTRY_CRITERION_ID = cc.CODE_NUMERIC + 2000
WHERE ccr.COST_MICROS > 0
