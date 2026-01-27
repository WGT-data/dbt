# WGT Mobile Attribution dbt Project

This dbt project builds the data models for WGT mobile app attribution, connecting Adjust install data with Amplitude user behavior to calculate campaign performance metrics including installs, revenue, retention, and ROAS.

## Quick Reference

| Model | Purpose | Grain |
|-------|---------|-------|
| `mart_campaign_performance_full` | Primary reporting model with all metrics | Partner/Campaign/Adgroup/Platform/Date |
| `int_user_cohort__attribution` | User-level install attribution | User/Platform |
| `int_user_cohort__metrics` | User-level revenue and retention | User/Platform |
| `int_skan__aggregate_attribution` | iOS SKAN aggregate installs (no user IDs) | Partner/Campaign/Date |

## Data Flow

```
Adjust Install Data          Amplitude Events
       │                           │
       ▼                           ▼
┌─────────────────┐    ┌─────────────────────────┐
│ stg_adjust__*   │    │ v_stg_amplitude__*      │
│ (iOS/Android)   │    │ (events, merge_ids)     │
└────────┬────────┘    └───────────┬─────────────┘
         │                         │
         │    ┌────────────────────┘
         │    │
         ▼    ▼
┌─────────────────────────────────┐
│ int_adjust_amplitude__device_   │
│ mapping                         │
│ (links Adjust device to         │
│  Amplitude user)                │
└────────────────┬────────────────┘
                 │
         ┌───────┴───────┐
         ▼               ▼
┌─────────────────┐  ┌─────────────────┐
│ int_user_cohort │  │ int_user_cohort │
│ __attribution   │  │ __metrics       │
│ (install source)│  │ (revenue/       │
│                 │  │  retention)     │
└────────┬────────┘  └────────┬────────┘
         │                    │
         └──────────┬─────────┘
                    ▼
         ┌─────────────────────┐      ┌─────────────────┐
         │ mart_campaign_      │◄─────│ Supermetrics    │
         │ performance_full    │      │ (spend data)    │
         └─────────────────────┘      └─────────────────┘
```

## Model Details

### Staging Models

#### Adjust (`models/staging/adjust/`)
Raw install, click, impression, and SKAN event data from Adjust S3 exports.

Key tables:
- `stg_adjust__ios_activity_install` - iOS install events with IDFV
- `stg_adjust__android_activity_install` - Android install events with GPS_ADID
- `stg_adjust__ios_activity_sk_install` - iOS SKAN postbacks (no device IDs)
- `stg_adjust__ios_activity_impression` - iOS ad impressions (takes ~30 min to build)

#### Amplitude (`models/staging/amplitude/`)
- `v_stg_amplitude__events` - All product analytics events
- `v_stg_amplitude__merge_ids` - Device-to-user ID mappings

#### Supermetrics (`models/staging/supermetrics/`)
- `stg_supermetrics__adj_campaign` - Campaign spend data from Adjust Network API via Supermetrics

### Intermediate Models

#### `int_adjust_amplitude__device_mapping`
Links Adjust device IDs (IDFV/GPS_ADID) to Amplitude user IDs using the merge_ids table.

**Key fields:**
- `ADJUST_DEVICE_ID` - IDFV (iOS) or GPS_ADID (Android)
- `AMPLITUDE_USER_ID` - Numeric user identifier in Amplitude
- `PLATFORM` - iOS or Android
- `FIRST_SEEN_AT` - First time this device was seen

#### `int_user_cohort__attribution`
Assigns each user to their install source (network, campaign, adgroup).

**Logic:**
1. Joins device mapping to Adjust install events
2. Takes first install per user (by timestamp)
3. Standardizes partner names via `network_mapping` seed

**Key fields:**
- `USER_ID`, `PLATFORM` - Primary key
- `AD_PARTNER` - Standardized partner name (Facebook, Unity Ads, etc.)
- `NETWORK_NAME` - Raw Adjust network name
- `CAMPAIGN_NAME`, `ADGROUP_NAME`, `CREATIVE_NAME`
- `INSTALL_DATE`, `INSTALL_TIME`

#### `int_user_cohort__metrics`
Calculates revenue and retention metrics per user.

**Revenue calculation:**
- Joins users to Amplitude `Revenue` events
- Calculates D7, D30, and lifetime revenue
- Separates purchase revenue (`tu='direct'`) from ad revenue (`tu='indirect'`)

**Retention calculation:**
- Uses `ClientOpened` event type to detect app opens
- D1/D7/D30 retained = user opened app exactly 1/7/30 days after install
- Maturity flags indicate if enough time has passed to measure

**IMPORTANT: Retention Data Limitation**
The `ClientOpened` event only has reliable data from **December 2025 forward**. Retention metrics for cohorts before this date will show near-zero values because the historical event data does not exist. When analyzing retention, filter to `DATE >= '2025-12-01'`.

#### `int_skan__aggregate_attribution`
Aggregates iOS SKAdNetwork postbacks at the campaign level.

**Why this exists:**
SKAN postbacks have NO device identifiers due to Apple's privacy framework. These installs cannot be joined to individual users, so they must be tracked separately as aggregates.

