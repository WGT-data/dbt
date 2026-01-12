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
    -- 3-day lookback to capture late-arriving data from S3 ingestion
    AND LOAD_TIMESTAMP >= DATEADD(day, -3, (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }}))
{% endif %}
