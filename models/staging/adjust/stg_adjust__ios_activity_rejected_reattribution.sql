{{ config(materialized='table', database='ADJUST_S3', schema='DATA', alias='IOS_ACTIVITY_REJECTED_REATTRIBUTION') }}

SELECT *
FROM ADJUST_S3.DATA.IOS_EVENTS
WHERE ACTIVITY_KIND = 'rejected_reattribution'
