/*
 * Baseline: iOS IDFV Match Rate
 *
 * PURPOSE: Calculate iOS IDFV match rate between Adjust and Amplitude.
 * IMPORTANT: Save results - this is the "before" baseline for Phase 3 normalization validation.
 *
 * SCOPE: Last 60 days
 * DATE RUN: 2026-02-11 (update this when you run the query)
 * SERIES: baseline_02 of 06
 */

WITH adjust_ios_idfv AS (
    SELECT DISTINCT
        UPPER(IDFV) AS idfv_normalized,
        'iOS' AS platform
    FROM ADJUST.S3_DATA.IOS_ACTIVITY_INSTALL
    WHERE ACTIVITY_KIND = 'install'
      AND IDFV IS NOT NULL
      AND TO_TIMESTAMP(CREATED_AT) >= DATEADD(day, -60, CURRENT_DATE())
)

, amplitude_ios_devices AS (
    SELECT DISTINCT
        UPPER(DEVICE_ID) AS device_id_normalized,
        'iOS' AS platform
    FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
    WHERE PLATFORM = 'iOS'
      AND DEVICE_ID IS NOT NULL
      AND EVENT_TIME >= DATEADD(day, -60, CURRENT_DATE())
)

, ios_idfv_matches AS (
    SELECT
        COUNT(DISTINCT adj.idfv_normalized) AS adjust_ios_idfv_devices,
        COUNT(DISTINCT amp.device_id_normalized) AS amplitude_ios_devices,

        -- IDFV match (expected to work: IDFV = Amplitude device_id)
        COUNT(DISTINCT CASE
            WHEN adj.idfv_normalized = amp.device_id_normalized
            THEN adj.idfv_normalized
        END) AS idfv_matches

    FROM adjust_ios_idfv adj
    LEFT JOIN amplitude_ios_devices amp
        ON adj.idfv_normalized = amp.device_id_normalized
)

SELECT
    'iOS' AS platform,
    'IDFV' AS match_type,
    adjust_ios_idfv_devices,
    amplitude_ios_devices,
    idfv_matches,
    ROUND(100.0 * idfv_matches / NULLIF(adjust_ios_idfv_devices, 0), 2) AS match_rate_pct,
    'Expected: 30-50% match rate (not all iOS installs generate Amplitude events)' AS interpretation
FROM ios_idfv_matches
