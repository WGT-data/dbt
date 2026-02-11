# Feature Research

**Domain:** dbt Analytics — Device ID Resolution & Data Quality Testing
**Researched:** 2026-02-10
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist in production dbt projects. Missing these = pipeline feels incomplete or unreliable.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Generic schema tests (unique, not_null) | Industry standard for data quality; dbt ships with 4 built-in tests (unique, not_null, accepted_values, relationships) | LOW | Apply to all primary/foreign keys, critical business columns. YAML-based, minimal effort |
| Source freshness monitoring | Table stakes for production pipelines; detects stale upstream data before it corrupts metrics | LOW | Configured via `loaded_at_field` timestamp in sources YAML. Run with `dbt source freshness` |
| Referential integrity tests (relationships) | Validates child → parent table references; prevents orphaned records in joins | LOW | Built-in `relationships` test. Critical for device mapping (Adjust → Amplitude foreign keys) |
| Incremental model testing | Ensures incremental models produce same results in full-refresh vs incremental modes (idempotency) | MEDIUM | Test both modes; validate lookback windows; essential for `int_adjust_amplitude__device_mapping` |
| Not-null constraints on join keys | Prevents silent data loss in joins; foundational data quality practice | LOW | Apply to all device IDs, user IDs, and foreign keys used in joins |

### Differentiators (Competitive Advantage)

Features that set high-quality analytics pipelines apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Device mapping diagnostics & alerts | Surfaces data quality issues (anomalous user→device ratios, missing mappings) before they impact MTA | MEDIUM | Already exists (`int_device_mapping__diagnostics.sql`). Add tests: warn if >100 devices/user, error if match rate <threshold |
| Multi-platform ID resolution validation | Validates Android GPS_ADID vs iOS IDFV mapping logic separately; catches platform-specific bugs | MEDIUM | Critical for this project (Android broken, iOS 1.4% match). Add tests to validate mapping coverage by platform |
| DRY code architecture (macros for reused logic) | Eliminates duplicated CASE statements (e.g., AD_PARTNER mapping); reduces maintenance burden | LOW-MEDIUM | Extract AD_PARTNER CASE to macro. Currently duplicated in `v_stg_adjust__installs.sql` + `v_stg_adjust__touchpoints.sql` |
| Stale static table detection | Alerts when `ADJUST_AMPLITUDE_DEVICE_MAPPING` static table hasn't been refreshed (currently stale since Nov 2025) | LOW | Add freshness test to static table sources. Prevents reliance on outdated manual mappings |
| Cross-model data consistency tests | Validates that device counts in staging layer match intermediate/mart layers (no silent data loss) | MEDIUM | Use `dbt-utils.equal_rowcount` or custom tests to compare aggregates across layers |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems in device ID resolution and testing contexts.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Real-time freshness monitoring | "We need instant alerts when data goes stale" | Adds complexity/cost; most analytics SLAs are hourly/daily, not real-time. Freshness checks run on schedule, not continuously | Run `dbt source freshness` on same cadence as pipeline (e.g., hourly). Alert only on missed SLAs, not every minute |
| Testing every column for uniqueness | "Let's test everything to be safe" | Creates test bloat; most columns SHOULD have duplicates. Wastes CI/CD time | Only test natural/surrogate keys. Use `not_null` for important non-key columns |
| Fuzzy device ID matching | "Let's use ML to guess matching IDs" | Introduces non-deterministic mappings; breaks attribution auditability. Privacy concerns with heuristic matching | Use deterministic mappings only (IDFV=device_id for iOS, GPS_ADID for Android). Surface unmapped devices in diagnostics, don't guess |
| Testing in production only | "We'll add tests later when we have issues" | By the time production breaks, bad data already corrupted downstream metrics. Expensive to fix retroactively | Add tests incrementally during development. Gate PRs on test passage in CI/CD |
| Hardcoded date filters in models | "Just filter to 2024-01-01 for now" | Makes models brittle; breaks when date ranges change. Already present in `v_stg_adjust__touchpoints.sql` (line 38, 63, 88, 112) | Use dbt vars for date ranges or remove static filters. Let downstream models control time windows |

## Feature Dependencies

