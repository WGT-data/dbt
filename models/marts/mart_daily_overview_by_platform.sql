-- mart_daily_overview_by_platform.sql
-- Unattributed daily business overview by Date, Platform, Country
--
-- PURPOSE: Top-line daily metrics combining spend data with
-- WGT.EVENTS revenue data — NO attribution join required. Shows the
-- complete revenue picture across all users regardless of device mapping.
--
-- SPEND SOURCES:
--   Mobile (iOS/Android): stg_adjust__report_daily (Adjust API)
--   Desktop: Fivetran Facebook + Google Ads (country-level)
-- REVENUE SOURCE: WGT.EVENTS.REVENUE (Amplitude/game events)
--
-- Grain: One row per DATE / PLATFORM / COUNTRY

{{ config(
    materialized='incremental',
    unique_key=['DATE', 'PLATFORM', 'COUNTRY'],
    incremental_strategy='merge',
    on_schema_change='append_new_columns',
    tags=['mart', 'business', 'overview']
) }}

-- =============================================
-- SPEND METRICS (from Adjust API)
-- =============================================
WITH spend_daily AS (
    SELECT
        DATE
        , PLATFORM
        , COALESCE(COUNTRY, '__none__') AS COUNTRY
        , SUM(NETWORK_COST) AS COST
        , SUM(IMPRESSIONS) AS IMPRESSIONS
        , SUM(CLICKS) AS CLICKS
        , SUM(INSTALLS) AS ADJUST_INSTALLS
        , SUM(PAID_INSTALLS) AS PAID_INSTALLS
        , SUM(SESSIONS) AS SESSIONS
    FROM {{ ref('stg_adjust__report_daily') }}
    WHERE DATE IS NOT NULL
    {% if is_incremental() %}
        AND DATE >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3
)

-- =============================================
-- WEB/DESKTOP SPEND (from Fivetran Facebook + Google Ads)
-- =============================================
, web_spend_daily AS (
    SELECT
        DATE
        , 'Desktop' AS PLATFORM
        , COALESCE(COUNTRY, '__none__') AS COUNTRY
        , SUM(SPEND) AS COST
        , SUM(IMPRESSIONS) AS IMPRESSIONS
        , SUM(CLICKS) AS CLICKS
        , 0 AS ADJUST_INSTALLS
        , 0 AS PAID_INSTALLS
        , 0 AS SESSIONS
    FROM (
        SELECT DATE, COUNTRY, SPEND, IMPRESSIONS, CLICKS
        FROM {{ ref('v_stg_facebook_spend') }}

        UNION ALL

        SELECT DATE, COUNTRY, SPEND, IMPRESSIONS, CLICKS
        FROM {{ ref('v_stg_google_ads__country_spend') }}
        WHERE PLATFORM = 'Desktop'
    ) web
    WHERE DATE IS NOT NULL
    {% if is_incremental() %}
        AND DATE >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3
)

-- Combine mobile + desktop spend
, all_spend_daily AS (
    SELECT * FROM spend_daily
    UNION ALL
    SELECT * FROM web_spend_daily
)

-- =============================================
-- REVENUE METRICS (from WGT.EVENTS — all users, no attribution)
-- =============================================
, revenue_daily AS (
    SELECT
        DATE(EVENTTIME) AS DATE
        , PLATFORM
        , COALESCE(COUNTRY, '__none__') AS COUNTRY
        , COUNT(*) AS REVENUE_EVENTS
        , COUNT(DISTINCT USERID) AS REVENUE_USERS
        , SUM(COALESCE(REVENUE, 0)) AS ALL_PLATFORM_REVENUE
        , SUM(CASE WHEN REVENUETYPE = 'direct' THEN COALESCE(REVENUE, 0) ELSE 0 END) AS PURCHASE_REVENUE
        , SUM(CASE WHEN REVENUETYPE = 'indirect' THEN COALESCE(REVENUE, 0) ELSE 0 END) AS AD_REVENUE
        , COUNT(DISTINCT CASE WHEN REVENUETYPE = 'direct' THEN USERID END) AS PURCHASERS
        , COUNT(DISTINCT CASE WHEN REVENUETYPE = 'indirect' THEN USERID END) AS AD_REVENUE_USERS
    FROM {{ source('events', 'REVENUE') }}
    WHERE REVENUE IS NOT NULL
    {% if is_incremental() %}
        AND EVENTTIME >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3
)

-- =============================================
-- COMBINE
-- =============================================
, combined AS (
    SELECT
        COALESCE(s.DATE, r.DATE) AS DATE
        , COALESCE(s.PLATFORM, r.PLATFORM) AS PLATFORM
        , COALESCE(s.COUNTRY, r.COUNTRY) AS COUNTRY

        -- Spend metrics
        , COALESCE(s.COST, 0) AS COST
        , COALESCE(s.IMPRESSIONS, 0) AS IMPRESSIONS
        , COALESCE(s.CLICKS, 0) AS CLICKS
        , COALESCE(s.ADJUST_INSTALLS, 0) AS ADJUST_INSTALLS
        , COALESCE(s.PAID_INSTALLS, 0) AS PAID_INSTALLS
        , COALESCE(s.SESSIONS, 0) AS SESSIONS

        -- Revenue metrics
        , COALESCE(r.ALL_PLATFORM_REVENUE, 0) AS ALL_PLATFORM_REVENUE
        , COALESCE(r.PURCHASE_REVENUE, 0) AS PURCHASE_REVENUE
        , COALESCE(r.AD_REVENUE, 0) AS AD_REVENUE
        , COALESCE(r.REVENUE_EVENTS, 0) AS REVENUE_EVENTS
        , COALESCE(r.REVENUE_USERS, 0) AS REVENUE_USERS
        , COALESCE(r.PURCHASERS, 0) AS PURCHASERS
        , COALESCE(r.AD_REVENUE_USERS, 0) AS AD_REVENUE_USERS

    FROM all_spend_daily s
    FULL OUTER JOIN revenue_daily r
        ON s.DATE = r.DATE
        AND LOWER(s.PLATFORM) = LOWER(r.PLATFORM)
        AND LOWER(s.COUNTRY) = LOWER(r.COUNTRY)
)

SELECT
    DATE
    , PLATFORM
    , COUNTRY

    -- Spend
    , COST
    , IMPRESSIONS
    , CLICKS
    , ADJUST_INSTALLS
    , PAID_INSTALLS
    , SESSIONS

    -- Revenue
    , ALL_PLATFORM_REVENUE
    , PURCHASE_REVENUE
    , AD_REVENUE
    , REVENUE_EVENTS
    , REVENUE_USERS
    , PURCHASERS
    , AD_REVENUE_USERS

FROM combined
WHERE DATE IS NOT NULL
