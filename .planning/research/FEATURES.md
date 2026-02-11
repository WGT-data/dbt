# Feature Landscape: dbt Pipeline Hardening & Testing

**Domain:** dbt project pipeline hardening (source freshness, singular tests, macro extraction)
**Project context:** MMM analytics pipeline on Snowflake via dbt Cloud
**Researched:** 2026-02-11

---

## Table Stakes

Features users expect in a production-grade dbt project. Missing = pipeline feels incomplete or unreliable.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Source freshness with loaded_at_field** | Standard dbt observability pattern for detecting stale upstream data | Low | `loaded_at_field` + `warn_after`/`error_after` are core dbt features |
| **Singular tests for business logic** | Generic tests (unique, not_null) cover only data shape; business rules need custom SQL | Low-Medium | Simple SQL queries returning failing records |
| **Macros for repeated CASE logic** | DRY principle — duplicated logic across models causes drift and maintenance burden | Low | Standard Jinja macro with parameters |
| **Incremental model validation** | Must verify incremental models work on first run AND subsequent runs before production | Low | Run `dbt run` (initial) then again (incremental) in dbt Cloud |
| **Date spine completeness for time series** | MMM regression requires gap-free daily data; missing dates break statistical models | Medium | Singular test joining date spine to actual data |
| **Cross-layer consistency tests** | Aggregated marts must reconcile to source layer; discrepancies indicate pipeline bugs | Medium | Singular test comparing SUMs across staging → intermediate → mart |
| **Zero-fill vs missing data flags** | COALESCEd zeros look identical to real zeros; data consumers need to distinguish them | Low | Boolean flags (HAS_*_DATA) already in mart model |
| **Static table staleness detection** | Seed/static tables can go stale silently; production pipelines need alerting | Low-Medium | Freshness check with 30-day threshold on mapping table |

---

## Differentiators

Features that set this pipeline apart. Not expected by default, but add significant value.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Hierarchical freshness config** | Define freshness at source level (all tables inherit), override at table level for exceptions | Low | Official dbt best practice, reduces YAML duplication |
| **Timezone-normalized loaded_at_field** | Multi-region data sources with local timestamps need UTC conversion for accurate freshness | Low | Use expressions like `convert_timezone('UTC', timestamp_col)::timestamp` |
| **Filter parameter for freshness queries** | Large tables benefit from WHERE clause in freshness check (e.g., partitioned tables) | Low | Reduces scan cost on billion-row tables |
| **Scheduled freshness as separate job** | Run freshness checks every 2 hours, model builds every 12 hours — different cadences | Low | dbt Cloud scheduled job feature |
| **Macro with consistency test** | Extract logic into macro AND validate it produces identical output to original CASE statement | Medium | Prevents regression when refactoring |
| **Network mapping seed coverage test** | Singular test ensures every NETWORK_NAME in source data has a mapping (no unmapped channels) | Medium | Critical for MMM — unmapped channels = lost spend visibility |
| **Data quality flags in marts** | Expose HAS_SPEND_DATA, HAS_INSTALL_DATA flags so analysts can filter or alert on missing data | Low | Already implemented in mmm__daily_channel_summary.sql |
| **Date spine with hardcoded start_date** | Avoid CROSS JOIN performance issues by using known data start boundary | Low | Already implemented with '2024-01-01' start |

---

## Anti-Features

