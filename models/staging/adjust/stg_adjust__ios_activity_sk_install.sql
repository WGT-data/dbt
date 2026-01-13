{{
    config(
        materialized='incremental',
        database='ADJUST_S3',
        schema='DATA',
        alias='IOS_ACTIVITY_SK_INSTALL',
        incremental_strategy='append',
        on_schema_change='append_new_columns'
    )
}}

SELECT *
FROM ADJUST_S3.DATA.IOS_EVENTS
WHERE ACTIVITY_KIND = 'sk_install'
{% if is_incremental() %}
WHERE LOAD_TIMESTAMP > IFNULL((SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }} WHERE LOAD_TIMESTAMP > current_timestamp - interval '1 day'), CURRENT_TIMESTAMP - interval '1 hour')
{% endif %}
