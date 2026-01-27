-- ============================================================================
-- ADJUST API TO SNOWFLAKE INTEGRATION
-- Part 1: Snowflake Objects Setup
-- ============================================================================
-- This script creates the necessary Snowflake objects to replicate the
-- SUPERMETRICS.DATA_TRANSFERS.ADJ_CAMPAIGN table using the Adjust Reports API
-- ============================================================================

-- Use appropriate role and warehouse
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE WGT;

-- Create a dedicated schema for Adjust API data
CREATE SCHEMA IF NOT EXISTS ADJUST_API;
USE SCHEMA ADJUST_API;

-- ============================================================================
-- 1. CREATE TARGET TABLE (matching Supermetrics structure)
-- ============================================================================

CREATE TABLE IF NOT EXISTS ADJ_CAMPAIGN_API (
    -- Dimensions (from Adjust API)
    AD_ID                   VARCHAR(256)    COMMENT 'Creative ID from the network (creative_id)',
    AD_NAME                 VARCHAR(1024)   COMMENT 'Creative name from the network (creative)',
    ADGROUP_ID_NETWORK      VARCHAR(256)    COMMENT 'Adgroup ID from the network (adgroup_id_network)',
    ADGROUP_NETWORK         VARCHAR(1024)   COMMENT 'Adgroup name from the network (adgroup_network)',
    APP                     VARCHAR(256)    COMMENT 'Name of the app (app)',
    CAMPAIGN_ID_NETWORK     VARCHAR(256)    COMMENT 'Campaign ID from the network (campaign_id_network)',
    CAMPAIGN_NETWORK        VARCHAR(1024)   COMMENT 'Campaign name from the network (campaign_network)',
    COUNTRY                 VARCHAR(256)    COMMENT 'Country name (country)',
    COUNTRY_CODE            VARCHAR(2)      COMMENT '2-character value ISO 3166 (country_code)',
    CURRENCY_CODE           VARCHAR(3)      COMMENT '3-character value ISO 4217',
    DATE                    DATE            COMMENT 'The date of the event (day)',
    DEVICE_TYPE             VARCHAR(64)     COMMENT 'Group by device type (device_type)',
    OS_NAME                 VARCHAR(64)     COMMENT 'Group by OS names (os_name)',
    PARTNER_ID              VARCHAR(256)    COMMENT 'Partner ID in Adjust system (partner_id)',
    PARTNER_NAME            VARCHAR(256)    COMMENT 'Partner name in Adjust system (partner_name)',
    PLATFORM                VARCHAR(64)     COMMENT 'Device operating system/platform (platform)',
    REGION                  VARCHAR(256)    COMMENT 'Business region (region)',
    STORE_ID                VARCHAR(256)    COMMENT 'Store app ID (store_id)',
    STORE_TYPE              VARCHAR(64)     COMMENT 'Store from where app was installed (store_type)',
    DATA_SOURCE_NAME        VARCHAR(64)     DEFAULT 'Adjust API' COMMENT 'Source identifier',

    -- Custom Event Metrics (WGT-specific events)
    C_DATASCAPE_BUNDLE_PURCHASE_EVENTS          NUMBER(38,0),
    C_DATASCAPE_BUNDLE_PURCHASE_REVENUE         FLOAT,
    C_DATASCAPE_COIN_PURCHASE_EVENTS            NUMBER(38,0),
    C_DATASCAPE_COIN_PURCHASE_REVENUE           FLOAT,
    C_DATASCAPE_CREDIT_PURCHASE_EVENTS          NUMBER(38,0),
    C_DATASCAPE_CREDIT_PURCHASE_REVENUE         FLOAT,
    C_DATASCAPE_PLAYFORCASHCLICK_EVENTS         NUMBER(38,0),
    C_DATASCAPE_PLAYFORCASHCLICK_REVENUE        FLOAT,
    C_DATASCAPE_REACHLEVEL_5_EVENTS             NUMBER(38,0),
    C_DATASCAPE_REACHLEVEL_5_REVENUE            FLOAT,
    C_DATASCAPE_REACHLEVEL_10_EVENTS            NUMBER(38,0),
    C_DATASCAPE_REACHLEVEL_10_REVENUE           FLOAT,
    C_DATASCAPE_REACHLEVEL_20_EVENTS            NUMBER(38,0),
    C_DATASCAPE_REACHLEVEL_20_REVENUE           FLOAT,
    C_DATASCAPE_REACHLEVEL_30_EVENTS            NUMBER(38,0),
    C_DATASCAPE_REACHLEVEL_30_REVENUE           FLOAT,
    C_DATASCAPE_REACHLEVEL_40_EVENTS            NUMBER(38,0),
    C_DATASCAPE_REACHLEVEL_40_REVENUE           FLOAT,
    C_DATASCAPE_REACHLEVEL_50_EVENTS            NUMBER(38,0),
    C_DATASCAPE_REACHLEVEL_50_REVENUE           FLOAT,
    C_DATASCAPE_REACHLEVEL_60_EVENTS            NUMBER(38,0),
    C_DATASCAPE_REACHLEVEL_60_REVENUE           FLOAT,
    C_DATASCAPE_REACHLEVEL_70_EVENTS            NUMBER(38,0),
    C_DATASCAPE_REACHLEVEL_70_REVENUE           FLOAT,
    C_DATASCAPE_REACHLEVEL_80_EVENTS            NUMBER(38,0),
    C_DATASCAPE_REACHLEVEL_80_REVENUE           FLOAT,
    C_DATASCAPE_REACHLEVEL_90_EVENTS            NUMBER(38,0),
    C_DATASCAPE_REACHLEVEL_90_REVENUE           FLOAT,
    C_DATASCAPE_REACHLEVEL_100_EVENTS           NUMBER(38,0),
    C_DATASCAPE_REACHLEVEL_100_REVENUE          FLOAT,
    C_DATASCAPE_REACHLEVEL_110_EVENTS           NUMBER(38,0),
    C_DATASCAPE_REACHLEVEL_110_REVENUE          FLOAT,
    C_DATASCAPE_REGISTRATION_EVENTS             NUMBER(38,0),
    C_DATASCAPE_TUTORIAL_COMPLETED_EVENTS       NUMBER(38,0),
    C_DATASCAPE_TUTORIAL_COMPLETED_REVENUE      FLOAT,

    -- Standard Metrics
    ADJUST_COST             FLOAT           COMMENT 'Cost using Adjust cost-on-engagement method',
    BASE_SESSIONS           NUMBER(38,0)    COMMENT 'Sessions excluding installs and reattributions',
    CLICKS                  NUMBER(38,0)    COMMENT 'Number of ad clicks',
    COST                    FLOAT           COMMENT 'Total ad spend',
    DEATTRIBUTIONS          NUMBER(38,0)    COMMENT 'Users removed from first attribution source',
    EVENTS                  NUMBER(38,0)    COMMENT 'Total triggered events',
    IMPRESSIONS             NUMBER(38,0)    COMMENT 'Total ad impressions',
    INSTALLS                NUMBER(38,0)    COMMENT 'Number of installs',
    NETWORK_COST            FLOAT           COMMENT 'Cost from Network API',
    PAID_CLICKS             NUMBER(38,0)    COMMENT 'Clicks with cost data',
    PAID_IMPRESSIONS        NUMBER(38,0)    COMMENT 'Impressions with cost data',
    PAID_INSTALLS           NUMBER(38,0)    COMMENT 'Installs with cost data',
    REATTRIBUTION_REINSTALLS NUMBER(38,0)   COMMENT 'Reinstalls leading to reattribution',
    REATTRIBUTIONS          NUMBER(38,0)    COMMENT 'Total reattributions',
    REINSTALLS              NUMBER(38,0)    COMMENT 'Number of reinstalls',
    SESSIONS                NUMBER(38,0)    COMMENT 'Total sessions including installs',
    UNINSTALLS              NUMBER(38,0)    COMMENT 'Number of uninstalls',

    -- Metadata
    LOADED_AT               TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP() COMMENT 'When this record was loaded',

    -- Primary key constraint
    CONSTRAINT pk_adj_campaign_api PRIMARY KEY (DATE, APP, OS_NAME, COUNTRY_CODE, PARTNER_ID, CAMPAIGN_ID_NETWORK, ADGROUP_ID_NETWORK, AD_ID)
);

