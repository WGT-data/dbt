# Phase 1: Test Foundation - Research

**Researched:** 2026-02-10
**Domain:** dbt data quality testing
**Confidence:** HIGH

## Summary

This phase establishes baseline data quality tests for a dbt project using Snowflake before making any device ID normalization changes. The goal is to catch regressions from upcoming code changes by implementing tests on primary keys, composite keys, foreign key relationships, and constrained values.

dbt ships with four built-in generic tests (unique, not_null, accepted_values, relationships) that cover the core requirements (TEST-01 through TEST-04). The critical challenge is TEST-05: avoiding historical false positive floods by using forward-looking filters that test only new data. dbt's `where` config enables date-based test filtering, which is essential for incremental models and large historical datasets.

The standard approach is to define tests in `.yml` schema files alongside models, organized by layer (staging, intermediate, marts). For composite key testing, dbt-utils package provides `unique_combination_of_columns` which is more performant than concatenation for large datasets.

**Primary recommendation:** Start with generic tests in schema.yml files for all primary/composite keys and referential integrity, use `where` config to filter tests to recent data (last 30-60 days), and add dbt-utils package for composite key testing.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dbt-core | 1.8+ | Data transformation & testing framework | Industry standard for analytics engineering |
| dbt-snowflake | 1.8+ | Snowflake adapter for dbt | Required for Snowflake warehouse |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| dbt-utils | 1.1.1+ | Utility macros including composite key tests | Testing uniqueness across multiple columns (TEST-02) |
| dbt-expectations | Optional | Advanced validation tests (regex, distributions) | Deferred to v2 (ADV-01) per requirements |
| Elementary | Optional | Anomaly detection on models | Deferred to v2 (ADV-02) per requirements |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dbt-utils.unique_combination_of_columns | Concatenation with `column_name: "(col1 \|\| col2)"` | Concatenation simpler but less performant on large datasets |
| Generic tests | Singular tests in tests/ folder | Singular tests less reusable, harder to maintain at scale |

**Installation:**
```bash
# Create packages.yml in project root
cat > packages.yml << 'EOF'
packages:
  - package: dbt-labs/dbt_utils
    version: 1.1.1
EOF

# Install packages
dbt deps
```

## Architecture Patterns

### Recommended Project Structure
```
models/
├── staging/
│   ├── adjust/
│   │   ├── _adjust__sources.yml      # Source definitions
│   │   ├── _adjust__models.yml       # Model docs + tests
│   │   └── *.sql
│   └── amplitude/
│       ├── _amplitude__sources.yml
│       ├── _amplitude__models.yml
│       └── *.sql
├── intermediate/
│   ├── _int_mta__models.yml          # Composite key tests here
│   └── *.sql
└── marts/
    ├── attribution/
    │   ├── _mta__models.yml
    │   └── *.sql
tests/
└── singular/                          # Custom SQL tests (TEST-06, TEST-07, TEST-08)
    ├── assert_touchpoint_credit_sums_to_one.sql
    └── assert_journey_coverage.sql
```

**Key conventions:**
- One `.yml` file per directory containing tests & docs for models in that directory
- Prefix with underscore and layer name: `_adjust__sources.yml`, `_int_mta__models.yml`
- Separate source definitions (`_sources.yml`) from model tests (`_models.yml`)

### Pattern 1: Generic Tests in Schema YAML
**What:** Define tests declaratively in `.yml` files alongside models
**When to use:** All primary keys, foreign keys, and standard column validations (TEST-01 through TEST-04)
**Example:**
```yaml
# Source: https://docs.getdbt.com/docs/build/data-tests
version: 2

models:
  - name: v_stg_adjust__installs
    description: Unified installs from Adjust (iOS + Android)
    columns:
      - name: DEVICE_ID
        description: Primary key - IDFV (iOS) or GPS_ADID (Android)
        data_tests:
          - unique:
              config:
                where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"
          - not_null:
              config:
                where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"

      - name: PLATFORM
        description: iOS or Android
        data_tests:
          - accepted_values:
              arguments:
                values: ['iOS', 'Android']
              config:
                where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"
```

**Notes:**
- `data_tests:` is preferred over legacy `tests:` key (both work)
- `arguments:` syntax available in dbt v1.10.5+; older versions use inline syntax
- `where` config filters the model before testing (prevents historical false positives)

