# Data Reconciliation Audit Report

**Run date**: 2026-03-06
**Data window**: 2025-01-01 through 2026-03-06
**Source**: All queries run against `WGT.DBT_WGTDATA` (Snowflake PROD)

---

## Executive Summary

This audit traces every mart's spend, installs, and revenue metrics back to raw sources and quantifies discrepancies.

**Key findings**:

1. **Spend, revenue, and installs all reconcile to raw sources** — no active double-counting across marts
2. **Desktop/web revenue accounts for ~23% of total daily revenue** ($13.3K/day avg), attributed to channels via web multi-touch attribution
3. **Adjust API reports $0 ad revenue** — not configured for ad revenue reporting. WGT.EVENTS captures ~$9.7K/day of mobile ad revenue that Adjust misses entirely
4. **CPI varies across marts by design** — different install denominators (API+SKAN vs Amplitude attribution) produce different but internally consistent metrics
5. **Raw-to-staging integrity is clean**: Adjust, Facebook, and Google spend all pass with zero deltas

**30-day averages** (from `mart_daily_business_overview`):

| Metric | Value |
|--------|-------|
| Total Spend | $20,793/day (Mobile: $16,277 + Desktop: $4,516) |
| Total Revenue | $58,306/day |
| ROAS | 3.82x |
| Blended CPI | $2.66 |
| DAU | 107,540 |
| ARPDAU | $0.542 |

---

## 1. SPEND RECONCILIATION

### 1.1 Cross-Mart Spend Comparison

| Date | Exec Summary | Biz Mobile | Biz Desktop | Biz Total | Platform Overview | MMM (unified) |
|------|-------------|-----------|------------|----------|------------------|---------------|
| 2026-03-04 | $15,666 | $15,666 | $4,761 | $20,427 | $16,997 | $20,427 |
| 2026-03-03 | $15,316 | $15,316 | $4,771 | $20,086 | $16,691 | $20,086 |
| 2026-03-02 | $17,007 | $17,007 | $4,426 | $21,434 | $18,237 | $21,434 |

**How spend flows**:

- **Exec Summary** = Adjust API `NETWORK_COST` (mobile campaigns only)
- **Biz Mobile** = Same Adjust API source. Confirmed identical to Exec.
- **Biz Desktop** = Fivetran Facebook + Google via `int_spend__unified` (~$4.5K/day avg)
- **Biz Total** = Mobile + Desktop. Matches MMM unified spend exactly.
- **Platform Overview** = Adjust (all platforms) + Fivetran Facebook + Fivetran Google (desktop only). Slightly lower than Biz Total because `int_spend__unified` deduplicates overlapping Google campaigns that Adjust also reports.
- **MMM** = `int_spend__unified` — deduplicates Adjust vs Fivetran at the campaign ID level.

### 1.2 Unified Spend Composition

| Source | Total Spend | % of Total |
|--------|------------|------------|
| Adjust API | $7,126,314 | 76.2% |
| Fivetran Google | $1,875,079 | 20.1% |
| Fivetran Facebook | $346,021 | 3.7% |
| **Total** | **$9,347,414** | 100% |

### 1.3 Raw-to-Staging Integrity

| Source | Result |
|--------|--------|
| Adjust API (`REPORT_DAILY_RAW` vs `stg_adjust__report_daily`) | **CLEAN** — 0 rows with delta > $0.01 |
| Facebook (`ADS_INSIGHTS` vs `v_stg_facebook_spend`) | **CLEAN** — 0 rows with delta > $0.01 |
| Google Ads (`CAMPAIGN_STATS` vs `v_stg_google_ads__spend`) | **CLEAN** — totals match to the penny ($1,875,079) |

### 1.4 Google Campaign Overlap Handling

39 Google campaigns exist in both Adjust and Fivetran data (same campaign IDs). These are mobile campaigns (iOS/Android) that Google's API also reports.

