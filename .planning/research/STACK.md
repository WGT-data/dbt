# Stack Research: Device Mapping Fixes and dbt Testing

**Domain:** dbt + Snowflake mobile analytics data quality and device ID resolution
**Researched:** 2026-02-10
**Confidence:** HIGH

## Recommended Stack

### Core dbt Testing Packages

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| dbt-utils | 1.3.3 | Core utility macros and basic generic tests | Industry standard, maintained by dbt Labs. Required by other packages. Provides foundational tests (unique, not_null, relationships, accepted_values) plus utility macros used by dbt-expectations and elementary. Supports dbt >=1.3.0, <3.0.0. |
| dbt-expectations | 0.10.9 | Advanced data quality tests inspired by Great Expectations | The de facto standard for comprehensive data quality testing in dbt. Provides 50+ tests including regex validation, statistical analysis, multi-column logic, distribution testing, and time-series checks. Active fork maintained by Metaplane after original was deprecated. Requires dbt >=1.7.x. |
| elementary | 0.22.1 | Data observability, anomaly detection, and test result monitoring | dbt-native observability solution. Provides anomaly detection tests (freshness, volume, distribution, cardinality) and metadata tables to track test results over time. Integrates with dbt Cloud. OSS version includes Slack/Teams alerts. Supports dbt >=1.0.0, <3.0.0. |

### Device ID Resolution Functions

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Snowflake EDITDISTANCE | Built-in | Levenshtein distance fuzzy matching for device IDs | Snowflake native function for calculating character-level edit distance. Use for probabilistic matching when exact IDs don't match but are similar (typos, formatting differences). Returns integer distance - lower is better match. |
| Snowflake JAROWINKLER_SIMILARITY | Built-in | Probabilistic string matching optimized for short strings | Snowflake native function returning 0-100 similarity score. Better than EDITDISTANCE for device IDs because it accounts for character transpositions and weighs matching prefixes more heavily. Use threshold of 85+ for high confidence matches. |
| Custom dbt macro for ID normalization | N/A | Standardize GPS_ADID, IDFA, IDFV formats before matching | Write macro to UPPER(), TRIM(), remove hyphens/formatting from device IDs before joins. Adjust uses GPS_ADID (Google Play Services ID), Amplitude uses device_id (IDFV for iOS, generated string for Android). Normalization critical for match rate improvement. |

### Supporting dbt Testing Macros

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| dbt-audit-helper | Latest (deprecated, use dbt_artifacts) | Compare old vs new models during migration | Do NOT use - obsolete. Use dbt_artifacts instead for metadata collection. |
| dbt_artifacts | Latest | Collect dbt run metadata and test results in data warehouse | Use if you need metadata tables beyond Elementary's capabilities. Creates mart layer with node-level execution metrics. However, Elementary provides similar functionality - evaluate if both are needed. |

### Snowflake-Specific Capabilities

| Tool | Purpose | Notes |
|------|---------|-------|
| INFORMATION_SCHEMA metadata | Source freshness without loaded_at_field | dbt Core v1.7+ can use Snowflake's table metadata for freshness checks when source tables lack explicit timestamp columns. Configure in source YAML with `freshness: {warn_after: {count: 24, period: hour}}`. |
| QUALIFY clause | Deduplication in device ID resolution | Use QUALIFY with ROW_NUMBER() for efficient deduplication when multiple matches exist. More performant than subqueries for finding best device ID match. |

## Installation

```yaml
# packages.yml
packages:
  # Core testing utilities (required first - other packages depend on it)
  - package: dbt-labs/dbt_utils
    version: 1.3.3

  # Advanced data quality tests
  - package: calogica/dbt-expectations
    version: 0.10.9

  # Data observability and anomaly detection
  - package: elementary-data/elementary
    version: 0.22.1
```

```bash
# Install packages
dbt deps

# Initialize elementary (one-time setup)
# Creates metadata schema and models
dbt run --select elementary

# Verify installation
dbt test --select package:dbt_expectations package:elementary
```

