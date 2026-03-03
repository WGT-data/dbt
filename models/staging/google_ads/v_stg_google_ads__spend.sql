{{
    config(
        materialized='view',
        schema='staging'
    )
}}

/*
    Google Ads spend staging model.
    Joins CAMPAIGN_STATS with campaign and account history
    to get campaign names and account details.
    Converts COST_MICROS to USD (divide by 1,000,000).
*/

SELECT
    cs.DATE
    , acc.ACCOUNT_ID AS CUSTOMER_ID
    , acc.ACCOUNT_NAME
    , cam.CAMPAIGN_ID
    , cam.CAMPAIGN_NAME
    , cs.COST_MICROS / 1000000.0 AS SPEND
    , cs.IMPRESSIONS
    , cs.CLICKS
FROM {{ source('google_ads', 'CAMPAIGN_STATS') }} cs
LEFT JOIN {{ ref('v_stg_google_ads__campaigns') }} cam
    ON cs.ID = cam.CAMPAIGN_ID
LEFT JOIN {{ ref('v_stg_google_ads__accounts') }} acc
    ON cam.CUSTOMER_ID = acc.ACCOUNT_ID
WHERE cs.COST_MICROS > 0
