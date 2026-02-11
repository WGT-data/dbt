{{ config(
    materialized='table',
    tags=['mmm', 'mart', 'summary']
) }}

-- mmm__daily_channel_summary.sql
-- Primary MMM input table: spend + installs + revenue at daily+channel+platform grain
-- Date spine ensures complete time series with no gaps (critical for MMM regression)
-- Grain: one row per DATE + PLATFORM + CHANNEL

-- Step 1: Generate date spine using hardcoded start date
-- Uses 2024-01-01 as start boundary (known data start from staging model filters)
-- Avoids CROSS JOIN of three intermediate models which creates a Cartesian product
WITH date_spine AS (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="'2024-01-01'",
        end_date="current_date()"
    ) }}
),

dates AS (
    SELECT CAST(date_day AS DATE) AS DATE
    FROM date_spine
),

-- Step 2: Get distinct channel+platform combinations from all sources
channels AS (
    SELECT DISTINCT PLATFORM, CHANNEL FROM {{ ref('int_mmm__daily_channel_spend') }}
    UNION
    SELECT DISTINCT PLATFORM, CHANNEL FROM {{ ref('int_mmm__daily_channel_installs') }}
    UNION
    SELECT DISTINCT PLATFORM, CHANNEL FROM {{ ref('int_mmm__daily_channel_revenue') }}
),

-- Step 3: Create complete grid (every date x every channel+platform)
date_channel_grid AS (
    SELECT
        d.DATE,
        c.PLATFORM,
        c.CHANNEL
    FROM dates d
    CROSS JOIN channels c
),

-- Step 4: Join actual data
spend AS (
    SELECT DATE, PLATFORM, CHANNEL, SPEND, IMPRESSIONS, CLICKS, PAID_INSTALLS
    FROM {{ ref('int_mmm__daily_channel_spend') }}
),

installs AS (
    SELECT DATE, PLATFORM, CHANNEL, INSTALLS
    FROM {{ ref('int_mmm__daily_channel_installs') }}
),

revenue AS (
    SELECT DATE, PLATFORM, CHANNEL, REVENUE, ALL_REVENUE, AD_REVENUE, API_INSTALLS
    FROM {{ ref('int_mmm__daily_channel_revenue') }}
)

-- Step 5: Final output with all metrics
SELECT
    g.DATE,
    g.PLATFORM,
    g.CHANNEL,

    -- Spend metrics
    COALESCE(s.SPEND, 0) AS SPEND,
    COALESCE(s.IMPRESSIONS, 0) AS IMPRESSIONS,
    COALESCE(s.CLICKS, 0) AS CLICKS,
    COALESCE(s.PAID_INSTALLS, 0) AS PAID_INSTALLS_SUPERMETRICS,

    -- Install metrics (from device-level S3 data)
    COALESCE(i.INSTALLS, 0) AS INSTALLS,

    -- Revenue metrics (from Adjust API)
    COALESCE(r.REVENUE, 0) AS REVENUE,
    COALESCE(r.ALL_REVENUE, 0) AS ALL_REVENUE,
    COALESCE(r.AD_REVENUE, 0) AS AD_REVENUE,
    COALESCE(r.API_INSTALLS, 0) AS INSTALLS_API,

    -- Derived KPIs
    CASE WHEN COALESCE(i.INSTALLS, 0) > 0
         THEN COALESCE(s.SPEND, 0) / i.INSTALLS
         ELSE NULL
    END AS CPI,

    CASE WHEN COALESCE(s.SPEND, 0) > 0
         THEN COALESCE(r.REVENUE, 0) / s.SPEND
         ELSE NULL
    END AS ROAS,

    CASE WHEN COALESCE(s.SPEND, 0) > 0
         THEN COALESCE(r.ALL_REVENUE, 0) / s.SPEND
         ELSE NULL
    END AS ALL_ROAS,

    -- Data quality flags
    CASE WHEN s.SPEND IS NOT NULL THEN 1 ELSE 0 END AS HAS_SPEND_DATA,
    CASE WHEN i.INSTALLS IS NOT NULL THEN 1 ELSE 0 END AS HAS_INSTALL_DATA,
    CASE WHEN r.REVENUE IS NOT NULL THEN 1 ELSE 0 END AS HAS_REVENUE_DATA

FROM date_channel_grid g
LEFT JOIN spend s
    ON g.DATE = s.DATE AND g.PLATFORM = s.PLATFORM AND g.CHANNEL = s.CHANNEL
LEFT JOIN installs i
    ON g.DATE = i.DATE AND g.PLATFORM = i.PLATFORM AND g.CHANNEL = i.CHANNEL
LEFT JOIN revenue r
    ON g.DATE = r.DATE AND g.PLATFORM = r.PLATFORM AND g.CHANNEL = r.CHANNEL

ORDER BY g.DATE DESC, g.PLATFORM, g.CHANNEL
