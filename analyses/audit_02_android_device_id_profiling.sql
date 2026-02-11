/*
 * Android Install Device ID Profiling
 *
 * PURPOSE: Profile device ID columns (GPS_ADID, ADID, IDFV, IDFA) for Android installs.
 * SCOPE: Last 60 days of install events (ACTIVITY_KIND = 'install')
 * SERIES: audit_02 of 03
 */

WITH android_install_samples AS (
    SELECT
        'Android' AS PLATFORM,
        GPS_ADID,
        ADID,
        IDFV,
        IDFA,
        CREATED_AT,
        ROW_NUMBER() OVER (ORDER BY CREATED_AT DESC) AS rn
    FROM ADJUST.S3_DATA.ANDROID_ACTIVITY_INSTALL
    WHERE ACTIVITY_KIND = 'install'
      AND TO_TIMESTAMP(CREATED_AT) >= DATEADD(day, -60, CURRENT_DATE())
)

, android_population_stats AS (
    SELECT
        PLATFORM,
        COUNT(*) AS total_rows,

        -- Population counts
        COUNT(GPS_ADID) AS gps_adid_count,
        COUNT(ADID) AS adid_count,
        COUNT(IDFV) AS idfv_count,
        COUNT(IDFA) AS idfa_count,

        -- Distinct counts
        COUNT(DISTINCT GPS_ADID) AS gps_adid_distinct,
        COUNT(DISTINCT ADID) AS adid_distinct,
        COUNT(DISTINCT IDFV) AS idfv_distinct,
        COUNT(DISTINCT IDFA) AS idfa_distinct,

        -- Population percentages
        ROUND(100.0 * COUNT(GPS_ADID) / COUNT(*), 2) AS gps_adid_pct,
        ROUND(100.0 * COUNT(ADID) / COUNT(*), 2) AS adid_pct,
        ROUND(100.0 * COUNT(IDFV) / COUNT(*), 2) AS idfv_pct,
        ROUND(100.0 * COUNT(IDFA) / COUNT(*), 2) AS idfa_pct

    FROM android_install_samples
)

, android_format_stats AS (
    SELECT
        PLATFORM,

        -- Length statistics
        MIN(LENGTH(GPS_ADID)) AS gps_adid_min_len,
        MAX(LENGTH(GPS_ADID)) AS gps_adid_max_len,
        AVG(LENGTH(GPS_ADID)) AS gps_adid_avg_len,

        MIN(LENGTH(ADID)) AS adid_min_len,
        MAX(LENGTH(ADID)) AS adid_max_len,
        AVG(LENGTH(ADID)) AS adid_avg_len,

        MIN(LENGTH(IDFV)) AS idfv_min_len,
        MAX(LENGTH(IDFV)) AS idfv_max_len,
        AVG(LENGTH(IDFV)) AS idfv_avg_len,

        MIN(LENGTH(IDFA)) AS idfa_min_len,
        MAX(LENGTH(IDFA)) AS idfa_max_len,
        AVG(LENGTH(IDFA)) AS idfa_avg_len,

        -- UUID format validation
        COUNT(CASE WHEN REGEXP_LIKE(GPS_ADID, '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') THEN 1 END) AS gps_adid_uuid_format,
        COUNT(CASE WHEN REGEXP_LIKE(ADID, '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') THEN 1 END) AS adid_uuid_format,
        COUNT(CASE WHEN REGEXP_LIKE(IDFV, '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') THEN 1 END) AS idfv_uuid_format,
        COUNT(CASE WHEN REGEXP_LIKE(IDFA, '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') THEN 1 END) AS idfa_uuid_format,

        -- Uppercase check
        COUNT(CASE WHEN GPS_ADID IS NOT NULL AND GPS_ADID = UPPER(GPS_ADID) THEN 1 END) AS gps_adid_uppercase,
        COUNT(CASE WHEN ADID IS NOT NULL AND ADID = UPPER(ADID) THEN 1 END) AS adid_uppercase,
        COUNT(CASE WHEN IDFV IS NOT NULL AND IDFV = UPPER(IDFV) THEN 1 END) AS idfv_uppercase,
        COUNT(CASE WHEN IDFA IS NOT NULL AND IDFA = UPPER(IDFA) THEN 1 END) AS idfa_uppercase

    FROM android_install_samples
)

, android_samples AS (
    SELECT
        PLATFORM,
        ARRAY_AGG(GPS_ADID) WITHIN GROUP (ORDER BY rn) AS gps_adid_samples,
        ARRAY_AGG(ADID) WITHIN GROUP (ORDER BY rn) AS adid_samples,
        ARRAY_AGG(IDFV) WITHIN GROUP (ORDER BY rn) AS idfv_samples,
        ARRAY_AGG(IDFA) WITHIN GROUP (ORDER BY rn) AS idfa_samples
    FROM (
        SELECT
            PLATFORM,
            GPS_ADID,
            ADID,
            IDFV,
            IDFA,
            rn,
            ROW_NUMBER() OVER (PARTITION BY
                CASE WHEN GPS_ADID IS NOT NULL THEN 1 END,
                CASE WHEN ADID IS NOT NULL THEN 1 END,
                CASE WHEN IDFV IS NOT NULL THEN 1 END,
                CASE WHEN IDFA IS NOT NULL THEN 1 END
                ORDER BY rn
            ) AS sample_rn
        FROM android_install_samples
    )
    WHERE sample_rn <= 5
    GROUP BY PLATFORM
)

SELECT
    ps.PLATFORM,
    ps.total_rows,
    ps.gps_adid_count,
    ps.gps_adid_distinct,
    ps.gps_adid_pct,
    ps.adid_count,
    ps.adid_distinct,
    ps.adid_pct,
    ps.idfv_count,
    ps.idfv_distinct,
    ps.idfv_pct,
    ps.idfa_count,
    ps.idfa_distinct,
    ps.idfa_pct,
    fs.gps_adid_min_len,
    fs.gps_adid_max_len,
    ROUND(fs.gps_adid_avg_len, 1) AS gps_adid_avg_len,
    fs.adid_min_len,
    fs.adid_max_len,
    ROUND(fs.adid_avg_len, 1) AS adid_avg_len,
    fs.idfv_min_len,
    fs.idfv_max_len,
    ROUND(fs.idfv_avg_len, 1) AS idfv_avg_len,
    fs.idfa_min_len,
    fs.idfa_max_len,
    ROUND(fs.idfa_avg_len, 1) AS idfa_avg_len,
    fs.gps_adid_uuid_format,
    fs.adid_uuid_format,
    fs.idfv_uuid_format,
    fs.idfa_uuid_format,
    fs.gps_adid_uppercase,
    fs.adid_uppercase,
    fs.idfv_uppercase,
    fs.idfa_uppercase,
    s.gps_adid_samples,
    s.adid_samples,
    s.idfv_samples,
    s.idfa_samples
FROM android_population_stats ps
JOIN android_format_stats fs ON ps.PLATFORM = fs.PLATFORM
JOIN android_samples s ON ps.PLATFORM = s.PLATFORM
