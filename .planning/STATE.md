# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-10)

**Core value:** Accurately attribute user acquisition spend to downstream revenue by connecting ad touchpoints to in-app behavior across Adjust and Amplitude.
**Current focus:** Phase 1 - Test Foundation

## Current Position

Phase: 1 of 6 (Test Foundation)
Plan: None yet (ready to plan)
Status: Ready to plan
Last activity: 2026-02-10 — Roadmap created for v1.0 Data Integrity milestone

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: N/A
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: None yet
- Trend: N/A

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Pre-v1.0: Flip `generate_schema_name` to check `dev` instead of `prod` (fixed stale S3 activity tables)
- Pre-v1.0: Create network-level MTA mart without CAMPAIGN_NAME dimension (partner-level reporting primary use case)

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

Last session: 2026-02-10 (roadmap creation)
Stopped at: Roadmap and STATE files created for v1.0 milestone
Resume file: None
