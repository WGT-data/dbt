---
phase: 05-mmm-pipeline-hardening-expand-test-coverage
plan: 01
subsystem: testing
tags: [mmm, singular-tests, data-quality, network-mapping, analysis]
requires:
  - phase: 03-mta-limitations-mmm-foundation
    provides: MMM intermediate models (spend, installs, revenue) and mart models (daily, weekly)
provides:
  - Three MMM singular tests (date spine completeness, cross-layer consistency, zero-fill integrity)
  - Network mapping coverage analysis query
affects:
  - 05-02: Will use these tests to validate MMM pipeline in dbt Cloud
  - 05-03: Network mapping gaps discovered here inform seed updates
tech-stack:
  added: []
  patterns:
    - Singular test pattern (zero rows = pass, failing rows = fail)
    - dbt_utils.date_spine for expected date grid generation
    - FULL OUTER JOIN for cross-layer consistency validation
    - Analysis queries in analysis/ directory for ad-hoc investigation
key-files:
  created:
    - tests/singular/test_mmm_date_spine_completeness.sql
    - tests/singular/test_mmm_cross_layer_consistency.sql
    - tests/singular/test_mmm_zero_fill_integrity.sql
    - analysis/check_network_mapping_coverage.sql
  modified: []
key-decisions:
  - "TEST-06: Date spine completeness test generates expected grid from active channels and validates every date+channel+platform exists"
  - "TEST-07: Cross-layer consistency test aggregates at DATE+PLATFORM grain and filters mart to HAS_*_DATA=1 to exclude zero-filled rows"
  - "TEST-08: Zero-fill integrity test only checks metric > 0 with flag = 0 violations (not zero metrics with flag = 1, which are valid)"
  - "Network mapping analysis scopes to last 90 days with actual spend/revenue/installs to find active unmapped partners"
duration: 1min
completed: 2026-02-11
---

# Phase 5 Plan 01: MMM Test Creation Summary

**Created three MMM singular tests (date spine, cross-layer, zero-fill) and network mapping coverage analysis query for pre-deployment validation**

## Performance

- **Duration:** 1 minute
- **Tasks completed:** 2/2
- **Files created:** 4
- **Commits:** 2

## Accomplishments

### Task 1: Create three MMM singular tests
**Commit:** b45bc5f

Created three singular test SQL files following the zero-rows-pass pattern established by test_ad_partner_mapping_consistency.sql:

1. **test_mmm_date_spine_completeness.sql (TEST-06)**
   - Generates expected date grid using dbt_utils.date_spine (2024-01-01 to current_date)
   - Cross joins with all active PLATFORM+CHANNEL combinations from mmm__daily_channel_summary
   - Left joins to actual data to find missing date+channel+platform combinations
   - Returns rows where expected grid has no corresponding mart row
   - Purpose: Ensures MMM regression receives complete time series with no gaps

2. **test_mmm_cross_layer_consistency.sql (TEST-07)**
   - Aggregates all metrics from three intermediate models (spend, installs, revenue) at DATE+PLATFORM grain using UNION ALL with zero-padding
   - Aggregates mart metrics at same grain, filtering to HAS_*_DATA=1 to exclude purely zero-filled date spine rows
   - Full outer joins and compares each metric (SPEND, IMPRESSIONS, CLICKS, PAID_INSTALLS, INSTALLS, REVENUE, ALL_REVENUE, AD_REVENUE, API_INSTALLS)
   - Returns rows where ABS(intermediate - mart) > 0.01 for currency or > 0 for counts
   - Purpose: Validates that date spine LEFT JOIN logic preserves data accuracy

3. **test_mmm_zero_fill_integrity.sql (TEST-08)**
   - Queries mmm__daily_channel_summary for six violation conditions
   - Only flags violations where metric > 0 but HAS_*_DATA = 0 (has data but flag says no)
   - Does NOT flag metric = 0 with flag = 1 (source can legitimately have $0 row)
   - Returns DATE, PLATFORM, CHANNEL, violation_type, and actual values for debugging
   - Purpose: Ensures CASE WHEN IS NOT NULL logic correctly sets data quality flags

