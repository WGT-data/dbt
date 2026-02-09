# dbt Model Validation Report

**Date:** 2026-02-06
**Database:** DBT_ANALYTICS
**Schema:** DBT_WGTDATA (dev)
**Warehouse:** DBT_ATTRIBUTION_WH

---

## Summary

| Metric | Count |
|--------|------:|
| Models Checked | 20 |
| Total Checks | 61 |
| PASS | 30 |
| FAIL | 4 |
| WARN | 3 |
| INFO | 22 |
| SKIP | 1 |
| ERROR (resolved) | 1 |

### Issues by Severity

| # | Severity | Model | Issue |
|---|----------|-------|-------|
| 1 | **FAIL** | `STG_SUPERMETRICS__ADJ_CAMPAIGN` | PLATFORM not standardized — 15 platforms including webos, apple-tv, server, etc. |
| 2 | **FAIL** | `ATTRIBUTION__CAMPAIGN_PERFORMANCE` | CPI outliers — 10 rows with CPI > $100 (Google Android up to $3,504) |
| 3 | **FAIL** | `INT_MTA__TOUCHPOINT_CREDIT` | POSITION_BASED credit sums to 0.5 for single-touchpoint installs |
| 4 | **FAIL** | `V_STG_AMPLITUDE__MERGE_IDS` | One-to-many mapping — some devices map to 2 users |
| 5 | **WARN** | `INT_MTA__USER_JOURNEY` | Max touchpoints = 25,500 per install (extreme outlier) |
| 6 | **WARN** | `ATTRIBUTION__NETWORK_PERFORMANCE` | $1M+ spend with NULL AD_PARTNER and 0 installs |
| 7 | **WARN** | `MART_CAMPAIGN_PERFORMANCE_FULL` | 1,706 rows where D1 retention < D7 or D7 < D30 |

---

## Layer 1: Staging Views

### 1A. V_STG_ADJUST__INSTALLS

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 1,398,993 (iOS: 1,396,020 + Android: 12,371 sources; staging dedupes) |
| Dedup (DEVICE_ID + PLATFORM) | **PASS** | No duplicate DEVICE_ID + PLATFORM combinations |
| NULL filtering | **PASS** | 0 NULL DEVICE_ID, 0 NULL INSTALL_TIMESTAMP |
| AD_PARTNER mapping | INFO | Top partners: Organic (848K), Unity (114K), Moloco (67K), AppLovin (67K), Apple (60K) |
| CAMPAIGN_ID extraction | INFO | Spot-checked — CAMPAIGN_ID parsed correctly from CAMPAIGN_NAME |

### 1B. V_STG_ADJUST__TOUCHPOINTS

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 987,103,259 |
| Platform/Type distribution | **PASS** | iOS impressions: 860M, iOS clicks: 115M, Android impressions: 6.8M, Android clicks: 4.1M |
| Epoch filter (TOUCHPOINT_EPOCH >= 1704067200) | **PASS** | 0 rows before cutoff |

### 1C. V_STG_AMPLITUDE__MERGE_IDS

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 5,655,598 |
| One-to-many mapping | **FAIL** | 20+ devices map to 2 users. Samples: `88E40760` (Android, 2 users), `91BF2742` (iOS, 2 users) |
| Android R-suffix stripped | **PASS** | 0 devices ending in 'R' |
| DEVICE_ID_UUID uppercase | **PASS** | All uppercase |

**Note:** The one-to-many issue means a small number of devices are associated with multiple user accounts (likely shared devices or account switches). This is expected at low volume but should be monitored.

### 1D. V_STG_AMPLITUDE__EVENTS

| Check | Result | Detail |
|-------|--------|--------|
| Existence | **SKIP** | Model deleted — replaced with direct source queries to WGT.EVENTS.REVENUE, WGT.EVENTS.ROUNDSTARTED, and Amplitude EVENTS_726530 |

### 1E. V_STG_REVENUE__EVENTS

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 1,305,889 |
| Date filter (>= 2025-01-01) | **PASS** | 0 rows before 2025 |
| NULL REVENUE_AMOUNT | **PASS** | 0 nulls out of 1,305,889 |

### 1F. STG_SUPERMETRICS__ADJ_CAMPAIGN

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 1,209,260 |
| Platform standardization | **FAIL** | 15 platforms found: iOS (730K), Android (418K), macos (22K), windows (15K), unknown (10K), server (6.9K), linux (3.1K), android-tv (1.9K), fire-tv, apple-tv, webos, tizen, playstation, roku-os, xbox |
| Dedup check | INFO | Distinct key combos checked |

**Root cause:** The Supermetrics source includes data for all platforms in WGT Golf, not just mobile. The staging model should filter to only 'iOS' and 'Android' if downstream models assume mobile-only, OR downstream models need to handle the full platform set.

**Impact:** Non-mobile platforms flow through to `ATTRIBUTION__NETWORK_PERFORMANCE` causing $1M+ in spend attributed to NULL AD_PARTNER with 0 installs.

### 1G. Facebook Staging Views

