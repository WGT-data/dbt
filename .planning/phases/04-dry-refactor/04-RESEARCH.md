# Phase 4: DRY Refactor - Research

**Researched:** 2026-02-11
**Domain:** dbt macro patterns, code refactoring, testing verification
**Confidence:** HIGH

## Summary

Phase 4 extracts a duplicated 22-line CASE statement (AD_PARTNER mapping logic) from two staging models into a reusable macro. The CASE statement is identical in both `v_stg_adjust__installs.sql` and `v_stg_adjust__touchpoints.sql`, creating maintenance risk when network mappings change.

Research investigated dbt macro best practices, refactoring verification patterns, and testing approaches. The standard approach is to create a macro in `macros/` that returns SQL (not executes it), allowing models to call it inline. For verification, the audit_helper package provides macros to compare column values before and after refactoring, ensuring the macro produces identical outputs to the original CASE statement.

Key findings: dbt macros should prioritize readability over abstraction, use descriptive names, accept column references as arguments, and be thoroughly tested. The project already uses dbt-utils, making audit_helper a natural addition for verification.

**Primary recommendation:** Create `macros/map_ad_partner.sql` with a macro that accepts a column name and returns the CASE statement SQL. Use audit_helper's `compare_column_values` macro to verify identical output before merging changes.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Claude's Discretion (ALL implementation decisions)

All implementation decisions deferred to Claude. User indicated they're not opinionated on approach — "go with what you think works."

**Extraction approach:**
- Recommend: Macro with hardcoded CASE statement (`macros/map_ad_partner.sql`) rather than seed JOIN approach
- Rationale: The existing `network_mapping.csv` seed serves a different purpose (SuperMetrics partner mapping with IDs) and uses exact-match names, while the CASE statement uses LIKE patterns (AppLovin%, Moloco%, Smadex%, etc.) that a simple seed JOIN can't replicate. Macro keeps behavior identical with zero risk.
- Both staging models call the macro instead of inlining the CASE

**Coverage gaps:**
- Current CASE statement is missing Tapjoy (2 entries in seed) and TikTok_Paid_Ads_Android (in seed) — these currently fall to 'Other'
- Recommend: Fix coverage gaps during macro extraction since we're touching this logic anyway. Add Tapjoy and TikTok_Paid_Ads_Android to the macro.
- This is a bug fix, not scope creep — the mappings should have been there

**Unmapped network handling:**
- Keep current behavior: unmapped networks fall to 'Other'
- No need to add alerting or flagging for unknown networks in this phase

**Verification:**
- Consistency test should compare macro output to original CASE output for all distinct NETWORK_NAME values in production data
- Both models must produce identical AD_PARTNER values after refactor

### Deferred Ideas (OUT OF SCOPE)

- Switching to seed-based JOIN approach — future improvement
- Network mapping coverage audit — Phase 5 already covers this

</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dbt-core | Current | Data transformation framework | Project already uses dbt |
| dbt-utils | >=1.1.1, <2.0.0 | Generic test utilities | Already installed in project (packages.yml) |
| dbt-audit-helper | 0.12.0+ | Refactoring verification | Official dbt Labs package for comparing outputs |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Snowflake adapter | Current | Database platform | Project uses Snowflake (confirmed in profiles.yml) |

**Installation (audit_helper):**
```yaml
# Add to packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.1.1", "<2.0.0"]
  - package: dbt-labs/audit_helper
    version: 0.12.0
```

Then run:
```bash
dbt deps
```

## Architecture Patterns

### Recommended Macro Structure

```
macros/
├── generate_schema_name.sql      # Existing - environment routing
├── get_source_schema.sql         # Existing - source schema lookup
├── setup_dev_views.sql           # Existing - dev setup
└── map_ad_partner.sql            # NEW - AD_PARTNER mapping logic
```

### Pattern 1: SQL-Returning Macro for Column Transformation

**What:** Macro that accepts a column name and returns SQL text (CASE statement) to be compiled into the model query.

