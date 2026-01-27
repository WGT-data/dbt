"""
AWS Lambda Function for Adjust Reports API Integration
========================================================
This Lambda function calls the Adjust Reports Service API and returns data
to Snowflake via an External Function.

Deployment Instructions:
1. Create a new Lambda function in AWS
2. Set runtime to Python 3.9+
3. Set timeout to 5 minutes (300 seconds)
4. Set memory to 512 MB minimum
5. Add the 'requests' layer or package it with the deployment
6. Configure environment variables (see below)
7. Create API Gateway trigger
8. Configure Snowflake External Function to call the API Gateway

Environment Variables Required:
- ADJUST_API_TOKEN: Your Adjust API bearer token

Author: Claude (AI Assistant)
Version: 1.0
"""

import json
import os
import requests
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

# Adjust API Configuration
ADJUST_API_BASE_URL = "https://automate.adjust.com/reports-service/report"

# Dimensions to match Supermetrics structure
DIMENSIONS = [
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

# Standard metrics available in Adjust API
STANDARD_METRICS = [
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
    "paid_installs"
]

# Custom event slugs for WGT (you'll need to get these from your Adjust dashboard)
# Format: {event_slug}_events and {event_slug}_revenue
CUSTOM_EVENT_SLUGS = [
    "bundle_purchase",
    "coin_purchase",
    "credit_purchase",
    "playforcashclick",
    "reachlevel_5",
    "reachlevel_10",
    "reachlevel_20",
    "reachlevel_30",
    "reachlevel_40",
    "reachlevel_50",
    "reachlevel_60",
    "reachlevel_70",
    "reachlevel_80",
    "reachlevel_90",
    "reachlevel_100",
    "reachlevel_110",
    "registration",
    "tutorial_completed"
]


def get_event_metrics() -> List[str]:
    """Generate event metric names from slugs."""
    metrics = []
    for slug in CUSTOM_EVENT_SLUGS:
        metrics.append(f"{slug}_events")
        # Some events don't have revenue (like registration)
        if slug not in ["registration"]:
            metrics.append(f"{slug}_revenue")
    return metrics


def call_adjust_api(
    api_token: str,
    app_token: str,
    start_date: str,
    end_date: str,
    dimensions: List[str],
    metrics: List[str],
    currency: str = "USD"
) -> Dict[str, Any]:
    """
    Call the Adjust Reports Service API.

    Args:
        api_token: Adjust API bearer token
        app_token: Adjust app token
        start_date: Start date (YYYY-MM-DD)
        end_date: End date (YYYY-MM-DD)
        dimensions: List of dimensions to group by
        metrics: List of metrics to retrieve
        currency: Currency for cost/revenue metrics

    Returns:
        API response as dictionary
    """
    headers = {
        "Authorization": f"Bearer {api_token}",
        "Content-Type": "application/json"
    }

    params = {
        "dimensions": ",".join(dimensions),
        "metrics": ",".join(metrics),
        "date_period": f"{start_date}:{end_date}",
        "app_token__in": app_token,
        "currency": currency,
        "attribution_type": "click,impression",
        "ad_spend_mode": "network"
    }

    response = requests.get(
        ADJUST_API_BASE_URL,
        headers=headers,
        params=params,
        timeout=120
    )

    response.raise_for_status()
    return response.json()


def transform_row(row: Dict[str, Any]) -> Dict[str, Any]:
    """
    Transform a single API row to match Snowflake table structure.
    """
    return {
        # Dimensions
        "DATE": row.get("day"),
        "APP": row.get("app"),
        "OS_NAME": row.get("os_name"),
        "DEVICE_TYPE": row.get("device_type"),
        "COUNTRY": row.get("country"),
        "COUNTRY_CODE": row.get("country_code"),
        "REGION": row.get("region"),
        "PARTNER_ID": row.get("partner_id"),
        "PARTNER_NAME": row.get("partner_name"),
        "CAMPAIGN_ID_NETWORK": row.get("campaign_id_network", "unknown"),
        "CAMPAIGN_NETWORK": row.get("campaign_network", "unknown"),
        "ADGROUP_ID_NETWORK": row.get("adgroup_id_network", "unknown"),
        "ADGROUP_NETWORK": row.get("adgroup_network", "unknown"),
        "AD_ID": row.get("creative_id", "unknown"),
        "AD_NAME": row.get("creative", "unknown"),
        "STORE_ID": row.get("store_id"),
        "STORE_TYPE": row.get("store_type"),
        "PLATFORM": row.get("platform", "mobile_app"),
        "CURRENCY_CODE": "USD",
        "DATA_SOURCE_NAME": "Adjust API",

        # Standard Metrics
        "INSTALLS": int(row.get("installs", 0) or 0),
        "CLICKS": int(row.get("clicks", 0) or 0),
        "IMPRESSIONS": int(row.get("impressions", 0) or 0),
        "SESSIONS": int(row.get("sessions", 0) or 0),
        "BASE_SESSIONS": int(row.get("base_sessions", 0) or 0),
        "COST": float(row.get("cost", 0) or 0),
        "ADJUST_COST": float(row.get("adjust_cost", 0) or 0),
        "NETWORK_COST": float(row.get("network_cost", 0) or 0),
        "REATTRIBUTIONS": int(row.get("reattributions", 0) or 0),
        "REATTRIBUTION_REINSTALLS": int(row.get("reattribution_reinstalls", 0) or 0),
        "REINSTALLS": int(row.get("reinstalls", 0) or 0),
        "UNINSTALLS": int(row.get("uninstalls", 0) or 0),
        "DEATTRIBUTIONS": int(row.get("deattributions", 0) or 0),
        "EVENTS": int(row.get("events", 0) or 0),
        "PAID_CLICKS": int(row.get("paid_clicks", 0) or 0),
        "PAID_IMPRESSIONS": int(row.get("paid_impressions", 0) or 0),
        "PAID_INSTALLS": int(row.get("paid_installs", 0) or 0),

        # Custom Event Metrics
        "C_DATASCAPE_BUNDLE_PURCHASE_EVENTS": int(row.get("bundle_purchase_events", 0) or 0),
        "C_DATASCAPE_BUNDLE_PURCHASE_REVENUE": float(row.get("bundle_purchase_revenue", 0) or 0),
        "C_DATASCAPE_COIN_PURCHASE_EVENTS": int(row.get("coin_purchase_events", 0) or 0),
        "C_DATASCAPE_COIN_PURCHASE_REVENUE": float(row.get("coin_purchase_revenue", 0) or 0),
        "C_DATASCAPE_CREDIT_PURCHASE_EVENTS": int(row.get("credit_purchase_events", 0) or 0),
        "C_DATASCAPE_CREDIT_PURCHASE_REVENUE": float(row.get("credit_purchase_revenue", 0) or 0),
        "C_DATASCAPE_PLAYFORCASHCLICK_EVENTS": int(row.get("playforcashclick_events", 0) or 0),
        "C_DATASCAPE_PLAYFORCASHCLICK_REVENUE": float(row.get("playforcashclick_revenue", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_5_EVENTS": int(row.get("reachlevel_5_events", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_5_REVENUE": float(row.get("reachlevel_5_revenue", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_10_EVENTS": int(row.get("reachlevel_10_events", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_10_REVENUE": float(row.get("reachlevel_10_revenue", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_20_EVENTS": int(row.get("reachlevel_20_events", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_20_REVENUE": float(row.get("reachlevel_20_revenue", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_30_EVENTS": int(row.get("reachlevel_30_events", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_30_REVENUE": float(row.get("reachlevel_30_revenue", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_40_EVENTS": int(row.get("reachlevel_40_events", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_40_REVENUE": float(row.get("reachlevel_40_revenue", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_50_EVENTS": int(row.get("reachlevel_50_events", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_50_REVENUE": float(row.get("reachlevel_50_revenue", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_60_EVENTS": int(row.get("reachlevel_60_events", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_60_REVENUE": float(row.get("reachlevel_60_revenue", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_70_EVENTS": int(row.get("reachlevel_70_events", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_70_REVENUE": float(row.get("reachlevel_70_revenue", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_80_EVENTS": int(row.get("reachlevel_80_events", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_80_REVENUE": float(row.get("reachlevel_80_revenue", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_90_EVENTS": int(row.get("reachlevel_90_events", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_90_REVENUE": float(row.get("reachlevel_90_revenue", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_100_EVENTS": int(row.get("reachlevel_100_events", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_100_REVENUE": float(row.get("reachlevel_100_revenue", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_110_EVENTS": int(row.get("reachlevel_110_events", 0) or 0),
        "C_DATASCAPE_REACHLEVEL_110_REVENUE": float(row.get("reachlevel_110_revenue", 0) or 0),
        "C_DATASCAPE_REGISTRATION_EVENTS": int(row.get("registration_events", 0) or 0),
        "C_DATASCAPE_TUTORIAL_COMPLETED_EVENTS": int(row.get("tutorial_completed_events", 0) or 0),
        "C_DATASCAPE_TUTORIAL_COMPLETED_REVENUE": float(row.get("tutorial_completed_revenue", 0) or 0),
    }


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler function.

    Expected input format (from Snowflake External Function):
    {
        "data": [
            [0, "app_token", "2025-01-01", "2025-01-01"]
        ]
    }

    Returns format for Snowflake:
    {
        "data": [
            [0, [{"row": "data"}, ...]]
        ]
    }
    """
    try:
        # Get API token from environment
        api_token = os.environ.get("ADJUST_API_TOKEN")
        if not api_token:
            raise ValueError("ADJUST_API_TOKEN environment variable not set")

        # Parse input from Snowflake
        input_data = event.get("data", [])
        results = []

        all_metrics = STANDARD_METRICS + get_event_metrics()

        for row in input_data:
            row_id = row[0]
            app_token = row[1]
            start_date = row[2]
            end_date = row[3]

            try:
                # Call Adjust API
                api_response = call_adjust_api(
                    api_token=api_token,
                    app_token=app_token,
                    start_date=start_date,
                    end_date=end_date,
                    dimensions=DIMENSIONS,
                    metrics=all_metrics
                )

                # Transform rows
                transformed_rows = []
                for api_row in api_response.get("rows", []):
                    transformed_rows.append(transform_row(api_row))

                results.append([row_id, json.dumps(transformed_rows)])

            except requests.exceptions.HTTPError as e:
                results.append([row_id, json.dumps({"error": f"API Error: {str(e)}"})])
            except Exception as e:
                results.append([row_id, json.dumps({"error": str(e)})])

        return {"data": results}

    except Exception as e:
        return {
            "data": [[0, json.dumps({"error": f"Lambda Error: {str(e)}"})]]
        }


# For local testing
if __name__ == "__main__":
    # Test event
    test_event = {
        "data": [
            [0, "YOUR_APP_TOKEN", "2025-01-01", "2025-01-01"]
        ]
    }

    # Set environment variable for testing
    os.environ["ADJUST_API_TOKEN"] = "YOUR_TOKEN_HERE"

    result = lambda_handler(test_event, None)
    print(json.dumps(result, indent=2))