**Current handling**:
- `mart_daily_overview_by_platform`: Fivetran Google spend is filtered to `PLATFORM = 'Desktop'` only, so these 39 mobile campaigns do not appear in the desktop spend rows. No double-counting.
- `int_spend__unified` (MMM, biz overview desktop): Deduplicates by campaign ID — Fivetran preferred where IDs overlap, Adjust fills the rest.

### 1.5 Google Country Code +2000 Mapping

All 18 country criterion IDs in the Google Ads data correctly map using the +2000 offset. **No mismatches found.**

---

## 2. INSTALLS RECONCILIATION

### 2.1 Cross-Mart Install Comparison

| Date | API (Exec) | SKAN | API+SKAN | Attribution | Biz Overview | MMM |
|------|-----------|------|----------|-------------|-------------|-----|
| 2026-03-04 | 8,397 | 0 | 8,397 | 0 | 8,397 | 8,360 |
| 2026-03-03 | 8,555 | 349 | 8,904 | 5,389 | 8,555 | 8,533 |
| 2026-03-02 | 9,854 | 1,351 | 11,205 | 6,425 | 9,854 | 9,827 |
| 2026-03-01 | 11,616 | 1,536 | 13,152 | 7,876 | 11,616 | 11,599 |
| 2026-02-28 | 11,785 | 1,343 | 13,128 | 7,690 | 11,785 | 11,762 |

**How installs flow**:

- **API (Adjust)** = Includes reinstalls. Used by Exec Summary and Biz Overview.
- **SKAN** = iOS only, SKAN 3.0 postbacks. Zero on recent days means postbacks haven't arrived yet.
- **API+SKAN** = Combined install count for Exec Summary CPI calculations.
- **Attribution** = Amplitude device-mapped users (~60-65% of API). Smaller because it requires SDK event sync and deduplicates to distinct user IDs.
- **MMM** = Adjust API installs carried through from `stg_adjust__report_daily`. Slightly lower than API due to the iOS/Android platform filter.

### 2.2 CPI Across Marts

Each mart uses a different install denominator, so CPI varies by design:

| Mart | CPI Formula | Example (2026-03-01) |
|------|------------|---------------------|
| `mart_exec_summary` | Cost / (API + SKAN) | $17,991 / 13,152 = **$1.37** |
| `mart_campaign_perf_full` | Cost / Attribution | $17,991 / 7,876 = **$2.28** |
| `mart_daily_business_overview` | Total Spend / API | $21,434 / 11,616 = **$1.85** |

The expected ordering holds: **API > MMM > Attribution** installs.

---

## 3. REVENUE RECONCILIATION

### 3.1 Cross-Mart Revenue Comparison

| Date | Exec (Adjust API) | Biz (WGT.EVENTS) | Platform | MMM Total | MMM Desktop |
|------|-------------------|-------------------|----------|-----------|-------------|
| 2026-03-04 | $35,022 | $56,696 | $56,696 | $47,666 | $12,761 |
| 2026-03-03 | $37,626 | $58,052 | $58,052 | $50,069 | $12,632 |
| 2026-03-02 | $31,180 | $48,052 | $48,052 | $41,152 | $10,102 |
| 2026-03-01 | $39,425 | $61,156 | $61,156 | $52,704 | $13,426 |
| 2026-02-28 | $45,026 | $66,699 | $66,699 | $60,006 | $15,281 |

**How revenue flows**:

- **Exec Summary** (`ADJUST_ALL_REVENUE`): Adjust API `ALL_REVENUE` — mobile event-date revenue. Does not include ad revenue (see 3.3).
- **Biz Overview** (`ALL_PLATFORM_REVENUE`): WGT.EVENTS all platforms, event-date. Confirmed identical to Platform Overview.
- **Platform Overview** (`ALL_PLATFORM_REVENUE`): Same WGT.EVENTS source, split by platform and country.
- **MMM** (`ALL_REVENUE`): Mobile from Adjust API + Desktop from WGT.EVENTS attributed via web MTA. Total is between Exec and Biz because it uses Adjust for mobile (lower than WGT.EVENTS due to missing ad revenue) plus WGT.EVENTS for desktop.

