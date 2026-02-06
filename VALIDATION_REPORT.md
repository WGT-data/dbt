# dbt Model Validation Report

**Date:** 2026-02-05
**Environment:** Dev (`DBT_ANALYTICS.DBT_WGTDATA`) and Prod (`DBT_ANALYTICS.DBT_ANALYTICS`)
**Purpose:** Pre-production audit of all downstream dbt models built on Adjust activity tables

---

## Summary

| Metric | Count |
|--------|-------|
| **Models Checked** | 20 |
| **Checks Run** | 48 |
| **PASS** | 38 |
| **PASS (with NOTE)** | 4 |
| **FAIL** | 6 |

### Issues Ranked by Severity

| # | Severity | Model | Issue |
|---|----------|-------|-------|
| 1 | **CRITICAL** | `mart_campaign_performance_full` | FULL OUTER JOIN completely broken — spend (PLATFORM="undefined") never matches cohort (PLATFORM="iOS"). CPI, ROAS, and all derived metrics are meaningless. $2.57M spend disconnected from $4.2M revenue. |
| 2 | **CRITICAL** | `mart_campaign_performance_full_mta` | Same PLATFORM mismatch as above. Spend never joins to Adjust or MTA attribution data. All cross-model metrics (CPI, ROAS) broken. |
| 3 | **HIGH** | `attribution__network_performance` | $1.02M spend with NULL AD_PARTNER and 0 installs from FULL OUTER JOIN mismatch ($248K iOS + $767K Android). |
| 4 | **MEDIUM** | `attribution__installs` | Grain violation — duplicates exist where CAMPAIGN_ID is NULL (e.g., AppLovin 186 dupes on single date). |
| 5 | **LOW** | `int_mta__touchpoint_credit` | Position-based credit doesn't sum to 1.0 for 1,503/493,720 installs (0.3%). Root cause: identical timestamps cause ROW_NUMBER non-determinism. |
| 6 | **LOW** | `int_mta__user_journey` | Some installs have up to 25,500 touchpoints — likely IP-based matching false positives on shared IPs. |

---

## LAYER 1: Staging Views

### 1A. v_stg_adjust__installs

**Schema:** Logic validated directly against `ADJUST.S3_DATA.*` (dev view is broken — references nonexistent `ADJUST_S3` database)
**Row Count:** iOS: 1,387,802 | Android: 11,191 | Combined: 1,398,993

| Check | Result | Details |
|-------|--------|---------|
| Dedup (DEVICE_ID + PLATFORM) | **PASS** | 0 duplicates |
| NULL filtering | **PASS** | 0 rows with NULL DEVICE_ID or NULL INSTALLED_AT |
| AD_PARTNER mapping | **PASS** | NETWORK_NAME correctly maps via CASE statement (e.g., "Untrusted Devices", "Apple Search Ads", "Organic") |
| CAMPAIGN_ID regex | **PASS** | Regex `[0-9]{8,}` correctly extracts numeric IDs from CAMPAIGN_NAME |

**NOTE:** The dev-compiled view (`DBT_ANALYTICS.DBT_WGTDATA.V_STG_ADJUST__INSTALLS`) references `ADJUST_S3.DBT_WGTDATA_PROD_DATA.*` which does not exist. The `_adjust__sources.yml` correctly maps to `ADJUST.S3_DATA`. The view needs to be recompiled against the correct target.

---

### 1B. v_stg_adjust__touchpoints

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`
**Row Count:** 987,010,968

| Check | Result | Details |
|-------|--------|---------|
| PLATFORM + TOUCHPOINT_TYPE distribution | **PASS** | iOS impressions: 571M, iOS clicks: 5.2M, Android impressions: 399M, Android clicks: 12M |
| NULL identifier check | **PASS** | 0 rows with both DEVICE_ID and IDFA null (iOS) or DEVICE_ID and IP_ADDRESS null (Android) |
| Epoch filter (CREATED_AT >= 1704067200) | **PASS** | 0 rows below epoch threshold |

---

### 1C. v_stg_amplitude__merge_ids

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`
**Row Count:** 5,637,159

