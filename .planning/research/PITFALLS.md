# Domain Pitfalls: Adding Pipeline Hardening to Existing dbt Project

**Domain:** Snowflake/dbt Cloud pipeline hardening (source freshness, singular tests, macro extraction)
**Project Context:** WGT dbt Analytics - adding production monitoring to existing MMM pipeline
**Researched:** 2026-02-11

**WARNING:** This is NOT generic dbt best practices. These are integration pitfalls specific to adding source freshness, singular tests, and macro extraction to an EXISTING dbt project with incremental models, no local dbt environment, and cross-source dependencies.

---

## Critical Pitfalls

Mistakes that cause rewrites, data errors, or production incidents.

### Pitfall 1: Source Freshness on Static Tables Without Timestamps

**What goes wrong:** Configuring `loaded_at_field` for static reference tables that lack timestamp columns causes `dbt source freshness` to fail with "column does not exist" errors, blocking the entire freshness job.

**Real scenario (WGT):** `ADJUST_AMPLITUDE_DEVICE_MAPPING` is a stale static table (1.55M rows, last updated Nov 2025) with no `_LOADED_AT` or equivalent timestamp. Adding freshness checks without a timestamp column fails immediately.

**Why it happens:**
- dbt requires a timestamp column to calculate `max(loaded_at_field)` for freshness
- Some warehouses support metadata-based freshness (BigQuery, Databricks), but **Snowflake does NOT** — you must specify `loaded_at_field`
- Static tables created from manual uploads or one-time loads often lack ETL timestamp columns

**Consequences:**
- Freshness job fails completely (not just for the static table, but the entire `dbt source freshness` run)
- Cannot detect staleness for tables that actually need monitoring
- Workarounds (adding dummy timestamp columns) pollute table structure

**Prevention:**
1. **Audit before configuration:** Query `INFORMATION_SCHEMA.COLUMNS` for all source tables to identify which have timestamp columns
   ```sql
   SELECT table_name, column_name, data_type
   FROM INFORMATION_SCHEMA.COLUMNS
   WHERE schema_name = 'S3_DATA'
     AND data_type IN ('TIMESTAMP_NTZ', 'TIMESTAMP_LTZ', 'TIMESTAMP_TZ', 'DATE')
   ORDER BY table_name, column_name;
   ```

2. **Omit freshness config for static tables:** If a table lacks a timestamp, don't configure `warn_after`/`error_after`. Per dbt docs: "If neither warn_after nor error_after is provided, then dbt will not calculate freshness snapshots for the tables in this source."

3. **Use Snowflake metadata for row count changes (alternative):** For tables without timestamps, create a singular test that compares `COUNT(*)` between runs to detect unexpected changes:
   ```sql
   -- tests/static_table_changed_unexpectedly.sql
   SELECT 'ADJUST_AMPLITUDE_DEVICE_MAPPING' AS table_name,
          COUNT(*) AS current_count
   FROM {{ source('adjust', 'ADJUST_AMPLITUDE_DEVICE_MAPPING') }}
   HAVING COUNT(*) != 1550000  -- Expected row count from Nov 2025
   ```

4. **Document WHY freshness is omitted:** Add YAML comment explaining why static table has no freshness check:
   ```yaml
   - name: ADJUST_AMPLITUDE_DEVICE_MAPPING
     description: Static device mapping (Nov 2025). No freshness check - no timestamp column exists.
     # freshness: omitted - no _LOADED_AT column, use static_table_changed_unexpectedly.sql test
   ```

**Detection:**
- Run `dbt source freshness --select source:adjust` before adding to production schedule
- Check compiled SQL in `target/compiled/` to see what query dbt generates
- Look for error: `SQL compilation error: invalid identifier 'LOADED_AT_FIELD'`

**Which phase:** Phase 6 (Source Freshness & Observability) — must resolve before scheduling freshness jobs

