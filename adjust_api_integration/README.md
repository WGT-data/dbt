# Adjust API to Snowflake Integration

Pulls data directly from the Adjust Reports Service API into Snowflake. Replaces Supermetrics.

## Architecture

Everything runs in Snowflake:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Adjust API    │────▶│  Snowpark UDF   │────▶│  Final Table    │
│ (automate.      │     │  (Python in     │     │ ADJ_CAMPAIGN_API│
│  adjust.com)    │     │   Snowflake)    │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                        ┌───────────────────────────────┘
                        ▼
                ┌─────────────────┐
                │ Snowflake Task  │
                │ (Daily at 6 AM) │
                └─────────────────┘
```

## Files

Run these in order:

| File | Who Runs It | Description |
|------|-------------|-------------|
| `00_ACCOUNTADMIN_REQUIRED.sql` | Admin (ACCOUNTADMIN) | Creates network permission for API access |
| `01_setup_snowflake_objects.sql` | You (SYSADMIN) | Creates schema, tables, credentials |
| `02_snowpark_udf.sql` | You (SYSADMIN) | Creates Python function that calls Adjust API |
| `03_stored_procedures.sql` | You (SYSADMIN) | Creates load procedures (single day, daily, backfill) |
| `04_snowflake_task.sql` | You (SYSADMIN) | Creates scheduled tasks for automated loading |

Other files:
- `05_get_api_token_instructions.md` - How to get Adjust API tokens
- `README.md` - This file

## Setup Steps

### Step 1: Admin runs external access setup
Have an admin with ACCOUNTADMIN run `00_ACCOUNTADMIN_REQUIRED.sql`.

### Step 2: Create Snowflake objects
Run `01_setup_snowflake_objects.sql` to create the schema and tables.

### Step 3: Store credentials
Already done. API token and app tokens are in:
- `WGT.ADJUST_API.API_CREDENTIALS`
- `WGT.ADJUST_API.APP_TOKEN_MAPPING`

### Step 4: Create the Snowpark UDF
Run `02_snowpark_udf.sql` to create the function that calls the Adjust API.

### Step 5: Create stored procedures
Run `03_stored_procedures.sql` to create the load logic.

### Step 6: Test
```sql
-- Test API connection
SELECT fetch_adjust_data(
    (SELECT CREDENTIAL_VALUE FROM WGT.ADJUST_API.API_CREDENTIALS WHERE CREDENTIAL_NAME = 'ADJUST_API_TOKEN'),
    'acqu46kv92ss',
    '2025-01-20',
    '2025-01-20'
);

-- Load one day of data
CALL WGT.ADJUST_API.load_adjust_data_for_date(
    '2025-01-20',
    'acqu46kv92ss',
    '1 - iOS Golf Mobile'
);

-- Check results
SELECT * FROM WGT.ADJUST_API.ADJ_CAMPAIGN_API LIMIT 10;
```

### Step 7: Backfill historical data
```sql
CALL WGT.ADJUST_API.backfill_adjust_data('2025-12-09', '2025-01-26');
```

### Step 8: Enable scheduled tasks
Run `04_snowflake_task.sql` to create and enable daily automation.

## Credentials Stored

| Credential | Value | Location |
|------------|-------|----------|
| API Token | sy2v5aD9UawXacgsrjgr | API_CREDENTIALS table |
| iOS App Token | acqu46kv92ss | APP_TOKEN_MAPPING table |
| Android App Token | q9nlmhlmwjec | APP_TOKEN_MAPPING table |

## Monitoring

```sql
-- Check load history
SELECT * FROM WGT.ADJUST_API.v_adjust_load_status ORDER BY STARTED_AT DESC;

-- Compare API vs Supermetrics totals
SELECT * FROM WGT.ADJUST_API.v_adjust_data_comparison;
```
