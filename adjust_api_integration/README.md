# Adjust API to Snowflake Integration

This integration replaces Supermetrics by pulling data directly from the Adjust Reports Service API into Snowflake.

## Overview

The solution uses:
1. Snowflake Python UDF to call the Adjust API
2. Stored procedures for data loading logic
3. Snowflake Tasks for scheduled execution
4. dbt models for data transformation

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Adjust API    │────▶│ Snowflake UDF   │────▶│ Staging Table   │
│ (Reports Svc)   │     │ (fetch_data)    │     │                 │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                          │
                                                          ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   dbt Models    │◀────│   Final Table   │◀────│ Stored Procedure│
│ (Transformation)│     │ ADJ_CAMPAIGN_API│     │ (MERGE logic)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Files

| File | Description |
|------|-------------|
| `01_setup_snowflake_objects.sql` | Creates tables, schemas, credentials storage |
| `02_lambda_function.py` | AWS Lambda function (optional, for external function approach) |
| `03_external_function_setup.sql` | External function and Snowpark UDF setup |
| `04_stored_procedures.sql` | Load procedures for single day, daily, and backfill |
| `05_snowflake_task.sql` | Scheduled tasks for automated loading |
| `06_get_api_token_instructions.md` | How to obtain your Adjust API token |

## Setup Instructions

### Step 1: Create Snowflake Objects

Run `01_setup_snowflake_objects.sql` to create:
- `WGT.ADJUST_API` schema
- `ADJ_CAMPAIGN_API` table (matches Supermetrics structure)
- `API_CREDENTIALS` table
- `APP_TOKEN_MAPPING` table
- `API_LOAD_LOG` table

### Step 2: Get API Credentials

Follow `06_get_api_token_instructions.md` to:
1. Generate an Adjust API token
2. Find your app tokens
3. Store credentials in Snowflake

### Step 3: Create the Snowpark UDF

Run `03_external_function_setup.sql` to create the `fetch_adjust_data_snowpark` function.

### Step 4: Create Stored Procedures

Run `04_stored_procedures.sql` to create:
- `load_adjust_data_for_date()` - Load a single day
- `load_adjust_daily()` - Load yesterday's data for all apps
- `backfill_adjust_data()` - Load a date range

### Step 5: Test the Integration

```sql
-- Test API connectivity
SELECT fetch_adjust_data_snowpark(
    'YOUR_API_TOKEN',
    'YOUR_APP_TOKEN',
    '2025-01-20',
    '2025-01-20'
);

-- Load a single day
CALL WGT.ADJUST_API.load_adjust_data_for_date(
    '2025-01-20',
    'YOUR_APP_TOKEN',
    '1 - iOS Golf Mobile'
);

-- Check results
SELECT COUNT(*) FROM WGT.ADJUST_API.ADJ_CAMPAIGN_API;
```

### Step 6: Backfill Historical Data

```sql
-- Backfill from where Supermetrics ended
CALL WGT.ADJUST_API.backfill_adjust_data(
    '2025-12-09',  -- Day after last Supermetrics data
    CURRENT_DATE() - 1
);
```

### Step 7: Enable Scheduled Tasks

Run `05_snowflake_task.sql` to create and enable:
- Daily load task (6 AM UTC)
- Weekly refresh task (Sundays 7 AM UTC)
- Monthly cleanup task

## dbt Integration

The integration includes dbt models in `models/staging/adjust_api/`:

- `stg_adjust_api__campaigns.sql` - Staging model for API data
- `stg_adjust__campaigns_unified.sql` - Combines Supermetrics + API data

Use `stg_adjust__campaigns_unified` for complete historical data.

## Column Mapping

| Supermetrics Column | Adjust API Dimension/Metric |
|--------------------|----------------------------|
| DATE | day |
| APP | app |
| OS_NAME | os_name |
| DEVICE_TYPE | device_type |
| COUNTRY | country |
| COUNTRY_CODE | country_code |
| PARTNER_ID | partner_id |
| PARTNER_NAME | partner_name |
| CAMPAIGN_ID_NETWORK | campaign_id_network |
| CAMPAIGN_NETWORK | campaign_network |
| ADGROUP_ID_NETWORK | adgroup_id_network |
| ADGROUP_NETWORK | adgroup_network |
| AD_ID | creative_id |
| AD_NAME | creative |
| INSTALLS | installs |
| CLICKS | clicks |
| IMPRESSIONS | impressions |
| SESSIONS | sessions |
| COST | cost |
| REATTRIBUTIONS | reattributions |

## Custom Events

The WGT custom events are mapped using Adjust event slugs:

| Supermetrics Column | Adjust Event Slug |
|--------------------|-------------------|
| C_DATASCAPE_BUNDLE_PURCHASE_EVENTS | bundle_purchase_events |
| C_DATASCAPE_COIN_PURCHASE_EVENTS | coin_purchase_events |
| C_DATASCAPE_REGISTRATION_EVENTS | registration_events |
| C_DATASCAPE_TUTORIAL_COMPLETED_EVENTS | tutorial_completed_events |
| C_DATASCAPE_REACHLEVEL_X_EVENTS | reachlevel_X_events |

You may need to verify these event slugs match your Adjust configuration.

## Monitoring

Check load status:
```sql
SELECT * FROM WGT.ADJUST_API.v_adjust_load_status
ORDER BY STARTED_AT DESC
LIMIT 20;
```

Compare sources:
```sql
SELECT * FROM WGT.ADJUST_API.v_adjust_data_comparison;
```

## Troubleshooting

**No data returned from API**
- Verify API token is valid
- Verify app token is correct
- Check date range has activity
- Review API_LOAD_LOG for errors

**Metrics don't match Supermetrics**
- Adjust may have different attribution windows
- Check currency settings match
- Verify event slugs are correct

**Task not running**
- Ensure task is resumed: `ALTER TASK task_name RESUME;`
- Check warehouse is not suspended
- Review task history for errors

## API Limits

- Max 50 concurrent requests
- Large date ranges may timeout
- Rate limit: 429 errors indicate throttling

For large backfills, process in weekly chunks:
```sql
-- Process week by week
CALL backfill_adjust_data('2025-12-09', '2025-12-15');
CALL backfill_adjust_data('2025-12-16', '2025-12-22');
-- etc.
```
