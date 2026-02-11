# Architecture Research: Device Mapping Fixes & dbt Testing Integration

**Domain:** dbt Analytics Pipeline (Snowflake + Mobile Attribution)
**Researched:** 2026-02-10
**Confidence:** HIGH

## Standard Architecture: Three-Layer dbt Pipeline

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          MARTS (Business Layer)                          │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────┐│
│  │ mart_network_        │  │ mart_campaign_       │  │ attribution__  ││
│  │ performance_mta      │  │ performance_full_mta │  │ *              ││
│  └──────────┬───────────┘  └──────────┬───────────┘  └────────┬───────┘│
│             │                          │                       │        │
├─────────────┴──────────────────────────┴───────────────────────┴────────┤
│                      INTERMEDIATE (Complex Logic)                        │
│  ┌──────────────────┐  ┌──────────────────┐  ┌─────────────────────┐   │
│  │ int_mta__        │  │ int_adjust_      │  │ int_device_mapping__││
│  │ user_journey     │  │ amplitude__      │  │ diagnostics         ││
│  │                  │  │ device_mapping   │  │                     ││
│  └────────┬─────────┘  └────────┬─────────┘  └──────────┬──────────┘   │
│           │                     │                        │              │
├───────────┴─────────────────────┴────────────────────────┴──────────────┤
│                       STAGING (Source Normalization)                     │
│  ┌───────────────┐  ┌───────────────┐  ┌──────────────────────────┐    │
│  │ v_stg_adjust__│  │ v_stg_        │  │ stg_adjust__             │    │
│  │ installs      │  │ amplitude__   │  │ [platform]_activity_*    │    │
│  │ touchpoints   │  │ merge_ids     │  │                          │    │
│  └───────┬───────┘  └───────┬───────┘  └───────┬──────────────────┘    │
│          │                  │                   │                       │
├──────────┴──────────────────┴───────────────────┴───────────────────────┤
│                           SOURCES (Raw Data)                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │ adjust.      │  │ amplitude.   │  │ network_     │  │ adjust_api_ │ │
│  │ S3_DATA      │  │ EVENTS_*     │  │ mapping.csv  │  │ data.       │ │
│  └──────────────┘  └──────────────┘  └──────────────┘  └─────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

### Layer Responsibilities

| Layer | Responsibility | Materialization | When to Modify |
|-------|----------------|-----------------|----------------|
| **Staging** | Source normalization, light transforms, rename columns | `view` | Adding/fixing source references, standardizing field names |
| **Intermediate** | Complex joins, device mapping, user journeys, credit attribution | `table` (incremental) | Business logic changes, new calculated fields, join fixes |
| **Marts** | Business-facing aggregations, reporting-ready tables | `table` (incremental) | New aggregation levels, dashboard requirements |
| **Seeds** | Static reference data (network mappings, config) | `seed` | Network name standardization, lookup table updates |
| **Macros** | Reusable SQL snippets, schema routing, duplicate code | N/A | DRY violations, environment config, shared logic |

## NEW Components for Device Mapping Fixes

### 1. Macro: `map_ad_partner()` (NEW)

**What:** Centralized CASE statement for AD_PARTNER mapping
**Where:** `/Users/riley/Documents/GitHub/wgt-dbt/macros/map_ad_partner.sql`
**Why:** Eliminates duplicate 18-line CASE statement in v_stg_adjust__installs and v_stg_adjust__touchpoints

**Integration Points:**
- Called by `v_stg_adjust__installs.sql` (line 65-83 → macro call)
- Called by `v_stg_adjust__touchpoints.sql` (line 136-154 → macro call)
- Returns standardized AD_PARTNER from NETWORK_NAME

**Example:**
```sql
{% macro map_ad_partner(network_name_column) %}
    CASE
        WHEN {{ network_name_column }} IN ('Facebook Installs', 'Instagram Installs', ...) THEN 'Meta'
        WHEN {{ network_name_column }} IN ('Google Ads ACE', 'Google Ads ACI', ...) THEN 'Google'
        ...
        ELSE 'Other'
    END
{% endmacro %}
```

**Impact:**
- Reduces code duplication by 36 lines
- Single source of truth for partner mapping
- Future network additions only need one update

### 2. Staging Model: `v_stg_amplitude__merge_ids.sql` (MODIFIED)

**Current State:** Strips 'R' suffix from Android DEVICE_ID, uppercases iOS IDFV
**Issue:** Android match rate is poor because logic assumes Amplitude device_id = Adjust GPS_ADID with 'R' suffix

