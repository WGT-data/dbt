{{
    config(
        materialized='incremental',
        database='ADJUST',
        schema='S3_DATA',
        alias='IOS_ACTIVITY_EVENT',
        incremental_strategy='append',
        on_schema_change='append_new_columns'
    )
}}

SELECT *
FROM ADJUST.{{ get_source_schema('S3_DATA') }}.IOS_EVENTS
WHERE ACTIVITY_KIND = 'event'
{% if is_incremental() %}
    AND LOAD_TIMESTAMP > (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }})
{% endif %}
