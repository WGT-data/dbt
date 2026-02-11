# State

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-02-10 — Milestone v1.0 started

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-10)

**Core value:** Accurately attribute user acquisition spend to downstream revenue by connecting ad touchpoints to in-app behavior across Adjust and Amplitude.
**Current focus:** Data integrity — device mapping fixes + data quality guardrails

## Accumulated Context

- Android `ANDROID_EVENTS` table has GPS_ADID (90% populated), ADID (100%), IDFA (touchpoints only, = GPS_ADID), IDFV (0%). None match Amplitude device_id.
- iOS IDFV = Amplitude device_id (confirmed). Match rate for MTA touchpoint devices is 1.4% (53/3,925 iOS devices, Jan 2026).
- `ADJUST_AMPLITUDE_DEVICE_MAPPING` static table has 1.55M rows, covers both iOS (484) and Android (344) matches to Amplitude. ADJUST_IDFV = AMPLITUDE_DEVICE_ID (identical values). Stale since Nov 2025.
- `ADJUST_INSTALLS` table has IDFV but only iOS data (no Android network names). Also stale since Nov 2025.
- SANs (Meta, Google, Apple, TikTok) will never have MTA data — no touchpoint sharing.
- Schema routing fixed: `generate_schema_name` checks `target.name == 'dev'` (not 'prod').
- S3 activity splitter models now write to correct `S3_DATA` schema in production.
