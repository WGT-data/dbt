{{
    config(
        materialized='incremental',
        unique_key=['USER_ID', 'EVENT_TIME', 'EVENT_TYPE'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

SELECT USER_ID
     , EVENT_TYPE
     , EVENT_TIME
     , EVENT_PROPERTIES:"$revenue"::DOUBLE AS REVENUE_AMOUNT
     , PLATFORM
     , COUNTRY
FROM {{ source('revenue', 'DIRECT_REVENUE_EVENTS') }}
WHERE EVENT_TIME >= '2025-01-01'
{% if is_incremental() %}
    -- 3-day lookback to capture late-arriving revenue events
    AND EVENT_TIME >= DATEADD(day, -3, (SELECT MAX(EVENT_TIME) FROM {{ this }}))
{% endif %}