**Device ID Fix Required:**
```sql
-- CURRENT (line 50-54):
UPPER(
    IFF(PLATFORM = 'Android' AND RIGHT(DEVICE_ID, 1) = 'R'
       , LEFT(DEVICE_ID, LENGTH(DEVICE_ID) - 1)
       , DEVICE_ID
    )
) AS DEVICE_ID_UUID

-- NEEDS INVESTIGATION:
-- 1. Verify Amplitude device_id format for Android (UUID? GPS_ADID?)
-- 2. Verify Adjust GPS_ADID format (uppercase UUID per v_stg_adjust__installs line 29)
-- 3. Test match rates with different normalization strategies
-- 4. Document actual format in model comments
```

**Integration Points:**
- Input: `source('amplitude', 'EVENTS_726530')` → DEVICE_ID, USER_ID, PLATFORM
- Output: `int_adjust_amplitude__device_mapping` (line 14)
- Downstream: All revenue attribution depends on this mapping quality

### 3. Intermediate Model: `int_adjust_amplitude__device_mapping.sql` (MODIFIED)

**Current State:** Simple passthrough with 7-day incremental lookback
**Issue:** No validation of mapping quality, no duplicate handling

**Enhancement Required:**
```sql
-- ADD: Deduplication logic if multiple Amplitude users share a device
-- ADD: Validation that ADJUST_DEVICE_ID matches expected format
-- ADD: Logging of unmappable records for diagnostics
```

**Integration Points:**
- Input: `ref('v_stg_amplitude__merge_ids')` → normalized device IDs
- Output: Used by revenue models (not in MTA pipeline, but critical for ROAS)
- Testing: Primary key test on `[ADJUST_DEVICE_ID, AMPLITUDE_USER_ID, PLATFORM]`

### 4. Diagnostic Model: `int_device_mapping__diagnostics.sql` (EXISTING)

**Purpose:** Data quality table for multi-device users
**Materialization:** `table` (not incremental - full refresh for accuracy)

**Current State:** Already built, surfaces users with 100+ devices as anomalies
**No Changes Required:** This is a monitoring table, not part of pipeline DAG

**Usage:** Business users query this to identify test accounts, fraud, shared devices

### 5. Diagnostic Model: `int_device_mapping__distribution_summary.sql` (EXISTING)

**Purpose:** Executive summary of device mapping quality
**Materialization:** `table` (full refresh)

**Current State:** Already built, shows user distribution across device count buckets
**No Changes Required:** This is a reporting table, not part of pipeline DAG

**Usage:** Stakeholder communication about data quality and match rates

## NEW Components for dbt Testing

### 6. Model YAML Configs (MODIFIED - Multiple Files)

**Pattern:** Co-locate tests with models in same directory

**Files to Modify:**
- `/Users/riley/Documents/GitHub/wgt-dbt/models/staging/adjust/_adjust__sources.yml`
- `/Users/riley/Documents/GitHub/wgt-dbt/models/staging/amplitude/_amplitude__sources.yml`
- `/Users/riley/Documents/GitHub/wgt-dbt/models/intermediate/_int_mta__models.yml`
- *NEW:* `/Users/riley/Documents/GitHub/wgt-dbt/models/staging/adjust/_adjust__models.yml` (for v_stg models)

**Generic Tests to Add:**
```yaml
# Example: v_stg_adjust__installs.sql
models:
  - name: v_stg_adjust__installs
    description: "Unified view of all app installs"
    columns:
      - name: DEVICE_ID
        description: "IDFV (iOS) or GPS_ADID (Android)"
        tests:
          - not_null
          - unique:
              config:
                where: "PLATFORM = 'Android'"  # Android has deterministic IDs
      - name: PLATFORM
        tests:
          - not_null
          - accepted_values:
              values: ['iOS', 'Android']
      - name: INSTALL_TIMESTAMP
        tests:
          - not_null
          - dbt_utils.recency:
              datepart: day
              field: INSTALL_TIMESTAMP
              interval: 7
```

**Integration:** Tests run via `dbt test` command, CI/CD integration

### 7. Singular Tests (NEW - tests/ folder)

**Pattern:** Custom SQL tests for complex business rules

**Files to Create:**
```
/Users/riley/Documents/GitHub/wgt-dbt/tests/
├── staging/
│   ├── test_device_id_format_consistency.sql
│   └── test_ad_partner_mapping_complete.sql
├── intermediate/
│   ├── test_device_mapping_no_orphans.sql
│   ├── test_user_journey_lookback_window.sql
│   └── test_touchpoint_credit_sums_to_one.sql
└── marts/
    └── test_mta_revenue_reconciliation.sql
```