### Pattern 2: Composite Key Uniqueness Testing
**What:** Test uniqueness across multiple columns that form a composite primary key
**When to use:** Intermediate models with multi-column natural keys (TEST-02)
**Example:**
```yaml
# Source: https://docs.getdbt.com/faqs/Tests/uniqueness-two-columns
version: 2

models:
  - name: int_mta__user_journey
    description: User journey with touchpoints
    data_tests:
      - dbt_utils.unique_combination_of_columns:
          arguments:
            combination_of_columns:
              - DEVICE_ID
              - PLATFORM
              - TOUCHPOINT_TIMESTAMP
              - NETWORK_NAME
          config:
            where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"
```

**Why dbt-utils over concatenation:**
- More performant on large datasets (millions of rows)
- Clearer intent in code
- Handles NULL values correctly

### Pattern 3: Foreign Key Relationships Test
**What:** Validate referential integrity between child and parent tables
**When to use:** Device mapping foreign keys, ensuring Adjust device_id exists in Amplitude mapping (TEST-03)
**Example:**
```yaml
# Source: https://docs.getdbt.com/docs/build/data-tests
version: 2

models:
  - name: int_mta__user_journey
    description: User journey requires valid device mapping
    columns:
      - name: DEVICE_ID
        description: Must exist in Amplitude device mapping
        data_tests:
          - relationships:
              arguments:
                to: ref('int_adjust_amplitude__device_mapping')
                field: ADJUST_DEVICE_ID
              config:
                where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"
                severity: warn  # Warn instead of error due to known iOS match rate limitations
```

**Notes:**
- Relationships test automatically excludes NULLs (matches SQL FK behavior)
- Use `severity: warn` for known data quality issues documented in requirements (DMAP-04)
- `to:` accepts `ref()` for models or `source()` for raw tables

### Pattern 4: Forward-Looking Test Filters (TEST-05)
**What:** Use `where` config to test only recent data, avoiding historical false positive floods
**When to use:** All tests on incremental models or large historical datasets
**Example:**
```yaml
# Source: https://docs.getdbt.com/reference/resource-configs/where
version: 2

models:
  - name: v_stg_adjust__touchpoints
    description: Incremental model with hardcoded 2024-01-01 filter in SQL
    columns:
      - name: DEVICE_ID
        data_tests:
          - not_null:
              config:
                # Test last 60 days only - avoid 2+ years of historical data
                where: "TOUCHPOINT_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"
```

**How `where` works:**
- Wraps model reference in subquery: `SELECT * FROM (SELECT * FROM model WHERE ...) dbt_subquery`
- Supports `{{ var() }}` and `{{ env_var() }}` for dynamic filtering
- Ignored for singular tests (only applies to generic tests)

**Recommended lookback windows:**
- Staging models: 30-60 days (balance coverage vs. performance)
- Intermediate models: 30-60 days
- Marts: 30 days (assume issues caught upstream)

### Pattern 5: Singular Tests for Complex Business Logic
**What:** SQL files in `tests/` folder that return failing rows
**When to use:** Cross-model validations, aggregate checks, domain-specific rules (TEST-06, TEST-07, TEST-08)
**Example:**
```sql
-- Source: https://docs.getdbt.com/docs/build/data-tests
-- tests/singular/assert_touchpoint_credit_sums_to_one.sql
-- TEST-06: Validate touchpoint credit sums to 1.0 per install per model

SELECT DEVICE_ID
     , PLATFORM
     , INSTALL_TIMESTAMP
     , SUM(CREDIT_TIME_DECAY) AS total_credit
FROM {{ ref('int_mta__touchpoint_credit') }}
WHERE INSTALL_TIMESTAMP >= DATEADD(day, -30, CURRENT_DATE)
GROUP BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
HAVING ABS(SUM(CREDIT_TIME_DECAY) - 1.0) > 0.01  -- Allow 1% rounding tolerance
```

**When singular > generic:**
- Multi-model aggregations (TEST-08: device counts match across layers)
- Statistical checks (sums, averages, distributions)
- Business rules that don't fit column-level tests

### Anti-Patterns to Avoid

