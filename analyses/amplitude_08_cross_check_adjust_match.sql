/*
 * Cross-Check: Do Any Amplitude Device IDs Match Adjust GPS_ADID?
 *
 * PURPOSE: Quick validation to check if there's ANY overlap between Amplitude device IDs
 *          and Adjust GPS_ADID. Expected: 0 matches if Amplitude uses random device IDs.
 *
 * SCOPE: Last 30 days, sampled to 1000 per source for performance
 * SERIES: amplitude_08 of 08
 */

WITH adjust_android_gps AS (
    SELECT DISTINCT
        UPPER(GPS_ADID) AS gps_adid_upper
    FROM ADJUST.S3_DATA.ANDROID_ACTIVITY_INSTALL
    WHERE ACTIVITY_KIND = 'install'
      AND GPS_ADID IS NOT NULL
      AND TO_TIMESTAMP(CREATED_AT) >= DATEADD(day, -30, CURRENT_DATE())
    LIMIT 1000  -- Sample for performance
)

, amplitude_android_devices AS (
    SELECT DISTINCT
        UPPER(DEVICE_ID) AS device_id_upper,
        CASE
            WHEN RIGHT(DEVICE_ID, 1) = 'R'
            THEN UPPER(LEFT(DEVICE_ID, LENGTH(DEVICE_ID) - 1))
            ELSE UPPER(DEVICE_ID)
        END AS device_id_normalized
    FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
    WHERE PLATFORM = 'Android'
      AND DEVICE_ID IS NOT NULL
      AND EVENT_TIME >= DATEADD(day, -30, CURRENT_DATE())
    LIMIT 1000  -- Sample for performance
)

SELECT
    COUNT(DISTINCT aa.gps_adid_upper) AS adjust_gps_adid_sample,
    COUNT(DISTINCT amp.device_id_upper) AS amplitude_device_sample,
    COUNT(DISTINCT CASE
        WHEN aa.gps_adid_upper = amp.device_id_upper
        THEN aa.gps_adid_upper
    END) AS direct_matches,
    COUNT(DISTINCT CASE
        WHEN aa.gps_adid_upper = amp.device_id_normalized
        THEN aa.gps_adid_upper
    END) AS r_stripped_matches,
    'Expected: 0 matches if Amplitude uses random device IDs' AS interpretation
FROM adjust_android_gps aa
CROSS JOIN amplitude_android_devices amp
