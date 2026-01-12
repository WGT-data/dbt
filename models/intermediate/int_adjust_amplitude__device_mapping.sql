{{
    config(
        materialized='incremental',
        unique_key=['ADJUST_DEVICE_ID', 'AMPLITUDE_USER_ID', 'PLATFORM'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

SELECT DEVICE_ID_UUID AS ADJUST_DEVICE_ID
     , USER_ID_INTEGER AS AMPLITUDE_USER_ID
     , PLATFORM
     , FIRST_SEEN_AT
FROM {{ ref('v_stg_amplitude__merge_ids') }}
{% if is_incremental() %}
    -- 7-day lookback to capture new device mappings
    WHERE FIRST_SEEN_AT >= DATEADD(day, -7, (SELECT MAX(FIRST_SEEN_AT) FROM {{ this }}))
{% endif %}