- **Testing every column for uniqueness:** Creates test bloat; only test natural/surrogate keys (per REQUIREMENTS.md Out of Scope)
- **No `where` filter on incremental models:** Leads to test runtime explosions and historical false positive floods
- **Concatenation for composite keys on large datasets:** Use dbt-utils.unique_combination_of_columns for performance
- **Hard-coding dates in `where` configs:** Use `DATEADD()` for dynamic lookback windows
- **`severity: error` on known data quality issues:** Use `severity: warn` for documented limitations (e.g., iOS IDFA match rate)

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Composite key uniqueness | Custom SQL concatenation or MD5 hashing | dbt-utils.unique_combination_of_columns | Handles NULLs correctly, more performant, standard pattern |
| Date-relative test filtering | Macro to wrap tests with date logic | dbt's built-in `where` config | Native support, works with all generic tests |
| Foreign key validation | Custom SQL join + count(*) test | dbt's `relationships` generic test | Excludes NULLs automatically, standard behavior |
| Test result storage | Custom logging table | dbt's `store_failures` config | Stores failing rows automatically, integrates with dbt artifacts |
| Test severity thresholds | IF/THEN logic in singular tests | `error_if` and `warn_if` configs | Declarative, supports row count thresholds |

**Key insight:** dbt's testing framework is mature and handles edge cases (NULLs, date filtering, severity) that custom SQL often misses. Use built-in configs before writing custom macros.

## Common Pitfalls

### Pitfall 1: Historical False Positive Flood
**What goes wrong:** Running unique/not_null tests on entire incremental model history (2+ years) surfaces old data quality issues unrelated to recent changes, overwhelming test output with irrelevant failures.

**Why it happens:** Default dbt tests run against full model results. Incremental models accumulate historical data that predates current quality standards.

**How to avoid:**
- Add `where` config to all tests on incremental models
- Use 30-60 day lookback window: `where: "date_column >= DATEADD(day, -60, CURRENT_DATE)"`
- Align lookback with incremental logic (if model processes last 10 days, test last 30)

**Warning signs:**
- Test runtime grows linearly with model history
- Test failures cite timestamps from months/years ago
- Tests pass in development but fail in production (more history)

### Pitfall 2: Testing Composite Keys with Concatenation at Scale
**What goes wrong:** Using `column_name: "(col1 || '-' || col2)"` for composite key uniqueness tests causes poor performance on multi-million row tables due to string concatenation overhead.

**Why it happens:** String concatenation requires full table scan and creates temporary strings for comparison.

**How to avoid:**
- Install dbt-utils package
- Use `dbt_utils.unique_combination_of_columns` for composite keys
- Reserve concatenation approach for small reference tables (<10K rows)

**Warning signs:**
- Uniqueness tests timeout or consume excessive warehouse credits
- Test runtime disproportionate to row count
- Warehouse query history shows high "Bytes scanned" for test queries

### Pitfall 3: Relationships Test Failing Due to Incremental Timing
**What goes wrong:** Relationships test fails intermittently because child model (int_mta__user_journey) processes more recent data than parent model (int_adjust_amplitude__device_mapping) due to different incremental schedules.

**Why it happens:** Child model runs hourly, parent model runs daily. New devices in child don't exist in parent until next parent refresh.

**How to avoid:**
- Align incremental lookback windows between parent/child (both use 7-day lookback)
- Use `severity: warn` instead of `error` for relationships where timing misalignment is expected
- Schedule dependent models together in orchestration layer
- Document known timing gaps in YAML descriptions

**Warning signs:**
- Relationships test fails on new data, passes on older data
- Failures resolve themselves after parent model refreshes
- Failure count correlates with time since parent model last ran

### Pitfall 4: Accepted Values Test Missing NULL Edge Case
**What goes wrong:** Accepted values test passes with allowed values `['iOS', 'Android']` but NULLs slip through because accepted_values test only checks non-NULL values.

**Why it happens:** dbt's accepted_values test intentionally excludes NULLs (matches SQL CHECK constraint behavior).

**How to avoid:**
- Pair accepted_values with not_null test on same column:
  ```yaml
  - name: PLATFORM
    data_tests:
      - not_null
      - accepted_values:
          arguments:
            values: ['iOS', 'Android']
  ```
- Document this pattern in project style guide

**Warning signs:**
- Unexpected NULL values in columns with accepted_values tests
- Downstream models fail on CASE statements that don't handle NULL
- BI dashboards show "(null)" category in platform filters

### Pitfall 5: Test Bloat from Over-Testing
**What goes wrong:** Adding unique/not_null tests to every column (ID, timestamp, name, description, metadata fields) creates hundreds of tests that slow down CI/CD and provide little value.

**Why it happens:** Zealous interpretation of "test everything" best practice without considering signal-to-noise ratio.

**How to avoid:**
- Only test natural/surrogate keys for uniqueness (per REQUIREMENTS.md)
- Only test columns with business-critical constraints (foreign keys, enums)
- Avoid testing derived columns where base columns are already tested
- Use test coverage as quality signal, not vanity metric