**When to use:** When identical SQL logic appears in multiple models and the logic transforms a single column value.

**Example:**
```sql
{%- macro map_ad_partner(column_name) -%}
    {#
        Maps NETWORK_NAME to standardized AD_PARTNER taxonomy.

        Args:
            column_name: The column containing network names to map

        Returns:
            SQL CASE statement that can be used in SELECT

        Example:
            SELECT {{ map_ad_partner('NETWORK_NAME') }} AS AD_PARTNER
    #}
    CASE
        WHEN {{ column_name }} IN ('Facebook Installs', 'Instagram Installs', 'Off-Facebook Installs', 'Facebook Messenger Installs') THEN 'Meta'
        WHEN {{ column_name }} IN ('Google Ads ACE', 'Google Ads ACI', 'Google Organic Search', 'google') THEN 'Google'
        WHEN {{ column_name }} IN ('TikTok SAN', 'TikTok_Paid_Ads_iOS', 'TikTok_Paid_Ads_Android', 'Tiktok Installs') THEN 'TikTok'
        WHEN {{ column_name }} = 'Apple Search Ads' THEN 'Apple'
        WHEN {{ column_name }} LIKE 'AppLovin%' THEN 'AppLovin'
        WHEN {{ column_name }} LIKE 'UnityAds%' THEN 'Unity'
        WHEN {{ column_name }} LIKE 'Moloco%' THEN 'Moloco'
        WHEN {{ column_name }} LIKE 'Smadex%' THEN 'Smadex'
        WHEN {{ column_name }} LIKE 'AdAction%' THEN 'AdAction'
        WHEN {{ column_name }} LIKE 'Vungle%' THEN 'Vungle'
        WHEN {{ column_name }} LIKE 'Tapjoy%' THEN 'Tapjoy'
        WHEN {{ column_name }} = 'Organic' THEN 'Organic'
        WHEN {{ column_name }} = 'Unattributed' THEN 'Unattributed'
        WHEN {{ column_name }} = 'Untrusted Devices' THEN 'Untrusted'
        WHEN {{ column_name }} IN ('wgtgolf', 'WGT_Events_SocialPosts_iOS', 'WGT_GiftCards_Social') THEN 'WGT'
        WHEN {{ column_name }} LIKE 'Phigolf%' THEN 'Phigolf'
        WHEN {{ column_name }} LIKE 'Ryder%' THEN 'Ryder Cup'
        ELSE 'Other'
    END
{%- endmacro -%}
```

**Usage in models:**
```sql
SELECT DEVICE_ID
     , PLATFORM
     , NETWORK_NAME
     , {{ map_ad_partner('NETWORK_NAME') }} AS AD_PARTNER
     , CAMPAIGN_NAME
FROM source_data
```

### Pattern 2: Refactoring Verification with audit_helper

**What:** Use audit_helper macros to compare model outputs before and after refactoring.

**When to use:** Before merging any refactoring that changes model SQL, especially when extracting logic into macros.

**Example workflow:**

1. **Before refactoring:** Note current state
   ```bash
   dbt run --select v_stg_adjust__installs v_stg_adjust__touchpoints
   ```

2. **Create comparison query:** Use audit_helper to compare old vs new
   ```sql
   -- analysis/verify_ad_partner_refactor.sql
   {{
       audit_helper.compare_column_values(
           a_query="select * from " ~ ref('v_stg_adjust__installs'),
           b_query="select * from dev_schema.v_stg_adjust__installs_refactored",
           primary_key="DEVICE_ID",
           column_to_compare="AD_PARTNER"
       )
   }}
   ```

3. **Run verification:**
   ```bash
   dbt compile --select verify_ad_partner_refactor
   # Then execute compiled SQL in Snowflake to see comparison results
   ```

4. **Check results:** Should show 100% match rate (in_both_correct column)

### Pattern 3: Custom Generic Test for Macro Consistency

**What:** Generic test that compares macro output to expected values for known inputs.

