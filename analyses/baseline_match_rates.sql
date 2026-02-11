/*
 * Baseline Match Rates Between Adjust and Amplitude
 *
 * PURPOSE: Calculate current device ID match rates BEFORE Phase 3 normalization changes.
 *          This establishes the "before" snapshot that will validate improvement after normalization.
 *
 * IMPORTANT: These numbers are the baseline. Save these results and run again after Phase 3
 *            to measure normalization effectiveness.
 *
 * HOW TO RUN: Copy and paste this entire query into dbt Cloud IDE SQL runner or Snowflake worksheet.
 *             No dbt compilation needed - uses fully qualified table names.
 *
 * EXPECTED OUTPUT: Multiple result sets showing match rates by platform and match strategy:
 *   - Android GPS_ADID direct match
 *   - Android GPS_ADID with 'R' suffix stripped
 *   - iOS IDFV match
 *   - iOS IDFA match
 *   - Current production device_mapping model state
 *
 * SCOPE: Last 60 days of data
 * DATE RUN: 2026-02-11 (update this when you run the query)
 */

-- =============================================================================
-- PART 1: Android GPS_ADID Match Rate
-- =============================================================================

WITH adjust_android_devices AS (
    SELECT DISTINCT
        UPPER(GPS_ADID) AS gps_adid_normalized,
        'Android' AS platform
    FROM ADJUST.S3_DATA.ANDROID_ACTIVITY_INSTALL
    WHERE ACTIVITY_KIND = 'install'
      AND GPS_ADID IS NOT NULL
      AND CREATED_AT >= DATEADD(day, -60, CURRENT_DATE())
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
      AND TO_TIMESTAMP(EVENT_TIME) >= DATEADD(day, -60, CURRENT_DATE())
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
FROM android_matches;


-- =============================================================================
-- PART 2: iOS IDFV Match Rate
-- =============================================================================

WITH adjust_ios_idfv AS (
    SELECT DISTINCT
        UPPER(IDFV) AS idfv_normalized,
        'iOS' AS platform
    FROM ADJUST.S3_DATA.IOS_ACTIVITY_INSTALL
    WHERE ACTIVITY_KIND = 'install'
      AND IDFV IS NOT NULL
      AND CREATED_AT >= DATEADD(day, -60, CURRENT_DATE())
)

, amplitude_ios_devices AS (
    SELECT DISTINCT
        UPPER(DEVICE_ID) AS device_id_normalized,
        'iOS' AS platform
    FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
    WHERE PLATFORM = 'iOS'
      AND DEVICE_ID IS NOT NULL
      AND TO_TIMESTAMP(EVENT_TIME) >= DATEADD(day, -60, CURRENT_DATE())
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
FROM ios_idfv_matches;


-- =============================================================================
-- PART 3: iOS IDFA Match Rate (ATT-Limited)
-- =============================================================================

WITH adjust_ios_idfa AS (
    SELECT DISTINCT
        UPPER(IDFA) AS idfa_normalized,
        UPPER(IDFV) AS idfv_normalized,
        'iOS' AS platform
    FROM ADJUST.S3_DATA.IOS_ACTIVITY_INSTALL
    WHERE ACTIVITY_KIND = 'install'
      AND IDFA IS NOT NULL  -- Only devices with IDFA consent
      AND CREATED_AT >= DATEADD(day, -60, CURRENT_DATE())
)

, amplitude_ios_devices AS (
    SELECT DISTINCT
        UPPER(DEVICE_ID) AS device_id_normalized,
        'iOS' AS platform
    FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
    WHERE PLATFORM = 'iOS'
      AND DEVICE_ID IS NOT NULL
      AND TO_TIMESTAMP(EVENT_TIME) >= DATEADD(day, -60, CURRENT_DATE())
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
FROM ios_idfa_matches;


-- =============================================================================
-- PART 4: Current Production Device Mapping Model State
-- =============================================================================
-- Query existing int_adjust_amplitude__device_mapping table to see current state

-- Try DBT_WGTDATA schema (dev) first
SELECT
    'DBT_WGTDATA.INT_ADJUST_AMPLITUDE__DEVICE_MAPPING' AS source_table,
    PLATFORM,
    COUNT(*) AS total_mappings,
    COUNT(DISTINCT ADJUST_DEVICE_ID) AS distinct_adjust_devices,
    COUNT(DISTINCT AMPLITUDE_USER_ID) AS distinct_amplitude_users,
    MIN(FIRST_SEEN_AT) AS earliest_mapping,
    MAX(FIRST_SEEN_AT) AS latest_mapping
FROM DBT_WGTDATA.INT_ADJUST_AMPLITUDE__DEVICE_MAPPING
WHERE FIRST_SEEN_AT >= DATEADD(day, -60, CURRENT_DATE())
GROUP BY PLATFORM

UNION ALL

-- Try PROD schema (prod) next
SELECT
    'PROD.INT_ADJUST_AMPLITUDE__DEVICE_MAPPING' AS source_table,
    PLATFORM,
    COUNT(*) AS total_mappings,
    COUNT(DISTINCT ADJUST_DEVICE_ID) AS distinct_adjust_devices,
    COUNT(DISTINCT AMPLITUDE_USER_ID) AS distinct_amplitude_users,
    MIN(FIRST_SEEN_AT) AS earliest_mapping,
    MAX(FIRST_SEEN_AT) AS latest_mapping
FROM PROD.INT_ADJUST_AMPLITUDE__DEVICE_MAPPING
WHERE FIRST_SEEN_AT >= DATEADD(day, -60, CURRENT_DATE())
GROUP BY PLATFORM

ORDER BY source_table, PLATFORM;


-- =============================================================================
-- PART 5: iOS Touchpoint Match Rate (MTA Attribution)
-- =============================================================================
-- Match rate for iOS MTA touchpoints (clicks/impressions) to Amplitude events
-- iOS touchpoints use IDFA (when available) or IP_ADDRESS for matching

WITH ios_touchpoints AS (
    SELECT DISTINCT
        UPPER(IDFA) AS idfa_normalized,
        IP_ADDRESS,
        'iOS' AS platform
    FROM ADJUST.S3_DATA.IOS_ACTIVITY_CLICK
    WHERE CREATED_AT >= DATEADD(day, -60, CURRENT_DATE())
      AND (IDFA IS NOT NULL OR IP_ADDRESS IS NOT NULL)

    UNION ALL

    SELECT DISTINCT
        UPPER(IDFA) AS idfa_normalized,
        IP_ADDRESS,
        'iOS' AS platform
    FROM ADJUST.S3_DATA.IOS_ACTIVITY_IMPRESSION
    WHERE CREATED_AT >= DATEADD(day, -60, CURRENT_DATE())
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
      AND TO_TIMESTAMP(EVENT_TIME) >= DATEADD(day, -60, CURRENT_DATE())
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
CROSS JOIN touchpoint_matches tm;


-- =============================================================================
-- PART 6: Summary - All Match Rates by Platform and Strategy
-- =============================================================================

WITH android_summary AS (
    SELECT
        'Android' AS platform,
        'GPS_ADID (direct)' AS match_strategy,
        (SELECT COUNT(DISTINCT UPPER(GPS_ADID))
         FROM ADJUST.S3_DATA.ANDROID_ACTIVITY_INSTALL
         WHERE ACTIVITY_KIND = 'install' AND GPS_ADID IS NOT NULL
           AND CREATED_AT >= DATEADD(day, -60, CURRENT_DATE())) AS adjust_devices,
        (SELECT COUNT(DISTINCT UPPER(DEVICE_ID))
         FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
         WHERE PLATFORM = 'Android' AND DEVICE_ID IS NOT NULL
           AND TO_TIMESTAMP(EVENT_TIME) >= DATEADD(day, -60, CURRENT_DATE())) AS amplitude_devices,
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
           AND CREATED_AT >= DATEADD(day, -60, CURRENT_DATE())) AS adjust_devices,
        (SELECT COUNT(DISTINCT UPPER(DEVICE_ID))
         FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
         WHERE PLATFORM = 'iOS' AND DEVICE_ID IS NOT NULL
           AND TO_TIMESTAMP(EVENT_TIME) >= DATEADD(day, -60, CURRENT_DATE())) AS amplitude_devices,
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
           AND CREATED_AT >= DATEADD(day, -60, CURRENT_DATE())) AS adjust_devices,
        (SELECT COUNT(DISTINCT UPPER(DEVICE_ID))
         FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
         WHERE PLATFORM = 'iOS' AND DEVICE_ID IS NOT NULL
           AND TO_TIMESTAMP(EVENT_TIME) >= DATEADD(day, -60, CURRENT_DATE())) AS amplitude_devices,
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

ORDER BY platform, match_strategy;
