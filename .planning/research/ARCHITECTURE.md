# Architecture Integration: Pipeline Hardening Features

**Project:** WGT dbt Analytics v1.0
**Research Focus:** Integration of source freshness, singular tests, and macro extraction with existing architecture
**Researched:** 2026-02-11
**Overall Confidence:** HIGH

## Executive Summary

This research addresses how three pipeline hardening features integrate with the existing WGT dbt project architecture:

1. **Source Freshness Monitoring** — Configurations live in existing `_sources.yml` files, no new components needed
2. **Singular Tests** — New `.sql` files in `tests/` directory, organized by domain (tests/mmm/, tests/mta/)
3. **AD_PARTNER Macro Extraction** — New macro file in `macros/` directory, replaces duplicated CASE logic

**Key architectural finding:** All three features integrate cleanly with existing dbt project structure through standard dbt conventions. No structural changes required — only new files added to existing directories.

## Existing Architecture Overview

### Current Layer Structure

```
sources (YAML configs)
  ↓
staging (views)
  - v_stg_adjust__installs
  - v_stg_adjust__touchpoints
  - stg_supermetrics__adj_campaign
  - stg_adjust__report_daily
  ↓
intermediate (incremental tables at int_mmm__*, table otherwise)
  - int_mmm__daily_channel_spend
  - int_mmm__daily_channel_installs
  - int_mmm__daily_channel_revenue
  - int_mta__user_journey
  - int_mta__touchpoint_credit
  ↓
marts (tables)
  - mmm__daily_channel_summary
  - mmm__weekly_channel_summary
  - mart_campaign_performance (MTA)
  - mart_network_comparison (MTA)
```

### Current File Organization

```
models/
  staging/
    adjust/
      _adjust__sources.yml        ← Source definitions
      _adjust__models.yml         ← Model properties + tests
      v_stg_adjust__installs.sql  ← Has duplicated AD_PARTNER CASE
      v_stg_adjust__touchpoints.sql ← Has duplicated AD_PARTNER CASE
    amplitude/
      _amplitude__sources.yml
      _amplitude__models.yml
    supermetrics/
      _supermetrics__sources.yml
    revenue/
      _revenue__sources.yml
  intermediate/
    _int_mmm__models.yml
    int_mmm__daily_channel_spend.sql  ← Incremental
    int_mmm__daily_channel_installs.sql ← Incremental
    int_mmm__daily_channel_revenue.sql ← Incremental
  marts/
    mmm/
      _mmm__models.yml
      mmm__daily_channel_summary.sql  ← Table
      mmm__weekly_channel_summary.sql ← Table

macros/
  generate_schema_name.sql       ← Environment-based schema routing
  get_source_schema.sql
  setup_dev_views.sql

tests/
  .gitkeep                        ← Empty (no singular tests yet)

seeds/
  network_mapping.csv             ← Channel taxonomy for AD_PARTNER mapping
```

### Critical Integration Points

**AD_PARTNER Duplication:**
- Lines 65-83 in `v_stg_adjust__installs.sql`
- Lines 140-158 in `v_stg_adjust__touchpoints.sql`
- Identical 18-line CASE statement mapping NETWORK_NAME → AD_PARTNER
- Used by downstream MMM models via `AD_PARTNER` column

**Incremental Model Pattern:**
- MMM intermediate models use `incremental` materialization with 7-day lookback
- Pattern: `WHERE DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))`
- Critical for freshness: Models must have recent data to avoid stale metrics

**Test Coverage Status:**
- Generic tests exist in `_models.yml` files (uniqueness, not_null, accepted_values)
- No singular tests currently exist
- dbt_utils.unique_combination_of_columns used for composite keys

## Feature 1: Source Freshness Configuration

### Integration Architecture

**Location:** Add `freshness` configs to **existing** `_sources.yml` files in `models/staging/` directories.

**No new files required.** Freshness configs are properties of source definitions, not separate components.

### YAML Structure

Source freshness configurations use this structure within existing source YAML files:

```yaml
version: 2

sources:
  - name: adjust
    description: Adjust mobile attribution data
    database: ADJUST
    schema: S3_DATA
    config:
      freshness:
        warn_after: {count: 12, period: hour}
        error_after: {count: 24, period: hour}
    tables:
      - name: IOS_ACTIVITY_INSTALL
        description: iOS install events with attribution data
        config:
          loaded_at_field: CREATED_AT  # Table-level override
          freshness:
            warn_after: {count: 6, period: hour}
            error_after: {count: 12, period: hour}
```

**Configuration hierarchy:**
1. **Source-level** `freshness` applies to all tables (default)
2. **Table-level** `freshness` overrides source-level for specific tables
3. **loaded_at_field** specifies which column tracks data recency

### Integration with Existing Files

**Modify these existing files:**

| File | Add Freshness For | loaded_at_field |
|------|-------------------|-----------------|
| `models/staging/adjust/_adjust__sources.yml` | All Adjust activity tables | CREATED_AT (epoch timestamp) |
| `models/staging/amplitude/_amplitude__sources.yml` | Amplitude event tables | EVENT_TIME or SERVER_UPLOAD_TIME |
| `models/staging/supermetrics/_supermetrics__sources.yml` | Supermetrics ad spend | DATE (calendar date, need proxy) |
| `models/staging/revenue/_revenue__sources.yml` | Revenue events | EVENT_TIME |