**When to use:** As ongoing regression testing after refactor is verified.

**Example:**
```sql
-- tests/generic/test_ad_partner_mapping.sql
{% test ad_partner_mapping_complete(model, column_name) %}
    -- Verify that known network names map to expected AD_PARTNER values
    WITH test_cases AS (
        SELECT 'Facebook Installs' AS network, 'Meta' AS expected_partner
        UNION ALL SELECT 'Google Ads ACE', 'Google'
        UNION ALL SELECT 'TikTok SAN', 'TikTok'
        UNION ALL SELECT 'Apple Search Ads', 'Apple'
        UNION ALL SELECT 'AppLovin_iOS_2019', 'AppLovin'
        UNION ALL SELECT 'Tapjoy', 'Tapjoy'
        -- Add more test cases as needed
    ),
    actual_mapping AS (
        SELECT
            network,
            {{ map_ad_partner('network') }} AS actual_partner
        FROM test_cases
    )
    SELECT
        t.network,
        t.expected_partner,
        a.actual_partner
    FROM test_cases t
    LEFT JOIN actual_mapping a ON t.network = a.network
    WHERE t.expected_partner != a.actual_partner
{% endtest %}
```

### Anti-Patterns to Avoid

- **Over-abstraction:** Don't create macros with complex conditional logic or multiple responsibilities. Keep macros focused on single transformations.
- **Macro without documentation:** Every macro should have a header comment explaining purpose, arguments, return value, and example usage.
- **Skipping verification:** Never refactor SQL without comparing output. Small typos in macros can silently break logic.
- **String arguments without quotes:** When calling macros, always quote column names: `{{ map_ad_partner('NETWORK_NAME') }}` not `{{ map_ad_partner(NETWORK_NAME) }}`

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Comparing model outputs during refactoring | Custom SQL diff queries | audit_helper package macros | Handles edge cases (nulls, type mismatches), provides statistical summaries, battle-tested by community |
| Column value verification tests | Manual WHERE clause tests | audit_helper.compare_column_values | Provides percentage match rates, identifies specific mismatches, includes helpful emojis for quick scanning |
| Testing macro logic in isolation | Python test scripts | dbt compile + SQL execution | Macros compile to SQL, easier to verify SQL output directly than test generation logic |
| Network name normalization | Multiple macros or CASE variants | Single macro with LIKE patterns | LIKE patterns handle naming variations (AppLovin_iOS_2019, AppLovin_Android_2019) without explicit enumeration |

**Key insight:** dbt's strength is SQL generation, not runtime execution. Macros should return SQL text that compiles into queries, not attempt procedural logic.

## Common Pitfalls

### Pitfall 1: Macro Argument Quoting Errors

**What goes wrong:** Calling `{{ map_ad_partner(NETWORK_NAME) }}` without quotes compiles to empty string if NETWORK_NAME isn't a Jinja variable, breaking the CASE statement.

**Why it happens:** Jinja treats unquoted text as variable references. Without quotes, `NETWORK_NAME` looks for a Jinja variable (not a SQL column).

**How to avoid:** Always quote column name arguments: `{{ map_ad_partner('NETWORK_NAME') }}`

**Warning signs:**
- dbt compiles successfully but SQL is malformed
- Error like "syntax error at or near ')'" in compiled SQL
- CASE statement appears in compiled SQL with empty condition: `CASE WHEN IN (...)`

### Pitfall 2: Forgetting to Add Missing Mappings

**What goes wrong:** Creating macro from existing CASE statement without checking for coverage gaps perpetuates existing bugs.

**Why it happens:** Easy to copy-paste existing logic without cross-referencing it against seed data or production values.

**How to avoid:**
1. Query distinct NETWORK_NAME values from production
2. Compare against CASE statement conditions
3. Check network_mapping.csv seed for additional partners
4. Add any missing mappings before deploying macro

**Warning signs:**
- network_mapping.csv contains networks not in CASE statement
- Production data shows 'Other' for networks that should have specific partners
- Seed row count doesn't match CASE condition count

