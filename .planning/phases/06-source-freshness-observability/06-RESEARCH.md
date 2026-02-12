# Phase 6: Source Freshness & Observability - Research

**Researched:** 2026-02-12
**Domain:** dbt source freshness monitoring and Snowflake metadata-based observability
**Confidence:** HIGH

## Summary

Source freshness in dbt validates whether data sources meet defined SLAs by checking the age of the most recent record against configured thresholds. For this phase, we need to configure freshness for Adjust S3 sources (with epoch CREATED_AT timestamps), Amplitude data share tables (leveraging Snowflake metadata), and implement custom monitoring for static table staleness using INFORMATION_SCHEMA.

The standard approach uses dbt's built-in `freshness` configuration in source YAML files with `warn_after` and `error_after` thresholds. The `dbt source freshness` command runs independently from model builds and outputs results to `target/sources.json`. In dbt Cloud, freshness checks are scheduled as separate jobs that run at double the frequency of the lowest SLA.

For the static mapping table staleness detection, we'll use a custom singular test that queries `INFORMATION_SCHEMA.TABLES.LAST_ALTERED` to detect when `ADJUST_AMPLITUDE_DEVICE_MAPPING` hasn't been updated in >30 days.

**Primary recommendation:** Configure source freshness using `loaded_at_field` expressions with TO_TIMESTAMP for Adjust sources and omit `loaded_at_field` for Amplitude (leveraging Snowflake metadata). Create custom singular test for static table monitoring. Schedule dedicated freshness job in dbt Cloud separate from model builds.

## Standard Stack

The established tools for source freshness monitoring:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dbt-core | 1.7+ | Source freshness feature | Native support, warehouse metadata fallback |
| dbt-snowflake | latest | Snowflake adapter | LAST_ALTERED metadata support |
| dbt-utils | 1.1.1+ | Testing utilities | Already in project, optional helper |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| dbt Cloud | N/A | Job scheduling | Separate freshness job execution |
| Snowflake INFORMATION_SCHEMA | Native | Table metadata | Static table monitoring |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dbt source freshness | Elementary Data | More features (ML anomaly detection) but external dependency |
| Custom INFORMATION_SCHEMA test | dbt-utils.recency | recency checks downstream models not source metadata |
| Separate freshness job | Checkbox in build job | Can't control frequency independently |

**Installation:**
```bash
# Already installed in project
# dbt-utils version: [">=1.1.1", "<2.0.0"]
```

## Architecture Patterns

### Recommended Project Structure
```
models/
├── staging/
│   ├── adjust/
│   │   └── _adjust__sources.yml        # Add freshness config here
│   └── amplitude/
│       └── _amplitude__sources.yml     # Add freshness config here
tests/
└── singular/
    └── test_static_table_staleness.sql # Custom INFORMATION_SCHEMA test
```

### Pattern 1: Source Freshness Configuration for Epoch Timestamps
**What:** Configure freshness using TO_TIMESTAMP expression to convert epoch timestamps to Snowflake TIMESTAMP_NTZ.
**When to use:** When source tables have epoch timestamps (seconds since 1970-01-01) as the most recent indicator.
**Example:**
```yaml
# Source: https://docs.getdbt.com/reference/resource-properties/freshness
version: 2

sources:
  - name: adjust
    database: ADJUST
    schema: S3_DATA
    freshness:
      warn_after: {count: 12, period: hour}
      error_after: {count: 24, period: hour}
    loaded_at_field: "TO_TIMESTAMP(CREATED_AT)"  # Converts epoch to timestamp
    tables:
      - name: IOS_ACTIVITY_INSTALL
      - name: IOS_ACTIVITY_SESSION
      - name: ANDROID_ACTIVITY_INSTALL
      # ... other tables inherit source-level freshness config
```

**Technical details:**
- Snowflake TO_TIMESTAMP automatically detects epoch scale (seconds if <31,536,000,000, milliseconds if larger)
- TO_TIMESTAMP defaults to TIMESTAMP_NTZ (no timezone) which is correct for freshness comparisons
- dbt converts result to UTC and compares against warn_after/error_after intervals
- Source-level config cascades to all tables unless overridden at table level

