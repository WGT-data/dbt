{{
    config(
        materialized='incremental',
        database='ADJUST_S3',
        schema='DATA',
        alias='IOS_ACTIVITY_SK_INSTALL_DIRECT',
        unique_key=['ADID', 'CREATED_AT', 'RANDOM'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

SELECT *
FROM ADJUST_S3.DATA.IOS_EVENTS
WHERE ACTIVITY_KIND = 'sk_install_direct'
{% if is_incremental() %}
    AND LOAD_TIMESTAMP > IFNULL(
        (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }} WHERE LOAD_TIMESTAMP > CURRENT_TIMESTAMP - INTERVAL '1 day'),
        CURRENT_TIMESTAMP - INTERVAL '1 hour'
    )
{% endif %}
