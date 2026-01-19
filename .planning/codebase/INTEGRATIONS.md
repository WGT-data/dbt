# External Integrations

**Analysis Date:** 2025-01-19

## APIs & External Services

**Mobile Attribution:**
- Adjust - Mobile attribution and install tracking
  - Database: `ADJUST_S3`
  - Schema: `PROD_DATA`
  - Tables: iOS/Android activity data (installs, clicks, impressions, sessions, events, reattributions, SKAdNetwork)
  - Source definition: `models/staging/adjust/_adjust__sources.yml`

**Product Analytics:**
- Amplitude - User behavior and product analytics
  - Database: `AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE` (Snowflake data share)
  - Schema: `SCHEMA_726530`
  - Tables: `EVENTS_726530`, `MERGE_IDS_726530`
  - Source definition: `models/staging/amplitude/_amplitude__sources.yml`

**Ad Spend Aggregation:**
- Supermetrics - Campaign spend data from Adjust
  - Database: `SUPERMETRICS`
  - Schema: `DATA_TRANSFERS`
  - Tables: `adj_campaign` (daily spend metrics by campaign/adgroup/creative)
  - Source definition: `models/staging/supermetrics/_supermetrics__sources.yml`

**Social Ads:**
- Facebook Ads via Fivetran
  - Database: `FIVETRAN_DATABASE`
  - Schema: `FACEBOOK_ADS`
  - Tables: `ADS_INSIGHTS`, `ACCOUNT_HISTORY`, `CAMPAIGN_HISTORY`, `AD_SET_HISTORY`, `AD_HISTORY`
  - Note: No YAML source definition - uses direct database references in SQL

**Revenue Events:**
- Internal Revenue System
  - Database: `WGT`
  - Schema: `PROD`
  - Tables: `DIRECT_REVENUE_EVENTS`
  - Source definition: `models/staging/revenue/_revenue__sources.yml`

## Data Storage

**Primary Data Warehouse:**
- Snowflake
  - Multiple databases: `ADJUST_S3`, `AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE`, `SUPERMETRICS`, `FIVETRAN_DATABASE`, `WGT`
  - Target database: Configured in dbt profile (external)

**Seed Data:**
- `seeds/network_mapping.csv` - Maps Adjust network names to Supermetrics partner IDs/names

**File Storage:**
- Local filesystem only (no cloud storage integration in dbt layer)

**Caching:**
- None at dbt layer - relies on Snowflake result caching

## Authentication & Identity

**Auth Provider:**
- Snowflake native authentication
  - Configured externally in `~/.dbt/profiles.yml`
  - Supports: username/password, SSO, key-pair auth (depends on profile config)

## Data Connectors Summary

| Source | Connector | Database | Update Frequency |
|--------|-----------|----------|------------------|
| Adjust | S3 → Snowflake | `ADJUST_S3` | Real-time (LOAD_TIMESTAMP) |
| Amplitude | Snowflake Share | `AMPLITUDEANALYTICS_*` | Near real-time (SERVER_UPLOAD_TIME) |
| Supermetrics | ETL | `SUPERMETRICS` | Daily |
| Facebook | Fivetran | `FIVETRAN_DATABASE` | Daily (_FIVETRAN_SYNCED) |
| Revenue | Internal ETL | `WGT` | Real-time |

## Ad Network Mapping

The `seeds/network_mapping.csv` maps network identifiers across systems:

| Adjust Network Name | Supermetrics Partner ID | Standardized Name |
|---------------------|------------------------|-------------------|
| Facebook Installs | 34 | Facebook |
| Google Ads ACE/ACI | 254 | Google Ads |
| Apple Search Ads | 257 | Apple |
| TikTok SAN | 2337 | TikTok for Business |
| AppLovin_iOS_2019 | 7 | Applovin |
| UnityAds_* | 42 | Unity Ads |
| Moloco_DSP_iOS | 56 | MOLOCO |
| Smadex DSP - iOS | 715 | Smadex |

## Monitoring & Observability

**Error Tracking:**
- None configured at dbt layer

**Logs:**
- dbt native logging to `logs/` directory (gitignored)

## CI/CD & Deployment

**Hosting:**
- Not defined in repository

**CI Pipeline:**
- None configured (no CI config files present)

## Environment Configuration

**Required Snowflake Access:**
- Read access to source databases:
  - `ADJUST_S3.PROD_DATA`
  - `AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530`
  - `SUPERMETRICS.DATA_TRANSFERS`
  - `FIVETRAN_DATABASE.FACEBOOK_ADS`
  - `WGT.PROD`
- Write access to target database/schema (configured in profile)

**dbt Profile Configuration:**
External file `~/.dbt/profiles.yml` must define `default` profile with:
- Snowflake account
- User credentials
- Warehouse
- Database
- Schema
- Role

## Webhooks & Callbacks

**Incoming:**
- None at dbt layer

**Outgoing:**
- None at dbt layer

## Data Flow Diagram

```
[Adjust S3]          →  ADJUST_S3.PROD_DATA
[Amplitude Share]    →  AMPLITUDEANALYTICS_*.SCHEMA_726530
[Supermetrics ETL]   →  SUPERMETRICS.DATA_TRANSFERS
[Fivetran Connector] →  FIVETRAN_DATABASE.FACEBOOK_ADS
[Internal ETL]       →  WGT.PROD
                            ↓
                     [dbt Transformations]
                            ↓
                     [Target Snowflake Schema]
                     (staging → intermediate → marts)
```

---

*Integration audit: 2025-01-19*