### Pattern 2: Source Freshness Without loaded_at_field (Metadata-Based)
**What:** Leverage Snowflake's LAST_ALTERED metadata for freshness calculation when no timestamp column exists.
**When to use:** Data share tables, external tables, or sources without explicit timestamp columns (dbt 1.7+).
**Example:**
```yaml
# Source: https://docs.getdbt.com/reference/resource-properties/freshness
version: 2

sources:
  - name: amplitude
    database: AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE
    schema: SCHEMA_726530
    freshness:
      warn_after: {count: 6, period: hour}
      error_after: {count: 12, period: hour}
    # No loaded_at_field specified - dbt uses INFORMATION_SCHEMA.TABLES.LAST_ALTERED
    tables:
      - name: EVENTS_726530
      - name: MERGE_IDS_726530
```

**Important caveats:**
- LAST_ALTERED tracks both DML and DDL operations (any table modification)
- For data share tables, this indicates when the share provider last modified the table
- If data share updates are infrequent by design, set more generous thresholds
- dbt 1.7+ automatically falls back to warehouse metadata when loaded_at_field is omitted

### Pattern 3: Custom Singular Test for Static Table Staleness
**What:** Query INFORMATION_SCHEMA.TABLES to detect when a static table hasn't been refreshed within expected timeframe.
**When to use:** Monitoring seed tables, static mappings, or manually maintained tables.
**Example:**
```sql
-- Source: https://docs.snowflake.com/en/sql-reference/info-schema/tables
-- tests/singular/test_static_table_staleness.sql
-- Test fails (returns rows) when mapping table is stale
SELECT
    TABLE_NAME,
    LAST_ALTERED,
    DATEDIFF('day', LAST_ALTERED, CURRENT_TIMESTAMP()) AS days_since_update
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'SCHEMA_NAME'
  AND TABLE_NAME = 'ADJUST_AMPLITUDE_DEVICE_MAPPING'
  AND DATEDIFF('day', LAST_ALTERED, CURRENT_TIMESTAMP()) > 30
```

**Key fields:**
- `LAST_ALTERED`: Tracks DML and DDL operations (data inserts/updates and schema changes)
- `LAST_DDL`: Tracks only DDL operations (CREATE, ALTER, DROP, UNDROP) - use if you only care about structure changes
- `ROW_COUNT`: Approximate row count, useful for detecting empty tables

### Pattern 4: Freshness Job Scheduling in dbt Cloud
**What:** Run `dbt source freshness` as a dedicated scheduled job separate from model builds.
**When to use:** Always - freshness monitoring should not block or delay model execution.
**Example:**
```yaml
# dbt Cloud Job Configuration (via UI)
Job Name: "Source Freshness Monitoring"
Commands: dbt source freshness
Schedule: Every 6 hours (cron: 0 */6 * * *)  # 2x frequency of 12-hour warn threshold
Environment: Production
Execution Settings:
  - Generate docs on run: No
  - Run on source freshness failure: N/A (single command)

Notification:
  - Email on failure: Yes
  - Slack webhook: Optional
```

**Scheduling best practices:**
- Run at least 2x frequency of lowest SLA (e.g., every 6 hours for 12-hour warn_after)
- Schedule outside peak hours if possible to minimize warehouse resource contention
- Separate from model build jobs - freshness failures shouldn't block transformations
- Results are stored in `target/sources.json` for programmatic access

