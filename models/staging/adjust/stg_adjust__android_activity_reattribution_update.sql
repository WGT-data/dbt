{{
    config(
        materialized='incremental',
        database='ADJUST_S3',
        schema='DATA',
        alias='ANDROID_ACTIVITY_REATTRIBUTION_UPDATE',
        incremental_strategy='append',
        incremental_predicates=["DATE(DBT_INTERNAL_DEST.LOAD_TIMESTAMP) >= CURRENT_DATE - 1"],
        on_schema_change='append_new_columns'
    )
}}

SELECT *
FROM ADJUST_S3.DATA.ANDROID_EVENTS
WHERE ACTIVITY_KIND = 'reattribution_update'
{% if is_incremental() %}
    AND LOAD_TIMESTAMP > (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }})
{% endif %}
