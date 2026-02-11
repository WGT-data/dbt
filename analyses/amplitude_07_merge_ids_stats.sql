/*
 * MERGE_IDS Table Profiling Statistics
 *
 * PURPOSE: Get row count for MERGE_IDS table.
 *          Run amplitude_05 first to confirm column names, then expand this query as needed.
 * SERIES: amplitude_07 of 08
 */

SELECT
    COUNT(*) AS total_rows
FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.MERGE_IDS_726530
