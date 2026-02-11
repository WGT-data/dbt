# Project Research Summary

**Project:** WGT Golf dbt Analytics - Device Mapping Fixes & Comprehensive Testing
**Domain:** dbt Analytics Pipeline (Snowflake + Mobile Attribution)
**Researched:** 2026-02-10
**Confidence:** HIGH

## Executive Summary

This project addresses critical data quality issues in a mature dbt analytics pipeline for mobile game attribution. The core problems are (1) broken Android device ID mapping between Adjust attribution data and Amplitude analytics (preventing revenue attribution), (2) structurally low iOS match rates that are often misunderstood as bugs, and (3) zero test coverage creating hidden data quality issues. Research confirms these are common problems in mobile attribution warehouses, with well-documented solutions.

The recommended approach is incremental adoption: establish baseline data quality tests first, then carefully refactor device ID normalization with full-refresh backfills, and finally extract duplicated logic into DRY macros. The critical insight is that this project is NOT starting from scratch—it's retrofitting tests onto a production pipeline with historical data quality issues. Testing adoption must be forward-looking (validate new data first) to avoid decision paralysis from hundreds of test failures on historical data.

Key risks include: (1) changing device ID normalization in staging models breaks incremental downstream models through duplication, requiring expensive full-refreshes that invalidate 30-day cohort windows, (2) refactoring the duplicated AD_PARTNER mapping logic without consistency tests causes silent attribution mismatches, and (3) iOS match rate expectations must be managed—the 1.4% IDFA match rate is structural due to Apple's ATT consent requirements, not a data quality bug fixable through normalization. Use incremental model testing strategies, full_history_mode variables for safe backfills, and probabilistic IP-based matching for iOS rather than pursuing deterministic device ID joins.

## Key Findings

### Recommended Stack

The project should adopt the industry-standard dbt testing stack incrementally: dbt-utils 1.3.3 for basic generic tests (unique, not_null, relationships), dbt-expectations 0.10.9 (Metaplane fork) for advanced validation (regex, distributions, statistical tests), and elementary 0.22.1 for observability and anomaly detection. For device ID resolution, leverage Snowflake's native EDITDISTANCE and JAROWINKLER_SIMILARITY functions for fuzzy matching (threshold >= 85) rather than external Python UDFs. All packages are dbt Fusion compatible (support dbt 1.0-3.0 range), though dbt-expectations requires dbt >= 1.7.

**Core technologies:**
- **dbt-utils 1.3.3**: Foundation for generic tests (unique, not_null, relationships, accepted_values) and utility macros. Required dependency for other packages. Use at all model layers.
- **dbt-expectations 0.10.9**: Advanced data quality tests (regex validation, statistical analysis, multi-column logic, distribution testing). Use at intermediate/marts layers only (slower execution). Active Metaplane fork replaces deprecated original.
- **elementary 0.22.1**: Data observability with anomaly detection tests (freshness, volume, distribution, cardinality shifts). Use at marts layer for production monitoring. OSS version sufficient; includes Slack/Teams alerts.
- **Snowflake JAROWINKLER_SIMILARITY**: Built-in fuzzy string matching optimized for short device IDs. Returns 0-100 similarity score. Use threshold >= 85 for high-confidence matches when exact device ID joins fail.
- **Custom dbt macro for ID normalization**: Centralized UPPER(), TRIM(), and hyphen removal for GPS_ADID and IDFV. Critical for improving Android match rates from existing GPS_ADID data.

**Critical version requirements:**
- dbt-expectations requires dbt >= 1.7.x (upgrade dbt if on older version)
- dbt-utils 1.3.3 requires dbt >= 1.3.0 (likely already met in WGT project)

### Expected Features

Mobile attribution analytics pipelines have clear "table stakes" expectations—features users assume exist in production. The WGT project currently lacks most basic data quality features, making this a "catch-up" effort rather than greenfield development.

