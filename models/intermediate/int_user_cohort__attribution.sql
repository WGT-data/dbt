-- int_user_cohort__attribution.sql
-- Links users to their install attribution source (network, campaign, adgroup)
-- Uses Amplitude USER_PROPERTIES [adjust] fields for attribution via USER_ID
-- Grain: One row per user_id/platform combination

{{ config(
    materialized='incremental',
    unique_key=['USER_ID', 'PLATFORM'],
    incremental_strategy='merge',
    tags=['cohort', 'attribution'],
    on_schema_change='append_new_columns'
) }}

WITH amplitude_attribution AS (
    SELECT
        USER_ID
        , PLATFORM
        , ADJUST_NETWORK
        , TRIM(REGEXP_REPLACE(ADJUST_CAMPAIGN, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS CAMPAIGN_NAME
        , TRIM(REGEXP_REPLACE(ADJUST_ADGROUP, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', '')) AS ADGROUP_NAME
        , ADJUST_CREATIVE AS CREATIVE_NAME
        , ADJUST_COUNTRY AS COUNTRY
        , COALESCE(
            TRY_TO_TIMESTAMP(ADJUST_INSTALLED_AT),
            FIRST_SEEN_AT
          ) AS INSTALL_TIME
        , DATE(COALESCE(
            TRY_TO_TIMESTAMP(ADJUST_INSTALLED_AT),
            FIRST_SEEN_AT
          )) AS INSTALL_DATE
    FROM {{ ref('v_stg_amplitude__user_attribution') }}
)

-- Join with network mapping for standardized partner names
, attributed AS (
    SELECT
        a.USER_ID
        , a.PLATFORM
        , NULL AS ADJUST_DEVICE_ID
        , COALESCE(nm.AD_PARTNER, a.ADJUST_NETWORK) AS AD_PARTNER
        , a.ADJUST_NETWORK AS NETWORK_NAME
        , a.CAMPAIGN_NAME
        , a.ADGROUP_NAME
        , a.CREATIVE_NAME
        , a.COUNTRY
        , a.INSTALL_TIME
        , a.INSTALL_DATE
    FROM amplitude_attribution a
    LEFT JOIN {{ ref('network_mapping') }} nm
        ON a.ADJUST_NETWORK = nm.ADJUST_NETWORK_NAME
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
    WHERE INSTALL_TIME >= DATEADD(day, -7, (SELECT MAX(INSTALL_TIME) FROM {{ this }}))
{% endif %}
