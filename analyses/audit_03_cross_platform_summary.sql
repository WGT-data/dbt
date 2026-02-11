/*
 * Cross-Platform Device ID Summary
 *
 * PURPOSE: Compare iOS vs Android device ID strategies side by side.
 *
 * Column Definitions:
 *   GPS_ADID: Google Play Services Advertising ID (Android only, should be NULL for iOS)
 *   ADID: Adjust's internal device hash (both platforms)
 *   IDFV: Identifier for Vendor - Apple's vendor-scoped device ID (iOS only, should be NULL for Android)
 *   IDFA: Identifier for Advertisers - Apple's advertising ID requiring ATT consent
 *         (iOS primary, Android uses this field for GPS_ADID in touchpoints)
 *
 * SCOPE: Last 60 days of install events
 * SERIES: audit_03 of 03
 */

WITH ios_summary AS (
    SELECT
        'iOS' AS PLATFORM,
        COUNT(*) AS total_installs,
        COUNT(IDFV) AS idfv_populated,
        COUNT(IDFA) AS idfa_populated,
        ROUND(100.0 * COUNT(IDFV) / COUNT(*), 2) AS idfv_pct,
        ROUND(100.0 * COUNT(IDFA) / COUNT(*), 2) AS idfa_pct
    FROM ADJUST.S3_DATA.IOS_ACTIVITY_INSTALL
    WHERE ACTIVITY_KIND = 'install'
      AND TO_TIMESTAMP(CREATED_AT) >= DATEADD(day, -60, CURRENT_DATE())
)

, android_summary AS (
    SELECT
        'Android' AS PLATFORM,
        COUNT(*) AS total_installs,
        COUNT(GPS_ADID) AS gps_adid_populated,
        COUNT(IDFA) AS idfa_field_populated,  -- On Android, IDFA field = GPS_ADID in touchpoints
        ROUND(100.0 * COUNT(GPS_ADID) / COUNT(*), 2) AS gps_adid_pct,
        ROUND(100.0 * COUNT(IDFA) / COUNT(*), 2) AS idfa_field_pct
    FROM ADJUST.S3_DATA.ANDROID_ACTIVITY_INSTALL
    WHERE ACTIVITY_KIND = 'install'
      AND TO_TIMESTAMP(CREATED_AT) >= DATEADD(day, -60, CURRENT_DATE())
)

SELECT
    PLATFORM,
    total_installs,
    idfv_populated AS primary_device_id_count,
    idfv_pct AS primary_device_id_pct,
    idfa_populated AS advertising_id_count,
    idfa_pct AS advertising_id_pct,
    'IDFV (100%) is Amplitude match key. IDFA (~3%) is ATT-limited.' AS notes
FROM ios_summary

UNION ALL

SELECT
    PLATFORM,
    total_installs,
    gps_adid_populated AS primary_device_id_count,
    gps_adid_pct AS primary_device_id_pct,
    idfa_field_populated AS advertising_id_count,
    idfa_field_pct AS advertising_id_pct,
    'GPS_ADID (90%+) should match Amplitude but currently does not. IDFA field in touchpoints = GPS_ADID.' AS notes
FROM android_summary