```
[Source freshness tests]
    └──requires──> [Sources YAML with loaded_at_field configured]

[Referential integrity tests]
    └──requires──> [Primary keys tested for uniqueness first]
                       └──requires──> [Schema YAML with column definitions]

[Device mapping diagnostics]
    └──requires──> [int_adjust_amplitude__device_mapping model]
    └──enhances──> [Multi-platform ID resolution validation]

[DRY macros (AD_PARTNER)]
    └──replaces──> [Duplicated CASE statements in 2 models]

[Incremental model testing]
    └──requires──> [Incremental models with is_incremental() logic]
    └──validates──> [Lookback windows (7-day in device mapping)]

[Cross-model consistency tests]
    └──requires──> [Generic schema tests passing first]
```

### Dependency Notes

- **Referential integrity requires unique primary keys:** Cannot test `relationships` until parent table's primary key passes `unique` test. Test order matters.
- **Device mapping diagnostics enhances validation:** Diagnostics table identifies anomalies; validation tests enforce thresholds. Work together to catch issues.
- **DRY macros eliminate duplication:** AD_PARTNER CASE statement appears in 2 files (lines 65-83 in installs, 136-154 in touchpoints). Extract to single macro to prevent drift.
- **Incremental testing validates lookback windows:** Device mapping uses 7-day lookback (line 17 of `int_adjust_amplitude__device_mapping.sql`). Test that late-arriving data within window gets captured.

## MVP Definition

### Launch With (v1)

Minimum viable testing framework — what's needed to validate data quality and unblock Android device mapping fixes.

- [ ] **Source freshness tests** — Detect stale Adjust/Amplitude data before it breaks MTA (Amplitude sources, Adjust sources, static mapping table)
- [ ] **Unique + not_null on device IDs** — Validate ADJUST_DEVICE_ID, AMPLITUDE_USER_ID, GPS_ADID, IDFV have no nulls or duplicates where expected
- [ ] **Referential integrity (device mapping)** — Test that `int_adjust_amplitude__device_mapping.ADJUST_DEVICE_ID` exists in Adjust installs (no orphaned mappings)
- [ ] **Platform-specific mapping validation** — Test Android GPS_ADID mapping separately from iOS IDFV (catch platform-specific bugs)
- [ ] **AD_PARTNER macro** — Extract duplicated CASE statement to DRY macro (foundational for maintainability)

### Add After Validation (v1.x)

Features to add once core testing framework is working and Android device mapping is fixed.

- [ ] **Device mapping diagnostics tests** — Add severity tests to `int_device_mapping__diagnostics` (warn if >100 devices/user, error if iOS match rate <1%)
- [ ] **Incremental model idempotency tests** — Validate `int_adjust_amplitude__device_mapping` produces same results in full-refresh vs incremental mode
- [ ] **Cross-layer consistency tests** — Compare device counts in staging vs intermediate vs marts (detect silent data loss)
- [ ] **Hardcoded date filter refactor** — Remove `CREATED_AT >= 1704067200` filters from staging models; use dbt vars or let downstream control time windows
- [ ] **Stale static table alerts** — Automate detection when `ADJUST_AMPLITUDE_DEVICE_MAPPING` hasn't been refreshed in >30 days

### Future Consideration (v2+)

Features to defer until data quality framework is mature and Android attribution is stable.

- [ ] **dbt-expectations package** — Advanced tests like `expect_grouped_row_values_to_have_recent_data` for SLA enforcement, `expect_row_values_to_have_data_for_every_n_datepart` for completeness gaps
- [ ] **Custom generic tests** — Create reusable tests for WGT-specific patterns (e.g., "validate all Android devices have GPS_ADID format")
- [ ] **Data quality dashboards** — Expose test results/trends in BI tool (not just dbt Cloud logs)
- [ ] **Automated backfill detection** — Alert when incremental models skip time periods (gap detection beyond freshness tests)
- [ ] **Unit tests (dbt v1.8+)** — Test macros and edge cases in isolation using dbt's new unit testing framework

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Unique + not_null on device IDs | HIGH (catches Android mapping bugs) | LOW (YAML config only) | P1 |
| Source freshness monitoring | HIGH (prevents stale data corruption) | LOW (YAML + scheduled job) | P1 |
| Referential integrity tests | HIGH (validates device mapping joins) | LOW (built-in `relationships` test) | P1 |
| AD_PARTNER macro (DRY) | MEDIUM (maintainability, prevents drift) | LOW (extract to macro) | P1 |
| Platform-specific validation | HIGH (Android broken, iOS 1.4% match) | MEDIUM (custom tests) | P1 |
| Device mapping diagnostics tests | MEDIUM (surfaces anomalies proactively) | MEDIUM (thresholds + severity config) | P2 |
| Incremental idempotency tests | MEDIUM (ensures data accuracy) | MEDIUM (requires test runs in both modes) | P2 |
| Cross-layer consistency tests | MEDIUM (detects silent data loss) | MEDIUM (requires dbt-utils or custom tests) | P2 |
| Hardcoded date filter refactor | LOW (tech debt, not blocking) | LOW (remove hardcoded values) | P2 |
| Stale static table alerts | LOW (manual workaround exists) | LOW (freshness test config) | P2 |
| dbt-expectations package | LOW (nice-to-have advanced tests) | MEDIUM (new dependency, learning curve) | P3 |
| Data quality dashboards | LOW (improves visibility, not critical) | HIGH (BI integration work) | P3 |

