{{
    config(
        materialized='incremental',
        database='ADJUST_S3',
        schema='DATA',
        alias='ANDROID_ACTIVITY_CLICK',
        unique_key=['GPS_ADID', 'CREATED_AT', 'RANDOM'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

SELECT *
FROM ADJUST_S3.DATA.ANDROID_EVENTS
WHERE ACTIVITY_KIND = 'click'
{% if is_incremental() %}
    AND LOAD_TIMESTAMP > IFNULL(
        (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }} WHERE LOAD_TIMESTAMP > CURRENT_TIMESTAMP - INTERVAL '1 day'),
        CURRENT_TIMESTAMP - INTERVAL '1 hour'
    )
{% endif %}
