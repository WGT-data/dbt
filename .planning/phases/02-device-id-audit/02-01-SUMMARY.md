---
phase: 02-device-id-audit
plan: 01
subsystem: data-quality
tags: [snowflake, sql, device-ids, dbt, adjust, amplitude, audit, profiling]

# Dependency graph
requires:
  - phase: 01-test-foundation
    provides: Test infrastructure and data quality patterns
provides:
  - 3 SQL audit queries profiling device IDs across Adjust and Amplitude source tables
  - Baseline match rate calculations by platform and match strategy
  - Comprehensive README with run instructions and troubleshooting guide
affects: [02-02, 03-normalization, device-mapping]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Snowflake data profiling with COUNT, DISTINCT, REGEXP_LIKE for format validation"
    - "Fully qualified table names for non-dbt SQL execution"
    - "Platform-grouped queries (GROUP BY PLATFORM) for cross-platform comparison"
    - "Baseline metrics capture before normalization changes"

key-files:
  created:
    - analyses/audit_device_id_formats.sql
    - analyses/amplitude_device_id_investigation.sql
    - analyses/baseline_match_rates.sql
    - analyses/README.md
  modified: []

key-decisions:
  - "Use fully qualified Snowflake table names (not dbt refs) so queries can be pasted directly into Snowflake or dbt Cloud IDE SQL runner"
  - "Scope audit queries to 30-60 day lookback for performance while maintaining sufficient sample size"
  - "Profile both direct match and R-stripped match for Android GPS_ADID to test Amplitude normalization hypothesis"
  - "Include iOS IDFA match rate investigation despite known ATT limitations to document baseline"

patterns-established:
  - "Pattern: SQL audit queries in analyses/ directory use DATABASE.SCHEMA.TABLE fully qualified names"
  - "Pattern: All device ID profiling queries include GROUP BY PLATFORM for iOS vs Android comparison"
  - "Pattern: Baseline metrics documented with timestamp for before/after validation"
  - "Pattern: Query header comments explain purpose, how to run, and expected output"

# Metrics
duration: 4min
completed: 2026-02-11
---

# Phase 2 Plan 1: Device ID Audit Queries Summary

**3 SQL audit queries profiling device IDs across Adjust (GPS_ADID, IDFV, IDFA) and Amplitude (DEVICE_ID, R suffix pattern) with baseline match rate calculations by platform**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-11T17:30:26Z
- **Completed:** 2026-02-11T17:34:40Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Device ID format audit query covering Adjust iOS/Android install tables with population stats, UUID validation, casing analysis, and sample values
- Amplitude DEVICE_ID investigation query answering key open questions: random ID vs GPS_ADID, R suffix prevalence, ADID field existence, MERGE_IDS table structure
- Baseline match rate query calculating Android GPS_ADID (direct and R-stripped), iOS IDFV, iOS IDFA, and iOS MTA touchpoint match rates
- Comprehensive README with run instructions, expected output, result capture workflow, and troubleshooting guide

## Task Commits

Each task was committed atomically:

1. **Task 1: Write device ID format audit and Amplitude investigation SQL queries** - `125bae5` (feat)
2. **Task 2: Write baseline match rate SQL and analyses README** - `e701819` (feat)

**Plan metadata:** Not yet committed (will be committed after STATE.md update)

## Files Created/Modified

### Created

- `analyses/audit_device_id_formats.sql` - Profiles device ID columns (GPS_ADID, ADID, IDFV, IDFA) across Adjust iOS/Android install tables with population percentages, length distribution, UUID format validation, uppercase/lowercase analysis, and sample values per column. Includes cross-platform summary comparing iOS (IDFV-primary) vs Android (GPS_ADID-primary) identifier strategies.

- `analyses/amplitude_device_id_investigation.sql` - Investigates Amplitude DEVICE_ID format by platform to determine if Android uses random IDs or GPS_ADID. Checks for Android 'R' suffix pattern (trailing R on device IDs), validates UUID format before/after stripping R, searches for ADID/advertising ID columns in EVENTS table, profiles MERGE_IDS table structure and content, and cross-checks if any Amplitude device IDs match Adjust GPS_ADID.