| Check | Result | Detail |
|-------|--------|--------|
| V_STG_FACEBOOK_SPEND row count | **PASS** | 18,358 rows |
| V_STG_FACEBOOK_CONVERSIONS DIVIDEND=0 | **PASS** | 0 rows with DIVIDEND=0 |

---

## Layer 2: Intermediate Models

### 2A. INT_ADJUST_AMPLITUDE__DEVICE_MAPPING

| Check | Result | Detail |
|-------|--------|--------|
| Row count vs merge_ids | **PASS** | 5,573,414 vs 5,655,598 (ratio: 0.99) |
| Uniqueness (ADJUST_DEVICE_ID + AMPLITUDE_USER_ID + PLATFORM) | **PASS** | No duplicates |

### 2B. INT_MTA__USER_JOURNEY

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 15,216,039 |
| 7-day lookback window | **PASS** | 0 touchpoints linked >7 days before install |
| Touchpoint count per install | **WARN** | Max = 25,500 touchpoints for a single install. Distribution: 25,500 (25,500 rows), 25,265 (50,530), 21,248, 10,506, 10,302. These are extreme outliers — likely bot/fraud traffic. |
| IS_FIRST_TOUCH / IS_LAST_TOUCH flags | **PASS** | Exactly 1 first and 1 last touch per install |

### 2C. INT_MTA__TOUCHPOINT_CREDIT

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 15,216,039 |
| Credit sums to ~1.0 | **FAIL** | Position-based credit sums to 0.5 for 2-touchpoint installs. All samples show PB_SUM = 0.5000 with TP_COUNT = 2. |
| CREDIT_LAST_TOUCH correct | **PASS** | 1.0 only for last touchpoint, 0 otherwise |
| CREDIT_FIRST_TOUCH correct | **PASS** | 1.0 only for first touchpoint, 0 otherwise |

**Root cause:** Position-based attribution assigns 40% to first touch, 40% to last touch, and 20% split among middle touchpoints. For 2-touchpoint journeys where a touchpoint is both first AND last (or where first and last overlap), the formula doesn't correctly distribute the full 1.0 credit.

**Note:** Last-touch, first-touch, and linear models all sum correctly. Time-decay is close. Only position-based has this issue, and only for 2-touchpoint installs.

### 2D. INT_SKAN__AGGREGATE_ATTRIBUTION

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 6,097 |
| No device-level identifiers | **PASS** | No IDFV, IDFA, GPS_ADID, or DEVICE_ID columns |
| Grain uniqueness (AD_PARTNER + CAMPAIGN_NAME + INSTALL_DATE) | **PASS** | No duplicates |
| CV bucket totals | INFO | Bucket total: 232,544 vs Install total: 268,933 — gap of 36,389 installs without conversion values (expected for null CVs) |

### 2E. INT_USER_COHORT__ATTRIBUTION

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 1,933,636 |
| Uniqueness (USER_ID + PLATFORM) | **PASS** | No duplicates |
| USER_ID match rate | INFO | 100.0% (all rows have a USER_ID) |

### 2F. INT_USER_COHORT__METRICS

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 4,442,769 |
| D1_RETAINED binary (0/1) | **PASS** | Values: [0, 1] |
| D7_RETAINED binary (0/1) | **PASS** | Values: [0, 1] |
| D30_RETAINED binary (0/1) | **PASS** | Values: [0, 1] |
| Revenue monotonicity (D7 <= D30 <= Total) | **PASS** | 0 violations |
| Maturity flags (D7_MATURED only if install 7+ days old) | **PASS** | 0 violations |

### 2G. INT_REVENUE__USER_SUMMARY

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 121,457 |
| No negative TOTAL_REVENUE | **PASS** | 0 violations |
| PURCHASE_COUNT >= 0 | **PASS** | 0 violations |

---

## Layer 3: Marts

### 3A. ATTRIBUTION__INSTALLS

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 513,911 |
| Grain uniqueness | **PASS** | Unique on full key (AD_PARTNER + NETWORK_NAME + CAMPAIGN_NAME + CAMPAIGN_ID + ADGROUP_NAME + ADGROUP_ID + PLATFORM + INSTALL_DATE) |
| No NULL AD_PARTNER | **PASS** | 0 rows with NULL AD_PARTNER |

### 3B. ATTRIBUTION__CAMPAIGN_PERFORMANCE

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 60,846 |
| Spend match vs Supermetrics | **PASS** | Campaign perf: $2,568,623 vs Supermetrics: $2,568,623 (exact match) |
| CPI sanity | **FAIL** | 10 rows with CPI > $100. All are Google Android or Meta Android with 1-2 installs and high daily spend ($1K-$3.5K). Google Android CPI up to $3,504. |

**Root cause:** Google and Meta Android campaigns are relatively new/small. Daily spend is allocated to very few installs, resulting in extremely high CPI values. These are likely campaign ramp-up periods or attribution gaps (spend tracked but installs not yet matched).

