-- Adjust API Integration - Snowpark UDF
-- Python function that calls the Adjust Reports API
-- Requires: admin must run 00_ACCOUNTADMIN_REQUIRED.sql first

USE ROLE SYSADMIN;
USE DATABASE WGT;
USE SCHEMA ADJUST_API;

CREATE OR REPLACE FUNCTION fetch_adjust_data(
    api_token VARCHAR,
    app_token VARCHAR,
    start_date VARCHAR,
    end_date VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.9'
PACKAGES = ('requests', 'snowflake-snowpark-python')
EXTERNAL_ACCESS_INTEGRATIONS = (adjust_api_access)
HANDLER = 'fetch_data'
AS
$$
import requests
import json

def fetch_data(api_token: str, app_token: str, start_date: str, end_date: str) -> dict:
    base_url = "https://automate.adjust.com/reports-service/report"

    # Same dimensions we had in Supermetrics
    dimensions = [
        "day",
        "app",
        "os_name",
        "device_type",
        "country",
        "country_code",
        "region",
        "partner_id",
        "partner_name",
        "campaign_id_network",
        "campaign_network",
        "adgroup_id_network",
        "adgroup_network",
        "creative_id",
        "creative",
        "store_id",
        "store_type",
        "platform"
    ]

    metrics = [
        "installs",
        "clicks",
        "impressions",
        "sessions",
        "base_sessions",
        "cost",
        "adjust_cost",
        "network_cost",
        "reattributions",
        "reattribution_reinstalls",
        "reinstalls",
        "uninstalls",
        "deattributions",
        "events",
        "paid_clicks",
        "paid_impressions",
        "paid_installs",
        # WGT custom events
        "bundle_purchase_events",
        "bundle_purchase_revenue",
        "coin_purchase_events",
        "coin_purchase_revenue",
        "credit_purchase_events",
        "credit_purchase_revenue",
        "playforcashclick_events",
        "playforcashclick_revenue",
        "registration_events",
        "tutorial_completed_events",
        "tutorial_completed_revenue",
        "reachlevel_5_events",
        "reachlevel_10_events",
        "reachlevel_20_events",
        "reachlevel_30_events",
        "reachlevel_40_events",
        "reachlevel_50_events",
        "reachlevel_60_events",
        "reachlevel_70_events",
        "reachlevel_80_events",
        "reachlevel_90_events",
        "reachlevel_100_events",
        "reachlevel_110_events"
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
        -- "attribution_type": "click,impression",
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

-- Test it like this:
/*
SELECT fetch_adjust_data(
    (SELECT CREDENTIAL_VALUE FROM WGT.ADJUST_API.API_CREDENTIALS WHERE CREDENTIAL_NAME = 'ADJUST_API_TOKEN'),
    'acqu46kv92ss',
    '2025-01-20',
    '2025-01-20'
) AS api_response;
*/

GRANT USAGE ON FUNCTION fetch_adjust_data(VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO ROLE DBT_ROLE;


-- For admin reference:
-- This UDF pulls marketing data from Adjust (installs, clicks, cost, etc.)
-- It only connects to automate.adjust.com and is read-only
-- The external access integration is needed because Snowflake blocks outbound calls by default