**Priority key:**
- P1: Must have for Android device mapping fix and baseline data quality (v1)
- P2: Should have, add when core tests are stable (v1.x)
- P3: Nice to have, future consideration when framework is mature (v2+)

## Device ID Resolution Feature Analysis

### iOS Device ID Mapping (Current State)

**What works:**
- IDFV = Amplitude device_id (deterministic match confirmed)
- `int_adjust_amplitude__device_mapping` captures iOS IDFV → Amplitude USER_ID

**What's broken:**
- Only 1.4% of iOS MTA touchpoint devices match (53/3,925 in Jan 2026)
- Most touchpoint devices never appear in Amplitude events
- Root cause: iOS touchpoints use IDFA (11% consent rate) or IP_ADDRESS (probabilistic), not IDFV

**Required features to fix:**
1. **IP-based matching validation** — Test if iOS touchpoint IP_ADDRESS matches Amplitude session IP (probabilistic but better than 1.4%)
2. **IDFA → device_id mapping** — Add fallback logic: if IDFA exists in touchpoint AND Amplitude event, map even if IDFV missing
3. **Unmapped device diagnostics** — Surface which touchpoints can't be mapped (IDFA missing, IP mismatch) for analysis

### Android Device ID Mapping (Current State)

**What works:**
- GPS_ADID collected in Adjust Android events (ADID = Google Advertising ID)
- `v_stg_adjust__touchpoints.sql` uses `UPPER(GPS_ADID)` as DEVICE_ID

