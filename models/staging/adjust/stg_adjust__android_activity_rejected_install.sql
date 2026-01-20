{{
    config(
        materialized='incremental',
        database='ADJUST_S3',
        schema='PROD_DATA',
        alias='ANDROID_ACTIVITY_REJECTED_INSTALL',
        incremental_strategy='append',
        on_schema_change='append_new_columns'
    )
}}

SELECT *
FROM ADJUST_S3.DATA.ANDROID_EVENTS
WHERE ACTIVITY_KIND = 'rejected_install'
{% if is_incremental() %}
    AND LOAD_TIMESTAMP > (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }})
{% endif %}
