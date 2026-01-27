-- Adjust API Integration - Scheduled Tasks
-- Sets up automatic daily data loading

USE ROLE SYSADMIN;
USE DATABASE WGT;
USE SCHEMA ADJUST_API;

-- Dedicated warehouse for API tasks
CREATE WAREHOUSE IF NOT EXISTS ADJUST_API_WH
    WAREHOUSE_SIZE = 'X-SMALL'
    AUTO_SUSPEND = 6
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

-- Daily task - runs at 6 AM UTC, loads yesterday's data
CREATE OR REPLACE TASK task_load_adjust_daily
    WAREHOUSE = ADJUST_API_WH
    SCHEDULE = 'USING CRON 0 6 * * * UTC'
AS
    CALL WGT.ADJUST_API.load_adjust_daily();

-- Weekly refresh - Sundays at 7 AM UTC, reloads last 7 days to catch late data
CREATE OR REPLACE TASK task_adjust_weekly_refresh
    WAREHOUSE = ADJUST_API_WH
    SCHEDULE = 'USING CRON 0 7 * * 0 UTC'
AS
    CALL WGT.ADJUST_API.backfill_adjust_data(
        DATEADD('day', -7, CURRENT_DATE()),
        DATEADD('day', -1, CURRENT_DATE())
    );

-- Monthly cleanup - 1st of each month, clears old staging data and logs
CREATE OR REPLACE TASK task_adjust_monthly_cleanup
    WAREHOUSE = ADJUST_API_WH
    SCHEDULE = 'USING CRON 0 0 1 * * UTC'
AS
BEGIN
    DELETE FROM WGT.ADJUST_API.ADJ_CAMPAIGN_API_STAGING
    WHERE LOADED_AT < DATEADD('day', -7, CURRENT_TIMESTAMP());

    DELETE FROM WGT.ADJUST_API.API_LOAD_LOG
    WHERE STARTED_AT < DATEADD('day', -90, CURRENT_TIMESTAMP());
END;

-- Turn on the tasks
ALTER TASK task_load_adjust_daily RESUME;
ALTER TASK task_adjust_weekly_refresh RESUME;
ALTER TASK task_adjust_monthly_cleanup RESUME;

-- Handy queries for managing tasks:
-- SHOW TASKS IN SCHEMA WGT.ADJUST_API;
-- ALTER TASK task_load_adjust_daily SUSPEND;
-- ALTER TASK task_load_adjust_daily RESUME;
-- EXECUTE TASK task_load_adjust_daily;  -- run manually

-- Monitoring views
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