**Warning signs:**
- `dbt test` runtime exceeds `dbt run` runtime
- Test failures rarely surface actionable issues
- Team ignores test failures due to "alert fatigue"
- CI/CD pipelines timeout waiting for tests

### Pitfall 6: Forgetting `arguments:` Wrapper in dbt v1.10.5+
**What goes wrong:** Test YAML uses old syntax without `arguments:` wrapper, causing cryptic parsing errors in dbt v1.10.5+.

**Why it happens:** dbt v1.10.5 changed syntax to require `arguments:` block for test parameters. Old examples/docs use pre-1.10.5 syntax.

**How to avoid:**
```yaml
# OLD (pre-1.10.5) - may fail in newer dbt versions
- accepted_values:
    values: ['iOS', 'Android']

# NEW (v1.10.5+) - explicit arguments block
- accepted_values:
    arguments:
      values: ['iOS', 'Android']
```

**Warning signs:**
- Test parsing errors mentioning "unexpected key"
- Tests worked in dbt <1.10.5 but fail after upgrade
- Cryptic YAML parsing errors with no clear line number

## Code Examples

Verified patterns from official sources:

### Example 1: Staging Model Primary Key Tests (TEST-01)
```yaml
# Source: https://docs.getdbt.com/docs/build/data-tests
# models/staging/adjust/_adjust__models.yml
version: 2

models:
  - name: v_stg_adjust__installs
    description: |
      Unified view of all app installs from Adjust (iOS + Android).
      Grain: One row per device (first install only).
      Primary key: DEVICE_ID (IDFV for iOS, GPS_ADID for Android).
    columns:
      - name: DEVICE_ID
        description: Primary key - IDFV (iOS) or UPPER(GPS_ADID) (Android)
        data_tests:
          - unique:
              config:
                where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"
          - not_null:
              config:
                where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"

      - name: PLATFORM
        description: iOS or Android
        data_tests:
          - not_null:
              config:
                where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"
          - accepted_values:
              arguments:
                values: ['iOS', 'Android']
              config:
                where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"
```

### Example 2: Intermediate Model Composite Key Tests (TEST-02)
```yaml
# Source: https://docs.getdbt.com/faqs/Tests/uniqueness-two-columns
# models/intermediate/_int_mta__models.yml
version: 2

models:
  - name: int_mta__user_journey
    description: |
      Maps all touchpoints to installs for multi-touch attribution.
      Grain: One row per device + touchpoint + install combination.
      Composite key: JOURNEY_ROW_KEY (MD5 hash of DEVICE_ID, PLATFORM, TOUCHPOINT_TIMESTAMP, etc.)
    data_tests:
      # Option 1: Test the pre-computed surrogate key
      - unique:
          arguments:
            column_name: JOURNEY_ROW_KEY
          config:
            where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"

      # Option 2: Test the natural key combination (more explicit)
      - dbt_utils.unique_combination_of_columns:
          arguments:
            combination_of_columns:
              - DEVICE_ID
              - PLATFORM
              - TOUCHPOINT_TIMESTAMP
              - NETWORK_NAME
              - INSTALL_TIMESTAMP
              - CAMPAIGN_ID
              - ADGROUP_ID
              - CREATIVE_NAME
              - MATCH_TYPE
          config:
            where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"

    columns:
      - name: JOURNEY_ROW_KEY
        description: Surrogate key (MD5 hash of natural key)
        data_tests:
          - not_null:
              config:
                where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"
```

### Example 3: Foreign Key Relationships Test (TEST-03)
```yaml
# Source: https://docs.getdbt.com/docs/build/data-tests
# models/intermediate/_int_mta__models.yml
version: 2

models:
  - name: int_mta__user_journey
    description: User journey requires valid Adjust device in Amplitude mapping
    columns:
      - name: DEVICE_ID
        description: |
          Adjust device ID (IDFV for iOS, GPS_ADID for Android).
          Must exist in Amplitude device mapping for downstream revenue attribution.

          KNOWN LIMITATION (DMAP-04): iOS match rate ~1.4% due to ATT framework.
          Android match rate TBD - will improve after GPS_ADID normalization (DMAP-03).
        data_tests:
          - not_null:
              config:
                where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"

          - relationships:
              arguments:
                to: ref('int_adjust_amplitude__device_mapping')
                field: ADJUST_DEVICE_ID
              config:
                where: "INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)"
                severity: warn  # Warn, not error - iOS match rate is structurally low
                # Future: Add error_if threshold after DMAP-03 normalization
```