-- ============================================================================
-- 2. CREATE STAGING TABLE FOR API RESPONSES
-- ============================================================================

CREATE TABLE IF NOT EXISTS ADJ_CAMPAIGN_API_STAGING (
    RAW_JSON        VARIANT         COMMENT 'Raw JSON response from Adjust API',
    API_CALL_DATE   DATE            COMMENT 'Date for which data was requested',
    LOADED_AT       TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================================
-- 3. CREATE API CREDENTIALS TABLE (Secure)
-- ============================================================================

CREATE TABLE IF NOT EXISTS API_CREDENTIALS (
    CREDENTIAL_NAME     VARCHAR(256)    PRIMARY KEY,
    CREDENTIAL_VALUE    VARCHAR(4096),
    DESCRIPTION         VARCHAR(1024),
    CREATED_AT          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- Insert placeholder for API token (update with actual token)
-- IMPORTANT: Replace 'YOUR_ADJUST_API_TOKEN_HERE' with your actual token
INSERT INTO API_CREDENTIALS (CREDENTIAL_NAME, CREDENTIAL_VALUE, DESCRIPTION)
SELECT 'ADJUST_API_TOKEN', 'YOUR_ADJUST_API_TOKEN_HERE', 'Adjust Reports Service API Bearer Token'
WHERE NOT EXISTS (SELECT 1 FROM API_CREDENTIALS WHERE CREDENTIAL_NAME = 'ADJUST_API_TOKEN');

-- ============================================================================
-- 4. CREATE APP TOKEN MAPPING TABLE
-- ============================================================================
-- The Adjust API requires app_token to filter by app
-- You need to get these from your Adjust dashboard

CREATE TABLE IF NOT EXISTS APP_TOKEN_MAPPING (
    APP_NAME            VARCHAR(256)    PRIMARY KEY,
    APP_TOKEN           VARCHAR(64)     COMMENT 'Adjust app token from dashboard',
    STORE_ID            VARCHAR(256),
    OS_NAME             VARCHAR(64),
    IS_ACTIVE           BOOLEAN         DEFAULT TRUE,
    CREATED_AT          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- Insert your app mappings (update with actual tokens from Adjust dashboard)
INSERT INTO APP_TOKEN_MAPPING (APP_NAME, APP_TOKEN, STORE_ID, OS_NAME)
SELECT '1 - iOS Golf Mobile', 'YOUR_IOS_APP_TOKEN', '672828590', 'ios'
WHERE NOT EXISTS (SELECT 1 FROM APP_TOKEN_MAPPING WHERE APP_NAME = '1 - iOS Golf Mobile');

INSERT INTO APP_TOKEN_MAPPING (APP_NAME, APP_TOKEN, STORE_ID, OS_NAME)
SELECT '2 - Googleplay Golf Mobile', 'YOUR_ANDROID_APP_TOKEN', 'YOUR_ANDROID_STORE_ID', 'android'
WHERE NOT EXISTS (SELECT 1 FROM APP_TOKEN_MAPPING WHERE APP_NAME = '2 - Googleplay Golf Mobile');

-- ============================================================================
-- 5. CREATE LOGGING TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS API_LOAD_LOG (
    LOG_ID              NUMBER          AUTOINCREMENT,
    LOAD_DATE           DATE,
    APP_NAME            VARCHAR(256),
    STATUS              VARCHAR(64),
    ROWS_LOADED         NUMBER,
    ERROR_MESSAGE       VARCHAR(4096),
    STARTED_AT          TIMESTAMP_NTZ,
    COMPLETED_AT        TIMESTAMP_NTZ,
    DURATION_SECONDS    NUMBER
);

-- ============================================================================
-- 6. GRANT PERMISSIONS
-- ============================================================================

GRANT USAGE ON SCHEMA WGT.ADJUST_API TO ROLE DBT_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA WGT.ADJUST_API TO ROLE DBT_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA WGT.ADJUST_API TO ROLE DBT_ROLE;
