{{ config(
    materialized='table',
    tags=['mmm', 'mart', 'summary']
) }}

-- mmm__daily_channel_summary.sql
-- Primary MMM input table: spend + installs + revenue + SKAN at daily+channel+platform grain
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
    UNION
    SELECT DISTINCT PLATFORM, CHANNEL FROM {{ ref('int_mmm__daily_channel_skan') }}
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
    SELECT DATE, PLATFORM, CHANNEL, SPEND, IMPRESSIONS, CLICKS,
           PAID_INSTALLS, PAID_CLICKS, PAID_IMPRESSIONS, SESSIONS, REATTRIBUTIONS
    FROM {{ ref('int_mmm__daily_channel_spend') }}
),

installs AS (
    SELECT DATE, PLATFORM, CHANNEL, INSTALLS
    FROM {{ ref('int_mmm__daily_channel_installs') }}
),

revenue AS (
    SELECT DATE, PLATFORM, CHANNEL, REVENUE, ALL_REVENUE, AD_REVENUE, API_INSTALLS
    FROM {{ ref('int_mmm__daily_channel_revenue') }}
),

skan AS (
    SELECT DATE, PLATFORM, CHANNEL,
           SKAN_INSTALLS, SKAN_NEW_INSTALLS, SKAN_REDOWNLOADS,
           SKAN_AVG_CV, SKAN_INSTALLS_WITH_CV,
           SKAN_CV_BUCKET_0, SKAN_CV_BUCKET_1_10, SKAN_CV_BUCKET_11_20,
           SKAN_CV_BUCKET_21_40, SKAN_CV_BUCKET_41_63,
           SKAN_STOREKIT_RENDERED, SKAN_VIEW_THROUGH, SKAN_WINNING_POSTBACKS,
           SKAN_V3_COUNT, SKAN_V4_COUNT
    FROM {{ ref('int_mmm__daily_channel_skan') }}
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
    COALESCE(s.PAID_INSTALLS, 0) AS PAID_INSTALLS,
    COALESCE(s.PAID_CLICKS, 0) AS PAID_CLICKS,
    COALESCE(s.PAID_IMPRESSIONS, 0) AS PAID_IMPRESSIONS,
    COALESCE(s.SESSIONS, 0) AS SESSIONS,
    COALESCE(s.REATTRIBUTIONS, 0) AS REATTRIBUTIONS,

    -- Install metrics (from Adjust S3 device-level / network-level API)
    COALESCE(i.INSTALLS, 0) AS INSTALLS,

    -- Revenue metrics (from Adjust API)
    COALESCE(r.REVENUE, 0) AS REVENUE,
    COALESCE(r.ALL_REVENUE, 0) AS ALL_REVENUE,
    COALESCE(r.AD_REVENUE, 0) AS AD_REVENUE,
    COALESCE(r.API_INSTALLS, 0) AS INSTALLS_API,

    -- SKAN metrics (iOS only — NULL/0 for Android and Desktop rows)
    COALESCE(sk.SKAN_INSTALLS, 0) AS SKAN_INSTALLS,
    COALESCE(sk.SKAN_NEW_INSTALLS, 0) AS SKAN_NEW_INSTALLS,
    COALESCE(sk.SKAN_REDOWNLOADS, 0) AS SKAN_REDOWNLOADS,
    sk.SKAN_AVG_CV,
    COALESCE(sk.SKAN_INSTALLS_WITH_CV, 0) AS SKAN_INSTALLS_WITH_CV,
    COALESCE(sk.SKAN_CV_BUCKET_0, 0) AS SKAN_CV_BUCKET_0,
    COALESCE(sk.SKAN_CV_BUCKET_1_10, 0) AS SKAN_CV_BUCKET_1_10,
    COALESCE(sk.SKAN_CV_BUCKET_11_20, 0) AS SKAN_CV_BUCKET_11_20,
    COALESCE(sk.SKAN_CV_BUCKET_21_40, 0) AS SKAN_CV_BUCKET_21_40,
    COALESCE(sk.SKAN_CV_BUCKET_41_63, 0) AS SKAN_CV_BUCKET_41_63,
    COALESCE(sk.SKAN_STOREKIT_RENDERED, 0) AS SKAN_STOREKIT_RENDERED,
    COALESCE(sk.SKAN_VIEW_THROUGH, 0) AS SKAN_VIEW_THROUGH,
    COALESCE(sk.SKAN_WINNING_POSTBACKS, 0) AS SKAN_WINNING_POSTBACKS,
    COALESCE(sk.SKAN_V3_COUNT, 0) AS SKAN_V3_COUNT,
    COALESCE(sk.SKAN_V4_COUNT, 0) AS SKAN_V4_COUNT,

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
    CASE WHEN r.REVENUE IS NOT NULL THEN 1 ELSE 0 END AS HAS_REVENUE_DATA,
    CASE WHEN sk.SKAN_INSTALLS IS NOT NULL THEN 1 ELSE 0 END AS HAS_SKAN_DATA

FROM date_channel_grid g
LEFT JOIN spend s
    ON g.DATE = s.DATE AND g.PLATFORM = s.PLATFORM AND g.CHANNEL = s.CHANNEL
LEFT JOIN installs i
    ON g.DATE = i.DATE AND g.PLATFORM = i.PLATFORM AND g.CHANNEL = i.CHANNEL
LEFT JOIN revenue r
    ON g.DATE = r.DATE AND g.PLATFORM = r.PLATFORM AND g.CHANNEL = r.CHANNEL
LEFT JOIN skan sk
    ON g.DATE = sk.DATE AND g.PLATFORM = sk.PLATFORM AND g.CHANNEL = sk.CHANNEL

ORDER BY g.DATE DESC, g.PLATFORM, g.CHANNEL
