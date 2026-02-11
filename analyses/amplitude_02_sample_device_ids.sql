/*
 * Sample Device IDs by Platform (Manual Inspection)
 *
 * PURPOSE: Show 10 sample device IDs per platform for visual format inspection.
 * SCOPE: Last 30 days
 * SERIES: amplitude_02 of 08
 */

WITH samples AS (
    SELECT
        PLATFORM,
        DEVICE_ID,
        -- For Android with 'R' suffix, show both original and stripped version
        CASE
            WHEN PLATFORM = 'Android' AND RIGHT(DEVICE_ID, 1) = 'R'
            THEN LEFT(DEVICE_ID, LENGTH(DEVICE_ID) - 1)
            ELSE NULL
        END AS device_id_stripped,
        USER_ID,
        EVENT_TIME,
        ROW_NUMBER() OVER (PARTITION BY PLATFORM ORDER BY EVENT_TIME DESC) AS rn
    FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
    WHERE EVENT_TIME >= DATEADD(day, -30, CURRENT_DATE())
      AND DEVICE_ID IS NOT NULL
      AND PLATFORM IN ('iOS', 'Android')
)

SELECT
    PLATFORM,
    DEVICE_ID,
    device_id_stripped,
    USER_ID,
    LENGTH(DEVICE_ID) AS device_id_length,
    CASE
        WHEN REGEXP_LIKE(DEVICE_ID, '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$')
        THEN 'UUID'
        WHEN device_id_stripped IS NOT NULL AND REGEXP_LIKE(device_id_stripped, '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$')
        THEN 'UUID + R suffix'
        ELSE 'Other format'
    END AS format_type
FROM samples
WHERE rn <= 10
ORDER BY PLATFORM, rn
