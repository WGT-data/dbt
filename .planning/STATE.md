# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-10)

**Core value:** Accurately attribute user acquisition spend to downstream revenue by connecting ad touchpoints to in-app behavior across Adjust and Amplitude.
**Current focus:** Phase 2 complete — ready for Phase 3 (Device ID Normalization Fix)

## Current Position

Phase: 3 of 6 (MTA Limitations & MMM Foundation) — IN PROGRESS
Plan: 2 of 2 (all plans done for Phase 3)
Status: Phase 3 complete, ready for Phase 4 planning
Last activity: 2026-02-11 — Completed 03-02-PLAN.md (Create MMM intermediate models)

Progress: [██████░░░░] 60% (Phase 1: 100% complete - 2/2 plans, Phase 2: 100% complete - 2/2 plans, Phase 3: 100% complete - 2/2 plans)

## Performance Metrics

**Velocity:**
- Total plans completed: 6
- Average duration: 4.2 min
- Total execution time: 0.42 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-test-foundation | 2/2 | 5 min | 2.5 min |
| 02-device-id-audit | 2/2 | 16 min | 8.0 min |
| 03-mta-limitations-mmm-foundation | 2/2 | 4 min | 2.0 min |

**Recent Trend:**
- Last 5 plans: 01-02 (3min), 02-01 (4min), 02-02 (12min), 03-01 (2min), 03-02 (2min)
- Trend: Phase 3 implementation plans very fast (2min avg) - straightforward model creation

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
- 02-01: Use fully qualified Snowflake table names (not dbt refs) for audit queries
- 02-01: Scope audit queries to 30-60 day lookback for performance
- 02-01: Profile both direct match and R-stripped match for Android GPS_ADID
- 02-02: Android device matching cannot be fixed via dbt normalization — requires Amplitude SDK change
- 02-02: iOS IDFV match rate (69.78%) is the correct iOS metric, not IDFA (0%)
- 02-02: Phase 3 must pivot from "fix normalization" to "investigate alternative matching strategies"
- 02-02: Recommend investigating USER_ID bridge as potential interim Android solution
- 03-02: Use Adjust API pre-aggregated revenue (stg_adjust__report_daily) rather than user-level cohort pipeline to avoid dependency on broken device mapping
- 03-02: Accept event-date-based revenue (not install-cohort-based) as acceptable tradeoff for MMM statistical modeling
- 03-02: Use Supermetrics as single source of truth for spend to avoid double-counting with Adjust API cost data
- 03-02: Use device-level S3 install counts (v_stg_adjust__installs) rather than API aggregates for accuracy

### Known Technical Context

- **Android CRITICAL:** Amplitude DEVICE_ID is a random SDK-generated UUID, NOT GPS_ADID. 0% match rate is structural, not a bug. 70% of Android Amplitude device IDs have 'R' suffix (random marker). No advertising ID columns exist in Amplitude data share.
- **iOS WORKING:** IDFV = Amplitude device_id (confirmed). 69.78% match rate (56,842/81,463 devices). UPPER() normalization is correct.
- **iOS IDFA:** 7.37% of iOS installs have IDFA (ATT consent). IDFA cannot match Amplitude (uses IDFV). Touchpoint IDFA availability 7.27%.
- **Android installs:** GPS_ADID 90.51% populated (76,159/84,145), lowercase UUID format.
- **Amplitude MERGE_IDS:** Contains only internal numeric ID merges (2.28M rows). Not useful for cross-system mapping.
- **Static mapping table:** `ADJUST_AMPLITUDE_DEVICE_MAPPING` (1.55M rows, stale Nov 2025) maps IDFV-to-IDFV only. iOS only. Redundant.
- **dbt device mapping model:** `int_adjust_amplitude__device_mapping` never built to production.
- SANs (Meta, Google, Apple, TikTok) will never have MTA data (no touchpoint sharing).

### Pending Todos

[From .planning/todos/pending/ — ideas captured during sessions]

None yet.

### Blockers/Concerns

- **Android MTA blocked on external dependency:** Amplitude SDK must be configured with `useAdvertisingIdForDeviceId()` by mobile engineering team. This is outside dbt scope.
- **MTA-to-MMM pivot complete:** Phase 3 pivoted from "fix normalization" to "build MMM foundation independent of device mapping". MMM pipeline now uses Adjust API pre-aggregated revenue (no device mapping dependency).

## Session Continuity

Last session: 2026-02-11
Stopped at: Phase 3 complete. Ready for Phase 4 planning (MMM daily summary mart).
Resume file: None (Phase 3 fully complete)