### Anti-Patterns to Avoid
- **Running freshness in build jobs with "Run source freshness" checkbox:** Can't control frequency independently, couples monitoring with transformations
- **Using `loaded_at_field` on data share tables when timestamp column doesn't exist:** Will fail; omit field and let dbt use metadata
- **Setting unrealistic SLAs:** Align warn_after/error_after with actual data pipeline latency, not ideal state
- **Alert fatigue from too-strict thresholds:** Start conservative, tighten thresholds based on observed behavior
- **Using dbt-utils.recency test for source freshness:** recency tests downstream models, not source tables; use dbt source freshness instead
- **Forgetting timezone conversion:** TO_TIMESTAMP returns local timezone by default; dbt converts to UTC for comparisons, but explicit UTC is clearer

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Source data latency monitoring | Custom SQL queries checking MAX(timestamp) | dbt source freshness | Standardized config, dbt Cloud integration, JSON output, threshold logic handled |
| Scheduling freshness checks | Cron job running dbt source freshness | dbt Cloud job scheduler | Native UI, notification hooks, execution history, failure handling |
| Alert notification | Custom email/Slack scripts | dbt Cloud notifications | Built-in on job failure, no custom code to maintain |
| Freshness result parsing | Custom JSON parsers for target/sources.json | dbt Cloud UI or dbt artifacts | Pre-built dashboards, no custom parsing logic |
| Timezone handling for timestamps | Manual timezone conversion logic | dbt's automatic UTC conversion | Handles all timestamp types, tested edge cases |

**Key insight:** dbt source freshness is a mature, well-tested feature with deep dbt Cloud integration. Custom solutions miss built-in threshold logic, metadata fallback (dbt 1.7+), and scheduling/notification infrastructure. The value is in configuration, not implementation.

## Common Pitfalls

### Pitfall 1: Epoch Timestamp Scale Confusion
**What goes wrong:** TO_TIMESTAMP interprets epoch values incorrectly if scale isn't what Snowflake expects, causing freshness to always fail or pass incorrectly.
**Why it happens:** Snowflake auto-detects scale based on magnitude (<31.5B = seconds, >31.5B = milliseconds), but edge cases exist. Source systems may use microseconds or nanoseconds.
**How to avoid:**
- Test with `SELECT TO_TIMESTAMP(CREATED_AT) FROM source_table LIMIT 1` to verify conversion
- If scale is wrong, explicitly specify: `TO_TIMESTAMP(CREATED_AT, 0)` for seconds, `TO_TIMESTAMP(CREATED_AT, 3)` for milliseconds
- For this project, Adjust CREATED_AT is epoch seconds (confirmed in success criteria)
**Warning signs:** Freshness always fails with "max loaded_at" showing dates in 1970 or far future (2058+)

### Pitfall 2: Data Share Tables Don't Have Timestamp Columns
**What goes wrong:** Configuring `loaded_at_field` on data share tables when the column doesn't exist causes `dbt source freshness` to fail with "column not found" error.
**Why it happens:** Amplitude data share tables often lack ETL metadata columns like `_loaded_at` or `_synced_at`. You can't add columns to shared data.
**How to avoid:**
- For Snowflake/Redshift/BigQuery/Databricks (dbt 1.7+): Omit `loaded_at_field` entirely and let dbt use LAST_ALTERED metadata
- Verify column existence before adding to config: `SHOW COLUMNS IN <database>.<schema>.<table>;`
- If LAST_ALTERED granularity is too coarse (e.g., only updated on schema changes), consider if freshness monitoring is appropriate for this source
**Warning signs:** `dbt source freshness` errors with SQL compilation error referencing non-existent column

### Pitfall 3: LAST_ALTERED Includes DDL Operations
**What goes wrong:** Freshness passes even though data is stale because a schema change (ADD COLUMN, ALTER) updated LAST_ALTERED.
**Why it happens:** LAST_ALTERED tracks "last altered by DML, DDL, or background metadata operation" - not just data inserts/updates.
**How to avoid:**
- Understand this limitation when using metadata-based freshness (no loaded_at_field)
- For static table monitoring, use LAST_DDL if you only care about manual schema changes, or LAST_ALTERED if you want any modification
- Cross-reference with ROW_COUNT changes if you need to distinguish data updates from schema changes
- Document this behavior for future maintainers
**Warning signs:** Freshness passes but users report stale data; INFORMATION_SCHEMA shows LAST_ALTERED = recent but data timestamps are old