**Example for Adjust sources:**

```yaml
# models/staging/adjust/_adjust__sources.yml
version: 2

sources:
  - name: adjust
    description: Adjust mobile attribution data
    database: ADJUST
    schema: S3_DATA
    config:
      loaded_at_field: CREATED_AT  # Source-level default
      freshness:
        warn_after: {count: 12, period: hour}
        error_after: {count: 24, period: hour}
    tables:
      - name: IOS_ACTIVITY_INSTALL
        description: iOS install events with attribution data
      - name: IOS_ACTIVITY_SESSION
        description: iOS session events
      # ... existing table definitions
```

**No schema changes required.** Freshness checks use existing timestamp columns.

### dbt Cloud Execution

**Validation without local dbt:**

1. **dbt Cloud CI Job** — Add freshness check to CI workflow
   - Command: `dbt source freshness`
   - Runs before `dbt build` to validate data recency
   - Does NOT fail job if freshness fails (use checkbox method)

2. **Dedicated Freshness Job** — Separate scheduled job for monitoring
   - Schedule: Every 1 hour (2x frequency of lowest 2-hour SLA)
   - Command: `dbt source freshness`
   - Store results for alerting
   - Does NOT run model builds

**dbt Cloud UI Configuration:**
- Execution Settings → "Run source freshness" checkbox = runs as first step without breaking build
- OR explicit command `dbt source freshness` = fails job if data stale

**No local dbt required.** All freshness checks run in dbt Cloud scheduled jobs.

### Data Flow Impact

```
Source Tables (Snowflake)
  ↓
[NEW] Freshness Check (dbt source freshness)
  ↓ validates timestamps
Staging Models (views)
  ↓
Intermediate Models (incremental)
  ↓
Marts (tables)
```

**Freshness checks are read-only.** They query source tables to check `loaded_at_field` timestamp, but do not modify data or run models.

### Component Boundaries

| Component | Responsibility | Freshness Role |
|-----------|----------------|----------------|
| Source tables | Raw data from ETL pipelines | Monitored (not modified) |
| Freshness configs | Define SLA thresholds | Lives in source YAML |
| dbt Cloud job | Execute freshness checks | Scheduled independently |
| Staging models | Transform source data | Unchanged (freshness is upstream) |

**No new components.** Freshness monitoring is metadata-only addition to existing source definitions.

## Feature 2: Singular Tests

### Integration Architecture

**Location:** New `.sql` files in `tests/` directory, organized by domain.

**Directory structure:**

```
tests/
  mmm/
    assert_mmm_daily_grain_completeness.sql
    assert_mmm_weekly_rollup_matches_daily.sql
    assert_mmm_revenue_source_consistency.sql
  mta/
    assert_touchpoint_credit_sums_to_one.sql
    assert_user_journey_lookback_coverage.sql
  cross_layer/
    assert_device_counts_staging_to_marts.sql
```

**dbt discovers all `.sql` files in `test-paths`** (default: `["tests"]`). Subdirectories are supported and recommended for organization.

### Singular Test Structure

**What they are:** SQL queries that return **failing rows**. Test passes if query returns zero rows.

**Example — Touchpoint credit sums to 1.0:**

```sql
-- tests/mta/assert_touchpoint_credit_sums_to_one.sql
/*
    Test: Touchpoint credit for each install should sum to exactly 1.0
    Grain: Per DEVICE_ID + PLATFORM + attribution model
    Fails: If any install has credit sum != 1.0 (accounting for floating point)
*/

WITH credit_sums AS (
    SELECT
        DEVICE_ID,
        PLATFORM,
        -- Add attribution model when available
        SUM(CREDIT) AS TOTAL_CREDIT
    FROM {{ ref('int_mta__touchpoint_credit') }}
    GROUP BY DEVICE_ID, PLATFORM
)

SELECT
    DEVICE_ID,
    PLATFORM,
    TOTAL_CREDIT,
    ABS(TOTAL_CREDIT - 1.0) AS DEVIATION
FROM credit_sums
WHERE ABS(TOTAL_CREDIT - 1.0) > 0.001  -- Tolerance for floating point
```

**Example — MMM daily grain completeness:**

```sql
-- tests/mmm/assert_mmm_daily_grain_completeness.sql
/*
    Test: MMM daily summary should have complete date spine with no gaps
    Critical: Time series models require continuous data
    Fails: If any date is missing between min and max date
*/

WITH date_spine AS (
    SELECT
        DATEADD(day, SEQ4(), (SELECT MIN(DATE) FROM {{ ref('mmm__daily_channel_summary') }})) AS DATE
    FROM TABLE(GENERATOR(ROWCOUNT => 1000))
    QUALIFY DATE <= (SELECT MAX(DATE) FROM {{ ref('mmm__daily_channel_summary') }})
),

actual_dates AS (
    SELECT DISTINCT DATE
    FROM {{ ref('mmm__daily_channel_summary') }}
)

SELECT
    date_spine.DATE AS MISSING_DATE
FROM date_spine
LEFT JOIN actual_dates
    ON date_spine.DATE = actual_dates.DATE
WHERE actual_dates.DATE IS NULL
```

