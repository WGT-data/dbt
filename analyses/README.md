# Device ID Audit Queries

This directory contains SQL analysis queries for **Phase 2: Device ID Audit & Documentation**. Each file is a single SQL statement that can be run individually in dbt Cloud IDE.

## How to Run

All queries use **fully qualified Snowflake table names** (not dbt `source()` or `ref()` functions). Run each file individually in dbt Cloud IDE or Snowflake.

### dbt Cloud IDE

1. Open dbt Cloud IDE
2. Navigate to `analyses/` and open a query file
3. Click "Run" or press Cmd/Ctrl + Enter
4. Results appear in the results pane

### Snowflake Worksheet

1. Copy and paste the file contents into a worksheet
2. Click "Run"

## Query Files

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
