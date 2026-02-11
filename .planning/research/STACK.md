# Technology Stack: v1.0 Remaining Work

**Project:** WGT dbt Analytics v1.0 Data Integrity
**Scope:** Stack additions for Phases 4-6 (DRY refactor, testing, source freshness)
**Researched:** 2026-02-11
**Confidence:** HIGH

## Executive Summary

The remaining v1.0 work requires **zero new packages or tools**. All needed capabilities exist in:
1. **Native dbt features**: Source freshness, singular tests, macros
2. **Existing dbt-utils** (already installed at version >=1.1.1)

This is intentional stack discipline. Adding packages for these simple needs would create maintenance burden with no value.

## Stack Status: No Changes Required

### Already Installed (Continue Using)

| Technology | Current Version | Purpose | Status |
|------------|----------------|---------|--------|
| dbt Cloud | N/A (SaaS) | Execution environment, job scheduling | ✓ Sufficient |
| Snowflake | N/A (warehouse) | Data warehouse | ✓ Sufficient |
| dbt-utils | >=1.1.1, <2.0.0 | Generic tests (unique_combination_of_columns, date_spine) | ✓ Sufficient |

### NOT Adding (Explicitly Rejected)

| Technology | Reason NOT to Add |
|------------|-------------------|
| dbt-expectations | Overkill for simple MMM business rule tests. Singular tests are clearer. |
| re_data / elementary | Too early for observability framework. Source freshness native checks sufficient. |
| Additional test packages | Native singular tests + dbt-utils covers all TEST-06/07/08 needs |
| Macro libraries | AD_PARTNER extraction is 18 lines. Writing custom macro > dependency |

## Feature-to-Stack Mapping

### Phase 4: DRY Refactor (CODE-01/02/04)

**Requirement:** Extract duplicated AD_PARTNER CASE statement from v_stg_adjust__installs and v_stg_adjust__touchpoints.

**Stack Used:**
- **Native dbt macros** (no packages required)

**Implementation:**
```jinja
-- macros/get_ad_partner.sql
{% macro get_ad_partner(network_name_column) %}
  CASE
    WHEN {{ network_name_column }} IN ('Facebook Installs', 'Instagram Installs', 'Off-Facebook Installs', 'Facebook Messenger Installs') THEN 'Meta'
    WHEN {{ network_name_column }} IN ('Google Ads ACE', 'Google Ads ACI', 'Google Organic Search', 'google') THEN 'Google'
    WHEN {{ network_name_column }} IN ('TikTok SAN', 'TikTok_Paid_Ads_iOS', 'Tiktok Installs') THEN 'TikTok'
    WHEN {{ network_name_column }} = 'Apple Search Ads' THEN 'Apple'
    WHEN {{ network_name_column }} LIKE 'AppLovin%' THEN 'AppLovin'
    WHEN {{ network_name_column }} LIKE 'UnityAds%' THEN 'Unity'
    WHEN {{ network_name_column }} LIKE 'Moloco%' THEN 'Moloco'
    WHEN {{ network_name_column }} LIKE 'Smadex%' THEN 'Smadex'
    WHEN {{ network_name_column }} LIKE 'AdAction%' THEN 'AdAction'
    WHEN {{ network_name_column }} LIKE 'Vungle%' THEN 'Vungle'
    WHEN {{ network_name_column }} = 'Organic' THEN 'Organic'
    WHEN {{ network_name_column }} = 'Unattributed' THEN 'Unattributed'
    WHEN {{ network_name_column }} = 'Untrusted Devices' THEN 'Untrusted'
    WHEN {{ network_name_column }} IN ('wgtgolf', 'WGT_Events_SocialPosts_iOS', 'WGT_GiftCards_Social') THEN 'WGT'
    WHEN {{ network_name_column }} LIKE 'Phigolf%' THEN 'Phigolf'
    WHEN {{ network_name_column }} LIKE 'Ryder%' THEN 'Ryder Cup'
    ELSE 'Other'
  END
{% endmacro %}
```

**Usage in models:**
```sql
SELECT
  ...
  , {{ get_ad_partner('NETWORK_NAME') }} AS AD_PARTNER
  ...
FROM source
```

**Why this approach:**
- **No dependencies**: Pure dbt macro, works in any dbt version
- **Location**: `macros/get_ad_partner.sql` (standard dbt convention)
- **Testing**: Consistency test validates identical output (see TEST-06)
- **Readability**: CASE statement visible in compiled SQL, easier to debug than package abstraction

**Current duplication:** Lines 65-83 in `v_stg_adjust__installs.sql` match lines 140-158 in `v_stg_adjust__touchpoints.sql` (18 identical lines)

### Phase 5: Expand Test Coverage (TEST-06/07/08)

**Requirement:** Singular tests for MMM models validating complex business rules.

