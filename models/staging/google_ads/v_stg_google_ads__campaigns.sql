{{
    config(
        materialized='view',
        schema='staging'
    )
}}

SELECT
    ID AS CAMPAIGN_ID
    , CUSTOMER_ID
    , NAME AS CAMPAIGN_NAME
    , STATUS AS CAMPAIGN_STATUS
    , ADVERTISING_CHANNEL_TYPE
    , START_DATE
    , END_DATE
    , _FIVETRAN_SYNCED
FROM {{ source('google_ads', 'CAMPAIGN_HISTORY') }}
WHERE _FIVETRAN_ACTIVE = TRUE
