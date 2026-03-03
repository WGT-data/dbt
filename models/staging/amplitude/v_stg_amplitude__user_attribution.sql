{{
    config(
        materialized='view',
        schema='staging'
    )
}}

/*
    User-level attribution from Amplitude USER_PROPERTIES.
    Extracts [adjust] namespace fields set by the Adjust SDK integration.
    Takes the first event per USER_ID + PLATFORM where [adjust] data exists.
    Grain: one row per USER_ID + PLATFORM.
*/

WITH source AS (

    SELECT
        USER_ID
        , PLATFORM
        , EVENT_TIME
        , USER_PROPERTIES:"[adjust] network"::STRING AS ADJUST_NETWORK
        , USER_PROPERTIES:"[adjust] campaign"::STRING AS ADJUST_CAMPAIGN
        , USER_PROPERTIES:"[adjust] adgroup"::STRING AS ADJUST_ADGROUP
        , USER_PROPERTIES:"[adjust] creative"::STRING AS ADJUST_CREATIVE
        , USER_PROPERTIES:"[adjust] installed_at"::STRING AS ADJUST_INSTALLED_AT
        , USER_PROPERTIES:"[adjust] is_organic"::STRING AS ADJUST_IS_ORGANIC
        , USER_PROPERTIES:"[adjust] country"::STRING AS ADJUST_COUNTRY
    FROM {{ source('amplitude', 'EVENTS_726530') }}
    WHERE USER_ID IS NOT NULL
      AND PLATFORM IN ('iOS', 'Android')
      AND USER_PROPERTIES:"[adjust] network" IS NOT NULL

)

SELECT
    USER_ID
    , PLATFORM
    , ADJUST_NETWORK
    , ADJUST_CAMPAIGN
    , ADJUST_ADGROUP
    , ADJUST_CREATIVE
    , ADJUST_INSTALLED_AT
    , ADJUST_IS_ORGANIC
    , ADJUST_COUNTRY
    , EVENT_TIME AS FIRST_SEEN_AT
FROM source
QUALIFY ROW_NUMBER() OVER (PARTITION BY USER_ID, PLATFORM ORDER BY EVENT_TIME ASC) = 1
