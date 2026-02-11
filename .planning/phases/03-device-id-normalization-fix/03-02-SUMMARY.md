---
phase: 03-mta-limitations-mmm-foundation
plan: 02
subsystem: analytics
tags: [mmm, dbt, snowflake, adjust, supermetrics, marketing-attribution]

# Dependency graph
requires:
  - phase: 01-test-foundation
    provides: dbt testing framework and configuration
  - phase: 02-device-id-audit
    provides: Understanding that device mapping is broken for Android (0% match rate)
provides:
  - MMM intermediate models aggregating spend, installs, and revenue at daily+channel+platform grain
  - Independent MMM pipeline that bypasses broken device mapping for revenue attribution
  - Consistent AD_PARTNER channel taxonomy across all three MMM metrics
affects: [04-mmm-mart, mmm-modeling, revenue-attribution]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "MMM pipeline uses Adjust API pre-aggregated revenue to avoid device mapping dependency"
    - "Incremental models with 7-day lookback for late-arriving data"
    - "Consistent channel taxonomy via network_mapping seed across all metrics"

key-files:
  created:
    - models/intermediate/int_mmm__daily_channel_spend.sql
    - models/intermediate/int_mmm__daily_channel_installs.sql
    - models/intermediate/int_mmm__daily_channel_revenue.sql
    - models/intermediate/_int_mmm__models.yml
  modified: []

key-decisions:
  - "Use Adjust API pre-aggregated revenue (stg_adjust__report_daily) rather than user-level cohort pipeline to avoid dependency on broken device mapping"
  - "Accept event-date-based revenue (not install-cohort-based) as acceptable tradeoff for MMM statistical modeling"
  - "Use Supermetrics as single source of truth for spend to avoid double-counting with Adjust API cost data"
  - "Use device-level S3 install counts (v_stg_adjust__installs) rather than API aggregates for accuracy"

patterns-established:
  - "MMM models aggregate at DATE+PLATFORM+CHANNEL grain with composite unique key"
  - "All MMM models use incremental materialization with merge strategy and 7-day lookback"
  - "Channel taxonomy standardized via network_mapping seed (AD_PARTNER column)"
  - "dbt_utils.unique_combination_of_columns tests on composite keys for data quality"

# Metrics
duration: 2min
completed: 2026-02-11
---

# Phase 03 Plan 02: MMM Intermediate Models Summary

**Three MMM intermediate models aggregate spend, installs, and revenue at daily+channel+platform grain, with revenue model deliberately independent of broken device mapping pipeline**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-11T21:59:00Z
- **Completed:** 2026-02-11T22:00:52Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Created spend aggregation model combining Supermetrics data with network_mapping taxonomy
- Created install count model using device-level Adjust S3 data for accuracy
- Created revenue model using Adjust API pre-aggregated data (bypassing broken device mapping)
- Established consistent DATE+PLATFORM+CHANNEL grain across all MMM building blocks
- Added dbt schema YAML with data quality tests for all three models

## Task Commits

Each task was committed atomically:

1. **Task 1: Create daily channel spend and installs intermediate models** - `b3c2394` (feat)
2. **Task 2: Create daily channel revenue model and MMM schema YAML** - `cce8661` (feat)

## Files Created/Modified

- `models/intermediate/int_mmm__daily_channel_spend.sql` - Daily spend by channel from Supermetrics, mapped via network_mapping seed
- `models/intermediate/int_mmm__daily_channel_installs.sql` - Daily install counts from device-level Adjust S3 data
- `models/intermediate/int_mmm__daily_channel_revenue.sql` - Daily revenue by channel from Adjust API (independent of device mapping)
- `models/intermediate/_int_mmm__models.yml` - Schema definitions with data quality tests for all 3 MMM models

## Decisions Made

**1. Use Adjust API pre-aggregated revenue rather than user-level cohort pipeline**
- **Rationale:** int_user_cohort__metrics depends on int_adjust_amplitude__device_mapping which is broken for Android (0% match rate). Adjust API already has revenue attributed at campaign/partner level, making MMM pipeline fully independent.
- **Tradeoff:** Revenue is event-date based (not install-cohort-date based). Acceptable for MMM because statistical modeling handles install-to-revenue lag through adstock/lag parameters.

**2. Use Supermetrics as single source of truth for spend**
- **Rationale:** Avoid double-counting since both Supermetrics and Adjust API have cost data for many partners. Supermetrics is the primary spend data source.

**3. Use device-level S3 install counts rather than API aggregates**
- **Rationale:** v_stg_adjust__installs counts distinct devices (first install only) for more accurate install metrics than API aggregated counts.

**4. Standardize channel taxonomy via network_mapping seed**
- **Rationale:** Ensures consistent AD_PARTNER values across spend, installs, and revenue for proper MMM aggregation.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**Ready for Phase 4 (MMM daily summary mart):**
- Three intermediate models provide clean inputs at consistent grain
- Channel taxonomy is standardized across all metrics
- Revenue pipeline is independent of broken device mapping
- All models have incremental logic and data quality tests

**No blockers:**
- Models can be built and tested in dbt Cloud
- Next phase will join these three models into final MMM mart

## Self-Check: PASSED

All created files exist:
- models/intermediate/int_mmm__daily_channel_spend.sql ✓
- models/intermediate/int_mmm__daily_channel_installs.sql ✓
- models/intermediate/int_mmm__daily_channel_revenue.sql ✓
- models/intermediate/_int_mmm__models.yml ✓

All commits exist:
- b3c2394 ✓
- cce8661 ✓

---
*Phase: 03-mta-limitations-mmm-foundation*
*Completed: 2026-02-11*
