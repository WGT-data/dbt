# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-10)

**Core value:** Accurately attribute user acquisition spend to downstream revenue by connecting ad touchpoints to in-app behavior across Adjust and Amplitude.
**Current focus:** Phase 2 - Device ID Audit & Documentation

## Current Position

Phase: 2 of 6 (Device ID Audit & Documentation)
Plan: 1 of 3 (Device ID Audit Queries)
Status: In progress
Last activity: 2026-02-11 — Completed 02-01-PLAN.md (Device ID Audit Queries)

Progress: [███░░░░░░░] 30% (Phase 1: 100% complete - 2/2 plans done, Phase 2: 33% complete - 1/3 plans done)

## Performance Metrics

**Velocity:**
- Total plans completed: 3
- Average duration: 3.0 min
- Total execution time: 0.15 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-test-foundation | 2/2 | 5 min | 2.5 min |
| 02-device-id-audit | 1/3 | 4 min | 4.0 min |

**Recent Trend:**
- Last 5 plans: 01-01 (2min), 01-02 (3min), 02-01 (4min)
- Trend: Consistent velocity, Phase 2 plans slightly longer (documentation-focused)

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Pre-v1.0: Flip `generate_schema_name` to check `dev` instead of `prod` (fixed stale S3 activity tables)
- Pre-v1.0: Create network-level MTA mart without CAMPAIGN_NAME dimension (partner-level reporting primary use case)
- 01-01: Use 60-day lookback for all test filters (balances data quality coverage with test execution performance)
- 01-01: Test only primary keys and constrained columns (PLATFORM) to avoid test bloat
- 01-01: Use model-specific timestamp columns in where filters (INSTALL_TIMESTAMP, TOUCHPOINT_TIMESTAMP, FIRST_SEEN_AT, EVENT_TIME)
- 01-02: Use severity: warn for device_mapping relationships test (iOS IDFA match rate ~1.4% due to ATT, Android mapping broken until Phase 3)
- 02-01: Use fully qualified Snowflake table names (not dbt refs) for audit queries to enable direct execution in Snowflake/dbt Cloud IDE without compilation
- 02-01: Scope audit queries to 30-60 day lookback for performance while maintaining sufficient sample size
- 02-01: Profile both direct match and R-stripped match for Android GPS_ADID to test Amplitude normalization hypothesis
- 02-01: Include iOS IDFA match rate investigation despite known ATT limitations to document baseline

### Known Technical Context

- Android `ANDROID_EVENTS` has GPS_ADID (90% populated), ADID (100%), IDFA (touchpoints = GPS_ADID), IDFV (0%). None match Amplitude device_id currently.
- iOS IDFV = Amplitude device_id (confirmed). MTA touchpoint match rate 1.4% (53/3,925 iOS devices, Jan 2026).
- `ADJUST_AMPLITUDE_DEVICE_MAPPING` static table: 1.55M rows, stale since Nov 2025.
- SANs (Meta, Google, Apple, TikTok) will never have MTA data (no touchpoint sharing).

### Pending Todos

[From .planning/todos/pending/ — ideas captured during sessions]

None yet.

### Blockers/Concerns

[Issues that affect future work]

None yet.

## Session Continuity

Last session: 2026-02-11T17:34:40Z (plan execution)
Stopped at: Completed 02-01-PLAN.md (Device ID Audit Queries)
Resume file: None
