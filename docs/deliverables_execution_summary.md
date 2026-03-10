# Deliverables Execution Summary

**Project**: WGT / Topgolf Mobile Game — Marketing Analytics dbt Platform
**Date**: 2026-03-09
**Environment**: Snowflake (`WGT.DBT_WGTDATA`) via dbt (62 SQL models + 2 seeds)

---

## Deliverable 1: Fivetran Integration

**Status**: Complete

Fivetran connectors for Facebook Ads and Google Ads are fully integrated as staging data sources. Seven Facebook staging models (`v_stg_facebook_spend`, `v_stg_facebook_accounts`, `v_stg_facebook_campaigns`, `v_stg_facebook_adsets`, `v_stg_facebook_ads`, `v_stg_facebook_conversions`, `v_stg_facebook_distinct_actions`) ingest from `FIVETRAN_DATABASE.FACEBOOK_ADS` and now use proper `{{ source() }}` refs via `_facebook__sources.yml`. Four Google Ads staging models (`v_stg_google_ads__spend`, `v_stg_google_ads__country_spend`, `v_stg_google_ads__accounts`, `v_stg_google_ads__campaigns`) ingest from `FIVETRAN_DATABASE.GOOGLE_ADS` via `_google_ads__sources.yml`.

Fivetran spend flows into `int_spend__unified`, which deduplicates overlapping Google campaign IDs between Adjust API and Fivetran (preferring Fivetran). Facebook spend covers web/desktop ad accounts with no overlap to Adjust mobile data, so both sources are included without dedup. The unified spend table feeds the MMM pipeline and daily business overview marts.

Facebook conversion actions are also surfaced through `facebook_conversions`, which allocates spend proportionally across action types using a DIVIDEND-based divisor.

---

## Deliverable 2: Custom API from Adjust — Pull Network-Level Aggregate Data (Impressions/Clicks)

**Status**: Complete

`stg_adjust__report_daily` is a staging view over `ADJUST.API_DATA.REPORT_DAILY_RAW`, which contains daily aggregate data pulled from the Adjust API. This replaced the prior Supermetrics integration. The model normalizes platform names (iOS/Android), strips trailing network IDs from campaign and adgroup names, and COALESCEs all numeric nulls to 0.

Columns include `IMPRESSIONS`, `CLICKS`, `NETWORK_COST` (spend), `INSTALLS`, `REVENUE`, `ALL_REVENUE`, `AD_REVENUE`, `SESSIONS`, `UNINSTALLS`, and `REATTRIBUTIONS` — all at the day/app/region/country/device_type/platform/partner/campaign/adgroup/creative grain. This is the primary spend source for all mobile networks and feeds directly into the exec summary, campaign performance, MTA, and MMM pipelines.

In addition to the API aggregate data, 26 Adjust S3 raw activity models partition the monolithic `IOS_EVENTS` and `ANDROID_EVENTS` tables by `ACTIVITY_KIND` (install, click, impression, session, etc.) for device-level analysis in the MTA and LTV pipelines.

---

## Deliverable 3: Attribution Modeling — Build & Test Web, Mobile, and Combo Attribution Models

**Status**: Complete

### Mobile MTA

The mobile multi-touch attribution pipeline runs from raw Adjust S3 touchpoints through to campaign-level performance:

1. **`v_stg_adjust__touchpoints`** — Unified clicks and impressions (iOS IDFA/IP + Android GPS_ADID matching)
2. **`int_mta__user_journey`** — Maps pre-install touchpoints to installs within a 7-day lookback window
3. **`int_mta__touchpoint_credit`** — Calculates five attribution model credits per touchpoint:
   - Last-Touch, First-Touch, Linear, Time-Decay (3-day half-life), Position-Based
4. **`mta__campaign_performance`** — Campaign-level fractional installs and D7/D30/Total revenue per model
5. **`mta__campaign_ltv`** — Extended LTV windows (D1/D7/D30/D180/D365/Total) per model