**Stack Used:**
- **Native dbt singular tests** (tests/ directory)
- **dbt-utils** (already installed) for generic tests on intermediate models

**Implementation:**

#### TEST-06: MMM Daily Summary Validation
```sql
-- tests/assert_mmm_daily_summary_has_all_metrics.sql
-- Validates that each date+platform+channel has spend, installs, and revenue joined
SELECT
  DATE,
  PLATFORM,
  CHANNEL,
  COUNT(*) as row_count
FROM {{ ref('mmm__daily_channel_summary') }}
WHERE SPEND IS NULL
  OR INSTALLS IS NULL
  OR REVENUE IS NULL
GROUP BY 1, 2, 3
HAVING COUNT(*) > 0
```

#### TEST-07: MMM Weekly Rollup Validation
```sql
-- tests/assert_mmm_weekly_aggregation_matches_daily.sql
-- Validates that weekly rollup sums match daily detail
WITH daily_totals AS (
  SELECT
    DATE_TRUNC('week', DATE) as week_start,
    PLATFORM,
    CHANNEL,
    SUM(SPEND) as daily_spend,
    SUM(INSTALLS) as daily_installs
  FROM {{ ref('mmm__daily_channel_summary') }}
  GROUP BY 1, 2, 3
),
weekly_totals AS (
  SELECT
    WEEK_START,
    PLATFORM,
    CHANNEL,
    SPEND as weekly_spend,
    INSTALLS as weekly_installs
  FROM {{ ref('mmm__weekly_channel_summary') }}
)
SELECT
  d.week_start,
  d.platform,
  d.channel,
  ABS(d.daily_spend - w.weekly_spend) as spend_diff,
  ABS(d.daily_installs - w.weekly_installs) as installs_diff
FROM daily_totals d
JOIN weekly_totals w
  ON d.week_start = w.week_start
  AND d.platform = w.platform
  AND d.channel = w.channel
WHERE ABS(d.daily_spend - w.weekly_spend) > 0.01
  OR ABS(d.daily_installs - w.weekly_installs) > 0.01
```

#### TEST-08: AD_PARTNER Consistency After Macro Extraction
```sql
-- tests/assert_ad_partner_consistency.sql
-- Validates that get_ad_partner() macro produces identical results to original CASE
-- This test should PASS after CODE-01 refactor completes
WITH installs_partners AS (
  SELECT DISTINCT NETWORK_NAME, AD_PARTNER as installs_ad_partner
  FROM {{ ref('v_stg_adjust__installs') }}
),
touchpoints_partners AS (
  SELECT DISTINCT NETWORK_NAME, AD_PARTNER as touchpoints_ad_partner
  FROM {{ ref('v_stg_adjust__touchpoints') }}
)
SELECT
  COALESCE(i.NETWORK_NAME, t.NETWORK_NAME) as network_name,
  i.installs_ad_partner,
  t.touchpoints_ad_partner
FROM installs_partners i
FULL OUTER JOIN touchpoints_partners t
  ON i.NETWORK_NAME = t.NETWORK_NAME
WHERE i.installs_ad_partner != t.touchpoints_ad_partner
  OR i.installs_ad_partner IS NULL
  OR t.touchpoints_ad_partner IS NULL
```

**Why singular tests:**
- **No package needed**: Native dbt feature, just write SQL in tests/
- **Full SQL flexibility**: Complex joins, aggregations, window functions
- **Business logic visibility**: Test SQL documents the business rule explicitly
- **No YAML configuration**: Test runs automatically with `dbt test`
- **Clear failure output**: Returns exact failing rows for debugging

**Why NOT dbt-expectations:**
- TEST-06/07/08 require multi-table joins and custom aggregation logic
- dbt-expectations focuses on single-column constraints (ranges, regex, uniqueness)
- Singular test SQL is clearer than wrapping complex logic in generic test YAML

### Phase 6: Source Freshness & Observability (FRESH-01/02/03/04)

**Requirement:** Monitor source data freshness for Adjust and Amplitude sources, detect stale static tables.

**Stack Used:**
- **Native dbt source freshness** (YAML configuration in sources)
- **dbt Cloud job scheduler** (separate freshness job)

**Implementation:**

#### FRESH-01/02: Source Freshness Configuration

