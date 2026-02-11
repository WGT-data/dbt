# Project Research Summary

**Project:** WGT dbt Analytics v1.0 - Pipeline Hardening
**Domain:** dbt project pipeline hardening (DRY refactor, testing, source freshness)
**Researched:** 2026-02-11
**Confidence:** HIGH

## Executive Summary

The remaining v1.0 work focuses on productionizing the existing MMM pipeline through three complementary activities: extracting duplicated AD_PARTNER logic into a macro (DRY refactor), adding singular tests for business rule validation, and configuring source freshness monitoring. The research reveals a critical finding: **all required capabilities exist natively in dbt or the already-installed dbt-utils package** — no new dependencies needed.

This is a low-risk, high-value hardening effort. The stack discipline of using native dbt features (macros, singular tests, source freshness YAML) over adding packages reduces maintenance burden while improving code quality. The architecture integrates cleanly: macros live in `macros/`, tests in `tests/`, and freshness configs in existing `_sources.yml` files. All validation happens in dbt Cloud (no local environment required).

The key risk is **silent data drift during macro extraction** — the AD_PARTNER CASE statement must produce identical output after refactoring. Prevention: create a consistency test that compares macro output to original CASE logic before deployment, validate in dbt Cloud dev environment with both full-refresh and incremental runs, then deploy. Additional risks include timezone mismatches in freshness configs and vacuous singular tests that pass because test logic is broken, not because data is clean. Both are mitigated through explicit validation steps.

## Key Findings

### Recommended Stack

**Zero new packages required.** All Phase 4-6 work uses native dbt features and existing dbt-utils (>=1.1.1).

**Core capabilities:**
- **Native dbt macros** — Extract duplicated 18-line AD_PARTNER CASE statement into parameterized macro. No package needed.
- **Native singular tests** — SQL files in `tests/` directory for complex business rules (date spine completeness, cross-layer consistency, zero-fill integrity). Standard dbt feature.
- **Native source freshness** — YAML configs in `_sources.yml` files with `loaded_at_field`, `warn_after`, `error_after`. Built into dbt-core since v0.18.0.
- **dbt Cloud job scheduler** — Separate freshness job (hourly) vs model builds (every 6 hours). Native dbt Cloud feature.

**Explicitly rejected:**
- dbt-expectations: Overkill for simple MMM business rule tests. Singular SQL is clearer.
- re_data / elementary: Too early for observability framework. Native freshness sufficient.
- Additional macro libraries: 18-line CASE statement is simple enough to write inline.

**Optional upgrade:** dbt-utils 1.1.1 → 1.3.3 (latest stable). Backward compatible patch, fixes time filter bug in date_spine. Not required but recommended.

### Expected Features

**Must have (table stakes):**
- Source freshness with `loaded_at_field` — Standard dbt observability for detecting stale upstream data
- Singular tests for business logic — Generic tests (unique, not_null) only cover data shape; business rules need custom SQL
- Macros for repeated CASE logic — DRY principle prevents drift between `v_stg_adjust__installs` and `v_stg_adjust__touchpoints`
- Incremental model validation — Must verify models work on first run AND subsequent runs (is_incremental branches)
- Cross-layer consistency tests — Aggregated marts must reconcile to source layer
- Zero-fill vs missing data flags — HAS_SPEND_DATA, HAS_INSTALL_DATA flags already exist in mart, tests validate integrity

**Should have (differentiators):**
- Hierarchical freshness config — Define at source level (all tables inherit), override at table level for exceptions
- Macro with consistency test — Extract logic into macro AND validate it produces identical output to original CASE
- Date spine completeness test — MMM regression requires gap-free daily data
- Scheduled freshness as separate job — Run freshness every 2 hours, model builds every 12 hours (different cadences)

**Defer (anti-features — explicitly avoid):**
- Freshness on every source table — Creates alert fatigue; focus on critical upstream tables only
- Over-abstracted macros — Only extract when logic duplicated 2+ times; favor readability
- Generic tests for complex business rules — Use singular SQL files for MMM-specific validations
- Testing every column — Only test primary keys and critical business logic
- Real-time freshness alerting — Analytics SLAs are hourly/daily, not seconds
- --full-refresh in production — Only use in dev or intentional backfill scenarios