**Must have (table stakes):**
- **Generic schema tests** — unique + not_null on all primary keys, device IDs, and join columns. Currently missing entirely; this is unusual for production pipelines.
- **Source freshness monitoring** — Detect stale upstream data (Adjust, Amplitude) before it corrupts metrics. Use dbt's built-in source freshness with 1-hour warn thresholds.
- **Referential integrity tests** — Validate device mapping relationships (Adjust → Amplitude foreign keys). Use built-in `relationships` test.
- **Incremental model testing** — Ensure incremental models produce same results as full-refresh. Critical for device mapping which uses 7-day lookback windows.
- **Not-null constraints on join keys** — Prevent silent data loss. Apply to DEVICE_ID, USER_ID, PLATFORM in all models.

**Should have (competitive advantage):**
- **Device mapping diagnostics & alerts** — Surface anomalies (>100 devices/user, match rate < threshold) proactively. Model already exists (`int_device_mapping__diagnostics`), needs severity tests added.
- **Platform-specific validation** — Test Android GPS_ADID mapping separately from iOS IDFV (different ID types, failure modes). Android is broken (needs fix), iOS is structural (manage expectations).
- **DRY macros for reused logic** — Extract duplicated AD_PARTNER CASE statement (appears in 2 models, 18 lines each) into single macro to prevent drift.
- **Stale static table detection** — Alert when `ADJUST_AMPLITUDE_DEVICE_MAPPING` hasn't been refreshed (currently stale since Nov 2025). Low complexity, high value.
- **Cross-model consistency tests** — Validate device counts match across staging → intermediate → marts. Detects silent data loss from join issues.

**Defer (v2+):**
- **dbt-expectations advanced tests** — Useful but not blocking. Add after core testing framework stabilizes.
- **Data quality dashboards** — BI tool integration for test result trends. dbt Cloud test UI sufficient for now.
- **Automated backfill detection** — Gap detection beyond basic freshness tests. Add when observability mature.
- **Unit tests (dbt v1.8+)** — Test macros in isolation. Defer until macro library is stable.

**Anti-features to avoid:**
- **Fuzzy device ID matching in attribution** — Introduces non-deterministic mappings, breaks auditability. Use deterministic matching (IDFV = device_id) or probabilistic IP-based matching, not ML guessing.
- **Testing every column for uniqueness** — Creates test bloat, wastes CI/CD time. Only test natural/surrogate keys.
- **Real-time freshness monitoring** — Adds complexity for marginal benefit. Hourly/daily SLA checks sufficient for analytics.

### Architecture Approach

The WGT project follows standard dbt three-layer architecture (staging → intermediate → marts), which aligns with industry best practices. Device mapping fixes require changes at all three layers, with testing co-located alongside models in YAML files. The project has established patterns (incremental models with unique_key, generate_schema_name macro for environment routing, network_mapping seed for reference data) that should be preserved.

**Major components:**

1. **Staging Layer (Source Normalization)** — `v_stg_adjust__installs`, `v_stg_adjust__touchpoints`, `v_stg_amplitude__merge_ids` handle device ID normalization (UPPER, strip Android 'R' suffix). Materialized as views. Tests: not_null on device IDs, accepted_values for platform, regex validation for ID formats. Key fix needed: Android GPS_ADID normalization currently incorrect.

2. **Intermediate Layer (Device Mapping & Attribution Logic)** — `int_adjust_amplitude__device_mapping` (incremental, 7-day lookback), `int_mta__user_journey` (incremental), `int_mta__touchpoint_credit` handle device ID joins and multi-touch attribution credit allocation. Materialized as incremental tables. Tests: unique on composite keys, relationships (foreign key validation), business rule tests (credit sums to 1.0). Critical path for device mapping fix.

3. **Marts Layer (Business Aggregations)** — `mart_campaign_performance_full_mta`, `mart_network_performance_mta` produce reporting-ready attribution metrics with D7/D30 cohort windows. Materialized as incremental tables. Tests: anomaly detection (elementary), business logic validation (ROAS ranges), row-level recency tests. Uses device mapping from intermediate layer.

4. **Diagnostic Models** — `int_device_mapping__diagnostics` (users with 100+ devices), `int_device_mapping__distribution_summary` (match rate executive summary). Materialized as full-refresh tables. Not part of DAG, used for monitoring and stakeholder communication.

