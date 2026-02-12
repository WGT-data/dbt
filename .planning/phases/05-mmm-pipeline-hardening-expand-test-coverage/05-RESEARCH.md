# Phase 5: MMM Pipeline Hardening + Expand Test Coverage - Research

**Researched:** 2026-02-11
**Domain:** dbt incremental models, data quality testing, MMM data validation
**Confidence:** HIGH

## Summary

Phase 5 validates the MMM pipeline built in Phase 3-4 by running models in dbt Cloud (local execution blocked by key-pair auth) and adding comprehensive data quality tests. The phase has two parallel workstreams: (1) hardening the MMM pipeline to ensure it runs successfully with correct incremental behavior, and (2) expanding test coverage with three singular tests that validate date spine completeness, cross-layer consistency, and zero-fill integrity.

Research focused on dbt incremental model best practices (merge strategy, unique_key configuration, full-refresh vs incremental testing), singular test patterns for complex validation logic, and network mapping coverage validation strategies. The standard approach is to use merge strategy with composite unique_key for incremental models, validate both full-refresh and incremental runs, and write custom singular tests for business-specific assertions that generic tests can't express.

Key findings: Incremental models with merge strategy require explicit unique_key configuration to avoid append-only behavior. Network mapping coverage requires comparing seed data to distinct source values. KPI calculations should use CASE WHEN denominators or dbt_utils.safe_divide to prevent division-by-zero errors. Singular tests are the right tool for validating date spine completeness and cross-model aggregation consistency.

**Primary recommendation:** Run dbt Cloud compile and run to validate MMM models, fix any compilation or runtime errors, verify incremental merge behavior with lookback window, validate network_mapping seed coverage, and add three singular tests for date spine completeness, cross-layer totals consistency, and data quality flag integrity.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dbt-core | Current (1.8+) | Data transformation framework | Project already uses dbt with Snowflake |
| dbt-utils | >=1.1.1, <2.0 | Generic test utilities, date_spine macro | Already installed (packages.yml) |
| dbt-snowflake | Current | Snowflake database adapter | Project uses Snowflake (confirmed) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| dbt-expectations | 0.10.0+ | Advanced data quality tests (optional) | For date completeness validation (expect_row_values_to_have_data_for_every_n_datepart) |
| audit_helper | 0.12.0 | Refactoring verification | Already installed in Phase 4 for comparing outputs |

**Note:** dbt-expectations is OPTIONAL for this phase. The required tests (date spine completeness, cross-layer consistency, zero-fill flags) can be written as singular tests without external packages.

**Installation (if using dbt-expectations):**
```yaml
# Add to packages.yml (optional)
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.1.1", "<2.0.0"]
  - package: dbt-labs/audit_helper
    version: 0.12.0
  - package: calogica/dbt-expectations
    version: 0.10.3
```

Then run:
```bash
dbt deps
```

## Architecture Patterns

### Recommended Test Structure

```
tests/
├── singular/
│   ├── test_ad_partner_mapping_consistency.sql     # Existing (Phase 4)
│   ├── test_mmm_date_spine_completeness.sql        # NEW - Phase 5
│   ├── test_mmm_cross_layer_consistency.sql        # NEW - Phase 5
│   └── test_mmm_zero_fill_integrity.sql            # NEW - Phase 5
```

### Pattern 1: Incremental Models with Merge Strategy

**What:** Incremental materialization using merge strategy to upsert records based on unique_key.

**When to use:** For aggregation tables that need to handle late-arriving data or reprocessing without duplicates.

**Example (from int_mmm__daily_channel_spend.sql):**
```sql
{{
    config(
        materialized='incremental',
        unique_key=['DATE', 'PLATFORM', 'CHANNEL'],
        incremental_strategy='merge',
        tags=['mmm', 'spend']
    )
}}

WITH spend_with_channel AS (
    SELECT
        s.DATE,
        s.PLATFORM,
        COALESCE(nm.AD_PARTNER, 'Other') AS CHANNEL,
        SUM(s.COST) AS SPEND,
        SUM(s.IMPRESSIONS) AS IMPRESSIONS,
        SUM(s.CLICKS) AS CLICKS,
        SUM(s.PAID_INSTALLS) AS PAID_INSTALLS
    FROM {{ ref('stg_supermetrics__adj_campaign') }} s
    LEFT JOIN {{ ref('network_mapping') }} nm
        ON s.PARTNER_NAME = nm.SUPERMETRICS_PARTNER_NAME
    WHERE s.DATE IS NOT NULL
      AND s.COST > 0
    {% if is_incremental() %}
      -- 7-day lookback captures late-arriving data
      AND s.DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3
)

SELECT DATE, PLATFORM, CHANNEL, SPEND, IMPRESSIONS, CLICKS, PAID_INSTALLS
FROM spend_with_channel
```

