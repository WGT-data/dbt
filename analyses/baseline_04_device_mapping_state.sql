/*
 * Current Production Device Mapping Model State
 *
 * PURPOSE: Query existing int_adjust_amplitude__device_mapping table to see current state.
 *          Tries both DBT_WGTDATA (dev) and PROD schemas.
 *
 * SCOPE: Last 60 days
 * SERIES: baseline_04 of 06
 */

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

ORDER BY source_table, PLATFORM