**Example — Cross-layer device count consistency:**

```sql
-- tests/cross_layer/assert_device_counts_staging_to_marts.sql
/*
    Test: Device counts should match from staging → intermediate → marts
    Validates: No unexpected duplicates or drops in transformation pipeline
    Fails: If counts differ by more than 1% (allows for edge case filtering)
*/

WITH staging_counts AS (
    SELECT
        DATE(INSTALL_TIMESTAMP) AS DATE,
        PLATFORM,
        COUNT(DISTINCT DEVICE_ID) AS STAGING_INSTALLS
    FROM {{ ref('v_stg_adjust__installs') }}
    WHERE INSTALL_TIMESTAMP >= DATEADD(day, -30, CURRENT_DATE)
    GROUP BY 1, 2
),

intermediate_counts AS (
    SELECT
        DATE,
        PLATFORM,
        SUM(INSTALLS) AS INTERMEDIATE_INSTALLS
    FROM {{ ref('int_mmm__daily_channel_installs') }}
    WHERE DATE >= DATEADD(day, -30, CURRENT_DATE)
    GROUP BY 1, 2
),

mart_counts AS (
    SELECT
        DATE,
        PLATFORM,
        SUM(INSTALLS) AS MART_INSTALLS
    FROM {{ ref('mmm__daily_channel_summary') }}
    WHERE DATE >= DATEADD(day, -30, CURRENT_DATE)
    GROUP BY 1, 2
)

SELECT
    s.DATE,
    s.PLATFORM,
    s.STAGING_INSTALLS,
    i.INTERMEDIATE_INSTALLS,
    m.MART_INSTALLS,
    ABS(s.STAGING_INSTALLS - i.INTERMEDIATE_INSTALLS) AS STAGING_TO_INT_DIFF,
    ABS(i.INTERMEDIATE_INSTALLS - m.MART_INSTALLS) AS INT_TO_MART_DIFF
FROM staging_counts s
FULL OUTER JOIN intermediate_counts i USING (DATE, PLATFORM)
FULL OUTER JOIN mart_counts m USING (DATE, PLATFORM)
WHERE
    ABS(s.STAGING_INSTALLS - i.INTERMEDIATE_INSTALLS) / NULLIF(s.STAGING_INSTALLS, 0) > 0.01
    OR ABS(i.INTERMEDIATE_INSTALLS - m.MART_INSTALLS) / NULLIF(i.INTERMEDIATE_INSTALLS, 0) > 0.01
```

### Integration with Existing Tests

**Current generic tests** (in `_models.yml` files):
- `not_null` — Column-level null checks
- `unique` — Primary key uniqueness
- `dbt_utils.unique_combination_of_columns` — Composite key uniqueness
- `accepted_values` — Enum validation (e.g., PLATFORM in ['iOS', 'Android'])
- `relationships` — Foreign key validation

**New singular tests** complement generic tests:
- **Generic tests:** Data shape and schema validation (structural)
- **Singular tests:** Business logic and cross-model validation (semantic)

**Test execution:**
```bash
dbt test                                    # Run all tests
dbt test --select test_type:singular       # Only singular tests
dbt test --select test_type:generic        # Only generic tests
dbt test --select tests/mmm/*              # Only MMM singular tests
```

### Naming Convention

**Pattern:** `assert_<what_is_being_tested>.sql`

**Examples:**
- `assert_touchpoint_credit_sums_to_one.sql`
- `assert_mmm_weekly_rollup_matches_daily.sql`
- `assert_revenue_source_consistency.sql`
- `assert_device_counts_staging_to_marts.sql`

**Benefits:**
- Clear test purpose from filename
- Easy to grep for failing test in logs
- Autocomplete-friendly in IDE

### dbt Cloud CI Integration

**Validation without local dbt:**

1. **CI Job includes tests automatically**
   - Default command: `dbt build --select state:modified+`
   - `dbt build` runs models AND tests in DAG order
   - Singular tests run after their referenced models

2. **Slim CI for modified tests**
   - Only tests referencing modified models run
   - Speeds up PR validation
   - Uses production as comparison state

3. **Test failure behavior**
   - Test failure = job failure
   - PR cannot merge until tests pass
   - Logs show failing rows for debugging

**No local dbt required.** CI jobs validate singular tests in dbt Cloud on every PR.

### Data Flow Impact

```
Staging Models
  ↓
Intermediate Models
  ↓
Marts
  ↓
[NEW] Singular Tests (query marts to validate business rules)
```

**Tests are read-only.** They query existing models but do not modify data or create new tables.

### Component Boundaries

| Component | Responsibility | Test Interaction |
|-----------|----------------|------------------|
| Staging models | Source normalization | Tested by generic tests |
| Intermediate models | Business logic | Tested by singular + generic tests |
| Marts | Aggregated metrics | Tested by singular tests (cross-layer validation) |
| Singular tests | Validate business rules | Query multiple models to assert correctness |

**Tests are separate from models** in DAG — they depend on models but models do not depend on tests.

## Feature 3: AD_PARTNER Macro Extraction

