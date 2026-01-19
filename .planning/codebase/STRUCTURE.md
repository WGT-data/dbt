# Codebase Structure

**Analysis Date:** 2026-01-19

## Directory Layout

```
wgt_dbt/
├── models/                    # All dbt SQL models
│   ├── staging/               # Source data transformations (views)
│   │   ├── adjust/            # Adjust mobile attribution
│   │   ├── amplitude/         # Amplitude product analytics
│   │   ├── facebook/          # Facebook ads data
│   │   ├── revenue/           # Revenue/purchase events
│   │   └── supermetrics/      # Ad spend from Supermetrics
│   ├── intermediate/          # Business logic layer (tables)
│   └── marts/                 # Aggregated metrics (tables)
│       ├── attribution/       # Attribution and MTA models
│       └── spend/             # Spend and performance models
├── seeds/                     # Static lookup data (CSV)
├── macros/                    # Jinja macros (empty)
├── tests/                     # Custom data tests (empty)
├── analyses/                  # Ad-hoc SQL analyses (empty)
├── snapshots/                 # SCD snapshots (empty)
├── dbt_project.yml            # Project configuration
└── .planning/                 # Planning documentation
    └── codebase/              # Codebase analysis docs
```

## Directory Purposes

**models/staging/adjust/**
- Purpose: Transform raw Adjust mobile attribution data
- Contains: Install events, touchpoints (clicks/impressions), activity events by platform
- Key files:
  - `v_stg_adjust__installs.sql`: Unified iOS/Android install events with AD_PARTNER mapping
  - `v_stg_adjust__touchpoints.sql`: Unified clicks and impressions for MTA
  - `stg_adjust__ios_activity_*.sql`: Individual iOS activity tables
  - `stg_adjust__android_activity_*.sql`: Individual Android activity tables
  - `_adjust__sources.yml`: Source definitions for Adjust tables

**models/staging/amplitude/**
- Purpose: Transform Amplitude product analytics data
- Contains: Event data and device-to-user mapping
- Key files:
  - `v_stg_amplitude__events.sql`: Core event stream
  - `v_stg_amplitude__merge_ids.sql`: Device ID to User ID mapping
  - `_amplitude__sources.yml`: Source definitions

**models/staging/revenue/**
- Purpose: Extract and clean revenue events
- Key files:
  - `v_stg_revenue__events.sql`: Revenue events with parsed `$revenue` property
  - `_revenue__sources.yml`: Source definitions

**models/staging/supermetrics/**
- Purpose: Transform ad spend data from Supermetrics
- Key files:
  - `stg_supermetrics__adj_campaign.sql`: Daily campaign spend with extensive metrics
  - `_supermetrics__sources.yml`: Source definitions

**models/staging/facebook/**
- Purpose: Facebook ads data for conversions and spend
- Contains: Account, campaign, adset, ad, and conversion data
- Key files: `v_stg_facebook_*.sql` (accounts, campaigns, adsets, ads, spend, conversions)

**models/intermediate/**
- Purpose: Complex joins and business logic
- Contains: Device mapping, user journeys, cohort metrics, MTA calculations
- Key files:
  - `int_adjust_amplitude__device_mapping.sql`: Links Adjust device IDs to Amplitude users
  - `int_mta__user_journey.sql`: Touchpoints joined to installs within lookback window
  - `int_mta__touchpoint_credit.sql`: Five attribution models calculated
  - `int_user_cohort__attribution.sql`: User install attribution source
  - `int_user_cohort__metrics.sql`: D7/D30/lifetime revenue and retention
  - `int_revenue__user_summary.sql`: User-level revenue aggregation
  - `int_device_mapping__diagnostics.sql`: Data quality for device mapping
  - `_int_mta__models.yml`: Model documentation for MTA

**models/marts/attribution/**
- Purpose: Business-facing attribution and performance metrics
- Contains: Campaign performance, network comparisons, dashboard reports
- Key files:
  - `attribution__installs.sql`: Install-level attribution with revenue (last-touch)
  - `attribution__campaign_performance.sql`: Campaign metrics joined with spend
  - `mta__campaign_performance.sql`: Multi-touch attribution by campaign
  - `mta__network_comparison.sql`: Network-level MTA comparison
  - `rpt__attribution_model_comparison.sql`: Current vs MTA model comparison
  - `rpt__attribution_weekly_summary.sql`: Weekly executive dashboard
  - `rpt__user_journey_insights.sql`: Journey complexity analytics
  - `mart_campaign_performance_full.sql`: Full campaign performance
  - `_mta__models.yml`: Model documentation

**models/marts/spend/**
- Purpose: Ad spend and performance reporting
- Key files:
  - `adjust_daily_performance_by_ad.sql`: Daily ad-level performance
  - `facebook_conversions.sql`: Facebook conversion tracking

**seeds/**
- Purpose: Static reference data loaded as tables
- Key files:
  - `network_mapping.csv`: Maps Adjust network names to Supermetrics partner IDs

## Key File Locations

**Entry Points:**
- `dbt_project.yml`: Project configuration, materialization settings

**Configuration:**
- `dbt_project.yml`: Model paths, materializations by folder
- `models/staging/*/_*__sources.yml`: Source database/schema/table definitions

**Core Logic:**
- `models/intermediate/int_adjust_amplitude__device_mapping.sql`: Device-to-user mapping
- `models/intermediate/int_mta__touchpoint_credit.sql`: Attribution credit calculations
- `models/intermediate/int_user_cohort__metrics.sql`: User cohort metrics

**Testing:**
- `tests/`: Custom data tests (currently empty)
- Model tests defined in `_*.yml` files via dbt schema tests

## Naming Conventions

**Files:**
- Staging views: `v_stg_{source}__{entity}.sql` (e.g., `v_stg_adjust__installs.sql`)
- Staging tables: `stg_{source}__{entity}.sql` (e.g., `stg_supermetrics__adj_campaign.sql`)
- Intermediate: `int_{domain}__{entity}.sql` (e.g., `int_mta__user_journey.sql`)
- Marts: `{domain}__{entity}.sql` (e.g., `attribution__campaign_performance.sql`)
- MTA marts: `mta__{entity}.sql` (e.g., `mta__campaign_performance.sql`)
- Reports: `rpt__{report_name}.sql` (e.g., `rpt__attribution_weekly_summary.sql`)
- Source definitions: `_{source}__sources.yml`
- Model documentation: `_{domain}__models.yml`

**Directories:**
- Staging subdirs: lowercase source name (e.g., `adjust`, `amplitude`)
- Mart subdirs: lowercase domain name (e.g., `attribution`, `spend`)

**Columns:**
- UPPERCASE with underscores (Snowflake convention)
- Date fields: `DATE`, `INSTALL_DATE`, `WEEK_START`
- Metrics: `D7_REVENUE`, `D30_ROAS`, `CPI_TIME_DECAY`
- Flags: `IS_FIRST_TOUCH`, `IS_PAYER`, `D7_MATURED`
- Credit columns: `CREDIT_LAST_TOUCH`, `CREDIT_TIME_DECAY`

## Where to Add New Code

**New Data Source:**
1. Create source YAML: `models/staging/{source}/_{source}__sources.yml`
2. Create staging models: `models/staging/{source}/v_stg_{source}__{table}.sql`
3. Add to intermediate layer if joins needed

**New Attribution Feature:**
- Primary code: `models/intermediate/int_mta__*.sql`
- Update credit calculation: `int_mta__touchpoint_credit.sql`
- Aggregate in marts: `models/marts/attribution/mta__*.sql`

**New Metric/KPI:**
- User-level: `models/intermediate/int_user_cohort__metrics.sql`
- Campaign-level: `models/marts/attribution/*__campaign_performance.sql`
- Network-level: `models/marts/attribution/*__network_*.sql`

**New Dashboard Report:**
- Location: `models/marts/attribution/rpt__*.sql`
- Follow pattern: Aggregate from existing models, add calculated metrics

**New Seed Data:**
- Location: `seeds/{name}.csv`
- Reference: `{{ ref('{name}') }}`
- Example use: Lookup tables, static mappings

**Utilities/Macros:**
- Location: `macros/`
- Currently empty, add reusable Jinja macros here

## Special Directories

**target/**
- Purpose: Compiled SQL, run artifacts, logs
- Generated: Yes (by `dbt run`)
- Committed: No (in `.gitignore`)

**dbt_packages/**
- Purpose: Installed dbt packages
- Generated: Yes (by `dbt deps`)
- Committed: No (in `.gitignore`)

**.planning/codebase/**
- Purpose: Codebase analysis documentation
- Generated: No (manually created)
- Committed: Yes

**seeds/**
- Purpose: CSV files loaded as tables
- Generated: No
- Committed: Yes
- Note: Run `dbt seed` to load/refresh

---

*Structure analysis: 2026-01-19*