### 3.2 Revenue Column Naming

Each mart's primary revenue column is named to reflect its actual source:

| Mart | Column | Definition |
|------|--------|-----------|
| `mart_exec_summary` | `ADJUST_ALL_REVENUE` | Adjust API ALL_REVENUE (mobile, event-date) |
| `mart_campaign_perf_full` | `COHORT_LIFETIME_REVENUE` | Cohort lifetime from WGT.EVENTS (mobile, install-date) |
| `mart_daily_business_overview` | `ALL_PLATFORM_REVENUE` | WGT.EVENTS all platforms (event-date) |
| `mart_daily_overview_by_platform` | `ALL_PLATFORM_REVENUE` | WGT.EVENTS all platforms (event-date, by platform+country) |

### 3.3 Adjust API vs WGT.EVENTS Mobile Revenue

| Metric | Adjust API (30d avg) | WGT.EVENTS (30d avg) | Daily Delta |
|--------|---------------------|---------------------|-------------|
| ALL_REVENUE | $35,440 | $45,109 | +$9,670 |
| Purchase revenue | $35,440 | $35,358 | -$82 |
| Ad revenue | **$0** | $9,751 | +$9,751 |

**Key insight**: Purchase revenue matches closely between both sources (<1% variance). The entire gap comes from **ad revenue** — Adjust API reports `AD_REVENUE = $0.00` (not configured for ad revenue reporting), while WGT.EVENTS captures ~$9.7K/day of `indirect` (ad) revenue from in-game ad monetization. This is a known Adjust configuration limitation, not a data pipeline issue.

### 3.4 MMM Desktop Revenue Attribution

Desktop revenue in the MMM pipeline is attributed to channels using the web multi-touch attribution (MTA) model. The MTA pipeline links anonymous pre-registration browser sessions to registrations via Amplitude's identity bridge, then distributes revenue across channels using time-decay credit weights. Paid channels are identified by GCLID (Google) and FBCLID (Meta).

| Channel | Revenue (since 2025-01) | % of Desktop |
|---------|------------------------|------|
| Organic | $3,013,549 | 52.5% |
| Unattributed | $2,455,133 | 42.7% |
| Google (paid) | $241,179 | 4.2% |
| Meta (paid) | $34,278 | 0.6% |

**Why 42.7% is Unattributed**: 15,790 desktop revenue users (of 30,217 total) have no web MTA data. Breakdown:
- **Legacy users** (60% of unattributed revenue): 9,106 users registered before web MTA tracking existed (pre-2024)
- **Steam/Amazon users** (22%): 4,675 users registered through Steam or Amazon storefronts, not the wgt.com website — no browser session trail
- **Other** (18%): Users who registered in a single session (no anonymous→identified transition), disabled JavaScript, or had other identity resolution gaps

### 3.5 Platform Revenue Breakdown (30-day avg)

| Platform | Avg Daily Revenue | Avg Daily Spend | Notes |
|----------|------------------|----------------|-------|
| iOS | $28,662 | $11,393 | Largest revenue and spend |
| Android | $16,295 | $4,884 | |
| Desktop | $10,994 | $1,283 | Spend from Fivetran FB+Google desktop only |
| Steam | $1,087 | $0 | No paid acquisition |
| Amazon | $833 | $0 | No paid acquisition |
| Web | $435 | $0 | No paid acquisition |

---

## 4. KNOWN LIMITATIONS

### Monitor