### Integration Architecture

**Location:** New file `macros/map_ad_partner.sql` in existing `macros/` directory.

**Current duplication:**
- `v_stg_adjust__installs.sql` lines 65-83
- `v_stg_adjust__touchpoints.sql` lines 140-158

**After extraction:**
- Macro defines logic once
- Both models call `{{ map_ad_partner('NETWORK_NAME') }}`

### Macro Structure

**File:** `macros/map_ad_partner.sql`

```sql
{% macro map_ad_partner(network_name_column) %}
    CASE
        WHEN {{ network_name_column }} IN ('Facebook Installs', 'Instagram Installs', 'Off-Facebook Installs', 'Facebook Messenger Installs') THEN 'Meta'
        WHEN {{ network_name_column }} IN ('Google Ads ACE', 'Google Ads ACI', 'Google Organic Search', 'google') THEN 'Google'
        WHEN {{ network_name_column }} IN ('TikTok SAN', 'TikTok_Paid_Ads_iOS', 'Tiktok Installs') THEN 'TikTok'
        WHEN {{ network_name_column }} = 'Apple Search Ads' THEN 'Apple'
        WHEN {{ network_name_column }} LIKE 'AppLovin%' THEN 'AppLovin'
        WHEN {{ network_name_column }} LIKE 'UnityAds%' THEN 'Unity'
        WHEN {{ network_name_column }} LIKE 'Moloco%' THEN 'Moloco'
        WHEN {{ network_name_column }} LIKE 'Smadex%' THEN 'Smadex'
        WHEN {{ network_name_column }} LIKE 'AdAction%' THEN 'AdAction'
        WHEN {{ network_name_column }} LIKE 'Vungle%' THEN 'Vungle'
        WHEN {{ network_name_column }} = 'Organic' THEN 'Organic'
        WHEN {{ network_name_column }} = 'Unattributed' THEN 'Unattributed'
        WHEN {{ network_name_column }} = 'Untrusted Devices' THEN 'Untrusted'
        WHEN {{ network_name_column }} IN ('wgtgolf', 'WGT_Events_SocialPosts_iOS', 'WGT_GiftCards_Social') THEN 'WGT'
        WHEN {{ network_name_column }} LIKE 'Phigolf%' THEN 'Phigolf'
        WHEN {{ network_name_column }} LIKE 'Ryder%' THEN 'Ryder Cup'
        ELSE 'Other'
    END
{% endmacro %}
```

**Usage in models:**

```sql
-- v_stg_adjust__installs.sql (AFTER refactor)
SELECT
    DEVICE_ID,
    PLATFORM,
    NETWORK_NAME,
    {{ map_ad_partner('NETWORK_NAME') }} AS AD_PARTNER,  -- Replaces 18-line CASE
    CAMPAIGN_NAME,
    -- ... rest of columns
FROM DEDUPED
```

```sql
-- v_stg_adjust__touchpoints.sql (AFTER refactor)
SELECT
    DEVICE_ID,
    PLATFORM,
    NETWORK_NAME,
    {{ map_ad_partner('NETWORK_NAME') }} AS AD_PARTNER,  -- Replaces 18-line CASE
    CAMPAIGN_NAME,
    -- ... rest of columns
FROM all_touchpoints
```

### Macro Organization

**Current macros directory:**

```
macros/
  generate_schema_name.sql   ← Environment routing (dev vs prod schemas)
  get_source_schema.sql      ← Source schema helper
  setup_dev_views.sql        ← Development setup helper
```

**After adding AD_PARTNER macro:**

```
macros/
  generate_schema_name.sql
  get_source_schema.sql
  setup_dev_views.sql
  map_ad_partner.sql         ← NEW: AD_PARTNER mapping logic
```

**Subdirectory option** (if more macros added later):

```
macros/
  schema/
    generate_schema_name.sql
    get_source_schema.sql
  helpers/
    setup_dev_views.sql
    map_ad_partner.sql
```

**dbt discovers macros automatically** — all `.sql` files in `macro-paths` (default: `["macros"]`) are loaded, including subdirectories.

### Integration with Existing Models

**Models affected:**

| Model | Current Lines | After Macro | Change |
|-------|---------------|-------------|--------|
| `v_stg_adjust__installs.sql` | 96 lines | 78 lines | -18 lines |
| `v_stg_adjust__touchpoints.sql` | 168 lines | 150 lines | -18 lines |

**Downstream impact:**

| Layer | Model | AD_PARTNER Usage | Impact |
|-------|-------|------------------|--------|
| Staging | `v_stg_adjust__installs` | Outputs AD_PARTNER column | Modified (uses macro) |
| Staging | `v_stg_adjust__touchpoints` | Outputs AD_PARTNER column | Modified (uses macro) |
| Intermediate | `int_mmm__daily_channel_installs` | Reads AD_PARTNER from staging | **No change** |
| Intermediate | `int_mmm__daily_channel_spend` | Uses network_mapping seed | **No change** |
| Intermediate | `int_mmm__daily_channel_revenue` | Uses network_mapping seed | **No change** |
| Marts | `mmm__daily_channel_summary` | Aggregates by CHANNEL | **No change** |

