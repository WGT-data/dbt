-- Adjust API Integration - Admin Setup
-- Needs ACCOUNTADMIN to run this

USE ROLE ACCOUNTADMIN;

-- Allow Snowflake to call out to Adjust's API
CREATE OR REPLACE NETWORK RULE WGT.ADJUST_API.adjust_api_network_rule
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('automate.adjust.com:443');

-- Create the integration that lets our UDF use the network rule
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION adjust_api_access
    ALLOWED_NETWORK_RULES = (WGT.ADJUST_API.adjust_api_network_rule)
    ENABLED = TRUE;

-- Let SYSADMIN create UDFs that use this
GRANT USAGE ON INTEGRATION adjust_api_access TO ROLE SYSADMIN;

-- Verify it worked
SHOW INTEGRATIONS LIKE 'adjust_api_access';
