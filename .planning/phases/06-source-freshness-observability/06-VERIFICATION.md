---
phase: 06-source-freshness-observability
verified: 2026-02-12T22:11:08Z
status: passed
score: 5/5 must-haves verified
re_verification:
  previous_status: human_needed
  previous_score: 4/5
  previous_date: 2026-02-12T22:09:04Z
  gaps_closed:
    - "Source freshness runs as a separate scheduled job in dbt Cloud (not embedded in build jobs)"
  gaps_remaining: []
  regressions: []
---

# Phase 6: Source Freshness & Observability Verification Report

**Phase Goal:** Add production monitoring and freshness checks
**Verified:** 2026-02-12T22:11:08Z
**Status:** passed
**Re-verification:** Yes — human verification checkpoint completed

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | dbt source freshness reports pass/warn/error status for all 13 Adjust S3 activity tables | ✓ VERIFIED | Adjust source group has freshness config (warn 12h, error 24h) with `TO_TIMESTAMP(CREATED_AT)` at source level, cascading to all 13 tables |
| 2 | dbt source freshness reports pass/warn/error status for Adjust API REPORT_DAILY_RAW table | ✓ VERIFIED | adjust_api_data source has freshness config (warn 30h, error 48h) with `CAST(DAY AS TIMESTAMP)` |
| 3 | dbt source freshness reports pass/warn/error status for both Amplitude data share tables | ✓ VERIFIED | Amplitude source has freshness config (warn 6h, error 12h) with metadata-based approach (no loaded_at_field) |
| 4 | Singular test detects when ADJUST_AMPLITUDE_DEVICE_MAPPING table is stale (>30 days since LAST_ALTERED) | ✓ VERIFIED | test_adjust_amplitude_mapping_staleness.sql queries INFORMATION_SCHEMA.TABLES.LAST_ALTERED with DATEDIFF > 30 days filter |
| 5 | Source freshness runs as a separate scheduled job in dbt Cloud (not embedded in build jobs) | ✓ VERIFIED | Summary documents human checkpoint completed: "dbt Cloud job configured and verified — all 16 sources report valid freshness status". Hotfix commit 25af895 applied after verification found DATE type issue, job re-ran successfully. |

**Score:** 5/5 truths verified (1 via documented human checkpoint completion)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `models/staging/adjust/_adjust__sources.yml` | Source freshness config for Adjust S3 and API sources | ✓ VERIFIED | 50 lines, contains 2 freshness blocks (adjust + adjust_api_data), has warn_after/error_after, has loaded_at_field for both source groups, used by 2 models (v_stg_adjust__touchpoints, v_stg_adjust__installs) |
| `models/staging/amplitude/_amplitude__sources.yml` | Source freshness config for Amplitude data share | ✓ VERIFIED | 14 lines, contains 1 freshness block, has warn_after/error_after, NO loaded_at_field (metadata-based), used by 2 models (v_stg_amplitude__merge_ids, attribution__installs) |
| `tests/singular/test_adjust_amplitude_mapping_staleness.sql` | Singular test for static mapping table staleness detection | ✓ VERIFIED | 21 lines, queries ADJUST.INFORMATION_SCHEMA.TABLES, filters on TABLE_NAME = 'ADJUST_AMPLITUDE_DEVICE_MAPPING', filters on DATEDIFF > 30 days, returns diagnostic columns (database, schema, table_name, last_altered, days_since_update, row_count, failure_reason) |

**All artifacts:** EXISTS + SUBSTANTIVE + WIRED

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `models/staging/adjust/_adjust__sources.yml` | ADJUST.S3_DATA.* | loaded_at_field with TO_TIMESTAMP(CREATED_AT) | ✓ WIRED | Pattern `TO_TIMESTAMP(CREATED_AT)` found in source config at line 11, cascades to all 13 S3 activity tables |
| `models/staging/adjust/_adjust__sources.yml` | ADJUST.API_DATA.REPORT_DAILY_RAW | loaded_at_field with DAY column | ✓ WIRED | Pattern `loaded_at_field: "CAST(DAY AS TIMESTAMP)"` found at line 47 (hotfix applied to cast DATE to TIMESTAMP) |
| `models/staging/amplitude/_amplitude__sources.yml` | AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.* | Metadata-based freshness (no loaded_at_field) | ✓ WIRED | Freshness block exists (lines 8-10), NO loaded_at_field present (confirmed via grep), falls back to INFORMATION_SCHEMA.TABLES.LAST_ALTERED |
| `tests/singular/test_adjust_amplitude_mapping_staleness.sql` | INFORMATION_SCHEMA.TABLES | LAST_ALTERED comparison | ✓ WIRED | FROM clause targets ADJUST.INFORMATION_SCHEMA.TABLES (line 19), WHERE clause filters on DATEDIFF('day', LAST_ALTERED, CURRENT_TIMESTAMP()) > 30 (line 21) |

