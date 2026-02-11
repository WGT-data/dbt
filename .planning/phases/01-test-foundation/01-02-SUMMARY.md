---
phase: 01-test-foundation
plan: 02
subsystem: data-quality
tags: [dbt, testing, intermediate-layer, device-mapping, mta, cohorts, revenue]

# Dependency Graph
requires:
  - 01-01  # Staging layer tests foundation
provides:
  - intermediate-layer-test-coverage
  - composite-key-uniqueness-tests
  - device-mapping-relationship-test
  - platform-accepted-values-tests
  - forward-looking-60day-filters
affects:
  - 01-test-foundation (completes this phase)

# Tech Stack
tech-stack:
  added: []
  patterns:
    - dbt-generic-tests
    - dbt-utils-unique-combination
    - severity-warn-for-known-issues
    - forward-looking-where-filters

# Key Files
key-files:
  created:
    - models/intermediate/_int_device_mapping__models.yml
    - models/intermediate/_int_cohort__models.yml
    - models/intermediate/_int_revenue__models.yml
  modified:
    - models/intermediate/_int_mta__models.yml

# Decisions Made
decisions:
  - id: TEST-03-SEVERITY
    what: "Use severity: warn for device_mapping relationships test"
    why: "iOS IDFA match rate is structurally ~1.4% due to ATT limitation. Android device mapping not yet fixed (Phase 3). Setting severity: warn allows tracking the metric without failing builds."
    alternatives: "error (would break builds), omit (would lose visibility)"
    impact: "Test runs but doesn't fail builds. Provides visibility into match rate issues."

# Metrics
duration: 3 min
completed: 2026-02-10
---

# Phase 01 Plan 02: Intermediate Layer Test Foundation Summary

**One-liner:** Comprehensive intermediate-layer test coverage with composite key uniqueness, device mapping relationships (severity: warn), platform constraints, and 60-day forward-looking filters

## What Was Accomplished

Added data quality tests to all intermediate models covering composite key uniqueness (TEST-02), foreign key relationships with device mapping (TEST-03), platform accepted_values (TEST-04), and forward-looking 60-day where filters (TEST-05).

This establishes the intermediate-layer test coverage which is the critical layer where device mapping and MTA attribution happen. The relationships test (TEST-03) between user_journey and device_mapping is the most important test for catching broken device ID matching — the exact problem Phase 3 will fix.

### Task Commits

| Task | Description | Commit | Files Modified |
|------|-------------|--------|----------------|
| 1 | Add tests to MTA models and create device mapping tests | 81e4a3e | _int_mta__models.yml (updated), _int_device_mapping__models.yml (created) |
| 2 | Create cohort and revenue intermediate model tests | ece4719 | _int_cohort__models.yml (created), _int_revenue__models.yml (created) |

### Test Coverage Summary

**Models with composite key tests:**
- `int_adjust_amplitude__device_mapping`: unique_combination_of_columns on [ADJUST_DEVICE_ID, AMPLITUDE_USER_ID, PLATFORM]
- `int_user_cohort__attribution`: unique_combination_of_columns on [USER_ID, PLATFORM]
- `int_user_cohort__metrics`: unique_combination_of_columns on [USER_ID, PLATFORM]

**Models with single-column unique tests:**
- `int_mta__user_journey`: unique + not_null on JOURNEY_ROW_KEY
- `int_mta__touchpoint_credit`: unique + not_null on JOURNEY_ROW_KEY
- `int_revenue__user_summary`: unique + not_null on USER_ID

**Referential integrity:**
- `int_mta__user_journey.DEVICE_ID` → `int_adjust_amplitude__device_mapping.ADJUST_DEVICE_ID` (severity: warn)

**Platform constraints:**
- All models with PLATFORM column have accepted_values ['iOS', 'Android'] + not_null tests
- 5 total PLATFORM tests across intermediate layer

**Where filters:**
- All tests use 60-day lookback (except int_revenue__user_summary which has no timestamp column)
- 23 total where filters using INSTALL_TIMESTAMP, FIRST_SEEN_AT, or INSTALL_TIME

## Technical Implementation

### Test Syntax
All tests use dbt v1.10.5+ syntax with `data_tests:` key and `arguments:` wrapper for test configs.

### Forward-Looking Filters
Tests use `where: "TIMESTAMP_COL >= DATEADD(day, -60, CURRENT_DATE)"` to:
- Balance data quality coverage with test execution performance
- Focus on recent data where issues are most likely to surface
- Reduce test runtime on large historical datasets

### Severity: Warn Pattern
The device mapping relationships test uses `severity: warn` because:
- iOS IDFA match rate is structurally limited to ~1.4% (ATT consent rate)
- Android device mapping is known to be broken (will be fixed in Phase 3)
- We want visibility into the metric without failing builds

## Deviations from Plan

None - plan executed exactly as written.

## Next Phase Readiness

**Phase 1 Complete:** This plan completes Phase 01 - Test Foundation.

**Ready for Phase 2:** Yes. All staging and intermediate models now have test coverage for primary keys, composite keys, platform constraints, and forward-looking filters.

**No blockers identified.**

## Knowledge Capture

### What Worked Well
- Using severity: warn for known issues (device mapping) provides visibility without breaking builds
- 60-day where filters strike good balance between coverage and performance
- Model-specific timestamp columns (INSTALL_TIMESTAMP vs FIRST_SEEN_AT vs INSTALL_TIME) allow precise filtering per model's grain

### Gotchas for Future Work
- int_revenue__user_summary has no PLATFORM column (aggregates across all platforms) - don't add platform tests to it
- int_revenue__user_summary has no obvious timestamp column for where filters - uses full dataset for testing
- Relationships test requires `to: ref('model_name')` syntax (not just 'model_name')

### Reference Patterns
```yaml
# Composite key test pattern
data_tests:
  - dbt_utils.unique_combination_of_columns:
      combination_of_columns:
        - COL1
        - COL2
      config:
        where: "TIMESTAMP_COL >= DATEADD(day, -60, CURRENT_DATE)"

# Relationships test with severity warn
- relationships:
    config:
      to: ref('target_model')
      field: TARGET_COLUMN
      severity: warn
      where: "TIMESTAMP_COL >= DATEADD(day, -60, CURRENT_DATE)"
    meta:
      comment: "Explanation of why severity is warn"

# Platform accepted_values pattern
- accepted_values:
    config:
      values: ['iOS', 'Android']
      where: "TIMESTAMP_COL >= DATEADD(day, -60, CURRENT_DATE)"
```

---

**Status:** ✅ Complete
**Phase 1 Progress:** 2/2 plans (100%)
**Next:** Phase 02 - Data Integrity

## Self-Check: PASSED
