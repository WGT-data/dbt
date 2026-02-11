/*
 * Amplitude Device ID Investigation
 *
 * PURPOSE: Investigate the actual format and characteristics of Amplitude's DEVICE_ID column
 *          to determine if it's a random ID or matches advertising IDs from Adjust.
 *          This is the KEY investigation for understanding Android device ID mapping failure.
 *
 * HOW TO RUN: Copy and paste this entire query into dbt Cloud IDE SQL runner or Snowflake worksheet.
 *             No dbt compilation needed - uses fully qualified table names.
 *
 * EXPECTED OUTPUT: Multiple result sets answering:
 *   Q1: Is Amplitude Android DEVICE_ID a random ID or GPS_ADID?
 *   Q2: Does Amplitude have a separate ADID/advertising_id field?
 *   Q3: Does MERGE_IDS contain device-to-advertising-ID mappings?
 *
 * SCOPE: Last 30 days of event data for performance
 */

-- =============================================================================
-- PART 1: Amplitude DEVICE_ID Format by Platform
-- =============================================================================

WITH amplitude_device_samples AS (
    SELECT
        PLATFORM,
        DEVICE_ID,
        USER_ID,
        SERVER_UPLOAD_TIME,
        ROW_NUMBER() OVER (PARTITION BY PLATFORM ORDER BY SERVER_UPLOAD_TIME DESC) AS rn
    FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
    WHERE SERVER_UPLOAD_TIME >= DATEADD(day, -30, CURRENT_DATE())
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
ORDER BY PLATFORM;


-- =============================================================================
-- PART 2: Sample Device IDs by Platform (Manual Inspection)
-- =============================================================================

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
        SERVER_UPLOAD_TIME,
        ROW_NUMBER() OVER (PARTITION BY PLATFORM ORDER BY SERVER_UPLOAD_TIME DESC) AS rn
    FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
    WHERE SERVER_UPLOAD_TIME >= DATEADD(day, -30, CURRENT_DATE())
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
ORDER BY PLATFORM, rn;


-- =============================================================================
-- PART 3: Amplitude ADID Field Investigation
-- =============================================================================
-- Check if EVENTS table has any columns containing 'ADID', 'ADVERTISING', or related terms

SELECT
    TABLE_CATALOG,
    TABLE_SCHEMA,
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    ORDINAL_POSITION
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'SCHEMA_726530'
  AND TABLE_NAME = 'EVENTS_726530'
  AND (
      UPPER(COLUMN_NAME) LIKE '%ADID%'
      OR UPPER(COLUMN_NAME) LIKE '%ADVERTISING%'
      OR UPPER(COLUMN_NAME) LIKE '%DEVICE_ID%'
      OR UPPER(COLUMN_NAME) LIKE '%GPS%'
      OR UPPER(COLUMN_NAME) LIKE '%GAID%'
      OR UPPER(COLUMN_NAME) LIKE '%IDFA%'
      OR UPPER(COLUMN_NAME) LIKE '%IDFV%'
  )
ORDER BY ORDINAL_POSITION;


-- =============================================================================
-- PART 4: Amplitude EVENTS_726530 Full Column List
-- =============================================================================
-- List all columns to identify any device-related fields we might have missed

SELECT
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    ORDINAL_POSITION
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'SCHEMA_726530'
  AND TABLE_NAME = 'EVENTS_726530'
ORDER BY ORDINAL_POSITION;


-- =============================================================================
-- PART 5: MERGE_IDS Table Structure Investigation
-- =============================================================================

-- First, check what columns exist in MERGE_IDS table
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    ORDINAL_POSITION
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'SCHEMA_726530'
  AND TABLE_NAME = 'MERGE_IDS_726530'
ORDER BY ORDINAL_POSITION;


-- =============================================================================
-- PART 6: MERGE_IDS Table Content Samples
-- =============================================================================

-- Get sample rows to understand what ID mappings exist
SELECT *
FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.MERGE_IDS_726530
LIMIT 20;


-- =============================================================================
-- PART 7: MERGE_IDS Table Profiling Statistics
-- =============================================================================

WITH merge_stats AS (
    SELECT
        COUNT(*) AS total_rows,
        COUNT(DISTINCT AMPLITUDE_ID) AS distinct_amplitude_ids,
        COUNT(DISTINCT MERGED_AMPLITUDE_ID) AS distinct_merged_ids,
        MIN(SERVER_UPLOAD_TIME) AS earliest_upload,
        MAX(SERVER_UPLOAD_TIME) AS latest_upload
    FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.MERGE_IDS_726530
)

SELECT
    total_rows,
    distinct_amplitude_ids,
    distinct_merged_ids,
    earliest_upload,
    latest_upload,
    DATEDIFF(day, earliest_upload, latest_upload) AS days_of_data
FROM merge_stats;


-- =============================================================================
-- PART 8: Cross-Check - Do Any Amplitude Device IDs Match Adjust GPS_ADID?
-- =============================================================================
-- Quick validation query to check if there's ANY overlap (shouldn't be if random IDs)

WITH adjust_android_gps AS (
    SELECT DISTINCT
        UPPER(GPS_ADID) AS gps_adid_upper
    FROM ADJUST.S3_DATA.ANDROID_ACTIVITY_INSTALL
    WHERE ACTIVITY_KIND = 'install'
      AND GPS_ADID IS NOT NULL
      AND CREATED_AT >= DATEADD(day, -30, CURRENT_DATE())
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
      AND SERVER_UPLOAD_TIME >= DATEADD(day, -30, CURRENT_DATE())
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
CROSS JOIN amplitude_android_devices amp;