Features to explicitly NOT build. Common mistakes in this domain.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Freshness on every source table** | Creates alert fatigue; focus on critical upstream tables only | Configure freshness for raw sources (Adjust, Amplitude) not intermediate models |
| **Over-abstracted macros** | "Remember that using Jinja can make your models harder for other users to interpret" (dbt docs) | Only extract macros when logic is duplicated 2+ times; favor readability over DRY-ness |
| **Generic tests for complex business rules** | "By that point, the test isn't so singular!" — trying to parameterize one-off logic creates complexity | Use singular tests (simple SQL files) for MMM-specific validations |
| **Testing every column** | "Creates test bloat; only test natural/surrogate keys" (REQUIREMENTS.md) | TEST-01/02 already cover primary keys; don't add uniqueness tests on descriptive columns |
| **Real-time freshness alerting** | Adds infrastructure complexity for marginal benefit; analytics SLAs are hourly/daily not seconds | Use warn_after/error_after with realistic thresholds (12-24 hours) |
| **Date field as loaded_at_field** | Date fields lack time precision; freshness checks become unreliable (everything on same day looks fresh) | Cast to timestamp: `date_field::timestamp` or use true timestamp column |
| **--full-refresh in production** | "This will treat incremental models as table models" — wipes and rebuilds everything, loses incremental value | Only use full-refresh in development or intentional backfill scenarios |
| **Singular tests without descriptive names** | File named `test_1.sql` gives no clue what it validates | Name files descriptively: `mmm_date_spine_completeness.sql`, `mmm_cross_layer_totals_match.sql` |

---

## Feature Dependencies

```
Source Freshness
└── loaded_at_field selection (must identify correct timestamp column)
    └── Timezone handling (if multi-region sources)
        └── Scheduled job setup (freshness check cadence)

Singular Tests
└── Business rule identification (what to validate)
    └── SQL query writing (returns failing records)
        └── Test naming convention (descriptive file names)

Macro Extraction
└── Identify duplicated logic (AD_PARTNER CASE in 2 models)
    └── Create parameterized macro (network_name → ad_partner)
        └── Consistency test (macro output = original CASE output)
            └── Replace original logic with macro calls

Pipeline Validation
└── Compile all models (syntax check)
    └── Run non-incremental models (tables, views)
        └── Run incremental models (first run = full build)
            └── Run incremental models again (subsequent = incremental append)
                └── Validate data quality (no errors, expected row counts)
```

---

## MMM-Specific Features

These features are specific to the MMM use case in this project.

### TEST-06: Date Spine Completeness

**What:** Singular test validates every expected date+channel+platform combination exists in mart
**Why critical:** Gaps in time series break MMM regression — model interprets missing rows as zero spend
**Implementation pattern:**
```sql
-- tests/mmm_date_spine_completeness.sql
-- Returns rows where date spine grid has gaps (failing records)
WITH expected_grid AS (
    -- Generate expected date+channel+platform combinations
    SELECT date_day::DATE AS date, platform, channel
    FROM {{ dbt_utils.date_spine(...) }}
    CROSS JOIN (SELECT DISTINCT platform, channel FROM {{ ref('int_mmm__daily_channel_spend') }})
),
actual_data AS (
    SELECT date, platform, channel
    FROM {{ ref('mmm__daily_channel_summary') }}
)
SELECT e.*
FROM expected_grid e
LEFT JOIN actual_data a USING (date, platform, channel)
WHERE a.date IS NULL  -- Missing combinations
```

### TEST-07: Cross-Layer Consistency

**What:** Validate SUM(spend) from intermediate models = SUM(spend) in daily summary mart
**Why critical:** Aggregation bugs cause incorrect ROAS calculations; must reconcile layers
**Implementation pattern:**
```sql
-- tests/mmm_cross_layer_totals_match.sql
WITH intermediate_totals AS (
    SELECT SUM(spend) AS total_spend FROM {{ ref('int_mmm__daily_channel_spend') }}
),
mart_totals AS (
    SELECT SUM(spend) AS total_spend FROM {{ ref('mmm__daily_channel_summary') }}
)
SELECT * FROM intermediate_totals i
CROSS JOIN mart_totals m
WHERE ABS(i.total_spend - m.total_spend) > 0.01  -- Allow penny rounding
```

### TEST-08: Zero-Fill Integrity

**What:** Validate HAS_SPEND_DATA=1 when SPEND>0, HAS_SPEND_DATA=0 when SPEND=0 and no source row
**Why critical:** Distinguishes "channel spent $0" from "channel has no data" — different meanings for analysts
**Implementation pattern:**
```sql
-- tests/mmm_zero_fill_integrity.sql
SELECT date, platform, channel, spend, has_spend_data
FROM {{ ref('mmm__daily_channel_summary') }}
WHERE (spend > 0 AND has_spend_data = 0)  -- Real data flagged as missing
   OR (spend = 0 AND has_spend_data = 1)  -- Zero-fill flagged as real data
```