Known structural limitation: MTA covers ~4.5% of installs because self-attributing networks (Meta, Google, Apple, TikTok) share no touchpoint data with Adjust, and iOS IDFA availability is ~7% under ATT. The MMM pipeline is recommended for strategic budget allocation; MTA is preserved for iOS non-SAN tactical analysis.

### Web MTA

The web attribution pipeline attributes registrations to browser sessions using Amplitude's identity bridge:

1. **`int_web_mta__user_journey`** — Maps anonymous browser sessions to game registrations (30-day lookback)
2. **`int_web_mta__touchpoint_credit`** — Same five attribution models applied to web sessions
3. **`int_web_mta__user_revenue`** — Cross-platform revenue for web-acquired users (D7/D30/Total)
4. **`rpt__web_attribution`** — Campaign-level web traffic and registration attribution with revenue

### Combined Attribution

**`mart_attribution__combined`** stacks mobile MTA and web MTA into a single table via UNION ALL. Both pipelines use the same five models with identical methodology. An `ACQUISITION_TYPE` column ('mobile_install' vs 'web_registration') distinguishes the rows. Conversions are intentionally not deduplicated — a user counted in both pipelines appears in both rows, which is correct for channel-level attribution analysis. Efficiency metrics (CPI, ROAS) are computed from the recommended (time-decay) model.

### Testing

50+ dbt tests cover the attribution pipeline: uniqueness on composite keys, accepted values for platform columns, relationship tests between touchpoints and installs (with `severity: warn` for known SAN coverage gaps), and forward-looking date filters to catch stale data.

---

## Deliverable 4: Build Internal Cohorted Metric View

**Status**: Complete

The cohort pipeline produces user-level and campaign-level lifetime value metrics:

1. **`int_user_cohort__attribution`** — Links Amplitude user IDs to Adjust install attribution (one row per USER_ID + PLATFORM)
2. **`int_user_cohort__metrics`** — Comprehensive user-level metrics: revenue at D1/D7/D30/D180/D365/Lifetime windows, split by revenue type (IAP vs ad), retention flags at each window (via ROUNDSTARTED events), maturity flags, and payer flags. Incremental with a 370-day lookback to cover the full D365 window.
3. **`mart_ltv__cohort_summary`** — Cohort-level rollup at INSTALL_DATE / AD_PARTNER / CAMPAIGN / PLATFORM grain. Outputs LTV per matured user, payer rates, and retention rates at each window. This is the primary cohort analysis mart.
4. **`mart_exec_summary`** — Campaign-level executive view combining Adjust API spend, SKAN installs, Amplitude-attributed installs, and cohort revenue (D7/D30).

Audit validation confirmed revenue matches exactly against raw `WGT.EVENTS.REVENUE` across a 10-user sample (9/10 exact, 1 user with $0.06 delta explained by incremental window boundary).

---

## Deliverable 5: Build SKAN Event Aggregation Model

**Status**: Complete

The SKAN pipeline handles Apple's privacy-preserving SKAdNetwork postback data:

1. **`stg_adjust__ios_activity_sk_install`** — Filters sk_install events from iOS S3 data. Uses `COALESCE(SK_TRANSACTION_ID, NONCE)` for dedup since SANs (Meta, Google) don't provide transaction IDs.
2. **`int_skan__aggregate_attribution`** — Aggregates postbacks by partner/campaign/date. Produces install counts, new installs, redownloads, average conversion value, CV distribution buckets (0, 1-10, 11-20, 21-40, 41-63), fidelity types (StoreKit-rendered, view-through), win rates, and SKAN version distribution (v3/v4).
3. **`mart_skan__campaign_performance`** — Standalone SKAN mart joining aggregate postback data with iOS spend from the Adjust API. Computes SKAN-specific efficiency metrics (SKAN CPI, CPM, CTR, CVR) and fidelity metrics (win rate, StoreKit-rendered rate, CV coverage rate). Country is inferred from campaign name patterns (iOS_US_, WGT_AU_, etc.) since SKAN postbacks carry no country dimension. SANs are aggregated to partner/date level with campaign = '__none__' because their campaign names don't match Adjust spend data.

