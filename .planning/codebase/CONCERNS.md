# Codebase Concerns

**Analysis Date:** 2026-01-19

## Tech Debt

**Duplicated AD_PARTNER Mapping Logic:**
- Issue: The same CASE WHEN network-to-partner mapping logic is duplicated in two files
- Files: `models/staging/adjust/v_stg_adjust__installs.sql` (lines 52-70), `models/staging/adjust/v_stg_adjust__touchpoints.sql` (lines 122-140)
- Impact: Changes to partner mappings require updates in multiple places; risk of drift between definitions
- Fix approach: Extract to a macro or create a reference table (similar to `seeds/network_mapping.csv`) that both staging models join to

**Hardcoded Date Filters:**
- Issue: Multiple staging models have hardcoded `WHERE ... >= '2025-01-01'` clauses filtering out historical data
- Files: `models/staging/adjust/v_stg_adjust__touchpoints.sql` (lines 33, 55, 78, 100), `models/staging/amplitude/v_stg_amplitude__events.sql` (line 18), `models/staging/amplitude/v_stg_amplitude__merge_ids.sql` (line 21), `models/staging/revenue/v_stg_revenue__events.sql` (line 17)
- Impact: Historical analysis impossible; date boundary not configurable; silently drops data
- Fix approach: Move date filter to a dbt variable (`var('min_date')`) or remove entirely and rely on incremental lookback windows

**Inconsistent Device ID Casing:**
- Issue: Device IDs require UPPER() normalization scattered across multiple models
- Files: `models/staging/adjust/v_stg_adjust__touchpoints.sql` (lines 19, 64), `models/staging/amplitude/v_stg_amplitude__merge_ids.sql` (lines 50-55), `models/intermediate/int_user_cohort__attribution.sql` (lines 18, 32)
- Impact: Join failures if casing is inconsistent; logic spread across codebase makes it hard to audit
- Fix approach: Apply UPPER() transformation once at the staging layer for all device ID sources; document the convention

**Android 'R' Suffix Workaround:**
- Issue: Android device IDs from Amplitude have trailing 'R' that must be stripped to match Adjust
- Files: `models/staging/amplitude/v_stg_amplitude__merge_ids.sql` (lines 50-55)
- Impact: Undocumented data quirk; if Amplitude changes format, joins will break silently
- Fix approach: Document this behavior in the model YML; add data quality test to verify format

**v_stg_adjust__installs Uses Direct Source References:**
- Issue: This staging model references sources directly with full paths (`ADJUST_S3.PROD_DATA.IOS_ACTIVITY_INSTALL`) instead of using `{{ source() }}` macro
- Files: `models/staging/adjust/v_stg_adjust__installs.sql` (lines 14, 32)
- Impact: No lineage tracking; source freshness checks won't work; inconsistent with other staging models
- Fix approach: Replace hardcoded references with `{{ source('adjust', 'IOS_ACTIVITY_INSTALL') }}`

**v_stg_adjust__installs Missing Incremental Logic:**
- Issue: Unlike `v_stg_adjust__touchpoints`, this model has no `{{ config(materialized='incremental') }}` or incremental filtering
- Files: `models/staging/adjust/v_stg_adjust__installs.sql`
- Impact: Full table scan on every run; performance will degrade as data grows
- Fix approach: Add incremental config with INSTALL_TIMESTAMP or LOAD_TIMESTAMP based lookback

## Known Bugs

**Potential Revenue Double-Counting in int_user_cohort__metrics:**
- Symptoms: Revenue from Amplitude events may be attributed differently than from the dedicated revenue source
- Files: `models/intermediate/int_user_cohort__metrics.sql` (uses `source('amplitude', 'EVENTS_726530')`), vs `models/intermediate/int_revenue__user_summary.sql` (uses `source('revenue', 'DIRECT_REVENUE_EVENTS')`)
- Trigger: If the same revenue events exist in both sources with different event properties
- Workaround: The models appear to be used for different purposes, but overlap should be audited

**FULL OUTER JOIN Can Create Orphan Rows:**
- Symptoms: Rows with NULL campaign/date values when spend exists but no attribution, or vice versa
- Files: `models/marts/attribution/mart_campaign_performance_full.sql` (line 199), `models/marts/attribution/mta__campaign_performance.sql` (line 219), `models/marts/attribution/attribution__campaign_performance.sql` (line 121)
- Trigger: Spend data with campaigns not tracked in Adjust; attribution with campaigns not in Supermetrics
- Workaround: WHERE DATE IS NOT NULL filter at end; orphan data is effectively hidden

## Security Considerations

**Source Database Credentials:**
- Risk: Multiple databases referenced (ADJUST_S3, AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE, SUPERMETRICS, WGT) require proper access controls
- Files: `models/staging/adjust/_adjust__sources.yml`, `models/staging/amplitude/_amplitude__sources.yml`, `models/staging/supermetrics/_supermetrics__sources.yml`, `models/staging/revenue/_revenue__sources.yml`
- Current mitigation: Credentials managed at profile level in dbt
- Recommendations: Ensure service account has read-only access; audit database permissions regularly

**No PII Handling Documentation:**
- Risk: USER_ID, DEVICE_ID fields potentially contain identifiable data
- Files: All intermediate and mart models
- Current mitigation: None visible
- Recommendations: Document PII classification; consider hashing or masking if required by policy

## Performance Bottlenecks

