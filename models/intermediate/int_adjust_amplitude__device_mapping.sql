{{
    config(
        materialized='table'
    )
}}

SELECT DEVICE_ID_UUID AS ADJUST_DEVICE_ID
     , USER_ID_INTEGER AS AMPLITUDE_USER_ID
     , PLATFORM
     , FIRST_SEEN_AT
FROM {{ ref('v_stg_amplitude__merge_ids') }}
