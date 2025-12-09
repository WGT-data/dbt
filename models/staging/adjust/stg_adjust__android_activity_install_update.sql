{{ config(materialized='table', database='ADJUST_S3', schema='DATA', alias='ANDROID_ACTIVITY_INSTALL_UPDATE') }}

SELECT *
FROM ADJUST_S3.DATA.ANDROID_EVENTS
WHERE ACTIVITY_KIND = 'install_update'