### Pitfall 4: Freshness Thresholds Don't Match Data Pipeline Reality
**What goes wrong:** Too-strict thresholds cause constant alerts (alert fatigue); too-loose thresholds miss real SLA violations.
**Why it happens:** Setting thresholds based on desired state ("data should be real-time") rather than actual pipeline latency.
**How to avoid:**
- Start by profiling current data latency: `SELECT MAX(loaded_at_field), CURRENT_TIMESTAMP(), DATEDIFF('hour', MAX(loaded_at_field), CURRENT_TIMESTAMP()) FROM source`
- Set warn_after at 90th percentile latency, error_after at 99th percentile
- For Adjust S3 data: typically 2-6 hour latency depending on event type
- For Amplitude data share: depends on share refresh schedule (check with Amplitude support)
- Adjust thresholds iteratively based on observed failure rates
**Warning signs:** Constant freshness failures/warnings, or failures that don't correlate with user-reported data issues

### Pitfall 5: Forgetting to Schedule Freshness Job in dbt Cloud
**What goes wrong:** Source freshness config is perfect but never runs, so SLA violations go undetected.
**Why it happens:** Assuming "Run source freshness" checkbox in build job is sufficient, or forgetting to create dedicated job.
**How to avoid:**
- Create separate dbt Cloud job with command: `dbt source freshness`
- Schedule at 2x frequency of lowest SLA (e.g., every 6 hours for 12-hour warn_after)
- Enable notifications (email, Slack) on job failure
- Test job manually before relying on schedule
- Document job existence and purpose in project README or internal docs
**Warning signs:** No freshness results in dbt Cloud runs, no alerts despite known pipeline issues

### Pitfall 6: Source-Level Config Applied to Wrong Tables
**What goes wrong:** Freshness config at source level cascades to all tables, causing failures for tables that shouldn't be monitored or have different SLAs.
**Why it happens:** Convenience of source-level config without considering table-specific needs.
**How to avoid:**
- Use source-level config only when all tables have same loaded_at_field and SLAs
- Override at table level for exceptions: set `freshness: null` to exclude specific tables
- For heterogeneous sources (mix of real-time and batch), configure at table level
- Example:
```yaml
sources:
  - name: adjust
    freshness:  # Default for all tables
      warn_after: {count: 12, period: hour}
    loaded_at_field: "TO_TIMESTAMP(CREATED_AT)"
    tables:
      - name: IOS_ACTIVITY_INSTALL
      - name: DAILY_AGGREGATES
        freshness:  # Override for batch table
          warn_after: {count: 30, period: hour}
```
**Warning signs:** Unexpected freshness failures on tables you don't care about, or missing freshness for tables you do care about

## Code Examples

Verified patterns from official sources:

### Adjust Source Configuration (Epoch Timestamps)
```yaml
# Source: https://docs.getdbt.com/reference/resource-properties/freshness
# models/staging/adjust/_adjust__sources.yml

version: 2

sources:
  - name: adjust
    description: Adjust mobile attribution data
    database: ADJUST
    schema: S3_DATA
    freshness:
      warn_after: {count: 12, period: hour}
      error_after: {count: 24, period: hour}
    loaded_at_field: "TO_TIMESTAMP(CREATED_AT)"
    tables:
      - name: IOS_ACTIVITY_INSTALL
        description: iOS install events with attribution data
      - name: IOS_ACTIVITY_SESSION
        description: iOS session events
      - name: IOS_ACTIVITY_EVENT
        description: iOS in-app events
      - name: ANDROID_ACTIVITY_INSTALL
        description: Android install events with attribution data
      - name: ANDROID_ACTIVITY_SESSION
        description: Android session events
      - name: ANDROID_ACTIVITY_EVENT
        description: Android in-app events
```

### Amplitude Source Configuration (Metadata-Based)
```yaml
# Source: https://docs.getdbt.com/reference/resource-properties/freshness
# models/staging/amplitude/_amplitude__sources.yml

version: 2

sources:
  - name: amplitude
    description: Amplitude product analytics data
    database: AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE
    schema: SCHEMA_726530
    freshness:
      warn_after: {count: 6, period: hour}
      error_after: {count: 12, period: hour}
    # No loaded_at_field - leverages Snowflake LAST_ALTERED metadata
    tables:
      - name: MERGE_IDS_726530
        description: Device ID to User ID mapping
      - name: EVENTS_726530
        description: All product events
```

