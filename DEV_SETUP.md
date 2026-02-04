# Development Environment Setup

## Dev/Prod Schema Isolation

This project uses separate schemas for dev and prod environments:

| Environment | Source Schema | Output Schema |
|-------------|---------------|---------------|
| dev         | DEV_S3_DATA   | DEV_S3_DATA   |
| prod        | S3_DATA       | S3_DATA       |

## One-Time Setup for Dev Environment

Before running dbt in dev mode, the DEV_S3_DATA schema needs views that point to prod source data:

```bash
dbt run-operation setup_dev_views
```

This creates views in `ADJUST.DEV_S3_DATA` that point to `ADJUST.S3_DATA` tables:
- `IOS_EVENTS` -> `S3_DATA.IOS_EVENTS`
- `ANDROID_EVENTS` -> `S3_DATA.ANDROID_EVENTS`

## Required Permissions

The DBT_ROLE needs the following grants (run as SYSADMIN):

```sql
-- Database
GRANT USAGE ON DATABASE ADJUST TO ROLE DBT_ROLE;

-- S3_DATA (prod)
GRANT USAGE ON SCHEMA ADJUST.S3_DATA TO ROLE DBT_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA ADJUST.S3_DATA TO ROLE DBT_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA ADJUST.S3_DATA TO ROLE DBT_ROLE;

-- DEV_S3_DATA (dev)
GRANT USAGE ON SCHEMA ADJUST.DEV_S3_DATA TO ROLE DBT_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA ADJUST.DEV_S3_DATA TO ROLE DBT_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA ADJUST.DEV_S3_DATA TO ROLE DBT_ROLE;
GRANT CREATE TABLE ON SCHEMA ADJUST.DEV_S3_DATA TO ROLE DBT_ROLE;
GRANT CREATE VIEW ON SCHEMA ADJUST.DEV_S3_DATA TO ROLE DBT_ROLE;

-- API_DATA
GRANT USAGE ON SCHEMA ADJUST.API_DATA TO ROLE DBT_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA ADJUST.API_DATA TO ROLE DBT_ROLE;
```

## Running dbt

```bash
# Dev (default)
dbt run

# Prod
dbt run --target prod
```