5. **DRY Macros (NEW)** — `map_ad_partner()` macro will centralize duplicated AD_PARTNER CASE statement. Currently duplicated across 2 models (36 total lines). Refactor requires consistency test to prevent attribution drift.

6. **Testing Structure (NEW)** — Generic tests in co-located YAML files (`_adjust__models.yml`, `_amplitude__sources.yml`), singular tests in `/tests` directory organized by layer (staging/, intermediate/, marts/), unit tests in model YAML (dbt v1.8+). Use test pyramid: many generic tests (fast), moderate singular tests (business rules), few integration tests (end-to-end).

### Critical Pitfalls

Research identified 6 critical pitfalls specific to retrofitting tests onto existing pipelines with device ID refactoring. These are not theoretical—they're derived from documented incidents in mobile attribution projects.

1. **Changing device ID logic in staging breaks incremental downstream models** — Modifying GPS_ADID normalization (adding UPPER, stripping 'R' suffix) causes incremental models to INSERT new rows instead of UPDATE existing rows, creating duplicates. The unique_key in incremental models won't match old vs new device IDs. **Prevention:** Full-refresh staging + ALL downstream with `dbt run --full-refresh --select model_name+`. Add uniqueness tests BEFORE changing logic to detect duplicates immediately. Use shadow column approach (add normalized_device_id as NEW column, backfill, then deprecate old column).

2. **Full-refresh invalidates D30 cohort windows** — Running `--full-refresh` on marts resets historical window. Models like `mart_campaign_performance_full` have 35-day lookback in incremental mode, insufficient to recalculate D30 metrics for cohorts older than 35 days. **Prevention:** Implement `full_history_mode` variable to include all data during full-refresh: `{% if is_incremental() and not var('full_history_mode', false) %}` with date filter, else no filter. Export backup before full-refresh. Validate D30 metrics exist for cohorts 30+ days old after refresh.

3. **Refactoring AD_PARTNER CASE logic changes attribution without detection** — The 18-line CASE statement is duplicated in installs and touchpoints models. Refactoring to macro or seed introduces risk of logic drift (different conditions, typos, missing network names → NULL instead of 'Other'). Attribution joins break when install AD_PARTNER != touchpoint AD_PARTNER for same network. **Prevention:** Add consistency test BEFORE refactoring that verifies both models produce identical AD_PARTNER for every NETWORK_NAME. Use shadow column during migration (AD_PARTNER_NEW alongside AD_PARTNER). Only swap after consistency test passes.

4. **Adding tests to zero-test project floods with false positives** — First `dbt test` run on WGT project will reveal hundreds of historical data quality issues (NULL device IDs, duplicates, casing inconsistencies), causing decision paralysis. Teams either ignore all failures (defeats purpose) or fix all issues first (blocks progress for weeks). **Prevention:** Forward-looking tests only: `where: "created_at >= '2026-02-01'"` to validate new data. Triage failures by severity (CRITICAL: NULL device IDs in joins, MODERATE: duplicates, COSMETIC: casing). Fix critical immediately, document moderate as known issues, ignore cosmetic. Add tests incrementally (5-10 per sprint, not 50+ at once).

5. **Source freshness checks fail without loaded_at_field** — Shared Snowflake databases (Adjust S3, Amplitude data share) lack ETL metadata columns like `_loaded_at`. Freshness checks fail with "column not found" or use wrong column (event_time instead of load_time), reporting stale data as fresh. **Prevention:** Audit source schemas first (`SHOW COLUMNS`). Use Snowflake INFORMATION_SCHEMA metadata (LAST_ALTERED) as fallback for tables without loaded_at_field. For event tables, use event_time as proxy with longer thresholds (warn_after 6 hours instead of 1 hour) to account for lag. Document proxy approach and supplement with external monitoring (Fivetran/Airbyte logs).

