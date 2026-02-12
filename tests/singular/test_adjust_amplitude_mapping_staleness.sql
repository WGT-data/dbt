-- test_adjust_amplitude_mapping_staleness.sql
-- Detects when the ADJUST_AMPLITUDE_DEVICE_MAPPING static table hasn't been refreshed in >30 days.
--
-- This test monitors the staleness of the static mapping table via INFORMATION_SCHEMA.TABLES.LAST_ALTERED.
-- Stale mapping data causes silent device matching degradation, reducing the accuracy of user journey tracking.
--
-- Test passes when zero rows returned (table was updated within 30 days).
-- Test fails when table hasn't been updated in >30 days, returning diagnostic info for investigation.

SELECT
    TABLE_CATALOG AS database_name,
    TABLE_SCHEMA AS schema_name,
    TABLE_NAME,
    LAST_ALTERED,
    DATEDIFF('day', LAST_ALTERED, CURRENT_TIMESTAMP()) AS days_since_update,
    ROW_COUNT,
    'Static mapping table stale - last updated ' ||
      DATEDIFF('day', LAST_ALTERED, CURRENT_TIMESTAMP()) || ' days ago' AS failure_reason
FROM ADJUST.INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME = 'ADJUST_AMPLITUDE_DEVICE_MAPPING'
  AND DATEDIFF('day', LAST_ALTERED, CURRENT_TIMESTAMP()) > 30
