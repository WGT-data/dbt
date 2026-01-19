# Technology Stack

**Analysis Date:** 2025-01-19

## Languages

**Primary:**
- SQL (Snowflake dialect) - All transformation logic in `models/**/*.sql`
- Jinja2 - Templating within dbt models for config, macros, and control flow

**Secondary:**
- YAML - Configuration and schema definitions in `dbt_project.yml` and `**/_.yml` files
- CSV - Seed data in `seeds/*.csv`

## Runtime

**Environment:**
- dbt (Data Build Tool) - SQL transformation framework
- Snowflake - Cloud data warehouse (target platform)

**Package Manager:**
- dbt packages via `packages.yml` (not present in this project - no external packages used)

## Frameworks

**Core:**
- dbt Core - SQL transformation and dependency management framework
- Project name: `wgt_dbt` (defined in `dbt_project.yml`)
- Config version: 2

**Testing:**
- dbt native testing via schema YAML files
- Test definitions in `tests/` directory (currently empty except `.gitkeep`)

**Build/Dev:**
- dbt CLI commands: `dbt run`, `dbt test`, `dbt build`
- Profile: `default` (configured externally in `~/.dbt/profiles.yml`)

## Key Dependencies

**Critical:**
- Snowflake - Target data warehouse platform
- dbt Core - Transformation framework (version not locked in project)

**Data Pipeline Dependencies:**
- Adjust S3 connector - Mobile attribution data ingestion
- Amplitude Snowflake share - Product analytics data
- Supermetrics - Ad spend data aggregation
- Fivetran - Facebook Ads data connector

## Configuration

**Environment:**
- dbt profile: `default` (external configuration)
- Target path: `target/`
- Clean targets: `target/`, `dbt_packages/`

**Key Paths:**
- Models: `models/`
- Tests: `tests/`
- Seeds: `seeds/`
- Macros: `macros/`
- Snapshots: `snapshots/`
- Analyses: `analyses/`

**Materialization Defaults (in `dbt_project.yml`):**
- `staging/` models: `view`
- `intermediate/` models: `table`
- `marts/` models: `table`

## Incremental Strategy

Most models use incremental materialization with:
- `incremental_strategy='merge'`
- `on_schema_change='append_new_columns'`
- Lookback windows (3-7 days) for late-arriving data

Example pattern from `v_stg_amplitude__events.sql`:
```sql
{{
    config(
        materialized='incremental',
        unique_key=['USER_ID', 'DEVICE_ID', 'EVENT_TIME', 'EVENT_TYPE'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}
```

## Platform Requirements

**Development:**
- dbt CLI installed
- Access to Snowflake account
- dbt profile configured in `~/.dbt/profiles.yml`

**Production:**
- Snowflake compute warehouse
- Scheduler (orchestration tool not defined in repo)

---

*Stack analysis: 2025-01-19*