### Pitfall 3: Assuming audit_helper Works on All Adapters

**What goes wrong:** Using `quick_are_queries_identical` macro on unsupported adapter causes runtime error.

**Why it happens:** Hashing functions differ across databases; audit_helper only supports Snowflake and BigQuery for quick comparisons.

**How to avoid:**
- For Snowflake/BigQuery: Use `quick_are_queries_identical` for fast verification
- For other adapters: Use `compare_column_values` or `compare_all_columns` (slower but adapter-agnostic)

**Warning signs:**
- Error about unsupported hash function
- Macro compilation fails with database-specific error

**Note for this project:** Uses Snowflake adapter (confirmed), so `quick_are_queries_identical` is supported.

### Pitfall 4: Not Testing Incremental Model Behavior After Refactor

**What goes wrong:** Macro works in full-refresh mode but breaks incremental builds due to timing of when macro is evaluated.

**Why it happens:** `v_stg_adjust__touchpoints` is incremental (materialized='incremental'). Macros evaluate at compile time, but incremental logic needs runtime context.

**How to avoid:**
- Test refactored model with both full-refresh and incremental runs
- Verify incremental filter logic (`{% if is_incremental() %}`) still works correctly
- Run `dbt run --select v_stg_adjust__touchpoints` (incremental) after verifying full-refresh

**Warning signs:**
- Full-refresh succeeds but incremental run fails
- Incremental run produces different row counts than expected
- Max timestamp logic breaks after refactor

### Pitfall 5: Whitespace Causing SQL Formatting Issues

**What goes wrong:** Extra spaces or newlines from macro output make compiled SQL hard to read or cause formatting inconsistencies.

**Why it happens:** Default Jinja syntax `{% ... %}` preserves whitespace. Without minus signs, macros add blank lines.

**How to avoid:** Use `{%- ... -%}` syntax to strip whitespace:
```sql
{%- macro map_ad_partner(column_name) -%}
    CASE
        ...
    END
{%- endmacro -%}
```

**Warning signs:**
- Compiled SQL has excessive blank lines
- Indentation looks inconsistent in dbt logs
- SQL formatting tools complain about whitespace

## Code Examples

### Example 1: Basic Macro Definition

**Source:** dbt official docs - Jinja and macros

```sql
{%- macro map_ad_partner(column_name) -%}
    CASE
        WHEN {{ column_name }} IN ('Facebook Installs', 'Instagram Installs') THEN 'Meta'
        WHEN {{ column_name }} LIKE 'AppLovin%' THEN 'AppLovin'
        ELSE 'Other'
    END
{%- endmacro -%}
```

### Example 2: Using Macro in Model

**Source:** Project context (v_stg_adjust__installs.sql)

**Before (duplicated CASE statement):**
```sql
SELECT DEVICE_ID
     , PLATFORM
     , NETWORK_NAME
     , CASE
           WHEN NETWORK_NAME IN ('Facebook Installs', 'Instagram Installs', 'Off-Facebook Installs', 'Facebook Messenger Installs') THEN 'Meta'
           WHEN NETWORK_NAME IN ('Google Ads ACE', 'Google Ads ACI', 'Google Organic Search', 'google') THEN 'Google'
           -- ... 15 more conditions ...
           ELSE 'Other'
       END AS AD_PARTNER
     , CAMPAIGN_NAME
FROM source_data
```

**After (macro call):**
```sql
SELECT DEVICE_ID
     , PLATFORM
     , NETWORK_NAME
     , {{ map_ad_partner('NETWORK_NAME') }} AS AD_PARTNER
     , CAMPAIGN_NAME
FROM source_data
```

### Example 3: Verification Query with audit_helper

**Source:** dbt-audit-helper GitHub documentation