---

## dbt Cloud Validation Workflow

Expected behavior when validating MMM pipeline in dbt Cloud:

### 1. Compile Check
**Command:** `dbt compile --select +mmm__daily_channel_summary`
**Expected:** All models compile without syntax errors
**Detects:** Jinja errors, SQL syntax issues, missing refs

### 2. Initial Run (Table Materialization)
**Command:** `dbt run --select +mmm__daily_channel_summary`
**Expected:** All models build as tables/views for first time
**Detects:** Runtime SQL errors, missing source tables

### 3. Incremental Run (Incremental Materialization)
**Command:** `dbt run --select int_mmm__daily_channel_spend int_mmm__daily_channel_installs int_mmm__daily_channel_revenue`
**Expected:** `is_incremental()` returns TRUE, only new rows processed
**Detects:** Incremental logic bugs, unique_key conflicts

### 4. Full Refresh
**Command:** `dbt run --full-refresh --select int_mmm__daily_channel_spend`
**Expected:** Table dropped and rebuilt from scratch
**When to use:** Schema changes, incremental logic updates, backfill scenarios

---

## Source Freshness Configuration Patterns

### Pattern 1: Hierarchical Source-Level Config (Recommended)

```yaml
# models/staging/adjust/_adjust__sources.yml
sources:
  - name: adjust
    freshness:
      warn_after: {count: 24, period: hour}
      error_after: {count: 48, period: hour}
    loaded_at_field: "TO_TIMESTAMP(CREATED_AT)"  # Epoch to timestamp conversion
    tables:
      - name: IOS_ACTIVITY_INSTALL
      - name: ANDROID_ACTIVITY_INSTALL
      # All tables inherit source-level freshness config
```

**Pros:** DRY, consistent SLAs across all source tables
**Cons:** All tables must have same loaded_at_field column

### Pattern 2: Table-Level Override

```yaml
sources:
  - name: adjust
    tables:
      - name: IOS_ACTIVITY_INSTALL
        freshness:
          warn_after: {count: 12, period: hour}
          error_after: {count: 24, period: hour}
        loaded_at_field: "TO_TIMESTAMP(CREATED_AT)"
```

**Pros:** Per-table SLA customization
**Cons:** More YAML, must configure each table individually

### Pattern 3: Static Table Staleness (FRESH-03)

```yaml
sources:
  - name: adjust
    tables:
      - name: ADJUST_AMPLITUDE_DEVICE_MAPPING
        freshness:
          warn_after: {count: 30, period: day}
          error_after: {count: 60, period: day}
        loaded_at_field: "LAST_UPDATED_AT"  # Static table refresh timestamp
```

**Use case:** Seed-like tables that refresh monthly, not daily
**Threshold:** 30 days matches requirement FRESH-03

### Pattern 4: Expression-Based loaded_at_field

```yaml
# For Amplitude with UTC conversion
loaded_at_field: "CONVERT_TIMEZONE('UTC', EVENT_TIME)::TIMESTAMP"

# For date fields requiring timestamp cast
loaded_at_field: "REPORT_DATE::TIMESTAMP"
```

**When needed:** Timezone normalization, data type conversion
**Caution:** Complex expressions may be slow on large tables; use `filter` parameter

---

## Macro Extraction Best Practices

### Current State: Duplicated CASE Logic

**Files with duplication:**
- `models/staging/adjust/v_stg_adjust__installs.sql` (lines 65-83)
- `models/staging/adjust/v_stg_adjust__touchpoints.sql` (lines 140-158)

**Duplication risk:** Network mapping changes require updating both files; drift causes inconsistent AD_PARTNER values

### Recommended Pattern: Parameterized Macro

```sql
-- macros/get_ad_partner.sql
{% macro get_ad_partner(network_name_column) %}
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
SELECT
    NETWORK_NAME,
    {{ get_ad_partner('NETWORK_NAME') }} AS AD_PARTNER,
    ...
FROM ...
```