| Check | Result | Details |
|-------|--------|---------|
| One-to-many (DEVICE_ID_UUID + PLATFORM → 1 USER_ID) | **PASS** | 0 violations |
| Android R-suffix stripping | **PASS** | 0 DEVICE_ID_UUID values ending in 'R' |
| Uppercase DEVICE_ID_UUID | **PASS** | All values are uppercase |

---

### 1D. v_stg_amplitude__events

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`
**Row Count:** 5,005,458,756

| Check | Result | Details |
|-------|--------|---------|
| SERVER_UPLOAD_TIME >= '2025-01-01' | **PASS** | 0 pre-2025 rows. Min date: 2025-08-15 |

---

### 1E. v_stg_revenue__events

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`
**Row Count:** 1,343,613

| Check | Result | Details |
|-------|--------|---------|
| EVENT_TIME >= '2025-01-01' | **PASS** | 0 pre-2025 rows |
| NULL REVENUE_AMOUNT | **PASS** | 0 NULL values (all rows have revenue amounts) |

---

### 1F. stg_supermetrics__adj_campaign

**Schema:** `SUPERMETRICS.DATA_TRANSFERS.ADJ_CAMPAIGN` (source)
**Row Count:** View: 1,209,260 | Source: 1,252,854 (dedup removed ~43K rows)

| Check | Result | Details |
|-------|--------|---------|
| Dedup (QUALIFY ROW_NUMBER) | **PASS** | Row reduction from 1,252,854 → 1,209,260 confirms dedup is working |
| PLATFORM standardization | **PASS (NOTE)** | 15 distinct platform values including iOS, Android, macos, windows, server, etc. Not just iOS/Android — this is correct for the Adjust API data which tracks all platforms |

---

### 1G. Facebook Staging Views

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`

| View | Row Count | Check | Result | Details |
|------|-----------|-------|--------|---------|
| v_stg_facebook_spend | 18,358 | JOIN produces results | **PASS** | Joins to ad_history, campaign_history, ad_set_history all working |
| v_stg_facebook_conversions | 209,397 | DIVIDEND = 0 check | **PASS** | 0 rows with DIVIDEND = 0 |

---

## LAYER 2: Intermediate Models

### 2A. int_adjust_amplitude__device_mapping

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`
**Row Count:** 5,637,159 (exact match with v_stg_amplitude__merge_ids)

| Check | Result | Details |
|-------|--------|---------|
| Row count vs merge_ids | **PASS** | 5,637,159 = 5,637,159 (exact match) |
| Uniqueness (ADJUST_DEVICE_ID + AMPLITUDE_USER_ID + PLATFORM) | **PASS** | 0 duplicates |

---

### 2B. int_mta__user_journey

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`
**Row Count:** 19,858,714

| Check | Result | Details |
|-------|--------|---------|
| 7-day lookback window | **PASS** | 0 touchpoints linked to installs more than 7 days prior |
| Touchpoint count distribution | **PASS (NOTE)** | Max = 25,500 touchpoints per install. This is high — likely from IP-based probabilistic matching on shared IPs. Top counts: 25,500 / 20,461 / 19,937. Affects a small number of installs. |
| IS_FIRST_TOUCH / IS_LAST_TOUCH flags | **PASS** | Exactly 1 first-touch and 1 last-touch per DEVICE_ID + PLATFORM + INSTALL_TIMESTAMP. 0 violations. |

---

### 2C. int_mta__touchpoint_credit

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`

| Check | Result | Details |
|-------|--------|---------|
| Last-touch credit sums to 1.0 | **PASS** | 0 violations |
| First-touch credit sums to 1.0 | **PASS** | 0 violations |
| Linear credit sums to 1.0 | **PASS** | 0 violations |
| Time-decay credit sums to ~1.0 | **PASS** | 0 violations (within 0.01 tolerance) |
| Position-based credit sums to 1.0 | **FAIL** | 1,503/493,720 installs (0.3%) do not sum to 1.0 |
| Last-touch = 1.0 only for last touchpoint | **PASS** | 0 violations |
| First-touch = 1.0 only for first touchpoint | **PASS** | 0 violations |

