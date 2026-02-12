---
phase: 06-source-freshness-observability
plan: 01
subsystem: observability
tags: [dbt-source-freshness, snowflake, adjust, amplitude, monitoring]

# Dependency graph
requires:
  - phase: 05-mmm-pipeline-hardening-expand-test-coverage
    provides: Validated MMM pipeline with all tests passing
provides:
  - Source freshness monitoring for 13 Adjust S3 tables (epoch-based)
  - Source freshness monitoring for Adjust API REPORT_DAILY_RAW (date-cast)
  - Metadata-based freshness monitoring for 2 Amplitude data share tables
  - Singular test for static mapping table staleness detection
  - dbt Cloud scheduled freshness job (every 6 hours)
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [dbt-source-freshness, metadata-based-freshness, information-schema-staleness-test]

key-files:
  created:
    - tests/singular/test_adjust_amplitude_mapping_staleness.sql
  modified:
    - models/staging/adjust/_adjust__sources.yml
    - models/staging/amplitude/_amplitude__sources.yml

key-decisions:
  - "Use TO_TIMESTAMP(CREATED_AT) for S3 tables — CREATED_AT is epoch seconds"
  - "Use CAST(DAY AS TIMESTAMP) for API table — DAY is DATE type, dbt requires TIMESTAMP"
  - "Omit loaded_at_field for Amplitude — metadata-based freshness via INFORMATION_SCHEMA.TABLES.LAST_ALTERED"
  - "S3 tables: warn 12h, error 24h (real-time S3 pipeline)"
  - "API table: warn 30h, error 48h (batch-loaded, less frequent)"
  - "Amplitude: warn 6h, error 12h (data share, very fresh)"

patterns-established:
  - "Epoch timestamp freshness: TO_TIMESTAMP(column) for loaded_at_field"
  - "Date-to-timestamp cast: CAST(column AS TIMESTAMP) when source column is DATE type"
  - "Metadata freshness: omit loaded_at_field for Snowflake data shares"

# Metrics
duration: 8min
completed: 2026-02-12
---

# Phase 6: Source Freshness & Observability Summary

**Source freshness monitoring for all 16 data sources (Adjust S3, Adjust API, Amplitude) with dbt Cloud scheduled job and static table staleness test**

## Performance

- **Duration:** ~8 min (across checkpoint iterations)
- **Started:** 2026-02-12
- **Completed:** 2026-02-12
- **Tasks:** 3 (2 automated + 1 human checkpoint)
- **Files modified:** 3

## Accomplishments
- All 13 Adjust S3 activity tables monitored with epoch-based freshness (12h warn, 24h error)
- Adjust API REPORT_DAILY_RAW monitored with date-cast freshness (30h warn, 48h error)
- Both Amplitude data share tables monitored with metadata-based freshness (6h warn, 12h error)
- Singular test detects ADJUST_AMPLITUDE_DEVICE_MAPPING staleness >30 days via INFORMATION_SCHEMA
- dbt Cloud job configured and verified — all 16 sources report valid freshness status

## Task Commits

Each task was committed atomically:

1. **Task 1: Configure source freshness for Adjust and Amplitude sources** - `e7514ab` (feat)
2. **Task 2: Create singular test for static mapping table staleness** - `f4d3dc9` (test)
3. **Task 3: Configure dbt Cloud source freshness job** - Human checkpoint (verified in dbt Cloud)

**Hotfix:** `25af895` — Cast DAY to TIMESTAMP for Adjust API freshness (DATE type incompatible with dbt freshness)

## Files Created/Modified
- `models/staging/adjust/_adjust__sources.yml` - Added freshness config for both source groups (adjust + adjust_api_data)
- `models/staging/amplitude/_amplitude__sources.yml` - Added metadata-based freshness config
- `tests/singular/test_adjust_amplitude_mapping_staleness.sql` - New singular test for static table staleness

## Decisions Made
- **CAST(DAY AS TIMESTAMP)** instead of raw `DAY` for API source — dbt source freshness requires TIMESTAMP type, DAY column is DATE
- **Metadata-based freshness** (no loaded_at_field) for Amplitude — data share has no timestamp columns, dbt falls back to INFORMATION_SCHEMA.TABLES.LAST_ALTERED
- **Source-level freshness** (not table-level) — cascades to all tables within each source group, reducing YAML duplication

## Deviations from Plan

### Auto-fixed Issues

**1. CAST(DAY AS TIMESTAMP) for Adjust API freshness**
- **Found during:** Task 3 (dbt Cloud verification)
- **Issue:** `loaded_at_field: "DAY"` returned DATE type, dbt expected TIMESTAMP — error: "Expected a timestamp value but received value of type 'date'"
- **Fix:** Changed to `loaded_at_field: "CAST(DAY AS TIMESTAMP)"`
- **Files modified:** models/staging/adjust/_adjust__sources.yml
- **Verification:** Re-ran dbt Cloud job, REPORT_DAILY_RAW now reports `ERROR STALE` (valid status, not type error)
- **Committed in:** `25af895`

---

**Total deviations:** 1 auto-fixed (type mismatch)
**Impact on plan:** Necessary fix for correctness. No scope creep.

## Issues Encountered
- First dbt Cloud run returned "Nothing to do" — changes hadn't been pushed to origin. Resolved by pushing commits.
- PropertyMovedToConfigDeprecation warnings (5 occurrences) — `freshness` as top-level source property is deprecated in dbt 2026.x, should be under `config`. Non-blocking warning, functionality works.

## User Setup Required
None beyond the already-configured dbt Cloud job.

## Next Phase Readiness
- This is the final phase of milestone v1.0 — all 6 phases complete
- Ready for milestone completion (`/gsd:complete-milestone`)

---
*Phase: 06-source-freshness-observability*
*Completed: 2026-02-12*
