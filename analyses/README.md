# Device ID Audit Queries

This directory contains SQL analysis queries for **Phase 2: Device ID Audit & Documentation**. These queries investigate device ID formats and measure baseline match rates across Adjust and Amplitude before any normalization changes are implemented.

## Purpose

These queries are the investigation tools for Phase 2. They produce real results from production Snowflake tables that will:

1. Establish baseline device ID population and format characteristics
2. Measure current match rates between Adjust and Amplitude by platform
3. Identify the root causes of Android device mapping failures
4. Document iOS IDFA availability and ATT consent impact

**Without running these queries, we cannot establish the "before" state that Phase 3 normalization will be measured against.**

## How to Run

All queries in this directory use **fully qualified Snowflake table names** (not dbt `source()` or `ref()` functions). This means they can be run directly without dbt compilation.

### Option 1: dbt Cloud IDE (Recommended)

1. Open dbt Cloud IDE
2. Create a new scratchpad or use the SQL runner
3. Copy and paste the entire SQL file contents
4. Click "Run" or press Cmd/Ctrl + Enter
5. Results will appear in the results pane below

### Option 2: Snowflake Worksheet

1. Log into Snowflake web UI
2. Navigate to Worksheets
3. Create a new worksheet
4. Copy and paste the entire SQL file contents
5. Click "Run All" or select sections to run individually
6. Results will appear in the results pane

## Query Files

Run these queries in order for best investigative flow:

### 1. `audit_device_id_formats.sql`

**What it does:** Profiles device ID columns (GPS_ADID, ADID, IDFV, IDFA) across Adjust iOS and Android install tables.

**Answers:**
- Which device ID columns are populated by platform?
- What percentage of installs have each ID type?
- What format do device IDs use? (UUID, length, casing)
- Are device IDs uppercase, lowercase, or mixed case?

**Output:** 3 result sets
1. iOS device ID profiling with population stats and sample values
2. Android device ID profiling with population stats and sample values
3. Cross-platform summary comparing iOS and Android

**Scope:** Last 60 days of install events

**Run time:** ~30-60 seconds

---

### 2. `amplitude_device_id_investigation.sql`

**What it does:** Investigates Amplitude's DEVICE_ID column format and checks for alternative device identifier fields.

**Answers:**
- Is Amplitude Android DEVICE_ID a random ID or GPS_ADID?
- Does Amplitude have a separate ADID or advertising_id field?
- What is the 'R' suffix pattern on Android device IDs?
- Does the MERGE_IDS table contain device-to-advertising-ID mappings?

**Output:** 8 result sets
1. Device ID format stats by platform (length, UUID format, R suffix prevalence)
2. Sample device IDs for manual inspection (10 per platform)
3. ADID-related column search results
4. Full EVENTS table column list
5. MERGE_IDS table column list
6. MERGE_IDS table sample rows (20 rows)
7. MERGE_IDS table profiling statistics
8. Cross-check: Do any Amplitude device IDs match Adjust GPS_ADID?

**Scope:** Last 30 days of event data

**Run time:** ~60-90 seconds (includes table schema queries)

---

### 3. `baseline_match_rates.sql`

**What it does:** Calculates current match rates between Adjust and Amplitude device IDs by platform and match strategy.

**Answers:**
- What is the Android GPS_ADID match rate (direct and R-stripped)?
- What is the iOS IDFV match rate?
- What is the iOS IDFA match rate (ATT-limited)?
- What is the iOS MTA touchpoint match rate?
- What does the current production device_mapping model contain?

**Output:** 6 result sets
1. Android GPS_ADID match rate (direct and R-stripped)
2. iOS IDFV match rate
3. iOS IDFA match rate with ATT consent percentage
4. Current production device_mapping model state
5. iOS touchpoint match rate for MTA
6. Summary table with all match rates by platform and strategy

**Scope:** Last 60 days of data

**Run time:** ~90-120 seconds (joins across large tables)

**IMPORTANT:** Save these results! They are the baseline "before" snapshot. Run again after Phase 3 to measure improvement.

---

## Capturing Results

After running each query:

1. **Export to CSV:**
   - dbt Cloud: Click "Download" in results pane
   - Snowflake: Click "Download Results" button

2. **Save to findings directory:**
   ```
   .planning/phases/02-device-id-audit/findings/
   ├── audit_device_id_formats_results.csv
   ├── amplitude_device_id_investigation_results.csv
   └── baseline_match_rates_results.csv
   ```

3. **Document key findings:**
   - Copy interesting sample values into documentation
   - Note any unexpected patterns (e.g., 0% population for expected columns)
   - Record exact match rate percentages for baseline comparison

4. **Share with team:**
   - Results inform Phase 3 normalization strategy
   - Baseline match rates set stakeholder expectations
   - iOS ATT limitations require explanation to non-technical stakeholders

## Technical Notes

- **No dbt compilation needed:** All queries use `DATABASE.SCHEMA.TABLE` fully qualified names
- **Date filters:** Queries scope to 30-60 day lookback to balance data coverage with performance
- **Sampling:** Some queries sample for performance (noted in comments)
- **Platform filtering:** All aggregate queries include `GROUP BY PLATFORM` for iOS vs Android comparison
- **Null handling:** `COUNT(column)` excludes NULLs; `COUNT(*)` includes all rows

## Common Issues

### "Object does not exist" errors

**Cause:** Snowflake role doesn't have access to source tables

**Fix:** Ensure you're using a role with read access to:
- `ADJUST.S3_DATA.*` tables
- `AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.*` tables

### Query timeout

**Cause:** Large date range or no date filter applied

**Fix:** Queries already have 30-60 day filters. If still timing out, reduce to 14-30 days by editing the `DATEADD(day, -60, CURRENT_DATE())` filter.

### Empty result sets

**Possible causes:**
1. **Recent data pipeline issue:** Check source freshness
2. **Wrong schema name:** Verify schema names match your environment
3. **Date filter too restrictive:** Increase day range in `DATEADD` filter

## Next Steps

After running all queries and capturing results:

1. ✅ Review results and identify patterns
2. ⬜ Document findings in `.planning/phases/02-device-id-audit/findings/` directory
3. ⬜ Update stakeholder documentation explaining iOS ATT limitations
4. ⬜ Design Phase 3 normalization strategy based on audit findings
5. ⬜ Set baseline metric alerts (if match rates drop, indicates data pipeline issue)

## Questions?

- **For query syntax issues:** Check Snowflake SQL documentation
- **For dbt-specific questions:** See [dbt docs on analyses](https://docs.getdbt.com/docs/build/analyses)
- **For device ID mapping context:** See `.planning/phases/02-device-id-audit/02-RESEARCH.md`
