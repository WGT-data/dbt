{{
    config(
        materialized='incremental',
        unique_key=['USER_ID', 'DEVICE_ID', 'EVENT_TIME', 'EVENT_TYPE'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

SELECT USER_ID
     , DEVICE_ID
     , EVENT_TYPE
     , EVENT_TIME
     , EVENT_PROPERTIES
     , PLATFORM
     , SERVER_UPLOAD_TIME
FROM {{ source('amplitude', 'EVENTS_726530') }}
WHERE SERVER_UPLOAD_TIME >= '2025-01-01'
{% if is_incremental() %}
    -- 3-day lookback to capture late-arriving events based on server upload time
    AND SERVER_UPLOAD_TIME >= DATEADD(day, -3, (SELECT MAX(SERVER_UPLOAD_TIME) FROM {{ this }}))
{% endif %}