```bash
# Install elementary CLI for observability dashboard and alerts (optional)
pip install elementary-data

# Generate observability report
edr report

# Configure Slack alerts (optional)
edr monitor --slack-webhook [webhook-url]
```

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| dbt-utils 1.3.3 | dbt-core >=1.3.0, <3.0.0 | Fusion compatible. Required by dbt-expectations and elementary. |
| dbt-expectations 0.10.9 | dbt-core >=1.7.x | Maintained by Metaplane (fork of deprecated calogica/dbt-expectations). Depends on dbt-utils. Works on Snowflake, BigQuery, Postgres, DuckDB. Spark support is experimental. |
| elementary 0.22.1 | dbt-core >=1.0.0, <3.0.0 | Fusion compatible. Wider compatibility range than dbt-expectations. |
| dbt Cloud | All versions above | Source freshness monitoring built into dbt Cloud UI. Configure in job settings with "Run source freshness" checkbox. |

**Critical:** dbt-expectations requires dbt 1.7+. If project is on dbt <1.7, upgrade dbt first or use only dbt-utils and elementary.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| dbt-expectations 0.10.9 (Metaplane fork) | dbt-expectations 0.8.x (original calogica) | NEVER - original is deprecated as of 2024-12-18. Active development moved to Metaplane fork. |
| elementary 0.22.1 | re-data | If you need simpler setup with less feature depth. re-data is lighter weight but lacks anomaly detection and real-time monitoring capabilities. |
| elementary OSS | Elementary Cloud | Use Cloud if you need: automated ML monitoring, column-level lineage from source to BI, built-in catalog, AI agents for reliability workflows. OSS sufficient for this project's monitoring needs. |
| Snowflake fuzzy matching functions | External Python/UDF fuzzy matching | Snowflake native functions (EDITDISTANCE, JAROWINKLER_SIMILARITY) are significantly faster and don't require Python UDF setup. Only use external if you need algorithms not in Snowflake (soundex, metaphone). |
| dbt source freshness | Elementary freshness anomaly tests | Use both. dbt source freshness validates SLA compliance. Elementary detects anomalous freshness patterns over time using ML. Complementary, not redundant. |
| Custom ID normalization macro | Snowflake variant functions | For GPS_ADID/IDFA normalization, custom macros are clearer and more maintainable than nested Snowflake functions. Build once, reuse everywhere. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| dbt-audit-helper package | Obsolete - no longer developed | dbt_artifacts for metadata collection. For model comparison during migration, use Datafold's data-diff or build custom comparison tests with dbt-expectations. |
| Probabilistic attribution in warehouse | Mobile attribution systems (Adjust) already do this with real-time context | Use deterministic matching on device IDs. Adjust attribution data already includes probabilistic modeling. Don't rebuild it in Snowflake. Focus on ID normalization and fuzzy matching for data quality issues only. |
| Great Expectations (Python) in dbt pipeline | Adds Python dependency, slower execution, harder to maintain in dbt-native workflow | dbt-expectations provides same test types as native dbt tests. Run in dbt Cloud, version controlled with models, no separate orchestration needed. |
| Soda Core for dbt projects | Separate tool, creates duplicate testing logic, team must learn another YAML syntax | dbt-expectations + elementary provide equivalent capabilities natively in dbt. Keep testing where transformations live. |
| Custom UDFs for device ID matching | Slow, requires Python/Java, breaks down-funnel filtering in Snowflake | Snowflake native EDITDISTANCE and JAROWINKLER_SIMILARITY functions. Snowflake optimizes these internally. |
| Copying all Amplitude data to match Adjust | Expensive compute and storage for marginal match rate improvement | Build device ID mapping table with fuzzy matching. Create intermediate model joining Adjust + Amplitude on multiple ID strategies (exact match → fuzzy match → fallback). |

## Stack Patterns by Variant

