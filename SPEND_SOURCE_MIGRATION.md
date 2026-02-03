# Spend Data Source Migration: Supermetrics → Adjust API

This document outlines changes to migrate spend data from Supermetrics to `ADJUST_S3.API_DATA.REPORT_DAILY_RAW`.

## New Staging Model Created

**File:** `models/staging/adjust/stg_adjust__report_daily.sql`

Source: `{{ source('adjust_api_data', 'REPORT_DAILY_RAW') }}`

## Column Mapping

| Supermetrics Column | Report Daily Raw Column | Output Column |
|---------------------|-------------------------|---------------|
| DATE | DAY | DATE |
| PARTNER_NAME | NETWORK | PARTNER_NAME |
| PARTNER_ID | (not available) | - |
| CAMPAIGN_NETWORK | CAMPAIGN_NETWORK | CAMPAIGN_NAME |
| CAMPAIGN_ID_NETWORK | CAMPAIGN_ID_NETWORK | CAMPAIGN_ID |
| ADGROUP_NETWORK | ADGROUP_NETWORK | ADGROUP_NAME |
| ADGROUP_ID_NETWORK | ADGROUP_ID_NETWORK | ADGROUP_ID |
| PLATFORM | OS_NAME (derived) | PLATFORM |
| NETWORK_COST | NETWORK_COST | COST |
| CLICKS | CLICKS | CLICKS |
| IMPRESSIONS | IMPRESSIONS | IMPRESSIONS |
| INSTALLS | INSTALLS | INSTALLS |

---

## Changes Required

### 1. mta__campaign_performance.sql

**Current spend CTE (lines 155-171):**
```sql
, spend AS (
    SELECT COALESCE(nm.SUPERMETRICS_PARTNER_NAME, s.PARTNER_NAME) AS AD_PARTNER
         , s.CAMPAIGN_ID_NETWORK AS CAMPAIGN_ID
         , s.PLATFORM
         , s.DATE
         , SUM(s.COST) AS COST
         , SUM(s.CLICKS) AS CLICKS
         , SUM(s.IMPRESSIONS) AS IMPRESSIONS
    FROM {{ ref('stg_supermetrics__adj_campaign') }} s
    LEFT JOIN network_mapping_deduped nm
        ON s.PARTNER_ID = CAST(nm.SUPERMETRICS_PARTNER_ID AS VARCHAR)
    WHERE TRY_TO_NUMBER(s.CAMPAIGN_ID_NETWORK) IS NOT NULL
    {% if is_incremental() %}
        AND s.DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3, 4
)
```

**Replace with:**
```sql
, spend AS (
    SELECT PARTNER_NAME AS AD_PARTNER
         , CAMPAIGN_ID_NETWORK AS CAMPAIGN_ID
         , PLATFORM
         , DATE
         , SUM(NETWORK_COST) AS COST
         , SUM(CLICKS) AS CLICKS
         , SUM(IMPRESSIONS) AS IMPRESSIONS
    FROM {{ ref('stg_adjust__report_daily') }}
    WHERE TRY_TO_NUMBER(CAMPAIGN_ID_NETWORK) IS NOT NULL
    {% if is_incremental() %}
        AND DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3, 4
)
```

**Also remove the `network_mapping_deduped` CTE (lines 143-149)** since it's no longer needed for the Supermetrics PARTNER_ID join.

---

### 2. mart_campaign_performance_full.sql

**Current spend_data CTE (lines 17-38):**
```sql
WITH spend_data AS (
    SELECT
        DATE
        , PARTNER_NAME AS AD_PARTNER
        , PARTNER_ID
        , CAMPAIGN_NETWORK AS CAMPAIGN_NAME
        , CAMPAIGN_ID_NETWORK AS CAMPAIGN_ID
        , ADGROUP_NETWORK AS ADGROUP_NAME
        , ADGROUP_ID_NETWORK AS ADGROUP_ID
        , PLATFORM
        , SUM(NETWORK_COST) AS COST
        , SUM(CLICKS) AS CLICKS
        , SUM(IMPRESSIONS) AS IMPRESSIONS
        , SUM(INSTALLS) AS ADJUST_INSTALLS
    FROM {{ source('supermetrics', 'adj_campaign') }}
    WHERE DATE IS NOT NULL
    {% if is_incremental() %}
        AND DATE >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
)
```

**Replace with:**
```sql
WITH spend_data AS (
    SELECT DATE
         , PARTNER_NAME AS AD_PARTNER
         , CAMPAIGN_NETWORK AS CAMPAIGN_NAME
         , CAMPAIGN_ID_NETWORK AS CAMPAIGN_ID
         , ADGROUP_NETWORK AS ADGROUP_NAME
         , ADGROUP_ID_NETWORK AS ADGROUP_ID
         , PLATFORM
         , SUM(NETWORK_COST) AS COST
         , SUM(CLICKS) AS CLICKS
         , SUM(IMPRESSIONS) AS IMPRESSIONS
         , SUM(INSTALLS) AS ADJUST_INSTALLS
    FROM {{ ref('stg_adjust__report_daily') }}
    WHERE DATE IS NOT NULL
    {% if is_incremental() %}
        AND DATE >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3, 4, 5, 6, 7
)
```

**Note:** PARTNER_ID column is removed since it's not in the new source and isn't used downstream in this model.

---

### 3. network_mapping CTE Cleanup

In `mta__campaign_performance.sql`, the `network_mapping_deduped` CTE can be removed since we no longer need to map PARTNER_ID to partner names. The new source already has clean PARTNER_NAME values from Adjust.

---

## Validation Queries

After migration, run these to compare old vs new:

```sql
-- Compare total spend by date
SELECT 'supermetrics' AS source
     , DATE
     , SUM(NETWORK_COST) AS total_cost
FROM {{ source('supermetrics', 'adj_campaign') }}
WHERE DATE >= '2021-04-07'
GROUP BY 1, 2

UNION ALL

SELECT 'adjust_api' AS source
     , DATE
     , SUM(NETWORK_COST) AS total_cost
FROM {{ ref('stg_adjust__report_daily') }}
GROUP BY 1, 2
ORDER BY DATE, source;
```

```sql
-- Compare by partner
SELECT 'supermetrics' AS source
     , PARTNER_NAME
     , SUM(NETWORK_COST) AS total_cost
FROM {{ source('supermetrics', 'adj_campaign') }}
WHERE DATE >= '2024-01-01'
GROUP BY 1, 2

UNION ALL

SELECT 'adjust_api' AS source
     , PARTNER_NAME
     , SUM(NETWORK_COST) AS total_cost
FROM {{ ref('stg_adjust__report_daily') }}
WHERE DATE >= '2024-01-01'
GROUP BY 1, 2
ORDER BY PARTNER_NAME, source;
```

---

## Files Modified

1. `models/staging/adjust/_adjust__sources.yml` - Added adjust_api_data source
2. `models/staging/adjust/stg_adjust__report_daily.sql` - NEW staging model
3. `models/marts/attribution/mta__campaign_performance.sql` - Update spend CTE
4. `models/marts/attribution/mart_campaign_performance_full.sql` - Update spend_data CTE