### Example 4: Singular Test for Aggregate Validation (TEST-06)
```sql
-- Source: https://docs.getdbt.com/docs/build/data-tests
-- tests/singular/assert_touchpoint_credit_sums_to_one.sql
--
-- Validates that attribution credit sums to 1.0 per install per attribution model.
-- Returns rows where sum deviates from 1.0 by more than 1% (rounding tolerance).
--
-- Grain: One row per failing (device, platform, install) combination per model.

WITH credit_sums AS (
    SELECT DEVICE_ID
         , PLATFORM
         , INSTALL_TIMESTAMP
         , SUM(CREDIT_TIME_DECAY) AS total_time_decay
         , SUM(CREDIT_FIRST_TOUCH) AS total_first_touch
         , SUM(CREDIT_LAST_TOUCH) AS total_last_touch
         , SUM(CREDIT_LINEAR) AS total_linear
         , SUM(CREDIT_POSITION_BASED) AS total_position_based
    FROM {{ ref('int_mta__touchpoint_credit') }}
    WHERE INSTALL_TIMESTAMP >= DATEADD(day, -30, CURRENT_DATE)  -- Test recent data only
    GROUP BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
)

SELECT DEVICE_ID
     , PLATFORM
     , INSTALL_TIMESTAMP
     , total_time_decay
     , total_first_touch
     , total_last_touch
     , total_linear
     , total_position_based
FROM credit_sums
WHERE ABS(total_time_decay - 1.0) > 0.01
   OR ABS(total_first_touch - 1.0) > 0.01
   OR ABS(total_last_touch - 1.0) > 0.01
   OR ABS(total_linear - 1.0) > 0.01
   OR ABS(total_position_based - 1.0) > 0.01
```