All three tests use {{ ref() }} for model references, include header comments explaining purpose and failure conditions, and follow the singular test convention (zero rows = pass).

### Task 2: Create network mapping coverage analysis query
**Commit:** 6283641

Created analysis/check_network_mapping_coverage.sql to identify unmapped PARTNER_NAME values:

**Data sources:**
- Supermetrics spend data (stg_supermetrics__adj_campaign) - last 90 days with COST > 0
- Adjust API revenue data (stg_adjust__report_daily) - last 90 days with REVENUE > 0 or INSTALLS > 0

**Mapping logic:**
- Left joins to network_mapping seed on SUPERMETRICS_PARTNER_NAME (for Supermetrics source)
- Left joins to network_mapping seed on ADJUST_NETWORK_NAME (for Adjust API source)
- Flags partners as 'Mapped' or 'UNMAPPED - will map to Other'

**Output:**
- Summary section: coverage_status, partner_count, partners (LISTAGG)
- Detail section: Each unmapped partner with source and recommendation

**Usage:** Run `dbt compile --select check_network_mapping_coverage` then execute compiled SQL in Snowflake worksheet to discover gaps before production deployment.

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create three MMM singular tests | b45bc5f | test_mmm_date_spine_completeness.sql, test_mmm_cross_layer_consistency.sql, test_mmm_zero_fill_integrity.sql |
| 2 | Create network mapping coverage analysis query | 6283641 | check_network_mapping_coverage.sql |

## Files Created/Modified

**Created:**
- tests/singular/test_mmm_date_spine_completeness.sql (1,691 bytes)
- tests/singular/test_mmm_cross_layer_consistency.sql (7,778 bytes)
- tests/singular/test_mmm_zero_fill_integrity.sql (1,985 bytes)
- analysis/check_network_mapping_coverage.sql (3,238 bytes)

**Modified:** None

## Decisions Made

1. **Date spine completeness test (TEST-06) uses active channels from mart**: Generates expected grid only for PLATFORM+CHANNEL combinations that already exist in mmm__daily_channel_summary. This avoids false positives for channels that have never had data.

2. **Cross-layer consistency test (TEST-07) filters mart to HAS_*_DATA=1**: Only compares rows that have actual source data, excluding purely zero-filled date spine rows. Zero-filled rows by definition have no intermediate data to compare against.

3. **Zero-fill integrity test (TEST-08) only checks metric > 0 violations**: Does NOT flag metric=0 with flag=1 as violations. A source row with $0 spend IS real data and should have HAS_*_DATA=1. Only flags non-zero metrics with flag=0 (impossible condition).

4. **Network mapping analysis scopes to last 90 days with activity**: Focuses on recent partners with actual spend/revenue/installs to avoid flagging historical/inactive partners as unmapped.

5. **Analysis query uses UNION (not UNION ALL) for partner deduplication**: A partner appearing in both Supermetrics and Adjust API should be listed once in output, not twice.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. All SQL files created successfully with valid Jinja syntax.

## Next Phase Readiness

**Ready for Plan 02:**
- Three singular tests ready for compilation and execution in dbt Cloud
- Network mapping analysis query ready for compilation and execution to discover gaps
- Tests will validate MMM pipeline data quality before production deployment

**Blockers:** None

**Recommendations:**
1. Run network mapping analysis first to identify gaps
2. Update network_mapping.csv seed if unmapped partners found
3. Run dbt test --select test_mmm_* to validate pipeline
4. If date spine test fails, investigate missing channel+platform combinations
5. If cross-layer test fails, check intermediate model filters and mart LEFT JOIN logic
6. If zero-fill test fails, check HAS_*_DATA CASE WHEN IS NOT NULL logic in mart

## Self-Check: PASSED

All created files verified:
- tests/singular/test_mmm_date_spine_completeness.sql: EXISTS
- tests/singular/test_mmm_cross_layer_consistency.sql: EXISTS
- tests/singular/test_mmm_zero_fill_integrity.sql: EXISTS
- analysis/check_network_mapping_coverage.sql: EXISTS

All commits verified:
- b45bc5f: EXISTS
- 6283641: EXISTS