**Example Singular Test:**
```sql
-- tests/intermediate/test_touchpoint_credit_sums_to_one.sql
-- Validates that all attribution model credits sum to 1.0 per install

WITH credit_totals AS (
    SELECT
        DEVICE_ID,
        INSTALL_TIMESTAMP,
        SUM(CREDIT_TIME_DECAY) AS total_time_decay,
        SUM(CREDIT_LINEAR) AS total_linear,
        SUM(CREDIT_POSITION_BASED) AS total_position_based
    FROM {{ ref('int_mta__touchpoint_credit') }}
    GROUP BY DEVICE_ID, INSTALL_TIMESTAMP
)

SELECT *
FROM credit_totals
WHERE
    ABS(total_time_decay - 1.0) > 0.01
    OR ABS(total_linear - 1.0) > 0.01
    OR ABS(total_position_based - 1.0) > 0.01
```

**Integration:** Runs with `dbt test` alongside generic tests

### 8. Unit Tests (NEW - model-level)

**Pattern:** Define test cases with mock input data and expected output
**Requires:** dbt Core 1.8+ (unit tests feature)

**Integration Points:**
```yaml
# In models/staging/adjust/_adjust__models.yml
unit_tests:
  - name: test_android_device_id_uppercase
    model: v_stg_adjust__installs
    given:
      - input: ref('source', 'adjust', 'ANDROID_ACTIVITY_INSTALL')
        rows:
          - GPS_ADID: "abc123-def456"
            INSTALLED_AT: 1704067200
            CREATED_AT: 1704067200
    expect:
      rows:
        - DEVICE_ID: "ABC123-DEF456"
          PLATFORM: "Android"
```

**When to Use:**
- Critical transformations (device ID normalization, credit calculation)
- Edge cases (null handling, date boundary conditions)
- NOT for full pipeline integration (use data tests instead)

### 9. Incremental Model Testing Strategy

**Challenge:** Incremental models (int_mta__user_journey, int_adjust_amplitude__device_mapping) accumulate data over time
**Risk:** Logic bugs compound, late-arriving data causes gaps

**Testing Approach:**

**A. Full Refresh Validation (Periodic)**
```bash
# In CI or scheduled job
dbt run --full-refresh --select int_mta__user_journey
dbt test --select int_mta__user_journey
```

**B. Lookback Window Testing**
```sql
-- tests/intermediate/test_user_journey_no_gaps.sql
-- Validates that all installs in lookback window have journey records

WITH recent_installs AS (
    SELECT DEVICE_ID, INSTALL_TIMESTAMP
    FROM {{ ref('v_stg_adjust__installs') }}
    WHERE INSTALL_TIMESTAMP >= CURRENT_DATE - INTERVAL '10 days'
),

journey_coverage AS (
    SELECT DISTINCT DEVICE_ID, INSTALL_TIMESTAMP
    FROM {{ ref('int_mta__user_journey') }}
    WHERE INSTALL_TIMESTAMP >= CURRENT_DATE - INTERVAL '10 days'
)

SELECT i.DEVICE_ID, i.INSTALL_TIMESTAMP
FROM recent_installs i
LEFT JOIN journey_coverage j
    ON i.DEVICE_ID = j.DEVICE_ID
    AND i.INSTALL_TIMESTAMP = j.INSTALL_TIMESTAMP
WHERE j.DEVICE_ID IS NULL
```

**C. Idempotency Checks**
```yaml
# Run model twice, compare results
# Implemented via CI pipeline or dbt Cloud job
# Use dbt-audit-helper package for comparison
```

**Integration:** Run in CI/CD before merge, scheduled for production monitoring

## Data Flow: Device Mapping Fix

### Before Fix (Current State)

```
Amplitude EVENTS_726530
    ├─ DEVICE_ID (Android: UUID, iOS: UUID)
    └─ USER_ID
         ↓
v_stg_amplitude__merge_ids
    └─ Strip 'R' suffix if Android (INCORRECT ASSUMPTION)
         ↓
int_adjust_amplitude__device_mapping
    └─ ADJUST_DEVICE_ID (low match rate for Android)
         ↓
Revenue Attribution (BROKEN for Android)
```

### After Fix (Target State)