**All key links:** WIRED

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| FRESH-01: Source freshness configured for Adjust sources with appropriate loaded_at_field or proxy timestamp | ✓ SATISFIED | Truth 1 & 2 verified: Both Adjust source groups have freshness + loaded_at_field |
| FRESH-02: Source freshness configured for Amplitude sources with appropriate loaded_at_field or proxy timestamp | ✓ SATISFIED | Truth 3 verified: Amplitude has freshness with metadata-based approach (proxy via INFORMATION_SCHEMA) |
| FRESH-03: Stale static table detection alerts when ADJUST_AMPLITUDE_DEVICE_MAPPING hasn't been refreshed in >30 days | ✓ SATISFIED | Truth 4 verified: Singular test exists and queries LAST_ALTERED with 30-day threshold |
| FRESH-04: Source freshness runs as scheduled job (separate from model builds) | ✓ SATISFIED | Truth 5 verified: Summary documents job configured with 6-hour schedule, verified in dbt Cloud |

**Coverage:** 4/4 requirements satisfied

### Anti-Patterns Found

None. All files are clean:
- No TODO/FIXME/placeholder comments
- No stub implementations
- No console.log-only code
- All files substantive (14-50 lines)
- All files actively used in project

### Re-verification Summary

**Previous verification (2026-02-12T22:09:04Z):**
- Status: human_needed
- Score: 4/5 truths verified
- Issue: Truth #5 (dbt Cloud job) required human verification

**Current verification (2026-02-12T22:11:08Z):**
- Status: passed
- Score: 5/5 truths verified
- Resolution: Summary documents human checkpoint completed in Task 3

**Gaps closed:**
1. **dbt Cloud job configuration** — Summary states "dbt Cloud job configured and verified — all 16 sources report valid freshness status" (line 66). Task 3 marked as "Human checkpoint (verified in dbt Cloud)" (line 74). Hotfix commit 25af895 was applied after verification found a DATE type compatibility issue, demonstrating actual job execution and verification occurred.

**Regressions:** None detected. All previously passing truths (1-4) still pass with identical evidence.

**Evidence of human verification:**
- Summary line 66: "dbt Cloud job configured and verified — all 16 sources report valid freshness status"
- Summary line 74: Task 3 marked as completed with human verification
- Summary line 97: Hotfix was applied after dbt Cloud verification found type mismatch
- Summary line 97: "Re-ran dbt Cloud job, REPORT_DAILY_RAW now reports `ERROR STALE` (valid status, not type error)"
- Summary line 106: "First dbt Cloud run returned 'Nothing to do' — changes hadn't been pushed to origin. Resolved by pushing commits."

This evidence demonstrates that actual dbt Cloud job execution occurred, issues were found and fixed, and the job was re-run successfully.

---

## Verification Summary

**Automated verification:** 4/5 truths verified programmatically
**Human checkpoint:** 1/5 truths verified via documented completion
**Artifacts:** All 3 files exist, are substantive (14-50 lines), and are actively used
**Key links:** All 4 critical connections verified (loaded_at_field configs, INFORMATION_SCHEMA query)
**Anti-patterns:** None detected
**Requirements:** 4/4 satisfied

**Status rationale:** All code artifacts are in place and correctly configured. Source freshness YAML files have appropriate warn/error thresholds and loaded_at_field configurations. The singular staleness test queries INFORMATION_SCHEMA correctly. The dbt Cloud job configuration (Truth #5) was documented as completed in the phase summary with evidence of actual job execution (hotfix applied after verification issues found). All 5 observable truths are now verified.

**Phase goal achieved:** Production monitoring and freshness checks are in place. All 13 Adjust S3 tables, 1 Adjust API table, and 2 Amplitude tables have source freshness monitoring configured. Static mapping table staleness detection is operational. dbt Cloud job is scheduled to run freshness checks every 6 hours.

---

_Verified: 2026-02-12T22:11:08Z_
_Verifier: Claude (gsd-verifier)_
