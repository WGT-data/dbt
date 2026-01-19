# Testing Patterns

**Analysis Date:** 2026-01-19

## Test Framework

**Runner:**
- dbt test (built-in)
- Config: `dbt_project.yml` (test-paths: ["tests"])

**Test Location:**
- Generic tests: YAML schema files (`_*__models.yml`, `_*__sources.yml`)
- Singular tests: `tests/` directory (currently empty - `.gitkeep` only)

**Run Commands:**
```bash
dbt test                    # Run all tests
dbt test --select model_name  # Test specific model
dbt test --select source:adjust  # Test specific source
dbt build                   # Run models + tests together
```

## Test File Organization

**Location:**
- Tests are defined inline with model/source documentation
- Schema files co-located with models in same directory

**Naming:**
- Source schemas: `models/staging/{source}/__{source}__sources.yml`
- Model schemas: `models/{layer}/_{domain}__models.yml`

**Current Schema Files:**
```
models/
  staging/
    adjust/
      _adjust__sources.yml        # Source definitions only
    amplitude/
      _amplitude__sources.yml     # Source definitions only
    supermetrics/
      _supermetrics__sources.yml  # Source + column descriptions
    revenue/
      _revenue__sources.yml       # Source definitions only
  intermediate/
    _int_mta__models.yml          # Model + column documentation
  marts/
    attribution/
      _mta__models.yml            # Model + column documentation
```

## Test Types

**Schema Tests (Not Currently Implemented):**
The codebase does not currently define any schema tests (unique, not_null, relationships, accepted_values). This is a gap.

**Singular Tests (Not Currently Implemented):**
The `tests/` directory contains only `.gitkeep` - no custom SQL tests exist.

## Recommended Testing Patterns

**Primary Key Tests:**
Add to model YAML files:
```yaml
models:
  - name: int_mta__touchpoint_credit
    columns:
      - name: DEVICE_ID
        tests:
          - not_null
      - name: PLATFORM
        tests:
          - not_null
          - accepted_values:
              values: ['iOS', 'Android']
```

**Unique Composite Key Tests:**
Based on unique_key configs in models, these combinations should be unique:

| Model | Unique Key Columns |
|-------|-------------------|
| `int_mta__user_journey` | DEVICE_ID, PLATFORM, TOUCHPOINT_TIMESTAMP, TOUCHPOINT_TYPE, NETWORK_NAME |
| `int_mta__touchpoint_credit` | DEVICE_ID, PLATFORM, TOUCHPOINT_TIMESTAMP, TOUCHPOINT_TYPE, NETWORK_NAME |
| `mta__campaign_performance` | AD_PARTNER, CAMPAIGN_ID, PLATFORM, DATE |
| `attribution__installs` | AD_PARTNER, NETWORK_NAME, CAMPAIGN_ID, ADGROUP_ID, PLATFORM, INSTALL_DATE |
| `int_adjust_amplitude__device_mapping` | ADJUST_DEVICE_ID, AMPLITUDE_USER_ID, PLATFORM |
| `int_user_cohort__metrics` | USER_ID, PLATFORM |

**Relationship Tests:**
```yaml
# Example: Ensure touchpoints reference valid installs
- name: DEVICE_ID
  tests:
    - relationships:
        to: ref('v_stg_adjust__installs')
        field: DEVICE_ID
```

## Data Quality Patterns in SQL

**Validation via WHERE Clauses:**
Models enforce data quality inline rather than through tests:

```sql
-- v_stg_adjust__installs.sql
WHERE IDFV IS NOT NULL
  AND INSTALLED_AT IS NOT NULL

-- v_stg_amplitude__merge_ids.sql
WHERE AE.DEVICE_ID IS NOT NULL
  AND AE.USER_ID IS NOT NULL
  AND AE.PLATFORM IN ('iOS', 'Android')
```

**Diagnostic Models:**
Data quality is monitored via dedicated diagnostic models:

- `int_device_mapping__diagnostics.sql` - Identifies users with anomalous device counts (100+ devices)
- `int_device_mapping__distribution_summary.sql` - Distribution summary for device mapping

