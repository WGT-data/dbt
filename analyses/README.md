# Analysis Queries

This directory contains SQL analysis queries that can be run individually in dbt Cloud IDE or Snowflake.

## How to Run

Queries in `reconciliation/` use dbt `ref()` functions — run them via **dbt Cloud IDE** (compile + run). Older Device ID audit queries use fully qualified Snowflake table names and can also be pasted directly into a Snowflake worksheet.

### dbt Cloud IDE

1. Open dbt Cloud IDE
2. Navigate to `analyses/` and open a query file
3. Click "Run" or press Cmd/Ctrl + Enter
4. Results appear in the results pane

### Snowflake Worksheet

1. Copy and paste the file contents into a worksheet
2. Click "Run"

## Query Files

---

### Data Reconciliation Audit (11 queries)

Located in `reconciliation/`. Full audit documentation: [`docs/audit_data_reconciliation.md`](../docs/audit_data_reconciliation.md).

**Start here** — run queries 01, 06, 08 first to surface top-level discrepancies, then drill into specific layers.

| File | What it does |
|------|-------------|
| `reconciliation_01_cross_mart_spend.sql` | Compare spend across exec summary, biz overview, platform overview, and MMM marts |
| `reconciliation_02_raw_vs_staging_adjust_spend.sql` | Validate Adjust API raw vs `stg_adjust__report_daily` spend |
| `reconciliation_03_raw_vs_staging_facebook_spend.sql` | Validate Fivetran Facebook raw vs `v_stg_facebook_spend` |
| `reconciliation_04_raw_vs_staging_google_spend.sql` | Validate Fivetran Google Ads raw vs `v_stg_google_ads__spend` |
| `reconciliation_05_unified_spend_breakdown.sql` | Daily spend by source in `int_spend__unified` |
| `reconciliation_06_cross_mart_installs.sql` | Compare 6 install definitions across all marts |
| `reconciliation_07_api_vs_s3_installs.sql` | Adjust API installs vs S3 device-level installs (reinstall inflation) |
| `reconciliation_08_cross_mart_revenue.sql` | Compare 4 revenue definitions across all marts |
| `reconciliation_09_adjust_vs_wgt_revenue.sql` | Adjust API revenue vs WGT.EVENTS.REVENUE (mobile only) |
| `reconciliation_10_google_campaign_overlap.sql` | Detect Google campaigns present in both Adjust and Fivetran |
| `reconciliation_11_google_country_code_validation.sql` | Validate Google Ads +2000 country code offset mapping |

**Scope:** 2025-01-01 onward. **Run time:** ~10-60 seconds each.

---

### Device ID Format Audit (3 queries)

Run in order for best investigative flow.

### Device ID Format Audit (3 queries)

| File | What it does |
|------|-------------|
| `audit_01_ios_device_id_profiling.sql` | Profile GPS_ADID, ADID, IDFV, IDFA for iOS installs (population %, format, casing, samples) |
| `audit_02_android_device_id_profiling.sql` | Same profiling for Android installs |
| `audit_03_cross_platform_summary.sql` | Side-by-side iOS vs Android comparison |

**Scope:** Last 60 days of install events. **Run time:** ~30-60 seconds each.

### Amplitude Device ID Investigation (8 queries)

| File | What it does |
|------|-------------|
| `amplitude_01_device_id_format_stats.sql` | DEVICE_ID format stats by platform (length, UUID %, R suffix %, casing) |
| `amplitude_02_sample_device_ids.sql` | 10 sample device IDs per platform for manual inspection |
| `amplitude_03_adid_field_investigation.sql` | Search for ADID/advertising ID columns in EVENTS table |
| `amplitude_04_events_column_list.sql` | Full EVENTS table column list |
| `amplitude_05_merge_ids_structure.sql` | MERGE_IDS table column structure |
| `amplitude_06_merge_ids_samples.sql` | 20 sample rows from MERGE_IDS |
| `amplitude_07_merge_ids_stats.sql` | MERGE_IDS row count |
| `amplitude_08_cross_check_adjust_match.sql` | Cross-check: do any Amplitude device IDs match Adjust GPS_ADID? |

**Scope:** Last 30 days. **Run time:** ~10-90 seconds each.

### Baseline Match Rates (6 queries)

| File | What it does |
|------|-------------|
| `baseline_01_android_gps_adid_match.sql` | Android GPS_ADID match rate (direct and R-stripped) |
| `baseline_02_ios_idfv_match.sql` | iOS IDFV match rate |
| `baseline_03_ios_idfa_match.sql` | iOS IDFA match rate with ATT consent % |
| `baseline_04_device_mapping_state.sql` | Current production device_mapping model state |
| `baseline_05_ios_touchpoint_match.sql` | iOS MTA touchpoint match rate |
| `baseline_06_summary_all_match_rates.sql` | Summary table with device counts by platform |

**Scope:** Last 60 days. **Run time:** ~30-120 seconds each.

**IMPORTANT:** Save baseline results! They are the "before" snapshot for Phase 3 comparison.

## Capturing Results

After running each query:

1. **Export to CSV** from the results pane
2. **Save to findings directory:**
   ```
   .planning/phases/02-device-id-audit/findings/
   ```
3. **Document key findings** — copy interesting values and record exact match rate percentages

## Common Issues

### "Object does not exist" errors
Ensure your Snowflake role has read access to `ADJUST.S3_DATA.*` and `AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.*` tables.

### Query timeout
Queries already have 30-60 day filters. If still timing out, reduce to 14 days by editing the `DATEADD` filter.

### Empty result sets
Check source freshness, verify schema names match your environment, or increase the day range.