### Example 5: Test Configuration in dbt_project.yml (Global Defaults)
```yaml
# Source: https://docs.getdbt.com/reference/data-test-configs
# dbt_project.yml

tests:
  wgt_dbt:
    # Global defaults for all tests
    +store_failures: true     # Store failing rows in database
    +severity: error          # Default to error (fail builds)

    # Override for specific test types
    generic:
      +limit: 100            # Only store first 100 failures
      +where: "created_at >= DATEADD(day, -60, CURRENT_DATE)"  # Default lookback

    singular:
      +severity: warn        # Singular tests warn by default
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `tests:` key in YAML | `data_tests:` key in YAML | dbt v1.5 (2023) | Clarifies data tests vs. unit tests; `tests:` still works as alias |
| Inline test arguments | `arguments:` block wrapper | dbt v1.10.5 (2024) | More explicit syntax; old syntax may fail parsing |
| Manual WHERE clauses in singular tests | `where` config in generic tests | dbt v1.0 (2021) | Declarative, reusable, applies to all generic tests |
| dbt-utils v0.x | dbt-utils v1.x | 2023 | Breaking changes to macro names; v1.1.1+ stable as of 2024 |
| No test result storage | `store_failures: true` default in dbt Cloud | dbt Cloud 2023 | Debugging failures easier; requires warehouse storage |

**Deprecated/outdated:**
- `schema_tests` macro override: Replaced by `data_tests` config in v1.0+
- `dbt-utils.test_*` naming: Changed to `dbt_utils.*` (underscore) in v1.0
- Hard-coded test severity: Use `error_if`/`warn_if` for dynamic thresholds

## Open Questions

### 1. Optimal lookback window for forward-looking filters (TEST-05)
**What we know:**
- dbt's `where` config enables date-based test filtering
- Incremental models filter to `>= 1704067200` (2024-01-01) in SQL
- Device mapping has 7-day incremental lookback

**What's unclear:**
- Ideal test lookback window to balance coverage vs. performance
- Whether 30 days catches enough edge cases or 60 days is safer
- How to handle models with different incremental windows

**Recommendation:**
- Start with 60-day lookback for all tests (2 months coverage)
- Monitor test runtime in CI/CD; reduce to 30 days if performance issues
- Align test lookback with incremental logic where possible (if model processes 7 days, test 30)
- Document chosen window in dbt_project.yml global config

### 2. Severity level for relationships test given known iOS match rate limitations (TEST-03)
**What we know:**
- iOS IDFA match rate is ~1.4% due to ATT framework (DMAP-04)
- Android match rate currently unknown, will improve after GPS_ADID normalization (DMAP-03)
- Relationships test will fail for unmapped devices

**What's unclear:**
- Should test use `severity: warn` (alert but don't block) or `severity: error` with high threshold?
- After DMAP-03 normalization, what Android match rate threshold indicates success?
- Whether to split test by platform (iOS warns, Android errors)

**Recommendation:**
- Use `severity: warn` initially for all platforms
- After DMAP-03 normalization establishes Android baseline, switch Android to `severity: error` with `error_if: '>100'` (allow <100 unmapped devices)
- Keep iOS as `severity: warn` indefinitely due to structural ATT limitations
- Document thresholds in test YAML with DMAP requirement references

### 3. Store_failures config impact on Snowflake storage costs
**What we know:**
- `store_failures: true` saves failing rows to database tables
- Helps debug failures but consumes warehouse storage
- Can be configured globally or per-test

**What's unclear:**
- Storage cost impact for tests that fail frequently (e.g., relationships test on unmapped devices)
- Whether to use `limit:` to cap stored rows per test
- Retention policy for test failure tables

**Recommendation:**
- Enable `store_failures: true` globally with `limit: 100` (first 100 failures)
- Monitor storage growth in Snowflake after 30 days
- Set up manual cleanup job to drop old test failure tables (>30 days)
- Disable for high-volume failures if storage costs become material

## Sources

### Primary (HIGH confidence)
- [dbt Docs: Add data tests to your DAG](https://docs.getdbt.com/docs/build/data-tests) - Generic test syntax, configuration
- [dbt Docs: where config](https://docs.getdbt.com/reference/resource-configs/where) - Forward-looking test filters
- [dbt Docs: Test uniqueness of two columns](https://docs.getdbt.com/faqs/Tests/uniqueness-two-columns) - Composite key testing approaches
- [dbt Docs: Data test configurations](https://docs.getdbt.com/reference/data-test-configs) - Severity, store_failures, error_if/warn_if

### Secondary (MEDIUM confidence)
- [lakefs.io: dbt Data Quality Checks: Types, Benefits & Best Practices](https://lakefs.io/blog/dbt-data-quality-checks/) - Testing strategy overview (2026)
- [Datafold: 7 dbt Testing Best Practices](https://www.datafold.com/blog/7-dbt-testing-best-practices) - Industry patterns (2025)
- [Medium: The Complete Guide to Data Quality Testing in dbt](https://medium.com/@puttt.spl/the-complete-guide-to-data-quality-testing-in-dbt-a2f15c665630) - Comprehensive guide (Jan 2026)
- [Stellans: dbt Data Tests Best Practices](https://stellans.io/dbt-data-tests-null-accepted-values-relationships-patterns-stellans-best-practices/) - Pattern examples
- [dbt Docs: How we structure our dbt projects](https://docs.getdbt.com/best-practices/how-we-structure/1-guide-overview) - Schema.yml organization
- [Datafold: Build a Basic CI Pipeline for dbt with GitHub Actions](https://www.datafold.com/blog/building-your-first-ci-pipeline-for-your-dbt-project) - CI/CD testing integration
- [Datafold: Best practices for using dbt with Snowflake](https://www.datafold.com/blog/best-practices-for-using-dbt-with-snowflake) - Snowflake-specific performance
- [dbt Hub: dbt_utils package](https://hub.getdbt.com/dbt-labs/dbt_utils/latest/) - Package installation, versioning

### Tertiary (LOW confidence)
- [Medium: dbt Tests Explained: Generic vs Singular](https://medium.com/@likkilaxminarayana/dbt-tests-explained-generic-vs-singular-with-real-examples-6c08d8dd78a7) - Jan 2026 examples
- [dbt Community Forum: Testing incremental models](https://discourse.getdbt.com/t/testing-incremental-models/1528) - Community patterns (older thread)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - dbt-core and dbt-utils are industry standard, versions verified from official sources
- Architecture: HIGH - Patterns verified from official dbt documentation with current syntax (v1.10.5+)
- Pitfalls: MEDIUM - Based on community best practices and official docs, but forward-looking filter window (30 vs 60 days) requires project-specific tuning

**Research date:** 2026-02-10
**Valid until:** 2026-04-10 (60 days - dbt testing patterns are stable, but package versions and syntax evolve)

**dbt version context:**
- Project uses dbt-fusion 2.0.0-preview.110 (preview/beta distribution)
- Research based on dbt-core 1.8+ and v1.10.5+ syntax where applicable
- Syntax may need adjustment if dbt-fusion diverges from core