### 3C. ATTRIBUTION__NETWORK_PERFORMANCE

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 21,442 |
| Spend total | INFO | $2,568,623 (matches campaign performance) |
| Spend without installs | **WARN** | NULL AD_PARTNER on iOS ($248K) and Android ($766K) with 0 installs. Also NULL on 13 other platforms (macos, windows, linux, etc.) with $0 spend. |

**Root cause:** Downstream effect of `STG_SUPERMETRICS__ADJ_CAMPAIGN` including non-mobile platforms. Spend data exists for platforms where Adjust doesn't track installs.

### 3D. MTA__CAMPAIGN_PERFORMANCE

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 17,840 |
| Attribution columns non-null | **PASS** | LT=0, FT=0, LIN=0, TD=0, PB=0 null values |
| Model totals comparison | INFO | LT: 493,720 / TD: 493,720 / LIN: 493,720 — all models produce identical total installs (expected: they redistribute credit, not create/destroy it) |

### 3E. MART_CAMPAIGN_PERFORMANCE_FULL

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 2,866,339 |
| No NULL dates | **PASS** | 0 rows with NULL DATE |
| CPI calculation | **PASS** | Spot-checked 10 rows — CPI = COST / ATTRIBUTION_INSTALLS matches stored values |
| Retention rate ordering | **WARN** | 1,706 rows where D1_RETENTION < D7_RETENTION or D7_RETENTION < D30_RETENTION. Avg retention: D1=1.16%, D7=0.58%, D30=0.04%. On average the ordering is correct but individual rows can violate at small sample sizes. |
| ROAS range | INFO | Min: 0.0, Max: 223.9, Avg: 0.003. Max of 223x is extreme but possible for low-spend high-revenue campaigns. |
| Spend match | **PASS** | Matches Supermetrics source exactly |

### 3F. MART_CAMPAIGN_PERFORMANCE_FULL_MTA

| Check | Result | Detail |
|-------|--------|--------|
| Row count | INFO | 74,927 |
| MTA columns present | **PASS** | 91 MTA columns covering all 5 attribution models across installs, CPI, revenue, ROAS, payers, and retention |
| Install fan-out check | INFO | ADJ: 1,915,648 / MTA LT: 493,720 / MTA TD: 493,720. MTA covers ~25% of Adjust installs (expected: MTA only covers installs with matched touchpoints) |

### 3G. Spend Marts

| Check | Result | Detail |
|-------|--------|--------|
| ADJUST_DAILY_PERFORMANCE_BY_AD date filter | **PASS** | Located in `DBT_ANALYTICS.DBT_ANALYTICS` schema. 0 rows before 2025-01-01 |
| FACEBOOK_CONVERSIONS | INFO | 206,622 rows. No DIVIDEND column present (schema changed). 1,194 rows with ALLCONV = 0. |

---

## Recommendations

### Critical (Fix Before Production)

1. **Position-Based Attribution Edge Case** (`INT_MTA__TOUCHPOINT_CREDIT`): Fix the position-based credit formula for 2-touchpoint journeys. Currently sums to 0.5 instead of 1.0. The formula should handle the case where a touchpoint is both first AND last (single touchpoint) or where there are exactly 2 touchpoints (each gets 0.5).

### High Priority

2. **Supermetrics Platform Filter** (`STG_SUPERMETRICS__ADJ_CAMPAIGN`): Add a `WHERE PLATFORM IN ('iOS', 'Android')` filter to exclude non-mobile platforms, OR update downstream models to handle the full platform set. Currently causes $1M+ in orphaned spend in network performance tables.

3. **CPI Outliers** (`ATTRIBUTION__CAMPAIGN_PERFORMANCE`): Consider adding guardrails for CPI > $100 (cap, flag, or exclude). Google Android campaigns show CPI up to $3,504 which distorts averages.

### Medium Priority

4. **Merge ID One-to-Many** (`V_STG_AMPLITUDE__MERGE_IDS`): ~20 devices map to multiple users. Consider adding dedup logic (e.g., keep the most recent user mapping) to prevent potential fan-out in downstream revenue/retention calculations.

5. **Extreme Touchpoint Counts** (`INT_MTA__USER_JOURNEY`): Some installs have 25,500 touchpoints. Consider adding a cap (e.g., max 500 touchpoints per install) to prevent these outliers from skewing attribution calculations and causing performance issues.

6. **Retention Rate Ordering** (`MART_CAMPAIGN_PERFORMANCE_FULL`): 1,706 rows violate D1 >= D7 >= D30 ordering. This is mathematically possible at small sample sizes (a user retained at D7 but not D1) but may confuse dashboard consumers. Consider adding a note or handling in the BI layer.

### Low Priority

7. **SKAN CV Bucket Gap** (`INT_SKAN__AGGREGATE_ATTRIBUTION`): 36,389 installs (13.5%) have no conversion value — this is expected Apple behavior for privacy-limited postbacks.

8. **Facebook ALLCONV Zeros** (`FACEBOOK_CONVERSIONS`): 1,194 rows with ALLCONV = 0. Low impact but worth monitoring.