**Large CTE Chains in mart_campaign_performance_full:**
- Problem: 324-line model with 6+ CTEs, FULL OUTER JOINs, and window functions
- Files: `models/marts/attribution/mart_campaign_performance_full.sql`
- Cause: Complex multi-source join with aggregations at multiple levels
- Improvement path: Consider breaking into intermediate models; materialize expensive CTEs as tables

**int_user_cohort__metrics Re-Processes Entire User History:**
- Problem: For each user in the lookback window, all their revenue events are re-aggregated
- Files: `models/intermediate/int_user_cohort__metrics.sql` (lines 91-184)
- Cause: Revenue and retention calculated from raw events each time
- Improvement path: Pre-aggregate daily user metrics; use merge_update_columns more granularly

**Expensive Window Functions in int_mta__user_journey:**
- Problem: Multiple ROW_NUMBER() and COUNT(*) OVER() on touchpoint data
- Files: `models/intermediate/int_mta__user_journey.sql` (lines 88-115)
- Cause: Position calculation requires sorting all touchpoints per device
- Improvement path: Acceptable for now; monitor as data volume grows

## Fragile Areas

**network_mapping.csv Seed:**
- Files: `seeds/network_mapping.csv`
- Why fragile: Manual CSV file maps Adjust network names to Supermetrics partner IDs; any new network requires manual update
- Safe modification: Add new rows only; never remove existing mappings without verifying downstream impact
- Test coverage: None - no tests validate mapping completeness

**Campaign ID Extraction via REGEXP:**
- Files: `models/staging/adjust/v_stg_adjust__installs.sql` (lines 6-8), `models/staging/adjust/v_stg_adjust__touchpoints.sql` (lines 24, 46, 69, 91)
- Why fragile: Pattern `\\(([0-9]+)\\)$` assumes campaign names end with `(123456)` format; will return NULL if format changes
- Safe modification: Test regex changes against production data before deploying
- Test coverage: None - no tests validate extraction success rate

**Platform Case Sensitivity:**
- Files: Multiple joins compare LOWER(PLATFORM) to handle 'iOS' vs 'ios' inconsistency
- Why fragile: Inconsistent casing in source data requires defensive coding everywhere
- Safe modification: Add platform normalization to staging layer
- Test coverage: None

**Cohort Window Magic Numbers:**
- Files: Multiple models use 7, 30, 35 day windows without configuration
- Why fragile: D7/D30 retention calculations hardcoded; changing window requires multi-file edits
- Safe modification: Create dbt vars for cohort windows
- Test coverage: None

## Scaling Limits

**Amplitude Events Table:**
- Current capacity: Unknown, but appears to be queried repeatedly in multiple models
- Limit: Large event tables can cause timeout on full scans
- Scaling path: Partition by date; ensure incremental models have efficient lookback windows

**Multi-Touch Attribution Cardinality:**
- Current capacity: One row per touchpoint per install
- Limit: High-touchpoint users (100+ impressions) cause data explosion
- Scaling path: Consider touchpoint deduplication or sampling for extreme cases; `int_device_mapping__diagnostics.sql` already identifies anomalous users

## Dependencies at Risk

**No Package Dependencies:**
- Risk: Project uses no dbt packages, meaning all logic is custom
- Impact: Missing out on tested utilities (dbt-utils, dbt-expectations)
- Migration plan: Evaluate dbt_utils for testing, dbt_date for date handling

**External Data Sources:**
- Risk: Three external systems (Adjust, Amplitude, Supermetrics) each have own data pipelines
- Impact: Data freshness varies; late-arriving data handled via lookback windows
- Migration plan: Lookback windows (3-7 days) already implemented; consider source freshness tests

## Missing Critical Features

**No dbt Tests:**
- Problem: `tests/` directory is empty
- Blocks: Cannot validate data quality; no regression detection
- Files: `tests/.gitkeep` (empty)

**No Documentation for Existing Models:**
- Problem: Only MTA models have YML documentation; staging/intermediate models lack schema definitions
- Blocks: Self-service analytics; onboarding new team members

**No Source Freshness Checks:**
- Problem: Sources defined but no freshness configuration
- Blocks: Alerting when upstream data pipelines fail

**No Pre-Commit Hooks or CI:**
- Problem: No visible CI/CD configuration
- Blocks: Automated testing before deploy; enforcing code standards

## Test Coverage Gaps

**Zero Unit Tests:**
- What's not tested: All business logic untested
- Files: All models in `models/`
- Risk: Schema changes, logic errors, and regressions go undetected
- Priority: High

**Missing Not-Null Tests:**
- What's not tested: Primary key columns (USER_ID, DEVICE_ID, DATE) could be NULL
- Files: All incremental models rely on unique_key which fails silently with NULLs
- Risk: Duplicate rows; incorrect merge behavior
- Priority: High

**Missing Uniqueness Tests:**
- What's not tested: Grain definitions not enforced
- Files: Every model declares unique_key but none tested
- Risk: Grain violations cause aggregation errors
- Priority: High

**Missing Referential Integrity Tests:**
- What's not tested: Foreign key relationships (e.g., USER_ID in int_user_cohort__metrics should exist in device mapping)
- Files: All joins between intermediate/mart models
- Risk: Orphan records; incorrect join results
- Priority: Medium

**Missing Accepted Values Tests:**
- What's not tested: PLATFORM should only be 'iOS' or 'Android'
- Files: All models with PLATFORM column
- Risk: Unexpected platform values cause data issues
- Priority: Medium

---

*Concerns audit: 2026-01-19*