**Critical: Macro refactor is transparent to downstream models.** The `AD_PARTNER` column still exists with identical values — only the SQL generation mechanism changes.

### Consistency Validation

**Pre-deployment test** (singular test for Phase 4):

```sql
-- tests/staging/assert_ad_partner_macro_consistency.sql
/*
    Test: Verify macro produces identical AD_PARTNER as original CASE statement
    Purpose: Validate refactor before removing old CASE logic
    Fails: If any NETWORK_NAME produces different AD_PARTNER after macro extraction
*/

WITH macro_mapping AS (
    SELECT DISTINCT
        NETWORK_NAME,
        {{ map_ad_partner('NETWORK_NAME') }} AS MACRO_AD_PARTNER
    FROM {{ ref('v_stg_adjust__installs') }}
),

-- This CTE would need to query a backup of the old logic or use compiled SQL comparison
-- Example assumes old CASE logic temporarily preserved as OLD_AD_PARTNER column for validation
original_mapping AS (
    SELECT DISTINCT
        NETWORK_NAME,
        AD_PARTNER AS ORIGINAL_AD_PARTNER
    FROM {{ ref('v_stg_adjust__installs') }}
)

SELECT
    o.NETWORK_NAME,
    o.ORIGINAL_AD_PARTNER,
    m.MACRO_AD_PARTNER
FROM original_mapping o
FULL OUTER JOIN macro_mapping m USING (NETWORK_NAME)
WHERE o.ORIGINAL_AD_PARTNER != m.MACRO_AD_PARTNER
   OR (o.ORIGINAL_AD_PARTNER IS NULL AND m.MACRO_AD_PARTNER IS NOT NULL)
   OR (o.ORIGINAL_AD_PARTNER IS NOT NULL AND m.MACRO_AD_PARTNER IS NULL)
```

**Post-deployment validation:**

```bash
# In dbt Cloud job or local dbt
dbt run --select v_stg_adjust__installs v_stg_adjust__touchpoints
dbt test --select v_stg_adjust__installs v_stg_adjust__touchpoints

# Verify downstream models compile without errors
dbt compile --select int_mmm__daily_channel_installs+
```

### dbt Cloud Validation

**No local dbt required:**

1. **CI Job validates macro refactor**
   - `dbt build --select state:modified+`
   - Compiles staging models with macro
   - Runs tests on refactored models
   - Builds downstream models to verify no breakage

2. **Compiled SQL inspection** (dbt Cloud UI)
   - Navigate to compiled SQL for staging models
   - Verify macro expands to full CASE statement
   - Compare compiled SQL before/after refactor

**Macro changes trigger full model recompilation** — dbt Cloud detects macro modifications and recompiles all models that reference the macro.

### Data Flow Impact

```
[BEFORE]
v_stg_adjust__installs.sql (CASE statement lines 65-83)
v_stg_adjust__touchpoints.sql (CASE statement lines 140-158)
  ↓
int_mmm__daily_channel_installs.sql (reads AD_PARTNER)
  ↓
mmm__daily_channel_summary.sql (aggregates by CHANNEL)

[AFTER]
macros/map_ad_partner.sql (CASE logic defined once)
  ↓ (compiled into)
v_stg_adjust__installs.sql (calls {{ map_ad_partner('NETWORK_NAME') }})
v_stg_adjust__touchpoints.sql (calls {{ map_ad_partner('NETWORK_NAME') }})
  ↓
int_mmm__daily_channel_installs.sql (reads AD_PARTNER — unchanged)
  ↓
mmm__daily_channel_summary.sql (aggregates by CHANNEL — unchanged)
```

**Compiled SQL is identical.** Macro is a code organization change, not a logic change.

### Component Boundaries