### Consistency Test (CODE-02)

```sql
-- tests/ad_partner_macro_consistency.sql
-- Validates macro produces identical output to original CASE statement
WITH macro_output AS (
    SELECT DEVICE_ID, {{ get_ad_partner('NETWORK_NAME') }} AS AD_PARTNER
    FROM {{ ref('v_stg_adjust__installs') }}
),
original_output AS (
    SELECT DEVICE_ID, AD_PARTNER
    FROM {{ ref('v_stg_adjust__installs') }}
)
SELECT m.device_id, m.ad_partner AS macro_value, o.ad_partner AS original_value
FROM macro_output m
FULL OUTER JOIN original_output o USING (device_id)
WHERE m.ad_partner != o.ad_partner  -- Any mismatches = test fails
   OR m.device_id IS NULL           -- Rows missing from macro
   OR o.device_id IS NULL           -- Rows missing from original
```

**When to run:** Immediately after macro extraction, before removing original CASE

---

## Confidence Assessment

| Topic | Level | Source | Notes |
|-------|-------|--------|-------|
| Source freshness config | HIGH | [dbt official docs](https://docs.getdbt.com/reference/resource-properties/freshness) | loaded_at_field, warn_after, error_after well-documented |
| Singular tests | HIGH | [dbt official docs](https://docs.getdbt.com/docs/build/data-tests) | Core dbt feature with clear examples |
| Macro best practices | HIGH | [dbt official docs](https://docs.getdbt.com/docs/build/jinja-macros) | Official guidance: favor readability over DRY-ness |
| Incremental model behavior | HIGH | [dbt official docs](https://docs.getdbt.com/docs/build/incremental-models) | is_incremental() behavior well-specified |
| Date spine patterns | MEDIUM | [dbt-utils package](https://github.com/dbt-labs/dbt-utils), web search | Community pattern, not official dbt feature |
| Zero-fill integrity testing | MEDIUM | Project-specific (mmm__daily_channel_summary.sql) | HAS_*_DATA pattern is custom to this project |
| Network mapping coverage test | MEDIUM | Project-specific requirement (MMM-03) | Custom singular test, not standard dbt pattern |
| dbt Cloud validation workflow | HIGH | [dbt official docs](https://docs.getdbt.com/reference/commands/run), [Stellans](https://stellans.io/dbt-run-vs-dbt-build-when-to-use-each-command/) | compile → run → incremental run → full-refresh is standard workflow |

---

## Implementation Complexity by Feature

| Feature | Complexity | Effort | Blockers |
|---------|-----------|--------|----------|
| FRESH-01: Adjust source freshness | Low | 15 min | Need to identify correct loaded_at_field (CREATED_AT epoch) |
| FRESH-02: Amplitude source freshness | Low | 10 min | EVENT_TIME already timestamp, no conversion needed |
| FRESH-03: Static table staleness | Low | 10 min | ADJUST_AMPLITUDE_DEVICE_MAPPING has LAST_UPDATED_AT column? Verify |
| FRESH-04: Scheduled freshness job | Low | 5 min | dbt Cloud UI config, separate from model runs |
| TEST-06: Date spine completeness | Medium | 30 min | Must understand date_spine macro, CROSS JOIN logic |
| TEST-07: Cross-layer consistency | Medium | 20 min | Straightforward SUM comparison, allow rounding tolerance |
| TEST-08: Zero-fill integrity | Low | 15 min | HAS_*_DATA flags already exist, just validate logic |
| CODE-01: Extract AD_PARTNER macro | Low | 20 min | Copy CASE to macro file, parameterize column name |
| CODE-02: Macro consistency test | Medium | 25 min | FULL OUTER JOIN to detect any discrepancies |
| CODE-04: Verify identical output | Low | 5 min | Run CODE-02 test, expect 0 rows returned |
| MMM-01: Compile + run in dbt Cloud | Low | 10 min | Already built locally, should compile cleanly |
| MMM-02: Incremental behavior validation | Low | 15 min | Run twice, check row counts increase incrementally |
| MMM-03: Network mapping coverage | Medium | 30 min | Join source NETWORK_NAME to seed, find unmapped |
| MMM-04: KPI validation (no division by zero) | Low | 10 min | Check CPI/ROAS logic, already has CASE WHEN guards |

**Total estimated effort:** 3.5-4 hours across all features

---

## MVP Recommendation

For remaining v1.0 work, prioritize in this order:

### Phase 4: DRY Refactor (CODE-01, CODE-02, CODE-04)
**Why first:** Prevents drift before adding more tests; macro becomes available for future models
1. Extract AD_PARTNER macro
2. Create consistency test (CODE-02)
3. Replace CASE in both models with macro call
4. Run consistency test (CODE-04)
5. Remove original CASE statements

**Dependencies:** None
**Risk:** Low (consistency test validates correctness)

### Phase 5: MMM Pipeline Validation (MMM-01 through MMM-04)
**Why second:** Validate foundation before adding observability
1. Compile all MMM models in dbt Cloud
2. Run full model build (tables + incremental first run)
3. Run incremental models again (validate incremental behavior)
4. Validate network mapping coverage (MMM-03)
5. Check KPI calculations (MMM-04)

**Dependencies:** Phase 4 complete (clean codebase)
**Risk:** Medium (may discover incremental bugs, network mapping gaps)

### Phase 6: Expand Test Coverage (TEST-06, TEST-07, TEST-08)
**Why third:** Pipeline must be stable before adding data quality assertions
1. Date spine completeness test (TEST-06)
2. Cross-layer consistency test (TEST-07)
3. Zero-fill integrity test (TEST-08)

**Dependencies:** Phase 5 complete (pipeline validated)
**Risk:** Low (singular tests are straightforward SQL)

### Phase 7: Source Freshness (FRESH-01 through FRESH-04)
**Why last:** Observability added after pipeline is hardened
1. Configure Adjust source freshness (FRESH-01)
2. Configure Amplitude source freshness (FRESH-02)
3. Configure static table staleness check (FRESH-03)
4. Create scheduled freshness job (FRESH-04)

**Dependencies:** Phase 6 complete (data quality validated)
**Risk:** Low (standard dbt feature)

---

## Sources

### Official dbt Documentation (HIGH confidence)
- [freshness | dbt Developer Hub](https://docs.getdbt.com/reference/resource-properties/freshness)
- [Add data tests to your DAG | dbt Developer Hub](https://docs.getdbt.com/docs/build/data-tests)
- [Jinja and macros | dbt Developer Hub](https://docs.getdbt.com/docs/build/jinja-macros)
- [Configure incremental models | dbt Developer Hub](https://docs.getdbt.com/docs/build/incremental-models)
- [Source freshness | dbt Developer Hub](https://docs.getdbt.com/docs/deploy/source-freshness)

### Community Resources (MEDIUM confidence)
- [dbt run vs build - Stellans](https://stellans.io/dbt-run-vs-dbt-build-when-to-use-each-command/)
- [7 dbt Macros That Actually Made Our Platform Maintainable | Medium](https://medium.com/tech-with-abhishek/7-dbt-macros-that-actually-made-our-platform-maintainable-02d3e7756860)
- [dbt Tests Explained: Generic vs Singular (With Real Examples) | Medium](https://medium.com/@likkilaxminarayana/dbt-tests-explained-generic-vs-singular-with-real-examples-6c08d8dd78a7)
- [How to use dbt source freshness tests to detect stale data | Datafold](https://www.datafold.com/blog/dbt-source-freshness)
- [expect_row_values_to_have_data_for_every_n_datepart | Elementary](https://www.elementary-data.com/dbt-tests/expect-row-values-to-have-data-for-every-n-datepart)

### Project-Specific Context
- WGT dbt project REQUIREMENTS.md (TEST-06/07/08, FRESH-01/02/03, CODE-01/02)
- mmm__daily_channel_summary.sql (HAS_*_DATA flag pattern)
- v_stg_adjust__installs.sql and v_stg_adjust__touchpoints.sql (AD_PARTNER duplication)

---

*Research complete for features dimension of v1.0 pipeline hardening work*