6. **iOS low match rate attributed to data issue when it's structural** — 1.4% iOS IDFA match rate leads teams to assume normalization bug, spending weeks investigating. Actual cause: touchpoints use IDFA (requires ATT consent, ~25% opt-in rate), installs use IDFV (different identifier, cannot be joined deterministically). 1.4% represents users who consented AND clicked AND installed—this is expected given consent rates. **Prevention:** Document iOS ATT limitations in project README before starting work. Baseline match rates before changes (iOS IDFA ~1-5%, iOS IP-based ~40-60%, Android GPS_ADID ~90%). Don't expect iOS IDFA match rate to improve significantly. Invest in IP-based probabilistic matching quality (timestamp windows, user-agent filters) instead of pursuing deterministic IDFA joins.

## Implications for Roadmap

Based on research, the project requires 6 phases with specific ordering to manage incremental model dependencies and avoid pitfall triggers. Phase ordering is constrained by: (1) tests must exist before refactoring logic (catch regressions immediately), (2) device ID normalization must be fixed with full-refresh strategy (requires backup/restore planning), (3) DRY refactoring must happen after tests stabilize (consistency tests prevent drift).

### Phase 1: Test Foundation (Table Stakes)
**Rationale:** Establish baseline data quality tests before making any code changes. Forward-looking tests (new data only) avoid historical data paralysis. This phase is defensive—catch regressions from upcoming device ID changes.

**Delivers:**
- Generic tests (unique, not_null, accepted_values) on staging models (installs, touchpoints, merge_ids)
- Referential integrity tests on device mapping intermediate models
- Platform-specific validation (Android vs iOS separate tests)
- Test execution in CI/CD pipeline

**Addresses Features:**
- Generic schema tests (table stakes)
- Not-null constraints on join keys (table stakes)
- Platform-specific validation (differentiator)

**Avoids Pitfalls:**
- Pitfall 4: Use `where: "created_at >= '2026-02-01'"` to test only new data, avoiding historical test failure flood
- Pitfall 1: Uniqueness tests on unique_key columns will immediately detect duplicates if device ID changes break incremental logic

**Research Flag:** Standard dbt testing patterns. Skip `/gsd:research-phase`.

### Phase 2: Device ID Audit & Documentation
**Rationale:** Investigate actual device ID formats in source systems before writing normalization logic. Prevent the "fix based on assumptions" anti-pattern. Document iOS ATT limitations to set stakeholder expectations.

**Delivers:**
- Audit queries for Amplitude DEVICE_ID format (Android vs iOS)
- Audit queries for Adjust GPS_ADID format (verify UPPER, hyphen handling)
- Documentation of iOS match rate limitations (ATT consent rates, IDFA vs IDFV)
- Baseline match rate metrics (Android, iOS IDFA, iOS IP-based) before changes
- Device ID normalization strategy document with examples

**Addresses Features:**
- Device mapping diagnostics (already exists, baseline current state)

**Avoids Pitfalls:**
- Pitfall 6: Document iOS structural limitations before starting work, preventing weeks of "why is iOS match rate low?" investigation
- Pitfall 1: Understand current device ID formats before changing normalization logic, preventing incorrect assumptions

**Research Flag:** May need deeper investigation depending on Amplitude schema complexity. Consider `/gsd:research-phase` if source format is non-standard.

### Phase 3: Device ID Normalization Fix (with Full-Refresh Backfill)
**Rationale:** Fix broken Android GPS_ADID normalization now that tests exist to catch regressions. Use full-refresh strategy with full_history_mode to preserve D30 cohort windows. This is the highest-risk phase—requires careful backup/restore planning.

**Delivers:**
- Updated `v_stg_amplitude__merge_ids` with correct Android device ID normalization
- Updated `v_stg_adjust__installs` to verify GPS_ADID normalization (likely already correct based on UPPER usage)
- Full-refresh of staging + downstream incremental models using `dbt run --full-refresh --select v_stg_amplitude__merge_ids+`
- Validation tests comparing row counts before/after, D30 metrics completeness
- Improved Android match rate (target: 80%+, up from current unknown baseline)

**Addresses Features:**
- Incremental model testing (table stakes)—verify full-refresh produces same results as incremental