Example diagnostic pattern:
```sql
-- int_device_mapping__diagnostics.sql
SELECT AMPLITUDE_USER_ID
     , DEVICE_COUNT
     , CASE
         WHEN DEVICE_COUNT >= 100 THEN TRUE
         ELSE FALSE
       END AS IS_ANOMALOUS
FROM device_counts
ORDER BY DEVICE_COUNT DESC
```

## Incremental Model Testing

**Lookback Window Pattern:**
All incremental models use lookback windows to handle late-arriving data:

| Model Type | Lookback Days | Rationale |
|------------|---------------|-----------|
| Adjust staging | 3 days | S3 ingestion delay |
| Amplitude events | 3 days | Server upload delay |
| Device mapping | 7 days | Account linking delay |
| User cohort metrics | 35 days | D30 maturity window + buffer |
| Attribution marts | 7 days | Revenue attribution window |

**Testing Incremental Logic:**
To validate incremental models work correctly:
```bash
# Full refresh
dbt run --select model_name --full-refresh

# Incremental run
dbt run --select model_name

# Compare row counts
dbt run-operation get_row_count --args '{"model": "model_name"}'
```

## Coverage Gaps

**Critical Models Without Tests:**

1. **Staging Models** - No validation that source data meets expectations
   - `v_stg_adjust__installs.sql` - Core install data
   - `v_stg_adjust__touchpoints.sql` - Touchpoint data for MTA
   - `v_stg_amplitude__merge_ids.sql` - Device-to-user mapping

2. **Intermediate Models** - No validation of transformation logic
   - `int_mta__user_journey.sql` - Journey construction
   - `int_mta__touchpoint_credit.sql` - Attribution credit calculations

3. **Mart Models** - No validation of aggregation logic
   - `mta__campaign_performance.sql` - Campaign metrics
   - `rpt__attribution_model_comparison.sql` - Model comparison

**Recommended Priority Tests:**

1. **Attribution Credit Sum = 1.0**
```sql
-- tests/assert_attribution_credits_sum_to_one.sql
SELECT DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
     , SUM(CREDIT_TIME_DECAY) AS TOTAL_CREDIT
FROM {{ ref('int_mta__touchpoint_credit') }}
GROUP BY 1, 2, 3
HAVING ABS(SUM(CREDIT_TIME_DECAY) - 1.0) > 0.001
```

2. **No Future Touchpoints**
```sql
-- tests/assert_touchpoints_before_install.sql
SELECT *
FROM {{ ref('int_mta__user_journey') }}
WHERE TOUCHPOINT_TIMESTAMP >= INSTALL_TIMESTAMP
```

3. **Ad Partner Mapping Consistency**
```sql
-- tests/assert_ad_partner_not_null.sql
SELECT *
FROM {{ ref('v_stg_adjust__installs') }}
WHERE AD_PARTNER IS NULL
```

## Mocking Patterns

**Not Currently Used:**
The project does not use dbt packages for mocking (e.g., dbt-unit-testing).

**Recommended Approach:**
For unit testing complex attribution logic, consider:
```yaml
# packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.0.0", "<2.0.0"]
  - package: EqualExperts/dbt_unit_testing
    version: [">=0.3.0", "<1.0.0"]
```

## CI/CD Testing

**Not Currently Configured:**
No CI pipeline detected (no `.github/workflows/`, no `bitbucket-pipelines.yml`, no `gitlab-ci.yml`).

**Recommended CI Pipeline:**
```yaml
# .github/workflows/dbt-ci.yml
name: dbt CI
on: [pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install dbt
        run: pip install dbt-snowflake
      - name: dbt deps
        run: dbt deps
      - name: dbt compile
        run: dbt compile --target ci
      - name: dbt test
        run: dbt test --target ci
```

## Documentation Testing

**Existing Documentation:**
- Model descriptions in `_mta__models.yml` and `_int_mta__models.yml`
- Column descriptions for key fields
- No automated documentation coverage checks

**Generate Docs:**
```bash
dbt docs generate
dbt docs serve
```

## Test Data Patterns

**Seed Data:**
- `seeds/network_mapping.csv` - Ad network name standardization
- Use for reference/mapping data that rarely changes

**No Test Fixtures:**
The project does not currently maintain test fixtures or sample data.

---

*Testing analysis: 2026-01-19*