**Root Cause (Position-Based):** When multiple touchpoints share identical timestamps, ROW_NUMBER() assigns positions non-deterministically. A touchpoint can be simultaneously flagged as IS_FIRST_TOUCH=1 and IS_LAST_TOUCH=1 while another gets neither flag, causing the 40/40/20 split to misallocate credit.

---

### 2D. int_skan__aggregate_attribution

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`
**Row Count:** 10,792

| Check | Result | Details |
|-------|--------|---------|
| No device-level identifiers | **PASS** | No IDFV, IDFA, or GPS_ADID columns present |
| Grain (AD_PARTNER + CAMPAIGN_NAME + PLATFORM + DATE) | **PASS** | 0 duplicates |
| CV bucket sum vs INSTALLS_WITH_CV | **PASS** | Bucket total (232,544) = INSTALLS_WITH_CV (232,544). Note: INSTALL_COUNT (268,933) includes installs with NULL CV, which is expected. |

---

### 2E. int_user_cohort__attribution

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`
**Row Count:** 1,936,604

| Check | Result | Details |
|-------|--------|---------|
| Uniqueness (USER_ID + PLATFORM) | **PASS** | 0 duplicates |
| USER_ID match rate | **PASS** | 100% match rate (1,936,604 / 1,936,604). All rows have USER_ID (inner join guarantees this). |

---

### 2F. int_user_cohort__metrics

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`

| Check | Result | Details |
|-------|--------|---------|
| Retention flags binary (0 or 1) | **PASS** | D1_RETAINED: {0, 1}, D7_RETAINED: {0, 1}, D30_RETAINED: {0, 1} |
| Revenue ordering (D7 <= D30 <= TOTAL) | **PASS** | 0 violations |
| Maturity flags correct | **PASS** | 0 violations (D7_MATURE=1 only if install 7+ days old, etc.) |

---

### 2G. int_revenue__user_summary

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`

| Check | Result | Details |
|-------|--------|---------|
| No negative TOTAL_REVENUE | **PASS** | Min = $0.99 |
| PURCHASE_COUNT >= 0 | **PASS** | Min = 1, Max = 11,568 |

**NOTE:** Max TOTAL_REVENUE = $103,824.58 — high but plausible for a whale user in mobile gaming.

---

## LAYER 3: Marts

### 3A. attribution__installs

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`
**Row Count:** 513,911

| Check | Result | Details |
|-------|--------|---------|
| NULL AD_PARTNER | **PASS** | 0 NULL values |
| Grain check (AD_PARTNER + NETWORK_NAME + CAMPAIGN_ID + ADGROUP_ID + PLATFORM + INSTALL_DATE) | **FAIL** | Duplicates exist where CAMPAIGN_ID is NULL |

**Duplicate Details:**

| AD_PARTNER | PLATFORM | Sample Dupe Count | Cause |
|------------|----------|-------------------|-------|
| AppLovin | iOS | 186 on single date | NULL CAMPAIGN_ID |
| Smadex | iOS | 101 on single date | NULL CAMPAIGN_ID |
| MOLOCO | iOS | 86 on single date | NULL CAMPAIGN_ID |
| Unity Ads | iOS | 79 on single date | NULL CAMPAIGN_ID |

**Root Cause:** When CAMPAIGN_ID is NULL, multiple rows with the same AD_PARTNER + PLATFORM + INSTALL_DATE + NULL CAMPAIGN_ID collapse to the same unique key but are actually distinct installs. The unique_key constraint should include a tiebreaker or CAMPAIGN_ID should be coalesced.

---

### 3B. attribution__campaign_performance

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`
**Row Count:** 212,710 rows with installs

| Check | Result | Details |
|-------|--------|---------|
| Cost total | **PASS (NOTE)** | $2.57M total cost |
| CPI sanity | **PASS (NOTE)** | Max CPI = $204.90 (Google, low-volume campaign). No negative CPI. 27 rows with CPI > $100, all low-volume campaigns (1-2 installs). |
| ROAS sanity | **PASS** | No extreme outliers |

---