**Avoids Pitfalls:**
- Pitfall 1: Full-refresh staging + downstream together (`model_name+` selector) prevents incremental model duplication
- Pitfall 2: Implement full_history_mode variable in marts to include all data (not just 35-day lookback), preserving D30 cohort windows
- Backup tables before full-refresh, validate cohort completeness after

**Research Flag:** May need `/gsd:research-phase` if Amplitude device ID format is unexpected or requires complex fuzzy matching logic.

### Phase 4: DRY Refactor (AD_PARTNER Macro)
**Rationale:** Extract duplicated AD_PARTNER CASE statement after device mapping stabilizes and tests are reliable. Use shadow column approach to verify macro produces identical output before swapping.

**Delivers:**
- `macros/map_ad_partner.sql` macro with centralized CASE statement
- Modified `v_stg_adjust__installs` and `v_stg_adjust__touchpoints` to use macro
- Consistency test verifying both models produce identical AD_PARTNER for all NETWORK_NAME values
- Migration validation: attribution install counts match touchpoint counts before/after refactor

**Addresses Features:**
- DRY macros (differentiator)—eliminates 36 lines of duplicated code, prevents drift

**Avoids Pitfalls:**
- Pitfall 3: Consistency test catches AD_PARTNER logic drift before it causes silent attribution mismatches
- Shadow column approach (AD_PARTNER_NEW) allows parallel validation before swapping

**Research Flag:** Standard dbt macro pattern. Skip `/gsd:research-phase`.

### Phase 5: Expand Test Coverage (Singular + Business Rules)
**Rationale:** Add comprehensive test suite after critical tests stabilize. Include singular tests for complex business rules (credit sums to 1.0, lookback window coverage, cross-layer consistency).

**Delivers:**
- Singular tests in `tests/` directory (touchpoint credit sums, user journey gaps, device mapping orphans)
- Expanded generic tests (not just keys, but important columns: timestamps, amounts, IDs)
- Elementary anomaly detection tests on marts (volume, distribution, freshness anomalies)
- Incremental model idempotency tests (full-refresh vs incremental comparison)

**Addresses Features:**
- Cross-model consistency tests (differentiator)
- Incremental model testing (table stakes)—verify idempotency
- Device mapping diagnostics tests (differentiator)—add severity thresholds

**Avoids Pitfalls:**
- Pitfall 4: Tests added incrementally (5-10 per sprint), not 50+ at once, preventing test suite management overhead
- Tests now cover business rules, not just data shape (uniqueness, not_null already in Phase 1)

**Research Flag:** Standard dbt testing patterns. Skip `/gsd:research-phase`.

### Phase 6: Source Freshness & Observability
**Rationale:** Add production monitoring after data pipeline is stable and tests are comprehensive. Source freshness is last because it requires understanding source schema timestamp columns (discovered in Phase 2 audit).

**Delivers:**
- Source freshness configuration in `_adjust__sources.yml` and `_amplitude__sources.yml` with correct loaded_at_field or Snowflake metadata fallback
- Scheduled `dbt source freshness` job (every 30 min, 2x the 1-hour SLA)
- Elementary CLI setup for observability dashboard and Slack alerts
- Stale static table detection (ADJUST_AMPLITUDE_DEVICE_MAPPING freshness test)
- Production monitoring job running elementary tests every 6 hours

**Addresses Features:**
- Source freshness monitoring (table stakes)
- Stale static table detection (differentiator)

**Avoids Pitfalls:**
- Pitfall 5: Use proxy timestamps (event_time) or Snowflake metadata (LAST_ALTERED) for sources without loaded_at_field. Conservative thresholds (warn_after 6 hours for proxy, not 1 hour) account for lag.

**Research Flag:** Standard dbt source freshness patterns. Skip `/gsd:research-phase`.

### Phase Ordering Rationale