**What's broken:**
- GPS_ADID doesn't match Amplitude device_id (different identifier types)
- IDFV column in ANDROID_EVENTS is 0% populated (Android doesn't have IDFV, it's iOS-only)
- ADID (Adjust's hashed identifier) also doesn't match
- Static mapping table `ADJUST_AMPLITUDE_DEVICE_MAPPING` stale since Nov 2025

**Required features to fix:**
1. **Amplitude Android device_id research** — Determine what Amplitude uses for Android device_id (App Set ID? Custom ID? User ID?)
2. **GPS_ADID → Amplitude device_id validation** — Test if GPS_ADID appears in Amplitude's merge_ids or custom user properties
3. **Alternative mapping strategy** — If GPS_ADID doesn't match, explore user_id-based mapping (require logged-in users) or IP-based probabilistic matching
4. **Platform-specific tests** — Separate Android mapping tests from iOS (different ID types, different failure modes)

### Attribution ID Mapping (Industry Context)

Per Amplitude documentation (2025-2026), Amplitude's Attribution API handles ID mapping:
- **Mobile attribution partners** (like Adjust) identify events using IDFA/IDFV/ADID
- **Amplitude** identifies users using `user_id`, `device_id`, and `amplitude_id`
- **Amplitude stores unmapped events for 72 hours**, looking for matching IDFA/IDFV/ADID on existing users
- **After 72 hours**, unmapped attribution events are dropped

**Implication:** WGT's manual device mapping (`int_adjust_amplitude__device_mapping`) may be fighting against Amplitude's built-in attribution logic. Consider:
1. **Use Amplitude Attribution API directly** instead of manual mapping (if available in WGT's Amplitude plan)
2. **Validate 72-hour window** — Are Adjust events arriving within 72 hours of Amplitude events? Late-arriving data gets dropped
3. **Check Amplitude attribution events** — Query Amplitude's attribution tables to see if mapping already happened upstream

## Competitor Feature Analysis

| Feature | dbt-expectations (package) | Elementary Data (observability) | Our Approach |
|---------|----------------------------|--------------------------------|--------------|
| Source freshness | Basic (dbt native) | Advanced (anomaly detection, ML) | Use dbt native freshness tests (adequate for WGT's hourly/daily SLAs) |
| Unique/not_null tests | Basic (dbt native) | Basic (dbt native + alerting) | Use dbt native tests; add to CI/CD gates |
| Referential integrity | `relationships` test (dbt native) | `relationships` + orphan detection | Use dbt native; add custom tests for platform-specific orphans |
| Data quality dashboards | None (test results in logs) | Pre-built dashboards | Defer to v2+; dbt Cloud test UI sufficient for now |
| Anomaly detection | `expect_*` tests (static thresholds) | ML-based anomaly detection | Use diagnostics table + static thresholds (100+ devices/user) |
| Freshness SLA enforcement | `warn_after`/`error_after` (dbt native) | Adaptive SLAs based on historical trends | Use dbt native with fixed SLAs (adequate for known refresh schedules) |

## Sources

- [Testing data sources in dbt - #dbtips](https://dbtips.substack.com/p/testing-data-sources-in-dbt)
- [What Is Dbt Testing? Definition, Best Practices, And More](https://www.montecarlodata.com/blog-what-is-dbt-testing-definition-best-practices-and-more/)
- [How to use dbt source freshness tests to detect stale data | Datafold](https://www.datafold.com/blog/dbt-source-freshness)
- [dbt tests: How to write fewer and better data tests?](https://www.elementary-data.com/post/dbt-tests)
- [Source freshness | dbt Developer Hub](https://docs.getdbt.com/docs/deploy/source-freshness)
- [Add data tests to your DAG | dbt Developer Hub](https://docs.getdbt.com/docs/build/data-tests)
- [7 dbt Testing Best Practices | Datafold](https://www.datafold.com/blog/7-dbt-testing-best-practices)
- [A Comprehensive Guide to dbt Tests to Ensure Data Quality | DataCamp](https://www.datacamp.com/tutorial/dbt-tests)
- [dbt Tests Explained: Generic vs Singular (With Real Examples) | Medium](https://medium.com/@likkilaxminarayana/dbt-tests-explained-generic-vs-singular-with-real-examples-6c08d8dd78a7)
- [Missing mobile attribution events | Amplitude](https://amplitude.com/docs/faq/missing-mobile-attribution-events)
- [Accepted device identifiers | Adjust Help Center](https://help.adjust.com/en/article/device-identifiers)
- [Troubleshooting: Missing mobile attribution events – Amplitude](https://amplitude.zendesk.com/hc/en-us/articles/360051234592-Troubleshooting-Missing-mobile-attribution-install-uninstall-events)
- [What is IDFV? | AppsFlyer mobile glossary](https://www.appsflyer.com/glossary/idfv/)
- [Track unique users | Amplitude](https://amplitude.com/docs/data/sources/instrument-track-unique-users)
- [DRY principles: How to write efficient SQL | dbt Labs](https://docs.getdbt.com/terms/dry)
- [dbt macros: What they are and why you should use them | Metaplane](https://www.metaplane.dev/blog/dbt-macros)
- [Jinja and macros | dbt Developer Hub](https://docs.getdbt.com/docs/build/jinja-macros)
- [Incremental models in-depth | dbt Developer Hub](https://docs.getdbt.com/best-practices/materializations/4-incremental-models)
- [How to Configure dbt Incremental Models](https://oneuptime.com/blog/post/2026-01-27-dbt-incremental-models/view)
- [Testing incremental models - dbt Community Forum](https://discourse.getdbt.com/t/testing-incremental-models/1528)
- [Understanding Mobile Device ID Tracking in 2026 - Ingest Labs](https://ingestlabs.com/mobile-device-id-tracking-guide/)
- [What is IDFA? Identifier for Advertisers (2026 Update; After ATT)](https://adjoe.io/glossary/idfa-identifier-for-advertisers/)
- [How to use dbt source freshness tests to detect stale data | Datafold](https://www.datafold.com/blog/dbt-source-freshness)
- [Guide to Using dbt Source Freshness for Data Updates | Secoda](https://www.secoda.co/learn/dbt-source-freshness)
- [Data Freshness: Best Practices & Key Metrics to Measure | Elementary Data](https://www.elementary-data.com/post/data-freshness-best-practices-and-key-metrics-to-measure-success)
- [5 essential data quality checks for analytics | dbt Labs](https://www.getdbt.com/blog/data-quality-checks)

---
*Feature research for: dbt Analytics — Device ID Resolution & Data Quality Testing*
*Researched: 2026-02-10*