- `analyses/baseline_match_rates.sql` - Calculates device ID match rates between Adjust and Amplitude by platform and match strategy: Android GPS_ADID (direct and R-stripped), iOS IDFV, iOS IDFA (ATT-limited), iOS MTA touchpoint IDFA matching, and current production device_mapping model state. Establishes "before" baseline for Phase 3 normalization validation.

- `analyses/README.md` - Comprehensive documentation for audit queries including purpose (Phase 2 investigation tools), run instructions (dbt Cloud IDE and Snowflake worksheet), query file descriptions with expected output and run time, result capture workflow, troubleshooting guide (permissions, timeouts, empty results), and next steps for findings documentation.

## Decisions Made

1. **Fully qualified table names over dbt refs:** All queries use `DATABASE.SCHEMA.TABLE` format (e.g., `ADJUST.S3_DATA.IOS_ACTIVITY_INSTALL`) instead of dbt `source()` or `ref()` functions. This allows queries to be copied and pasted directly into Snowflake or dbt Cloud IDE SQL runner without dbt compilation. Trade-off: Queries are not DRY and won't benefit from source definition changes, but gain immediate executability for investigation workflow.

2. **30-60 day lookback scope:** Audit queries filter to recent data (30 days for Amplitude investigation, 60 days for Adjust profiling and match rates) to balance sample size with query performance. Sufficient for format validation and baseline metrics while avoiding timeouts on large tables. Trade-off: Not a full historical audit, but adequate for establishing current-state patterns.

3. **Android R-stripped match included:** Baseline match rate query tests both direct GPS_ADID match and GPS_ADID match after stripping trailing 'R' from Amplitude device IDs. This validates the existing normalization hypothesis (current code strips R suffix) and will establish if R-stripping is the solution or if Android uses random IDs entirely. Expected result: 0% match on both strategies if Amplitude uses random IDs.

4. **iOS IDFA match rate despite known limitations:** Included iOS IDFA match rate calculation even though research indicates Amplitude uses IDFV (not IDFA) and ATT consent limits IDFA to ~3% of installs. This documents the baseline for stakeholder communication about iOS MTA structural limitations and confirms that low iOS touchpoint match rates are ATT-related, not a normalization bug.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. All queries written with expected format based on source schema definitions and existing staging model patterns.

## User Setup Required

None - no external service configuration required. Queries are ready to run in Snowflake or dbt Cloud IDE with existing read access to Adjust and Amplitude source tables.

## Next Phase Readiness

**Ready for Plan 02-02 (Run audit queries and document findings):**
- 3 SQL audit queries complete and ready to execute
- README provides clear run instructions for dbt Cloud IDE and Snowflake worksheet
- Query output will populate `.planning/phases/02-device-id-audit/findings/` directory
- Baseline match rates will establish "before" metrics for Phase 3 validation

**Key questions these queries will answer:**
1. What is the actual format of Amplitude Android DEVICE_ID? (Random ID vs GPS_ADID)
2. What is the prevalence of the 'R' suffix on Android device IDs? (0%, 50%, 100%?)
3. Do any Amplitude device IDs match Adjust GPS_ADID directly? (Expected: 0% if random IDs)
4. What is the current iOS IDFV match rate? (Expected: 30-50% if IDFV = Amplitude device_id)
5. What is the iOS IDFA availability rate? (Expected: ~3% due to ATT consent)

**No blockers.** Queries are self-contained and do not depend on any dbt model outputs. Can be run immediately in any Snowflake environment with read access to source tables.

---
*Phase: 02-device-id-audit*
*Completed: 2026-02-11*

## Self-Check: PASSED

All files created:
- analyses/audit_device_id_formats.sql
- analyses/amplitude_device_id_investigation.sql
- analyses/baseline_match_rates.sql
- analyses/README.md

All commits verified:
- 125bae5 (Task 1)
- e701819 (Task 2)