### 3C. attribution__network_performance

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`

| Check | Result | Details |
|-------|--------|---------|
| Spend with no installs | **FAIL** | $1.02M in spend with NULL AD_PARTNER and 0 installs |

**Breakdown:**

| AD_PARTNER | PLATFORM | COST | INSTALLS |
|------------|----------|------|----------|
| NULL | Android | $767K | 0 |
| NULL | iOS | $248K | 0 |

**Root Cause:** The FULL OUTER JOIN between spend (from Supermetrics) and install attribution produces rows where the spend side has no matching AD_PARTNER in the attribution data. The spend-side AD_PARTNER is NULL because it comes from the COALESCE fallback in the join, and the attribution side has no matching row.

---

### 3D. mta__campaign_performance

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`

| Check | Result | Details |
|-------|--------|---------|
| All 5 attribution columns non-null | **PASS** | All columns present and populated |
| Install total consistency | **PASS** | LT=493,720, FT=493,720, TD=493,720, LIN=493,720.14, PB=493,017.40 |

**NOTE:** Position-based is slightly low (493,017 vs 493,720) due to the position-based credit bug identified in Layer 2C. Linear is slightly above 1.0 (493,720.14) due to floating-point accumulation — acceptable.

---

### 3E. mart_campaign_performance_full

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`
**Row Count:** 407,164

| Check | Result | Details |
|-------|--------|---------|
| No NULL dates | **PASS** | 0 NULL dates |
| Retention rates between 0 and 1 | **PASS** | D1: 0/306,352 out of range. D7: 0/303,271 out of range. D30: 0/298,311 out of range. |
| Retention ordering (D1 >= D7 >= D30 avg) | **PASS** | D1=1.16%, D7=0.58%, D30=0.04% — correct ordering |
| ROAS reasonable | **FAIL** | ALL ROAS values = 0.0. Zero rows where both COST > 0 AND TOTAL_REVENUE > 0. |
| CPI = COST / INSTALLS | **FAIL** | Zero rows where both COST > 0 AND ATTRIBUTION_INSTALLS > 0. CPI is NULL everywhere. |

**ROOT CAUSE (CRITICAL):**

The FULL OUTER JOIN between `spend_data` and `cohort_metrics` **never matches a single row**:

- **Spend side:** 9,136 rows, ALL with `PLATFORM = 'undefined'`
- **Cohort side:** 306,541 rows, ALL with `PLATFORM = 'iOS'`
- **Join condition** includes `LOWER(s.PLATFORM) = LOWER(c.PLATFORM)` → `'undefined' != 'ios'` → **zero matches**

The `stg_adjust__report_daily` model (spend source) has `PLATFORM = 'undefined'` in the dev build. The prod version (`DBT_ANALYTICS.DBT_ANALYTICS.STG_ADJUST__REPORT_DAILY`) has correct lowercase values (`ios`, `android`).

**Impact:** $2.57M in spend is completely disconnected from $4.2M in revenue. All derived metrics (CPI, ROAS, ARPI, ARPPU, cost-per-paying-user) are meaningless. The table has data but the two halves never connect.

**Additionally:** Cohort side is iOS-only (0 Android users). This means even with correct PLATFORM values, Android metrics would be missing from the cohort side.

---

### 3F. mart_campaign_performance_full_mta

**Schema:** `DBT_ANALYTICS.DBT_WGTDATA`
**Row Count:** 74,927

| Check | Result | Details |
|-------|--------|---------|
| All 6 attribution model columns present | **PASS** | All 74,927 rows have non-null values for all 6 models |
| All 6 attribution model columns non-null | **PASS** | 0 NULLs across all 6 install columns |
| Cross-check: ADJUST installs | **PASS (NOTE)** | ADJUST_INSTALLS = 1,915,648. MTA models: LT/FT/TD = 493,720, LIN = 493,720.14, PB = 493,017.40. The 3.9x gap is expected — many installs are organic/direct with no touchpoints. |
| Fan-out check | **PASS** | LT=FT=TD install totals match exactly. LIN and PB within expected tolerance. |
| ROAS / CPI cross-model | **FAIL** | Same PLATFORM mismatch as 3E. Spend side: PLATFORM = "undefined" (5,661 rows). Adjust/MTA side: PLATFORM = "iOS". Zero rows with both spend and installs. |

**ROOT CAUSE:** Same as 3E — `stg_adjust__report_daily` (dev build) has `PLATFORM = 'undefined'` while attribution data has `PLATFORM = 'iOS'`.

---

### 3G. Spend Marts

#### adjust_daily_performance_by_ad

**Schema:** `DBT_ANALYTICS.DBT_ANALYTICS` (prod)
**Row Count:** 969,955

| Check | Result | Details |
|-------|--------|---------|
| DATE >= '2025-01-01' filter | **PASS** | Min date: 2025-07-01, Max date: 2025-12-08. 0 pre-2025 rows. |

#### facebook_conversions

**Schema:** `DBT_ANALYTICS.DBT_ANALYTICS` (prod)
**Row Count:** 209,397

| Check | Result | Details |
|-------|--------|---------|
| No DIVIDEND = 0 rows | **PASS** | SPEND: 0 NULLs, IMPRESSIONS: 0 NULLs. CLICKS: 9,852 NULLs — this is from NULL CLICKS_RAW in source, not from DIVIDEND=0 division. |

---

## Recommendations Before Production Push

### Must Fix (Blockers)

1. **Fix `stg_adjust__report_daily` PLATFORM mapping.** The dev build has `PLATFORM = 'undefined'` for all rows. The prod version has correct values (`ios`, `android`). Ensure the dbt model properly maps the PLATFORM column from the Adjust API source. This single fix will unblock both `mart_campaign_performance_full` and `mart_campaign_performance_full_mta`.

2. **Fix `attribution__installs` grain.** COALESCE NULL CAMPAIGN_ID values (e.g., to `'unknown'`) or add a row-level identifier to the unique_key to prevent duplicate rows when CAMPAIGN_ID is NULL.

3. **Fix `attribution__network_performance` NULL AD_PARTNER.** Investigate why $1.02M in Supermetrics spend doesn't map to any AD_PARTNER. This may require adding missing entries to the network_mapping seed or fixing PARTNER_NAME standardization.

### Should Fix (Non-Blocking)

4. **Fix position-based credit for tied timestamps.** Add a secondary sort key (e.g., TOUCHPOINT_TYPE, CAMPAIGN_NAME) to the ROW_NUMBER() in `int_mta__user_journey` to make position assignment deterministic when timestamps are identical. Affects 0.3% of installs.

5. **Investigate high touchpoint counts.** Some installs have 25,500+ touchpoints from IP-based matching. Consider adding a cap or filtering out touchpoints from high-frequency IPs to reduce noise and improve query performance.

6. **Fix dev view compilation.** `V_STG_ADJUST__INSTALLS` in dev references `ADJUST_S3` database which doesn't exist. Recompile against correct `ADJUST.S3_DATA` target.

7. **Add Android users to cohort pipeline.** The cohort side of `mart_campaign_performance_full` is iOS-only (0 Android users). Verify that the `int_user_cohort__attribution` Android join (on GPS_ADID) is matching correctly.

### Acceptable As-Is

- Facebook CLICKS NULLs (9,852 rows) — source data has NULL CLICKS_RAW for some conversion types. Not a data quality issue.
- CPI outliers up to $204.90 — all from low-volume campaigns (1-2 installs). Expected for campaign ramp-up periods.
- Linear credit floating-point drift (493,720.14 vs 493,720) — negligible accumulation error.
- SKAN CV bucket total (232,544) < INSTALL_COUNT (268,933) — installs with NULL conversion values are correctly excluded from buckets.

---

## Environment Notes

- **Prod schema** (`DBT_ANALYTICS.DBT_ANALYTICS`): Last built 2026-02-03. Contains: staging views, `attribution__installs`, `attribution__campaign_performance`, `attribution__network_performance`, `mta__campaign_performance`, `adjust_daily_performance_by_ad`, `facebook_conversions`.
- **Dev schema** (`DBT_ANALYTICS.DBT_WGTDATA`): Various dates (Jan 26-27). Contains all models including `mart_campaign_performance_full` and `mart_campaign_performance_full_mta` which are NOT yet in prod.
- `mart_campaign_performance_full` exists in PROD schema (100,623 rows, Jan 12) but is an older build.
- `mart_campaign_performance_full_mta` does NOT exist in prod at all.
