-- Adjust API Integration - Network-Level Install & Spend Totals
-- Purpose: Accurate channel-level install counts for MMM
--
-- The granular pipeline (ADJUST.API_DATA.REPORT_DAILY_RAW) uses 17+ dimensions,
-- which causes install undercounts of up to 78% for some networks (Moloco, Apple,
-- TikTok). This lightweight endpoint uses only 5 dimensions (day, app, os_name,
-- partner_name, platform), matching the Adjust dashboard's network-level aggregation.
--
-- This does NOT replace the existing granular pipeline — it supplements it
-- for install counting only. Spend/campaign/creative analysis continues to
-- use the granular data.
--
-- Deployment: Run this entire file in a Snowflake worksheet as SYSADMIN.
--
-- Prerequisites (already deployed):
--   - ADJUST_API external access integration (created by ACCOUNTADMIN)
--   - WGT.PROD.ADJUST_API_KEY secret
--   - WGT.PROD.ADJUST_APP_TOKEN_IOS secret
--   - WGT.PROD.ADJUST_APP_TOKEN_GOOGLE secret

USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================
-- 1. Target table (already created, included for reference)
-- ============================================================

CREATE TABLE IF NOT EXISTS ADJUST.API_DATA.REPORT_DAILY_NETWORK_RAW (
    DAY                 DATE,
    APP                 VARCHAR(256),
    OS_NAME             VARCHAR(64),
    PLATFORM            VARCHAR(64),
    NETWORK             VARCHAR(256),
    PARTNER_NAME        VARCHAR(256),
    INSTALLS            NUMBER(38,0),
    CLICKS              NUMBER(38,0),
    IMPRESSIONS         NUMBER(38,0),
    COST                FLOAT,
    NETWORK_COST        FLOAT,
    ADJUST_COST         FLOAT,
    PAID_INSTALLS       NUMBER(38,0),
    PAID_CLICKS         NUMBER(38,0),
    PAID_IMPRESSIONS    NUMBER(38,0),
    SESSIONS            NUMBER(38,0),
    REATTRIBUTIONS      NUMBER(38,0),
    LOADED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

GRANT SELECT ON TABLE ADJUST.API_DATA.REPORT_DAILY_NETWORK_RAW TO ROLE DBT_ROLE;


-- ============================================================
-- 2. UDF - network-level API call (already deployed)
-- ============================================================
-- Uses ADJUST_API integration and WGT.PROD.ADJUST_API_KEY secret.
-- Only 5 dimensions vs 17+ in the granular pipeline.

CREATE OR REPLACE FUNCTION ADJUST.ADJUST_API.fetch_adjust_network_data(
    app_token VARCHAR,
    start_date VARCHAR,
    end_date VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.9'
PACKAGES = ('requests', 'snowflake-snowpark-python')
EXTERNAL_ACCESS_INTEGRATIONS = (ADJUST_API)
SECRETS = ('api_key' = WGT.PROD.ADJUST_API_KEY)
HANDLER = 'fetch_data'
AS
$$
import requests
import _snowflake

def fetch_data(app_token: str, start_date: str, end_date: str) -> dict:
    api_token = _snowflake.get_generic_secret_string('api_key')
    base_url = "https://automate.adjust.com/reports-service/report"

    dimensions = ["day", "app", "os_name", "partner_name", "platform"]
    metrics = ["installs", "clicks", "impressions", "cost", "network_cost",
               "adjust_cost", "paid_installs", "paid_clicks", "paid_impressions",
               "sessions", "reattributions"]

    headers = {
        "Authorization": f"Bearer {api_token}",
        "Content-Type": "application/json"
    }

    params = {
        "dimensions": ",".join(dimensions),
        "metrics": ",".join(metrics),
        "date_period": f"{start_date}:{end_date}",
        "app_token__in": app_token,
        "currency": "USD",
        "attribution_type": "all",
        "ad_spend_mode": "network"
    }

    try:
        response = requests.get(base_url, headers=headers, params=params, timeout=120)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.HTTPError as e:
        return {"error": f"HTTP Error: {response.status_code} - {response.text}"}
    except requests.exceptions.RequestException as e:
        return {"error": f"Request failed: {str(e)}"}
    except Exception as e:
        return {"error": f"Unexpected error: {str(e)}"}
$$;


-- ============================================================
-- 3. Daily load procedure
-- ============================================================
-- Calls the UDF for both iOS and Google Play, inserts into the
-- network-level table. Uses MERGE to handle re-runs safely.

CREATE OR REPLACE PROCEDURE ADJUST.ADJUST_API.load_network_daily(p_date DATE)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_ios_token VARCHAR DEFAULT 'acqu46kv92ss';
    v_google_token VARCHAR DEFAULT 'q9nlmhlmwjec';
    v_date_str VARCHAR;
    v_rows_before INTEGER;
    v_rows_after INTEGER;
BEGIN
    v_date_str := TO_VARCHAR(:p_date, 'YYYY-MM-DD');

    SELECT COUNT(*) INTO v_rows_before
    FROM ADJUST.API_DATA.REPORT_DAILY_NETWORK_RAW
    WHERE DAY = :p_date;

    -- Delete existing data for this date (simple upsert)
    DELETE FROM ADJUST.API_DATA.REPORT_DAILY_NETWORK_RAW WHERE DAY = :p_date;

    -- Load iOS
    INSERT INTO ADJUST.API_DATA.REPORT_DAILY_NETWORK_RAW
        (DAY, APP, OS_NAME, PLATFORM, NETWORK, PARTNER_NAME, INSTALLS, CLICKS, IMPRESSIONS, COST, NETWORK_COST, ADJUST_COST, PAID_INSTALLS, PAID_CLICKS, PAID_IMPRESSIONS, SESSIONS, REATTRIBUTIONS)
    SELECT TO_DATE(f.value:day::VARCHAR), f.value:app::VARCHAR, f.value:os_name::VARCHAR, f.value:platform::VARCHAR,
           f.value:partner_name::VARCHAR, f.value:partner_name::VARCHAR,
           f.value:installs::NUMBER, f.value:clicks::NUMBER, f.value:impressions::NUMBER,
           f.value:cost::FLOAT, f.value:network_cost::FLOAT, f.value:adjust_cost::FLOAT,
           f.value:paid_installs::NUMBER, f.value:paid_clicks::NUMBER, f.value:paid_impressions::NUMBER,
           f.value:sessions::NUMBER, f.value:reattributions::NUMBER
    FROM TABLE(FLATTEN(input =>
        ADJUST.ADJUST_API.fetch_adjust_network_data(:v_ios_token, :v_date_str, :v_date_str):rows
    )) f;

    -- Load Google Play
    INSERT INTO ADJUST.API_DATA.REPORT_DAILY_NETWORK_RAW
        (DAY, APP, OS_NAME, PLATFORM, NETWORK, PARTNER_NAME, INSTALLS, CLICKS, IMPRESSIONS, COST, NETWORK_COST, ADJUST_COST, PAID_INSTALLS, PAID_CLICKS, PAID_IMPRESSIONS, SESSIONS, REATTRIBUTIONS)
    SELECT TO_DATE(f.value:day::VARCHAR), f.value:app::VARCHAR, f.value:os_name::VARCHAR, f.value:platform::VARCHAR,
           f.value:partner_name::VARCHAR, f.value:partner_name::VARCHAR,
           f.value:installs::NUMBER, f.value:clicks::NUMBER, f.value:impressions::NUMBER,
           f.value:cost::FLOAT, f.value:network_cost::FLOAT, f.value:adjust_cost::FLOAT,
           f.value:paid_installs::NUMBER, f.value:paid_clicks::NUMBER, f.value:paid_impressions::NUMBER,
           f.value:sessions::NUMBER, f.value:reattributions::NUMBER
    FROM TABLE(FLATTEN(input =>
        ADJUST.ADJUST_API.fetch_adjust_network_data(:v_google_token, :v_date_str, :v_date_str):rows
    )) f;

    SELECT COUNT(*) INTO v_rows_after
    FROM ADJUST.API_DATA.REPORT_DAILY_NETWORK_RAW
    WHERE DAY = :p_date;

    RETURN 'Loaded ' || v_rows_after || ' rows for ' || p_date || ' (was ' || v_rows_before || ')';
END;
$$;


-- ============================================================
-- 4. Scheduled tasks
-- ============================================================

-- Daily: load yesterday's data at 6:15 AM UTC
CREATE OR REPLACE TASK ADJUST.ADJUST_API.task_load_network_daily
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 15 6 * * * UTC'
AS
    CALL ADJUST.ADJUST_API.load_network_daily(DATEADD('day', -1, CURRENT_DATE()));

ALTER TASK ADJUST.ADJUST_API.task_load_network_daily RESUME;

-- Weekly: reload last 7 days on Sundays at 7:15 AM UTC to catch late data
CREATE OR REPLACE TASK ADJUST.ADJUST_API.task_network_weekly_refresh
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 15 7 * * 0 UTC'
AS
BEGIN
    CALL ADJUST.ADJUST_API.load_network_daily(DATEADD('day', -7, CURRENT_DATE()));
    CALL ADJUST.ADJUST_API.load_network_daily(DATEADD('day', -6, CURRENT_DATE()));
    CALL ADJUST.ADJUST_API.load_network_daily(DATEADD('day', -5, CURRENT_DATE()));
    CALL ADJUST.ADJUST_API.load_network_daily(DATEADD('day', -4, CURRENT_DATE()));
    CALL ADJUST.ADJUST_API.load_network_daily(DATEADD('day', -3, CURRENT_DATE()));
    CALL ADJUST.ADJUST_API.load_network_daily(DATEADD('day', -2, CURRENT_DATE()));
    CALL ADJUST.ADJUST_API.load_network_daily(DATEADD('day', -1, CURRENT_DATE()));
END;

ALTER TASK ADJUST.ADJUST_API.task_network_weekly_refresh RESUME;


-- ============================================================
-- 5. Manual operations
-- ============================================================
/*
-- Test a single day:
CALL ADJUST.ADJUST_API.load_network_daily('2026-03-10');

-- Check data:
SELECT PARTNER_NAME, SUM(INSTALLS), SUM(COST)
FROM ADJUST.API_DATA.REPORT_DAILY_NETWORK_RAW
WHERE DAY = '2026-03-10'
GROUP BY 1 ORDER BY 2 DESC;

-- Check tasks are running:
SELECT *
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('day', -1, CURRENT_TIMESTAMP()),
    TASK_NAME => 'TASK_LOAD_NETWORK_DAILY'
));
*/