- **Tests before refactoring:** Phase 1 (tests) must precede Phase 3 (device ID fix) and Phase 4 (macro refactor) to catch regressions immediately. This prevents silent bugs in attribution logic.
- **Audit before normalization:** Phase 2 (audit) must precede Phase 3 (fix) to avoid "fix based on assumptions" anti-pattern. Prevents weeks of rework if assumptions about device ID formats are wrong.
- **Device ID fix before DRY refactor:** Phase 3 (normalization) must precede Phase 4 (macro) because device ID changes require full-refresh (high risk), while macro refactoring is low risk. Avoid combining high-risk changes.
- **Core tests before expansion:** Phase 1 (critical tests) must precede Phase 5 (comprehensive tests) to avoid test failure paralysis. Forward-looking tests on new data first, then expand to historical data.
- **Observability last:** Phase 6 (freshness/monitoring) comes after pipeline stabilizes. No point monitoring freshness if device mapping is broken or tests are failing.

**Critical path dependencies:**
- Phase 1 → Phase 3 (tests must exist before device ID changes)
- Phase 2 → Phase 3 (audit must inform normalization logic)
- Phase 3 → Phase 4 (device mapping must stabilize before DRY refactor)
- Phase 1 → Phase 5 (core tests must stabilize before expanding coverage)

### Research Flags

**Phases likely needing deeper research during planning:**
- **Phase 2 (Device ID Audit):** IF Amplitude DEVICE_ID format is non-standard or requires complex fuzzy matching beyond simple UPPER/strip 'R' suffix, run `/gsd:research-phase` to investigate Amplitude device identifier documentation and find normalization examples.
- **Phase 3 (Device ID Fix):** IF audit reveals unexpected device ID format (not UUID, not GPS_ADID), run `/gsd:research-phase` to research Snowflake fuzzy matching strategies (EDITDISTANCE, JAROWINKLER_SIMILARITY) and find implementation examples for probabilistic device ID matching.

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Test Foundation):** dbt generic tests (unique, not_null, relationships) are well-documented with extensive official examples. Use dbt-utils package (industry standard).
- **Phase 4 (DRY Refactor):** dbt macros for CASE statement extraction are standard pattern with official documentation and many examples.
- **Phase 5 (Expand Tests):** Singular tests and dbt-expectations package have comprehensive documentation. Elementary observability setup has official quickstart guide.
- **Phase 6 (Source Freshness):** dbt source freshness is core feature with official docs. Snowflake metadata fallback (LAST_ALTERED) is documented workaround.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All package versions verified via dbt Package Hub and GitHub releases. Snowflake fuzzy matching functions confirmed as built-in. Amplitude/Adjust device ID documentation from official help centers. |
| Features | HIGH | Feature categorization (table stakes, differentiators, anti-features) based on multiple dbt testing best practice sources (dbt Labs, Datafold, Elementary Data). Mobile attribution patterns confirmed via Adjust and Amplitude official docs. |
| Architecture | HIGH | Three-layer dbt architecture (staging → intermediate → marts) is industry standard. Component responsibilities align with dbt best practices. Testing structure (co-located YAML, tests/ directory, test pyramid) documented in official dbt docs. |
| Pitfalls | HIGH | All 6 pitfalls derived from documented issues in dbt incremental model testing, mobile device ID tracking challenges (ATT impact), and dbt testing adoption case studies. Recovery strategies based on dbt Community Forum discussions and vendor blogs. |

**Overall confidence:** HIGH

Research is comprehensive and grounded in official documentation. All technology recommendations verified via primary sources (Package Hub, GitHub, official vendor docs). Pitfalls are documented in multiple sources (dbt Community Forum, vendor blogs, case studies), not theoretical. Architecture patterns align with dbt Labs official best practices.

### Gaps to Address

Research identified 2 gaps that require validation during planning/execution:

- **Amplitude DEVICE_ID format specifics:** Research confirms Amplitude uses `device_id` (IDFV for iOS, custom for Android) but did NOT verify the exact format in WGT's specific Amplitude instance. The current 'R' suffix stripping logic suggests custom formatting. **Action:** Phase 2 audit must query actual DEVICE_ID values to confirm format before implementing normalization fix. If format is non-standard, run `/gsd:research-phase` for deeper investigation.