**If Android GPS_ADID != Amplitude device_id:**
- Use UPPER() normalization first (Amplitude stores lowercase, Adjust may vary)
- Build mapping table with ROW_NUMBER() QUALIFY to deduplicate
- Try exact match on normalized GPS_ADID → Amplitude device_id
- Fallback to JAROWINKLER_SIMILARITY >= 85 for high confidence fuzzy matches
- Log unmatched records in separate model for manual review

**If iOS IDFA match rate is low (1.4%):**
- Check for IDFV usage (Amplitude uses IDFV when IDFA unavailable due to ATT)
- Post-ATT, IDFA availability is ~25-30% - low match rate expected
- Build user-level mapping using Amplitude user_id + session timestamps to bridge Adjust → Amplitude
- Consider using Amplitude's Attribution API to push Adjust events into Amplitude instead of matching in warehouse
- Document that 70%+ of iOS traffic is unattributable at device level due to ATT

**If source freshness SLA is 1 hour or less:**
- Run dbt Cloud freshness job every 30 minutes (2x frequency of lowest SLA)
- Use "Run source freshness" checkbox in job settings (doesn't block downstream on failure)
- Add elementary freshness anomaly tests to detect unexpected delays beyond SLA
- Configure Slack alerts for error_after threshold breaches

**If comprehensive test coverage is goal:**
- Layer tests strategically: sources (basic hygiene) → staging (nulls, types, deduplication) → intermediate (joins, grain, enrichment) → marts (business logic, anomalies)
- Use dbt-utils tests at all layers (unique, not_null, relationships, accepted_values)
- Use dbt-expectations at intermediate/marts (regex, distributions, multi-column logic, time-series)
- Use elementary at marts only (anomaly detection on production outputs)
- Avoid testing same thing at multiple layers - test net-new columns and logic at each layer

**If team is new to dbt testing:**
- Start with dbt-utils 1.3.3 only - master built-in tests first
- Add dbt-expectations 0.10.9 after 2-4 weeks when team is comfortable with test patterns
- Add elementary 0.22.1 last - after test coverage is substantial
- Elementary is most valuable when you have 50+ tests to monitor

## Device ID Resolution Architecture Recommendation

### Staging Layer
- `stg_adjust__installs` - normalize GPS_ADID/IDFA with UPPER(), TRIM(), remove hyphens
- `stg_amplitude__events` - normalize device_id with same logic
- Tests: not_null on device IDs, accepted_values for platform, dbt-expectations regex for device ID format

### Intermediate Layer
- `int_device_id_mapping__exact_match` - GPS_ADID = device_id
- `int_device_id_mapping__fuzzy_match` - JAROWINKLER_SIMILARITY >= 85 where exact match failed
- `int_device_id_mapping__final` - UNION exact + fuzzy with match_type flag, deduplicated with QUALIFY
- Tests: unique on mapping key, relationships tests to staging, dbt-expectations for match score distribution

### Marts Layer
- `mart_adjust_amplitude_bridge` - final device mapping with match quality metadata
- `mart_unmatched_devices` - devices that failed all matching strategies for manual review
- Tests: elementary anomaly tests on match rate %, volume tests, cardinality tests

## Source Freshness Configuration

```yaml
# models/staging/adjust/_adjust__sources.yml
sources:
  - name: adjust
    description: Adjust mobile attribution data
    database: ADJUST
    schema: S3_DATA
    # Run freshness check every 30 min in dbt Cloud (2x the 1-hour SLA)
    freshness:
      warn_after: {count: 1, period: hour}
      error_after: {count: 2, period: hour}
    tables:
      - name: ANDROID_ACTIVITY_INSTALL
        loaded_at_field: created_at  # Adjust timestamp field
        # Override if this source has different SLA
        # freshness:
        #   warn_after: {count: 24, period: hour}

# models/staging/amplitude/_amplitude__sources.yml
sources:
  - name: amplitude
    database: AMPLITUDE
    schema: EVENTS
    freshness:
      warn_after: {count: 1, period: hour}
      error_after: {count: 2, period: hour}
    tables:
      - name: events
        loaded_at_field: event_time
```

## dbt Cloud Job Configuration

**Job 1: Source Freshness Monitor (every 30 min)**
- Commands: `dbt source freshness`
- Schedule: Cron `*/30 * * * *` (every 30 minutes)
- Do NOT check "Run source freshness" - this IS the freshness job
- Alerts: Slack on error_after breach

**Job 2: Production Run (every 1 hour)**
- Commands: `dbt build --select state:modified+` (uses state for efficiency)
- Schedule: Cron `0 * * * *` (top of every hour)
- Check "Run source freshness" checkbox - runs before build, doesn't block on failure
- Run after: Job 1 (waits for freshness check)

**Job 3: Elementary Monitoring (every 6 hours)**
- Commands: `dbt run --select elementary` then `dbt test`
- Schedule: Cron `0 */6 * * *` (every 6 hours)
- Generates metadata for elementary dashboard
- Configure elementary CLI separately to pull metadata and send Slack alerts

## Testing Strategy by Layer

### Sources (Adjust, Amplitude raw tables)
- **Tests:** Basic hygiene only - flag source system issues
- **dbt-utils:** None (can't add tests to sources, only freshness)
- **dbt-expectations:** None
- **elementary:** Freshness anomaly detection on critical sources
- **Goal:** Identify upstream data quality issues

### Staging (stg_adjust__*, stg_amplitude__*)
- **Tests:** Data type validation, nulls on critical columns, deduplication
- **dbt-utils:** not_null (device IDs, timestamps), unique (event IDs)
- **dbt-expectations:** expect_column_values_to_match_regex (device ID format), expect_column_values_to_be_in_type_list
- **elementary:** Volume anomaly detection (sudden drop/spike in row count)
- **Goal:** Clean, typed, deduplicated inputs for downstream models

### Intermediate (int_device_id_mapping__*, int_mta__*)
- **Tests:** Grain validation, join logic verification, enrichment checks
- **dbt-utils:** unique (composite keys after joins), relationships (foreign key validation), accepted_values (match_type, platform)
- **dbt-expectations:** expect_column_pair_values_A_to_be_greater_than_B (timestamp ordering), expect_compound_columns_to_be_unique, expect_column_quantile_values_to_be_between (match score distribution)
- **elementary:** Cardinality anomaly detection (unexpected fan-out from joins)
- **Goal:** Verify transformation logic produces expected grain and relationships

### Marts (mart_campaign_performance_*, mart_adjust_amplitude_bridge)
- **Tests:** Business logic validation, anomaly detection, critical business rules
- **dbt-utils:** not_null (revenue, user counts), unique (campaign + date), relationships (to dimension tables)
- **dbt-expectations:** expect_column_values_to_be_between (reasonable ranges for spend, ROAS), expect_column_mean_to_be_between (average session length), expect_row_values_to_have_recent_data (ensure data pipeline is current)
- **elementary:** All anomaly types (freshness, volume, schema changes, distribution shifts in KPIs)
- **Goal:** Protect production data quality, alert on unexpected changes

## Performance Considerations

**Test execution time:**
- dbt-utils tests: Fast (compiled to simple SQL)
- dbt-expectations statistical tests: Slower (aggregations, windows). Limit to marts.
- elementary anomaly tests: Slower (compare to historical baseline). Run on schedule, not every dbt run.

**Fuzzy matching optimization:**
- Block/partition before fuzzy matching (e.g., match within platform + date range)
- Fuzzy match only after exact match fails (reduces comparison pairs by 90%+)
- Set similarity threshold high (>=85) to avoid false positives
- Use QUALIFY to deduplicate matches in same query (faster than subquery)

**Incremental testing:**
- Use `dbt test --select state:modified+` in CI to test only changed models
- Full test suite on production schedule (every 6 hours)
- Source freshness every 30 min (independent of model builds)

## Sources

### Package Versions and Compatibility
- [dbt-utils Package Hub](https://hub.getdbt.com/dbt-labs/dbt_utils/latest/) - Version 1.3.3 confirmed, dbt >=1.3.0 requirement (HIGH confidence)
- [dbt-expectations GitHub (Metaplane fork)](https://github.com/metaplane/dbt-expectations) - Version 0.10.9, dbt >=1.7.x requirement, deprecation of original package (HIGH confidence)
- [elementary Package Hub](https://hub.getdbt.com/elementary-data/elementary/latest/) - Version 0.22.1, dbt >=1.0.0 compatibility (HIGH confidence)
- [elementary GitHub](https://github.com/elementary-data/elementary) - OSS capabilities, installation process (HIGH confidence)

### dbt Testing Best Practices
- [Test smarter not harder: Where should tests go in your pipeline?](https://docs.getdbt.com/blog/test-smarter-where-tests-should-go) - Official dbt Labs testing strategy by layer (HIGH confidence)
- [dbt Source Freshness Documentation](https://docs.getdbt.com/docs/deploy/source-freshness) - Freshness configuration, scheduling recommendations (HIGH confidence)
- [DBT Models in Snowflake: Best Practices](https://medium.com/@manik.ruet08/dbt-models-in-snowflake-best-practices-for-staging-intermediate-and-mart-layers-2abf37d08f65) - Layer-specific testing patterns (MEDIUM confidence)
- [dbt Packages Documentation](https://docs.getdbt.com/docs/build/packages) - Version pinning best practices (HIGH confidence)

### Mobile Attribution and Device ID Resolution
- [Adjust Device Identifiers Help](https://help.adjust.com/en/article/device-identifiers) - GPS_ADID, IDFA, Android ID usage in Adjust (HIGH confidence)
- [Amplitude User Identification](https://help.amplitude.com/hc/en-us/articles/206404628-Step-2-Identifying-your-users) - device_id, user_id, amplitude_id reconciliation (HIGH confidence)
- [Amplitude Adjust Integration](https://amplitude.com/docs/data/destination-catalog/adjust) - Attribution API, device ID mapping between systems (HIGH confidence)
- [Understanding Mobile Device ID Tracking 2026](https://ingestlabs.com/mobile-device-id-tracking-guide/) - ATT impact, IDFA opt-in rates, 2026 context (MEDIUM confidence)
- [Probabilistic Attribution](https://www.singular.net/glossary/probabilistic-attribution/) - Deterministic vs probabilistic matching approaches (MEDIUM confidence)

### Snowflake Fuzzy Matching
- [Fuzzy matching in Snowflake | DAS42](https://das42.com/thought-leadership/fuzzy-matching-in-snowflake/) - EDITDISTANCE, JAROWINKLER_SIMILARITY usage patterns (HIGH confidence)
- [Fuzzy Match Strings using SQL in Snowflake](https://medium.com/@itsdaniyalm/fuzzy-match-strings-using-sql-in-snowflake-a32bbc4b1fb7) - Implementation examples (MEDIUM confidence)

### Data Quality and Observability Landscape
- [The 2026 Open-Source Data Quality and Data Observability Landscape](https://datakitchen.io/the-2026-open-source-data-quality-and-data-observability-landscape/) - Ecosystem overview, elementary vs alternatives (MEDIUM confidence)
- [Add observability to your dbt project: Top 3 dbt testing packages](https://www.elementary-data.com/post/add-observability-to-your-dbt-project-top-3-dbt-testing-packages) - Elementary + dbt-expectations + dbt-utils stack justification (MEDIUM confidence)
- [Data Observability dbt Packages](https://infinitelambda.com/data-observability-dbt-packages/) - dbt_artifacts vs elementary comparison (MEDIUM confidence)

---
*Stack research for: WGT Golf dbt Analytics - Device Mapping Fixes and Comprehensive Testing*
*Researched: 2026-02-10*
*Confidence: HIGH - All package versions verified via official sources (Package Hub, GitHub). Device ID resolution patterns confirmed via Adjust and Amplitude official documentation. Snowflake fuzzy matching functions verified as built-in capabilities.*
