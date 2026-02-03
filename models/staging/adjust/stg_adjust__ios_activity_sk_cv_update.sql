{{
    config(
        materialized='incremental',
        database='ADJUST',
        schema='S3_DATA',
        alias='IOS_ACTIVITY_SK_CV_UPDATE',
        incremental_strategy='append',
        on_schema_change='append_new_columns'
    )
}}

SELECT *
FROM ADJUST.S3_DATA.IOS_EVENTS
WHERE ACTIVITY_KIND = 'sk_cv_update'
{% if is_incremental() %}
    AND LOAD_TIMESTAMP > (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }})
{% endif %}
