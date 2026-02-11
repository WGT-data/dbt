# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-10)

**Core value:** Accurately attribute user acquisition spend to downstream revenue by connecting ad touchpoints to in-app behavior across Adjust and Amplitude.
**Current focus:** Phase 1 - Test Foundation

## Current Position

Phase: 1 of 6 (Test Foundation)
Plan: 2 of 2 (Intermediate Layer Tests)
Status: Phase complete
Last activity: 2026-02-10 — Completed 01-02-PLAN.md (Intermediate Layer Test Foundation)

Progress: [██░░░░░░░░] 20% (Phase 1: 100% complete - 2/2 plans done)

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: 2.5 min
- Total execution time: 0.08 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-test-foundation | 2/2 | 5 min | 2.5 min |

**Recent Trend:**
- Last 5 plans: 01-01 (2min), 01-02 (3min)
- Trend: Consistent velocity

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

Last session: 2026-02-11T01:00:31Z (plan execution)
Stopped at: Completed 01-02-PLAN.md (Intermediate Layer Test Foundation)
Resume file: None
