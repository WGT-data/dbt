{{
    config(
        materialized='incremental',
        database='ADJUST_S3',
        schema='DATA',
        alias='IOS_ACTIVITY_INSTALL_UPDATE',
        incremental_strategy='append',
        incremental_predicates=["DATE(DBT_INTERNAL_DEST.LOAD_TIMESTAMP) >= CURRENT_DATE - 1"],
        on_schema_change='append_new_columns'
    )
}}

SELECT *
FROM ADJUST_S3.DATA.IOS_EVENTS
WHERE ACTIVITY_KIND = 'install_update'
{% if is_incremental() %}
    AND LOAD_TIMESTAMP > (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }})
{% endif %}
