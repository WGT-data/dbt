# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-11)

**Core value:** Accurately attribute user acquisition spend to downstream revenue by connecting ad touchpoints to in-app behavior across Adjust and Amplitude.
**Current focus:** Phase 6 - Source Freshness & Observability

## Current Position

Phase: 6 of 6 complete (06-source-freshness-observability)
Plan: 1 of 1 complete
Status: All phases complete — milestone v1.0 ready for completion
Last activity: 2026-02-12 — Completed 06-01-PLAN.md (source freshness monitoring + dbt Cloud job)

Progress: [██████████] 100% (Phase 1: 100%, Phase 2: 100%, Phase 3: 100%, Phase 4: 100%, Phase 5: 100%, Phase 6: 100%)

## Performance Metrics

**Velocity:**
- Total plans completed: 12
- Average duration: 5.8 min
- Total execution time: 1.1 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-test-foundation | 2/2 | 5 min | 2.5 min |
| 02-device-id-audit | 2/2 | 16 min | 8.0 min |
| 03-mta-limitations-mmm-foundation | 3/3 | 18 min | 6.0 min |
| 04-dry-refactor | 1/1 | 2 min | 2.0 min |
| 05-mmm-pipeline-hardening-expand-test-coverage | 2/2 | 31 min | 15.5 min |
| 06-source-freshness-observability | 1/1 | 8 min | 8.0 min |

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
- Milestone: Phases 4-6 redefined for MMM-first strategy (DRY refactor, MMM hardening + testing, source freshness)
- Milestone: TEST-06/07/08 redefined for MMM context (date spine, cross-layer, zero-fill) replacing MTA-specific tests
- 04-01: Extract AD_PARTNER CASE logic into reusable macro to eliminate duplication between installs and touchpoints models
- 04-01: Add Tapjoy LIKE pattern to fix coverage gap (was falling to 'Other')
- 04-01: Add TikTok_Paid_Ads_Android to TikTok IN list to fix Android TikTok attribution gap
- 04-01: Use whitespace-stripped Jinja syntax ({%- -%}) for clean compiled SQL output
- 05-01: Date spine completeness test generates expected grid from active channels and validates every date+channel+platform exists
- 05-01: Cross-layer consistency test aggregates at DATE+PLATFORM grain and filters mart to HAS_*_DATA=1 to exclude zero-filled rows
- 05-01: Zero-fill integrity test only checks metric > 0 with flag = 0 violations (not zero metrics with flag = 1, which are valid)
- 05-01: Network mapping analysis scopes to last 90 days with actual spend/revenue/installs to find active unmapped partners
- 05-02: Filter revenue model to PLATFORM IN ('iOS', 'Android') — non-mobile platforms excluded (no corresponding spend/install data for MMM)
- 05-02: Adjust API installs do NOT include SKAN — verified empirically (API ≈ S3, SKAN is additive ~15-20%)
- 05-02: Add SKAN installs to iOS counts via UNION ALL + SUM — S3 and SKAN are non-overlapping sources
- 05-02: Use self-referencing date spine test instead of independent date generation — avoids Snowflake date type comparison issues
- 06-01: Use TO_TIMESTAMP(CREATED_AT) for S3 tables — CREATED_AT is epoch seconds
- 06-01: Use CAST(DAY AS TIMESTAMP) for API table — DAY is DATE type, dbt freshness requires TIMESTAMP
- 06-01: Omit loaded_at_field for Amplitude — metadata-based freshness via INFORMATION_SCHEMA.TABLES.LAST_ALTERED
- 06-01: S3 tables: warn 12h, error 24h; API: warn 30h, error 48h; Amplitude: warn 6h, error 12h

### Known Technical Context

- **Android CRITICAL:** Amplitude DEVICE_ID is a random SDK-generated UUID, NOT GPS_ADID. 0% match rate is structural, not a bug. 70% of Android Amplitude device IDs have 'R' suffix (random marker). No advertising ID columns exist in Amplitude data share.
- **iOS WORKING:** IDFV = Amplitude device_id (confirmed). 69.78% match rate (56,842/81,463 devices). UPPER() normalization is correct.
- **iOS IDFA:** 7.37% of iOS installs have IDFA (ATT consent). IDFA cannot match Amplitude (uses IDFV). Touchpoint IDFA availability 7.27%.
- **Android installs:** GPS_ADID 90.51% populated (76,159/84,145), lowercase UUID format.
- **Amplitude MERGE_IDS:** Contains only internal numeric ID merges (2.28M rows). Not useful for cross-system mapping.
- **Static mapping table:** `ADJUST_AMPLITUDE_DEVICE_MAPPING` (1.55M rows, stale Nov 2025) maps IDFV-to-IDFV only. iOS only. Redundant.
- **dbt device mapping model:** `int_adjust_amplitude__device_mapping` never built to production.
- SANs (Meta, Google, Apple, TikTok) will never have MTA data (no touchpoint sharing).
- **MMM pipeline validated:** 3 intermediate models + 2 mart models running in dbt Cloud. All 29 tests pass.
- **SKAN integrated:** iOS install counts now include SKAdNetwork postbacks (~15-20% additional installs from non-ATT users).
- **Revenue model scoped:** Only iOS/Android platforms included. Non-mobile (windows $48K, server, macos) excluded — no corresponding spend/install data for MMM.
- **Source freshness configured:** All 16 sources monitored via dbt Cloud job (every 6h). Adjust S3 currently stale (expected). Amplitude passing. Staleness test for static mapping table active.

### Pending Todos

[From .planning/todos/pending/ — ideas captured during sessions]

None yet.

### Blockers/Concerns

- **No technical blockers:** MMM pipeline fully validated in dbt Cloud with all tests passing.

## Session Continuity

Last session: 2026-02-12
Stopped at: All 6 phases complete — milestone v1.0 ready for completion
Resume file: None
