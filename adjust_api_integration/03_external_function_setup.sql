-- ============================================================================
-- ADJUST API TO SNOWFLAKE INTEGRATION
-- Part 3: External Function & API Integration Setup
-- ============================================================================
-- This script sets up the Snowflake External Function that calls AWS Lambda
-- to retrieve data from the Adjust Reports API
-- ============================================================================

-- PREREQUISITE: You must have already:
-- 1. Deployed the Lambda function (02_lambda_function.py)
-- 2. Created an API Gateway trigger for the Lambda
-- 3. Created an IAM role for Snowflake to assume

USE ROLE ACCOUNTADMIN;
USE DATABASE WGT;
USE SCHEMA ADJUST_API;

-- ============================================================================
-- 1. CREATE API INTEGRATION
-- ============================================================================
-- Replace the placeholders with your actual AWS values

CREATE OR REPLACE API INTEGRATION adjust_api_integration
    API_PROVIDER = aws_api_gateway
    API_AWS_ROLE_ARN = 'arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/snowflake-adjust-api-role'
    API_ALLOWED_PREFIXES = ('https://YOUR_API_GATEWAY_ID.execute-api.YOUR_REGION.amazonaws.com/')
    ENABLED = TRUE;

-- Get the API_AWS_IAM_USER_ARN and API_AWS_EXTERNAL_ID to configure trust relationship
DESCRIBE API INTEGRATION adjust_api_integration;

-- ============================================================================
-- 2. CREATE EXTERNAL FUNCTION
-- ============================================================================
-- This function calls the Lambda via API Gateway

CREATE OR REPLACE EXTERNAL FUNCTION fetch_adjust_data(
    app_token VARCHAR,
    start_date VARCHAR,
    end_date VARCHAR
)
RETURNS VARIANT
API_INTEGRATION = adjust_api_integration
AS 'https://YOUR_API_GATEWAY_ID.execute-api.YOUR_REGION.amazonaws.com/prod/adjust-fetch';

-- ============================================================================
-- 3. TEST THE EXTERNAL FUNCTION
-- ============================================================================
-- Uncomment and run after setup is complete

-- SELECT fetch_adjust_data('YOUR_APP_TOKEN', '2025-01-01', '2025-01-01');

-- ============================================================================
-- 4. ALTERNATIVE: SNOWFLAKE PYTHON UDF (No AWS Required)
-- ============================================================================
-- If you prefer not to use AWS Lambda, you can use Snowpark Python UDF
-- This runs directly in Snowflake using Snowpark

CREATE OR REPLACE FUNCTION fetch_adjust_data_snowpark(
    api_token VARCHAR,
    app_token VARCHAR,
    start_date VARCHAR,
    end_date VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.9'
PACKAGES = ('requests', 'snowflake-snowpark-python')
HANDLER = 'fetch_data'
AS
$$
import requests
import json

def fetch_data(api_token: str, app_token: str, start_date: str, end_date: str) -> dict:
    """
    Fetch data from Adjust Reports API.
    """
    base_url = "https://automate.adjust.com/reports-service/report"

    dimensions = [
        "day", "app", "os_name", "device_type", "country", "country_code",
        "region", "partner_id", "partner_name", "campaign_id_network",
        "campaign_network", "adgroup_id_network", "adgroup_network",
        "creative_id", "creative", "store_id", "store_type", "platform"
    ]

    metrics = [
        "installs", "clicks", "impressions", "sessions", "base_sessions",
        "cost", "adjust_cost", "network_cost", "reattributions",
        "reattribution_reinstalls", "reinstalls", "uninstalls",
        "deattributions", "events", "paid_clicks", "paid_impressions",
        "paid_installs"
    ]

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
        "attribution_type": "click,impression",
        "ad_spend_mode": "network"
    }

    try:
        response = requests.get(base_url, headers=headers, params=params, timeout=120)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        return {"error": str(e)}
$$;

-- Grant execute permission
GRANT USAGE ON FUNCTION fetch_adjust_data_snowpark(VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO ROLE DBT_ROLE;
