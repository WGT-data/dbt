{{ config(materialized='table', database='ADJUST_S3', schema='DATA', alias='IOS_ACTIVITY_ATT_UPDATE') }}

SELECT *
FROM ADJUST_S3.DATA.IOS_EVENTS
WHERE ACTIVITY_KIND = 'att_update'