```
Amplitude EVENTS_726530
    ├─ DEVICE_ID (format: TBD via investigation)
    └─ USER_ID
         ↓
v_stg_amplitude__merge_ids
    └─ CORRECT normalization based on verified format
         ↓ [TESTED: not_null, format validation]
int_adjust_amplitude__device_mapping
    └─ ADJUST_DEVICE_ID (high match rate)
         ↓ [TESTED: no orphans, referential integrity]
Revenue Attribution (WORKING)
```

**Critical Path:**
1. Investigate actual Amplitude DEVICE_ID format (Android and iOS)
2. Investigate actual Adjust GPS_ADID format (verify UPPER() in installs model)
3. Update v_stg_amplitude__merge_ids normalization logic
4. Add tests to validate match rate improvement
5. Monitor int_device_mapping__distribution_summary for quality changes

## Data Flow: dbt Testing Integration

### Generic Tests (YAML-based)

```
Model Definition (SQL)
    ↓
Model Config (YAML in same directory)
    ├─ columns: [DEVICE_ID, PLATFORM, ...]
    └─ tests: [not_null, unique, accepted_values]
         ↓
`dbt test` command
    ├─ Generates SQL: SELECT * WHERE DEVICE_ID IS NULL
    └─ Fails if query returns rows
         ↓
CI/CD Pipeline (blocks merge if tests fail)
```

### Singular Tests (SQL-based)

```
Custom Test SQL (tests/ folder)
    └─ SELECT rows that violate business rule
         ↓
`dbt test` command
    └─ Runs query, fails if rows returned
         ↓
CI/CD Pipeline
```

### Test Execution Flow

```
Developer commits code
    ↓
CI Pipeline Triggered
    ├─ dbt deps (install packages)
    ├─ dbt compile (validate Jinja/SQL)
    ├─ dbt run --select state:modified+ (build changed models)
    ├─ dbt test --select state:modified+ (run tests on changed models)
    └─ PASS → Allow merge | FAIL → Block merge
         ↓
Production Deployment
    ├─ dbt run (full pipeline or incremental)
    ├─ dbt test (data quality validation)
    └─ Alert if tests fail (data quality regression)
```

## Architectural Patterns

### Pattern 1: Macro for Duplicate SQL

**What:** Extract repeated CASE statements, date logic, or calculations into reusable macros
**When to use:** Same SQL block appears in 2+ models
**Trade-offs:**
- PRO: DRY principle, single source of truth, easier maintenance
- CON: Reduces SQL readability (Jinja abstraction), harder for non-engineers to debug

**Example:**
```sql
-- macros/map_ad_partner.sql
{% macro map_ad_partner(network_name_column) %}
    CASE
        WHEN {{ network_name_column }} IN ('Facebook Installs', ...) THEN 'Meta'
        WHEN {{ network_name_column }} IN ('Google Ads ACE', ...) THEN 'Google'
        ELSE 'Other'
    END
{% endmacro %}

-- models/staging/adjust/v_stg_adjust__installs.sql
SELECT
    DEVICE_ID,
    NETWORK_NAME,
    {{ map_ad_partner('NETWORK_NAME') }} AS AD_PARTNER  -- Instead of 18-line CASE
FROM source_table
```

