/*
 * Summary: All Match Rates by Platform and Strategy
 *
 * PURPOSE: Single-query summary of device counts by platform.
 *          Note: matched_devices and match_rate_pct are placeholders (0) -
 *          update with actual results from baseline_01 through baseline_03.
 *
 * SCOPE: Last 60 days
 * SERIES: baseline_06 of 06
 */

WITH android_summary AS (
    SELECT
        'Android' AS platform,
        'GPS_ADID (direct)' AS match_strategy,
        (SELECT COUNT(DISTINCT UPPER(GPS_ADID))
         FROM ADJUST.S3_DATA.ANDROID_ACTIVITY_INSTALL
         WHERE ACTIVITY_KIND = 'install' AND GPS_ADID IS NOT NULL
           AND TO_TIMESTAMP(CREATED_AT) >= DATEADD(day, -60, CURRENT_DATE())) AS adjust_devices,
        (SELECT COUNT(DISTINCT UPPER(DEVICE_ID))
         FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
         WHERE PLATFORM = 'Android' AND DEVICE_ID IS NOT NULL
           AND EVENT_TIME >= DATEADD(day, -60, CURRENT_DATE())) AS amplitude_devices,
        0 AS matched_devices,  -- Update with actual query results
        0.0 AS match_rate_pct,
        'Baseline BEFORE Phase 3 normalization' AS notes
)

, ios_idfv_summary AS (
    SELECT
        'iOS' AS platform,
        'IDFV' AS match_strategy,
        (SELECT COUNT(DISTINCT UPPER(IDFV))
         FROM ADJUST.S3_DATA.IOS_ACTIVITY_INSTALL
         WHERE ACTIVITY_KIND = 'install' AND IDFV IS NOT NULL
           AND TO_TIMESTAMP(CREATED_AT) >= DATEADD(day, -60, CURRENT_DATE())) AS adjust_devices,
        (SELECT COUNT(DISTINCT UPPER(DEVICE_ID))
         FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
         WHERE PLATFORM = 'iOS' AND DEVICE_ID IS NOT NULL
           AND EVENT_TIME >= DATEADD(day, -60, CURRENT_DATE())) AS amplitude_devices,
        0 AS matched_devices,  -- Update with actual query results
        0.0 AS match_rate_pct,
        'Baseline BEFORE Phase 3 normalization' AS notes
)

, ios_idfa_summary AS (
    SELECT
        'iOS' AS platform,
        'IDFA (ATT-limited)' AS match_strategy,
        (SELECT COUNT(DISTINCT UPPER(IDFA))
         FROM ADJUST.S3_DATA.IOS_ACTIVITY_INSTALL
         WHERE ACTIVITY_KIND = 'install' AND IDFA IS NOT NULL
           AND TO_TIMESTAMP(CREATED_AT) >= DATEADD(day, -60, CURRENT_DATE())) AS adjust_devices,
        (SELECT COUNT(DISTINCT UPPER(DEVICE_ID))
         FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
         WHERE PLATFORM = 'iOS' AND DEVICE_ID IS NOT NULL
           AND EVENT_TIME >= DATEADD(day, -60, CURRENT_DATE())) AS amplitude_devices,
        0 AS matched_devices,  -- Update with actual query results
        0.0 AS match_rate_pct,
        'Baseline BEFORE Phase 3 normalization (ATT consent ~3%)' AS notes
)

SELECT
    platform,
    match_strategy,
    adjust_devices,
    amplitude_devices,
    matched_devices,
    match_rate_pct,
    notes
FROM android_summary

UNION ALL

SELECT
    platform,
    match_strategy,
    adjust_devices,
    amplitude_devices,
    matched_devices,
    match_rate_pct,
    notes
FROM ios_idfv_summary

UNION ALL

SELECT
    platform,
    match_strategy,
    adjust_devices,
    amplitude_devices,
    matched_devices,
    match_rate_pct,
    notes
FROM ios_idfa_summary

ORDER BY platform, match_strategy
