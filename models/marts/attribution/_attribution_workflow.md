# Attribution Data Workflow

## Overview

This document explains how the Multi-Touch Attribution (MTA) models integrate with the existing Adjust-Amplitude device mapping workflow.

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              SOURCE DATA                                         │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ADJUST (Snowflake)                          AMPLITUDE (Snowflake Share)        │
│  ├── IOS_ACTIVITY_IMPRESSION                 └── EVENTS_726530                  │
│  ├── IOS_ACTIVITY_CLICK                          ├── User events                │
│  ├── IOS_ACTIVITY_INSTALL                        ├── Revenue events             │
│  ├── ANDROID_ACTIVITY_IMPRESSION                 └── Session events             │
│  ├── ANDROID_ACTIVITY_CLICK                                                     │
│  └── ANDROID_ACTIVITY_INSTALL                                                   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              STAGING LAYER                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────┐    ┌─────────────────────────┐                     │
│  │ v_stg_adjust__installs  │    │ v_stg_adjust__touchpoints│  ◄── NEW (MTA)     │
│  │ (Device + Install data) │    │ (Impressions + Clicks)   │                     │
│  └───────────┬─────────────┘    └───────────┬─────────────┘                     │
│              │                              │                                    │
│  ┌───────────┴─────────────┐    ┌───────────┴─────────────┐                     │
│  │ v_stg_amplitude__events │    │v_stg_amplitude__merge_ids│                     │
│  │ (User behavior)         │    │ (Device → User mapping)  │                     │
│  └───────────┬─────────────┘    └───────────┬─────────────┘                     │
│              │                              │                                    │
└──────────────┼──────────────────────────────┼────────────────────────────────────┘
               │                              │
               ▼                              ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           INTERMEDIATE LAYER                                     │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │              int_adjust_amplitude__device_mapping                         │   │
│  │              ════════════════════════════════════                         │   │
│  │              Links Adjust Device IDs to Amplitude User IDs               │   │
│  │              KEY JOIN TABLE FOR ALL ATTRIBUTION                          │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                    │                                │                            │
│                    │                                │                            │
│     ┌──────────────┴───────────┐      ┌────────────┴────────────┐              │
│     │                          │      │                          │              │
│     ▼                          ▼      ▼                          ▼              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌────────────┐ │
│  │int_user_cohort  │  │int_user_cohort  │  │int_mta__user    │  │int_mta__   │ │
│  │__attribution    │  │__metrics        │  │_journey         │  │touchpoint  │ │
│  │                 │  │                 │  │                 │  │_credit     │ │
│  │(User→Campaign)  │  │(D7/D30 Revenue) │  │(All touchpoints │  │(5 attrib   │ │
│  │                 │  │                 │  │ per install)    │  │ models)    │ │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  └─────┬──────┘ │
│           │                    │                    │                  │        │
│           │    EXISTING FLOW   │                    │    NEW MTA FLOW  │        │
│           └──────────┬─────────┘                    └────────┬─────────┘        │
│                      │                                       │                  │
└──────────────────────┼───────────────────────────────────────┼──────────────────┘
                       │                                       │
                       ▼                                       ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              MART LAYER                                          │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  EXISTING MODELS                           NEW MTA MODELS                       │
│  ────────────────                          ───────────────                       │
│  ┌─────────────────────────┐               ┌─────────────────────────┐          │
│  │attribution__installs    │               │mta__campaign_performance│          │
│  │attribution__campaign_   │               │mta__network_comparison  │          │
│  │  performance            │               └─────────────────────────┘          │
│  │attribution__network_    │                                                    │
│  │  performance            │               DASHBOARD VIEWS                      │
│  └─────────────────────────┘               ────────────────                      │
│                                            ┌─────────────────────────┐          │
│                                            │rpt__attribution_model_  │          │
│                                            │  comparison             │          │
│                                            │rpt__attribution_weekly_ │          │
│                                            │  summary                │          │
│                                            │rpt__user_journey_       │          │
│                                            │  insights               │          │
│                                            └─────────────────────────┘          │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Key Integration Point: Device Mapping

The `int_adjust_amplitude__device_mapping` table is the **critical link** between:
- **Adjust data** (device-level: impressions, clicks, installs)
- **Amplitude data** (user-level: revenue, retention, engagement)

### How It Works