**Key fields:**
- `PARTNER`, `CAMPAIGN_NAME`, `INSTALL_DATE` - Grain
- `INSTALL_COUNT`, `NEW_INSTALL_COUNT`, `REDOWNLOAD_COUNT`
- `AVG_CONVERSION_VALUE` - Proxy for user quality
- Conversion value distribution buckets (CV_BUCKET_0, CV_BUCKET_1_10, etc.)

**Note:** There is potential overlap between SKAN installs and device-level installs. Users who consented to tracking appear in both. Deduplication logic is not yet implemented.

### Mart Models

#### `mart_campaign_performance_full`
The primary reporting model combining spend, installs, revenue, and retention.

**Join logic:**
- FULL OUTER JOIN between Supermetrics spend data and cohort metrics
- Matches on: DATE, AD_PARTNER, CAMPAIGN_NAME, ADGROUP_NAME, PLATFORM
- Partner names are case-insensitive matched

**Metrics included:**
- **Spend:** Cost, Clicks, Impressions
- **Installs:** ADJUST_INSTALLS (from Supermetrics), ATTRIBUTION_INSTALLS (from device mapping)
- **Efficiency:** CPI, CPM, CTR, CVR, IPM
- **Revenue:** Total, D7, D30 (purchase + ad revenue separately)
- **ROAS:** Total, D7, D30
- **ARPI/ARPPU:** Revenue per install / per paying user
- **Retention:** D1, D7, D30 rates with matured user denominators

**Unique key:** `AD_PARTNER`, `CAMPAIGN_NAME`, `ADGROUP_NAME`, `PLATFORM`, `DATE`

## Known Issues and Nuances

### 1. Retention Data Only Valid from December 2025
The `ClientOpened` Amplitude event only has reliable USER_ID population from December 2025 forward. For earlier cohorts, retention will appear as 0% because we cannot match users to their app open events.

**Workaround:** Filter dashboards to `DATE >= '2025-12-01'` for retention analysis.

### 2. Spend Data Cutoff
Supermetrics spend data currently stops at **December 8, 2025**. This means recent dates will show installs and revenue but $0 cost.

### 3. SKAN vs Device-Level Overlap
SKAN aggregate installs (`int_skan__aggregate_attribution`) may overlap with device-level installs (`int_user_cohort__attribution`) for users who consented to tracking. The models are currently separate and should not be summed directly.

### 4. Partner Name Standardization
Partner names come from multiple sources:
- Adjust raw data uses `NETWORK_NAME`
- Supermetrics uses `PARTNER_NAME`
- The `network_mapping` seed standardizes names

Some partners may not be mapped and will show their raw names.

### 5. Android COUNTRY field
The Android install table does not have a COUNTRY column. iOS has country data.

### 6. Incremental Processing Windows
- Device mapping: 7-day lookback
- User attribution: 7-day lookback
- User metrics: 35-day lookback (to capture D30 windows)
- Spend data: 3-day lookback

For historical rebuilds, use `--full-refresh`.

## Running the Models

### Full refresh (recommended for initial build)
```bash
dbt build --full-refresh
```

### Incremental run
```bash
dbt build
```

### Build specific models
```bash
# Just the mart
dbt build --select mart_campaign_performance_full

# Attribution models only
dbt build --select tag:attribution

# SKAN model
dbt build --select int_skan__aggregate_attribution
```

### Excluding slow models
The iOS impressions staging table takes ~30 minutes. To skip it:
```bash
dbt build --exclude stg_adjust__ios_activity_impression
```

## Data Sources

| Source | Database | Schema | Description |
|--------|----------|--------|-------------|
| Adjust | ADJUST_S3 | IOS_ACTIVITY, ANDROID_ACTIVITY | Raw install/click/impression data |
| Amplitude | AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE | SCHEMA_726530 | Events and merge_ids |
| Supermetrics | SUPERMETRICS | ADJ_CAMPAIGN | Campaign spend from Adjust Network API |

## Output Tables

All models write to `DBT_ANALYTICS.DBT_WGTDATA` (dev) or `DBT_ANALYTICS.PROD` (prod).

## Retention Benchmarks (Dec 2025+ cohorts)

| Partner | D1 Retention |
|---------|-------------|
| TikTok | 25% |
| wgtgolf (owned) | 25% |
| MOLOCO | 23% |
| Apple Search Ads | 23% |
| Facebook | 22% |
| Organic | 21% |
| Smadex | 20% |
| Applovin | 17% |
| Unity Ads | 15% |

## Revenue Metrics (Dec 2025+ cohorts)

| Partner | ARPI (Lifetime) | Payer Rate |
|---------|-----------------|------------|
| Apple | $2.87 | 1.45% |
| wgtgolf | $1.63 | 3.43% |
| Organic | $1.55 | 1.80% |
| MOLOCO | $1.07 | 2.29% |
| Facebook | $0.69 | 2.21% |
| Applovin | $0.68 | 1.63% |
| Smadex | $0.63 | 1.56% |
| TikTok | $0.40 | 0.96% |
| Unity Ads | $0.07 | 0.30% |

## Contact

For questions about this project, contact the data team.