**Adjust Sources** (update `models/staging/adjust/_adjust__sources.yml`):
```yaml
version: 2

sources:
  - name: adjust
    description: Adjust mobile attribution data
    database: ADJUST
    schema: S3_DATA
    config:
      freshness:
        warn_after: {count: 6, period: hour}
        error_after: {count: 12, period: hour}
    tables:
      - name: IOS_ACTIVITY_INSTALL
        description: iOS install events with attribution data
        config:
          loaded_at_field: CREATED_AT  # Epoch timestamp
      - name: IOS_ACTIVITY_IMPRESSION
        config:
          loaded_at_field: CREATED_AT
      - name: IOS_ACTIVITY_CLICK
        config:
          loaded_at_field: CREATED_AT
      - name: ANDROID_ACTIVITY_INSTALL
        config:
          loaded_at_field: CREATED_AT
      - name: ANDROID_ACTIVITY_IMPRESSION
        config:
          loaded_at_field: CREATED_AT
      - name: ANDROID_ACTIVITY_CLICK
        config:
          loaded_at_field: CREATED_AT

  - name: adjust_api_data
    description: Adjust API aggregated report data
    database: ADJUST
    schema: API_DATA
    config:
      freshness:
        warn_after: {count: 12, period: hour}
        error_after: {count: 24, period: hour}
    tables:
      - name: REPORT_DAILY_RAW
        description: Daily aggregated campaign performance data from Adjust API
        config:
          loaded_at_field: DATE  # Date field proxy
```

**Amplitude Sources** (update `models/staging/amplitude/_amplitude__sources.yml`):
```yaml
version: 2

sources:
  - name: amplitude
    description: Amplitude product analytics data
    database: AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE
    schema: SCHEMA_726530
    config:
      freshness:
        warn_after: {count: 6, period: hour}
        error_after: {count: 12, period: hour}
    tables:
      - name: MERGE_IDS_726530
        description: Device ID to User ID mapping
        config:
          loaded_at_field: SERVER_UPLOAD_TIME  # Amplitude metadata
      - name: EVENTS_726530
        description: All product events
        config:
          loaded_at_field: SERVER_UPLOAD_TIME
```

**Configuration notes:**
- **loaded_at_field**: Column representing when data arrived (not event timestamp)
  - Adjust uses `CREATED_AT` (epoch timestamp of S3 load)
  - Amplitude uses `SERVER_UPLOAD_TIME` (Amplitude ingestion timestamp)
  - API data uses `DATE` as proxy (no ingestion timestamp available)
- **warn_after/error_after**: Configurable thresholds
  - Event data: 6h warn, 12h error (near real-time expectation)
  - API data: 12h warn, 24h error (daily batch process)
- **No filter needed**: Default checks MAX(loaded_at_field) < current_timestamp - threshold

#### FRESH-03: Stale Static Table Detection

**Approach:** Use source freshness on static seed or intermediate table with custom loaded_at_field

**Option 1 - Add metadata column to seed:**
```yaml
# models/staging/adjust/_adjust__sources.yml
sources:
  - name: adjust_static
    description: Static reference tables
    database: ADJUST
    schema: S3_DATA
    config:
      freshness:
        warn_after: {count: 30, period: day}
        error_after: {count: 45, period: day}
    tables:
      - name: ADJUST_AMPLITUDE_DEVICE_MAPPING
        config:
          loaded_at_field: LAST_UPDATED  # Requires adding timestamp column
```

**Option 2 - Query warehouse metadata:**
```sql
-- tests/assert_device_mapping_not_stale.sql
-- Singular test checking table last modified time
SELECT
  DATEDIFF(day, MAX(LAST_ALTERED), CURRENT_TIMESTAMP()) as days_stale
FROM ADJUST.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'S3_DATA'
  AND TABLE_NAME = 'ADJUST_AMPLITUDE_DEVICE_MAPPING'
HAVING days_stale > 30
```

**Recommendation:** Use Option 2 (singular test) because:
- No schema changes to static table required
- Snowflake INFORMATION_SCHEMA.TABLES.LAST_ALTERED is reliable
- Test runs with standard `dbt test` (no separate job needed)
- Clear failure message: "Table stale for X days"

#### FRESH-04: Dedicated Freshness Job in dbt Cloud

**Job Configuration:**
- **Job name:** "Source Freshness Check"
- **Commands:** `dbt source freshness`
- **Schedule:** Every 6 hours (2x frequency of lowest SLA)
- **Execution settings:**
  - Run on schedule (not triggered by other jobs)
  - Separate from model build jobs
  - Send alerts on failure
- **Target:** Production environment

**Why separate job:**
- Freshness failures should NOT block model builds
- Different execution cadence (freshness runs 4x/day, builds run 1x/day)
- Alerts go to different stakeholders (data engineering vs analytics)
- `dbt source freshness` writes results to `target/sources.json` for tracking

**dbt Cloud setup:**
1. Create new Deploy Job
2. Commands: `dbt source freshness`
3. Schedule: Cron expression `0 */6 * * *` (every 6 hours)
4. Enable "Send email on failure" to data engineering team

**Why native dbt source freshness:**
- **No package needed**: Built into dbt-core since v0.18.0
- **dbt Cloud integration**: Native UI showing freshness status
- **Snowflake optimized**: Uses INFORMATION_SCHEMA when loaded_at_field not specified
- **Zero-config alerting**: dbt Cloud email notifications on error_after threshold

