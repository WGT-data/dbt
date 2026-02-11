# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-11)

**Core value:** Accurately attribute user acquisition spend to downstream revenue by connecting ad touchpoints to in-app behavior across Adjust and Amplitude.
**Current focus:** Redefining Phases 4-7 for MMM-first strategy after Phase 3 pivot

## Current Position

Phase: Redefining roadmap (Phases 4-7)
Plan: —
Status: Defining requirements and roadmap for remaining v1.0 work
Last activity: 2026-02-11 — Redefined v1.0 requirements for MMM pivot

Progress: [██████░░░░] 60% (Phase 1: 100%, Phase 2: 100%, Phase 3: 100%, Phases 4-7: defining)

## Performance Metrics

**Velocity:**
- Total plans completed: 8
- Average duration: 4.9 min
- Total execution time: 0.65 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-test-foundation | 2/2 | 5 min | 2.5 min |
| 02-device-id-audit | 2/2 | 16 min | 8.0 min |
| 03-mta-limitations-mmm-foundation | 3/3 | 18 min | 6.0 min |

**Recent Trend:**
- Last 5 plans: 01-02 (3min), 02-01 (4min), 02-02 (12min), 03-01 (3min), 03-02 (11min), 03-03 (2min)
- Trend: Phase 3 complete (6.0 min avg) - mix of research/docs and implementation

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
- 03-01: MTA development work formally closed — cannot serve strategic budget allocation
- 03-01: Existing MTA models preserved (not deleted) for iOS-only tactical analysis with limitation headers
- 03-01: MMM (Marketing Mix Modeling) is the recommended strategic alternative for budget allocation
- 03-01: Android MTA fix requires external dependency (Amplitude SDK reconfiguration) — documented without timeline pressure
- 03-02: Use incremental materialization for MMM intermediate models (spend, installs, revenue aggregations)
- 03-02: Aggregate by DATE+PLATFORM+CHANNEL grain (no campaign-level detail needed for MMM)
- 03-02: Use network_mapping seed for consistent AD_PARTNER taxonomy across data sources
- 03-02: Use S3 device-level installs (not API installs) for accuracy in MMM install counts
- 03-02: Use Adjust API revenue (not user cohort metrics) to avoid device mapping dependency
- 03-03: Use hardcoded start_date='2024-01-01' in date spine (not CROSS JOIN for date bounds)
- 03-03: Materialize marts as 'table' not 'incremental' since date spine requires full grid regeneration
- 03-03: COALESCE all metrics to 0 for gap-free time series (critical for MMM regression)
- 03-03: Weekly rollup recomputes KPIs from weekly totals (not averaged from daily KPIs)
- 03-03: Add data quality flags (HAS_SPEND_DATA, etc.) to distinguish zero-filled from missing data
- Milestone: Continue v1.0 with redefined Phases 4-7 (DRY refactor, MMM hardening, expanded tests, source freshness)
- Milestone: TEST-06/07/08 redefined for MMM context (date spine, cross-layer, zero-fill) replacing MTA-specific tests

### Known Technical Context

- **Android CRITICAL:** Amplitude DEVICE_ID is a random SDK-generated UUID, NOT GPS_ADID. 0% match rate is structural, not a bug. 70% of Android Amplitude device IDs have 'R' suffix (random marker). No advertising ID columns exist in Amplitude data share.
- **iOS WORKING:** IDFV = Amplitude device_id (confirmed). 69.78% match rate (56,842/81,463 devices). UPPER() normalization is correct.
- **iOS IDFA:** 7.37% of iOS installs have IDFA (ATT consent). IDFA cannot match Amplitude (uses IDFV). Touchpoint IDFA availability 7.27%.
- **Android installs:** GPS_ADID 90.51% populated (76,159/84,145), lowercase UUID format.
- **Amplitude MERGE_IDS:** Contains only internal numeric ID merges (2.28M rows). Not useful for cross-system mapping.
- **Static mapping table:** `ADJUST_AMPLITUDE_DEVICE_MAPPING` (1.55M rows, stale Nov 2025) maps IDFV-to-IDFV only. iOS only. Redundant.
- **dbt device mapping model:** `int_adjust_amplitude__device_mapping` never built to production.
- SANs (Meta, Google, Apple, TikTok) will never have MTA data (no touchpoint sharing).
- **MMM pipeline built:** 3 intermediate models + 2 mart models, independent of device matching. Uses Adjust API revenue.

### Pending Todos

[From .planning/todos/pending/ — ideas captured during sessions]

None yet.

### Blockers/Concerns

- **No technical blockers:** MMM pipeline built locally, needs dbt Cloud validation.
- **Network mapping coverage unknown:** Need to verify network_mapping seed covers all active partners in source data.

## Session Continuity

Last session: 2026-02-11
Stopped at: Redefining v1.0 roadmap (Phases 4-7) after MMM pivot
Resume file: None (roadmap creation in progress)
