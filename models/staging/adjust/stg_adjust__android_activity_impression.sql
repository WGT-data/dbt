{{
    config(
        materialized='incremental',
        database='ADJUST_S3',
        schema='DATA',
        alias='ANDROID_ACTIVITY_IMPRESSION',
        incremental_strategy='append',
        on_schema_change='append_new_columns'
    )
}}

SELECT *
FROM ADJUST_S3.DATA.ANDROID_EVENTS
WHERE ACTIVITY_KIND = 'impression'
{% if is_incremental() %}
WHERE LOAD_TIMESTAMP > IFNULL((SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }} WHERE LOAD_TIMESTAMP > current_timestamp - interval '1 day'), CURRENT_TIMESTAMP - interval '1 hour')
{% endif %}