| Component | Responsibility | Before Refactor | After Refactor |
|-----------|----------------|-----------------|----------------|
| `map_ad_partner` macro | Define NETWORK_NAME → AD_PARTNER mapping | N/A (doesn't exist) | **NEW:** Single source of truth |
| `v_stg_adjust__installs` | Normalize install events | Contains CASE logic | Calls macro |
| `v_stg_adjust__touchpoints` | Normalize touchpoint events | Contains CASE logic | Calls macro |
| Downstream models | Business logic and aggregation | Read AD_PARTNER column | Read AD_PARTNER column (no change) |

**Macro is compile-time only** — it does not create runtime components or tables. It generates SQL that is embedded into model definitions.

## Architectural Patterns to Follow

### Pattern 1: Freshness Configs Co-Located with Source Definitions

**What:** Source freshness configurations live in the same YAML file as source table definitions.

**Why:**
- Single file contains all source metadata (schema, tables, freshness)
- Easy to update freshness SLAs when source changes
- No separate "monitoring config" files to maintain

**Example:**

```yaml
# models/staging/adjust/_adjust__sources.yml
sources:
  - name: adjust
    config:
      freshness:
        warn_after: {count: 12, period: hour}
```

**Anti-pattern:** Creating separate `monitoring.yml` or `freshness.yml` files disconnected from source definitions.

### Pattern 2: Singular Tests Organized by Domain

**What:** Group singular tests into subdirectories matching model layer or business domain.

**Why:**
- Clear ownership and discoverability
- Easy to run domain-specific tests (`dbt test --select tests/mmm/*`)
- Mirrors model directory structure

**Example:**

```
tests/
  mmm/           ← Tests for MMM pipeline
  mta/           ← Tests for MTA pipeline
  cross_layer/   ← Tests spanning multiple layers
  staging/       ← Tests for staging layer edge cases
```

**Anti-pattern:** All singular tests in flat `tests/` directory with no organization.

### Pattern 3: Macros for Repeated Business Logic

**What:** Extract CASE statements, complex transformations, or repeated SQL patterns into macros.

**When:**
- Logic appears in 2+ models
- Logic is >10 lines
- Logic represents business rules (not boilerplate)

**Example:** `map_ad_partner()` macro for NETWORK_NAME → AD_PARTNER mapping.

**Anti-pattern:** Creating macros for simple column aliases or one-off transformations (over-abstraction).

### Pattern 4: Incremental Models with Lookback Windows

**What:** Incremental models use lookback windows to handle late-arriving data.

**Why:**
- Source data may arrive out of order
- Ensures recent data is reprocessed on each run
- Prevents data gaps from late data

**Example:**

```sql
{% if is_incremental() %}
  AND DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
{% endif %}
```

**Trade-off:** 7-day lookback means reprocessing 7 days of data on each run, but guarantees data completeness.

### Pattern 5: Test Scope Limited to Recent Data

**What:** Singular tests include `WHERE` clauses to limit scope to recent data (e.g., last 30 days).

**Why:**
- Prevents historical data issues from blocking current development
- Faster test execution
- Focuses validation on actively changing data

**Example:**

```sql
WHERE DATE >= DATEADD(day, -30, CURRENT_DATE)
```

**Anti-pattern:** Testing entire dataset history, causing tests to fail on unchangeable historical data.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Source Freshness on Non-Timestamp Columns

**What goes wrong:** Configuring `loaded_at_field` to point to a business date column instead of ETL timestamp.

**Why bad:** Business dates (e.g., `DATE` in aggregated tables) don't reflect data freshness — data could be days old with a current business date.

**Prevention:** Use ETL timestamps (CREATED_AT, LOAD_TIMESTAMP, SERVER_UPLOAD_TIME) for freshness checks, not business dates.

**Example:**

```yaml
# BAD
loaded_at_field: DATE  # Business date, not ETL timestamp

# GOOD
loaded_at_field: CREATED_AT  # Actual data arrival timestamp
```

### Anti-Pattern 2: Singular Tests Without Failure Context

**What goes wrong:** Test queries return only IDs without showing *why* the test failed.

**Why bad:** Debugging requires re-running test with additional columns to understand failure.

**Prevention:** Include relevant context columns in test output (not just failing keys).

**Example:**

```sql
-- BAD: Only shows which installs failed
SELECT DEVICE_ID
FROM credit_sums
WHERE ABS(TOTAL_CREDIT - 1.0) > 0.001

-- GOOD: Shows *why* they failed
SELECT
    DEVICE_ID,
    PLATFORM,
    TOTAL_CREDIT,
    ABS(TOTAL_CREDIT - 1.0) AS DEVIATION  -- Shows magnitude of failure
FROM credit_sums
WHERE ABS(TOTAL_CREDIT - 1.0) > 0.001
```

### Anti-Pattern 3: Macros with Hardcoded Values

**What goes wrong:** Macros contain hardcoded database names, schemas, or magic numbers instead of parameters or variables.

**Why bad:** Macros become environment-specific and break in dev/prod/CI.

**Prevention:** Use `target` context variables and macro parameters.

**Example:**

```sql
-- BAD: Hardcoded schema
{% macro get_installs() %}
    SELECT * FROM PROD.S3_DATA.IOS_ACTIVITY_INSTALL
{% endmacro %}

-- GOOD: Uses source() function
{% macro get_installs() %}
    SELECT * FROM {{ source('adjust', 'IOS_ACTIVITY_INSTALL') }}
{% endmacro %}
```

### Anti-Pattern 4: Over-Abstracting with Macros

**What goes wrong:** Creating macros for simple operations that are clearer as inline SQL.

**Why bad:** Reduces readability — readers must jump to macro definition to understand logic.

**Prevention:** Only create macros for logic repeated 2+ times or complex transformations (>10 lines).

**Example:**

```sql
-- BAD: Macro for simple column alias
{% macro platform_name(col) %}
    CASE WHEN {{ col }} = 'i' THEN 'iOS' ELSE 'Android' END
{% endmacro %}

-- GOOD: Inline for one-off simple transformation
CASE WHEN platform_code = 'i' THEN 'iOS' ELSE 'Android' END AS PLATFORM
```

### Anti-Pattern 5: Freshness Without Alerting

**What goes wrong:** Configuring source freshness but not setting up alerting or scheduled jobs.

**Why bad:** Freshness checks only help if someone monitors them — silent failures are useless.

**Prevention:**
- Schedule dedicated freshness job in dbt Cloud
- Set up alerts (email, Slack, PagerDuty)
- Document escalation path for stale data

**Example:**

```yaml
# Config exists but no job runs it = useless
freshness:
  warn_after: {count: 12, period: hour}

# Must also:
# 1. Create dbt Cloud job scheduled every 6 hours
# 2. Add dbt source freshness to job commands
# 3. Configure job notifications to team Slack channel
```

## Build Order Recommendation

Based on architectural dependencies and risk management:

### Phase 4: DRY Refactor (AD_PARTNER Macro)

**Build order:**

1. **Create macro file** — `macros/map_ad_partner.sql`
   - Define CASE logic once
   - Add macro documentation (Jinja comments)

2. **Create consistency test** — `tests/staging/assert_ad_partner_macro_consistency.sql`
   - Validate macro produces identical output to original CASE
   - Run test against production data

3. **Refactor first model** — `v_stg_adjust__installs.sql`
   - Replace CASE statement with `{{ map_ad_partner('NETWORK_NAME') }}`
   - Commit and run CI

4. **Refactor second model** — `v_stg_adjust__touchpoints.sql`
   - Replace CASE statement with `{{ map_ad_partner('NETWORK_NAME') }}`
   - Commit and run CI

5. **Validate downstream** — Run downstream models
   - `dbt build --select int_mmm__daily_channel_installs+ int_mmm__daily_channel_spend+`
   - Verify no breakage

**Rationale:** Create macro first, validate with test, then refactor models incrementally. Downstream models unchanged.

### Phase 5: Expand Test Coverage (Singular Tests)

**Build order:**

1. **Create test directory structure**
   ```bash
   mkdir tests/mmm tests/mta tests/cross_layer tests/staging
   ```

2. **Write MMM singular tests** — Domain-specific business rules
   - `tests/mmm/assert_mmm_daily_grain_completeness.sql`
   - `tests/mmm/assert_mmm_weekly_rollup_matches_daily.sql`
   - `tests/mmm/assert_mmm_revenue_source_consistency.sql`

3. **Write MTA singular tests** (if MTA pipeline still active)
   - `tests/mta/assert_touchpoint_credit_sums_to_one.sql`
   - `tests/mta/assert_user_journey_lookback_coverage.sql`

4. **Write cross-layer tests** — Validate data integrity across layers
   - `tests/cross_layer/assert_device_counts_staging_to_marts.sql`

5. **Run and debug tests**
   - `dbt test --select test_type:singular`
   - Fix failures (either data issues or test logic)

6. **Add to CI** — Tests automatically run via `dbt build` in CI jobs

**Rationale:** Tests organized by domain for maintainability. MMM tests first (active pipeline), MTA tests second (limited pipeline).

### Phase 6: Source Freshness & Observability

**Build order:**

1. **Add freshness to Adjust sources** — `models/staging/adjust/_adjust__sources.yml`
   - Add `loaded_at_field: CREATED_AT`
   - Add `freshness` config with warn/error thresholds

2. **Add freshness to Amplitude sources** — `models/staging/amplitude/_amplitude__sources.yml`
   - Identify correct timestamp column (EVENT_TIME vs SERVER_UPLOAD_TIME)
   - Add `freshness` config

3. **Add freshness to Supermetrics sources** — `models/staging/supermetrics/_supermetrics__sources.yml`
   - Use proxy approach if no ETL timestamp
   - Add `freshness` config

4. **Add freshness to Revenue sources** — `models/staging/revenue/_revenue__sources.yml`
   - Add `freshness` config

5. **Create dbt Cloud freshness job**
   - Schedule: Every 1 hour
   - Command: `dbt source freshness`
   - Notifications: Slack or email

6. **Test freshness checks**
   - Manually run job in dbt Cloud
   - Verify freshness results appear in logs
   - Trigger failure (temporarily lower threshold) to test alerting

**Rationale:** Configure freshness incrementally by source, then create scheduled job. Test job before production rollout.

## Component Integration Summary

### New Components

| Component | Type | Location | Purpose |
|-----------|------|----------|---------|
| Source freshness configs | YAML properties | `models/staging/*/_*__sources.yml` | Define data freshness SLAs |
| Singular tests | SQL queries | `tests/mmm/`, `tests/mta/`, `tests/cross_layer/` | Validate business rules |
| `map_ad_partner` macro | Jinja macro | `macros/map_ad_partner.sql` | DRY AD_PARTNER mapping logic |
| Freshness monitoring job | dbt Cloud job | dbt Cloud UI | Scheduled freshness checks |

### Modified Components

| Component | Change Type | Purpose |
|-----------|-------------|---------|
| `_adjust__sources.yml` | Add freshness config | Monitor Adjust data recency |
| `_amplitude__sources.yml` | Add freshness config | Monitor Amplitude data recency |
| `_supermetrics__sources.yml` | Add freshness config | Monitor Supermetrics data recency |
| `_revenue__sources.yml` | Add freshness config | Monitor Revenue data recency |
| `v_stg_adjust__installs.sql` | Replace CASE with macro call | Use centralized AD_PARTNER logic |
| `v_stg_adjust__touchpoints.sql` | Replace CASE with macro call | Use centralized AD_PARTNER logic |

### Unchanged Components

- All intermediate models (no structural changes)
- All mart models (no structural changes)
- `network_mapping` seed (still used for Supermetrics mapping)
- Generic tests in `_models.yml` files (supplemented, not replaced)
- `generate_schema_name` macro (continues to route schemas by environment)

## Validation Strategy (No Local dbt)

### dbt Cloud CI Validation

**Automatic validation on every PR:**

1. **Macro changes** trigger recompilation of all dependent models
2. **Test changes** run against modified models (Slim CI)
3. **Source config changes** validated during compilation (syntax check)

**CI job commands:**

```bash
# Standard CI job (validates models + tests)
dbt build --select state:modified+

# Freshness validation (add to CI job for source changes)
dbt source freshness
```

### Manual Validation in dbt Cloud

**For freshness configs:**

1. Navigate to dbt Cloud job
2. Add `dbt source freshness` to commands
3. Run job manually
4. Check logs for freshness results

**For singular tests:**

1. Write test SQL file
2. Commit to feature branch
3. CI job runs `dbt build` (includes tests)
4. Review job logs for test results

**For macros:**

1. Create macro file
2. Commit to feature branch
3. CI job compiles models using macro
4. Inspect compiled SQL in dbt Cloud UI

**No local dbt installation required.** All validation happens in dbt Cloud jobs.

### Compiled SQL Inspection

**To verify macro expansion:**

1. Navigate to dbt Cloud job run
2. Select model (e.g., `v_stg_adjust__installs`)
3. View "Compiled" tab
4. Verify macro expanded to full CASE statement
5. Compare compiled SQL before/after refactor

**This validates macro logic without running queries.**

## Downstream Roadmap Implications

### Phase Ordering Rationale

**Current roadmap order:**
- Phase 4: DRY Refactor (macro extraction)
- Phase 5: Expand Test Coverage (singular tests)
- Phase 6: Source Freshness & Observability

**Architectural justification:**

1. **Phase 4 first** — Macro extraction must complete before comprehensive testing
   - Reason: Tests should validate macro logic, not duplicated CASE statements
   - Dependency: Phase 5 singular tests reference staging models refactored in Phase 4

2. **Phase 5 second** — Singular tests validate refactored models and business logic
   - Reason: Tests protect production pipeline before adding monitoring
   - Dependency: Tests must pass before adding alerting (Phase 6)

3. **Phase 6 last** — Observability layer assumes stable, tested pipeline
   - Reason: Freshness alerts only valuable if data pipeline is validated
   - Dependency: Source freshness should monitor a pipeline with high test coverage

**This order minimizes risk:** Code quality improvements (Phase 4) → validation (Phase 5) → monitoring (Phase 6).

### Research Flags for Future Phases

**Phase 4 (DRY Refactor):**
- ✅ HIGH confidence — Macro organization well-documented
- ✅ HIGH confidence — dbt Cloud validation strategy clear
- ⚠️ MEDIUM confidence — Consistency test strategy requires custom SQL (no built-in test)

**Phase 5 (Expand Test Coverage):**
- ✅ HIGH confidence — Singular test structure well-documented
- ✅ HIGH confidence — Test organization patterns clear
- ⚠️ MEDIUM confidence — Business rule tests require domain knowledge (not architectural)

**Phase 6 (Source Freshness):**
- ✅ HIGH confidence — Freshness config location and syntax verified
- ✅ HIGH confidence — dbt Cloud job setup documented
- ⚠️ MEDIUM confidence — Appropriate thresholds require operational data (SLA analysis)

**No deep research gaps.** All three features have clear integration patterns with existing architecture.

## Sources

### Official dbt Documentation

- [Source freshness configuration](https://docs.getdbt.com/reference/resource-configs/freshness)
- [Source freshness deployment](https://docs.getdbt.com/docs/deploy/source-freshness)
- [Add sources to your DAG](https://docs.getdbt.com/docs/build/sources)
- [Source configurations](https://docs.getdbt.com/reference/source-configs)
- [Data tests overview](https://docs.getdbt.com/docs/build/data-tests)
- [test-paths configuration](https://docs.getdbt.com/reference/project-configs/test-paths)
- [Jinja and macros](https://docs.getdbt.com/docs/build/jinja-macros)
- [macro-paths configuration](https://docs.getdbt.com/reference/project-configs/macro-paths)
- [Continuous integration in dbt Cloud](https://docs.getdbt.com/docs/deploy/ci-jobs)
- [Get started with CI tests](https://docs.getdbt.com/guides/set-up-ci)

### Community Resources and Best Practices

- [dbt source freshness usage and examples](https://popsql.com/learn-dbt/dbt-sources)
- [Testing data sources in dbt](https://dbtips.substack.com/p/testing-data-sources-in-dbt)
- [dbt testing best practices](https://www.datafold.com/blog/7-dbt-testing-best-practices)
- [dbt project structure guide](https://medium.com/@likkilaxminarayana/6-dbt-project-structure-explained-a-practical-guide-for-analytics-engineers-5894f6230756)
- [dbt macros comprehensive guide](https://www.datacamp.com/tutorial/dbt-macros)
- [dbt macros best practices](https://medium.com/tech-with-abhishek/7-dbt-macros-that-actually-made-our-platform-maintainable-02d3e7756860)
- [Organizing dbt projects](https://www.thedataschool.co.uk/curtis-paterson/organising-a-dbt-project-best-practices/)