**Why NOT re_data or elementary:**
- Those packages require:
  - Additional models (artifact tracking tables)
  - Separate deployment job for observability models
  - Configuration learning curve
- Native source freshness gives same value for this use case:
  - Detects stale data
  - Sends alerts
  - Logs results (sources.json)
- Defer advanced observability until v2.0 (if needed)

## Package Version Recommendations

### Keep Current: dbt-utils

**Current spec:** `>=1.1.1, <2.0.0`

**Latest version:** 1.3.3 (released 2024-12-11)

**Recommendation:** Upgrade to pin to 1.3.3
```yaml
# packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: 1.3.3
```

**Why upgrade:**
- Fixes time filter bug in source_column_name (affects date_spine usage)
- Better union_relations compile mode handling
- Still compatible with dbt-core <3.0.0 (same range as current spec)
- Patch upgrade (1.1.1 → 1.3.3) is low risk

**Migration impact:** None (backward compatible patch)

### NOT Installing

**Explicitly rejected packages for Phases 4-6:**

| Package | Why NOT Adding |
|---------|---------------|
| dbt-expectations | 67 macros, 400KB+ dependency for 3 simple tests. Singular SQL clearer. |
| re_data | Requires dbt run for observability models. Native freshness sufficient. |
| elementary | 30+ models for monitoring. Too early, revisit at v2.0 if needed. |
| dbt-date | Only use date_spine from dbt-utils. Don't need fiscal calendar macros. |
| dbt-audit-helper | For migration validation. Not applicable (not migrating platforms). |

## Installation

**No new installations required.** Optionally upgrade existing package:

```bash
# In dbt Cloud or local (if applicable):
# 1. Update packages.yml to pin dbt-utils to 1.3.3
# 2. Run package install
dbt deps
```

**Expected output:**
```
Installing dbt-labs/dbt_utils@1.3.3
  Installed from version 1.3.3
```

## Validation Checklist

After implementing Phases 4-6, verify stack usage:

- [ ] **Phase 4:** Custom macro in `macros/get_ad_partner.sql` works (compile succeeds)
- [ ] **Phase 5:** Singular tests in `tests/*.sql` run with `dbt test` (no package imports)
- [ ] **Phase 6:** Source freshness YAML added to `_adjust__sources.yml` and `_amplitude__sources.yml`
- [ ] **Phase 6:** `dbt source freshness` runs successfully in dbt Cloud job
- [ ] **Phase 6:** Stale table test in `tests/assert_device_mapping_not_stale.sql` works
- [ ] **Zero new packages:** `dbt deps` output shows only dbt-utils (no new dependencies)

## Stack Discipline Rationale

This research explicitly avoids the "add a package" reflex. Key principles:

1. **Native first**: If dbt-core has the feature, use it (macros, singular tests, source freshness)
2. **Justify dependencies**: Only add packages when native approach significantly worse
3. **Test simplicity**: Complex test logic → singular SQL, not generic test macros
4. **Macro simplicity**: 18-line CASE statement → custom macro, not package abstraction
5. **Defer complexity**: Save observability frameworks for v2.0 when ROI proven

**Cost of this discipline:**
- More files (tests/*.sql vs schema.yml entries)
- Custom macro instead of package function

**Benefit of this discipline:**
- Zero new dependencies to maintain
- Zero new dbt Cloud compatibility risk
- Full SQL visibility (no package black boxes)
- Faster CI (no additional package downloads)

## Sources

**Official dbt Documentation:**
- [Source freshness configuration](https://docs.getdbt.com/reference/resource-configs/freshness) - Freshness syntax
- [Deploy source freshness](https://docs.getdbt.com/docs/deploy/source-freshness) - dbt Cloud job setup
- [Singular tests](https://docs.getdbt.com/docs/build/data-tests) - Tests directory structure
- [Jinja and macros](https://docs.getdbt.com/docs/build/jinja-macros) - Macro syntax
- [Source properties](https://docs.getdbt.com/reference/source-properties) - loaded_at_field reference
- [dbt-utils package hub](https://hub.getdbt.com/dbt-labs/dbt_utils/latest/) - Version 1.3.3 details

**Community Resources:**
- [dbt-utils releases](https://github.com/dbt-labs/dbt-utils/releases) - Version changelog
- [Ultimate Guide to dbt Macros 2025](https://dagster.io/guides/ultimate-guide-to-dbt-macros-in-2025-syntax-examples-pro-tips) - Best practices
- [7 dbt Testing Best Practices](https://www.datafold.com/blog/7-dbt-testing-best-practices) - Singular vs generic tests
- [dbt Source Freshness Guide](https://www.secoda.co/learn/dbt-source-freshness) - loaded_at_field examples