**Sources:**
- [Jinja and macros | dbt Developer Hub](https://docs.getdbt.com/docs/build/jinja-macros)
- [dbt macros: What they are and why you should use them | Metaplane](https://www.metaplane.dev/blog/dbt-macros)

### Pattern 2: Co-located Testing (YAML + Models)

**What:** Keep test definitions in same subdirectory as models they test
**When to use:** Always (dbt best practice for organization)
**Trade-offs:**
- PRO: Test discovery, easier navigation, logical grouping
- CON: None (this is standard)

**Example:**
```
models/staging/adjust/
├── _adjust__sources.yml          # Source freshness tests
├── _adjust__models.yml            # Model tests for v_stg_* models
├── v_stg_adjust__installs.sql
└── v_stg_adjust__touchpoints.sql
```

**Sources:**
- [How we structure our dbt projects | dbt Developer Hub](https://docs.getdbt.com/best-practices/how-we-structure/1-guide-overview)
- [Organising a dbt Project: Best Practices - The Data School](https://www.thedataschool.co.uk/curtis-paterson/organising-a-dbt-project-best-practices/)

### Pattern 3: Test Pyramid for Analytics

**What:** Layer tests by scope (unit → generic → singular → integration)
**When to use:** Comprehensive data quality strategy
**Trade-offs:**
- PRO: Catches bugs at appropriate level (fast unit tests, thorough integration tests)
- CON: Overhead of maintaining multiple test types

**Pyramid Structure:**
```
        ┌─────────────────┐
        │  Integration    │  ← Singular tests: end-to-end business rules
        │  Tests (Few)    │     (revenue reconciliation, attribution sums)
        ├─────────────────┤
        │  Data Tests     │  ← Generic tests: column-level constraints
        │  (Many)         │     (not_null, unique, accepted_values)
        ├─────────────────┤
        │  Unit Tests     │  ← Model-level: mock data, expected output
        │  (Moderate)     │     (device ID normalization, credit calculation)
        └─────────────────┘
```

**Recommendation for WGT:**
- **Unit Tests:** 5-10 critical transformations (device mapping, credit attribution)
- **Generic Tests:** 50+ (all primary keys, critical columns)
- **Singular Tests:** 10-15 complex business rules (lookback windows, credit sums)

**Sources:**
- [Unit Test vs an Integration Test for dbt | Datafold](https://www.datafold.com/blog/unit-test-vs-an-integration-test-for-dbt)
- [7 dbt Testing Best Practices | Datafold](https://www.datafold.com/blog/7-dbt-testing-best-practices)

### Pattern 4: Incremental Model Testing Strategy

**What:** Full refresh validation + lookback window tests for incremental models
**When to use:** All incremental models (int_mta__user_journey, device_mapping, touchpoints)
**Trade-offs:**
- PRO: Prevents logic bugs from compounding over time
- CON: Full refresh is expensive (run weekly/monthly, not in CI)

**Testing Approach:**
```sql
-- 1. Generic Test: Recency (data is fresh)
- dbt_utils.recency:
    datepart: day
    field: INSTALL_TIMESTAMP
    interval: 7

-- 2. Singular Test: No gaps in incremental window
SELECT * FROM installs
WHERE INSTALL_TIMESTAMP >= CURRENT_DATE - 10
  AND NOT EXISTS (SELECT 1 FROM journey WHERE ...)

-- 3. CI Test: Run with --full-refresh on feature branch
dbt run --full-refresh --select int_mta__user_journey

-- 4. Production Monitor: Compare incremental vs full refresh (monthly)
```

**Sources:**
- [Testing incremental models - dbt Community Forum](https://discourse.getdbt.com/t/testing-incremental-models/1528)
- [dbt Incremental part 2: Implementing & Testing – Joon](https://joonsolutions.com/dbt-incremental-implementing-testing/)

## Integration Points

### External Data Sources

| Source | Integration Pattern | Notes |
|--------|---------------------|-------|
| Adjust S3 Data | dbt source() → Snowflake external table | Activity tables (install, click, impression) partitioned by platform |
| Amplitude Events | dbt source() → Snowflake table | Events table (726530) with DEVICE_ID, USER_ID |
| Network Mapping CSV | dbt seed → Snowflake table | Static partner name mappings, version controlled |
| Adjust API Data | dbt source() → Snowflake table | Aggregated daily reports (not used in MTA, used for spend) |

### Internal Model Dependencies

| Upstream | Downstream | Communication | Data Contract |
|----------|------------|---------------|---------------|
| v_stg_adjust__installs | int_mta__user_journey | ref() in SQL | DEVICE_ID (not_null), PLATFORM (iOS/Android), INSTALL_TIMESTAMP |
| v_stg_adjust__touchpoints | int_mta__user_journey | ref() in SQL | DEVICE_ID or IDFA (iOS), TOUCHPOINT_TIMESTAMP within 7-day window |
| v_stg_amplitude__merge_ids | int_adjust_amplitude__device_mapping | ref() in SQL | DEVICE_ID_UUID (normalized), AMPLITUDE_USER_ID (not_null) |
| int_mta__user_journey | int_mta__touchpoint_credit | ref() in SQL | JOURNEY_ROW_KEY (unique), TOUCHPOINT_POSITION, BASE_TYPE_WEIGHT |
| int_mta__touchpoint_credit | mart_network_performance_mta | ref() in SQL | CREDIT_TIME_DECAY (sums to 1.0 per install) |

**Data Contract Validation:**
- All contracts enforced via generic tests (not_null, unique, accepted_values)
- Breaking changes to upstream models caught in CI via `dbt test --select state:modified+`

### Schema Routing (generate_schema_name macro)

| Model Schema Config | Dev Environment | Prod Environment | Purpose |
|---------------------|-----------------|------------------|---------|
| `schema: 'S3_DATA'` | DEV_S3_DATA | S3_DATA | Adjust activity models (raw source references) |
| No schema config | DBT_WGTDATA | PROD | All staging, intermediate, marts |

**Integration:** Automatic schema routing based on target.name in profiles.yml

## Build Order (Dependency Graph)

### Phase 1: Macro Refactoring (No Dependencies)

**Build Order:**
1. Create `/Users/riley/Documents/GitHub/wgt-dbt/macros/map_ad_partner.sql`
2. Modify `v_stg_adjust__installs.sql` (replace CASE with macro call)
3. Modify `v_stg_adjust__touchpoints.sql` (replace CASE with macro call)
4. Test: `dbt run --select v_stg_adjust__installs v_stg_adjust__touchpoints`
5. Validate: AD_PARTNER values unchanged (compare before/after)

**Critical Path:** Macro must be created BEFORE models are modified

### Phase 2: Device Mapping Investigation (Dependency: None)

**Build Order:**
1. Query Amplitude EVENTS_726530 table → examine DEVICE_ID format for Android
2. Query Adjust ANDROID_ACTIVITY_INSTALL → examine GPS_ADID format
3. Document findings in `v_stg_amplitude__merge_ids.sql` header comments
4. Design normalization logic based on verified formats
5. Update `v_stg_amplitude__merge_ids.sql` DEVICE_ID_UUID calculation
6. Test: `dbt run --select v_stg_amplitude__merge_ids int_adjust_amplitude__device_mapping`
7. Validate: Check `int_device_mapping__distribution_summary` for match rate improvement

**Critical Path:** Investigation BEFORE code changes

### Phase 3: Generic Testing (Dependency: Models exist)

**Build Order:**
1. Create `/Users/riley/Documents/GitHub/wgt-dbt/models/staging/adjust/_adjust__models.yml`
2. Add tests for v_stg_adjust__installs (not_null, unique on Android DEVICE_ID)
3. Add tests for v_stg_adjust__touchpoints (not_null on identifiers)
4. Add tests to existing `models/staging/amplitude/_amplitude__sources.yml`
5. Add tests to existing `models/intermediate/_int_mta__models.yml`
6. Test: `dbt test --select v_stg_adjust__installs v_stg_adjust__touchpoints`

**Critical Path:** Models must run successfully BEFORE tests added

### Phase 4: Singular Testing (Dependency: Generic tests passing)

**Build Order:**
1. Create `/Users/riley/Documents/GitHub/wgt-dbt/tests/staging/test_device_id_format_consistency.sql`
2. Create `/Users/riley/Documents/GitHub/wgt-dbt/tests/intermediate/test_touchpoint_credit_sums_to_one.sql`
3. Create `/Users/riley/Documents/GitHub/wgt-dbt/tests/intermediate/test_user_journey_lookback_window.sql`
4. Test: `dbt test --select test_type:singular`

**Critical Path:** Generic tests validate data shape, singular tests validate business rules

### Phase 5: CI/CD Integration (Dependency: All tests written)

**Build Order:**
1. Add `dbt test` to CI pipeline (after `dbt run`)
2. Configure to run on pull requests
3. Block merge if tests fail
4. Add production monitoring for test failures

**Critical Path:** Tests must be comprehensive BEFORE enforcing in CI

## Recommended Project Structure (After Changes)

```
/Users/riley/Documents/GitHub/wgt-dbt/
├── models/
│   ├── staging/
│   │   ├── adjust/
│   │   │   ├── _adjust__sources.yml          (source freshness tests)
│   │   │   ├── _adjust__models.yml           (NEW: generic tests for v_stg models)
│   │   │   ├── v_stg_adjust__installs.sql    (MODIFIED: use map_ad_partner macro)
│   │   │   └── v_stg_adjust__touchpoints.sql (MODIFIED: use map_ad_partner macro)
│   │   ├── amplitude/
│   │   │   ├── _amplitude__sources.yml       (add tests for DEVICE_ID)
│   │   │   └── v_stg_amplitude__merge_ids.sql(MODIFIED: fix Android normalization)
│   ├── intermediate/
│   │   ├── _int_mta__models.yml              (add tests for journey, credit)
│   │   ├── int_adjust_amplitude__device_mapping.sql (validate, possibly modify)
│   │   ├── int_device_mapping__diagnostics.sql (no changes)
│   │   ├── int_mta__user_journey.sql         (no changes)
│   │   └── int_mta__touchpoint_credit.sql    (no changes)
│   ├── marts/
│   │   └── attribution/
│   │       ├── _mta__models.yml              (add tests for marts)
│   │       └── mart_network_performance_mta.sql (no changes)
├── macros/
│   ├── generate_schema_name.sql              (no changes)
│   └── map_ad_partner.sql                    (NEW: centralized partner mapping)
├── tests/                                     (NEW: singular tests folder)
│   ├── staging/
│   │   ├── test_device_id_format_consistency.sql
│   │   └── test_ad_partner_mapping_complete.sql
│   ├── intermediate/
│   │   ├── test_device_mapping_no_orphans.sql
│   │   ├── test_user_journey_lookback_window.sql
│   │   └── test_touchpoint_credit_sums_to_one.sql
├── seeds/
│   └── network_mapping.csv                   (no changes)
├── dbt_project.yml                           (possibly add test-paths config)
└── .github/workflows/                        (NEW: CI/CD integration)
    └── ci.yml                                 (run dbt test in CI)
```

### Structure Rationale

- **macros/**: Reusable SQL logic extracted from models (DRY principle)
- **tests/**: Organized by layer (staging, intermediate, marts) matching model structure
- **YAML files**: Co-located with models in same directory for discoverability
- **Diagnostic models**: Remain in intermediate/ layer (they ARE intermediate models, just for monitoring)

## Anti-Patterns to Avoid

### Anti-Pattern 1: Testing in Production Only

**What people do:** Only run `dbt test` in production after deployment
**Why it's wrong:** Data quality regressions reach users before being caught
**Do this instead:** Run `dbt test` in CI/CD pipeline, block merge if tests fail

**Prevention:**
```yaml
# .github/workflows/ci.yml
- name: Run dbt tests
  run: dbt test --select state:modified+
  # Fails CI if tests fail → blocks merge
```

### Anti-Pattern 2: Overusing Macros

**What people do:** Extract every repeated SQL pattern into macros for "DRY"
**Why it's wrong:** Reduces readability, creates abstraction layers that confuse non-engineers
**Do this instead:** Only extract to macro if repeated 2+ times AND logic is complex

**Example of Overuse:**
```sql
-- DON'T: This is too simple to abstract
{% macro upper_device_id(col) %}
    UPPER({{ col }})
{% endmacro %}

-- DO: Just write UPPER() inline
SELECT UPPER(DEVICE_ID) AS DEVICE_ID
```

**Sources:**
- [Jinja and macros | dbt Developer Hub](https://docs.getdbt.com/docs/build/jinja-macros)

### Anti-Pattern 3: Testing Everything with Generic Tests

**What people do:** Only use not_null, unique, accepted_values for all validation
**Why it's wrong:** Business rules (credit sums to 1.0, lookback windows) can't be expressed as column-level constraints
**Do this instead:** Use test pyramid (generic for columns, singular for business rules, unit for transformations)

**Example:**
```yaml
# DON'T: Can't validate "credits sum to 1.0" with generic test
columns:
  - name: CREDIT_TIME_DECAY
    tests:
      - not_null  # This only checks nulls, not summation logic

# DO: Write singular test
-- tests/intermediate/test_touchpoint_credit_sums_to_one.sql
SELECT DEVICE_ID
FROM {{ ref('int_mta__touchpoint_credit') }}
GROUP BY DEVICE_ID, INSTALL_TIMESTAMP
HAVING ABS(SUM(CREDIT_TIME_DECAY) - 1.0) > 0.01
```

**Sources:**
- [dbt Tests Explained: Generic vs Singular | Medium](https://medium.com/@likkilaxminarayana/dbt-tests-explained-generic-vs-singular-with-real-examples-6c08d8dd78a7)

### Anti-Pattern 4: Seeds for Dynamic Data

**What people do:** Use seeds for data that changes frequently (daily partner mappings, config that updates weekly)
**Why it's wrong:** Seeds require manual CSV updates and `dbt seed` runs, breaks automation
**Do this instead:** Seeds for static reference data only (network_mapping.csv is appropriate because partner names rarely change)

**Current Use Case (CORRECT):**
```csv
# seeds/network_mapping.csv
# Changes: ~2-3 times/year when new partner added
adjust_network_name,supermetrics_partner_id,ad_partner
Facebook Installs,34,Meta
AppLovin_iOS_2019,7,AppLovin
```

**Anti-Pattern Example:**
```csv
# seeds/daily_exchange_rates.csv ← WRONG, changes daily
date,currency,rate
2026-02-10,EUR,0.85
# This should be ETL pipeline or external table, not seed
```

**Sources:**
- [Working with dbt Seeds: Critical Best Practices | Dagster](https://dagster.io/guides/working-with-dbt-seeds-quick-tutorial-critical-best-practices)
- [Can I use seeds to load raw data? | dbt Developer Hub](https://docs.getdbt.com/faqs/Seeds/load-raw-data-with-seed)

### Anti-Pattern 5: Ignoring Incremental Model Testing

**What people do:** Write incremental model, never test with --full-refresh
**Why it's wrong:** Logic bugs compound over time, late-arriving data creates gaps
**Do this instead:** Periodic full refresh validation, lookback window tests

**Prevention:**
```bash
# Weekly job: Full refresh validation
dbt run --full-refresh --select int_mta__user_journey
# Compare row counts, aggregates to incremental version
# Alert if discrepancies > threshold
```

**Sources:**
- [Testing incremental models - dbt Community Forum](https://discourse.getdbt.com/t/testing-incremental-models/1528)

## Sources

**dbt Testing:**
- [dbt Data Quality Checks: Types, Benefits & Best Practices | lakefs.io](https://lakefs.io/blog/dbt-data-quality-checks/)
- [7 dbt Testing Best Practices | Datafold](https://www.datafold.com/blog/7-dbt-testing-best-practices)
- [A Comprehensive Guide to dbt Tests to Ensure Data Quality | DataCamp](https://www.datacamp.com/tutorial/dbt-tests)
- [Add data tests to your DAG | dbt Developer Hub](https://docs.getdbt.com/docs/build/data-tests)
- [dbt Tests Explained: Generic vs Singular | Medium](https://medium.com/@likkilaxminarayana/dbt-tests-explained-generic-vs-singular-with-real-examples-6c08d8dd78a7)
- [Unit Test vs an Integration Test for dbt | Datafold](https://www.datafold.com/blog/unit-test-vs-an-integration-test-for-dbt)
- [Unit tests | dbt Developer Hub](https://docs.getdbt.com/docs/build/unit-tests)

**dbt Project Structure:**
- [Organising a dbt Project: Best Practices - The Data School](https://www.thedataschool.co.uk/curtis-paterson/organising-a-dbt-project-best-practices/)
- [How we structure our dbt projects | dbt Developer Hub](https://docs.getdbt.com/best-practices/how-we-structure/1-guide-overview)
- [6. dbt Project Structure Explained | Medium](https://medium.com/@likkilaxminarayana/6-dbt-project-structure-explained-a-practical-guide-for-analytics-engineers-5894f6230756)
- [test-paths | dbt Developer Hub](https://docs.getdbt.com/reference/project-configs/test-paths)

**dbt Macros:**
- [Jinja and macros | dbt Developer Hub](https://docs.getdbt.com/docs/build/jinja-macros)
- [dbt macros: What they are and why you should use them | Metaplane](https://www.metaplane.dev/blog/dbt-macros)
- [How To Write Reusable SQL With dbt Macros And Jinja | Hevo](https://hevodata.com/data-transformation/dbt-macros/)

**dbt Seeds:**
- [Working with dbt Seeds: Quick Tutorial & Critical Best Practices | Dagster](https://dagster.io/guides/working-with-dbt-seeds-quick-tutorial-critical-best-practices)
- [dbt Seeds: What are they and how to use them | Datafold](https://www.datafold.com/blog/dbt-seeds)
- [Can I use seeds to load raw data? | dbt Developer Hub](https://docs.getdbt.com/faqs/Seeds/load-raw-data-with-seed)
- [Seeds in dbt: When and How I Actually Use Them | Medium](https://medium.com/@likkilaxminarayana/seeds-in-dbt-when-and-how-i-actually-use-them-in-real-projects-f38217b88edf)

**Incremental Model Testing:**
- [Testing incremental models - dbt Community Forum](https://discourse.getdbt.com/t/testing-incremental-models/1528)
- [dbt Incremental part 2: Implementing & Testing – Joon](https://joonsolutions.com/dbt-incremental-implementing-testing/)
- [I Tested dbt's Incremental Strategies on 1M Rows | Medium](https://medium.com/@reliabledataengineering/i-tested-dbts-incremental-strategies-on-1m-rows-here-s-what-actually-happened-1628cf03931f)

---
*Architecture research for: WGT dbt Analytics Pipeline - Device Mapping & Testing Integration*
*Researched: 2026-02-10*