SKAN installs also flow into `mart_exec_summary` (as SKAN_INSTALLS) and `int_mmm__daily_channel_installs` (combined with S3 installs for a non-overlapping total).

---

## Deliverable 6: Hybrid Performance Views — Rollup Performance Across Creative, Ad Set & Campaign Levels

**Status**: Complete

The project delivers performance views at multiple levels of granularity:

### Creative & Ad Set Level
**`mart_campaign_performance_full`** is the most granular performance mart. It reports at the DATE / AD_PARTNER / CAMPAIGN / ADGROUP / CREATIVE grain with spend, impressions, clicks, Adjust installs, SKAN installs, attribution installs, CPI, CPM, CTR, CVR, IPM, D7/D30/Total revenue and ROAS, ARPI, ARPPU, and D1/D7/D30 retention rates. This enables drill-down from network → campaign → adgroup → creative.

### Campaign Level
- **`mart_exec_summary`** — Campaign-level executive view (removes adgroup/creative dimension) with spend, multi-source installs (API + SKAN + Amplitude), cohort revenue, and Power BI date grain columns
- **`mta__campaign_performance`** — Campaign-level MTA with all five attribution models and revenue windows
- **`mart_campaign_performance_full_mta`** — Side-by-side comparison of Adjust last-touch installs vs five MTA models at campaign level

### Network Level
- **`mart_network_performance_mta`** — Network-level rollup of MTA performance (AD_PARTNER + PLATFORM + DATE)

### Blended Cross-Platform
- **`mart_blended_performance`** — Unified channel/campaign/date grain combining mobile spend+installs alongside web sessions+registrations. Computes blended efficiency metrics (BLENDED_CPA, BLENDED_ROAS) that account for web value driven by mobile ad spend. Includes HAS_MOBILE_DATA and HAS_WEB_DATA flags for filtering.

### Daily Overview
- **`mart_daily_business_overview`** — Top-line daily KPIs across all platforms
- **`mart_daily_overview_by_platform`** — Daily KPIs broken down by platform (iOS, Android, Desktop) and country

### Power BI Integration
- **`mart_exec_summary_measures`** — DAX-compatible scaffold view passing through only additive columns (ratios excluded to prevent incorrect aggregation)
- **`mart_daily_overview_by_platform_measures`** — Single-row anchor table for DAX measure context

---

## Summary

| # | Deliverable | Status | Key Models |
|---|-------------|--------|------------|
| 1 | Fivetran Integration | Complete | 7 Facebook + 4 Google staging models, `_facebook__sources.yml`, `_google_ads__sources.yml` |
| 2 | Adjust API (Impressions/Clicks) | Complete | `stg_adjust__report_daily` + 26 S3 activity models |
| 3 | Attribution Modeling (Web + Mobile + Combined) | Complete | Mobile MTA (4 models), Web MTA (4 models), `mart_attribution__combined` |
| 4 | Internal Cohorted Metric View | Complete | `int_user_cohort__metrics`, `mart_ltv__cohort_summary`, `mart_exec_summary` |
| 5 | SKAN Event Aggregation | Complete | `int_skan__aggregate_attribution`, `mart_skan__campaign_performance` |
| 6 | Hybrid Performance Views (Creative → Campaign → Network) | Complete | `mart_campaign_performance_full`, `mart_blended_performance`, `mart_network_performance_mta` |

All six deliverables are fully implemented, tested, and documented. The 62-model dbt project is audited (`docs/audit_data_reconciliation.md`) with a comprehensive data dictionary (`docs/WGT_Data_Dictionary.md`).