### Architecture Approach

All three features integrate cleanly with existing dbt project structure through standard dbt conventions. **No structural changes required** — only new files added to existing directories: `macros/map_ad_partner.sql` (new), tests in `tests/mmm/` subdirectories (new), freshness configs in existing `_sources.yml` files (modified).

**Major components:**

1. **Source Freshness Monitoring** — Add `freshness` configs to existing `models/staging/*/_*__sources.yml` files. Use CREATED_AT (epoch timestamp) for Adjust, EVENT_TIME/SERVER_UPLOAD_TIME for Amplitude. Configure source-level defaults, override at table level for exceptions. Deploy via separate dbt Cloud job scheduled hourly.

2. **Singular Tests** — Create `tests/mmm/`, `tests/mta/`, `tests/cross_layer/` subdirectories. Tests are SQL queries returning failing rows (0 rows = pass). Examples: date spine completeness, weekly rollup matches daily, AD_PARTNER consistency after macro extraction. Tests run automatically via `dbt build` in CI jobs.

3. **AD_PARTNER Macro** — Extract duplicated CASE statement (lines 65-83 in `v_stg_adjust__installs.sql`, lines 140-158 in `v_stg_adjust__touchpoints.sql`) into `macros/map_ad_partner.sql`. Replace original CASE with `{{ map_ad_partner('NETWORK_NAME') }}` calls. Macro is compile-time only (generates SQL, no runtime components).

