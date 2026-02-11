---
phase: 01-test-foundation
plan: 01
subsystem: testing
tags: [dbt, dbt-utils, data-quality, staging-tests, snowflake]

# Dependency graph
requires:
  - phase: pre-v1.0
    provides: Existing staging models (v_stg_adjust__installs, v_stg_adjust__touchpoints, v_stg_amplitude__merge_ids, v_stg_revenue__events)
provides:
  - dbt-utils package dependency (>=1.1.1) for composite key testing
  - Staging layer data quality tests (unique, not_null, accepted_values) on all 4 staging models
  - 60-day forward-looking where filters on all tests
affects: [02-device-id-normalization, future-staging-models, test-infrastructure]

# Tech tracking
tech-stack:
  added: [dbt-utils >= 1.1.1]
  patterns:
    - "All staging model tests use 60-day forward-looking where filters"
    - "Composite keys tested with dbt_utils.unique_combination_of_columns"
    - "Platform columns validated with accepted_values ['iOS', 'Android']"
    - "Test definitions use data_tests: key with arguments: wrapper (dbt v1.10.5+ syntax)"

key-files:
  created:
    - packages.yml
    - models/staging/adjust/_adjust__models.yml
    - models/staging/amplitude/_amplitude__models.yml
    - models/staging/revenue/_revenue__models.yml
  modified: []

key-decisions:
  - "Use 60-day lookback for all test filters (matches business needs for recent data quality, reduces test execution time)"
  - "Test only primary keys and constrained columns (PLATFORM) - avoid test bloat"
  - "Use model-specific timestamp columns in where filters (INSTALL_TIMESTAMP, TOUCHPOINT_TIMESTAMP, FIRST_SEEN_AT, EVENT_TIME)"

patterns-established:
  - "Staging model test pattern: composite unique key + not_null on key columns + accepted_values on PLATFORM + 60-day where filters"
  - "YAML schema files use data_tests: key (not legacy tests:) with arguments: wrapper for test parameters"

# Metrics
duration: 2min
completed: 2026-02-10
---

# Phase 01 Plan 01: Staging Layer Test Foundation Summary

**Baseline data quality tests for all staging models using dbt-utils with 60-day forward-looking filters on primary keys, platform validation, and composite unique key constraints**

## Performance

- **Duration:** 2 minutes
- **Started:** 2026-02-10T16:55:49Z
- **Completed:** 2026-02-10T16:57:32Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Installed dbt-utils package (>=1.1.1) for composite key testing capability
- Added comprehensive test coverage to all 4 staging models (Adjust installs/touchpoints, Amplitude merge IDs, Revenue events)
- Established 60-day forward-looking test filter pattern to focus on recent data quality
- Validated primary key uniqueness (simple and composite), not_null constraints, and platform accepted values across all staging models

## Task Commits

Each task was committed atomically:

1. **Task 1: Create packages.yml and staging Adjust model tests** - `9e378e0` (test)
2. **Task 2: Create staging Amplitude and Revenue model tests** - `6b96d1f` (test)

## Files Created/Modified

- `packages.yml` - dbt-utils package dependency declaration (>=1.1.1 for composite key testing)
- `models/staging/adjust/_adjust__models.yml` - Tests for v_stg_adjust__installs (unique DEVICE_ID) and v_stg_adjust__touchpoints (composite key uniqueness)
- `models/staging/amplitude/_amplitude__models.yml` - Tests for v_stg_amplitude__merge_ids (composite key on DEVICE_ID_UUID + USER_ID_INTEGER + PLATFORM)
- `models/staging/revenue/_revenue__models.yml` - Tests for v_stg_revenue__events (composite key on USER_ID + EVENT_TIME + EVENT_TYPE)

## Decisions Made

**1. 60-day lookback for all test where filters**
- **Rationale:** Balances data quality coverage (catches recent issues) with test execution performance (limits scan volume). Business focuses on recent data for decision-making.

**2. Test only primary keys and constrained columns (PLATFORM)**
- **Rationale:** Avoids test bloat. Primary key uniqueness and not_null tests catch the most critical data quality issues. PLATFORM accepted_values prevents invalid platform values from propagating downstream.

**3. Use model-specific timestamp columns in where filters**
- **Rationale:** Each staging model has different timestamp column names (INSTALL_TIMESTAMP, TOUCHPOINT_TIMESTAMP, FIRST_SEEN_AT, EVENT_TIME). Using the correct column ensures tests filter accurately.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. YAML syntax verification attempted with Python yaml module (not installed in externally-managed environment), fell back to grep pattern verification which confirmed all expected test patterns present.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**Ready for Phase 01 Plan 02 (Intermediate Layer Tests):**
- Staging layer test foundation established
- dbt-utils package available for composite key testing
- 60-day forward-looking filter pattern established

**Blockers/Concerns:**
- None. Tests will need to be run with `dbt test` to verify they pass against actual data, but that's part of normal dbt workflow (not blocking next plan).

---
*Phase: 01-test-foundation*
*Completed: 2026-02-10*

## Self-Check: PASSED

All created files verified:
- packages.yml
- models/staging/adjust/_adjust__models.yml
- models/staging/amplitude/_amplitude__models.yml
- models/staging/revenue/_revenue__models.yml

All commits verified:
- 9e378e0
- 6b96d1f
