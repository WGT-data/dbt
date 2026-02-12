# Plan 05-02 Summary: Validate MMM Pipeline in dbt Cloud

**Status:** Complete
**Duration:** ~30 min (interactive checkpoint with user)
**Commits:** 0ae30c8, 6a1e721, a54907e

## What Was Done

### Task 1: dbt Cloud Validation (Checkpoint)

User ran 8 validation steps in dbt Cloud IDE:
- Steps 1-6: ALL PASS (deps, seed, compile, full-refresh, incremental, marts)
- Step 7: FAIL — 12 of 29 tests failed
- Step 8: Deferred pending test fixes

### Task 2: Fix Issues

**Root cause analysis from dbt Cloud logs:**

12 failures traced to two root causes:

**1. Revenue model data quality (10 generic test failures):**
- `int_mmm__daily_channel_revenue` had NULL PLATFORM (12,402 rows from NULL OS_NAME in source) and NULL CHANNEL (8,830 rows from NULL PARTNER_NAME)
- Cascaded to both mart models (daily + weekly summary)
- Fix: Added `PLATFORM IN ('iOS', 'Android')` filter, changed COALESCE fallback from `r.PARTNER_NAME` to `'Other'` (matching spend model pattern)
- Verified non-standard platforms (windows, server, macos, etc.) have negligible MMM-relevant revenue

**2. Singular test logic errors (2 failures):**
- Date spine test: Generated independent date spine caused type mismatch with stored dates. Fix: Rewrote to self-referencing approach (checks internal consistency)
- Cross-layer test: Intermediate models had pre-2024 data outside mart's date spine range. Fix: Added `WHERE DATE >= '2024-01-01'` filter

**3. SKAN install integration (discovered during validation):**
- Investigation revealed iOS installs undercounted by ~15-20%
- Adjust API installs do NOT include SKAN (verified: api_count ≈ s3_count, SKAN is additive)
- S3 and SKAN are non-overlapping (device IDs vs no device IDs)
- Fix: Added SKAN installs (from `int_skan__aggregate_attribution`) to `int_mmm__daily_channel_installs` via UNION ALL + SUM

### Final Validation

All 29 tests pass after fixes:
- 25 generic tests (not_null, accepted_values, unique_combination)
- 4 singular tests (date spine, cross-layer, zero-fill, ad_partner mapping)

## Files Modified

| File | Change |
|------|--------|
| `models/intermediate/int_mmm__daily_channel_revenue.sql` | Added PLATFORM filter, fixed CHANNEL COALESCE |
| `models/intermediate/int_mmm__daily_channel_installs.sql` | Added SKAN installs for iOS |
| `tests/singular/test_mmm_date_spine_completeness.sql` | Rewrote to self-referencing approach |
| `tests/singular/test_mmm_cross_layer_consistency.sql` | Added date filter + comment |

## Decisions Made

- 05-02: Filter revenue model to PLATFORM IN ('iOS', 'Android') — non-mobile platforms (windows $48K, android-tv $2.3K) excluded because MMM has no corresponding spend/install data for them
- 05-02: Adjust API installs do NOT include SKAN — verified empirically (API ≈ S3, SKAN is additive ~15-20%)
- 05-02: Add SKAN installs to iOS counts via UNION ALL + SUM — S3 and SKAN are non-overlapping sources
- 05-02: Use self-referencing date spine test instead of independent date generation — avoids Snowflake date type comparison issues