**Integration points:**
- Macro refactor is transparent to downstream models (AD_PARTNER column still exists with identical values)
- Tests are read-only (query models but don't create tables)
- Freshness checks are read-only (query source timestamps but don't run models)
- All validation happens in dbt Cloud jobs (no local dbt required)

### Critical Pitfalls

1. **Macro Extraction Changes Output Silently (CODE-01/02)** — Extracting duplicated CASE into macro can introduce subtle differences (whitespace, NULL handling, ELSE clause) that break downstream models. **Prevention:** Create baseline of current output BEFORE extraction, create consistency test comparing macro to original CASE, run test in dbt Cloud dev, expect 0 failures. Update one model at a time, validate, then second model.

2. **Wrong `loaded_at_field` — Created vs Loaded Timestamps (FRESH-01/02)** — Using source system creation timestamps (CREATED_AT, EVENT_TIME) instead of ETL load timestamps (LOAD_TIMESTAMP, _LOADED_AT) makes freshness report age of data events, not data delivery, causing silent staleness. **Prevention:** For Adjust S3 tables, use LOAD_TIMESTAMP (ETL write time), not CREATED_AT (event time). Document in YAML: `loaded_at_field: LOAD_TIMESTAMP  # ETL time, not event time`.

3. **Incremental Model First Run vs Subsequent Run Divergence (MMM-01/02)** — `is_incremental()` branches cause models to produce different results on first run (full) vs subsequent runs (incremental), breaking backfills. **Prevention:** Keep business logic OUTSIDE is_incremental block. Use performance filters only (7-day lookback for late data). Test BOTH paths in dbt Cloud: `--full-refresh` then normal run, verify row counts increase or stay same (not decrease).

4. **Singular Tests That Pass Vacuously (TEST-06/07/08)** — Tests return 0 rows because test logic is broken (impossible WHERE, empty JOIN), not because data is good. **Prevention:** Validate test fails when intentional violation added. Add row count expectations. Include context columns in output (not just IDs). Test the test before deploying.

5. **Source Freshness on Static Tables Without Timestamps (FRESH-03)** — `ADJUST_AMPLITUDE_DEVICE_MAPPING` lacks timestamp column. Adding freshness fails with "column does not exist". **Prevention:** Omit freshness config for static tables. Use singular test checking Snowflake INFORMATION_SCHEMA.TABLES.LAST_ALTERED instead, or row count change test.

## Implications for Roadmap

Based on research, the existing Phase 4-6 structure is optimal. Recommendations:

### Phase 4: DRY Refactor (CODE-01/02/04)
**Rationale:** Macro extraction must complete before comprehensive testing. Tests should validate macro logic, not duplicated CASE statements. Clean codebase foundation before adding validation layer.

**Delivers:**
- `macros/map_ad_partner.sql` — Single source of truth for NETWORK_NAME → AD_PARTNER mapping
- Refactored `v_stg_adjust__installs.sql` and `v_stg_adjust__touchpoints.sql` — 18 lines removed per model
- `tests/staging/assert_ad_partner_macro_consistency.sql` — Validates macro produces identical output

**Build order:**
1. Create macro file (EXACT copy of CASE logic, no improvements yet)
2. Create consistency test comparing macro to original CASE
3. Refactor `v_stg_adjust__installs.sql` (replace CASE with macro call)
4. Run consistency test, expect 0 failures
5. Refactor `v_stg_adjust__touchpoints.sql`
6. Validate downstream models compile without errors

**Avoids:** Silent data drift (Pitfall 4), seed case sensitivity bugs (Pitfall 10)

**Complexity:** Low (1-2 hours). All testing in dbt Cloud dev environment.

**Research confidence:** HIGH. Macro organization well-documented. No deep research needed.

### Phase 5: Expand Test Coverage (TEST-06/07/08, MMM-01/02/03/04)
**Rationale:** Singular tests validate refactored models and business logic before adding observability. Tests protect production pipeline before freshness alerts. Must validate incremental models work correctly (first run vs subsequent runs).

**Delivers:**
- `tests/mmm/assert_mmm_daily_grain_completeness.sql` — Date spine has no gaps
- `tests/mmm/assert_mmm_weekly_rollup_matches_daily.sql` — Weekly sums match daily detail
- `tests/mmm/assert_mmm_zero_fill_integrity.sql` — HAS_*_DATA flags correct
- `tests/cross_layer/assert_device_counts_staging_to_marts.sql` — Cross-layer consistency
- MMM incremental model validation — Both code paths tested

**Build order:**
1. Create test directory structure (`tests/mmm/`, `tests/mta/`, `tests/cross_layer/`)
2. Write MMM singular tests (date spine, weekly rollup, zero-fill)
3. Test incremental models TWICE (--full-refresh, then normal run)
4. Write cross-layer consistency tests (with consistent filters: iOS-only, date >= 2024-06-01)
5. Run `dbt test --select test_type:singular` in dbt Cloud, debug failures
6. Add to CI (automatic via `dbt build`)

**Avoids:** Vacuous tests (Pitfall 6), brittle hardcoded thresholds (Pitfall 7), cross-layer filter mismatches (Pitfall 8), incremental divergence (Pitfall 5)

**Complexity:** Medium (2-3 hours). Singular tests are straightforward SQL, but require business rule knowledge.

**Research confidence:** HIGH. Test organization patterns clear. Business logic tests domain-specific (not architectural concern).

### Phase 6: Source Freshness & Observability (FRESH-01/02/03/04)
**Rationale:** Observability layer assumes stable, tested pipeline. Freshness alerts only valuable if data pipeline is validated. Add monitoring after code quality improvements and testing complete.

**Delivers:**
- Freshness configs in `models/staging/adjust/_adjust__sources.yml` (LOAD_TIMESTAMP, warn 6h, error 12h)
- Freshness configs in `models/staging/amplitude/_amplitude__sources.yml` (SERVER_UPLOAD_TIME, warn 6h, error 12h)
- Freshness configs in `models/staging/supermetrics/_supermetrics__sources.yml` (DATE proxy, warn 12h, error 24h)
- Static table staleness test `tests/static_table_changed_unexpectedly.sql` (for ADJUST_AMPLITUDE_DEVICE_MAPPING)
- dbt Cloud freshness job (scheduled every 1 hour)

**Build order:**
1. Audit timestamp columns (query INFORMATION_SCHEMA.COLUMNS to confirm LOAD_TIMESTAMP exists)
2. Add freshness to Adjust sources (use LOAD_TIMESTAMP, not CREATED_AT)
3. Add freshness to Amplitude sources (identify correct timestamp column)
4. Add freshness to Supermetrics sources (use DATE proxy or _FIVETRAN_SYNCED)
5. Omit freshness for static tables, create row count change test instead
6. Create dbt Cloud freshness job (schedule hourly, command: `dbt source freshness`)
7. Test freshness job manually, verify results in logs
8. Trigger failure (temporarily lower threshold) to test alerting

**Avoids:** Static table timestamp errors (Pitfall 1), wrong timestamp column (Pitfall 2), timezone mismatch (Pitfall 3), freshness+build in same job (Pitfall 11)

**Complexity:** Low (1-2 hours). Standard dbt feature, mostly YAML configuration.

**Research confidence:** HIGH. Freshness config location and syntax verified. Snowflake-specific guidance clear.

### Phase Ordering Rationale

**Code quality → Validation → Monitoring** minimizes risk:

1. **Phase 4 first** — DRY refactor reduces technical debt before building on top of it. Tests in Phase 5 should validate clean macro logic, not duplicated CASE statements. Macro becomes available for future models.

2. **Phase 5 second** — Tests validate refactored models and business logic before adding monitoring. High test coverage required before alerting (Phase 6) to avoid alert fatigue from known issues. Tests must pass before freshness alerts become actionable.

3. **Phase 6 last** — Observability layer assumes stable, tested pipeline. Freshness alerts only valuable if data pipeline is validated (otherwise alerts fire on expected failures). Source freshness should monitor a pipeline with high test coverage.

**Dependencies:** Each phase builds on previous. Cannot skip or reorder without increasing risk.

### Research Flags

**Phases needing deeper research during planning:** None. All three phases have clear integration patterns with existing architecture.

**Phases with standard patterns (skip research-phase):**
- **Phase 4:** Native dbt macros well-documented. Consistency test pattern clear.
- **Phase 5:** Singular test structure well-documented. Test organization patterns established.
- **Phase 6:** Source freshness configuration verified. dbt Cloud job setup documented.

**Confidence levels by phase:**
- Phase 4 (DRY Refactor): HIGH confidence — Macro organization clear, dbt Cloud validation strategy verified
- Phase 5 (Expand Test Coverage): HIGH confidence — Singular test structure clear, test organization patterns established
- Phase 6 (Source Freshness): HIGH confidence — Freshness config syntax verified, dbt Cloud job setup documented

**No deep research gaps.** All features use native dbt capabilities with clear documentation.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All capabilities native to dbt or existing dbt-utils. Zero new packages. Official docs verified. |
| Features | HIGH | Table stakes (macros, singular tests, freshness) and differentiators (consistency tests, hierarchical config) clearly defined. Anti-features identified. |
| Architecture | HIGH | Integration points mapped to existing file structure. All three features fit standard dbt conventions. dbt Cloud validation strategy clear. |
| Pitfalls | HIGH | Critical pitfalls identified with prevention strategies. Snowflake-specific guidance (timezone, case sensitivity) verified. WGT-specific constraints (no local dbt) addressed. |

**Overall confidence:** HIGH

### Gaps to Address

**Operational unknowns (resolve during Phase 6 execution):**

1. **Actual Snowflake timestamp column types** — Research assumes LOAD_TIMESTAMP exists for Adjust S3 tables, but not verified. Impact: Timezone conversion requirements (TIMESTAMP_NTZ vs TIMESTAMP_LTZ). **Resolution:** Run `DESCRIBE TABLE` audit query before configuring freshness.

2. **Actual data refresh frequencies** — Research assumes Adjust S3 (6hr), Supermetrics (daily), Amplitude (12hr) based on typical patterns. Not verified with WGT. Impact: `warn_after` threshold configuration. **Resolution:** Ask data engineering team for SLAs, or observe MAX(LOAD_TIMESTAMP) patterns over 1 week.

3. **network_mapping.csv completeness** — STATE.md says "coverage unknown". Impact: AD_PARTNER macro extraction (what happens for unmapped networks?). **Resolution:** Phase 4 must include coverage audit (SELECT DISTINCT NETWORK_NAME from staging, compare to seed) before macro extraction.

**Architectural validations (resolve during Phase 4/5 execution):**

4. **Incremental model lookback logic** — Research assumes 7-day lookback in MMM intermediate models, but not verified by reading model SQL. Impact: Test validation strategy (must account for overlapping date ranges). **Resolution:** Inspect `int_mmm__*.sql` files during Phase 5 to confirm is_incremental filter logic.

5. **dbt Cloud dev environment permissions** — Research assumes ability to create jobs, run dbt source freshness, inspect compiled SQL. Not verified. Impact: Phase 6 freshness job creation. **Resolution:** Verify permissions before Phase 6 kickoff.

**None of these gaps block planning.** All can be resolved during phase execution with < 30 minutes investigation each.

## Sources

### Primary (HIGH confidence)

**dbt Official Documentation:**
- [Source freshness configuration](https://docs.getdbt.com/reference/resource-configs/freshness) — Freshness syntax, loaded_at_field, warn/error thresholds
- [Deploy source freshness](https://docs.getdbt.com/docs/deploy/source-freshness) — dbt Cloud job setup
- [Add sources to your DAG](https://docs.getdbt.com/docs/build/sources) — Source YAML structure
- [Singular tests](https://docs.getdbt.com/docs/build/data-tests) — Tests directory structure
- [Jinja and macros](https://docs.getdbt.com/docs/build/jinja-macros) — Macro syntax, best practices
- [Configure incremental models](https://docs.getdbt.com/docs/build/incremental-models) — is_incremental() behavior
- [Incremental models in-depth](https://docs.getdbt.com/best-practices/materializations/4-incremental-models) — Full refresh, lookback patterns
- [dbt-utils package hub](https://hub.getdbt.com/dbt-labs/dbt_utils/latest/) — Version 1.3.3 details

**Snowflake Official Documentation:**
- [Identifier requirements](https://docs.snowflake.com/en/sql-reference/identifiers-syntax) — Case sensitivity rules
- [CONVERT_TIMEZONE function](https://docs.snowflake.com/en/sql-reference/functions/convert_timezone) — Timezone handling

### Secondary (MEDIUM confidence)

**Community Best Practices:**
- [7 dbt Testing Best Practices](https://www.datafold.com/blog/7-dbt-testing-best-practices) — Singular vs generic tests, vacuous test detection
- [dbt source freshness usage guide](https://www.datafold.com/blog/dbt-source-freshness) — loaded_at_field selection, ETL vs event timestamps
- [Ultimate Guide to dbt Macros 2025](https://dagster.io/guides/ultimate-guide-to-dbt-macros-in-2025-syntax-examples-pro-tips) — Macro organization, testing strategies
- [How to unit test macros in dbt](https://medium.com/glitni/how-to-unit-test-macros-in-dbt-89bdb5de8634) — Macro validation patterns
- [Challenges with dbt Tests in Practice](https://datasettler.com/blog/post-4-dbt-pitfalls-in-practice/) — Brittle thresholds, alert fatigue

**GitHub Issues & Forums:**
- [dbt seed case sensitivity issue](https://github.com/dbt-labs/dbt-core/issues/7265) — Snowflake quote_columns behavior
- [Using non-UTC timestamps for freshness](https://discourse.getdbt.com/t/using-a-non-utc-timestamp-when-calculating-source-freshness/1237) — Timezone conversion examples

### Tertiary (Project-specific)

- WGT dbt project REQUIREMENTS.md — TEST-06/07/08, FRESH-01/02/03, CODE-01/02 specifications
- WGT dbt project STATE.md — network_mapping coverage unknown, device mapping staleness
- Existing model files — v_stg_adjust__installs.sql, v_stg_adjust__touchpoints.sql (AD_PARTNER duplication verified)

---
*Research completed: 2026-02-11*
*Ready for roadmap: yes*
