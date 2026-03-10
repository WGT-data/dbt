-- test_adjust_amplitude_mapping_staleness.sql
-- Detects when the device mapping table hasn't been refreshed in >30 days.
--
-- Checks the dbt-managed int_adjust_amplitude__device_mapping table in the target schema.
-- Stale mapping data causes silent device matching degradation.
--
-- Test passes when zero rows returned (table was updated within 30 days).
-- Test fails when table hasn't been updated in >30 days.

SELECT
    TABLE_CATALOG AS database_name,
    TABLE_SCHEMA AS schema_name,
    TABLE_NAME,
    LAST_ALTERED,
    DATEDIFF('day', LAST_ALTERED, CURRENT_TIMESTAMP()) AS days_since_update,
    ROW_COUNT,
    'Device mapping table stale - last updated ' ||
      DATEDIFF('day', LAST_ALTERED, CURRENT_TIMESTAMP()) || ' days ago' AS failure_reason
FROM WGT.INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME = 'INT_ADJUST_AMPLITUDE__DEVICE_MAPPING'
  AND TABLE_SCHEMA = 'DBT_WGTDATA'
  AND DATEDIFF('day', LAST_ALTERED, CURRENT_TIMESTAMP()) > 30
