# WGT / Topgolf Mobile Game Analytics — Data Dictionary

**Project**: wgt-dbt
**Platform**: Snowflake + dbt
**Last Updated**: 2026-03-09
**Total Models**: 62 SQL models + 2 seeds

---

## Table of Contents

1. [Overview & Data Flow](#1-overview--data-flow)
2. [Raw Data Sources](#2-raw-data-sources)
3. [Staging Models](#3-staging-models)
4. [Intermediate Models](#4-intermediate-models)
5. [Mart Endpoints](#5-mart-endpoints)
6. [Seeds](#6-seeds)
7. [Known Limitations Summary](#7-known-limitations-summary)

---

## 1. Overview & Data Flow

This dbt project powers the marketing analytics data platform for WGT (World Golf Tour) / Topgolf mobile game. It ingests raw event streams and ad platform reports, transforms them through staging and intermediate layers, and surfaces mart tables consumed by Power BI dashboards and the marketing science team.

**Five major analytical pipelines run through this project:**

| Pipeline | Purpose |
|---|---|
| **MMM** (Media Mix Modeling) | Unified spend + installs + revenue at DATE/PLATFORM/CHANNEL grain for econometric modeling |
| **LTV** (Lifetime Value) | Cohort-based revenue windows (D1/D7/D30/D180/D365) per user, anchored to install date |
| **Mobile MTA** (Multi-Touch Attribution) | Fractional install credit across touchpoints; iOS IDFA-only due to ATT limits |
| **Web MTA** | UTM/referrer attribution for web-to-app registrations via Amplitude session data |
| **Cohort** | User-level retention and revenue metrics for campaign performance reporting |

### ASCII Lineage Diagram

```
RAW SOURCES
══════════════════════════════════════════════════════════════════════
  ADJUST.S3_DATA          ADJUST.API_DATA       AMPLITUDE
  ├── IOS_EVENTS          └── REPORT_DAILY_RAW  ├── EVENTS_726530
  └── ANDROID_EVENTS                            └── MERGE_IDS_726530

  FIVETRAN_DATABASE                             WGT
  ├── FACEBOOK_ADS                              ├── PROD.DIRECT_REVENUE_EVENTS
  │   ├── ADS_INSIGHTS                          └── EVENTS.*
  │   └── ADS_INSIGHTS_ACTIONS                      (REVENUE, ROUNDSTARTED,
  └── GOOGLE_ADS                                     ROUNDENDED, etc.)
      ├── CAMPAIGN_STATS
      ├── CAMPAIGN_COUNTRY_REPORT
      ├── CAMPAIGN_HISTORY
      └── ACCOUNT_HISTORY

        │
        ▼
STAGING
══════════════════════════════════════════════════════════════════════
  Adjust API           Adjust S3 (26 pass-through activity models)
  └── stg_adjust__report_daily
                       ├── v_stg_adjust__installs     (unified iOS+Android)
                       ├── v_stg_adjust__touchpoints  (MTA clicks+impressions)
                       └── stg_adjust__ios_activity_sk_install (SKAN)

  Facebook Ads         Google Ads           Amplitude          Revenue
  ├── v_stg_facebook_spend        ├── v_stg_google_ads__spend    ├── v_stg_amplitude__user_attribution
  ├── v_stg_facebook_accounts     ├── v_stg_google_ads__country_spend ├── v_stg_amplitude__merge_ids
  ├── v_stg_facebook_campaigns    ├── v_stg_google_ads__accounts └── v_stg_revenue__events
  ├── v_stg_facebook_adsets       └── v_stg_google_ads__campaigns
  ├── v_stg_facebook_ads
  ├── v_stg_facebook_conversions
  └── v_stg_facebook_distinct_actions

        │
        ▼
INTERMEDIATE
══════════════════════════════════════════════════════════════════════
  Spend Pipeline           Install Pipeline         Revenue Pipeline
  └── int_spend__unified   └── int_mmm__daily_      └── int_mmm__daily_
  └── int_mmm__daily_          channel_installs         channel_revenue
      channel_spend

  SKAN Pipeline            User Cohort Pipeline     Device Mapping
  └── int_skan__            ├── int_user_cohort__   └── int_adjust_amplitude__
      aggregate_attribution     attribution              device_mapping
                           └── int_user_cohort__
                               metrics

  Mobile MTA Pipeline      Web MTA Pipeline         LTV Pipeline
  ├── int_mta__user_journey ├── int_web_mta__        └── int_ltv__device_revenue
  └── int_mta__touchpoint_     user_journey
      credit               ├── int_web_mta__
                               touchpoint_credit
                           └── int_web_mta__
                               user_revenue

        │
        ▼
MARTS
══════════════════════════════════════════════════════════════════════
  Daily Overview           Executive Summary        Campaign Performance
  ├── mart_daily_overview_ ├── mart_exec_summary    ├── mart_campaign_performance_full
  │   by_platform          └── mart_exec_summary_   └── mart_campaign_performance_full_mta
  ├── mart_daily_business_     measures
  │   overview
  └── mart_daily_overview_
      by_platform_measures

  MTA Attribution          LTV                      MMM
  ├── mta__campaign_       └── mart_ltv__cohort_    ├── mmm__daily_channel_summary
  │   performance              summary              └── mmm__weekly_channel_summary
  ├── mta__campaign_ltv
  ├── mart_network_
  │   performance_mta
  └── rpt__mta_vs_adjust_
      installs

  Web Attribution          Spend
  └── rpt__web_attribution └── facebook_conversions
```

---

## 2. Raw Data Sources

### 2.1 ADJUST.S3_DATA — IOS_EVENTS

**Description**: Monolithic raw event table receiving all iOS activity from Adjust S3 export. Every activity type (installs, sessions, clicks, impressions, SKAdNetwork postbacks, etc.) lands in this single table, differentiated by the `ACTIVITY_KIND` column.

| Column | Type | Description |
|---|---|---|
| ACTIVITY_KIND | VARCHAR | Event type: install, session, click, impression, reattribution, sk_install, sk_event, att_update, etc. |
| IDFV | VARCHAR | iOS Identifier for Vendor — primary device identifier for installs |
| IDFA | VARCHAR | iOS Identifier for Advertisers — available ~4-11% of records (requires ATT consent) |
| GPS_ADID | VARCHAR | Google Advertising ID — NULL for iOS |
| INSTALLED_AT | NUMBER | Install epoch timestamp |
| CREATED_AT | NUMBER | Event creation epoch timestamp |
| NETWORK_NAME | VARCHAR | Raw Adjust network/partner name |
| CAMPAIGN_NAME | VARCHAR | Campaign name with trailing ID in parentheses, e.g. `Campaign Name (abc123)` |
| ADGROUP_NAME | VARCHAR | Ad group name with trailing ID in parentheses |
| CREATIVE_NAME | VARCHAR | Creative name |
| IP_ADDRESS | VARCHAR | Device IP address at event time — used for probabilistic iOS MTA matching |
| SK_TRANSACTION_ID | VARCHAR | SKAdNetwork transaction ID (SANs omit this) |
| NONCE | VARCHAR | SKAN nonce — fallback dedup key when SK_TRANSACTION_ID is NULL |
| LOAD_TIMESTAMP | TIMESTAMP | Snowflake load time |

### 2.2 ADJUST.S3_DATA — ANDROID_EVENTS

**Description**: Monolithic raw event table for all Android activity from Adjust S3 export. Same structure as IOS_EVENTS but with Android-specific identifiers. Notable: no IP_ADDRESS column.

| Column | Type | Description |
|---|---|---|
| ACTIVITY_KIND | VARCHAR | Event type: install, session, click, impression, reattribution, etc. |
| GPS_ADID | VARCHAR | Google Advertising ID — primary Android device identifier |
| IDFV | VARCHAR | NULL for Android |
| IDFA | VARCHAR | NULL for Android |
| INSTALLED_AT | NUMBER | Install epoch timestamp |
| CREATED_AT | NUMBER | Event creation epoch timestamp |
| NETWORK_NAME | VARCHAR | Raw Adjust network/partner name |
| CAMPAIGN_NAME | VARCHAR | Campaign name with trailing ID in parentheses |
| ADGROUP_NAME | VARCHAR | Ad group name with trailing ID in parentheses |
| TRACKER_NAME | VARCHAR | Adjust tracker/link name |
| LOAD_TIMESTAMP | TIMESTAMP | Snowflake load time |

### 2.3 ADJUST.API_DATA — REPORT_DAILY_RAW

**Description**: Pre-aggregated daily campaign statistics from the Adjust Reporting API. This is the primary spend and install source for mobile campaigns. Data starts from 2021-04-07 (replaced Supermetrics at that point).

| Column | Type | Description |
|---|---|---|
| DAY | DATE | Report date |
| APP | VARCHAR | App identifier |
| REGION | VARCHAR | Geographic region |
| COUNTRY | VARCHAR | Country name |
| COUNTRY_CODE | VARCHAR | ISO country code |
| DEVICE_TYPE | VARCHAR | Device type |
| OS_NAME | VARCHAR | Operating system name (ios / android — lowercased from Adjust) |
| CHANNEL | VARCHAR | Marketing channel |
| NETWORK | VARCHAR | Ad network / partner name |
| CAMPAIGN | VARCHAR | Adjust internal campaign name |
| CAMPAIGN_NETWORK | VARCHAR | Network-side campaign name (with trailing ID) |
| CAMPAIGN_ID_NETWORK | VARCHAR | Network-side campaign ID |
| ADGROUP | VARCHAR | Adjust internal ad group name |
| ADGROUP_NETWORK | VARCHAR | Network-side ad group name (with trailing ID) |
| ADGROUP_ID_NETWORK | VARCHAR | Network-side ad group ID |
| IMPRESSIONS | NUMBER | Ad impressions |
| CLICKS | NUMBER | Ad clicks |
| INSTALLS | NUMBER | Attributed installs (last-touch, Adjust MMP) |
| NETWORK_COST | NUMBER | Spend as reported by the ad network |
| REVENUE | NUMBER | In-app purchase (IAP) revenue |
| ALL_REVENUE | NUMBER | Total revenue (IAP + ad revenue) |
| AD_REVENUE | NUMBER | In-app advertising revenue |
| SESSIONS | NUMBER | App sessions |

### 2.4 AMPLITUDEANALYTICS — EVENTS_726530

**Description**: All product events from the Amplitude analytics SDK, identified by project ID 726530. Contains a superset of user events including game actions and user property snapshots. The `USER_PROPERTIES` column is a JSON variant containing Adjust attribution data under `[adjust]` keys.

| Column | Type | Description |
|---|---|---|
| EVENT_TIME | TIMESTAMP | Event timestamp |
| USER_ID | VARCHAR | Amplitude user ID (maps to WGT account ID) |
| DEVICE_ID | VARCHAR | Amplitude device ID (random UUID — does NOT match Adjust GPS_ADID) |
| EVENT_TYPE | VARCHAR | Event name, e.g. NewPlayerCreation_Success, Cookie_Existing_Account |
| USER_PROPERTIES | VARIANT | JSON blob containing all user properties at event time, including `[adjust] Network`, `[adjust] Campaign`, `[adjust] Install Time`, `[adjust] Tracker Name` |
| PLATFORM | VARCHAR | iOS / Android / Web |
| COUNTRY | VARCHAR | Country at event time |
| OS_NAME | VARCHAR | Operating system |
| APP_VERSION | VARCHAR | App version string |

### 2.5 AMPLITUDEANALYTICS — MERGE_IDS_726530

**Description**: Device-to-user ID mapping table maintained by Amplitude. When a device is associated with a user account, a record is written here. Critical for bridging anonymous device sessions to known user IDs.

| Column | Type | Description |
|---|---|---|
| AMPLITUDE_ID | NUMBER | Amplitude's internal numeric ID |
| MERGE_EVENT_TIME | TIMESTAMP | When the merge/mapping occurred |
| MERGE_SERVER_TIME | TIMESTAMP | Server-side time of merge |
| MAPPED_ID | VARCHAR | The device ID or prior user ID being mapped |
| AMPLITUDE_USER_ID | VARCHAR | The canonical WGT user ID |

### 2.6 FIVETRAN_DATABASE.FACEBOOK_ADS — ADS_INSIGHTS

**Description**: Facebook Ads performance metrics by date/ad, synced via Fivetran. Contains WGT's web/desktop Facebook ad account data. Referenced via `{{ source('facebook_ads', 'ADS_INSIGHTS') }}` defined in `_facebook__sources.yml`.

| Column | Type | Description |
|---|---|---|
| DATE_START | DATE | Report date |
| AD_ID | VARCHAR | Facebook ad ID |
| SPEND | NUMBER | Ad spend in account currency |
| IMPRESSIONS | NUMBER | Ad impressions |
| INLINE_LINK_CLICKS | NUMBER | Link clicks |
| ACCOUNT_ID | VARCHAR | Facebook ad account ID |

### 2.7 FIVETRAN_DATABASE.FACEBOOK_ADS — ADS_INSIGHTS_ACTIONS

**Description**: Conversion action breakdown for Facebook ads. Each row represents one action type for an ad/date combination. Joined to ADS_INSIGHTS to build conversion reporting.

| Column | Type | Description |
|---|---|---|
| DATE_START | DATE | Report date |
| AD_ID | VARCHAR | Facebook ad ID |
| ACTION_TYPE | VARCHAR | Conversion action type (e.g. offsite_conversion.fb_pixel_purchase) |
| VALUE | NUMBER | Number of actions or revenue value |

### 2.8 FIVETRAN_DATABASE.GOOGLE_ADS — CAMPAIGN_STATS / CAMPAIGN_COUNTRY_REPORT

**Description**: Google Ads performance data synced via Fivetran. `CAMPAIGN_STATS` is the primary spend source (cost in micros). `CAMPAIGN_COUNTRY_REPORT` provides country-level breakdown used in MMM.

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| CAMPAIGN_ID | NUMBER | Google campaign ID |
| COST_MICROS | NUMBER | Spend in micros (divide by 1,000,000 for actual spend) |
| IMPRESSIONS | NUMBER | Ad impressions |
| CLICKS | NUMBER | Ad clicks |
| CRITERION_ID | NUMBER | Country criterion ID (actual country numeric code + 2000) |

### 2.9 WGT.PROD — DIRECT_REVENUE_EVENTS / WGT.EVENTS.*

**Description**: WGT's own event and revenue tables. `DIRECT_REVENUE_EVENTS` contains raw revenue events with JSON-encoded properties. The `WGT.EVENTS` schema contains pre-split tables for common event types.

| Table | Description |
|---|---|
| WGT.PROD.DIRECT_REVENUE_EVENTS | Raw revenue events; `EVENT_PROPERTIES:"$revenue"::DOUBLE` extracts amount |
| WGT.EVENTS.REVENUE | Pre-split revenue table with `USERID`, `EVENTTIME`, `PLATFORM`, `REVENUE`, `REVENUETYPE` (direct=IAP, indirect=ad) |
| WGT.EVENTS.ROUNDSTARTED | Game round start events — used as session proxy for retention calculation |
| WGT.EVENTS.ROUNDENDED | Game round completion events |
| WGT.EVENTS.BALLCONSUMED | Ball consumption events |
| WGT.EVENTS.BALL_CONSUME_HISTORIC | Historical ball consumption records |
| WGT.EVENTS.EVENT_HISTORY | General event history archive |

---

## 3. Staging Models

### 3.1 Adjust API — `stg_adjust__report_daily`

**Purpose**: Clean, normalized view over `REPORT_DAILY_RAW`. Applies column renames, PLATFORM normalization, trailing-ID stripping from campaign/adgroup names, and COALESCE of all numeric nulls to 0.

**Grain**: One row per DAY / APP / REGION / COUNTRY / DEVICE_TYPE / PLATFORM / CHANNEL / PARTNER / CAMPAIGN / ADGROUP / CREATIVE

**Source**: `ADJUST.API_DATA.REPORT_DAILY_RAW`

**Materialization**: view (schema: staging)

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date (renamed from DAY) |
| APP | VARCHAR | App identifier |
| REGION | VARCHAR | Geographic region |
| COUNTRY | VARCHAR | Country name |
| COUNTRY_CODE | VARCHAR | ISO country code |
| PLATFORM | VARCHAR | Normalized: 'iOS' or 'Android' (CASE on OS_NAME) |
| CHANNEL | VARCHAR | Adjust channel grouping |
| PARTNER_NAME | VARCHAR | Ad network name (renamed from NETWORK) |
| CAMPAIGN_NETWORK | VARCHAR | Campaign name with trailing ID stripped via REGEXP_REPLACE |
| CAMPAIGN_ID_NETWORK | VARCHAR | Network-side campaign ID |
| ADGROUP_NETWORK | VARCHAR | Ad group name with trailing ID stripped |
| ADGROUP_ID_NETWORK | VARCHAR | Network-side ad group ID |
| NETWORK_COST | NUMBER | Spend from ad network (COALESCEd to 0) |
| INSTALLS | NUMBER | Attributed installs (COALESCEd to 0) |
| REVENUE | NUMBER | IAP revenue (COALESCEd to 0) |
| ALL_REVENUE | NUMBER | Total revenue = IAP + ad revenue (COALESCEd to 0) |
| AD_REVENUE | NUMBER | In-app ad revenue (COALESCEd to 0) |
| CLICKS | NUMBER | Ad clicks (COALESCEd to 0) |
| IMPRESSIONS | NUMBER | Ad impressions (COALESCEd to 0) |
| SESSIONS | NUMBER | App sessions (COALESCEd to 0) |
| UNINSTALLS | NUMBER | Uninstall events (COALESCEd to 0) |
| REATTRIBUTIONS | NUMBER | Reattribution events (COALESCEd to 0) |

**Key Business Logic**:
- `PLATFORM`: `CASE WHEN UPPER(OS_NAME) = 'IOS' THEN 'iOS' WHEN UPPER(OS_NAME) = 'ANDROID' THEN 'Android'` — standardizes Adjust's lowercase OS names.
- `CAMPAIGN_NETWORK` / `ADGROUP_NETWORK`: `TRIM(REGEXP_REPLACE(col, '\\s*\\([a-zA-Z0-9_-]+\\)\\s*$', ''))` — strips network-appended IDs like `Campaign Name (abc123)`.
- All numeric columns are `COALESCE(col, 0)` — safe for aggregation without null-handling downstream.
- Filter: `WHERE DAY IS NOT NULL`

**Known Caveats**:
- This is the primary spend source for all mobile networks. Desktop/web spend from Meta and Google flows through Fivetran staging models instead.
- `NETWORK_COST` is network-reported spend. `COST` and `ADJUST_COST` are also available but not used in downstream models.

---

### 3.2 Adjust S3 Installs — `v_stg_adjust__installs`

**Purpose**: Unified iOS + Android first-install table. Deduplicates to one row per device per platform using the earliest install timestamp. iOS uses IDFV as the device identifier; Android uses UPPER(GPS_ADID).

**Grain**: One row per DEVICE_ID + PLATFORM (first install only)

**Source**: `ADJUST.S3_DATA.IOS_EVENTS` (ACTIVITY_KIND = 'install'), `ADJUST.S3_DATA.ANDROID_EVENTS` (ACTIVITY_KIND = 'install') — via staging activity models

**Materialization**: view

| Column | Type | Description |
|---|---|---|
| DEVICE_ID | VARCHAR | iOS: IDFV. Android: UPPER(GPS_ADID) |
| IDFA | VARCHAR | iOS advertising ID (available only with ATT consent). NULL for Android |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| NETWORK_NAME | VARCHAR | Raw Adjust network name at install |
| AD_PARTNER | VARCHAR | Standardized partner label via `map_ad_partner()` macro (Meta, Google, TikTok, etc.) |
| CAMPAIGN_NAME | VARCHAR | Campaign name with trailing ID stripped |
| CAMPAIGN_ID | VARCHAR | Extracted campaign ID from parentheses suffix |
| ADGROUP_NAME | VARCHAR | Ad group name with trailing ID stripped |
| ADGROUP_ID | VARCHAR | Extracted ad group ID from parentheses suffix |
| CREATIVE_NAME | VARCHAR | Creative name |
| TRACKER_NAME | VARCHAR | Adjust tracker name (iOS only; NULL for Android) |
| COUNTRY | VARCHAR | Country at install (iOS only; NULL for Android) |
| IP_ADDRESS | VARCHAR | IP address at install (iOS only; NULL for Android — Android table lacks this column) |
| INSTALL_TIMESTAMP | TIMESTAMP | Install datetime (converted from epoch) |
| INSTALL_EPOCH | NUMBER | Raw install epoch |
| CREATED_TIMESTAMP | TIMESTAMP | Record creation datetime |

**Key Business Logic**:
- iOS filter: `WHERE IDFV IS NOT NULL AND INSTALLED_AT IS NOT NULL`
- Android filter: `WHERE GPS_ADID IS NOT NULL AND INSTALLED_AT IS NOT NULL`
- Dedup: `QUALIFY ROW_NUMBER() OVER (PARTITION BY DEVICE_ID, PLATFORM ORDER BY INSTALL_TIMESTAMP ASC) = 1`
- Campaign/adgroup IDs extracted via: `REGEXP_SUBSTR(col, '\\(([a-zA-Z0-9_-]+)\\)$', 1, 1, 'e')`

**Known Caveats**:
- Android has no COUNTRY or IP_ADDRESS — those columns are NULL for all Android rows.
- IDFA is populated only when the user granted ATT (App Tracking Transparency) consent — approximately 7-11% of iOS installs.
- This view is the source of truth for install counts in the MMM and cohort pipelines.

---

### 3.3 Adjust S3 Touchpoints — `v_stg_adjust__touchpoints`

**Purpose**: Unified clicks and impressions for the mobile MTA pipeline. Filters to 2024-01-01 onward. iOS touchpoints have no IDFV (device ID); matching relies on IDFA (~4-11%) or IP address. Android touchpoints use GPS_ADID.

**Grain**: One row per touchpoint event

**Source**: `IOS_ACTIVITY_CLICK`, `IOS_ACTIVITY_IMPRESSION`, `ANDROID_ACTIVITY_CLICK`, `ANDROID_ACTIVITY_IMPRESSION` (via staging activity models)

**Materialization**: incremental (merge)

**Unique Key**: `[PLATFORM, TOUCHPOINT_TYPE, TOUCHPOINT_EPOCH, NETWORK_NAME, CAMPAIGN_ID, IP_ADDRESS, LOAD_TIMESTAMP]`

| Column | Type | Description |
|---|---|---|
| DEVICE_ID | VARCHAR | NULL for iOS (no IDFV on touchpoints). UPPER(GPS_ADID) for Android |
| IDFA | VARCHAR | iOS advertising ID (~4% impressions, ~11% clicks). NULL for Android |
| IP_ADDRESS | VARCHAR | Device IP (iOS only; Android tables lack this column) |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| TOUCHPOINT_TYPE | VARCHAR | 'impression' or 'click' |
| NETWORK_NAME | VARCHAR | Raw ad network name |
| AD_PARTNER | VARCHAR | Standardized partner label via `map_ad_partner()` macro |
| CAMPAIGN_NAME | VARCHAR | Campaign name with trailing ID stripped |
| CAMPAIGN_ID | VARCHAR | Extracted campaign ID |
| ADGROUP_NAME | VARCHAR | Ad group name with trailing ID stripped |
| ADGROUP_ID | VARCHAR | Extracted ad group ID |
| CREATIVE_NAME | VARCHAR | Creative name |
| TOUCHPOINT_TIMESTAMP | TIMESTAMP | Touchpoint datetime |
| TOUCHPOINT_EPOCH | NUMBER | Raw touchpoint epoch |
| LOAD_TIMESTAMP | TIMESTAMP | Snowflake load time |

**Key Business Logic**:
- Date filter: `CREATED_AT >= 1704067200` (2024-01-01 epoch) for all four subqueries.
- iOS filter requires: `(IDFA IS NOT NULL OR IP_ADDRESS IS NOT NULL)` — excludes touchpoints with no matching identifier at all.
- Android filter requires: `GPS_ADID IS NOT NULL`.
- Incremental: each platform/type CTE checks `CREATED_AT > MAX(TOUCHPOINT_EPOCH)` from the existing table partition.

**Known Caveats**:
- Self-attributing networks (Meta, Google, Apple Search Ads, TikTok) do not share touchpoint data with Adjust — these networks have 0% MTA coverage regardless of IDFA availability.
- iOS probabilistic IP matching was evaluated but not implemented due to privacy concerns.

---

### 3.4 Adjust S3 SKAN — `stg_adjust__ios_activity_sk_install`

**Purpose**: Filters iOS SKAdNetwork install postbacks from IOS_EVENTS for the SKAN attribution pipeline.

**Grain**: One row per sk_install event

**Source**: `ADJUST.S3_DATA.IOS_EVENTS` WHERE ACTIVITY_KIND = 'sk_install'

**Materialization**: incremental (append) → writes to `ADJUST.S3_DATA.IOS_ACTIVITY_SK_INSTALL`

| Column | Type | Description |
|---|---|---|
| SK_TRANSACTION_ID | VARCHAR | SKAN transaction ID (NULL for self-attributing networks) |
| NONCE | VARCHAR | SKAN nonce — dedup fallback when SK_TRANSACTION_ID is NULL |
| NETWORK_NAME | VARCHAR | Ad network that served the ad |
| CAMPAIGN_NAME | VARCHAR | Campaign name |
| COUNTRY | VARCHAR | Country code from postback |
| CONVERSION_VALUE | NUMBER | SKAN conversion value (0-63) |
| CREATED_AT | NUMBER | Postback receipt epoch |

**Known Caveats**: SKAN postbacks are privacy-aggregated by Apple. Granularity is limited and country is often omitted in postbacks.

---

### 3.5 Adjust S3 Raw Activity Models (26 pass-through models)

These models are pure partitions of the monolithic `IOS_EVENTS` and `ANDROID_EVENTS` tables. Each applies a single `WHERE ACTIVITY_KIND = '<type>'` filter and writes incrementally (append) to a dedicated table in the `ADJUST.S3_DATA` schema. No column transformations are applied.

**Materialization**: incremental (append) → writes directly into `ADJUST.S3_DATA.<model_name>`

**iOS models (16)**:

| Model | ACTIVITY_KIND filter |
|---|---|
| `stg_adjust__ios_activity_install` | install |
| `stg_adjust__ios_activity_session` | session |
| `stg_adjust__ios_activity_event` | event |
| `stg_adjust__ios_activity_click` | click |
| `stg_adjust__ios_activity_impression` | impression |
| `stg_adjust__ios_activity_reattribution` | reattribution |
| `stg_adjust__ios_activity_install_update` | install_update |
| `stg_adjust__ios_activity_reattribution_update` | reattribution_update |
| `stg_adjust__ios_activity_rejected_install` | rejected_install |
| `stg_adjust__ios_activity_rejected_reattribution` | rejected_reattribution |
| `stg_adjust__ios_activity_att_update` | att_update |
| `stg_adjust__ios_activity_sk_install` | sk_install |
| `stg_adjust__ios_activity_sk_install_direct` | sk_install_direct |
| `stg_adjust__ios_activity_sk_event` | sk_event |
| `stg_adjust__ios_activity_sk_cv_update` | sk_cv_update |
| `stg_adjust__ios_activity_sk_qualifier` | sk_qualifier |

**Android models (10)**:

| Model | ACTIVITY_KIND filter |
|---|---|
| `stg_adjust__android_activity_install` | install |
| `stg_adjust__android_activity_session` | session |
| `stg_adjust__android_activity_event` | event |
| `stg_adjust__android_activity_click` | click |
| `stg_adjust__android_activity_impression` | impression |
| `stg_adjust__android_activity_reattribution` | reattribution |
| `stg_adjust__android_activity_install_update` | install_update |
| `stg_adjust__android_activity_reattribution_update` | reattribution_update |
| `stg_adjust__android_activity_rejected_install` | rejected_install |
| `stg_adjust__android_activity_rejected_reattribution` | rejected_reattribution |

**Known Caveats**: These models exist to partition raw data for query efficiency. The upstream monolithic tables (IOS_EVENTS, ANDROID_EVENTS) remain the source of truth. The partitioned tables are used by `v_stg_adjust__installs` and `v_stg_adjust__touchpoints`.

---

### 3.6 Facebook Ads Staging

#### `v_stg_facebook_spend`

**Purpose**: Facebook ad spend aggregated to date/account/campaign/adset/ad/country grain, with account and campaign metadata joined in. Uses `country_codes` seed for country resolution.

**Grain**: DATE / ACCOUNT_ID / CAMPAIGN_ID / ADSET_ID / AD_ID / COUNTRY_CODE

**Source**: `{{ source('facebook_ads', 'ADS_INSIGHTS') }}` (via `_facebook__sources.yml`)

**Materialization**: view

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| ACCOUNT_ID | VARCHAR | Facebook ad account ID |
| ACCOUNT_NAME | VARCHAR | Ad account name (from v_stg_facebook_accounts) |
| CAMPAIGN_ID | VARCHAR | Facebook campaign ID |
| CAMPAIGN | VARCHAR | Campaign name (from v_stg_facebook_campaigns) |
| ADSET_ID | VARCHAR | Ad set ID |
| ADSET_NAME | VARCHAR | Ad set name (from v_stg_facebook_adsets) |
| AD_ID | VARCHAR | Facebook ad ID |
| AD_NAME | VARCHAR | Ad name (from v_stg_facebook_ads) |
| COUNTRY_CODE | VARCHAR | ISO alpha-2 country code |
| SPEND | NUMBER | SUM(SPEND) for the grain |
| IMPRESSIONS | NUMBER | SUM(IMPRESSIONS) |
| CLICKS | NUMBER | SUM(INLINE_LINK_CLICKS) |

#### `v_stg_facebook_accounts` / `v_stg_facebook_campaigns` / `v_stg_facebook_adsets` / `v_stg_facebook_ads`

**Purpose**: Deduped history tables providing the latest metadata record per entity ID. Used as lookup joins in `v_stg_facebook_spend`.

**Materialization**: view

**Key Logic**: Each selects the most recent record per ID using `QUALIFY ROW_NUMBER() OVER (PARTITION BY ID ORDER BY _FIVETRAN_SYNCED DESC) = 1` or similar.

#### `v_stg_facebook_conversions`

**Purpose**: Facebook conversion actions with spend allocated proportionally across action types using a divisor (DIVIDEND) equal to the count of distinct action types per ad/date.

**Source**: `FIVETRAN_DATABASE.FACEBOOK_ADS.ADS_INSIGHTS_ACTIONS`

**Materialization**: view

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| AD_ID | VARCHAR | Facebook ad ID |
| ACTION_TYPE | VARCHAR | Conversion action type |
| VALUE | NUMBER | Action count or value |
| SPEND | NUMBER | Allocated spend (total spend / DIVIDEND) |
| DIVIDEND | NUMBER | Count of distinct action types for this ad/date |

#### `v_stg_facebook_distinct_actions`

**Purpose**: Helper view counting distinct action types per ad/date combination. Feeds the DIVIDEND calculation in `v_stg_facebook_conversions`.

**Source Configuration**: All 7 Facebook staging models now use `{{ source('facebook_ads', ...) }}` refs defined in `_facebook__sources.yml`. The source points to `FIVETRAN_DATABASE.FACEBOOK_ADS`. If the Fivetran destination changes, update the source YAML — no model SQL changes required.

---

### 3.7 Google Ads Staging

#### `v_stg_google_ads__spend`

**Purpose**: Google Ads campaign spend with COST_MICROS converted to actual spend. Filters to rows with spend > 0.

**Grain**: DATE / CAMPAIGN_ID

**Source**: `FIVETRAN_DATABASE.GOOGLE_ADS.CAMPAIGN_STATS` (via `_google_ads__sources.yml`)

**Materialization**: view

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| CAMPAIGN_ID | NUMBER | Google campaign ID |
| CAMPAIGN_NAME | VARCHAR | Campaign name (from v_stg_google_ads__campaigns join) |
| SPEND | NUMBER | COST_MICROS / 1,000,000 |
| IMPRESSIONS | NUMBER | Ad impressions |
| CLICKS | NUMBER | Ad clicks |

**Key Logic**: `WHERE COST_MICROS > 0` — excludes zero-spend rows.

#### `v_stg_google_ads__country_spend`

**Purpose**: Google Ads spend broken down by country, with platform inferred from campaign name keywords. Used in the MMM pipeline for country-level spend allocation.

**Grain**: DATE / CAMPAIGN_ID / COUNTRY_CODE

**Source**: `FIVETRAN_DATABASE.GOOGLE_ADS.CAMPAIGN_COUNTRY_REPORT`

**Materialization**: view

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| CAMPAIGN_ID | NUMBER | Google campaign ID |
| COUNTRY_CODE | VARCHAR | ISO country code (CRITERION_ID - 2000 → lookup in country_codes seed) |
| PLATFORM | VARCHAR | Inferred from campaign name: 'iOS', 'Android', 'Desktop', or 'Unknown' |
| SPEND | NUMBER | COST_MICROS / 1,000,000 |
| IMPRESSIONS | NUMBER | Ad impressions |
| CLICKS | NUMBER | Ad clicks |

**Key Logic**: `CRITERION_ID = country_numeric_code + 2000` — Google's encoding for country targeting criteria.

#### `v_stg_google_ads__accounts` / `v_stg_google_ads__campaigns`

**Purpose**: Deduped account and campaign metadata from Fivetran history tables.

**Materialization**: view

**Key Logic**: `WHERE _FIVETRAN_ACTIVE = TRUE` filters to the current active record per entity.

---

### 3.8 Amplitude Staging

#### `v_stg_amplitude__user_attribution`

**Purpose**: Extracts Adjust attribution data from Amplitude's USER_PROPERTIES JSON for each user. Captures the first event per USER_ID + PLATFORM that contains Adjust attribution fields. This is used to link Amplitude users to their Adjust install attribution.

**Grain**: One row per USER_ID + PLATFORM

**Source**: `AMPLITUDEANALYTICS.EVENTS_726530`

**Materialization**: incremental (merge)

| Column | Type | Description |
|---|---|---|
| USER_ID | VARCHAR | Amplitude / WGT user account ID |
| PLATFORM | VARCHAR | 'iOS', 'Android', or 'Web' |
| ADJUST_NETWORK | VARCHAR | Extracted from USER_PROPERTIES:"[adjust] Network" |
| ADJUST_CAMPAIGN | VARCHAR | Extracted from USER_PROPERTIES:"[adjust] Campaign" |
| ADJUST_ADGROUP | VARCHAR | Extracted from USER_PROPERTIES:"[adjust] Ad Group" |
| ADJUST_CREATIVE | VARCHAR | Extracted from USER_PROPERTIES:"[adjust] Creative" |
| ADJUST_TRACKER_NAME | VARCHAR | Extracted from USER_PROPERTIES:"[adjust] Tracker Name" |
| ADJUST_INSTALL_TIME | TIMESTAMP | Extracted from USER_PROPERTIES:"[adjust] Install Time" |
| FIRST_SEEN_AT | TIMESTAMP | Earliest event time with Adjust attribution data |

**Key Logic**: `QUALIFY ROW_NUMBER() OVER (PARTITION BY USER_ID, PLATFORM ORDER BY EVENT_TIME ASC) = 1` — keeps the first record with Adjust data.

#### `v_stg_amplitude__merge_ids`

**Purpose**: Maps Amplitude DEVICE_ID to USER_ID using the MERGE_IDS table. Prioritizes `NewPlayerCreation_Success` events over `Cookie_Existing_Account` to get the canonical user mapping. Strips trailing 'R' suffix from Android device IDs.

**Grain**: One row per DEVICE_ID

**Source**: `AMPLITUDEANALYTICS.MERGE_IDS_726530`, `AMPLITUDEANALYTICS.EVENTS_726530`

**Materialization**: incremental (merge), 7-day lookback on MERGE_EVENT_TIME. Data from 2025-01-01+.

| Column | Type | Description |
|---|---|---|
| DEVICE_ID | VARCHAR | Amplitude device ID (Android: trailing 'R' stripped) |
| USER_ID | VARCHAR | Mapped WGT user account ID |
| PLATFORM | VARCHAR | Device platform |
| MAPPING_TYPE | VARCHAR | Source of mapping: 'NewPlayerCreation_Success' or 'Cookie_Existing_Account' |
| MAPPED_AT | TIMESTAMP | Timestamp of the mapping event |

**Key Logic**: Priority order: `NewPlayerCreation_Success` > `Cookie_Existing_Account`. Android device IDs have a trailing 'R' character stripped: `REGEXP_REPLACE(DEVICE_ID, 'R$', '')`.

**Known Caveats**: Amplitude's DEVICE_ID is a random UUID generated by the SDK — it does NOT match Adjust's GPS_ADID on Android. This is the root cause of 0% Android MTA match rate.

---

### 3.9 Revenue Events — `v_stg_revenue__events`

**Purpose**: Revenue events from WGT's direct revenue event table with JSON property extraction. Provides an event-level revenue stream as an alternative to the pre-split `WGT.EVENTS.REVENUE` table.

**Grain**: One row per revenue event

**Source**: `WGT.PROD.DIRECT_REVENUE_EVENTS`

**Materialization**: incremental (merge), 3-day lookback. Data from 2025-01-01+.

| Column | Type | Description |
|---|---|---|
| EVENT_ID | VARCHAR | Unique event identifier |
| USER_ID | VARCHAR | WGT user account ID |
| EVENT_TIME | TIMESTAMP | Revenue event timestamp |
| PLATFORM | VARCHAR | Device platform |
| REVENUE_AMOUNT | NUMBER | `EVENT_PROPERTIES:"$revenue"::DOUBLE` — extracted from JSON |

**Key Logic**: `EVENT_PROPERTIES:"$revenue"::DOUBLE AS REVENUE_AMOUNT` — Snowflake semi-structured JSON extraction.

---

## 4. Intermediate Models

### 4.1 Spend Pipeline

#### `int_spend__unified`

**Purpose**: Deduplicates and combines spend from all three sources (Fivetran Facebook, Fivetran Google, Adjust API) into a single unified spend table. Resolves source overlap using campaign ID matching.

**Grain**: DATE / SOURCE / CHANNEL / CAMPAIGN_ID / PLATFORM

**Sources**: `v_stg_facebook_spend`, `v_stg_google_ads__spend`, `stg_adjust__report_daily`, `network_mapping`

**Materialization**: view

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| SOURCE | VARCHAR | 'fivetran_facebook', 'fivetran_google', or 'adjust_api' |
| CHANNEL | VARCHAR | Ad channel: 'Meta', 'Google', or mapped partner name |
| CAMPAIGN_ID | VARCHAR | Network-side campaign ID |
| CAMPAIGN_NAME | VARCHAR | Campaign name |
| PLATFORM | VARCHAR | 'iOS', 'Android', or NULL (Fivetran sources lack platform dimension) |
| SPEND | NUMBER | Ad spend in USD |
| IMPRESSIONS | NUMBER | Ad impressions |
| CLICKS | NUMBER | Ad clicks |

**Key Business Logic**:
- Meta: Fivetran covers web/desktop accounts; Adjust covers mobile accounts. No campaign ID overlap → both included.
- Google: Fivetran is the preferred source. Adjust rows are excluded for any CAMPAIGN_ID already present in Fivetran Google data.
- All other networks: Adjust API only.
- Adjust rows with `NETWORK_COST <= 0` are excluded.

**Known Caveats**: Fivetran Facebook and Google sources do not carry a PLATFORM dimension. Platform splits for these sources must be inferred downstream (e.g., from campaign name patterns in Google country spend).

---

#### `int_mmm__daily_channel_spend`

**Purpose**: Reaggregates `int_spend__unified` to the DATE + PLATFORM + CHANNEL grain for MMM input.

**Grain**: DATE / PLATFORM / CHANNEL

**Source**: `int_spend__unified`

**Materialization**: incremental (merge), 7-day lookback

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| PLATFORM | VARCHAR | 'iOS', 'Android', 'Desktop', or NULL |
| CHANNEL | VARCHAR | Standardized ad channel name |
| SPEND | NUMBER | Total spend for date/platform/channel |
| IMPRESSIONS | NUMBER | Total impressions |
| CLICKS | NUMBER | Total clicks |

---

### 4.2 Install Pipeline

#### `int_mmm__daily_channel_installs`

**Purpose**: Combines S3-based installs (`v_stg_adjust__installs`) with SKAN installs (`int_skan__aggregate_attribution`) to produce a complete install count for MMM. SKAN installs are non-overlapping iOS-only additions.

**Grain**: DATE / PLATFORM / CHANNEL (aggregated)

**Sources**: `v_stg_adjust__installs`, `int_skan__aggregate_attribution`

**Materialization**: incremental (merge), 7-day lookback

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Install date |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| CHANNEL | VARCHAR | Ad partner / channel |
| INSTALLS | NUMBER | COUNT DISTINCT DEVICE_ID from S3 + SKAN install count |

---

### 4.3 Revenue Pipeline

#### `int_mmm__daily_channel_revenue`

**Purpose**: Constructs channel-attributed revenue for MMM. Mobile revenue comes from `stg_adjust__report_daily`. Desktop revenue from `WGT.EVENTS.REVENUE` is allocated to channels using web MTA channel weights. Now includes all three platform types (iOS, Android, Desktop).

**Grain**: DATE / PLATFORM / CHANNEL

**Sources**: `stg_adjust__report_daily`, `WGT.EVENTS.REVENUE`, `int_web_mta__touchpoint_credit`

**Materialization**: incremental (merge), 7-day lookback

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Revenue date |
| PLATFORM | VARCHAR | 'iOS', 'Android', or 'Desktop' |
| CHANNEL | VARCHAR | Ad channel |
| REVENUE | NUMBER | Direct (IAP) revenue |
| AD_REVENUE | NUMBER | In-app advertising revenue |

**Key Business Logic**: Mobile (iOS/Android) revenue comes from Adjust API. Desktop revenue from `WGT.EVENTS.REVENUE` is allocated proportionally to channels using web MTA credit weights from `int_web_mta__touchpoint_credit`.

---

### 4.4 SKAN Pipeline

#### `int_skan__aggregate_attribution`

**Purpose**: Aggregates SKAdNetwork install postbacks by partner/campaign/date. Handles the SAN case where SK_TRANSACTION_ID is NULL by falling back to NONCE for distinct counting.

**Grain**: DATE / NETWORK_NAME / CAMPAIGN_NAME (aggregated)

**Source**: `stg_adjust__ios_activity_sk_install`

**Materialization**: incremental (merge), 7-day lookback

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Postback receipt date |
| NETWORK_NAME | VARCHAR | Ad network |
| CAMPAIGN_NAME | VARCHAR | Campaign name |
| INSTALL_COUNT | NUMBER | Total SKAN installs (distinct by COALESCE(SK_TRANSACTION_ID, NONCE)) |
| NEW_INSTALL_COUNT | NUMBER | New installs (excluding redownloads where supported) |
| AVG_CONVERSION_VALUE | NUMBER | Average SKAN conversion value |

**Known Caveats**: SKAN postbacks are Apple-privacy-aggregated. Self-attributing networks (Meta, Google) do not provide SK_TRANSACTION_ID, so NONCE is used as the dedup key. Country granularity is often missing.

---

### 4.5 User Cohort Pipeline

#### `int_user_cohort__attribution`

**Purpose**: Links WGT user IDs to their Adjust install attribution by joining Amplitude user attribution data with install records. Produces one row per USER_ID + PLATFORM with attribution metadata.

**Grain**: USER_ID / PLATFORM

**Sources**: `v_stg_amplitude__user_attribution`, `v_stg_adjust__installs`

**Materialization**: incremental (merge), 7-day lookback on INSTALL_TIME

| Column | Type | Description |
|---|---|---|
| USER_ID | VARCHAR | WGT user account ID |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| INSTALL_TIME | TIMESTAMP | Earliest install timestamp |
| INSTALL_DATE | DATE | Install date |
| NETWORK_NAME | VARCHAR | Attributed ad network |
| AD_PARTNER | VARCHAR | Standardized partner label |
| CAMPAIGN_NAME | VARCHAR | Attributed campaign name |
| CAMPAIGN_ID | VARCHAR | Campaign ID |
| ADGROUP_NAME | VARCHAR | Ad group name |
| COUNTRY | VARCHAR | Install country |

---

#### `int_user_cohort__metrics`

**Purpose**: Comprehensive user-level cohort metrics table. For each user, calculates cumulative revenue at D1/D7/D30/D180/D365/lifetime windows, split by revenue type (total, purchase/IAP, ad). Also calculates retention flags (did the user play on day N?) and maturity flags (has day N elapsed since install?).

**Grain**: USER_ID / PLATFORM

**Sources**: `int_user_cohort__attribution`, `WGT.EVENTS.REVENUE`, `WGT.EVENTS.ROUNDSTARTED`

**Materialization**: incremental (merge), 370-day lookback on INSTALL_DATE

**Unique Key**: `[USER_ID, PLATFORM]`

| Column | Type | Description |
|---|---|---|
| USER_ID | VARCHAR | WGT user account ID |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| INSTALL_DATE | DATE | First install date |
| INSTALL_TIME | TIMESTAMP | First install timestamp |
| D1_REVENUE | NUMBER | Total revenue within 1 day of install |
| D7_REVENUE | NUMBER | Total revenue within 7 days of install |
| D30_REVENUE | NUMBER | Total revenue within 30 days of install |
| D180_REVENUE | NUMBER | Total revenue within 180 days of install |
| D365_REVENUE | NUMBER | Total revenue within 365 days of install |
| TOTAL_REVENUE | NUMBER | Lifetime total revenue |
| D1_PURCHASE_REVENUE | NUMBER | IAP revenue within 1 day (REVENUETYPE = 'direct') |
| D7_PURCHASE_REVENUE | NUMBER | IAP revenue within 7 days |
| D30_PURCHASE_REVENUE | NUMBER | IAP revenue within 30 days |
| D180_PURCHASE_REVENUE | NUMBER | IAP revenue within 180 days |
| D365_PURCHASE_REVENUE | NUMBER | IAP revenue within 365 days |
| TOTAL_PURCHASE_REVENUE | NUMBER | Lifetime IAP revenue |
| D1_AD_REVENUE | NUMBER | Ad revenue within 1 day (REVENUETYPE = 'indirect') |
| D7_AD_REVENUE | NUMBER | Ad revenue within 7 days |
| D30_AD_REVENUE | NUMBER | Ad revenue within 30 days |
| D180_AD_REVENUE | NUMBER | Ad revenue within 180 days |
| D365_AD_REVENUE | NUMBER | Ad revenue within 365 days |
| TOTAL_AD_REVENUE | NUMBER | Lifetime ad revenue |
| IS_D1_PAYER | NUMBER | 1 if user made any IAP purchase within day 1 |
| IS_D7_PAYER | NUMBER | 1 if user made any IAP purchase within day 7 |
| IS_D30_PAYER | NUMBER | 1 if user made any IAP purchase within day 30 |
| IS_D180_PAYER | NUMBER | 1 if user made any IAP purchase within day 180 |
| IS_D365_PAYER | NUMBER | 1 if user made any IAP purchase within day 365 |
| IS_PAYER | NUMBER | 1 if user ever made any IAP purchase |
| D1_RETAINED | NUMBER | 1 if user had a ROUNDSTARTED event on day 1 after install |
| D7_RETAINED | NUMBER | 1 if user had a ROUNDSTARTED event on day 7 after install |
| D30_RETAINED | NUMBER | 1 if user had a ROUNDSTARTED event on day 30 after install |
| D180_RETAINED | NUMBER | 1 if user had a ROUNDSTARTED event on day 180 after install |
| D365_RETAINED | NUMBER | 1 if user had a ROUNDSTARTED event on day 365 after install |
| D1_MATURED | NUMBER | 1 if >= 1 day has elapsed since install (metrics are final) |
| D7_MATURED | NUMBER | 1 if >= 7 days have elapsed since install |
| D30_MATURED | NUMBER | 1 if >= 30 days have elapsed since install |
| D180_MATURED | NUMBER | 1 if >= 180 days have elapsed since install |
| D365_MATURED | NUMBER | 1 if >= 365 days have elapsed since install |

**Key Business Logic**:
- Revenue windows: `SUM(CASE WHEN r.EVENT_TIME <= DATEADD(day, N, u.INSTALL_TIME) THEN r.REVENUE ELSE 0 END)`
- Retention: exact-day match — `s.SESSION_DATE = DATEADD(day, N, u.INSTALL_DATE)` (using ROUNDSTARTED as session proxy)
- Maturity: `DATEDIFF(day, INSTALL_DATE, CURRENT_DATE()) >= N`
- Incremental: re-processes users with `INSTALL_DATE >= DATEADD(day, -370, CURRENT_DATE())` — covers full D365 window plus buffer.
- Payer flags are based on `REVENUETYPE = 'direct'` (IAP) only, not ad revenue.

**Known Caveats**: Retention uses ROUNDSTARTED (a game event) rather than a session open event. This means a user who opened the app but did not start a round would not be counted as retained. This was a deliberate tradeoff to reduce Amplitude query compute costs.

---

### 4.6 Device Mapping

#### `int_adjust_amplitude__device_mapping`

**Purpose**: Attempts to bridge Adjust DEVICE_ID (IDFV for iOS) to Amplitude USER_ID via the merge IDs table. Intended to enable device-level LTV attribution.

**Grain**: DEVICE_ID / PLATFORM

**Sources**: `v_stg_adjust__installs`, `v_stg_amplitude__merge_ids`

**Materialization**: incremental (merge)

| Column | Type | Description |
|---|---|---|
| DEVICE_ID | VARCHAR | Adjust device ID (IDFV for iOS) |
| PLATFORM | VARCHAR | Device platform |
| USER_ID | VARCHAR | Mapped Amplitude/WGT user ID (NULL if no match) |
| HAS_USER_MAPPING | BOOLEAN | TRUE if a user ID was successfully mapped |

**Known Caveats**: This model was built but never deployed to production. As of November 2025, it is stale. Android match rate is 0% because Amplitude SDK uses a random UUID as DEVICE_ID — not GPS_ADID. iOS match rate is limited to IDFV-based matching. The root fix requires Amplitude SDK configuration change (`useAdvertisingIdForDeviceId()` for Android).

---

### 4.7 Mobile MTA Pipeline

#### `int_mta__user_journey`

**Purpose**: Maps pre-install touchpoints to installs to construct each user's ad exposure journey. Matches touchpoints to installs within a 7-day lookback window. iOS uses IDFA-to-IDFA matching. Android uses DEVICE_ID matching.

**Grain**: One row per DEVICE_ID + TOUCHPOINT + INSTALL combination

**Sources**: `v_stg_adjust__touchpoints`, `v_stg_adjust__installs`

**Materialization**: incremental (merge)

| Column | Type | Description |
|---|---|---|
| JOURNEY_ROW_KEY | VARCHAR | MD5 hash of device+touchpoint+install identifiers — unique row key |
| DEVICE_ID | VARCHAR | Device identifier |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| TOUCHPOINT_TYPE | VARCHAR | 'click' or 'impression' |
| NETWORK_NAME | VARCHAR | Ad network of touchpoint |
| AD_PARTNER | VARCHAR | Standardized partner label |
| CAMPAIGN_NAME | VARCHAR | Touchpoint campaign name |
| CAMPAIGN_ID | VARCHAR | Touchpoint campaign ID |
| TOUCHPOINT_TIMESTAMP | TIMESTAMP | When the touchpoint occurred |
| INSTALL_TIMESTAMP | TIMESTAMP | When the device installed |
| INSTALL_NETWORK | VARCHAR | Network recorded at install time (Adjust last-touch) |
| INSTALL_AD_PARTNER | VARCHAR | Standardized install partner |
| INSTALL_CAMPAIGN_ID | VARCHAR | Campaign ID recorded at install |
| HOURS_TO_INSTALL | NUMBER | Hours between touchpoint and install |
| DAYS_TO_INSTALL | NUMBER | Days between touchpoint and install |
| TOUCHPOINT_POSITION | NUMBER | Touchpoint's chronological position in the journey (1 = first) |
| TOTAL_TOUCHPOINTS | NUMBER | Total touchpoints in this install's journey |
| IS_FIRST_TOUCH | NUMBER | 1 if this is the first touchpoint |
| IS_LAST_TOUCH | NUMBER | 1 if this is the last touchpoint |
| BASE_TYPE_WEIGHT | NUMBER | Type weight: clicks = 2.0, impressions = 1.0 |

**Known Caveats**: Android 0% match rate (Amplitude SDK UUID ≠ GPS_ADID). iOS IDFA available for only ~7.37% of installs. Self-attributing networks (Meta, Google, Apple, TikTok) share 0% touchpoint data. This model is preserved for iOS non-SAN tactical analysis.

---

#### `int_mta__touchpoint_credit`

**Purpose**: Calculates five attribution model credit scores for each touchpoint in a user's journey. The recommended model is time_decay.

**Grain**: One row per JOURNEY_ROW_KEY (same as int_mta__user_journey)

**Source**: `int_mta__user_journey`

**Materialization**: incremental (merge, 10-day lookback on INSTALL_TIMESTAMP)

| Column | Type | Description |
|---|---|---|
| JOURNEY_ROW_KEY | VARCHAR | MD5 hash unique row key |
| DEVICE_ID | VARCHAR | Device identifier |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| TOUCHPOINT_TYPE | VARCHAR | 'click' or 'impression' |
| NETWORK_NAME | VARCHAR | Ad network |
| AD_PARTNER | VARCHAR | Standardized partner |
| CAMPAIGN_NAME | VARCHAR | Campaign name |
| CAMPAIGN_ID | VARCHAR | Campaign ID |
| TOUCHPOINT_TIMESTAMP | TIMESTAMP | Touchpoint time |
| INSTALL_TIMESTAMP | TIMESTAMP | Install time |
| CREDIT_LAST_TOUCH | NUMBER | Last-touch credit (1.0 for last touchpoint, 0.0 for all others) |
| CREDIT_FIRST_TOUCH | NUMBER | First-touch credit (1.0 for first touchpoint, 0.0 for all others) |
| CREDIT_LINEAR | NUMBER | Linear credit weighted by touchpoint type (clicks = 2x impressions) |
| CREDIT_TIME_DECAY | NUMBER | Time-decay credit; half-life = 3 days; type-weighted. Formula: `2^(-DAYS_TO_INSTALL/3)` |
| CREDIT_POSITION_BASED | NUMBER | U-shaped: 40% first, 40% last, 20% distributed among middle touchpoints |
| CREDIT_RECOMMENDED | NUMBER | Alias for CREDIT_TIME_DECAY — the recommended model |

**Key Business Logic**:
- Time-decay formula: `POWER(2, -1.0 * DAYS_TO_INSTALL / 3)` — gives weight of 1.0 at install day, 0.5 at 3 days prior, 0.25 at 6 days prior.
- Linear and time-decay are type-weighted: clicks carry 2x the base weight of impressions.
- Position-based with only 2 touchpoints splits 50/50 (normalized 40/40 weights).
- All credits for a given install sum to 1.0.

---

### 4.8 Web MTA Pipeline

#### `int_web_mta__user_journey`

**Purpose**: Maps anonymous web browser sessions to game registrations using Amplitude's identity bridge. Captures UTM parameters, referrer data, and session metadata from USER_PROPERTIES JSON. Uses a 30-day lookback window before the registration event.

**Grain**: One row per USER_ID / session / registration combination

**Source**: `AMPLITUDEANALYTICS.EVENTS_726530` (web events + NewPlayerCreation_Success events)

**Materialization**: table

| Column | Type | Description |
|---|---|---|
| USER_ID | VARCHAR | WGT user account ID |
| SESSION_ID | VARCHAR | Amplitude web session identifier |
| REGISTRATION_TIMESTAMP | TIMESTAMP | When the user registered (NewPlayerCreation_Success) |
| SESSION_TIMESTAMP | TIMESTAMP | Web session timestamp |
| UTM_SOURCE | VARCHAR | utm_source from USER_PROPERTIES |
| UTM_MEDIUM | VARCHAR | utm_medium from USER_PROPERTIES |
| UTM_CAMPAIGN | VARCHAR | utm_campaign from USER_PROPERTIES |
| REFERRER | VARCHAR | HTTP referrer |
| DAYS_TO_REGISTRATION | NUMBER | Days between session and registration |
| TOUCHPOINT_POSITION | NUMBER | Chronological position in web journey |
| TOTAL_TOUCHPOINTS | NUMBER | Total web touchpoints before registration |
| IS_FIRST_TOUCH | NUMBER | 1 if first web touchpoint |
| IS_LAST_TOUCH | NUMBER | 1 if last web touchpoint (registration session) |

**Known Caveats**: Approximately 86% of web traffic is anonymous (no USER_ID). Only users who registered can be retroactively attributed. UTM data is captured at the session level from Amplitude user properties, which may not reflect every session's actual UTM parameters.

---

#### `int_web_mta__touchpoint_credit`

**Purpose**: Calculates the same five attribution model credits as the mobile MTA pipeline, applied to web journeys. No click/impression type weighting — all web sessions are active visits and treated equally.

**Grain**: One row per USER_ID / SESSION_ID

**Source**: `int_web_mta__user_journey`

**Materialization**: table

| Column | Type | Description |
|---|---|---|
| USER_ID | VARCHAR | WGT user account ID |
| SESSION_ID | VARCHAR | Web session identifier |
| UTM_SOURCE | VARCHAR | Traffic source |
| UTM_MEDIUM | VARCHAR | Traffic medium |
| UTM_CAMPAIGN | VARCHAR | Campaign |
| CREDIT_LAST_TOUCH | NUMBER | Last-touch credit |
| CREDIT_FIRST_TOUCH | NUMBER | First-touch credit |
| CREDIT_LINEAR | NUMBER | Linear (equal) credit |
| CREDIT_TIME_DECAY | NUMBER | Time-decay credit (3-day half-life) |
| CREDIT_POSITION_BASED | NUMBER | U-shaped: 40/40/20 |
| CREDIT_RECOMMENDED | NUMBER | Alias for CREDIT_TIME_DECAY |

---

#### `int_web_mta__user_revenue`

**Purpose**: Cross-platform per-user revenue anchored to the web registration timestamp. Used to evaluate downstream revenue from web-acquired users across D7/D30/Total windows. Includes JOURNEY_COUNT to avoid double-counting users who have multiple device journeys.

**Grain**: USER_ID

**Sources**: `int_web_mta__user_journey`, `WGT.EVENTS.REVENUE`

**Materialization**: table

| Column | Type | Description |
|---|---|---|
| USER_ID | VARCHAR | WGT user account ID |
| REGISTRATION_TIMESTAMP | TIMESTAMP | Web registration timestamp |
| D7_REVENUE | NUMBER | Revenue within 7 days of registration |
| D30_REVENUE | NUMBER | Revenue within 30 days of registration |
| TOTAL_REVENUE | NUMBER | Lifetime revenue post-registration |
| JOURNEY_COUNT | NUMBER | Number of distinct web journeys (for multi-device dedup weighting) |

---

### 4.9 LTV Pipeline

#### `int_ltv__device_revenue`

**Purpose**: Bridges Adjust device installs to user-level revenue via the device mapping table. Produces D1/D7/D30/D180/D365/Total revenue windows per device/install, with a flag indicating whether a user mapping was found. Device mapping is deduplicated to 1 user per device+platform to prevent fan-out in downstream joins.

**Grain**: DEVICE_ID / PLATFORM / INSTALL_TIMESTAMP

**Sources**: `int_adjust_amplitude__device_mapping`, `int_user_cohort__metrics`

**Materialization**: incremental (merge)

| Column | Type | Description |
|---|---|---|
| DEVICE_ID | VARCHAR | Adjust device identifier |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| INSTALL_TIMESTAMP | TIMESTAMP | Install timestamp |
| USER_ID | VARCHAR | Mapped user ID (NULL if no mapping) — deduplicated to 1 per device+platform |
| HAS_USER_MAPPING | BOOLEAN | TRUE if device was matched to a user |
| D1_REVENUE | NUMBER | Revenue within 1 day of install |
| D7_REVENUE | NUMBER | Revenue within 7 days of install |
| D30_REVENUE | NUMBER | Revenue within 30 days of install |
| D180_REVENUE | NUMBER | Revenue within 180 days of install |
| D365_REVENUE | NUMBER | Revenue within 365 days of install |
| TOTAL_REVENUE | NUMBER | Lifetime revenue post-install |

**Known Caveats**: Inherits all limitations of `int_adjust_amplitude__device_mapping` — Android 0% match, iOS limited to IDFV. Device mapping dedup (added 2026-03-09) fixed 310 duplicate rows that were causing fan-out.

---

## 5. Mart Endpoints

### 5.1 Daily Overview

#### `mart_daily_overview_by_platform`

**Purpose**: Daily KPIs broken down by PLATFORM and COUNTRY. Intended for day-to-day operational monitoring. Mobile spend from Adjust API; Desktop spend from Fivetran Facebook + Google (filtered to desktop).

**Grain**: DATE / PLATFORM / COUNTRY

**Sources**: `stg_adjust__report_daily`, `int_spend__unified`, `WGT.EVENTS.REVENUE`, `v_stg_adjust__installs`

**Materialization**: incremental (merge), 7-day lookback

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| PLATFORM | VARCHAR | 'iOS', 'Android', or 'Desktop' |
| COUNTRY | VARCHAR | Country name or code |
| SPEND | NUMBER | Ad spend |
| INSTALLS | NUMBER | New installs |
| REVENUE | NUMBER | Total revenue (IAP + ad) |
| DAU | NUMBER | Daily active users (via ROUNDSTARTED distinct user count) |
| CPI | NUMBER | Cost per install (SPEND / INSTALLS) |
| ROAS | NUMBER | Return on ad spend (REVENUE / SPEND) |

---

#### `mart_daily_business_overview`

**Purpose**: Top-line daily business summary across all platforms. Primary dashboard mart for executive review.

**Grain**: DATE

**Sources**: `stg_adjust__report_daily`, `int_spend__unified`, `WGT.EVENTS.REVENUE`, `WGT.EVENTS.ROUNDSTARTED`

**Materialization**: incremental (merge), 7-day lookback

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| TOTAL_SPEND | NUMBER | Total ad spend across all platforms and channels |
| MOBILE_SPEND | NUMBER | iOS + Android spend from Adjust API |
| DESKTOP_SPEND | NUMBER | Desktop spend from Fivetran (Facebook + Google) |
| TOTAL_INSTALLS | NUMBER | All platform installs |
| TOTAL_REVENUE | NUMBER | All platform revenue |
| DAU | NUMBER | Daily active users across all platforms |
| BLENDED_CPI | NUMBER | TOTAL_SPEND / TOTAL_INSTALLS |
| ROAS | NUMBER | TOTAL_REVENUE / TOTAL_SPEND |
| ARPDAU | NUMBER | TOTAL_REVENUE / DAU |

---

#### `mart_daily_overview_by_platform_measures`

**Purpose**: Single-row Power BI anchor table for DAX measure context. Contains one row to provide a calculation context for measures that are not directly tied to a table's rows.

**Grain**: Single row

**Materialization**: table

---

### 5.2 Executive Summary

#### `mart_exec_summary`

**Purpose**: Campaign-level executive performance summary combining spend, installs (Adjust API + SKAN + Amplitude attribution), and revenue. Includes country normalization and SKAN country inference from campaign name patterns. Includes date grain columns for Power BI granularity slicer.

**Grain**: DATE / AD_PARTNER / CAMPAIGN / PLATFORM / COUNTRY

**Sources**: `stg_adjust__report_daily`, `int_skan__aggregate_attribution`, `int_user_cohort__attribution`, `int_user_cohort__metrics`

**Materialization**: incremental (merge), 7-day lookback

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| AD_PARTNER | VARCHAR | Standardized partner label |
| CAMPAIGN | VARCHAR | Campaign name |
| CAMPAIGN_ID | VARCHAR | Campaign ID |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| COUNTRY | VARCHAR | Country (with normalization applied) |
| SPEND | NUMBER | Adjust API NETWORK_COST |
| ATTRIBUTION_INSTALLS | NUMBER | Adjust API installs + SKAN + Amplitude-attributed |
| API_INSTALLS | NUMBER | Installs from Adjust API report |
| SKAN_INSTALLS | NUMBER | iOS SKAN-attributed installs |
| AMPLITUDE_INSTALLS | NUMBER | Users attributed via Amplitude user properties |
| D7_REVENUE | NUMBER | Cohort D7 revenue from WGT.EVENTS |
| D30_REVENUE | NUMBER | Cohort D30 revenue from WGT.EVENTS |
| ALL_REVENUE | NUMBER | Adjust API ALL_REVENUE (IAP + ad) |
| DATE_YEAR | NUMBER | Year — date grain column for Power BI |
| DATE_QUARTER | NUMBER | Quarter number — date grain column |
| DATE_MONTH | NUMBER | Month number — date grain column |
| DATE_WEEK | DATE | Week start date — date grain column |

---

#### `mart_exec_summary_measures`

**Purpose**: Power BI scaffold view that passes through only additive base columns from `mart_exec_summary`. Pre-computed ratios (CPI, ROAS) are excluded to prevent incorrect aggregation in DAX.

**Grain**: Same as mart_exec_summary

**Source**: `mart_exec_summary`

**Materialization**: view

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| AD_PARTNER | VARCHAR | Standardized partner label |
| CAMPAIGN | VARCHAR | Campaign name |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| COUNTRY | VARCHAR | Country |
| SPEND | NUMBER | Adjust API NETWORK_COST |
| API_INSTALLS | NUMBER | Adjust API installs |
| SKAN_INSTALLS | NUMBER | SKAN installs |
| ATTRIBUTION_INSTALLS | NUMBER | All attribution installs |
| D7_REVENUE | NUMBER | Cohort D7 revenue |
| D30_REVENUE | NUMBER | Cohort D30 revenue |
| ADJUST_ALL_REVENUE | NUMBER | Adjust API ALL_REVENUE (IAP + ad) |
| DATE_YEAR | NUMBER | Year |
| DATE_QUARTER | NUMBER | Quarter |
| DATE_MONTH | NUMBER | Month |
| DATE_WEEK | DATE | Week start |

**Update 2026-03-09:** Removed invalid CAMPAIGN_ID column (not additive — breaks DAX aggregation). Fixed TOTAL_REVENUE → ADJUST_ALL_REVENUE to correctly reference the upstream column.

---

### 5.3 Campaign Performance

#### `mart_campaign_performance_full`

**Purpose**: Most granular campaign + adgroup performance mart. Covers mobile platforms only. Uses ATTRIBUTION_INSTALLS (Adjust API + SKAN) as the install denominator for CPI.

**Grain**: DATE / AD_PARTNER / CAMPAIGN / ADGROUP / PLATFORM

**Sources**: `stg_adjust__report_daily`, `int_skan__aggregate_attribution`

**Materialization**: incremental (merge), 7-day lookback

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| AD_PARTNER | VARCHAR | Standardized partner label |
| CAMPAIGN | VARCHAR | Campaign name |
| CAMPAIGN_ID | VARCHAR | Campaign ID |
| ADGROUP | VARCHAR | Ad group name |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| SPEND | NUMBER | Ad spend (NETWORK_COST) |
| API_INSTALLS | NUMBER | Adjust API reported installs |
| SKAN_INSTALLS | NUMBER | SKAN installs (iOS only) |
| ATTRIBUTION_INSTALLS | NUMBER | API_INSTALLS + SKAN_INSTALLS |
| CPI | NUMBER | SPEND / ATTRIBUTION_INSTALLS |
| REVENUE | NUMBER | Adjust API REVENUE (IAP) |
| ALL_REVENUE | NUMBER | Adjust API ALL_REVENUE |
| ROAS | NUMBER | ALL_REVENUE / SPEND |
| IMPRESSIONS | NUMBER | Ad impressions |
| CLICKS | NUMBER | Ad clicks |
| CTR | NUMBER | CLICKS / IMPRESSIONS |
| IPM | NUMBER | Installs per thousand impressions |

---

#### `mart_campaign_performance_full_mta`

**Purpose**: Campaign performance with six attribution model install credits displayed side by side. Enables comparison of Adjust's last-touch installs against five MTA methodologies.

**Grain**: AD_PARTNER / CAMPAIGN / PLATFORM / DATE

**Sources**: `stg_adjust__report_daily`, `int_mta__touchpoint_credit`

**Materialization**: incremental (merge), 7-day lookback

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| AD_PARTNER | VARCHAR | Standardized partner label |
| CAMPAIGN | VARCHAR | Campaign name |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| SPEND | NUMBER | Ad spend |
| ADJUST_INSTALLS | NUMBER | Adjust last-touch installs (API) |
| MTA_LAST_TOUCH | NUMBER | SUM(CREDIT_LAST_TOUCH) fractional installs |
| MTA_FIRST_TOUCH | NUMBER | SUM(CREDIT_FIRST_TOUCH) fractional installs |
| MTA_LINEAR | NUMBER | SUM(CREDIT_LINEAR) fractional installs |
| MTA_TIME_DECAY | NUMBER | SUM(CREDIT_TIME_DECAY) fractional installs |
| MTA_POSITION_BASED | NUMBER | SUM(CREDIT_POSITION_BASED) fractional installs |
| MTA_RECOMMENDED | NUMBER | SUM(CREDIT_RECOMMENDED) fractional installs |

---

### 5.4 MTA Attribution Marts

#### `mta__campaign_performance`

**Purpose**: MTA campaign performance with fractional install credits and revenue windows (D7/D30/Total) for each of the six attribution models. Primary MTA output for tactical campaign optimization.

**Grain**: AD_PARTNER / CAMPAIGN / PLATFORM / DATE

**Sources**: `int_mta__touchpoint_credit`, `int_user_cohort__metrics`

**Materialization**: incremental (merge)

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Install date |
| AD_PARTNER | VARCHAR | Ad network partner |
| CAMPAIGN | VARCHAR | Campaign name |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| ADJUST_INSTALLS | NUMBER | Adjust API last-touch installs |
| MTA_LAST_TOUCH | NUMBER | Fractional installs — last touch |
| MTA_FIRST_TOUCH | NUMBER | Fractional installs — first touch |
| MTA_LINEAR | NUMBER | Fractional installs — linear |
| MTA_TIME_DECAY | NUMBER | Fractional installs — time decay |
| MTA_POSITION_BASED | NUMBER | Fractional installs — position based |
| D7_REVENUE_LAST_TOUCH | NUMBER | D7 revenue allocated by last-touch credit |
| D7_REVENUE_TIME_DECAY | NUMBER | D7 revenue allocated by time-decay credit |
| D30_REVENUE_LAST_TOUCH | NUMBER | D30 revenue allocated by last-touch credit |
| D30_REVENUE_TIME_DECAY | NUMBER | D30 revenue allocated by time-decay credit |
| TOTAL_REVENUE_LAST_TOUCH | NUMBER | Lifetime revenue — last touch allocated |
| TOTAL_REVENUE_TIME_DECAY | NUMBER | Lifetime revenue — time decay allocated |

**Known Caveats**: Coverage limited to iOS non-SAN traffic (~7.37% of iOS installs). All Android rows will show 0 MTA credits.

---

#### `mta__campaign_ltv`

**Purpose**: MTA-attributed LTV per campaign. Extends `mta__campaign_performance` with full D1/D7/D30/D180/D365/Total revenue windows from `int_ltv__device_revenue`. Includes coverage metrics showing what fraction of installs have MTA data.

**Grain**: AD_PARTNER / CAMPAIGN / PLATFORM / DATE

**Sources**: `int_mta__touchpoint_credit`, `int_ltv__device_revenue`

**Materialization**: incremental (merge)

| Column | Type | Description |
|---|---|---|
| (Same install/spend columns as mta__campaign_performance) | | |
| D1_REVENUE_[MODEL] | NUMBER | D1 revenue allocated by each of 6 models |
| D7_REVENUE_[MODEL] | NUMBER | D7 revenue |
| D30_REVENUE_[MODEL] | NUMBER | D30 revenue |
| D180_REVENUE_[MODEL] | NUMBER | D180 revenue |
| D365_REVENUE_[MODEL] | NUMBER | D365 revenue |
| TOTAL_REVENUE_[MODEL] | NUMBER | Lifetime revenue |
| MTA_COVERAGE_PCT | NUMBER | % of installs with at least one MTA touchpoint |

**Known Caveats**: Inherits all limitations of device mapping and MTA pipelines. Never deployed to production.

---

#### `mart_network_performance_mta`

**Purpose**: Network-level (no campaign dimension) rollup of MTA performance. Aggregates fractional install credits and revenue to the AD_PARTNER + PLATFORM + DATE grain.

**Grain**: DATE / AD_PARTNER / PLATFORM

**Source**: `mta__campaign_performance`

**Materialization**: incremental (merge)

---

#### `rpt__mta_vs_adjust_installs`

**Purpose**: Audit model for diagnosing MTA coverage. Compares six install perspectives side by side: Adjust API, Adjust S3, and five MTA models. Key diagnostic metrics: MTA_COVERAGE_PCT (what % of S3 installs have at least one MTA touchpoint), MTA_CREDIT_SHIFT_PCT (how much credit shifts between last-touch and time-decay).

**Grain**: AD_PARTNER / PLATFORM / DATE

**Sources**: `stg_adjust__report_daily`, `v_stg_adjust__installs`, `int_mta__touchpoint_credit`

**Materialization**: table

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Date |
| AD_PARTNER | VARCHAR | Ad network |
| PLATFORM | VARCHAR | Platform |
| API_INSTALLS | NUMBER | Adjust API reported installs |
| S3_INSTALLS | NUMBER | Adjust S3 raw install count |
| MTA_LAST_TOUCH | NUMBER | MTA last-touch fractional installs |
| MTA_FIRST_TOUCH | NUMBER | MTA first-touch fractional installs |
| MTA_LINEAR | NUMBER | MTA linear fractional installs |
| MTA_TIME_DECAY | NUMBER | MTA time-decay fractional installs |
| MTA_POSITION_BASED | NUMBER | MTA position-based fractional installs |
| MTA_COVERAGE_PCT | NUMBER | S3 installs with ≥1 MTA touchpoint / total S3 installs |
| MTA_CREDIT_SHIFT_PCT | NUMBER | (MTA_TIME_DECAY - MTA_LAST_TOUCH) / MTA_LAST_TOUCH |

---

### 5.5 LTV

#### `mart_ltv__cohort_summary`

**Purpose**: Classic cohort LTV table. Uses Adjust last-touch attribution (from `int_user_cohort__attribution`) — works for both iOS and Android platforms with full coverage. Outputs D1/D7/D30/D180/D365/Total revenue per cohort, LTV per matured user, payer rates, and retention rates.

**Grain**: INSTALL_DATE / AD_PARTNER / CAMPAIGN / PLATFORM

**Sources**: `int_user_cohort__attribution`, `int_user_cohort__metrics`

**Materialization**: incremental (merge), 370-day lookback

| Column | Type | Description |
|---|---|---|
| INSTALL_DATE | DATE | Cohort install date |
| AD_PARTNER | VARCHAR | Attributed ad partner |
| CAMPAIGN | VARCHAR | Attributed campaign |
| PLATFORM | VARCHAR | 'iOS' or 'Android' |
| USERS | NUMBER | Total users in cohort |
| D1_MATURED_USERS | NUMBER | Users who have reached D1 maturity |
| D7_MATURED_USERS | NUMBER | Users who have reached D7 maturity |
| D30_MATURED_USERS | NUMBER | Users who have reached D30 maturity |
| D180_MATURED_USERS | NUMBER | Users who have reached D180 maturity |
| D365_MATURED_USERS | NUMBER | Users who have reached D365 maturity |
| D1_REVENUE | NUMBER | Total D1 revenue for cohort |
| D7_REVENUE | NUMBER | Total D7 revenue for cohort |
| D30_REVENUE | NUMBER | Total D30 revenue for cohort |
| D180_REVENUE | NUMBER | Total D180 revenue for cohort |
| D365_REVENUE | NUMBER | Total D365 revenue for cohort |
| TOTAL_REVENUE | NUMBER | Total lifetime revenue for cohort |
| LTV_D1 | NUMBER | D1_REVENUE / D1_MATURED_USERS |
| LTV_D7 | NUMBER | D7_REVENUE / D7_MATURED_USERS |
| LTV_D30 | NUMBER | D30_REVENUE / D30_MATURED_USERS |
| LTV_D180 | NUMBER | D180_REVENUE / D180_MATURED_USERS |
| LTV_D365 | NUMBER | D365_REVENUE / D365_MATURED_USERS |
| D7_PAYER_RATE | NUMBER | IS_D7_PAYER users / D7_MATURED_USERS |
| D30_PAYER_RATE | NUMBER | IS_D30_PAYER users / D30_MATURED_USERS |
| D1_RETENTION | NUMBER | D1_RETAINED users / D1_MATURED_USERS |
| D7_RETENTION | NUMBER | D7_RETAINED users / D7_MATURED_USERS |
| D30_RETENTION | NUMBER | D30_RETAINED users / D30_MATURED_USERS |

---

### 5.6 MMM

#### `mmm__daily_channel_summary`

**Purpose**: Primary input table for Media Mix Modeling. Contains DATE + PLATFORM + CHANNEL grain with a zero-filled date spine (no gaps, even for channels with no spend on a given day). Spend from `int_spend__unified`, installs from S3 + SKAN, revenue from Adjust API (mobile) and WGT.EVENTS (desktop).

**Grain**: DATE / PLATFORM / CHANNEL (zero-filled — all combinations present for all dates)

**Sources**: `int_mmm__daily_channel_spend`, `int_mmm__daily_channel_installs`, `int_mmm__daily_channel_revenue`, date spine

**Materialization**: table (full rebuild)

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| PLATFORM | VARCHAR | 'iOS', 'Android', or 'Desktop' |
| CHANNEL | VARCHAR | Ad channel name |
| SPEND | NUMBER | Total spend (0 if no spend on this date) |
| INSTALLS | NUMBER | Total installs (0 if none) |
| REVENUE | NUMBER | Direct/IAP revenue |
| AD_REVENUE | NUMBER | In-app advertising revenue |

**Key Business Logic**: Date spine ensures every DATE/PLATFORM/CHANNEL combination has a row even with zero values — required for time-series modeling in MMM tools.

---

#### `mmm__weekly_channel_summary`

**Purpose**: Weekly rollup of `mmm__daily_channel_summary`. KPIs are recomputed from weekly sums (not averaged). Used for lower-frequency MMM runs.

**Grain**: WEEK_START / PLATFORM / CHANNEL

**Source**: `mmm__daily_channel_summary`

**Materialization**: table (full rebuild)

| Column | Type | Description |
|---|---|---|
| WEEK_START | DATE | Monday of the report week |
| PLATFORM | VARCHAR | 'iOS', 'Android', or 'Desktop' |
| CHANNEL | VARCHAR | Ad channel name |
| SPEND | NUMBER | Weekly total spend |
| INSTALLS | NUMBER | Weekly total installs |
| REVENUE | NUMBER | Weekly total revenue |
| AD_REVENUE | NUMBER | Weekly total ad revenue |

---

### 5.7 Web Attribution

#### `rpt__web_attribution`

**Purpose**: Web traffic and registration attribution report. Combines anonymous web session data from Amplitude with MTA registration attribution and cross-platform revenue. Sessions cover ~86% of web traffic (anonymous visitors who did not register).

**Grain**: DATE / UTM_SOURCE / UTM_MEDIUM / UTM_CAMPAIGN

**Sources**: `AMPLITUDEANALYTICS.EVENTS_726530` (raw web events), `int_web_mta__touchpoint_credit`, `int_web_mta__user_revenue`

**Materialization**: table (full rebuild)

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Session date |
| UTM_SOURCE | VARCHAR | Traffic source (organic, google, facebook, etc.) |
| UTM_MEDIUM | VARCHAR | Traffic medium (cpc, email, referral, etc.) |
| UTM_CAMPAIGN | VARCHAR | Campaign name |
| SESSIONS | NUMBER | Total web sessions (anonymous + identified) |
| REGISTRATIONS_LAST_TOUCH | NUMBER | Registrations attributed (last-touch) |
| REGISTRATIONS_TIME_DECAY | NUMBER | Registrations attributed (time-decay) |
| D7_REVENUE_LAST_TOUCH | NUMBER | D7 post-registration revenue — last touch |
| D7_REVENUE_TIME_DECAY | NUMBER | D7 post-registration revenue — time decay |
| D30_REVENUE_LAST_TOUCH | NUMBER | D30 revenue — last touch |
| D30_REVENUE_TIME_DECAY | NUMBER | D30 revenue — time decay |
| TOTAL_REVENUE_LAST_TOUCH | NUMBER | Lifetime revenue — last touch |
| TOTAL_REVENUE_TIME_DECAY | NUMBER | Lifetime revenue — time decay |

---

### 5.8 Spend

#### `facebook_conversions`

**Purpose**: Facebook conversion actions with spend allocated proportionally using the DIVIDEND divisor. Provides actionable conversion data for Facebook campaign optimization.

**Grain**: DATE / AD_ID / ACTION_TYPE

**Sources**: `v_stg_facebook_conversions`, `v_stg_facebook_spend`

**Materialization**: incremental (merge), 7-day lookback

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Report date |
| AD_ID | VARCHAR | Facebook ad ID |
| AD_NAME | VARCHAR | Ad name |
| CAMPAIGN_ID | VARCHAR | Campaign ID |
| CAMPAIGN | VARCHAR | Campaign name |
| ACTION_TYPE | VARCHAR | Conversion action type |
| VALUE | NUMBER | Conversion count or value |
| SPEND | NUMBER | Spend allocated to this action type (total / DIVIDEND) |
| DIVIDEND | NUMBER | Distinct action type count for this ad/date |

---

### 5.9 SKAN, Combined Attribution & Blended Performance

#### `mart_skan__campaign_performance`

**Purpose**: Standalone SKAN campaign performance mart joining SKAdNetwork postback data with Adjust API spend data for iOS. Provides SKAN-specific metrics including conversion value distributions, fidelity types (StoreKit-rendered vs view-through), win rates, and efficiency metrics (SKAN CPI, CPM, CTR, CVR). Country is inferred from campaign name patterns. Self-attributing networks (Meta, Google) are aggregated to partner/date level with campaign = '__none__'.

**Grain**: AD_PARTNER + CAMPAIGN_NAME + INSTALL_DATE + COUNTRY

**Sources**: `int_skan__aggregate_attribution`, `stg_adjust__report_daily`, `network_mapping`

**Materialization**: incremental (merge)

| Column | Type | Description |
|---|---|---|
| INSTALL_DATE | DATE | SKAN install date |
| AD_PARTNER | VARCHAR | Standardized partner name (Meta, Google, AppLovin, etc.) |
| CAMPAIGN_NAME | VARCHAR | Campaign name from SKAN postback. '__none__' for SANs |
| COUNTRY | VARCHAR | Country inferred from campaign name patterns. 'unknown' when not extractable |
| COST | NUMBER | iOS ad spend from Adjust API |
| CLICKS | NUMBER | Ad clicks |
| IMPRESSIONS | NUMBER | Ad impressions |
| ADJUST_INSTALLS | NUMBER | Adjust API installs (iOS only) |
| SKAN_INSTALL_COUNT | NUMBER | Total SKAN installs (new + redownloads) |
| SKAN_NEW_INSTALLS | NUMBER | SKAN new install count (excludes redownloads) |
| SKAN_REDOWNLOADS | NUMBER | SKAN redownload count |
| SKAN_CPI | NUMBER | Cost per SKAN new install (COST / SKAN_NEW_INSTALLS) |
| CPM | NUMBER | Cost per thousand impressions |
| CTR | NUMBER | Click-through rate (CLICKS / IMPRESSIONS) |
| SKAN_CVR | NUMBER | SKAN conversion rate (SKAN_NEW_INSTALLS / CLICKS) |
| WIN_RATE | NUMBER | Fraction of postbacks where this network won SKAN attribution |
| STOREKIT_RENDERED_RATE | NUMBER | Fraction of installs that were StoreKit-rendered (high fidelity) |
| VIEW_THROUGH_RATE | NUMBER | Fraction of installs that were view-through (low fidelity) |
| CV_COVERAGE_RATE | NUMBER | Fraction of installs with a non-null conversion value |
| AVG_CONVERSION_VALUE | NUMBER | Average SKAN conversion value (proxy for engagement quality) |
| MAX_CONVERSION_VALUE | NUMBER | Maximum SKAN conversion value |
| INSTALLS_WITH_CV | NUMBER | Count of installs with a conversion value |
| CV_BUCKET_0 | NUMBER | Installs with conversion value = 0 |
| CV_BUCKET_1_10 | NUMBER | Installs with conversion value 1-10 |
| CV_BUCKET_11_20 | NUMBER | Installs with conversion value 11-20 |
| CV_BUCKET_21_40 | NUMBER | Installs with conversion value 21-40 |
| CV_BUCKET_41_63 | NUMBER | Installs with conversion value 41-63 |
| STOREKIT_RENDERED_COUNT | NUMBER | Raw count of StoreKit-rendered installs |
| VIEW_THROUGH_COUNT | NUMBER | Raw count of view-through installs |
| WINNING_POSTBACKS | NUMBER | Count of winning SKAN postbacks |
| SKAN_V3_COUNT | NUMBER | SKAN version 3 postback count |
| SKAN_V4_COUNT | NUMBER | SKAN version 4 postback count |

**SKAN Limitations**:
- No device identifiers — cannot join to individual users or revenue
- SKAN 3.0: campaign-level only (no adgroup/creative granularity)
- SANs (Meta, Google): campaign names don't match Adjust API spend data — aggregated to partner/date level
- Conversion values are a proxy for engagement, not actual revenue

---

#### `mart_attribution__combined`

**Purpose**: Combined web + mobile multi-touch attribution view. Stacks mobile MTA (app installs from `mta__campaign_performance`) and web MTA (registrations from `rpt__web_attribution`) into a single table with aligned columns using UNION ALL. Use ACQUISITION_TYPE to filter: 'mobile_install' or 'web_registration'. Both pipelines use the same 5 MTA models. Conversions are NOT deduplicated between web and mobile. Spend is mobile-only.

**Grain**: DATE + ACQUISITION_TYPE + CHANNEL + CAMPAIGN + PLATFORM

**Sources**: `mta__campaign_performance`, `rpt__web_attribution`

**Materialization**: table

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Install date (mobile) or session date (web) |
| ACQUISITION_TYPE | VARCHAR | 'mobile_install' or 'web_registration' |
| CHANNEL | VARCHAR | AD_PARTNER for mobile, TRAFFIC_SOURCE for web |
| CAMPAIGN | VARCHAR | Campaign name (mobile) or utm_campaign (web) |
| PLATFORM | VARCHAR | iOS/Android for mobile, 'Web' for web |
| COST | NUMBER | Ad spend (mobile only; 0 for web) |
| IMPRESSIONS | NUMBER | Ad impressions (mobile only; 0 for web) |
| CLICKS | NUMBER | Ad clicks (mobile only; 0 for web) |
| CONVERSIONS_LAST_TOUCH | NUMBER | Attributed conversions — last touch |
| CONVERSIONS_FIRST_TOUCH | NUMBER | Attributed conversions — first touch |
| CONVERSIONS_LINEAR | NUMBER | Attributed conversions — linear |
| CONVERSIONS_TIME_DECAY | NUMBER | Attributed conversions — time decay |
| CONVERSIONS_POSITION_BASED | NUMBER | Attributed conversions — position based |
| CONVERSIONS_RECOMMENDED | NUMBER | Attributed conversions — recommended model (time-decay for both) |
| D7_REVENUE_LAST_TOUCH | NUMBER | 7-day revenue — last touch |
| D7_REVENUE_FIRST_TOUCH | NUMBER | 7-day revenue — first touch |
| D7_REVENUE_LINEAR | NUMBER | 7-day revenue — linear |
| D7_REVENUE_TIME_DECAY | NUMBER | 7-day revenue — time decay |
| D7_REVENUE_POSITION_BASED | NUMBER | 7-day revenue — position based |
| D7_REVENUE_RECOMMENDED | NUMBER | 7-day revenue — recommended model |
| D30_REVENUE_LAST_TOUCH | NUMBER | 30-day revenue — last touch |
| D30_REVENUE_FIRST_TOUCH | NUMBER | 30-day revenue — first touch |
| D30_REVENUE_LINEAR | NUMBER | 30-day revenue — linear |
| D30_REVENUE_TIME_DECAY | NUMBER | 30-day revenue — time decay |
| D30_REVENUE_POSITION_BASED | NUMBER | 30-day revenue — position based |
| D30_REVENUE_RECOMMENDED | NUMBER | 30-day revenue — recommended model |
| TOTAL_REVENUE_LAST_TOUCH | NUMBER | Lifetime revenue — last touch |
| TOTAL_REVENUE_FIRST_TOUCH | NUMBER | Lifetime revenue — first touch |
| TOTAL_REVENUE_LINEAR | NUMBER | Lifetime revenue — linear |
| TOTAL_REVENUE_TIME_DECAY | NUMBER | Lifetime revenue — time decay |
| TOTAL_REVENUE_POSITION_BASED | NUMBER | Lifetime revenue — position based |
| TOTAL_REVENUE_RECOMMENDED | NUMBER | Lifetime revenue — recommended model |
| UNIQUE_USERS | NUMBER | Unique devices (mobile) or unique registrants (web) |
| CPI_RECOMMENDED | NUMBER | Cost per conversion — recommended model. Mobile only (NULL for web) |
| D7_ROAS_RECOMMENDED | NUMBER | D7 ROAS — recommended model. Mobile only |
| D30_ROAS_RECOMMENDED | NUMBER | D30 ROAS — recommended model. Mobile only |
| TOTAL_ROAS_RECOMMENDED | NUMBER | Lifetime ROAS — recommended model. Mobile only |

**Key Business Logic**:
- Mobile conversions = fractional installs; Web conversions = fractional registrations
- Web has no RECOMMENDED model — uses time-decay as the recommended default
- Spend, impressions, clicks are 0 for web rows (web spend not tracked at campaign level)
- CPI/ROAS metrics are NULL for web rows

---

#### `mart_blended_performance`

**Purpose**: Blended web + mobile performance view aggregated to channel/campaign/date. Full outer joins mobile spend/installs (from `mta__campaign_performance`) with web sessions/registrations (from `rpt__web_attribution`). Computes blended efficiency metrics that account for web value driven by mobile ad spend. Unlike `mart_attribution__combined` (separate rows per acquisition type), this model aggregates both pipelines into a single row per channel+campaign+date.

**Grain**: DATE + CHANNEL + CAMPAIGN

**Sources**: `mta__campaign_performance`, `rpt__web_attribution`

**Materialization**: table

| Column | Type | Description |
|---|---|---|
| DATE | DATE | Event date |
| CHANNEL | VARCHAR | Unified channel name (AD_PARTNER for mobile, TRAFFIC_SOURCE for web) |
| CAMPAIGN | VARCHAR | Campaign name |
| TOTAL_SPEND | NUMBER | Total ad spend (mobile only) |
| TOTAL_CONVERSIONS | NUMBER | Mobile installs + web registrations (time-decay) |
| TOTAL_D7_REVENUE | NUMBER | Mobile + web 7-day revenue (time-decay) |
| TOTAL_D30_REVENUE | NUMBER | Mobile + web 30-day revenue (time-decay) |
| TOTAL_REVENUE | NUMBER | Mobile + web lifetime revenue (time-decay) |
| BLENDED_CPA | NUMBER | TOTAL_SPEND / TOTAL_CONVERSIONS |
| BLENDED_D7_ROAS | NUMBER | TOTAL_D7_REVENUE / TOTAL_SPEND |
| BLENDED_D30_ROAS | NUMBER | TOTAL_D30_REVENUE / TOTAL_SPEND |
| BLENDED_TOTAL_ROAS | NUMBER | TOTAL_REVENUE / TOTAL_SPEND |
| MOBILE_SPEND | NUMBER | Mobile ad spend |
| MOBILE_IMPRESSIONS | NUMBER | Mobile ad impressions |
| MOBILE_CLICKS | NUMBER | Mobile ad clicks |
| MOBILE_INSTALLS | NUMBER | Mobile installs (time-decay) |
| MOBILE_D7_REVENUE | NUMBER | Mobile 7-day revenue |
| MOBILE_D30_REVENUE | NUMBER | Mobile 30-day revenue |
| MOBILE_TOTAL_REVENUE | NUMBER | Mobile lifetime revenue |
| MOBILE_UNIQUE_DEVICES | NUMBER | Mobile unique devices |
| WEB_SESSIONS | NUMBER | Web sessions (anonymous + identified) |
| WEB_UNIQUE_DEVICES | NUMBER | Web unique devices |
| WEB_REGISTRATIONS | NUMBER | Web registrations (time-decay) |
| WEB_D7_REVENUE | NUMBER | Web 7-day post-registration revenue |
| WEB_D30_REVENUE | NUMBER | Web 30-day post-registration revenue |
| WEB_TOTAL_REVENUE | NUMBER | Web lifetime post-registration revenue |
| WEB_PAYERS | NUMBER | Web payers |
| HAS_MOBILE_DATA | BOOLEAN | TRUE if row has mobile install or spend data |
| HAS_WEB_DATA | BOOLEAN | TRUE if row has web session or registration data |

**Key Business Logic**:
- FULL OUTER JOIN on DATE + CHANNEL + CAMPAIGN (case-insensitive) — rows can have mobile-only, web-only, or both
- Blended efficiency metrics (CPA/ROAS) are NULL when spend is 0
- All revenue uses time-decay model (recommended)

---

## 6. Seeds

### `country_codes`

**Purpose**: ISO country code reference table used for country resolution in Google Ads (CRITERION_ID - 2000 → country code) and Facebook Ads (country code normalization).

**Columns**:

| Column | Description |
|---|---|
| ALPHA_2 | ISO 3166-1 alpha-2 code (e.g., US, GB) |
| ALPHA_3 | ISO 3166-1 alpha-3 code (e.g., USA, GBR) |
| NUMERIC | ISO 3166-1 numeric code (used for Google Ads: CRITERION_ID = NUMERIC + 2000) |
| NAME | Full country name |

**Used by**: `v_stg_google_ads__country_spend`, `v_stg_facebook_spend`

---

### `network_mapping`

**Purpose**: Maps raw Adjust network names (as they appear in REPORT_DAILY_RAW and S3 events) to standardized AD_PARTNER labels used consistently across all downstream models.

**Columns**:

| Column | Description |
|---|---|
| ADJUST_NETWORK_NAME | Raw network name as reported by Adjust |
| AD_PARTNER | Standardized label: Meta, Google, TikTok, Apple, Unity, AppLovin, Moloco, Organic, etc. |

**Used by**: `int_spend__unified`, `v_stg_adjust__installs` (via `map_ad_partner()` macro), `v_stg_adjust__touchpoints`

**Note**: The `map_ad_partner()` macro implements this mapping as a SQL CASE expression based on this seed, enabling consistent partner naming across all staging and mart models.

---

## 7. Known Limitations Summary

| Limitation | Affected Models | Impact | Remediation Path |
|---|---|---|---|
| **Android MTA: 0% match rate** | `int_mta__user_journey`, `int_mta__touchpoint_credit`, all `mta__*` marts | MTA credits for Android are always 0. Android campaigns cannot be evaluated with MTA. | Configure Amplitude SDK with `useAdvertisingIdForDeviceId()` on Android to use GPS_ADID instead of random UUID. |
| **iOS IDFA: ~7.37% availability** | `int_mta__user_journey`, all `mta__*` marts | Only ~7% of iOS installs have touchpoint matching. MTA understates iOS coverage. | No full fix possible under Apple ATT framework. Consider probabilistic matching as supplement. |
| **Self-attributing networks (SANs): 0% touchpoint data** | `int_mta__user_journey`, all `mta__*` marts | Meta, Google, Apple Search Ads, and TikTok share no touchpoint data with Adjust. These networks (majority of spend) cannot be MTA-attributed. | Inherent limitation of the SAN model. MMM is the recommended alternative for these networks. |
| **Device mapping never deployed** | `int_adjust_amplitude__device_mapping`, `int_ltv__device_revenue`, `mta__campaign_ltv` | Device-level LTV attribution is non-functional in production. | Requires Android SDK fix above plus production deployment. |
| ~~**No Facebook source YAML**~~ | All `v_stg_facebook_*` models | ~~Database/schema name changes require manual SQL updates.~~ | ✅ **Resolved** — `_facebook__sources.yml` added; all 7 FB models now use `{{ source() }}` refs. |
| **Retention uses ROUNDSTARTED, not session open** | `int_user_cohort__metrics`, `mart_ltv__cohort_summary` | Users who opened the app but did not start a round are not counted as retained. Retention rates may be understated. | Deliberate tradeoff for compute cost. Revisit if Amplitude compute costs allow. |
| **Desktop spend lacks platform dimension in Fivetran** | `int_spend__unified`, `mmm__daily_channel_summary` | Facebook and Google Fivetran data does not carry a PLATFORM column. Desktop platform is inferred from campaign name keywords or assumed. | Enforce platform naming convention in campaign names; or use Fivetran's platform breakdown if available. |
| **Adjust API revenue uses last-touch attribution** | `stg_adjust__report_daily`, `mart_exec_summary`, all API-revenue models | Revenue in the Adjust API report is attributed to the last-touch channel only — multi-touch revenue distribution is not reflected. | MMM provides a channel-weighted revenue view. MTA revenue allocation in `mta__campaign_performance` addresses this for covered traffic. |
| **SKAN country often missing** | `int_skan__aggregate_attribution`, `mart_exec_summary` | SKAdNetwork postbacks frequently omit country. Country is inferred from campaign name patterns where possible but may be NULL. | Apple Privacy limitation — no full remediation available. |
