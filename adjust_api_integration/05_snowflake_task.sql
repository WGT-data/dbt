-- ============================================================================
-- ADJUST API TO SNOWFLAKE INTEGRATION
-- Part 5: Snowflake Task for Scheduled Data Loading
-- ============================================================================
-- This creates a scheduled task that runs daily to load Adjust data
-- ============================================================================

USE ROLE SYSADMIN;
USE DATABASE WGT;
USE SCHEMA ADJUST_API;

-- ============================================================================
-- 1. CREATE WAREHOUSE FOR TASKS (if needed)
-- ============================================================================

CREATE WAREHOUSE IF NOT EXISTS ADJUST_API_WH
    WAREHOUSE_SIZE = 'X-SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse for Adjust API data loading tasks';

-- ============================================================================
-- 2. CREATE DAILY LOAD TASK
-- ============================================================================
-- Runs every day at 6:00 AM UTC (adjust timezone as needed)

CREATE OR REPLACE TASK task_load_adjust_daily
    WAREHOUSE = ADJUST_API_WH
    SCHEDULE = 'USING CRON 0 6 * * * UTC'
    COMMENT = 'Daily load of Adjust campaign data via API'
AS
    CALL WGT.ADJUST_API.load_adjust_daily();

-- ============================================================================
-- 3. CREATE TASK TO RELOAD LAST 7 DAYS (for data corrections)
-- ============================================================================
-- Runs weekly on Sunday at 7:00 AM UTC to catch any late-arriving data

CREATE OR REPLACE TASK task_adjust_weekly_refresh
    WAREHOUSE = ADJUST_API_WH
    SCHEDULE = 'USING CRON 0 7 * * 0 UTC'
    COMMENT = 'Weekly refresh of last 7 days of Adjust data'
AS
    CALL WGT.ADJUST_API.backfill_adjust_data(
        DATEADD('day', -7, CURRENT_DATE()),
        DATEADD('day', -1, CURRENT_DATE())
    );

-- ============================================================================
-- 4. CREATE CLEANUP TASK
-- ============================================================================
-- Removes old staging data and compresses logs monthly

CREATE OR REPLACE TASK task_adjust_monthly_cleanup
    WAREHOUSE = ADJUST_API_WH
    SCHEDULE = 'USING CRON 0 0 1 * * UTC'
    COMMENT = 'Monthly cleanup of staging data and old logs'
AS
BEGIN
    -- Delete staging data older than 7 days
    DELETE FROM WGT.ADJUST_API.ADJ_CAMPAIGN_API_STAGING
    WHERE LOADED_AT < DATEADD('day', -7, CURRENT_TIMESTAMP());

    -- Delete logs older than 90 days
    DELETE FROM WGT.ADJUST_API.API_LOAD_LOG
    WHERE STARTED_AT < DATEADD('day', -90, CURRENT_TIMESTAMP());
END;

-- ============================================================================
-- 5. ENABLE TASKS
-- ============================================================================
-- Tasks are created in suspended state. Enable them when ready.

-- Enable daily task
ALTER TASK task_load_adjust_daily RESUME;

-- Enable weekly refresh task
ALTER TASK task_adjust_weekly_refresh RESUME;

-- Enable monthly cleanup task
ALTER TASK task_adjust_monthly_cleanup RESUME;

-- ============================================================================
-- 6. TASK MANAGEMENT QUERIES
-- ============================================================================

-- View all tasks
-- SHOW TASKS IN SCHEMA WGT.ADJUST_API;

-- View task history
-- SELECT *
-- FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
--     SCHEDULED_TIME_RANGE_START => DATEADD('day', -7, CURRENT_TIMESTAMP()),
--     TASK_NAME => 'TASK_LOAD_ADJUST_DAILY'
-- ))
-- ORDER BY SCHEDULED_TIME DESC;

-- Suspend a task
-- ALTER TASK task_load_adjust_daily SUSPEND;

-- Resume a task
-- ALTER TASK task_load_adjust_daily RESUME;

-- Execute task manually (for testing)
-- EXECUTE TASK task_load_adjust_daily;

-- ============================================================================
-- 7. MONITORING VIEW
-- ============================================================================

CREATE OR REPLACE VIEW v_adjust_load_status AS
SELECT
    LOAD_DATE,
    APP_NAME,
    STATUS,
    ROWS_LOADED,
    ERROR_MESSAGE,
    STARTED_AT,
    COMPLETED_AT,
    DURATION_SECONDS
FROM WGT.ADJUST_API.API_LOAD_LOG
ORDER BY STARTED_AT DESC;

-- View for comparing API data vs Supermetrics
CREATE OR REPLACE VIEW v_adjust_data_comparison AS
SELECT
    'Supermetrics' AS SOURCE,
    MIN(DATE) AS MIN_DATE,
    MAX(DATE) AS MAX_DATE,
    COUNT(*) AS TOTAL_ROWS,
    SUM(INSTALLS) AS TOTAL_INSTALLS,
    SUM(CLICKS) AS TOTAL_CLICKS,
    SUM(COST) AS TOTAL_COST
FROM SUPERMETRICS.DATA_TRANSFERS.ADJ_CAMPAIGN

UNION ALL

SELECT
    'Adjust API' AS SOURCE,
    MIN(DATE) AS MIN_DATE,
    MAX(DATE) AS MAX_DATE,
    COUNT(*) AS TOTAL_ROWS,
    SUM(INSTALLS) AS TOTAL_INSTALLS,
    SUM(CLICKS) AS TOTAL_CLICKS,
    SUM(COST) AS TOTAL_COST
FROM WGT.ADJUST_API.ADJ_CAMPAIGN_API;

GRANT SELECT ON VIEW v_adjust_load_status TO ROLE DBT_ROLE;
GRANT SELECT ON VIEW v_adjust_data_comparison TO ROLE DBT_ROLE;
