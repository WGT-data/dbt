/*
 * Baseline: iOS Touchpoint Match Rate (MTA Attribution)
 *
 * PURPOSE: Match rate for iOS MTA touchpoints (clicks/impressions) to Amplitude events.
 *          iOS touchpoints use IDFA (when available) or IP_ADDRESS for matching.
 *
 * SCOPE: Last 60 days
 * SERIES: baseline_05 of 06
 */

WITH ios_touchpoints AS (
    SELECT DISTINCT
        UPPER(IDFA) AS idfa_normalized,
        IP_ADDRESS,
        'iOS' AS platform
    FROM ADJUST.S3_DATA.IOS_ACTIVITY_CLICK
    WHERE TO_TIMESTAMP(CREATED_AT) >= DATEADD(day, -60, CURRENT_DATE())
      AND (IDFA IS NOT NULL OR IP_ADDRESS IS NOT NULL)

    UNION ALL

    SELECT DISTINCT
        UPPER(IDFA) AS idfa_normalized,
        IP_ADDRESS,
        'iOS' AS platform
    FROM ADJUST.S3_DATA.IOS_ACTIVITY_IMPRESSION
    WHERE TO_TIMESTAMP(CREATED_AT) >= DATEADD(day, -60, CURRENT_DATE())
      AND (IDFA IS NOT NULL OR IP_ADDRESS IS NOT NULL)
)

, ios_touchpoint_stats AS (
    SELECT
        COUNT(*) AS total_touchpoints,
        COUNT(CASE WHEN idfa_normalized IS NOT NULL THEN 1 END) AS idfa_populated_touchpoints,
        COUNT(CASE WHEN IP_ADDRESS IS NOT NULL THEN 1 END) AS ip_populated_touchpoints,
        COUNT(DISTINCT idfa_normalized) AS distinct_idfa,
        COUNT(DISTINCT IP_ADDRESS) AS distinct_ips
    FROM ios_touchpoints
)

, amplitude_ios_devices AS (
    SELECT DISTINCT
        UPPER(DEVICE_ID) AS device_id_normalized,
        IP_ADDRESS,
        'iOS' AS platform
    FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
    WHERE PLATFORM = 'iOS'
      AND DEVICE_ID IS NOT NULL
      AND EVENT_TIME >= DATEADD(day, -60, CURRENT_DATE())
)

, touchpoint_matches AS (
    SELECT
        COUNT(DISTINCT tp.idfa_normalized) AS touchpoint_distinct_idfa,
        COUNT(DISTINCT amp.device_id_normalized) AS amplitude_distinct_devices,

        -- IDFA-to-device_id match (should be ~0% since Amplitude uses IDFV, not IDFA)
        COUNT(DISTINCT CASE
            WHEN tp.idfa_normalized = amp.device_id_normalized
            THEN tp.idfa_normalized
        END) AS idfa_direct_matches

    FROM ios_touchpoints tp
    LEFT JOIN amplitude_ios_devices amp
        ON tp.idfa_normalized = amp.device_id_normalized
    WHERE tp.idfa_normalized IS NOT NULL
)

SELECT
    'iOS MTA Touchpoints' AS match_context,
    ts.total_touchpoints,
    ts.idfa_populated_touchpoints,
    ROUND(100.0 * ts.idfa_populated_touchpoints / NULLIF(ts.total_touchpoints, 0), 2) AS idfa_availability_pct,
    tm.touchpoint_distinct_idfa,
    tm.amplitude_distinct_devices,
    tm.idfa_direct_matches,
    ROUND(100.0 * tm.idfa_direct_matches / NULLIF(tm.touchpoint_distinct_idfa, 0), 2) AS touchpoint_match_rate_pct,
    'iOS touchpoints match via IDFA, but Amplitude uses IDFV. Need IDFA-to-IDFV bridge via installs.' AS interpretation
FROM ios_touchpoint_stats ts
CROSS JOIN touchpoint_matches tm