```sql
-- Save as analysis/verify_installs_refactor.sql
{%- set old_query -%}
    SELECT
        DEVICE_ID,
        CASE
            WHEN NETWORK_NAME IN ('Facebook Installs', 'Instagram Installs', 'Off-Facebook Installs', 'Facebook Messenger Installs') THEN 'Meta'
            WHEN NETWORK_NAME IN ('Google Ads ACE', 'Google Ads ACI', 'Google Organic Search', 'google') THEN 'Google'
            -- ... full original CASE statement ...
            ELSE 'Other'
        END AS AD_PARTNER
    FROM {{ ref('v_stg_adjust__installs') }}
    WHERE INSTALL_TIMESTAMP >= DATEADD(day, -7, CURRENT_DATE)
{%- endset -%}

{%- set new_query -%}
    SELECT
        DEVICE_ID,
        {{ map_ad_partner('NETWORK_NAME') }} AS AD_PARTNER
    FROM {{ ref('v_stg_adjust__installs') }}
    WHERE INSTALL_TIMESTAMP >= DATEADD(day, -7, CURRENT_DATE)
{%- endset -%}

{{
    audit_helper.compare_column_values(
        a_query=old_query,
        b_query=new_query,
        primary_key="DEVICE_ID",
        column_to_compare="AD_PARTNER"
    )
}}
```

**Run with:**
```bash
dbt compile --select verify_installs_refactor
# Copy compiled SQL from target/compiled/... and run in Snowflake
```

**Expected output:** Summary table showing 100% in "in_both_correct" column.

### Example 4: Custom Generic Test

**Source:** dbt best practices - writing custom generic tests

```sql
-- tests/generic/test_macro_consistency.sql
{% test macro_matches_case_statement(model, column_name) %}
    {#
        Verifies macro output matches expected hardcoded values.
        Fails if any network produces unexpected AD_PARTNER.
    #}
    WITH known_mappings AS (
        SELECT 'Facebook Installs' AS network, 'Meta' AS expected
        UNION ALL SELECT 'Google Ads ACE', 'Google'
        UNION ALL SELECT 'TikTok SAN', 'TikTok'
        UNION ALL SELECT 'Tapjoy', 'Tapjoy'
    ),
    actual_output AS (
        SELECT
            network,
            {{ map_ad_partner('network') }} AS actual
        FROM known_mappings
    )
    SELECT *
    FROM known_mappings k
    JOIN actual_output a ON k.network = a.network
    WHERE k.expected != a.actual
{% endtest %}
```

