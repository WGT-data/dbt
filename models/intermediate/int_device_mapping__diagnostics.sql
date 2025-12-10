{{config(materialized = "table")}}

-- Device Mapping Diagnostics
-- Surfaces users with multiple device mappings for data quality review
-- Users with 100+ devices likely represent test accounts, fraud, or shared demo devices

WITH DEVICE_MAPPING AS (
    SELECT *
    FROM {{ ref('int_adjust_amplitude__device_mapping') }}
)

, USER_DEVICE_COUNTS AS (
    SELECT AMPLITUDE_USER_ID
         , PLATFORM
         , COUNT(DISTINCT ADJUST_DEVICE_ID) AS DEVICE_COUNT
         , MIN(FIRST_SEEN_AT) AS FIRST_DEVICE_SEEN
         , MAX(FIRST_SEEN_AT) AS LAST_DEVICE_ADDED
    FROM DEVICE_MAPPING
    WHERE AMPLITUDE_USER_ID IS NOT NULL
    GROUP BY AMPLITUDE_USER_ID
         , PLATFORM
)

, DEVICE_COUNT_BUCKETS AS (
    SELECT AMPLITUDE_USER_ID
         , PLATFORM
         , DEVICE_COUNT
         , FIRST_DEVICE_SEEN
         , LAST_DEVICE_ADDED
         , CASE 
             WHEN DEVICE_COUNT = 1 THEN '1 device'
             WHEN DEVICE_COUNT BETWEEN 2 AND 5 THEN '2-5 devices'
             WHEN DEVICE_COUNT BETWEEN 6 AND 10 THEN '6-10 devices'
             WHEN DEVICE_COUNT BETWEEN 11 AND 50 THEN '11-50 devices'
             WHEN DEVICE_COUNT BETWEEN 51 AND 100 THEN '51-100 devices'
             WHEN DEVICE_COUNT BETWEEN 101 AND 500 THEN '101-500 devices'
             WHEN DEVICE_COUNT BETWEEN 501 AND 1000 THEN '501-1000 devices'
             ELSE '1000+ devices'
           END AS DEVICE_COUNT_BUCKET
         , CASE 
             WHEN DEVICE_COUNT >= 100 THEN TRUE 
             ELSE FALSE 
           END AS IS_ANOMALOUS
    FROM USER_DEVICE_COUNTS
)

SELECT AMPLITUDE_USER_ID
     , PLATFORM
     , DEVICE_COUNT
     , DEVICE_COUNT_BUCKET
     , IS_ANOMALOUS
     , FIRST_DEVICE_SEEN
     , LAST_DEVICE_ADDED
     , DATEDIFF('day', FIRST_DEVICE_SEEN, LAST_DEVICE_ADDED) AS DAYS_ACTIVE
FROM DEVICE_COUNT_BUCKETS
ORDER BY DEVICE_COUNT DESC