**Sources:**
- [dbt freshness documentation](https://docs.getdbt.com/reference/resource-properties/freshness)
- [Using a non-UTC timestamp when calculating source freshness](https://discourse.getdbt.com/t/using-a-non-utc-timestamp-when-calculating-source-freshness/1237)

---

### Pitfall 2: Wrong `loaded_at_field` — Created vs Loaded Timestamps

**What goes wrong:** Using source system creation timestamps (e.g., `CREATED_AT`, `EVENT_TIME`) instead of ETL load timestamps (e.g., `_LOADED_AT`, `_FIVETRAN_SYNCED`) makes freshness checks report the age of **data events**, not the age of **data delivery**, causing false negatives.

**Real scenario (WGT):** Adjust S3 activity tables have both `CREATED_AT` (when event happened in the app) and `LOAD_TIMESTAMP` (when S3 write occurred). Using `CREATED_AT` would show "data is fresh" even if S3 exports stopped yesterday, because old events have old timestamps.

**Why it happens:**
- Source tables often have multiple timestamp columns with different semantics
- `CREATED_AT` / `EVENT_TIME` = when the business event occurred (install, click, purchase)
- `_LOADED_AT` / `LOAD_TIMESTAMP` = when the ETL pipeline wrote the row to the warehouse
- Developers instinctively choose the "semantic" timestamp without considering ETL context

**Consequences:**
- Freshness checks pass while data pipeline is actually broken
- **Silent data staleness** — worst type of failure (no alert, but data is stale)
- Debugging incidents becomes harder ("why didn't freshness alert fire?")

**Prevention:**

1. **Identify ETL timestamps first:** For each source, document which column represents ETL load time:

   | Source | Table | ETL Timestamp | Event Timestamp | Use for Freshness |
   |--------|-------|---------------|-----------------|-------------------|
   | Adjust S3 | IOS_ACTIVITY_INSTALL | LOAD_TIMESTAMP | CREATED_AT | LOAD_TIMESTAMP |
   | Adjust S3 | ANDROID_ACTIVITY_CLICK | LOAD_TIMESTAMP | CREATED_AT | LOAD_TIMESTAMP |
   | Amplitude | EVENTS | _LOADED_AT | EVENT_TIME | _LOADED_AT |
   | Supermetrics | ADJ_CAMPAIGN | _FIVETRAN_SYNCED | DATE | _FIVETRAN_SYNCED |

2. **Test freshness logic before deployment:** Query to verify ETL timestamp progresses forward:
   ```sql
   SELECT DATE_TRUNC('hour', LOAD_TIMESTAMP) AS load_hour,
          COUNT(*) AS row_count,
          MIN(CREATED_AT) AS oldest_event,
          MAX(CREATED_AT) AS newest_event
   FROM {{ source('adjust', 'IOS_ACTIVITY_INSTALL') }}
   WHERE LOAD_TIMESTAMP >= DATEADD(day, -7, CURRENT_TIMESTAMP)
   GROUP BY 1
   ORDER BY 1 DESC;
   ```

   If `LOAD_TIMESTAMP` hours are continuous → good signal for freshness.
   If gaps exist in `LOAD_TIMESTAMP` but `CREATED_AT` is current → wrong column.

3. **Validate with intentional staleness:** Simulate stale data scenario:
   - Note current `MAX(LOAD_TIMESTAMP)`
   - Wait for `warn_after` interval to pass
   - Run `dbt source freshness`
   - Verify warning fires

4. **Document column choice in YAML:**
   ```yaml
   sources:
     - name: adjust
       tables:
         - name: IOS_ACTIVITY_INSTALL
           loaded_at_field: LOAD_TIMESTAMP  # ETL write time, not CREATED_AT (event time)
           freshness:
             warn_after: {count: 6, period: hour}
   ```

**Detection:**
- Freshness checks never warn even when pipeline issues are known
- `max(loaded_at_field)` returns dates far in the past (e.g., last event was 30 days ago)
- Data team reports "pipeline is broken" but freshness shows green

**Which phase:** Phase 6 (Source Freshness & Observability) — validate during freshness configuration

**Sources:**
- [dbt source freshness best practices](https://www.datafold.com/blog/dbt-source-freshness)
- [Add sources to your DAG](https://docs.getdbt.com/docs/build/sources)

---

### Pitfall 3: Timezone Mismatch — Local Timestamps vs UTC Comparison

**What goes wrong:** Source tables with non-UTC timestamps get compared to `CURRENT_TIMESTAMP` in UTC, causing freshness to calculate incorrect staleness intervals (off by timezone offset hours).

**Real scenario:** If Adjust `LOAD_TIMESTAMP` is in PST (UTC-8) but dbt compares it to `CURRENT_TIMESTAMP` (UTC), data loaded 4 hours ago appears to be loaded -4 hours in the future or 12 hours ago (depending on DST).

**Why it happens:**
- Snowflake `CURRENT_TIMESTAMP` returns session timezone (often UTC for service accounts)
- Source tables may store timestamps in application timezone or local warehouse timezone
- dbt's freshness calculation: `CURRENT_TIMESTAMP - max(loaded_at_field)` assumes same timezone
- Snowflake timestamp types: `TIMESTAMP_NTZ` (no timezone), `TIMESTAMP_LTZ` (local), `TIMESTAMP_TZ` (with TZ)

**Consequences:**
- Freshness warnings fire too early (if source is ahead) or too late (if source is behind)
- Intermittent false positives when DST changes occur
- Inconsistent behavior across sources with different timezone conventions

**Prevention:**

1. **Audit timestamp column types:**
   ```sql
   SELECT table_name,
          column_name,
          data_type
   FROM INFORMATION_SCHEMA.COLUMNS
   WHERE schema_name = 'S3_DATA'
     AND column_name LIKE '%TIMESTAMP%' OR column_name LIKE '%LOADED%';
   ```

2. **Convert to UTC in `loaded_at_field` expression:**
   ```yaml
   sources:
     - name: adjust
       tables:
         - name: IOS_ACTIVITY_INSTALL
           loaded_at_field: "CONVERT_TIMEZONE('America/Los_Angeles', 'UTC', LOAD_TIMESTAMP)"
           freshness:
             warn_after: {count: 6, period: hour}
   ```

3. **For TIMESTAMP_NTZ (no timezone info), document assumption:**
   ```yaml
   sources:
     - name: amplitude
       tables:
         - name: EVENTS
           loaded_at_field: _LOADED_AT  # TIMESTAMP_NTZ assumed to be UTC per Amplitude docs
           freshness:
             warn_after: {count: 12, period: hour}
   ```

4. **Test timezone conversion:**
   ```sql
   SELECT LOAD_TIMESTAMP AS original,
          CONVERT_TIMEZONE('America/Los_Angeles', 'UTC', LOAD_TIMESTAMP) AS utc_converted,
          CURRENT_TIMESTAMP AS current_utc,
          DATEDIFF(hour, CONVERT_TIMEZONE('America/Los_Angeles', 'UTC', LOAD_TIMESTAMP), CURRENT_TIMESTAMP) AS hours_old
   FROM {{ source('adjust', 'IOS_ACTIVITY_INSTALL') }}
   ORDER BY LOAD_TIMESTAMP DESC
   LIMIT 5;
   ```

**Detection:**
- Freshness warnings appear at unexpected times (e.g., warns at 2am even though load completed at 11pm)
- Hour-offset discrepancies (warns 6 hours after threshold should trigger)
- Inconsistent behavior before/after DST changes

**Which phase:** Phase 6 (Source Freshness & Observability) — validate during freshness configuration

**Sources:**
- [Timezone conversion in dbt source freshness](https://docs.getdbt.com/reference/resource-properties/freshness)
- [Snowflake timezone handling](https://docs.snowflake.com/en/sql-reference/functions/convert_timezone)

---

### Pitfall 4: Macro Extraction Changes Output Silently

**What goes wrong:** Extracting duplicated CASE statement logic into a macro introduces subtle differences in output (whitespace, NULL handling, ELSE clause) that break downstream models or change business logic without tests detecting it.

**Real scenario (WGT):** AD_PARTNER CASE statement duplicated in `v_stg_adjust__installs` and `v_stg_adjust__touchpoints`. Extracting to `{{ map_ad_partner(column_name='NETWORK_NAME') }}` must produce IDENTICAL output, including:
- Same string values ('Meta' not 'meta')
- Same NULL handling (ELSE 'Other' vs ELSE NULL)
- Same trimming/casing behavior

**Why it happens:**
- Original CASE statements have minor inconsistencies developers don't notice (one has `TRIM()`, other doesn't)
- Macro introduces parameterization that changes behavior (e.g., `column_name` vs hardcoded `NETWORK_NAME`)
- Jinja rendering can add/remove whitespace in ways that affect string comparisons
- No pre/post comparison of actual data output

**Consequences:**
- **Silent data drift:** Downstream models produce different results after macro extraction
- JOIN mismatches: Two models that previously joined on AD_PARTNER now have 0 matches due to casing difference
- Incremental models fail: Unique key violations because 'Meta' ≠ 'meta' in MERGE statements
- Business logic breaks: Revenue attributed to 'Other' instead of 'Meta' because ELSE clause changed

**Prevention:**

1. **Baseline comparison before extraction:** Capture current output BEFORE creating macro:
   ```sql
   -- Save baseline to temp table
   CREATE OR REPLACE TEMP TABLE installs_ad_partner_baseline AS
   SELECT DEVICE_ID, NETWORK_NAME, AD_PARTNER
   FROM {{ ref('v_stg_adjust__installs') }}
   WHERE INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE);
   ```

2. **Extract macro with EXACT copy of logic:** Don't "improve" the logic while extracting:
   ```sql
   -- macros/map_ad_partner.sql
   {% macro map_ad_partner(column_name='NETWORK_NAME') %}
   CASE
       WHEN {{ column_name }} IN ('Facebook Installs', 'Instagram Installs', 'Off-Facebook Installs', 'Facebook Messenger Installs') THEN 'Meta'
       WHEN {{ column_name }} IN ('Google Ads ACE', 'Google Ads ACI', 'Google Organic Search', 'google') THEN 'Google'
       WHEN {{ column_name }} IN ('TikTok SAN', 'TikTok_Paid_Ads_iOS', 'Tiktok Installs') THEN 'TikTok'
       -- ... EXACT same logic as original, including ELSE
       ELSE 'Other'
   END
   {% endmacro %}
   ```

3. **Update models to use macro (one at a time):**
   ```sql
   -- v_stg_adjust__installs.sql
   SELECT DEVICE_ID
        , NETWORK_NAME
        , {{ map_ad_partner(column_name='NETWORK_NAME') }} AS AD_PARTNER  -- Changed line
        , ...
   FROM DEDUPED
   ```

4. **Create consistency singular test BEFORE deploying:**
   ```sql
   -- tests/ad_partner_macro_consistency.sql
   -- Fails if macro produces different output than baseline
   WITH macro_output AS (
       SELECT DEVICE_ID, NETWORK_NAME, AD_PARTNER
       FROM {{ ref('v_stg_adjust__installs') }}
       WHERE INSTALL_TIMESTAMP >= DATEADD(day, -60, CURRENT_DATE)
   ),
   baseline AS (
       SELECT * FROM installs_ad_partner_baseline
   ),
   differences AS (
       SELECT m.DEVICE_ID, m.NETWORK_NAME,
              m.AD_PARTNER AS macro_value,
              b.AD_PARTNER AS baseline_value
       FROM macro_output m
       FULL OUTER JOIN baseline b
         ON m.DEVICE_ID = b.DEVICE_ID
       WHERE m.AD_PARTNER != b.AD_PARTNER
          OR (m.AD_PARTNER IS NULL AND b.AD_PARTNER IS NOT NULL)
          OR (m.AD_PARTNER IS NOT NULL AND b.AD_PARTNER IS NULL)
   )
   SELECT * FROM differences
   ```

5. **Run dbt test LOCALLY first (if possible) or in dbt Cloud dev environment:**
   - `dbt run --select v_stg_adjust__installs`
   - `dbt test --select ad_partner_macro_consistency`
   - Expect 0 failures

6. **After validation, update second model and repeat:**
   - Update `v_stg_adjust__touchpoints` to use macro
   - Create similar consistency test for touchpoints
   - Validate 0 differences

**Detection:**
- Downstream model row counts change after macro deployment
- JOINS return fewer matches than before
- Revenue/metric totals shift unexpectedly
- Incremental models fail with "unique key constraint violated"

**Which phase:** Phase 4 (DRY Refactor) — critical to validate BEFORE merging macro

**WGT-specific risk:** Touchpoints model is INCREMENTAL — if macro changes output, MERGE statement will insert duplicate rows instead of updating existing ones.

**Sources:**
- [dbt macros guide](https://docs.getdbt.com/docs/build/jinja-macros)
- [Unit Testing dbt Macros](https://www.dumky.net/posts/unit-testing-dbt-macros-a-workaround-for-dbts-unit-testing-limitations/)

---

### Pitfall 5: Incremental Model First Run vs Subsequent Run Divergence

**What goes wrong:** `is_incremental()` logic branches cause incremental models to produce DIFFERENT results on first run (full refresh) vs subsequent runs (incremental), leading to incorrect data when model is rebuilt.

**Real scenario (WGT):** MMM intermediate models (`int_mmm__daily_channel_spend`, `int_mmm__daily_channel_installs`, `int_mmm__daily_channel_revenue`) use incremental materialization. If filters/JOINs differ between first run and incremental runs, backfilling historical data produces different totals than original run.

**Why it happens:**
- `is_incremental()` returns `False` on first run (table doesn't exist yet)
- `is_incremental()` returns `True` on subsequent runs (table exists)
- Developers add date filters inside `{% if is_incremental() %}` block to improve performance
- Filter logic differs between branches, causing different row selection

**Example of dangerous pattern:**
```sql
SELECT DATE, CHANNEL, SUM(COST) AS SPEND
FROM {{ ref('stg_supermetrics__adj_campaign') }}
WHERE DATE IS NOT NULL
{% if is_incremental() %}
  AND DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
{% endif %}
GROUP BY 1, 2
```

**Problem:** First run includes ALL historical dates. Subsequent runs only include last 7 days. If you `--full-refresh` to rebuild, you only get last 7 days (based on current data's max date), losing all history.

**Consequences:**
- **Data loss on rebuild:** Full refresh produces subset of data instead of full history
- **Testing blind spot:** Tests run on first build (full data) but production runs incrementally (filtered)
- **Backfill failures:** Can't backfill historical dates because incremental filter prevents it
- **CI/CD false confidence:** CI builds from scratch (is_incremental = False), passes tests, but production behavior differs

**Prevention:**

1. **Keep business logic OUTSIDE is_incremental block:**
   ```sql
   -- GOOD: Filter is same for both branches
   SELECT DATE, CHANNEL, SUM(COST) AS SPEND
   FROM {{ ref('stg_supermetrics__adj_campaign') }}
   WHERE DATE IS NOT NULL
     AND COST > 0  -- Business logic here
   {% if is_incremental() %}
     AND DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))  -- Performance optimization ONLY
   {% endif %}
   GROUP BY 1, 2
   ```

2. **Use performance filters, not business filters, in incremental block:**
   - Performance filter: `DATE >= MAX(DATE) - 7` (safe because it overlaps with existing data)
   - Business filter: `DATE >= '2024-01-01'` (MUST be outside block)

3. **Add lookback overlap to prevent gaps:**
   ```sql
   {% if is_incremental() %}
     -- 7-day lookback ensures late-arriving data is captured
     AND DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
   {% endif %}
   ```

4. **Test BOTH code paths:**

   **First run test:**
   ```bash
   # Drop table to simulate first run
   dbt run --select int_mmm__daily_channel_spend --full-refresh
   # Verify row count includes all history
   SELECT COUNT(*), MIN(DATE), MAX(DATE)
   FROM DEV_S3_DATA.int_mmm__daily_channel_spend;
   ```

   **Incremental run test:**
   ```bash
   # Run again without full-refresh
   dbt run --select int_mmm__daily_channel_spend
   # Verify row count INCREASES (new dates added) or stays same (no new data)
   SELECT COUNT(*), MIN(DATE), MAX(DATE)
   FROM DEV_S3_DATA.int_mmm__daily_channel_spend;
   ```

5. **Document expected behavior in model config:**
   ```sql
   {{
       config(
           materialized='incremental',
           unique_key=['DATE', 'PLATFORM', 'CHANNEL'],
           incremental_strategy='merge',
           tags=['mmm', 'spend']
       )
   }}

   /*
       Incremental strategy: 7-day lookback overlap
       - First run: Loads all history from stg_supermetrics__adj_campaign
       - Subsequent runs: Merges last 7 days (handles late-arriving data)
       - Full refresh: Safe to run, rebuilds complete history
   */
   ```

6. **WGT-specific: Cannot test locally, so test in dbt Cloud dev environment:**
   - Run model with `--full-refresh` in dev
   - Note row counts and date ranges
   - Run again WITHOUT `--full-refresh`
   - Verify counts increase or stay same (not decrease)

**Detection:**
- Row counts decrease after full refresh
- Historical dates missing after rebuild
- Tests pass in CI but fail in production
- Metrics totals differ between first deployment and subsequent runs

**Which phase:** Phase 4 (DRY Refactor) and Phase 5 (Expand Test Coverage) — validate MMM incremental models before adding tests

**Sources:**
- [dbt incremental models in-depth](https://docs.getdbt.com/best-practices/materializations/4-incremental-models)
- [Clone incremental models as the first step of your CI job](https://docs.getdbt.com/best-practices/clone-incremental-models)
- [Testing incremental models](https://discourse.getdbt.com/t/testing-incremental-models/1528)

---

## Moderate Pitfalls

Mistakes that cause delays, brittle tests, or technical debt.

### Pitfall 6: Singular Tests That Pass Vacuously

**What goes wrong:** Singular tests return 0 rows (pass) because the test logic is broken, not because data quality is good. Test provides false confidence.

**Examples of vacuous tests:**

**Type 1: Impossible WHERE clause**
```sql
-- tests/revenue_after_install.sql
-- INTENTION: Fail if revenue events occur before install date
SELECT r.USER_ID, r.EVENT_TIME, i.INSTALL_TIMESTAMP
FROM {{ ref('v_stg_revenue__events') }} r
JOIN {{ ref('v_stg_adjust__installs') }} i
  ON r.USER_ID = i.DEVICE_ID  -- BUG: Wrong join key (USER_ID vs DEVICE_ID)
WHERE r.EVENT_TIME < i.INSTALL_TIMESTAMP
```
**Why vacuous:** JOIN never matches (wrong keys), so WHERE clause always evaluates on empty set. Test always passes regardless of data quality.

**Type 2: Test data doesn't exist**
```sql
-- tests/mmm_daily_summary_no_gaps.sql
-- INTENTION: Fail if date gaps exist in MMM summary
WITH date_sequence AS (
    SELECT DATE
    FROM {{ ref('mart_mmm__daily_summary') }}
    WHERE DATE >= '2024-01-01'  -- BUG: Production data doesn't exist before 2024-06-01
),
gaps AS (
    SELECT DATE,
           LEAD(DATE) OVER (ORDER BY DATE) AS next_date,
           DATEDIFF(day, DATE, LEAD(DATE) OVER (ORDER BY DATE)) AS gap_days
    FROM date_sequence
)
SELECT * FROM gaps WHERE gap_days > 1
```
**Why vacuous:** No rows match `DATE >= '2024-01-01'` because data only exists from June 2024 onwards. Empty input → empty output → test passes.

**Type 3: Aggregation without HAVING**
```sql
-- tests/touchpoint_credit_sum_is_one.sql
-- INTENTION: Fail if touchpoint credits don't sum to 1.0 per install
SELECT JOURNEY_ROW_KEY, SUM(CREDIT) AS total_credit
FROM {{ ref('int_mta__touchpoint_credit') }}
GROUP BY JOURNEY_ROW_KEY
-- BUG: Missing HAVING clause
-- Should be: HAVING ABS(SUM(CREDIT) - 1.0) > 0.001
```
**Why vacuous:** Test returns ALL rows (with their credit sums) but no WHERE/HAVING clause filters to failures. dbt checks if query returns > 0 rows, so this test ALWAYS fails (even when credits sum correctly).

**Consequences:**
- False confidence in data quality
- Real data quality issues go undetected
- Tests become "security theater" — exist for compliance but don't catch bugs
- When actual data quality issue occurs, tests still pass (erosion of trust)

**Prevention:**

1. **Always validate test logic manually first:**
   ```sql
   -- Step 1: Run the test query in Snowflake
   -- Step 2: Intentionally break data to verify test FAILS
   -- Step 3: Fix data, verify test PASSES
   ```

2. **Use assertions that explicitly check conditions:**
   ```sql
   -- tests/touchpoint_credit_sum_is_one.sql
   WITH credit_sums AS (
       SELECT JOURNEY_ROW_KEY,
              SUM(CREDIT) AS total_credit
       FROM {{ ref('int_mta__touchpoint_credit') }}
       GROUP BY JOURNEY_ROW_KEY
   )
   SELECT JOURNEY_ROW_KEY, total_credit
   FROM credit_sums
   WHERE ABS(total_credit - 1.0) > 0.001  -- Explicit failure condition
      OR total_credit IS NULL
   ```

3. **Add row count expectations:**
   ```sql
   -- tests/mmm_date_spine_complete.sql
   WITH expected_dates AS (
       -- Generate date spine from known start date to today
       SELECT DATEADD(day, seq, '{{ var("mmm_start_date") }}'::DATE) AS DATE
       FROM TABLE(GENERATOR(ROWCOUNT => DATEDIFF(day, '{{ var("mmm_start_date") }}', CURRENT_DATE) + 1))
   ),
   actual_dates AS (
       SELECT DISTINCT DATE
       FROM {{ ref('mart_mmm__daily_summary') }}
   ),
   missing_dates AS (
       SELECT e.DATE
       FROM expected_dates e
       LEFT JOIN actual_dates a ON e.DATE = a.DATE
       WHERE a.DATE IS NULL
   )
   SELECT * FROM missing_dates
   ```

4. **Add test metadata comments:**
   ```sql
   -- tests/revenue_after_install.sql
   /*
   TEST PURPOSE: Verify revenue events don't occur before install
   EXPECTED FAILURES: 0 rows (all revenue after install)
   EXPECTED ROW COUNT WHEN PASSING: 0
   EXPECTED ROW COUNT WHEN FAILING: > 0 (shows violating rows)

   VALIDATION CHECKLIST:
   [ ] Manually verified test fails when intentional violation added
   [ ] Verified test passes on clean data
   [ ] Checked that test scans expected number of rows (not empty input)
   */
   SELECT r.USER_ID, r.EVENT_TIME, i.INSTALL_TIMESTAMP
   FROM {{ ref('v_stg_revenue__events') }} r
   JOIN {{ ref('int_adjust_amplitude__device_mapping') }} dm
     ON r.USER_ID = dm.AMPLITUDE_USER_ID  -- Correct join via mapping
   JOIN {{ ref('v_stg_adjust__installs') }} i
     ON dm.ADJUST_DEVICE_ID = i.DEVICE_ID
   WHERE r.EVENT_TIME < i.INSTALL_TIMESTAMP
   ```

5. **Test the test (meta-testing):**
   - Add temporary bad data to staging table
   - Run dbt test, verify it FAILS
   - Remove bad data, verify it PASSES

**Detection:**
- Test passes immediately on first run without data inspection
- Test continues to pass even when known data quality issues exist
- Test query returns 0 rows when run manually (input is empty, not filtered)

**Which phase:** Phase 5 (Expand Test Coverage) — validate all singular tests before deployment

**WGT-specific risks:**
- Join on USER_ID vs DEVICE_ID confusion (common in cross-source tests)
- Date range assumptions (data doesn't exist before June 2024)
- iOS vs Android data availability differences

**Sources:**
- [7 dbt Testing Best Practices](https://www.datafold.com/blog/7-dbt-testing-best-practices)
- [dbt tests: How to write fewer and better data tests](https://www.elementary-data.com/post/dbt-tests)
- [Everything you need to know about dbt tests](https://www.metaplane.dev/blog/dbt-test-examples-best-practices)

---

### Pitfall 7: Brittle Singular Tests — Hardcoded Thresholds

**What goes wrong:** Singular tests with hardcoded thresholds (row counts, percentages, date ranges) break frequently as data volume grows or business logic changes, causing alert fatigue.

**Examples of brittle tests:**

**Type 1: Hardcoded row count**
```sql
-- tests/installs_daily_volume.sql
-- INTENTION: Catch days with unusually low install counts
SELECT DATE, COUNT(*) AS install_count
FROM {{ ref('v_stg_adjust__installs') }}
WHERE INSTALL_TIMESTAMP >= DATEADD(day, -7, CURRENT_DATE)
GROUP BY DATE
HAVING COUNT(*) < 100  -- BUG: Hardcoded threshold
```
**Why brittle:** As marketing spend increases, daily installs grow from 100 → 500 → 1000. Threshold becomes meaningless. Conversely, seasonal drops (holidays) trigger false positives.

**Type 2: Hardcoded percentage**
```sql
-- tests/ios_idfa_availability.sql
-- INTENTION: Detect drop in IDFA consent rate
SELECT 'IDFA consent rate dropped' AS issue
FROM {{ ref('v_stg_adjust__installs') }}
WHERE PLATFORM = 'iOS'
  AND INSTALL_TIMESTAMP >= DATEADD(day, -7, CURRENT_DATE)
HAVING (COUNT(CASE WHEN IDFA IS NOT NULL THEN 1 END) / COUNT(*)) < 0.07  -- BUG: Hardcoded 7%
```
**Why brittle:** ATT consent rates fluctuate (iOS version distribution, user cohorts, seasonality). Hardcoded 7% based on historical data becomes outdated.

**Type 3: Hardcoded date cutoff**
```sql
-- tests/mmm_data_backfilled.sql
-- INTENTION: Ensure MMM data exists back to project start
SELECT 'Missing historical data' AS issue
FROM {{ ref('mart_mmm__daily_summary') }}
WHERE DATE < '2024-01-01'  -- BUG: Hardcoded start date
HAVING COUNT(*) = 0
```
**Why brittle:** Data actually starts June 2024. Test fails until someone updates hardcoded date. Future backfills require test updates.

**Consequences:**
- **Alert fatigue:** Tests fail frequently due to natural data variance, team ignores failures
- **Maintenance burden:** Every business logic change requires updating test thresholds
- **Delayed incident detection:** Real anomalies hidden among noisy false positives
- **Test disablement:** Team adds `severity: warn` or deletes tests instead of fixing them

**Prevention:**

1. **Use dynamic thresholds based on recent data:**
   ```sql
   -- tests/installs_daily_volume_anomaly.sql
   WITH recent_avg AS (
       SELECT AVG(daily_count) AS avg_installs,
              STDDEV(daily_count) AS stddev_installs
       FROM (
           SELECT DATE, COUNT(*) AS daily_count
           FROM {{ ref('v_stg_adjust__installs') }}
           WHERE INSTALL_TIMESTAMP >= DATEADD(day, -30, CURRENT_DATE)
             AND INSTALL_TIMESTAMP < DATEADD(day, -7, CURRENT_DATE)  -- Baseline period
           GROUP BY DATE
       )
   ),
   recent_days AS (
       SELECT DATE, COUNT(*) AS daily_count
       FROM {{ ref('v_stg_adjust__installs') }}
       WHERE INSTALL_TIMESTAMP >= DATEADD(day, -7, CURRENT_DATE)
       GROUP BY DATE
   )
   SELECT r.DATE, r.daily_count, a.avg_installs, a.stddev_installs
   FROM recent_days r
   CROSS JOIN recent_avg a
   WHERE r.daily_count < (a.avg_installs - 2 * a.stddev_installs)  -- 2 stddev threshold
   ```

2. **Use percentage-of-baseline instead of absolute thresholds:**
   ```sql
   -- tests/ios_idfa_rate_drop.sql
   WITH baseline AS (
       SELECT COUNT(CASE WHEN IDFA IS NOT NULL THEN 1 END)::FLOAT / COUNT(*) AS idfa_rate
       FROM {{ ref('v_stg_adjust__installs') }}
       WHERE PLATFORM = 'iOS'
         AND INSTALL_TIMESTAMP >= DATEADD(day, -30, CURRENT_DATE)
         AND INSTALL_TIMESTAMP < DATEADD(day, -7, CURRENT_DATE)
   ),
   recent AS (
       SELECT COUNT(CASE WHEN IDFA IS NOT NULL THEN 1 END)::FLOAT / COUNT(*) AS idfa_rate
       FROM {{ ref('v_stg_adjust__installs') }}
       WHERE PLATFORM = 'iOS'
         AND INSTALL_TIMESTAMP >= DATEADD(day, -7, CURRENT_DATE)
   )
   SELECT 'IDFA rate dropped by more than 50%' AS issue,
          b.idfa_rate AS baseline_rate,
          r.idfa_rate AS recent_rate
   FROM recent r
   CROSS JOIN baseline b
   WHERE r.idfa_rate < (b.idfa_rate * 0.5)  -- 50% relative drop
   ```

3. **Use dbt variables for thresholds (adjustable without code changes):**
   ```sql
   -- tests/mmm_date_spine_complete.sql
   -- dbt_project.yml: vars: { mmm_start_date: '2024-06-01' }
   WITH expected_dates AS (
       SELECT DATEADD(day, seq, '{{ var("mmm_start_date") }}'::DATE) AS DATE
       FROM TABLE(GENERATOR(ROWCOUNT => DATEDIFF(day, '{{ var("mmm_start_date") }}', CURRENT_DATE) + 1))
   ),
   actual_dates AS (
       SELECT DISTINCT DATE
       FROM {{ ref('mart_mmm__daily_summary') }}
   )
   SELECT e.DATE
   FROM expected_dates e
   LEFT JOIN actual_dates a ON e.DATE = a.DATE
   WHERE a.DATE IS NULL
   ```

4. **Document why threshold was chosen:**
   ```sql
   -- tests/spend_daily_limit.sql
   /*
   THRESHOLD: $50,000 daily spend limit
   RATIONALE: Marketing budget cap per finance policy (2024 budget planning)
   REVIEW FREQUENCY: Annually (before budget cycle)
   LAST REVIEWED: 2024-06-01
   OWNER: Marketing Ops team
   */
   SELECT DATE, SUM(SPEND) AS total_spend
   FROM {{ ref('int_mmm__daily_channel_spend') }}
   WHERE DATE >= DATEADD(day, -7, CURRENT_DATE)
   GROUP BY DATE
   HAVING SUM(SPEND) > {{ var('daily_spend_limit', 50000) }}
   ```

5. **For true business rules, use config variables:**
   ```yaml
   # dbt_project.yml
   vars:
     mmm_start_date: '2024-06-01'
     daily_spend_limit: 50000
     min_daily_installs: 50  # Hard floor (below this = pipeline broken)
   ```

**Detection:**
- Test fails on every run or very frequently
- Test failure rate > 10% (should be < 1% for good tests)
- Team discusses "should we just disable this test?"
- Test threshold values don't match current business reality

**Which phase:** Phase 5 (Expand Test Coverage) — design tests to be resilient

**WGT-specific considerations:**
- iOS vs Android volume differences (separate thresholds)
- SANs (Meta, Google, TikTok, Apple) have different spend patterns than programmatic
- Seasonal variance (holidays, marketing campaigns)

**Sources:**
- [Challenges with DBT Tests in Practice](https://datasettler.com/blog/post-4-dbt-pitfalls-in-practice/)
- [dbt data quality checks best practices](https://lakefs.io/blog/dbt-data-quality-checks/)

---

### Pitfall 8: Cross-Layer Consistency Tests Without Accounting for Filters

**What goes wrong:** Tests that validate row counts or metric totals match across layers fail because different layers apply different WHERE filters, causing expected mismatches.

**Real scenario (WGT):** Testing that install counts match from staging → intermediate → marts:

```sql
-- tests/install_count_consistency.sql (BROKEN)
WITH staging_count AS (
    SELECT COUNT(*) AS cnt
    FROM {{ ref('v_stg_adjust__installs') }}
),
intermediate_count AS (
    SELECT COUNT(DISTINCT DEVICE_ID) AS cnt
    FROM {{ ref('int_mta__user_journey') }}
),
mart_count AS (
    SELECT SUM(INSTALLS) AS cnt
    FROM {{ ref('mart_mmm__daily_summary') }}
)
SELECT 'Counts do not match' AS issue
WHERE (SELECT cnt FROM staging_count) != (SELECT cnt FROM intermediate_count)
   OR (SELECT cnt FROM staging_count) != (SELECT cnt FROM mart_count)
```

**Why this fails:**
- **Staging:** All installs (iOS + Android, all time)
- **Intermediate:** Only installs with device mapping (iOS only, filters out unmapped devices)
- **Marts:** Only installs in date range with spend data (date spine from 2024-06-01)

Counts will NEVER match. Test always fails.

**Consequences:**
- Test fails on every run → team ignores it → alert fatigue
- Team doesn't understand WHY counts differ → reduces trust in data
- Real data quality issues (e.g., duplicate rows) hidden among expected mismatches

**Prevention:**

1. **Apply consistent filters across all layers:**
   ```sql
   -- tests/install_count_consistency.sql (FIXED)
   WITH staging_count AS (
       SELECT COUNT(*) AS cnt
       FROM {{ ref('v_stg_adjust__installs') }}
       WHERE PLATFORM = 'iOS'  -- Match intermediate filter
         AND INSTALL_TIMESTAMP >= '2024-06-01'  -- Match mart filter
   ),
   intermediate_count AS (
       SELECT COUNT(DISTINCT DEVICE_ID) AS cnt
       FROM {{ ref('int_mta__user_journey') }}
       WHERE INSTALL_TIMESTAMP >= '2024-06-01'
   ),
   mart_count AS (
       SELECT SUM(INSTALLS) AS cnt
       FROM {{ ref('mart_mmm__daily_summary') }}
       WHERE DATE >= '2024-06-01'
   )
   SELECT 'Counts do not match' AS issue,
          (SELECT cnt FROM staging_count) AS staging,
          (SELECT cnt FROM intermediate_count) AS intermediate,
          (SELECT cnt FROM mart_count) AS mart
   WHERE (SELECT cnt FROM staging_count) != (SELECT cnt FROM intermediate_count)
      OR (SELECT cnt FROM staging_count) != (SELECT cnt FROM mart_count)
   ```

2. **OR accept expected variance and test for it:**
   ```sql
   -- tests/install_count_reasonable_loss.sql
   WITH staging_count AS (
       SELECT COUNT(*) AS cnt
       FROM {{ ref('v_stg_adjust__installs') }}
       WHERE INSTALL_TIMESTAMP >= '2024-06-01'
   ),
   mart_count AS (
       SELECT SUM(INSTALLS) AS cnt
       FROM {{ ref('mart_mmm__daily_summary') }}
   )
   SELECT 'Too many installs lost between staging and mart' AS issue,
          s.cnt AS staging_installs,
          m.cnt AS mart_installs,
          (s.cnt - m.cnt)::FLOAT / s.cnt AS loss_rate
   FROM staging_count s
   CROSS JOIN mart_count m
   WHERE (s.cnt - m.cnt)::FLOAT / s.cnt > 0.05  -- Allow 5% loss (device mapping)
   ```

3. **Document expected differences:**
   ```sql
   -- tests/cross_layer_metrics.sql
   /*
   EXPECTED DIFFERENCES:
   - Staging → Intermediate: iOS-only filter reduces count by ~50% (Android excluded)
   - Intermediate → Mart: Device mapping filter reduces count by ~30% (unmapped devices)
   - Staging → Mart: Date filter (>= 2024-06-01) reduces count (historical data excluded)

   ACCEPTABLE VARIANCE: ±2% for same-platform, same-date-range comparisons
   */
   ```

4. **Test grain consistency, not count consistency:**
   ```sql
   -- tests/grain_consistency_install.sql
   -- Verify that every install in mart exists in staging (no invented rows)
   WITH mart_installs AS (
       SELECT DISTINCT DATE, PLATFORM, CHANNEL
       FROM {{ ref('mart_mmm__daily_summary') }}
       WHERE INSTALLS > 0
   ),
   staging_installs AS (
       SELECT DISTINCT
              DATE(INSTALL_TIMESTAMP) AS DATE,
              PLATFORM,
              AD_PARTNER AS CHANNEL
       FROM {{ ref('v_stg_adjust__installs') }}
   )
   SELECT m.DATE, m.PLATFORM, m.CHANNEL, 'Mart has installs not in staging' AS issue
   FROM mart_installs m
   LEFT JOIN staging_installs s
     ON m.DATE = s.DATE
    AND m.PLATFORM = s.PLATFORM
    AND m.CHANNEL = s.CHANNEL
   WHERE s.DATE IS NULL  -- Mart row has no corresponding staging row
   ```

5. **For MMM specifically, test zero-fill behavior:**
   ```sql
   -- tests/mmm_zero_fill_integrity.sql
   -- Verify that zero-filled rows are flagged correctly
   SELECT DATE, PLATFORM, CHANNEL,
          INSTALLS,
          HAS_INSTALL_DATA
   FROM {{ ref('mart_mmm__daily_summary') }}
   WHERE INSTALLS = 0 AND HAS_INSTALL_DATA = TRUE  -- Contradiction
      OR INSTALLS > 0 AND HAS_INSTALL_DATA = FALSE  -- Contradiction
   ```

**Detection:**
- Test fails on every run with counts that "should match"
- Team discusses "why are these numbers different?"
- Counts differ by consistent percentage (e.g., always 50% difference)

**Which phase:** Phase 5 (Expand Test Coverage) — when adding MMM cross-layer tests

**WGT-specific filters to account for:**
- iOS vs Android (intermediate layer iOS-only due to device mapping)
- Date range (MMM starts 2024-06-01, but staging has earlier data)
- Device mapping filter (int_mta models only include mapped devices)

**Sources:**
- [dbt data quality framework](https://www.getdbt.com/blog/building-a-data-quality-framework-with-dbt-and-dbt-cloud)
- [5 essential data quality checks for analytics](https://www.getdbt.com/blog/data-quality-checks)
- [Guide to dbt data quality checks](https://www.metaplane.dev/blog/guide-to-dbt-data-quality-checks)

---

### Pitfall 9: Testing Macros Without dbt Environment

**What goes wrong:** Cannot test macro changes locally because dbt is not runnable locally (RSA key-pair auth), forcing all testing to happen in dbt Cloud where iteration is slow and risky.

**Real scenario (WGT):** Extracting AD_PARTNER CASE statement into macro. Normally you'd test locally:
```bash
dbt compile --select v_stg_adjust__installs
cat target/compiled/.../v_stg_adjust__installs.sql  # Inspect compiled SQL
dbt run --select v_stg_adjust__installs
dbt test --select v_stg_adjust__installs
```

But WGT has NO local dbt environment. All testing must happen in dbt Cloud dev environment via browser.

**Why this happens:**
- Snowflake connection uses RSA key-pair authentication (not username/password)
- Private key not shared with all developers
- dbt Cloud IDE is the only approved development environment
- "Just use dbt Cloud" policy prevents local setup

**Consequences:**
- **Slow iteration:** Each macro change requires: edit in browser → save → dbt run → wait → check results
- **No compiled SQL inspection:** Can't easily see what Jinja renders to (dbt Cloud doesn't show compiled SQL in UI)
- **Risky changes:** Can't test macro in isolation, must run full model to see results
- **No version control workflow:** Can't test in branch before pushing (dbt Cloud auto-commits)

**Prevention:**

1. **Use dbt Cloud IDE's "Compile" button to inspect rendered SQL:**
   - Open model in dbt Cloud IDE
   - Click "Compile" (not "Run")
   - Scroll to bottom of IDE to see compiled SQL
   - Verify macro renders correctly

2. **Create throwaway test models for macro development:**
   ```sql
   -- models/scratchpad/test_ad_partner_macro.sql
   -- Temporary model to test macro in isolation
   {{
       config(
           materialized='ephemeral',  -- Doesn't create table
           tags=['test', 'scratchpad']
       )
   }}

   SELECT 'Facebook Installs' AS network_name,
          {{ map_ad_partner(column_name='network_name') }} AS ad_partner
   UNION ALL
   SELECT 'Google Ads ACE', {{ map_ad_partner(column_name='network_name') }}
   UNION ALL
   SELECT 'Unknown Network', {{ map_ad_partner(column_name='network_name') }}
   ```

   Compile this to see macro output, then delete when done.

3. **Use dbt Cloud job runs for validation (slower but comprehensive):**
   - Create dbt Cloud job: "Dev: Macro Testing"
   - Configure to run: `dbt run --select v_stg_adjust__installs && dbt test --select v_stg_adjust__installs`
   - Run manually after macro changes
   - Check job logs for errors

4. **Extract and test macro logic in SQL worksheet first:**
   ```sql
   -- Snowflake worksheet: test_ad_partner_logic.sql
   -- Test CASE statement logic before extracting to macro
   WITH test_networks AS (
       SELECT 'Facebook Installs' AS network_name UNION ALL
       SELECT 'Google Ads ACE' UNION ALL
       SELECT 'TikTok SAN' UNION ALL
       SELECT 'Unknown Partner'
   )
   SELECT network_name,
          CASE
              WHEN network_name IN ('Facebook Installs', 'Instagram Installs') THEN 'Meta'
              WHEN network_name IN ('Google Ads ACE', 'Google Ads ACI') THEN 'Google'
              -- ... rest of logic
              ELSE 'Other'
          END AS ad_partner
   FROM test_networks;
   ```

   Once CASE statement is validated in Snowflake, copy EXACT logic to macro.

5. **Use singular test as macro validator:**
   ```sql
   -- tests/validate_ad_partner_macro.sql
   -- Test that macro produces expected output for known inputs
   WITH test_cases AS (
       SELECT 'Facebook Installs' AS input, 'Meta' AS expected UNION ALL
       SELECT 'Google Ads ACE', 'Google' UNION ALL
       SELECT 'TikTok SAN', 'TikTok' UNION ALL
       SELECT 'Apple Search Ads', 'Apple' UNION ALL
       SELECT 'Unknown Partner', 'Other'
   ),
   macro_results AS (
       SELECT input,
              expected,
              {{ map_ad_partner(column_name='input') }} AS actual
       FROM test_cases
   )
   SELECT input, expected, actual
   FROM macro_results
   WHERE expected != actual
   ```

   Run this test in dbt Cloud to validate macro.

6. **Document macro testing checklist:**
   ```sql
   -- macros/map_ad_partner.sql
   /*
   TESTING CHECKLIST (dbt Cloud only):
   [ ] Compiled SQL reviewed (Compile button in IDE)
   [ ] Test model created in scratchpad/ with known inputs
   [ ] validate_ad_partner_macro.sql test passes
   [ ] v_stg_adjust__installs runs successfully with macro
   [ ] v_stg_adjust__touchpoints runs successfully with macro
   [ ] ad_partner_macro_consistency.sql test passes (macro matches original CASE)
   */
   {% macro map_ad_partner(column_name='NETWORK_NAME') %}
   ...
   {% endmacro %}
   ```

**Detection:**
- Macro changes break models and you don't find out until dbt Cloud run fails
- Multiple commit-push-run-fail cycles to debug simple Jinja syntax error
- Frustration with "I wish I could just test this locally"

**Which phase:** Phase 4 (DRY Refactor) — macro extraction requires iterative testing

**WGT-specific constraint:** NO local dbt environment, ALL testing via dbt Cloud browser IDE

**Workarounds:**
- Use Snowflake worksheet for SQL logic validation first
- Use ephemeral scratchpad models for macro testing
- Use singular tests as macro validators
- Rely heavily on dbt Cloud's Compile button

**Sources:**
- [How to unit test macros in dbt](https://medium.com/glitni/how-to-unit-test-macros-in-dbt-89bdb5de8634)
- [Unit Testing dbt Macros](https://www.dumky.net/posts/unit-testing-dbt-macros-a-workaround-for-dbts-unit-testing-limitations/)
- [dbt unit tests](https://docs.getdbt.com/docs/build/unit-tests)

---

### Pitfall 10: Snowflake Case Sensitivity — Seed CSV vs Model Column Mismatch

**What goes wrong:** Seed CSV has lowercase column headers (`supermetrics_partner_name`), models reference columns as UPPERCASE (`SUPERMETRICS_PARTNER_NAME`), JOIN breaks because Snowflake treats them as different columns.

**Real scenario (WGT):** `network_mapping.csv` seed has lowercase headers. MMM models join on:
```sql
LEFT JOIN {{ ref('network_mapping') }} nm
  ON s.PARTNER_NAME = nm.SUPERMETRICS_PARTNER_NAME  -- BUG: Case mismatch
```

**Why it breaks:**
- Snowflake default: unquoted identifiers are case-insensitive and UPPERCASED
- dbt seed default for Snowflake: `quote_columns: false` → headers are uppercased
- CSV headers are `supermetrics_partner_name` (lowercase)
- When `quote_columns: false`, Snowflake creates column as `SUPERMETRICS_PARTNER_NAME` (uppercase)
- SQL references column as `SUPERMETRICS_PARTNER_NAME` → works
- SQL references column as `supermetrics_partner_name` → also works (case-insensitive)
- **BUT:** If seed configured with `quote_columns: true`, column becomes `"supermetrics_partner_name"` (case-sensitive lowercase)
- JOIN with `nm.SUPERMETRICS_PARTNER_NAME` now fails: column `"SUPERMETRICS_PARTNER_NAME"` does not exist

**Consequences:**
- JOIN returns 0 rows (silent data loss)
- Models compile successfully but produce wrong results
- Hard to debug (SQL looks correct, Snowflake accepts it, but join doesn't match)
- Intermittent failures if `quote_columns` setting changes

**Prevention:**

1. **Standardize on UPPERCASE unquoted throughout project:**
   ```yaml
   # dbt_project.yml
   seeds:
     wgt_dbt:
       +quote_columns: false  # Default, but make it explicit
   ```

   ```csv
   # seeds/network_mapping.csv (headers UPPERCASE)
   SUPERMETRICS_PARTNER_NAME,AD_PARTNER
   Facebook,Meta
   Google,Google
   ```

2. **OR standardize on lowercase quoted (not recommended for Snowflake):**
   ```yaml
   # dbt_project.yml
   seeds:
     wgt_dbt:
       +quote_columns: true
   ```

   ```sql
   -- models/intermediate/int_mmm__daily_channel_spend.sql
   LEFT JOIN {{ ref('network_mapping') }} nm
     ON s.partner_name = nm.supermetrics_partner_name  -- All lowercase
   ```

3. **Document case sensitivity rules in project README:**
   ```markdown
   ## Snowflake Case Sensitivity Rules

   - All model columns: UPPERCASE unquoted
   - All seed CSV headers: UPPERCASE
   - All JOIN keys: UPPERCASE unquoted
   - `quote_columns: false` for all seeds (default)

   **Rationale:** Snowflake uppercases unquoted identifiers. Using uppercase
   throughout prevents case sensitivity bugs.
   ```

4. **Test seed joins explicitly:**
   ```sql
   -- tests/network_mapping_join_works.sql
   -- Verify seed can be joined with Supermetrics data
   SELECT s.PARTNER_NAME,
          nm.AD_PARTNER
   FROM {{ ref('stg_supermetrics__adj_campaign') }} s
   LEFT JOIN {{ ref('network_mapping') }} nm
     ON s.PARTNER_NAME = nm.SUPERMETRICS_PARTNER_NAME
   WHERE s.PARTNER_NAME IS NOT NULL
     AND nm.AD_PARTNER IS NULL  -- Join failed to match
   LIMIT 10
   ```

5. **Use consistent casing in ref() calls:**
   ```sql
   -- GOOD: Case-insensitive ref
   FROM {{ ref('network_mapping') }}

   -- AVOID: Quoted ref (case-sensitive)
   FROM {{ ref('NETWORK_MAPPING') }}
   ```

6. **Audit seed column names after dbt seed:**
   ```sql
   -- Run in Snowflake after dbt seed
   SELECT column_name
   FROM INFORMATION_SCHEMA.COLUMNS
   WHERE table_schema = 'DBT_WGTDATA'  -- Dev schema
     AND table_name = 'NETWORK_MAPPING';

   -- Expected: SUPERMETRICS_PARTNER_NAME (uppercase, unquoted)
   -- If you see: "supermetrics_partner_name" (quoted) → fix CSV or quote_columns setting
   ```

**Detection:**
- JOIN returns 0 rows unexpectedly
- Error: "invalid identifier" or "column does not exist" despite column existing in table
- DESCRIBE TABLE shows `"column_name"` (quoted) instead of `COLUMN_NAME` (unquoted)

**Which phase:** Phase 4 (DRY Refactor) — when validating network_mapping seed integration

**WGT-specific context:**
- `network_mapping.csv` seed used in MMM models
- JOIN between Supermetrics staging and seed must work
- Comment in `int_mmm__daily_channel_spend.sql` already acknowledges this: "Snowflake treats unquoted identifiers as case-insensitive. The seed CSV has lowercase headers (supermetrics_partner_name) but since quote_columns is not set in dbt_project.yml, Snowflake uppercases them internally. Using UPPERCASE here for project consistency."

**Sources:**
- [Snowflake identifier requirements](https://docs.snowflake.com/en/sql-reference/identifiers-syntax)
- [dbt seed case sensitivity issue](https://github.com/dbt-labs/dbt-core/issues/7265)
- [Configuring quoting in dbt projects](https://docs.getdbt.com/reference/project-configs/quoting)

---

## Minor Pitfalls

Mistakes that cause annoyance but are fixable.

### Pitfall 11: Source Freshness Job Scheduling Conflicts

**What goes wrong:** Running `dbt source freshness` as part of main dbt Cloud job (that also runs models) causes job to take longer and makes freshness results harder to track.

**Why it's suboptimal:**
- `dbt run` rebuilds models (10+ minutes)
- `dbt source freshness` checks timestamps (< 1 minute)
- Combined job conflates two concerns: build success vs data freshness
- Can't schedule freshness checks more frequently than model builds (e.g., freshness every hour, builds every 6 hours)

**Consequences:**
- Delayed freshness alerts (only check when models run)
- Harder to debug failures (did freshness fail or did model fail?)
- Can't optimize scheduling (freshness needs to run more frequently)

**Prevention:**

1. **Create separate dbt Cloud job for freshness:**
   - Job name: "Source Freshness Checks"
   - Commands: `dbt source freshness`
   - Schedule: Hourly (or based on lowest SLA ÷ 2)
   - Notifications: Slack/email on freshness warnings

2. **Keep model build jobs separate:**
   - Job name: "Production Build"
   - Commands: `dbt run && dbt test`
   - Schedule: Every 6 hours (or based on data refresh frequency)

3. **Use dbt Cloud job dependencies (if needed):**
   - Freshness job runs first
   - If freshness passes, trigger build job
   - If freshness fails, don't build (stale data alert)

**Detection:**
- Freshness warnings buried in long job logs
- "Why do we only check freshness every 6 hours when data refreshes hourly?"
- Freshness alerts arrive hours after data went stale

**Which phase:** Phase 6 (Source Freshness & Observability) — when configuring dbt Cloud jobs

---

### Pitfall 12: Filter Column Not in `loaded_at_field` Table

**What goes wrong:** Using `filter:` in freshness config that references a column not present in the source table causes freshness query to fail.

**Example:**
```yaml
sources:
  - name: adjust
    tables:
      - name: IOS_ACTIVITY_INSTALL
        loaded_at_field: LOAD_TIMESTAMP
        freshness:
          warn_after: {count: 6, period: hour}
          filter: PLATFORM = 'iOS'  # BUG: PLATFORM column doesn't exist in raw table
```

**Why it happens:**
- `filter:` is applied to the raw source table query, not the staging model
- Source table has different columns than staging model
- Developer copies filter from staging model without checking source schema

**Consequences:**
- `dbt source freshness` fails with "column does not exist"
- All freshness checks blocked by one bad filter

**Prevention:**

1. **Only filter on columns that exist in source table:**
   ```yaml
   sources:
     - name: adjust
       tables:
         - name: IOS_ACTIVITY_INSTALL
           loaded_at_field: LOAD_TIMESTAMP
           freshness:
             warn_after: {count: 6, period: hour}
             # filter: none needed (table is already iOS-only)
   ```

2. **Check source schema before adding filter:**
   ```sql
   DESCRIBE TABLE ADJUST.S3_DATA.IOS_ACTIVITY_INSTALL;
   ```

3. **Test freshness query manually:**
   ```sql
   SELECT MAX(LOAD_TIMESTAMP) AS max_loaded_at
   FROM ADJUST.S3_DATA.IOS_ACTIVITY_INSTALL
   WHERE PLATFORM = 'iOS';  -- Test if this column exists
   ```

**Detection:**
- Freshness job fails with SQL error
- Error message: "invalid identifier 'PLATFORM'"

**Which phase:** Phase 6 (Source Freshness & Observability)

---

### Pitfall 13: Freshness Warn vs Error Thresholds Too Close

**What goes wrong:** Setting `warn_after` and `error_after` with minimal gap (e.g., warn at 6 hours, error at 7 hours) doesn't give team time to investigate before escalating to error.

**Example:**
```yaml
freshness:
  warn_after: {count: 6, period: hour}
  error_after: {count: 7, period: hour}  # Only 1 hour gap
```

**Why it's suboptimal:**
- Warning fires at 6 hours
- Team investigates (takes 30-60 minutes)
- Before investigation completes, error fires
- Error triggers paging/escalation unnecessarily

**Prevention:**

1. **Use 2x gap between warn and error:**
   ```yaml
   freshness:
     warn_after: {count: 6, period: hour}
     error_after: {count: 12, period: hour}  # 6-hour investigation window
   ```

2. **OR use warn-only for most sources:**
   ```yaml
   freshness:
     warn_after: {count: 6, period: hour}
     # error_after: omitted (warn only, no auto-escalation)
   ```

3. **Reserve error_after for critical sources only:**
   - Sources that gate customer-facing dashboards → use `error_after`
   - Sources used for internal analysis → use `warn_after` only

**Detection:**
- Frequent escalations to error before team can investigate
- "Why did this page me? I was already looking into it."

**Which phase:** Phase 6 (Source Freshness & Observability)

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| **Phase 4: DRY Refactor (Macro Extraction)** | Macro changes output silently (Pitfall 4) | Create consistency test comparing macro output to original CASE before deployment |
| **Phase 4: DRY Refactor** | Cannot test macro locally (Pitfall 9) | Use dbt Cloud Compile button + ephemeral scratchpad models + Snowflake worksheet for SQL validation |
| **Phase 4: DRY Refactor** | Seed CSV case sensitivity breaks JOIN (Pitfall 10) | Audit `network_mapping.csv` headers are UPPERCASE, test seed join explicitly |
| **Phase 5: MMM Test Coverage** | Incremental model first run ≠ subsequent runs (Pitfall 5) | Test MMM models with `--full-refresh` and without, verify row counts increase/stay same |
| **Phase 5: MMM Test Coverage** | Cross-layer tests fail due to filter differences (Pitfall 8) | Apply consistent filters (iOS-only, date >= 2024-06-01) across staging/intermediate/mart in tests |
| **Phase 5: MMM Test Coverage** | Singular tests pass vacuously (Pitfall 6) | Validate test fails when intentional violation added, passes when data is clean |
| **Phase 5: MMM Test Coverage** | Brittle hardcoded thresholds (Pitfall 7) | Use dynamic baselines (recent avg ± 2σ) instead of absolute thresholds |
| **Phase 6: Source Freshness** | Static table without timestamp (Pitfall 1) | Omit freshness config for `ADJUST_AMPLITUDE_DEVICE_MAPPING`, use row count change test instead |
| **Phase 6: Source Freshness** | Wrong timestamp column (Pitfall 2) | Use LOAD_TIMESTAMP (ETL time) not CREATED_AT (event time) for Adjust sources |
| **Phase 6: Source Freshness** | Timezone mismatch (Pitfall 3) | Convert LOAD_TIMESTAMP to UTC if needed: `CONVERT_TIMEZONE('America/Los_Angeles', 'UTC', LOAD_TIMESTAMP)` |
| **Phase 6: Source Freshness** | Freshness + build in same job (Pitfall 11) | Create separate dbt Cloud job for `dbt source freshness` (run hourly) vs model builds (run every 6 hours) |

---

## Integration Risks — Cross-Cutting Concerns

### Risk 1: No Local dbt Testing → All Validation in dbt Cloud

**Impact areas:** Phases 4, 5, 6 (all require iterative testing)

**Challenge:** Every change requires commit → push → dbt Cloud run → check logs → repeat

**Mitigation strategy:**
1. **Phase 4 (Macro):** Use Snowflake worksheet to validate CASE logic before extracting to macro
2. **Phase 5 (Tests):** Write singular test SQL in Snowflake first, then move to dbt when validated
3. **Phase 6 (Freshness):** Query `MAX(LOAD_TIMESTAMP)` manually to verify columns exist before configuring

**Acceptance:** Slower iteration is unavoidable. Build extra validation time into phase estimates.

---

### Risk 2: Incremental Models + Testing Requires Two Runs

**Impact areas:** Phase 5 (testing incremental models)

**Challenge:** Tests run on first build (full data) but production runs incrementally (filtered data). Behavior diverges.

**Mitigation strategy:**
1. Test incremental models TWICE in dbt Cloud dev:
   - First: `dbt run --select int_mmm__daily_channel_spend --full-refresh`
   - Second: `dbt run --select int_mmm__daily_channel_spend` (no flag)
2. Verify row counts increase or stay same (not decrease)
3. Document expected behavior in model config comments

---

### Risk 3: Cross-Source Freshness Differences

**Impact areas:** Phase 6 (source freshness)

**Challenge:** Adjust S3 (6-hour refresh), Supermetrics (daily refresh), Amplitude (12-hour refresh) have different SLAs

**Mitigation strategy:**
1. Configure freshness per source's actual SLA:
   ```yaml
   # Adjust: S3 exports every 6 hours
   warn_after: {count: 8, period: hour}

   # Supermetrics: Daily refresh
   warn_after: {count: 30, period: hour}

   # Amplitude: 12-hour refresh
   warn_after: {count: 15, period: hour}
   ```

2. Don't use `error_after` for sources outside dbt control (upstream data providers)

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Source Freshness | HIGH | Verified with official dbt docs, Snowflake-specific timezone/timestamp guidance |
| Singular Tests | HIGH | Validated against dbt testing best practices, cross-referenced multiple sources |
| Macro Extraction | MEDIUM | Based on dbt macro docs + community testing patterns, but WGT's no-local-dbt constraint limits validation options |
| Incremental Models | HIGH | Official dbt docs on `is_incremental()`, clone-for-CI patterns |
| Snowflake Case Sensitivity | HIGH | Official Snowflake identifier docs, verified dbt seed behavior via GitHub issues |

---

## Gaps to Address

**Unknown 1: Actual Snowflake timestamp column types in WGT sources**
- Need to run `DESCRIBE TABLE` for Adjust, Amplitude, Supermetrics tables to confirm `TIMESTAMP_NTZ` vs `TIMESTAMP_LTZ`
- Impacts timezone conversion requirements (Pitfall 3)
- **Resolution:** Run audit query in Phase 6 before configuring freshness

**Unknown 2: Actual data refresh frequencies**
- Research assumes Adjust S3 (6hr), Supermetrics (daily), Amplitude (12hr) but not verified
- Impacts `warn_after` threshold configuration
- **Resolution:** Ask WGT data engineering team for SLAs, or observe `MAX(LOAD_TIMESTAMP)` patterns over 1 week

**Unknown 3: network_mapping.csv completeness**
- Research assumes seed covers all active partners, but STATE.md says "coverage unknown"
- Impacts AD_PARTNER macro extraction (what happens for unmapped networks?)
- **Resolution:** Phase 4 must include coverage audit before macro extraction

---

## Sources

### dbt Official Documentation
- [dbt source freshness](https://docs.getdbt.com/reference/resource-properties/freshness)
- [Add sources to your DAG](https://docs.getdbt.com/docs/build/sources)
- [Configure incremental models](https://docs.getdbt.com/docs/build/incremental-models)
- [Incremental models in-depth](https://docs.getdbt.com/best-practices/materializations/4-incremental-models)
- [Clone incremental models as the first step of your CI job](https://docs.getdbt.com/best-practices/clone-incremental-models)
- [dbt Jinja and macros](https://docs.getdbt.com/docs/build/jinja-macros)
- [Configuring quoting in dbt projects](https://docs.getdbt.com/reference/project-configs/quoting)
- [Unit tests](https://docs.getdbt.com/docs/build/unit-tests)
- [Testing incremental models](https://discourse.getdbt.com/t/testing-incremental-models/1528)

### Community Best Practices
- [How to use dbt source freshness tests to detect stale data](https://www.datafold.com/blog/dbt-source-freshness)
- [Guide to Using dbt Source Freshness for Data Updates](https://www.secoda.co/learn/dbt-source-freshness)
- [7 dbt Testing Best Practices](https://www.datafold.com/blog/7-dbt-testing-best-practices)
- [dbt tests: How to write fewer and better data tests](https://www.elementary-data.com/post/dbt-tests)
- [Everything you need to know about dbt tests](https://www.metaplane.dev/blog/dbt-test-examples-best-practices)
- [Challenges with DBT Tests in Practice](https://datasettler.com/blog/post-4-dbt-pitfalls-in-practice/)
- [How to unit test macros in dbt](https://medium.com/glitni/how-to-unit-test-macros-in-dbt-89bdb5de8634)
- [Unit Testing dbt Macros: A workaround for dbt's unit testing limitations](https://www.dumky.net/posts/unit-testing-dbt-macros-a-workaround-for-dbts-unit-testing-limitations/)
- [dbt data quality framework](https://www.getdbt.com/blog/building-a-data-quality-framework-with-dbt-and-dbt-cloud)
- [5 essential data quality checks for analytics](https://www.getdbt.com/blog/data-quality-checks)
- [Guide to dbt data quality checks](https://www.metaplane.dev/blog/guide-to-dbt-data-quality-checks)

### Snowflake Documentation
- [Snowflake identifier requirements](https://docs.snowflake.com/en/sql-reference/identifiers-syntax)
- [Snowflake timezone handling](https://docs.snowflake.com/en/sql-reference/functions/convert_timezone)

### GitHub Issues & Community Forums
- [dbt seed case sensitivity issue](https://github.com/dbt-labs/dbt-core/issues/7265)
- [Using a non-UTC timestamp when calculating source freshness](https://discourse.getdbt.com/t/using-a-non-utc-timestamp-when-calculating-source-freshness/1237)

---

**Research completed:** 2026-02-11
**Confidence:** HIGH for source freshness and testing patterns, MEDIUM for macro extraction (constrained by no-local-dbt environment)
**Next steps:** Use this document during Phases 4-6 planning to structure prevention strategies into task lists
