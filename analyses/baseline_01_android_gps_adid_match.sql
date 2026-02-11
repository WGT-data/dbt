/*
 * Baseline: Android GPS_ADID Match Rate
 *
 * PURPOSE: Calculate Android GPS_ADID match rate between Adjust and Amplitude (direct and R-stripped).
 * IMPORTANT: Save results - this is the "before" baseline for Phase 3 normalization validation.
 *
 * SCOPE: Last 60 days
 * DATE RUN: 2026-02-11 (update this when you run the query)
 * SERIES: baseline_01 of 06
 */

WITH adjust_android_devices AS (
    SELECT DISTINCT
        UPPER(GPS_ADID) AS gps_adid_normalized,
        'Android' AS platform
    FROM ADJUST.S3_DATA.ANDROID_ACTIVITY_INSTALL
    WHERE ACTIVITY_KIND = 'install'
      AND GPS_ADID IS NOT NULL
      AND TO_TIMESTAMP(CREATED_AT) >= DATEADD(day, -60, CURRENT_DATE())
)

, amplitude_android_devices AS (
    SELECT DISTINCT
        UPPER(DEVICE_ID) AS device_id_raw,
        CASE
            WHEN RIGHT(DEVICE_ID, 1) = 'R'
            THEN UPPER(LEFT(DEVICE_ID, LENGTH(DEVICE_ID) - 1))
            ELSE UPPER(DEVICE_ID)
        END AS device_id_r_stripped,
        'Android' AS platform
    FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
    WHERE PLATFORM = 'Android'
      AND DEVICE_ID IS NOT NULL
      AND EVENT_TIME >= DATEADD(day, -60, CURRENT_DATE())
)

, android_matches AS (
    SELECT
        COUNT(DISTINCT adj.gps_adid_normalized) AS adjust_android_devices,
        COUNT(DISTINCT amp.device_id_raw) AS amplitude_android_devices,

        -- Direct match attempt (GPS_ADID = DEVICE_ID uppercase)
        COUNT(DISTINCT CASE
            WHEN adj.gps_adid_normalized = amp.device_id_raw
            THEN adj.gps_adid_normalized
        END) AS direct_matches,

        -- R-stripped match attempt (GPS_ADID = DEVICE_ID with 'R' removed)
        COUNT(DISTINCT CASE
            WHEN adj.gps_adid_normalized = amp.device_id_r_stripped
            THEN adj.gps_adid_normalized
        END) AS r_stripped_matches

    FROM adjust_android_devices adj
    LEFT JOIN amplitude_android_devices amp
        ON adj.gps_adid_normalized = amp.device_id_raw
           OR adj.gps_adid_normalized = amp.device_id_r_stripped
)

SELECT
    'Android' AS platform,
    'GPS_ADID' AS match_type,
    adjust_android_devices,
    amplitude_android_devices,
    direct_matches,
    r_stripped_matches,
    ROUND(100.0 * direct_matches / NULLIF(adjust_android_devices, 0), 2) AS direct_match_rate_pct,
    ROUND(100.0 * r_stripped_matches / NULLIF(adjust_android_devices, 0), 2) AS r_stripped_match_rate_pct,
    'Expected: ~0% if Amplitude uses random device IDs' AS interpretation
FROM android_matches