- **Full_history_mode implementation in existing marts:** Research recommends using `{% if is_incremental() and not var('full_history_mode', false) %}` pattern to preserve D30 cohort windows during full-refresh, but WGT marts currently have hardcoded 35-day lookback filters. **Action:** Phase 3 must refactor date filtering logic in `mart_campaign_performance_full` and `mart_campaign_performance_full_mta` to support full_history_mode variable. Test that D30 metrics exist for cohorts 30+ days old after full-refresh with variable enabled.

Both gaps are addressable during execution with minimal risk—they don't invalidate the core approach but require validation/adjustment based on actual project specifics.

## Sources

### Primary (HIGH confidence)
- [dbt Package Hub: dbt-utils 1.3.3](https://hub.getdbt.com/dbt-labs/dbt_utils/latest/) — Version confirmation, compatibility requirements
- [dbt Package Hub: elementary 0.22.1](https://hub.getdbt.com/elementary-data/elementary/latest/) — Observability package version, capabilities
- [dbt-expectations GitHub (Metaplane fork)](https://github.com/metaplane/dbt-expectations) — Active fork confirmation, dbt 1.7+ requirement, deprecation of original
- [dbt Labs: Incremental models in-depth](https://docs.getdbt.com/best-practices/materializations/4-incremental-models) — Official best practices for incremental strategies, unique_key usage
- [dbt Labs: Test smarter not harder](https://docs.getdbt.com/blog/test-smarter-where-tests-should-go) — Official testing strategy by layer (staging vs intermediate vs marts)
- [dbt Labs: Source Freshness](https://docs.getdbt.com/docs/deploy/source-freshness) — Freshness configuration, loaded_at_field, Snowflake metadata fallback
- [Adjust Help: Device Identifiers](https://help.adjust.com/en/article/device-identifiers) — GPS_ADID, IDFA, Android ID usage in Adjust
- [Amplitude Docs: Identifying Users](https://help.amplitude.com/hc/en-us/articles/206404628-Step-2-Identifying-your-users) — device_id, user_id, amplitude_id reconciliation
- [Amplitude Docs: Missing Mobile Attribution Events](https://amplitude.com/docs/faq/missing-mobile-attribution-events) — Attribution API, 72-hour window, device ID mapping
- [DAS42: Fuzzy Matching in Snowflake](https://das42.com/thought-leadership/fuzzy-matching-in-snowflake/) — EDITDISTANCE, JAROWINKLER_SIMILARITY usage patterns, threshold recommendations

### Secondary (MEDIUM confidence)
- [Datafold: 7 dbt Testing Best Practices](https://www.datafold.com/blog/7-dbt-testing-best-practices) — Forward-looking tests, test pyramid, avoiding false positives
- [Elementary Data: dbt Tests - How to Write Fewer and Better](https://www.elementary-data.com/post/dbt-tests) — Strategic test placement, avoiding test bloat
- [Ingest Labs: Mobile Device ID Tracking in 2026](https://ingestlabs.com/mobile-device-id-tracking-guide/) — ATT impact, IDFA opt-in rates (~25%), IDFV vs IDFA differences
- [Metaplane: dbt Macros Guide](https://www.metaplane.dev/blog/dbt-macros) — When to use macros, DRY principles, avoiding over-abstraction
- [Medium: DBT Models in Snowflake Best Practices](https://medium.com/@manik.ruet08/dbt-models-in-snowflake-best-practices-for-staging-intermediate-and-mart-layers-2abf37d08f65) — Layer-specific testing patterns, materialization strategies
- [dbt Community Forum: Testing Incremental Models](https://discourse.getdbt.com/t/testing-incremental-models/1528) — Full-refresh validation, lookback window testing, idempotency checks

### Tertiary (LOW confidence, needs validation)
- WGT dbt project codebase analysis (2026-02-10) — Current state assessment (zero tests, duplicated CASE statements, Android 'R' suffix logic). **Validation needed:** Query actual device_id values in Amplitude EVENTS_726530 table to confirm format assumptions.
- `.planning/codebase/CONCERNS.md` reference — Technical debt audit. **Validation needed:** Confirm device mapping diagnostics model exists and is currently used for monitoring.

---
*Research completed: 2026-02-10*
*Ready for roadmap: yes*
