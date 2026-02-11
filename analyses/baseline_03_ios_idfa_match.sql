/*
 * Baseline: iOS IDFA Match Rate (ATT-Limited)
 *
 * PURPOSE: Calculate iOS IDFA match rate and ATT consent percentage.
 * IMPORTANT: Save results - this is the "before" baseline for Phase 3 normalization validation.
 *
 * SCOPE: Last 60 days
 * DATE RUN: 2026-02-11 (update this when you run the query)
 * SERIES: baseline_03 of 06
 */

WITH adjust_ios_idfa AS (
    SELECT DISTINCT
        UPPER(IDFA) AS idfa_normalized,
        UPPER(IDFV) AS idfv_normalized,
        'iOS' AS platform
    FROM ADJUST.S3_DATA.IOS_ACTIVITY_INSTALL
    WHERE ACTIVITY_KIND = 'install'
      AND IDFA IS NOT NULL  -- Only devices with IDFA consent
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

, ios_idfa_matches AS (
    SELECT
        COUNT(DISTINCT adj.idfa_normalized) AS adjust_ios_idfa_devices,
        COUNT(DISTINCT adj.idfv_normalized) AS adjust_ios_total_devices,
        COUNT(DISTINCT amp.device_id_normalized) AS amplitude_ios_devices,

        -- IDFA match attempt (IDFA = Amplitude device_id)
        COUNT(DISTINCT CASE
            WHEN adj.idfa_normalized = amp.device_id_normalized
            THEN adj.idfa_normalized
        END) AS idfa_matches,

        -- IDFV match for IDFA-consented devices (should be the real match path)
        COUNT(DISTINCT CASE
            WHEN adj.idfv_normalized = amp.device_id_normalized
            THEN adj.idfv_normalized
        END) AS idfa_devices_matched_via_idfv

    FROM adjust_ios_idfa adj
    LEFT JOIN amplitude_ios_devices amp
        ON adj.idfa_normalized = amp.device_id_normalized
           OR adj.idfv_normalized = amp.device_id_normalized
)

SELECT
    'iOS' AS platform,
    'IDFA' AS match_type,
    adjust_ios_idfa_devices AS idfa_consented_devices,
    adjust_ios_total_devices,
    ROUND(100.0 * adjust_ios_idfa_devices / NULLIF(adjust_ios_total_devices, 0), 2) AS idfa_consent_rate_pct,
    amplitude_ios_devices,
    idfa_matches AS idfa_direct_matches,
    idfa_devices_matched_via_idfv AS idfa_devices_matched_via_idfv,
    ROUND(100.0 * idfa_matches / NULLIF(adjust_ios_idfa_devices, 0), 2) AS idfa_match_rate_pct,
    ROUND(100.0 * idfa_devices_matched_via_idfv / NULLIF(adjust_ios_idfa_devices, 0), 2) AS idfv_match_rate_pct,
    'IDFA match ~0% expected (Amplitude uses IDFV). IDFV match is the real attribution path for iOS.' AS interpretation
FROM ios_idfa_matches
