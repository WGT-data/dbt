-- ============================================================================
-- ADJUST API INTEGRATION - ACCOUNTADMIN COMMANDS
-- ============================================================================
-- This script must be run by someone with ACCOUNTADMIN role.
-- It creates the external access integration needed for Snowflake to call
-- the Adjust API directly.
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- Step 1: Create network rule allowing access to Adjust API
CREATE OR REPLACE NETWORK RULE WGT.ADJUST_API.adjust_api_network_rule
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('automate.adjust.com:443');

-- Step 2: Create external access integration
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION adjust_api_access
    ALLOWED_NETWORK_RULES = (WGT.ADJUST_API.adjust_api_network_rule)
    ENABLED = TRUE;

-- Step 3: Grant usage to SYSADMIN so they can create UDFs with this integration
GRANT USAGE ON INTEGRATION adjust_api_access TO ROLE SYSADMIN;

-- Step 4: Verify setup
SHOW INTEGRATIONS LIKE 'adjust_api_access';

-- ============================================================================
-- That's it! After running this, Riley can create the Snowpark UDF
-- using SYSADMIN role.
-- ============================================================================