| # | Item | Detail |
|---|------|--------|
| 1 | **CPI varies 66% across marts** | Different install denominators — by design. Exec uses API+SKAN, Campaign Perf uses Amplitude attribution. |
| 2 | **Adjust API ad revenue is $0** | Not configured for ad revenue reporting. WGT.EVENTS captures ~$9.7K/day that Adjust misses. No pipeline fix possible — requires Adjust account configuration. |
| 3 | **43% of desktop revenue unattributed** | Legacy + Steam/Amazon users without web MTA data. Structurally correct — no web session trail to attribute. |
| 4 | **API+SKAN overlap risk in exec summary** | API may include ATT-consented iOS users also counted in SKAN postbacks. Low impact. |

### Validated — No Issues

| Check | Result |
|-------|--------|
| Raw-to-staging Adjust spend | Exact match |
| Raw-to-staging Facebook spend | Exact match |
| Raw-to-staging Google spend | Exact match |
| Google +2000 country code mapping | All 18 codes match |
| Biz Total Spend = MMM Unified Spend | Confirmed identical |
| Biz Revenue = Platform Revenue | Confirmed identical |
| MMM desktop revenue vs raw WGT.EVENTS | Exact match ($0 diff across $5.7M) |
| Column renames verified in Snowflake | All 4 marts confirmed |

---

## 5. MART ARCHITECTURE REFERENCE

### Spend Sources by Mart

| Mart | Mobile Spend | Desktop Spend |
|------|-------------|--------------|
| `mart_exec_summary` | Adjust API | — |
| `mart_daily_business_overview` | Adjust API | `int_spend__unified` (Fivetran FB + Google) |
| `mart_daily_overview_by_platform` | Adjust API | Fivetran FB + Google (desktop-filtered) |
| `int_spend__unified` (MMM) | Adjust API (deduped) | Fivetran FB + Google |

### Revenue Sources by Mart

| Mart | Mobile Revenue | Desktop Revenue |
|------|---------------|----------------|
| `mart_exec_summary` | Adjust API ALL_REVENUE | — |
| `mart_campaign_perf_full` | WGT.EVENTS (cohort, install-date) | — |
| `mart_daily_business_overview` | WGT.EVENTS (event-date) | WGT.EVENTS (event-date) |
| `mart_daily_overview_by_platform` | WGT.EVENTS (event-date) | WGT.EVENTS (event-date) |
| `int_mmm__daily_channel_revenue` | Adjust API (event-date) | WGT.EVENTS + Web MTA attribution |

### Install Sources by Mart

| Mart | Primary | Secondary |
|------|---------|-----------|
| `mart_exec_summary` | Adjust API + SKAN | Amplitude attribution |
| `mart_campaign_perf_full` | Adjust API | Amplitude attribution |
| `mart_daily_business_overview` | Adjust API | — |
| `int_mmm__daily_channel_revenue` | Adjust API (mobile only) | — |

---

## Appendix: Reconciliation Queries

All reconciliation SQL files are in `analyses/reconciliation/`:

| File | Description |
|------|------------|
| `reconciliation_01_cross_mart_spend.sql` | Spend comparison across all marts |
| `reconciliation_02_raw_vs_staging_adjust_spend.sql` | Adjust raw → staging integrity |
| `reconciliation_03_raw_vs_staging_facebook_spend.sql` | Facebook raw → staging integrity |
| `reconciliation_04_raw_vs_staging_google_spend.sql` | Google raw → staging integrity |
| `reconciliation_05_unified_spend_breakdown.sql` | Unified spend source composition |
| `reconciliation_06_cross_mart_installs.sql` | Install comparison across marts |
| `reconciliation_07_api_vs_s3_installs.sql` | API vs S3 install delta (reinstalls) |
| `reconciliation_08_cross_mart_revenue.sql` | Revenue comparison across marts |
| `reconciliation_09_adjust_vs_wgt_revenue.sql` | Adjust API vs WGT.EVENTS revenue |
| `reconciliation_10_google_campaign_overlap.sql` | Google campaign overlap audit |
| `reconciliation_11_google_country_code_validation.sql` | Google +2000 country code check |
