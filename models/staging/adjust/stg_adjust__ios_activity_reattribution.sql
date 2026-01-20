{{
    config(
        materialized='incremental',
        database='ADJUST_S3',
        schema='DATA',
        alias='IOS_ACTIVITY_REATTRIBUTION',
        incremental_strategy='append',
        on_schema_change='append_new_columns'
    )
}}

SELECT *
FROM ADJUST_S3.DATA.IOS_EVENTS
WHERE ACTIVITY_KIND = 'reattribution'
{% if is_incremental() %}
    AND LOAD_TIMESTAMP > (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }})
{% endif %}