```sql
-- Device mapping links Adjust devices to Amplitude users
int_adjust_amplitude__device_mapping
├── ADJUST_DEVICE_ID   -- From Adjust (IDFV for iOS, GPS_ADID for Android)
├── AMPLITUDE_USER_ID  -- From Amplitude events
├── PLATFORM           -- iOS or Android
└── FIRST_SEEN_AT      -- When user first appeared
```

### Current Flow (Last-Touch Attribution)

1. **Install captured in Adjust** → Device ID + Network/Campaign attribution
2. **Device mapped to Amplitude User** → via `int_adjust_amplitude__device_mapping`
3. **User metrics calculated** → D7/D30 revenue, retention from Amplitude
4. **Attribution aggregated** → By campaign, credited to last-touch network

### New MTA Flow

1. **All touchpoints captured** → Impressions + Clicks from Adjust (NEW)
2. **Touchpoints joined to installs** → Within 7-day lookback window (NEW)
3. **Credit calculated per touchpoint** → 5 attribution models (NEW)
4. **Device mapped to Amplitude User** → Same `int_adjust_amplitude__device_mapping`
5. **User metrics distributed** → Revenue split by fractional credit (NEW)

## Model Dependencies

```
v_stg_adjust__touchpoints (NEW)
         │
         ▼
int_mta__user_journey (NEW)
         │
         ├──► Uses v_stg_adjust__installs (EXISTING)
         │
         ▼
int_mta__touchpoint_credit (NEW)
         │
         ├──► Uses int_adjust_amplitude__device_mapping (EXISTING) ◄── KEY LINK
         │
         ▼
mta__campaign_performance (NEW)
         │
         ├──► Uses int_user_cohort__metrics (EXISTING)
         │
         ▼
rpt__attribution_model_comparison (NEW)
         │
         └──► Uses attribution__campaign_performance (EXISTING)
```

## Running the Models

### Full Refresh (First Run)
```bash
# Run MTA models with all dependencies
dbt run --select +mta__campaign_performance +mta__network_comparison +rpt__attribution_model_comparison +rpt__attribution_weekly_summary +rpt__user_journey_insights
```

### Incremental (Daily)
```bash
# Same command - models are incremental and will only process new data
dbt run --select +mta__campaign_performance +mta__network_comparison +rpt__attribution_model_comparison +rpt__attribution_weekly_summary +rpt__user_journey_insights
```

### Test New Models
```bash
dbt test --select tag:mta
```

## Dashboard Queries

### Compare Current vs MTA (Quick Overview)
```sql
SELECT AD_PARTNER
     , SUM(COST) AS SPEND
     , SUM(INSTALLS_CURRENT) AS INSTALLS_LAST_TOUCH
     , SUM(MTA_INSTALLS_TIME_DECAY) AS INSTALLS_TIME_DECAY
     , ROUND(AVG(INSTALL_DIFF_PCT), 1) AS AVG_DIFF_PCT
FROM rpt__attribution_model_comparison
WHERE DATE >= CURRENT_DATE - 30
GROUP BY 1
ORDER BY SPEND DESC;
```

### Find Networks That Benefit from MTA
```sql
-- Networks where MTA gives MORE credit than last-touch
SELECT AD_PARTNER
     , SUM(COST) AS SPEND
     , SUM(MTA_INSTALLS_TIME_DECAY - INSTALLS_CURRENT) AS ADDITIONAL_INSTALLS
     , ROUND(AVG(INSTALL_DIFF_PCT), 1) AS AVG_LIFT_PCT
FROM rpt__attribution_model_comparison
WHERE DATE >= CURRENT_DATE - 30
GROUP BY 1
HAVING SUM(MTA_INSTALLS_TIME_DECAY - INSTALLS_CURRENT) > 0
ORDER BY ADDITIONAL_INSTALLS DESC;
```

### Journey Complexity by Network
```sql
SELECT AD_PARTNER
     , ROUND(AVG(AVG_TOUCHPOINTS), 1) AS AVG_TOUCHPOINTS
     , ROUND(AVG(MULTI_TOUCH_PCT), 1) AS MULTI_TOUCH_PCT
     , ROUND(AVG(CROSS_NETWORK_PCT), 1) AS CROSS_NETWORK_PCT
FROM rpt__user_journey_insights
WHERE DATE >= CURRENT_DATE - 30
GROUP BY 1
ORDER BY AVG_TOUCHPOINTS DESC;
```