**Apply in schema YAML:**
```yaml
# models/staging/adjust/_adjust__models.yml
models:
  - name: v_stg_adjust__installs
    data_tests:
      - macro_matches_case_statement:
          column_name: NETWORK_NAME
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Inline CASE statements duplicated across models | Macros for reusable SQL generation | dbt 0.14.0 (2019) introduced improved macro support | Reduces duplication, centralizes business logic |
| Manual SQL comparison for refactoring | audit_helper package | Released 2020 by dbt Labs | Automated verification, statistical summaries |
| Schema-only tests | Unit tests for models/macros | dbt 1.8.0 (2024) introduced unit testing | Can test transformation logic with mock inputs |
| Generic tests defined anywhere | tests/generic/ directory convention | dbt 1.5.0 (2023) standardized location | Clearer project organization |

**Deprecated/outdated:**
- **schema tests** renamed to **data tests** in dbt 1.5+ (documentation now uses "data tests")
- **test blocks without the `test_` prefix** - Generic tests should use `test_` prefix in macro name (enforced in dbt 1.0+)

## Open Questions

1. **Should we add all seed networks to macro or only LIKE-pattern-compatible ones?**
   - What we know: network_mapping.csv has 28 rows; CASE statement has ~15 conditions using LIKE patterns and IN lists
   - What's unclear: Whether to add exact matches for every seed row or keep LIKE patterns to catch variants
   - Recommendation: Use LIKE patterns where variants exist (AppLovin%, Moloco%), add specific IN entries for exact matches (Tapjoy, TikTok_Paid_Ads_Android). This balances coverage and future-proofing.

2. **How to handle new networks that appear in production after macro is deployed?**
   - What we know: Current CASE has ELSE 'Other' as fallback
   - What's unclear: Whether 'Other' mappings should trigger alerts or just log quietly
   - Recommendation: Keep ELSE 'Other' behavior (no alerts this phase). Phase 5 covers network mapping audit which can identify 'Other' values for review.

3. **Should verification query run against all historical data or recent window?**
   - What we know: audit_helper can compare any query, but full table scans are slow
   - What's unclear: Minimum data window that gives confidence without performance hit
   - Recommendation: Use 7-day window (DATEADD(day, -7, CURRENT_DATE)) for verification. Covers recent data patterns without scanning full history. Can expand if discrepancies found.

## Sources

### Primary (HIGH confidence)
- [dbt Docs: Jinja and macros](https://docs.getdbt.com/docs/build/jinja-macros) - Macro syntax, argument passing, best practices
- [dbt Docs: Writing custom generic tests](https://docs.getdbt.com/best-practices/writing-custom-generic-tests) - Generic test patterns
- [dbt Docs: Data tests](https://docs.getdbt.com/docs/build/data-tests) - Built-in and custom test approaches
- [dbt-audit-helper GitHub](https://github.com/dbt-labs/dbt-audit-helper) - Refactoring verification macros, installation, usage
- [dbt Docs: Best practices - structure overview](https://docs.getdbt.com/best-practices/how-we-structure/1-guide-overview) - DRY principles, macro organization
- Project files (HIGH confidence - direct observation):
  - `/Users/riley/Documents/GitHub/wgt-dbt/models/staging/adjust/v_stg_adjust__installs.sql` - Current CASE statement
  - `/Users/riley/Documents/GitHub/wgt-dbt/models/staging/adjust/v_stg_adjust__touchpoints.sql` - Duplicated CASE statement
  - `/Users/riley/Documents/GitHub/wgt-dbt/macros/generate_schema_name.sql` - Existing macro conventions
  - `/Users/riley/Documents/GitHub/wgt-dbt/packages.yml` - dbt-utils already installed
  - `/Users/riley/Documents/GitHub/wgt-dbt/models/staging/adjust/_adjust__models.yml` - Existing test patterns

### Secondary (MEDIUM confidence)
- [dbt Community: How do we pass column values into dbt macros](https://discourse.getdbt.com/t/how-do-we-pass-column-values-into-dbt-macros/9782) - Community patterns
- [dbt Blog: audit_helper for migration](https://docs.getdbt.com/blog/audit-helper-for-migration) - Real-world refactoring case study
- [Datafold: 7 dbt Testing Best Practices](https://www.datafold.com/blog/7-dbt-testing-best-practices) - Industry best practices for verification

### Tertiary (LOW confidence - supplementary)
- [Medium: 7 dbt Macros That Actually Made Our Platform Maintainable](https://medium.com/tech-with-abhishek/7-dbt-macros-that-actually-made-our-platform-maintainable-02d3e7756860) - Blocked (403 error)
- WebSearch results for "dbt macro reusable CASE statement" - Multiple sources agree on abstraction recommendation but not verified with official docs

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - dbt-core and dbt-utils already in use (verified in project files), audit_helper is official dbt Labs package
- Architecture patterns: HIGH - Macro syntax verified via official docs, project conventions observed in existing macros, audit_helper usage documented in official GitHub
- Pitfalls: MEDIUM - Based on dbt docs best practices and community patterns, not all pitfalls verified in project-specific context
- Coverage gaps (Tapjoy/TikTok): HIGH - Confirmed by comparing CASE statement to network_mapping.csv seed
- Incremental model impact: MEDIUM - `v_stg_adjust__touchpoints` confirmed as incremental model, but macro impact on incremental logic needs testing

**Research date:** 2026-02-11
**Valid until:** 2026-03-13 (30 days - dbt is stable, macro patterns don't change frequently)