### Static Table Staleness Test
```sql
-- Source: https://docs.snowflake.com/en/sql-reference/info-schema/tables
-- tests/singular/test_adjust_amplitude_mapping_staleness.sql

-- Test fails (returns rows) when static mapping table hasn't been updated in >30 days
-- Success criteria: ADJUST_AMPLITUDE_DEVICE_MAPPING refreshed within 30 days

SELECT
    TABLE_NAME,
    LAST_ALTERED,
    DATEDIFF('day', LAST_ALTERED, CURRENT_TIMESTAMP()) AS days_since_update,
    ROW_COUNT,
    'Static mapping table is stale - last updated ' || days_since_update || ' days ago' AS failure_message
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'PUBLIC'  -- Replace with actual schema
  AND TABLE_NAME = 'ADJUST_AMPLITUDE_DEVICE_MAPPING'
  AND DATEDIFF('day', LAST_ALTERED, CURRENT_TIMESTAMP()) > 30
```

### Running Freshness Locally
```bash
# Source: https://docs.getdbt.com/reference/commands/source

# Check all sources
dbt source freshness

# Check specific source
dbt source freshness --select "source:adjust"

# Output to custom location
dbt source freshness --output target/source_freshness.json

# Results structure in target/sources.json:
# {
#   "metadata": { "generated_at": "2026-02-12T10:30:00Z" },
#   "results": {
#     "source.wgt_dbt.adjust.IOS_ACTIVITY_INSTALL": {
#       "max_loaded_at": "2026-02-12T08:15:00Z",
#       "snapshotted_at": "2026-02-12T10:30:00Z",
#       "max_loaded_at_time_ago_in_s": 8100,
#       "status": "pass",  # or "warn" or "error"
#       "criteria": { "warn_after": { "count": 12, "period": "hour" } }
#     }
#   }
# }
```