**Key elements:**
- **unique_key as array:** Multiple columns define uniqueness at DATE+PLATFORM+CHANNEL grain
- **Lookback window:** 7-day overlap captures late-arriving data without reprocessing entire history
- **WHERE filter before is_incremental():** Base filter (DATE IS NOT NULL) applies to both full-refresh and incremental runs
- **Merge strategy:** Updates existing rows (same unique_key) and inserts new rows

**Source:** [dbt docs - About incremental strategy](https://docs.getdbt.com/docs/build/incremental-strategy)

### Pattern 2: Singular Test for Date Spine Completeness

**What:** SQL query that identifies missing date+channel+platform combinations in a date spine model.

**When to use:** When you need gap-free time series (critical for MMM regression models).

**Example:**
```sql
-- tests/singular/test_mmm_date_spine_completeness.sql
-- Validates that every date between start and end has a row for every channel+platform combination

WITH expected_dates AS (
    -- Generate expected date range
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="'2024-01-01'",
        end_date="current_date()"
    ) }}
),

expected_channels AS (
    -- Get all channel+platform combinations that should exist
    SELECT DISTINCT PLATFORM, CHANNEL
    FROM {{ ref('mmm__daily_channel_summary') }}
),

expected_grid AS (
    -- Every date should have every channel+platform
    SELECT
        CAST(d.date_day AS DATE) AS DATE,
        c.PLATFORM,
        c.CHANNEL
    FROM expected_dates d
    CROSS JOIN expected_channels c
),

actual_data AS (
    SELECT DATE, PLATFORM, CHANNEL
    FROM {{ ref('mmm__daily_channel_summary') }}
)

-- Return rows that are missing (test fails if any rows returned)
SELECT
    eg.DATE,
    eg.PLATFORM,
    eg.CHANNEL,
    'Missing from mmm__daily_channel_summary' AS error_reason
FROM expected_grid eg
LEFT JOIN actual_data ad
    ON eg.DATE = ad.DATE
    AND eg.PLATFORM = ad.PLATFORM
    AND eg.CHANNEL = ad.CHANNEL
WHERE ad.DATE IS NULL
```

**Rationale:** Singular test returns failing rows (rows that violate assertion). Zero rows = test passes. This test ensures MMM models have complete date coverage with no gaps.

**Source:** [dbt docs - Add data tests to your DAG](https://docs.getdbt.com/docs/build/data-tests)

### Pattern 3: Singular Test for Cross-Layer Aggregation Consistency

**What:** SQL query that compares aggregated totals across layers (intermediate → mart) to detect summation errors.

**When to use:** When mart models aggregate intermediate models and you need to ensure no data is lost or duplicated.

**Example:**
```sql
-- tests/singular/test_mmm_cross_layer_consistency.sql
-- Validates that intermediate layer totals match daily summary totals

WITH intermediate_totals AS (
    SELECT
        DATE,
        PLATFORM,
        SUM(SPEND) AS total_spend,
        SUM(INSTALLS) AS total_installs,
        SUM(REVENUE) AS total_revenue
    FROM (
        SELECT DATE, PLATFORM, SPEND, 0 AS INSTALLS, 0 AS REVENUE
        FROM {{ ref('int_mmm__daily_channel_spend') }}
        UNION ALL
        SELECT DATE, PLATFORM, 0, INSTALLS, 0
        FROM {{ ref('int_mmm__daily_channel_installs') }}
        UNION ALL
        SELECT DATE, PLATFORM, 0, 0, REVENUE
        FROM {{ ref('int_mmm__daily_channel_revenue') }}
    )
    GROUP BY 1, 2
),

mart_totals AS (
    SELECT
        DATE,
        PLATFORM,
        SUM(SPEND) AS total_spend,
        SUM(INSTALLS) AS total_installs,
        SUM(REVENUE) AS total_revenue
    FROM {{ ref('mmm__daily_channel_summary') }}
    -- Only check rows that have actual data (not zero-filled by date spine)
    WHERE HAS_SPEND_DATA = 1 OR HAS_INSTALL_DATA = 1 OR HAS_REVENUE_DATA = 1
    GROUP BY 1, 2
)

-- Return mismatches (test fails if any discrepancies)
SELECT
    COALESCE(i.DATE, m.DATE) AS DATE,
    COALESCE(i.PLATFORM, m.PLATFORM) AS PLATFORM,
    i.total_spend AS intermediate_spend,
    m.total_spend AS mart_spend,
    i.total_installs AS intermediate_installs,
    m.total_installs AS mart_installs,
    i.total_revenue AS intermediate_revenue,
    m.total_revenue AS mart_revenue,
    CASE
        WHEN ABS(COALESCE(i.total_spend, 0) - COALESCE(m.total_spend, 0)) > 0.01 THEN 'SPEND_MISMATCH'
        WHEN ABS(COALESCE(i.total_installs, 0) - COALESCE(m.total_installs, 0)) > 0 THEN 'INSTALLS_MISMATCH'
        WHEN ABS(COALESCE(i.total_revenue, 0) - COALESCE(m.total_revenue, 0)) > 0.01 THEN 'REVENUE_MISMATCH'
    END AS error_type
FROM intermediate_totals i
FULL OUTER JOIN mart_totals m
    ON i.DATE = m.DATE AND i.PLATFORM = m.PLATFORM
WHERE ABS(COALESCE(i.total_spend, 0) - COALESCE(m.total_spend, 0)) > 0.01
   OR ABS(COALESCE(i.total_installs, 0) - COALESCE(m.total_installs, 0)) > 0
   OR ABS(COALESCE(i.total_revenue, 0) - COALESCE(m.total_revenue, 0)) > 0.01
```

**Rationale:** Detects if date spine grid introduces duplication or if aggregation logic drops rows. Uses small tolerance (0.01) for floating-point comparison.

**Source:** [dbt-expectations - expect_table_aggregation_to_equal_other_table](https://github.com/calogica/dbt-expectations) (adapted as singular test)

### Pattern 4: KPI Calculation with Division-by-Zero Protection

**What:** Use CASE WHEN or NULLIF to return NULL instead of error when dividing by zero.

**When to use:** For calculated metrics like CPI (spend/installs) or ROAS (revenue/spend).

**Example (from mmm__daily_channel_summary.sql):**
```sql
-- Derived KPIs with NULL for undefined values
CASE WHEN COALESCE(i.INSTALLS, 0) > 0
     THEN COALESCE(s.SPEND, 0) / i.INSTALLS
     ELSE NULL
END AS CPI,

CASE WHEN COALESCE(s.SPEND, 0) > 0
     THEN COALESCE(r.REVENUE, 0) / s.SPEND
     ELSE NULL
END AS ROAS
```

**Alternative (using dbt_utils.safe_divide):**
```sql
{{ dbt_utils.safe_divide(
    numerator='COALESCE(s.SPEND, 0)',
    denominator='i.INSTALLS'
) }} AS CPI
```

**Rationale:** Division by zero causes SQL errors. CASE WHEN checks denominator > 0 before division. NULL is semantically correct (CPI undefined when installs = 0).

**Source:** [GitHub - dbt-utils safe_divide macro](https://github.com/dbt-labs/dbt-utils/issues/679), [dbt docs - Ratio metrics](https://docs.getdbt.com/docs/build/ratio)

### Pattern 5: Network Mapping Coverage Validation

**What:** Query to identify source values (PARTNER_NAME) that aren't mapped in network_mapping seed.

**When to use:** To validate reference data completeness before production deployment.

**Example:**
```sql
-- analysis/unmapped_partners.sql (analysis, not a test)
WITH active_partners AS (
    -- Partners with spend in last 90 days from Supermetrics
    SELECT DISTINCT PARTNER_NAME
    FROM {{ ref('stg_supermetrics__adj_campaign') }}
    WHERE DATE >= DATEADD(day, -90, CURRENT_DATE)
      AND COST > 0

    UNION

    -- Partners with revenue in last 90 days from Adjust API
    SELECT DISTINCT PARTNER_NAME
    FROM {{ ref('stg_adjust__report_daily') }}
    WHERE DATE >= DATEADD(day, -90, CURRENT_DATE)
      AND REVENUE > 0
),

mapped_partners AS (
    SELECT SUPERMETRICS_PARTNER_NAME AS PARTNER_NAME
    FROM {{ ref('network_mapping') }}
    WHERE SUPERMETRICS_PARTNER_NAME IS NOT NULL

    UNION

    SELECT ADJUST_NETWORK_NAME
    FROM {{ ref('network_mapping') }}
    WHERE ADJUST_NETWORK_NAME IS NOT NULL
)

-- Active partners not in mapping seed
SELECT
    ap.PARTNER_NAME,
    'Missing from network_mapping seed' AS issue,
    'Will map to Other in MMM models' AS impact
FROM active_partners ap
LEFT JOIN mapped_partners mp
    ON ap.PARTNER_NAME = mp.PARTNER_NAME
WHERE mp.PARTNER_NAME IS NULL
ORDER BY ap.PARTNER_NAME
```

**Rationale:** This is an analysis query (saved in analysis/ directory), not a test. It helps identify coverage gaps but doesn't fail builds. Use this to discover unmapped partners, then update network_mapping.csv seed as needed.

**Source:** Project context (network_mapping.csv has 29 rows, need to validate against active partners)

### Anti-Patterns to Avoid

- **Missing unique_key in incremental models:** Without unique_key, merge strategy behaves like append, creating duplicates
- **No lookback window in incremental filter:** Captures only new data, missing late-arriving updates
- **Testing only full-refresh mode:** Incremental logic often differs, test both scenarios
- **Hardcoding dates in tests:** Use CURRENT_DATE or relative date functions for evergreen tests
- **Not filtering by data flags in cross-layer tests:** Date spine adds zero-filled rows, causing false mismatches
- **Using equality (=) for floating-point comparisons:** Use ABS(diff) < tolerance for spend/revenue

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Date spine generation | Recursive CTEs or manual calendar tables | dbt_utils.date_spine macro | Already packaged, handles edge cases (leap years, timezone), widely tested |
| Division-by-zero handling | Manual CASE WHEN everywhere | dbt_utils.safe_divide macro (optional) | Consistent pattern across project, less error-prone |
| Cross-table aggregation tests | Separate queries run manually | Singular tests in tests/singular/ | Automated by dbt test, version-controlled, runs in CI/CD |
| Incremental model testing | Manual comparison queries | dbt Cloud full-refresh vs incremental runs | Built-in behavior, no custom scripts needed |
| Network mapping coverage audit | Excel spreadsheets or BI tool queries | dbt analysis queries (analysis/ directory) | Lives with code, reproducible, uses ref() for consistency |

**Key insight:** dbt's testing framework is designed for data quality validation. Singular tests are the right tool for custom business logic that can't be expressed with generic tests (unique, not_null, etc.).

## Common Pitfalls

### Pitfall 1: Incremental Models Append Instead of Merge

**What goes wrong:** Running incremental model creates duplicate rows for existing unique_key values instead of updating them.

**Why it happens:** Missing or incorrect unique_key configuration. From dbt docs: "If you use merge without specifying a unique_key, it behaves like the append strategy."

**How to avoid:**
1. Always specify unique_key in config block for merge strategy
2. Use array syntax for composite keys: `unique_key=['DATE', 'PLATFORM', 'CHANNEL']`
3. Verify unique_key matches the grain of the model (one row per unique_key combination)
4. Test with --full-refresh first, then test incremental run to verify merge behavior

**Warning signs:**
- Row count grows unexpectedly on incremental runs
- Generic test for unique_combination_of_columns fails after incremental run
- Same date+platform+channel has multiple rows

**Source:** [dbt docs - About incremental strategy](https://docs.getdbt.com/docs/build/incremental-strategy)

### Pitfall 2: Lookback Window Too Short for Late-Arriving Data

**What goes wrong:** Incremental model misses updates to past dates because lookback window (e.g., 1 day) is shorter than data latency.

**Why it happens:** Spend data from ad platforms can arrive 24-72 hours late. If lookback is only 1 day, late data never gets processed.

**How to avoid:**
1. Set lookback window based on known data latency (3-7 days typical for ad spend)
2. Example: `WHERE s.DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))`
3. Balance between data completeness and query performance
4. Monitor source data latency patterns to calibrate lookback

**Warning signs:**
- Totals change when running full-refresh vs incremental
- Recent dates show lower spend/installs than expected
- Discrepancies between staging models (which see all data) and incremental aggregations

**Source:** Project context (stg_supermetrics__adj_campaign uses 3-day lookback)

### Pitfall 3: Not Testing Both Full-Refresh and Incremental Runs

**What goes wrong:** Model works perfectly in full-refresh mode but fails or produces different results in incremental mode.

**Why it happens:** is_incremental() logic is only evaluated during incremental runs. Different code paths = different behavior.

**How to avoid:**
1. First run: `dbt run --select model_name --full-refresh` (establishes baseline)
2. Second run: `dbt run --select model_name` (tests incremental logic)
3. Compare row counts and sample aggregates between runs
4. Verify lookback window captures expected overlap

**Warning signs:**
- Different row counts between full-refresh and incremental
- Tests pass on full-refresh but fail on incremental
- Incremental run performance unexpectedly slow (might be scanning entire table)

**Source:** [dbt Community Forum - Testing incremental models](https://discourse.getdbt.com/t/testing-incremental-models/1528)

### Pitfall 4: Date Spine Includes Zero-Filled Rows in Cross-Layer Tests

**What goes wrong:** Cross-layer consistency test shows mismatches because mart table has date spine zero-filled rows that don't exist in intermediate tables.

**Why it happens:** mmm__daily_channel_summary uses date spine to create complete grid. Intermediate models only have rows with actual data.

**How to avoid:**
1. Filter mart table by data quality flags: `WHERE HAS_SPEND_DATA = 1 OR HAS_INSTALL_DATA = 1 OR HAS_REVENUE_DATA = 1`
2. This excludes purely zero-filled rows from comparison
3. Only compare rows that have at least one metric with real data

**Warning signs:**
- Cross-layer test shows mart has more rows than intermediate
- Mismatches occur for date+channel combinations with all zeros
- Test fails even though business logic is correct

**Source:** Project context (mmm__daily_channel_summary includes HAS_*_DATA flags specifically for this purpose)

### Pitfall 5: Network Mapping Seed Doesn't Cover All Active Partners

**What goes wrong:** Active ad partners fall through to 'Other' category in MMM models because they're not in network_mapping.csv seed.

**Why it happens:** New campaigns launch with new partner variations (e.g., "TikTok_Paid_Ads_Android") that weren't in original seed.

**How to avoid:**
1. Before deploying, query distinct PARTNER_NAME values from source tables (last 90 days)
2. Compare against network_mapping seed coverage
3. Add missing partners to seed OR update AD_PARTNER macro LIKE patterns to catch variants
4. Run analysis query (Pattern 5 above) to identify unmapped partners

**Warning signs:**
- 'Other' category has significant spend/installs in MMM outputs
- Manual inspection reveals known partners (TikTok, AppLovin) in 'Other'
- network_mapping seed row count (29 rows) seems low compared to active campaigns

**Source:** Project context (STATE.md notes "Network mapping coverage unknown")

### Pitfall 6: Division-by-Zero Errors in KPI Calculations

**What goes wrong:** CPI or ROAS calculation fails with "Division by zero" error when denominator is 0.

**Why it happens:** COALESCE(installs, 0) / installs when installs = 0. Or SPEND / 0 when filtering includes rows with no spend.

**How to avoid:**
1. Use CASE WHEN to check denominator > 0 before division
2. Return NULL (not 0) when KPI is undefined
3. Example: `CASE WHEN installs > 0 THEN spend / installs ELSE NULL END`
4. Alternative: Use dbt_utils.safe_divide macro

**Warning signs:**
- dbt run fails with "Division by zero" error
- KPI columns show 0 instead of NULL for undefined values
- Downstream analytics tools crash on infinity values

**Source:** [Medium - Division by Zero Errors in SQL](https://medium.com/@simon.harrison_Select_Distinct/divide-by-zero-errors-sql-power-bi-dax-bigquery-and-more-0880e67ed450)

## Code Examples

### Example 1: Singular Test for Zero-Fill Integrity

**Source:** Project context (HAS_*_DATA flags in mmm__daily_channel_summary)

```sql
-- tests/singular/test_mmm_zero_fill_integrity.sql
-- Validates that HAS_*_DATA flags correctly distinguish real data from COALESCE zero-fills

WITH flagged_data AS (
    SELECT
        DATE,
        PLATFORM,
        CHANNEL,
        SPEND,
        INSTALLS,
        REVENUE,
        HAS_SPEND_DATA,
        HAS_INSTALL_DATA,
        HAS_REVENUE_DATA
    FROM {{ ref('mmm__daily_channel_summary') }}
)

-- Detect incorrect flags (test fails if any violations found)
SELECT
    DATE,
    PLATFORM,
    CHANNEL,
    CASE
        WHEN SPEND > 0 AND HAS_SPEND_DATA = 0 THEN 'Spend > 0 but flag = 0'
        WHEN SPEND = 0 AND HAS_SPEND_DATA = 1 THEN 'Spend = 0 but flag = 1'
        WHEN INSTALLS > 0 AND HAS_INSTALL_DATA = 0 THEN 'Installs > 0 but flag = 0'
        WHEN INSTALLS = 0 AND HAS_INSTALL_DATA = 1 THEN 'Installs = 0 but flag = 1'
        WHEN REVENUE > 0 AND HAS_REVENUE_DATA = 0 THEN 'Revenue > 0 but flag = 0'
        WHEN REVENUE = 0 AND HAS_REVENUE_DATA = 1 THEN 'Revenue = 0 but flag = 1'
    END AS violation_type,
    SPEND,
    HAS_SPEND_DATA,
    INSTALLS,
    HAS_INSTALL_DATA,
    REVENUE,
    HAS_REVENUE_DATA
FROM flagged_data
WHERE (SPEND > 0 AND HAS_SPEND_DATA = 0)
   OR (SPEND = 0 AND HAS_SPEND_DATA = 1)
   OR (INSTALLS > 0 AND HAS_INSTALL_DATA = 0)
   OR (INSTALLS = 0 AND HAS_INSTALL_DATA = 1)
   OR (REVENUE > 0 AND HAS_REVENUE_DATA = 0)
   OR (REVENUE = 0 AND HAS_REVENUE_DATA = 1)
```

**Rationale:** HAS_*_DATA flags distinguish "real zero" (partner had no activity) from "zero-filled by date spine" (partner didn't exist yet). Critical for MMM analysis to know which zeros are meaningful.

### Example 2: Running Models in dbt Cloud

**Source:** [dbt docs - Connect Snowflake](https://docs.getdbt.com/docs/cloud/connect-data-platform/connect-snowflake)

Since local dbt is unavailable (key-pair auth issue), use dbt Cloud IDE:

1. **Compile models to check for SQL errors:**
   ```bash
   dbt compile --select int_mmm__daily_channel_spend int_mmm__daily_channel_installs int_mmm__daily_channel_revenue mmm__daily_channel_summary mmm__weekly_channel_summary
   ```

2. **Run full-refresh (initial load):**
   ```bash
   dbt run --select int_mmm__daily_channel_spend int_mmm__daily_channel_installs int_mmm__daily_channel_revenue --full-refresh
   ```

3. **Run incremental (test merge strategy):**
   ```bash
   dbt run --select int_mmm__daily_channel_spend int_mmm__daily_channel_installs int_mmm__daily_channel_revenue
   ```

4. **Run mart models (table materialization):**
   ```bash
   dbt run --select mmm__daily_channel_summary mmm__weekly_channel_summary
   ```

5. **Run all tests:**
   ```bash
   dbt test --select int_mmm__daily_channel_spend int_mmm__daily_channel_installs int_mmm__daily_channel_revenue mmm__daily_channel_summary mmm__weekly_channel_summary
   ```

### Example 3: Network Mapping Coverage Check

**Source:** Project context (network_mapping.csv seed)

```sql
-- analysis/check_network_mapping_coverage.sql
-- Run with: dbt compile --select check_network_mapping_coverage
-- Then execute compiled SQL in Snowflake to see results

WITH supermetrics_partners AS (
    SELECT DISTINCT PARTNER_NAME, 'Supermetrics' AS source
    FROM {{ ref('stg_supermetrics__adj_campaign') }}
    WHERE DATE >= DATEADD(day, -90, CURRENT_DATE)
      AND COST > 0
),

adjust_api_partners AS (
    SELECT DISTINCT PARTNER_NAME, 'Adjust API' AS source
    FROM {{ ref('stg_adjust__report_daily') }}
    WHERE DATE >= DATEADD(day, -90, CURRENT_DATE)
      AND (REVENUE > 0 OR INSTALLS > 0)
),

all_active_partners AS (
    SELECT * FROM supermetrics_partners
    UNION
    SELECT * FROM adjust_api_partners
),

seed_coverage AS (
    SELECT
        ap.PARTNER_NAME,
        ap.source,
        nm.AD_PARTNER AS mapped_to,
        CASE
            WHEN nm.AD_PARTNER IS NOT NULL THEN 'Mapped'
            ELSE 'UNMAPPED - will be Other'
        END AS coverage_status
    FROM all_active_partners ap
    LEFT JOIN {{ ref('network_mapping') }} nm
        ON ap.PARTNER_NAME = nm.SUPERMETRICS_PARTNER_NAME
        OR ap.PARTNER_NAME = nm.ADJUST_NETWORK_NAME
)

SELECT
    coverage_status,
    COUNT(*) AS partner_count,
    LISTAGG(DISTINCT PARTNER_NAME, ', ') WITHIN GROUP (ORDER BY PARTNER_NAME) AS partners
FROM seed_coverage
GROUP BY coverage_status
ORDER BY
    CASE coverage_status
        WHEN 'Mapped' THEN 1
        ELSE 2
    END,
    partner_count DESC
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual SQL scripts for incremental updates | dbt incremental materialization | dbt 0.7.0 (2017) | Declarative config replaces procedural logic |
| Separate test scripts run ad-hoc | dbt test command with singular/generic tests | dbt 0.14.0 (2019) | Tests version-controlled, automated in CI/CD |
| Schema tests | Data tests | dbt 1.5.0 (2023) | Terminology update, no behavior change |
| Manual date spine tables | dbt_utils.date_spine macro | dbt-utils 0.1.0 (2018) | Standardized pattern, handles edge cases |
| Custom division-by-zero handling | dbt_utils.safe_divide macro | dbt-utils 0.8.0 (2021) | Consistent cross-database pattern |
| dbt compile only | dbt Cloud IDE with compile + run | dbt Cloud (ongoing) | Web-based, no local environment needed |

**Deprecated/outdated:**
- **append_new_columns** on_schema_change setting: Still valid but incremental models now default to safer fail behavior
- **dbt-expectations package:** GitHub README states "no longer actively supported" (as of 2025), though still functional for existing use cases

## Open Questions

1. **What is the actual network_mapping coverage gap?**
   - What we know: Seed has 29 rows (28 partners + header). Unknown if this covers all active partners.
   - What's unclear: Whether any active partners in last 90 days are unmapped.
   - Recommendation: Run analysis query (Example 3 above) in dbt Cloud to identify gaps before building tests. Add missing partners to seed if found.

2. **Should date spine test enforce date range (2024-01-01 to current)?**
   - What we know: mmm__daily_channel_summary uses hardcoded start_date='2024-01-01' in date spine.
   - What's unclear: Whether test should validate start date boundary or just check for gaps within existing data.
   - Recommendation: Test for gaps within actual data range (don't enforce 2024-01-01 boundary). Model config owns date range, test validates completeness.

3. **What tolerance should cross-layer consistency test use?**
   - What we know: Floating-point arithmetic can cause small rounding differences in aggregations.
   - What's unclear: Acceptable tolerance for spend/revenue comparisons (0.01? 0.001? exact match?).
   - Recommendation: Start with 0.01 tolerance (1 cent) for spend/revenue, 0 for installs (integer counts). Adjust if false positives occur.

4. **Should singular tests filter to recent date range for performance?**
   - What we know: Full table scans can be slow. Generic tests use 60-day filters for performance.
   - What's unclear: Whether singular tests should filter or scan entire history for comprehensive validation.
   - Recommendation: Start with full history (no date filter) since these tests run infrequently and validate data integrity. Add date filter if performance becomes issue.

## Sources

### Primary (HIGH confidence)
- [dbt docs - About incremental strategy](https://docs.getdbt.com/docs/build/incremental-strategy) - Merge strategy, unique_key configuration
- [dbt docs - Configure incremental models](https://docs.getdbt.com/docs/build/incremental-models) - Best practices, lookback windows
- [dbt docs - Add data tests to your DAG](https://docs.getdbt.com/docs/build/data-tests) - Singular test patterns
- [dbt docs - Ratio metrics](https://docs.getdbt.com/docs/build/ratio) - Division-by-zero handling with NULLIF
- [dbt docs - Connect Snowflake](https://docs.getdbt.com/docs/cloud/connect-data-platform/connect-snowflake) - dbt Cloud authentication methods
- Project files (HIGH confidence - direct observation):
  - `/Users/riley/Documents/GitHub/wgt-dbt/models/intermediate/int_mmm__daily_channel_spend.sql` - Incremental config
  - `/Users/riley/Documents/GitHub/wgt-dbt/models/intermediate/int_mmm__daily_channel_installs.sql` - Incremental config
  - `/Users/riley/Documents/GitHub/wgt-dbt/models/intermediate/int_mmm__daily_channel_revenue.sql` - Incremental config
  - `/Users/riley/Documents/GitHub/wgt-dbt/models/marts/mmm/mmm__daily_channel_summary.sql` - Date spine, KPI calculations, data flags
  - `/Users/riley/Documents/GitHub/wgt-dbt/models/marts/mmm/mmm__weekly_channel_summary.sql` - Weekly rollup pattern
  - `/Users/riley/Documents/GitHub/wgt-dbt/seeds/network_mapping.csv` - 29 rows of partner mappings
  - `/Users/riley/Documents/GitHub/wgt-dbt/macros/map_ad_partner.sql` - AD_PARTNER macro (Phase 4)
  - `/Users/riley/Documents/GitHub/wgt-dbt/.planning/STATE.md` - Known context (MMM pipeline built, coverage unknown)

### Secondary (MEDIUM confidence)
- [dbt Community Forum - Testing incremental models](https://discourse.getdbt.com/t/testing-incremental-models/1528) - Full-refresh vs incremental testing patterns
- [Datafold Blog - 7 dbt Testing Best Practices](https://www.datafold.com/blog/7-dbt-testing-best-practices) - Industry best practices
- [Datadog Blog - Implement dbt data quality checks with dbt-expectations](https://www.datadoghq.com/blog/dbt-data-quality-testing/) - dbt-expectations usage examples
- [GitHub - dbt-labs/dbt-utils safe_divide issue](https://github.com/dbt-labs/dbt-utils/issues/679) - safe_divide macro discussion
- [Medium - Division by Zero Errors in SQL](https://medium.com/@simon.harrison_Select_Distinct/divide-by-zero-errors-sql-power-bi-dax-bigquery-and-more-0880e67ed450) - NULLIF patterns
- [Zuar Blog - Date Dimensions and Calendar Table in Snowflake](https://www.zuar.com/blog/date-dimensions-date-scaffold-date-spine-snowflake/) - Date spine patterns
- [PopSQL - How to Avoid Gaps in Data in Snowflake](https://popsql.com/learn-sql/snowflake/how-to-avoid-gaps-in-data-in-snowflake) - Cross-join technique for completeness

### Tertiary (LOW confidence - supplementary)
- [GitHub - calogica/dbt-expectations](https://github.com/calogica/dbt-expectations) - Package no longer actively supported (noted in README)
- WebSearch results for "dbt cross-model consistency tests" - Multiple sources agree on pattern but not verified in official docs

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - dbt-core and dbt-utils verified in project files (packages.yml, dbt_project.yml)
- Incremental models: HIGH - Configuration patterns verified in existing MMM intermediate models, official dbt docs confirm merge strategy behavior
- Singular tests: HIGH - Pattern verified in existing test_ad_partner_mapping_consistency.sql from Phase 4, official dbt docs confirm test structure
- Network mapping coverage: MEDIUM - Seed file exists (29 rows confirmed) but coverage gap unknown until analysis query runs in dbt Cloud
- KPI calculations: HIGH - Division-by-zero handling verified in mmm__daily_channel_summary.sql (CASE WHEN pattern used)
- Data quality flags: HIGH - HAS_*_DATA flags confirmed in mmm__daily_channel_summary.sql lines 100-102

**Research date:** 2026-02-11
**Valid until:** 2026-03-13 (30 days - dbt is stable, incremental model patterns don't change frequently)
