# Pitfalls Research

**Domain:** Device ID Mapping Fixes & dbt Testing Adoption for Existing dbt + Snowflake Analytics
**Researched:** 2026-02-10
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Changing Device ID Logic in Staging Models Breaks Incremental Downstream Models

**What goes wrong:**
Modifying device ID normalization logic (e.g., adding UPPER() transforms, stripping Android 'R' suffix) in staging models causes existing incremental downstream models to have a mix of old and new device IDs. This creates duplicate user records (same user appears twice with different device IDs) or missing data (old device ID can't join to new device ID in attribution).

**Why it happens:**
The merge strategy in incremental models only updates rows where the `unique_key` matches. If you change how device IDs are normalized in the staging layer, the new normalized device IDs won't match the old denormalized device IDs already in the incremental model. The incremental model will INSERT new rows instead of UPDATE existing rows, creating duplicates.

**Specific risk in WGT project:**
- `v_stg_adjust__touchpoints` uses `unique_key=['PLATFORM', 'TOUCHPOINT_TYPE', 'TOUCHPOINT_EPOCH', 'NETWORK_NAME', 'CAMPAIGN_ID', 'IP_ADDRESS']` but doesn't include DEVICE_ID in the key
- If Android device ID normalization changes from `GPS_ADID` to `UPPER(GPS_ADID)`, touchpoints will duplicate (same touchpoint with two different device IDs)
- `v_stg_amplitude__merge_ids` already applies `UPPER()` and strips Android 'R' suffix, but if this logic changes, the `unique_key=['DEVICE_ID_UUID', 'USER_ID_INTEGER', 'PLATFORM']` will cause duplicates
- All marts (`mart_campaign_performance_full`, `mart_campaign_performance_full_mta`) use incremental merge and will accumulate stale device mappings

**How to avoid:**
1. **Phase 0 (Audit):** Document the current device ID format in every incremental model that includes device IDs in joins or unique keys
2. **Phase 1 (Add Tests First):** Add uniqueness tests on device ID columns BEFORE changing normalization logic to detect duplicates immediately
3. **Phase 2 (Backfill Strategy):** When changing normalization logic:
   - Full-refresh the staging model AND all downstream incremental models using `dbt run --full-refresh --select model_name+` (the `+` includes downstream dependencies)
   - Use a migration window: add normalized_device_id as a NEW column, backfill it, then deprecate the old column
4. **Phase 3 (Verification):** After full-refresh, run row count comparisons (before vs after) and uniqueness tests to verify no duplicates introduced

**Warning signs:**
- Row counts in incremental models suddenly increase after a device ID logic change
- Uniqueness tests on `unique_key` columns fail (if tests exist)
- User journey reports show the same user with multiple device IDs
- Attribution discrepancies increase (same install attributed twice)

**Phase to address:**
- **Phase 1: Test Foundation** - Add uniqueness tests as baseline
- **Phase 2: Device ID Audit** - Document current normalization and plan migration
- **Phase 3: Refactor with Backfill** - Execute device ID fixes with full-refresh strategy

---

### Pitfall 2: Full-Refresh Invalidates D30 Cohort Windows

**What goes wrong:**
Running `dbt run --full-refresh` on incremental models that calculate D7/D30 retention or revenue cohorts will reset the historical window. Models like `mart_campaign_performance_full` calculate D30_REVENUE, but after a full-refresh, only NEW data is available. Users installed 30 days ago will have incomplete D30 metrics until 30 days pass again.

**Why it happens:**
Incremental models with cohort logic rely on historical context. A full-refresh deletes the existing table and rebuilds from the `is_incremental() = false` logic, which typically has a limited lookback window (e.g., 35 days in `mart_campaign_performance_full`). The 35-day lookback is NOT enough to recalculate D30 metrics for cohorts older than 35 days.

**Specific risk in WGT project:**
- `mart_campaign_performance_full` has a 35-day lookback: `WHERE INSTALL_DATE >= DATEADD(day, -35, (SELECT MAX(DATE) FROM {{ this }}))`
- If you full-refresh on Feb 10, only installs from Jan 6 onward are included
- Cohorts from Jan 1-5 lose their D30 revenue data permanently (unless you rebuild from raw sources with no date filter)
- Marketing team reports will show a "revenue drop" for early January cohorts, which is a data artifact, not a real business change

**How to avoid:**
1. **Before full-refresh:** Export the current incremental table to a backup (e.g., `CREATE TABLE backup_mart AS SELECT * FROM mart_campaign_performance_full`)
2. **Temporary full-history mode:** During full-refresh, override the date filter with `dbt run --full-refresh --vars '{"full_history_mode": true}'` and add logic in the model:
   ```sql
   {% if is_incremental() and not var('full_history_mode', false) %}
     WHERE INSTALL_DATE >= DATEADD(day, -35, (SELECT MAX(DATE) FROM {{ this }}))
   {% else %}
     -- Full refresh: include all data (no date filter)
   {% endif %}
   ```
3. **Validate cohort completeness:** After full-refresh, check that D30 metrics exist for cohorts 30+ days old
4. **Only full-refresh when necessary:** Use full-refresh sparingly. For device ID fixes, consider a "shadow column" approach (add new column, backfill, then swap) instead of full-refresh.

**Warning signs:**
- D30 revenue metrics are NULL for cohorts that previously had data
- Row counts drop significantly after full-refresh (old cohorts missing)
- Date range in the table is shorter than expected (e.g., only 35 days instead of 6 months)

**Phase to address:**
- **Phase 2: Device ID Audit** - Document full-refresh risks and cohort dependencies
- **Phase 3: Refactor with Backfill** - Implement full_history_mode variable for safe full-refresh

---

### Pitfall 3: Refactoring AD_PARTNER CASE Logic Changes Attribution Without Detection

**What goes wrong:**
The AD_PARTNER mapping CASE statement is duplicated in `v_stg_adjust__installs` and `v_stg_adjust__touchpoints`. If you refactor this into a macro or seed table, even a small logic difference (e.g., case sensitivity, new network added to only one place) will cause attribution mismatches. Installs may be attributed to "Meta" while touchpoints are attributed to "Facebook Installs", breaking multi-touch attribution joins.

**Why it happens:**
The CASE statement has 15+ conditions (Meta, Google, TikTok, etc.) and is manually duplicated. When refactoring to a macro, developers might:
- Add/remove a condition in one place but not the other
- Change the order of conditions (which matters for overlapping patterns like `LIKE 'AppLovin%'` vs exact matches)
- Introduce a typo in the macro that differs from the original

Without tests that verify both models produce **identical** AD_PARTNER values for the same NETWORK_NAME, the drift goes undetected until attribution reports show discrepancies.

**Specific risk in WGT project:**
- `v_stg_adjust__installs.sql` lines 65-83: AD_PARTNER CASE statement
- `v_stg_adjust__touchpoints.sql` lines 136-154: AD_PARTNER CASE statement
- Both are identical TODAY, but if you refactor to a macro `{{ map_ad_partner('NETWORK_NAME') }}`, any difference will break attribution
- The `network_mapping.csv` seed already exists for spend data but uses different column names (ADJUST_NETWORK_NAME, SUPERMETRICS_PARTNER_NAME) and may not have all touchpoint network names
- If you migrate to the seed, missing network names will map to NULL instead of 'Other', causing joins to fail

**How to avoid:**
1. **Phase 1 (Baseline Test):** Before refactoring, add a custom test that verifies both models produce the same AD_PARTNER for every NETWORK_NAME:
   ```sql
   -- tests/assert_ad_partner_mapping_consistent.sql
   WITH installs AS (
     SELECT DISTINCT NETWORK_NAME, AD_PARTNER
     FROM {{ ref('v_stg_adjust__installs') }}
   ),
   touchpoints AS (
     SELECT DISTINCT NETWORK_NAME, AD_PARTNER
     FROM {{ ref('v_stg_adjust__touchpoints') }}
   ),
   mismatches AS (
     SELECT i.NETWORK_NAME, i.AD_PARTNER AS install_ad_partner, t.AD_PARTNER AS touchpoint_ad_partner
     FROM installs i
     FULL OUTER JOIN touchpoints t USING (NETWORK_NAME)
     WHERE i.AD_PARTNER != t.AD_PARTNER OR i.AD_PARTNER IS NULL OR t.AD_PARTNER IS NULL
   )
   SELECT * FROM mismatches
   ```
2. **Phase 2 (Refactor Incrementally):**
   - First, create the macro but don't use it yet
   - Add the macro call as a NEW column (e.g., AD_PARTNER_NEW) alongside the existing AD_PARTNER
   - Run the consistency test to verify AD_PARTNER = AD_PARTNER_NEW
   - Only after test passes, replace AD_PARTNER with the macro
3. **Phase 3 (Seed Migration):** If migrating to `network_mapping.csv`:
   - Add ALL network names from both models to the seed (use `SELECT DISTINCT NETWORK_NAME FROM v_stg_adjust__installs UNION SELECT DISTINCT NETWORK_NAME FROM v_stg_adjust__touchpoints`)
   - Add a default fallback: `COALESCE(seed.AD_PARTNER, 'Other')`
   - Test that no network names map to NULL

**Warning signs:**
- Attribution install counts diverge from touchpoint counts for the same campaign
- MTA reports show "Unattributed" or "Other" for networks that previously had specific AD_PARTNER values
- Join cardinality between `int_user_cohort__attribution` and `int_mta__user_journey` changes unexpectedly

**Phase to address:**
- **Phase 1: Test Foundation** - Add AD_PARTNER consistency test
- **Phase 4: Refactor Shared Logic** - Execute macro/seed migration with shadow column approach

---

### Pitfall 4: Adding dbt Tests to Zero-Test Project Floods with False Positives

**What goes wrong:**
When adopting dbt tests on an existing project with zero tests, running `dbt test` for the first time reveals hundreds of data quality issues that have existed for months. Teams face decision paralysis: fix all issues before proceeding (blocks progress), or ignore failures (defeats the purpose of testing). The flood of test failures makes it impossible to distinguish critical issues from cosmetic ones.

**Why it happens:**
Existing data has accumulated quality issues that were invisible without tests:
- NULL device IDs in attribution models (historical data before validation)
- Duplicate rows in incremental models (from past full-refresh bugs)
- Invalid platform values (e.g., "ios" vs "iOS" vs NULL)
- Referential integrity violations (user IDs in metrics table that don't exist in device mapping)

Adding tests reveals these issues all at once. Without a prioritization strategy, teams either:
- Disable tests to "unblock" progress (tests become ignored documentation)
- Spend weeks fixing historical data before adding new features (testing becomes a blocker)

**Specific risk in WGT project:**
- Currently **zero** tests in `tests/` directory (only `.gitkeep`)
- All incremental models have `unique_key` defined but never verified
- Device ID normalization has evolved (Android 'R' suffix workaround, UPPER() added in some places but not others)
- Platform values are inconsistent (joins use `LOWER(PLATFORM)` defensively, indicating known casing issues)
- If you add standard tests (unique + not_null on all unique_keys), expect failures on:
  - `v_stg_adjust__touchpoints`: unique_key includes IP_ADDRESS which can be NULL for Android
  - `v_stg_amplitude__merge_ids`: historical data may have NULL user IDs or device IDs
  - Platform columns: may have NULL or unexpected values like "android" instead of "Android"

**How to avoid:**
1. **Phase 1 (Selective Testing):** Start with **forward-looking** tests on NEW data only:
   - Add tests with `where` clauses: `where: "created_at >= '2026-02-01'"` to only validate recent data
   - Focus on critical models first: staging models that feed attribution (installs, touchpoints, merge_ids)
   - Test only primary keys initially; defer column-level tests to later phases
2. **Phase 2 (Triage Test Failures):**
   - Run tests on full history to inventory failures
   - Classify failures by severity:
     - **CRITICAL:** Breaks downstream joins (NULL device IDs in attribution models)
     - **MODERATE:** Incorrect aggregations (duplicate rows in incremental models)
     - **COSMETIC:** Inconsistent casing (platform = "ios" vs "iOS" but handled by LOWER() in joins)
   - Fix CRITICAL issues immediately; document MODERATE/COSMETIC as known issues to fix later
3. **Phase 3 (Incremental Backfill):**
   - For CRITICAL issues in historical data, run targeted backfills (e.g., UPDATE to normalize platform casing)
   - For MODERATE issues, plan a maintenance window to full-refresh affected incremental models
   - For COSMETIC issues, fix the source but don't backfill historical data
4. **Phase 4 (Expand Test Coverage):**
   - Only after critical tests are stable (passing on new data), add more tests incrementally
   - Add one test category at a time (e.g., all uniqueness tests, then all not_null tests, then referential integrity)
   - Never add 50+ tests at once; add 5-10 tests, stabilize them, then add the next 5-10

**Warning signs:**
- `dbt test` takes 30+ minutes and returns 200+ failures
- Team debates whether to "fix all the red" or "ignore tests for now"
- Tests get disabled or removed after initial adoption attempt
- New tests are never added because "we're still fixing the backlog"

**Phase to address:**
- **Phase 1: Test Foundation** - Add forward-looking tests on critical models only
- **Phase 5: Expand Test Coverage** - After critical tests stabilize, add comprehensive test suite

---

### Pitfall 5: Source Freshness Checks Fail on Shared Databases Without loaded_at_field

**What goes wrong:**
Adding `source freshness` checks requires a `loaded_at_field` to query when data was last loaded. Shared Snowflake databases (e.g., ADJUST_S3, AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE) may not have a consistent timestamp column indicating freshness. Freshness checks fail with "column not found" errors, or worse, use the wrong column (e.g., event_time instead of loaded_at_time) and report stale data as fresh.

**Why it happens:**
Source freshness in dbt assumes you control the source schema and have a metadata column like `_loaded_at` or `_etl_timestamp`. Shared databases from external vendors (Adjust S3 exports, Amplitude data shares) often have:
- **Event timestamps** (CREATED_AT, INSTALLED_AT) but no load timestamps
- **Snowflake metadata** (LAST_ALTERED in INFORMATION_SCHEMA) but this reflects table-level changes, not row-level freshness
- **No consistent column** across all tables (some have SERVER_UPLOAD_TIME, others don't)

If you configure `loaded_at_field: CREATED_AT`, freshness checks will report data as "fresh" even if the ETL pipeline broke days ago (because the latest CREATED_AT is still recent).

**Specific risk in WGT project:**
- `ADJUST_S3.PROD_DATA.*` tables: Android and iOS activity tables may have CREATED_AT (event creation time) but no _LOADED_AT
- `AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.AMPLITUDE.EVENTS_726530`: Has SERVER_UPLOAD_TIME which approximates loaded_at, but may lag by hours
- `SUPERMETRICS.*` tables: Unknown schema; may or may not have ETL timestamps
- `WGT.REVENUE_PROD.*` tables: Internal database; likely has ETL metadata but needs verification

**How to avoid:**
1. **Phase 1 (Audit Source Schemas):** For each source database, identify what timestamp columns exist:
   ```sql
   -- Run for each source table
   SHOW COLUMNS IN ADJUST_S3.PROD_DATA.IOS_ACTIVITY_INSTALL;
   SELECT COLUMN_NAME, DATA_TYPE FROM RESULT WHERE DATA_TYPE LIKE '%TIMESTAMP%';
   ```
2. **Phase 2 (Snowflake Metadata Fallback):** For sources without loaded_at_field, use Snowflake's LAST_ALTERED from metadata:
   - dbt 1.5+ supports freshness checks without `loaded_at_field` on Snowflake by querying INFORMATION_SCHEMA.TABLES
   - This works but is table-level (not row-level), so it only detects if the table stopped updating entirely
3. **Phase 3 (Proxy Timestamps):** For event tables, use event_time as a proxy:
   ```yaml
   sources:
     - name: adjust
       tables:
         - name: IOS_ACTIVITY_INSTALL
           loaded_at_field: CREATED_AT  # Proxy: event time, not load time
           freshness:
             warn_after: {count: 6, period: hour}  # Events should be near real-time
   ```
   - Document that this is a proxy and may miss ETL failures where events still flow but are delayed
4. **Phase 4 (Alerting Strategy):** Set conservative thresholds:
   - For event-time proxies, use longer windows (e.g., warn_after 6 hours instead of 1 hour) to account for event time lag
   - For metadata-based checks, accept they only catch complete pipeline failures (not delays)
   - Supplement with external monitoring (e.g., check Fivetran/Airbyte logs directly)

**Warning signs:**
- `dbt source freshness` fails with "column LOADED_AT does not exist"
- Freshness checks always pass even when you know the pipeline broke
- Freshness tests report warnings during known good periods (false positives due to event time lag)

**Phase to address:**
- **Phase 1: Test Foundation** - Audit source schemas for timestamp columns
- **Phase 6: Source Freshness** - Add freshness checks with proxy timestamps and conservative thresholds

---

### Pitfall 6: iOS Low Match Rate Attributed to Data Issue When It's Structural

**What goes wrong:**
Discovering that iOS device IDs have only a 1.4% match rate between Adjust touchpoints and Amplitude installs leads teams to assume there's a data quality bug (normalization issue, missing fields). They spend weeks investigating device ID formats, UPPER() transforms, and schema changes, only to discover the low match rate is **structural**: iOS touchpoints have IDFA (ad identifier) but installs have IDFV (vendor identifier), and Apple's ATT framework means 70-80% of users don't consent to IDFA tracking.

**Why it happens:**
iOS attribution uses two different identifier types:
- **Touchpoints (impressions/clicks):** Use IDFA (Identifier for Advertisers) which requires user consent via ATT
- **Installs:** Use IDFV (Identifier for Vendors) which is available without consent but only tracks users within the same vendor's apps

These are **fundamentally different identifiers** that cannot be joined deterministically. Most iOS users (75%+) decline ATT consent, so their IDFA is NULL or zeroed out. Even if you perfectly normalize device IDs, you can't join NULL IDFA (touchpoint) to non-NULL IDFV (install).

The 1.4% match rate represents:
- Users who consented to ATT AND clicked an ad AND installed
- This is expected given ~25% ATT consent rate × click-through rate × conversion rate

**Specific risk in WGT project:**
- Project context notes "iOS low match rate (1.4%) may be structural — touchpoint devices that never install can't appear in Amplitude"
- `v_stg_adjust__touchpoints` includes IDFA for iOS but it's NULL for 89% of clicks and 96% of impressions
- `v_stg_adjust__installs` uses IDFV as DEVICE_ID, which has no relationship to IDFA
- The project already falls back to IP_ADDRESS matching for iOS (probabilistic), which is the correct approach

**How to avoid:**
1. **Phase 0 (Education):** Document iOS attribution limitations in project README:
   - IDFA ≠ IDFV (cannot be joined)
   - ATT consent rate is ~25%, so expect 75% of iOS touchpoints to have NULL IDFA
   - IP-based matching is probabilistic, not deterministic; some mismatch is expected
2. **Phase 1 (Baseline Metrics):** Establish baseline match rates BEFORE making changes:
   - iOS IDFA match rate: ~1.4% (deterministic matches)
   - iOS IP match rate: ~40-60% (probabilistic matches via IP_ADDRESS + timestamp window)
   - Android GPS_ADID match rate: ~90%+ (deterministic matches)
3. **Phase 2 (Don't Over-Fix):** When improving device ID normalization:
   - DO fix Android GPS_ADID normalization (UPPER(), strip 'R' suffix) to improve Android match rate
   - DO fix iOS IDFV normalization for install tracking
   - DON'T expect iOS IDFA match rate to significantly improve (it's capped by ATT consent rate)
   - DON'T spend weeks investigating why iOS match rate is "low" when it's structural
4. **Phase 3 (Accept Probabilistic Matching):** For iOS, invest in improving IP-based matching quality:
   - Tighten timestamp windows (e.g., match touchpoint to install within 1 hour instead of 24 hours)
   - Add user-agent or geolocation filters (same country, same device model)
   - Accept that iOS attribution will always be less precise than Android

**Warning signs:**
- Team debates "why is iOS match rate so low, is the data broken?"
- Stakeholders expect iOS match rate to reach Android levels (90%+)
- Multiple refactors of iOS device ID logic don't improve match rate
- iOS attribution improvement becomes a multi-week blocking task

**Phase to address:**
- **Phase 0: Documentation** - Document iOS ATT limitations and expected match rates
- **Phase 2: Device ID Audit** - Baseline current match rates before changes

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Adding tests with `where: "created_at >= '2026-02-01'"` to only validate new data | Avoids fixing historical data quality issues; unblocks testing adoption | Historical data quality issues persist; tests don't catch regressions in old cohorts | **Acceptable** during initial testing adoption; backfill historical data in Phase 3+ |
| Using event timestamp (CREATED_AT) as proxy for loaded_at_field in source freshness | Enables freshness checks on shared databases without ETL metadata | Misses ETL delays where events flow but are stale; may report fresh when pipeline is slow | **Acceptable** when no ETL metadata exists; supplement with external monitoring |
| Keeping duplicated AD_PARTNER CASE statement in two models during migration | Avoids breaking existing logic during refactor | Risk of drift if one model gets updated but not the other | **Only acceptable** for 1-2 sprints during migration; must have consistency test |
| Full-refresh incremental models to fix device ID normalization | Simplest way to apply normalization change to all historical data | Loses D30 cohort context for 30 days; query cost for full table scan | **Acceptable** if combined with full_history_mode variable to include all data |
| Using LOWER(PLATFORM) in joins instead of fixing source data casing | Defensive coding prevents join failures from casing inconsistencies | Slower joins (can't use indexes on LOWER()); hides underlying data quality issue | **Never acceptable** long-term; fix source data normalization in staging layer |
| Skipping uniqueness tests on incremental models to avoid test failures | Unblocks deployment; avoids fixing duplicate row issues | Incremental merge logic silently breaks; duplicates accumulate over time | **Never acceptable**; uniqueness on `unique_key` is mandatory for incremental models |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Snowflake shared databases (Adjust, Amplitude) | Assuming all tables have `_loaded_at` or ETL metadata columns | Audit schema first; use Snowflake metadata (LAST_ALTERED) or event timestamp proxy |
| Amplitude EVENTS table | Querying full table without date filter (causes timeouts) | Always filter by SERVER_UPLOAD_TIME in WHERE clause; use incremental models |
| Adjust S3 exports | Expecting device IDs to be normalized (uppercase, no special characters) | Apply UPPER() normalization in staging layer; Android has trailing 'R' to strip |
| network_mapping.csv seed | Assuming all network names are mapped; missing names cause NULL joins | Add COALESCE(seed.AD_PARTNER, 'Other') fallback; test for unmapped networks |
| Refactoring CASE statement to macro | Deploying macro without verifying compiled SQL matches original | Add shadow column with macro output; test original = macro before switching |
| iOS IDFA tracking | Expecting deterministic device ID matches like Android | Use IP_ADDRESS + timestamp window for probabilistic matching; accept <5% IDFA match rate due to ATT |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full table scan on incremental models during device ID refactor | Query times increase from seconds to minutes; Snowflake credits spike | Use `dbt run --select model_name+` to full-refresh staging + downstream together; avoid multiple full-refreshes | > 10M rows in incremental model; compound with multiple downstream marts |
| Testing all models with full history on first `dbt test` run | Test run takes 30+ minutes; Snowflake query timeout errors | Add `where: "created_at >= '2026-02-01'"` to tests; test new data only initially | > 100M rows in tested models; multiple joins in custom tests |
| Querying INFORMATION_SCHEMA for source freshness on every dbt run | Adds 1-2 seconds per source; compounds with 10+ sources | Use `dbt source freshness` as separate scheduled job, not in every run | > 20 sources; scheduled every 15 minutes |
| Adding 50+ tests at once without test selection | CI pipeline times out; developers avoid running tests locally | Add tests incrementally (5-10 per sprint); use `dbt test --select model_name` for targeted testing | > 100 tests; each test scans millions of rows |
| Custom test with FULL OUTER JOIN on large models | Test query takes 10+ minutes; fails in CI with timeout | Use sampling for custom tests: `WHERE RANDOM() < 0.01` to test 1% of data | Testing models with > 50M rows each; cartesian join risk |

---

## "Looks Done But Isn't" Checklist

- [ ] **Device ID normalization refactor:** Verify full-refresh was run on staging + ALL downstream incremental models (use `dbt run --full-refresh --select model_name+` to ensure downstream cascade)
- [ ] **dbt tests added:** Verify tests are not all disabled with `config(enabled=false)` or `--exclude test_type:data` in production runs
- [ ] **AD_PARTNER mapping refactored to macro/seed:** Verify consistency test exists and passes (tests that both models produce identical AD_PARTNER for same NETWORK_NAME)
- [ ] **Source freshness checks:** Verify loaded_at_field column actually exists in source table (run `SHOW COLUMNS` query to confirm)
- [ ] **Incremental model refactor:** Verify `is_incremental()` logic was tested with BOTH full-refresh (`--full-refresh`) and incremental run (second run after full-refresh)
- [ ] **Uniqueness tests on incremental models:** Verify test includes ALL columns in `unique_key` config (tests often miss composite key columns)
- [ ] **Full-refresh with cohort windows:** Verify full_history_mode or equivalent logic was used to avoid losing D30 cohort data (check that MAX(date) - MIN(date) is still 180+ days after full-refresh)
- [ ] **iOS attribution improvement:** Verify expectations are set with stakeholders that IDFA match rate will remain <5% due to ATT (not a data quality bug)

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Duplicates in incremental model after device ID normalization change | **HIGH** (requires full-refresh + 30 days to recalculate cohorts) | 1. Export current table to backup 2. Audit duplicates: `SELECT unique_key, COUNT(*) GROUP BY unique_key HAVING COUNT(*) > 1` 3. Delete duplicates with DELETE/MERGE 4. If duplicates are widespread, full-refresh staging + downstream models 5. Validate row counts and D30 metrics |
| AD_PARTNER mapping drift between installs and touchpoints | **MEDIUM** (requires data backfill for mismatched period) | 1. Identify drift period: `SELECT MIN(date), MAX(date) FROM mismatches` 2. Run consistency test to find affected network names 3. Backfill using: `dbt run --select model_name --full-refresh --vars '{"start_date": "2026-01-15", "end_date": "2026-02-10"}'` 4. Verify attribution counts match before/after |
| Test failures flood after initial testing adoption | **LOW** (triage and prioritize; fix incrementally) | 1. Export test results: `dbt test --store-failures` 2. Classify failures by severity (CRITICAL/MODERATE/COSMETIC) 3. Fix CRITICAL failures immediately 4. Disable MODERATE tests with `config(enabled=false, severity=warn)` and document as known issues 5. Ignore COSMETIC failures; fix source but don't backfill |
| Source freshness false positives due to wrong loaded_at_field | **LOW** (reconfigure and re-run) | 1. Audit source schema: `SHOW COLUMNS IN table` 2. Identify correct timestamp column or use Snowflake metadata 3. Update sources.yml with correct loaded_at_field or remove it to use metadata 4. Adjust warn_after/error_after thresholds to account for event time lag 5. Run `dbt source freshness` to validate |
| Lost D30 cohort data after full-refresh | **HIGH** (30-day wait to recalculate OR restore from backup) | 1. If backup exists: restore incremental model from backup and re-run only new data 2. If no backup: Accept data loss; wait 30 days for cohorts to mature 3. Future prevention: Add full_history_mode variable to allow full-refresh without losing cohorts |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Changing device ID logic breaks incremental downstream | Phase 2: Device ID Audit + Phase 3: Refactor with Backfill | Row counts match before/after full-refresh; uniqueness tests pass |
| Full-refresh invalidates D30 cohort windows | Phase 3: Refactor with Backfill | D30 metrics exist for cohorts 30+ days old; date range in table is 180+ days |
| AD_PARTNER refactor causes attribution mismatches | Phase 1: Test Foundation + Phase 4: Refactor Shared Logic | Consistency test passes; attribution install counts match touchpoint counts |
| Test adoption floods with false positives | Phase 1: Test Foundation (forward-looking tests only) | Critical tests pass on new data; test run time < 5 minutes |
| Source freshness fails without loaded_at_field | Phase 6: Source Freshness | `dbt source freshness` completes without errors; alerts fire during known pipeline outages |
| iOS low match rate assumed to be data bug | Phase 0: Documentation + Phase 2: Device ID Audit | Stakeholders understand ATT limitations; iOS IDFA match rate expectations set at <5% |

---

## Sources

**dbt Incremental Models & Testing:**
- [Incremental models in-depth | dbt Developer Hub](https://docs.getdbt.com/best-practices/materializations/4-incremental-models)
- [About incremental strategy | dbt Developer Hub](https://docs.getdbt.com/docs/build/incremental-strategy)
- [unique_key | dbt Developer Hub](https://docs.getdbt.com/reference/resource-configs/unique_key)
- [7 dbt Testing Best Practices | Datafold](https://www.datafold.com/blog/7-dbt-testing-best-practices)
- [What data tests should I add to my project? | dbt Developer Hub](https://docs.getdbt.com/faqs/Tests/recommended-tests)

**Refactoring & Change Management:**
- [Configure incremental models | dbt Developer Hub](https://docs.getdbt.com/docs/build/incremental-models)
- [Ultimate Guide to dbt Macros in 2025 | Dagster](https://dagster.io/guides/ultimate-guide-to-dbt-macros-in-2025-syntax-examples-pro-tips)
- [Working with the SQL CASE statements - dbt Docs](https://docs.getdbt.com/sql-reference/case)

**Source Freshness:**
- [freshness | dbt Developer Hub](https://docs.getdbt.com/reference/resource-properties/freshness)
- [Source freshness | dbt Developer Hub](https://docs.getdbt.com/docs/deploy/source-freshness)
- [How to use dbt source freshness tests | Datafold](https://www.datafold.com/blog/dbt-source-freshness)

**Mobile Device ID & Attribution:**
- [Understanding Mobile Device ID Tracking in 2026 - Ingest Labs](https://ingestlabs.com/mobile-device-id-tracking-guide/)
- [Cross-Device Analytics: The Complete Guide | Improvado](https://improvado.io/blog/cross-device-analytics)

**Project-Specific:**
- WGT dbt project codebase analysis (2026-02-10)
- `.planning/codebase/CONCERNS.md` (technical debt audit)

---

*Pitfalls research for: Device ID Mapping Fixes & dbt Testing Adoption (WGT dbt Project)*
*Researched: 2026-02-10*
