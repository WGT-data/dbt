/*
 * Amplitude DEVICE_ID Format by Platform
 *
 * PURPOSE: Investigate the actual format and characteristics of Amplitude's DEVICE_ID column
 *          to determine if it's a random ID or matches advertising IDs from Adjust.
 *
 * SCOPE: Last 30 days, sampled to 100k events per platform for performance
 * SERIES: amplitude_01 of 08
 */

WITH amplitude_device_samples AS (
    SELECT
        PLATFORM,
        DEVICE_ID,
        USER_ID,
        EVENT_TIME,
        ROW_NUMBER() OVER (PARTITION BY PLATFORM ORDER BY EVENT_TIME DESC) AS rn
    FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
    WHERE EVENT_TIME >= DATEADD(day, -30, CURRENT_DATE())
      AND DEVICE_ID IS NOT NULL
      AND PLATFORM IN ('iOS', 'Android')
)

, device_id_stats AS (
    SELECT
        PLATFORM,
        COUNT(*) AS total_events,
        COUNT(DISTINCT DEVICE_ID) AS distinct_devices,
        COUNT(DISTINCT USER_ID) AS distinct_users,

        -- Length distribution
        MIN(LENGTH(DEVICE_ID)) AS device_id_min_len,
        MAX(LENGTH(DEVICE_ID)) AS device_id_max_len,
        ROUND(AVG(LENGTH(DEVICE_ID)), 1) AS device_id_avg_len,

        -- UUID format check (8-4-4-4-12 pattern)
        COUNT(CASE WHEN REGEXP_LIKE(DEVICE_ID, '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') THEN 1 END) AS device_id_uuid_format,
        ROUND(100.0 * COUNT(CASE WHEN REGEXP_LIKE(DEVICE_ID, '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') THEN 1 END) / COUNT(*), 2) AS device_id_uuid_pct,

        -- Android 'R' suffix check (specific to Android Amplitude SDK)
        COUNT(CASE WHEN PLATFORM = 'Android' AND RIGHT(DEVICE_ID, 1) = 'R' THEN 1 END) AS android_r_suffix_count,
        ROUND(100.0 * COUNT(CASE WHEN PLATFORM = 'Android' AND RIGHT(DEVICE_ID, 1) = 'R' THEN 1 END) / NULLIF(COUNT(CASE WHEN PLATFORM = 'Android' THEN 1 END), 0), 2) AS android_r_suffix_pct,

        -- After stripping 'R': does it match UUID pattern?
        COUNT(CASE
            WHEN PLATFORM = 'Android' AND RIGHT(DEVICE_ID, 1) = 'R'
                AND REGEXP_LIKE(LEFT(DEVICE_ID, LENGTH(DEVICE_ID) - 1), '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$')
            THEN 1
        END) AS android_r_stripped_uuid_count,

        -- Uppercase vs lowercase check
        COUNT(CASE WHEN DEVICE_ID = UPPER(DEVICE_ID) THEN 1 END) AS device_id_uppercase,
        COUNT(CASE WHEN DEVICE_ID = LOWER(DEVICE_ID) THEN 1 END) AS device_id_lowercase,
        COUNT(CASE WHEN DEVICE_ID != UPPER(DEVICE_ID) AND DEVICE_ID != LOWER(DEVICE_ID) THEN 1 END) AS device_id_mixed_case

    FROM amplitude_device_samples
    WHERE rn <= 100000  -- Sample for performance
    GROUP BY PLATFORM
)

SELECT
    PLATFORM,
    total_events,
    distinct_devices,
    distinct_users,
    device_id_min_len,
    device_id_max_len,
    device_id_avg_len,
    device_id_uuid_format,
    device_id_uuid_pct,
    android_r_suffix_count,
    android_r_suffix_pct,
    android_r_stripped_uuid_count,
    device_id_uppercase,
    device_id_lowercase,
    device_id_mixed_case
FROM device_id_stats
ORDER BY PLATFORM