### Testing TO_TIMESTAMP Conversion
```sql
-- Verify epoch timestamp conversion before adding to freshness config
SELECT
    CREATED_AT,
    TO_TIMESTAMP(CREATED_AT) AS converted_timestamp,
    CURRENT_TIMESTAMP() AS now,
    DATEDIFF('hour', TO_TIMESTAMP(CREATED_AT), CURRENT_TIMESTAMP()) AS hours_old
FROM ADJUST.S3_DATA.IOS_ACTIVITY_INSTALL
ORDER BY CREATED_AT DESC
LIMIT 5;

-- Expected: converted_timestamp should be recent dates (within hours/days, not 1970 or 2058)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| loaded_at_field required | Optional with metadata fallback | dbt Core 1.7 (2023) | Can monitor data shares, external tables without timestamp columns |
| Manual cron jobs for freshness | dbt Cloud scheduler | dbt Cloud v1.0 | Native UI, notifications, execution history |
| Separate Elementary/Monte Carlo for monitoring | dbt native freshness + custom tests | 2024-2025 trend | Simpler stack, fewer dependencies |
| "Run source freshness" checkbox only | Dedicated freshness jobs | dbt Cloud best practice | Independent scheduling, 2x SLA frequency |
| Timezone-naive timestamp comparisons | Automatic UTC conversion | dbt Core 0.18+ | Handles timezone edge cases correctly |

**Deprecated/outdated:**
- `dbt-utils.recency` test for source freshness: Use native dbt source freshness instead (recency is for downstream models, not sources)
- Embedding freshness in build jobs: Separate freshness jobs allow independent scheduling and avoid blocking transformations

## Open Questions

Things that couldn't be fully resolved:

1. **What is the actual Amplitude data share refresh schedule?**
   - What we know: Amplitude data shares update on a schedule configured during setup; default is typically hourly or daily
   - What's unclear: The specific refresh cadence for this project's Amplitude share (AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE)
   - Recommendation: Start with conservative thresholds (warn_after: 6 hours, error_after: 12 hours) and adjust based on observed LAST_ALTERED update frequency. Contact Amplitude support or check share configuration if failures occur.

2. **Does the static mapping table need to exist for the test to pass?**
   - What we know: STATE.md says "Static mapping table: ADJUST_AMPLITUDE_DEVICE_MAPPING (1.55M rows, stale Nov 2025) maps IDFV-to-IDFV only. iOS only. Redundant."
   - What's unclear: Is this table actively used in production, or is it legacy? If dropped, the test will fail with "table not found"
   - Recommendation: Confirm table still exists before implementing test. If table is truly redundant and should be dropped, don't create the staleness test. If table is still referenced by downstream models/queries, implement the test to prevent silent staleness.

3. **Are there other sources beyond Adjust and Amplitude that need freshness monitoring?**
   - What we know: Project has sources for supermetrics, revenue, adjust_api, events based on Glob results
   - What's unclear: Which sources are critical for MMM pipeline and need freshness monitoring
   - Recommendation: Phase 6 requirements only mention Adjust and Amplitude. Document freshness patterns so future phases can extend to other sources. Priority: Adjust (S3 activity tables) and Amplitude (data share) only for Phase 6.

4. **What is the correct database/schema for ADJUST_AMPLITUDE_DEVICE_MAPPING?**
   - What we know: STATE.md mentions the table exists with 1.55M rows
   - What's unclear: Full qualified name (database.schema.table) needed for INFORMATION_SCHEMA query
   - Recommendation: Query Snowflake to locate table: `SHOW TABLES LIKE 'ADJUST_AMPLITUDE_DEVICE_MAPPING' IN ACCOUNT;` Then update test SQL with correct database/schema.

## Sources

### Primary (HIGH confidence)
- [dbt Source Freshness Deploy Docs](https://docs.getdbt.com/docs/deploy/source-freshness) - Core functionality and execution patterns
- [dbt Freshness Property Reference](https://docs.getdbt.com/reference/resource-properties/freshness) - Complete configuration syntax and options
- [dbt Source Command Reference](https://docs.getdbt.com/reference/commands/source) - CLI usage and output format
- [Snowflake TO_TIMESTAMP Documentation](https://docs.snowflake.com/en/sql-reference/functions/to_timestamp) - Epoch handling and variants
- [Snowflake INFORMATION_SCHEMA.TABLES](https://docs.snowflake.com/en/sql-reference/info-schema/tables) - LAST_ALTERED and LAST_DDL column definitions

### Secondary (MEDIUM confidence)
- [Datafold: How to use dbt source freshness tests](https://www.datafold.com/blog/dbt-source-freshness) - Best practices and common pitfalls
- [dbt Job Scheduler Documentation](https://docs.getdbt.com/docs/deploy/job-scheduler) - Scheduling patterns and frequency recommendations
- [dbt Best Practices: Writing Custom Generic Tests](https://docs.getdbt.com/best-practices/writing-custom-generic-tests) - Custom test file structure
- [Snowflake Community: LAST_ALTERED Column Behavior](https://community.snowflake.com/s/article/Column-LAST-ALTERED-in-TABLES-view-gets-updated-when-a-query-attempts-to-update-the-tale-without-updating-any-rows) - Edge case documentation
- [Secoda: Guide to Using dbt Source Freshness](https://www.secoda.co/learn/dbt-source-freshness) - Execution frequency best practices

### Tertiary (LOW confidence)
- [Medium: Stale data detection with BigQuery metadata](https://eponkratova.medium.com/stale-data-detection-with-dbt-and-bigquery-dataset-metadata-662196cf9370) - Pattern for metadata-based monitoring (BigQuery-specific but concept applies)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - dbt source freshness is mature feature with official docs and wide adoption
- Architecture: HIGH - Patterns verified against official dbt and Snowflake documentation
- Pitfalls: MEDIUM - Based on official docs plus community forum issues; Adjust epoch and Amplitude metadata patterns are project-specific

**Research date:** 2026-02-12
**Valid until:** 2026-03-31 (45 days) - dbt source freshness is stable feature; Snowflake INFORMATION_SCHEMA is stable; freshness patterns unlikely to change rapidly
