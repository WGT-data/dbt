{{
    config(
        materialized='view',
        schema='staging'
    )
}}

SELECT
    ID AS ACCOUNT_ID
    , DESCRIPTIVE_NAME AS ACCOUNT_NAME
    , CURRENCY_CODE
    , TIME_ZONE
    , _FIVETRAN_SYNCED
FROM {{ source('google_ads', 'ACCOUNT_HISTORY') }}
WHERE _FIVETRAN_ACTIVE = TRUE
