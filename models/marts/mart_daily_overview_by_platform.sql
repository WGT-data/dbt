-- mart_daily_overview_by_platform.sql
-- Unattributed daily business overview by Date + Platform
--
-- PURPOSE: Top-line daily metrics combining spend data with
-- WGT.EVENTS revenue data — NO attribution join required. Shows the
-- complete revenue picture across all users regardless of device mapping.
--
-- SPEND SOURCE: int_spend__unified (deduped across Fivetran + Adjust API)
-- INSTALLS SOURCE: stg_adjust__report_daily_network (accurate network-level counts)
-- REVENUE SOURCE: WGT.EVENTS.REVENUE (Amplitude/game events)
--
-- Grain: One row per DATE / PLATFORM

{{ config(
    materialized='incremental',
    unique_key=['DATE', 'PLATFORM'],
    incremental_strategy='merge',
    on_schema_change='append_new_columns',
    tags=['mart', 'business', 'overview']
) }}

-- =============================================
-- SPEND METRICS (from int_spend__unified)
-- =============================================
WITH spend_daily AS (
    SELECT
        DATE
        , PLATFORM
        , SUM(SPEND) AS SPEND
        , SUM(IMPRESSIONS) AS IMPRESSIONS
        , SUM(CLICKS) AS CLICKS
    FROM {{ ref('int_spend__unified') }}
    WHERE DATE IS NOT NULL
      AND PLATFORM IS NOT NULL
    {% if is_incremental() %}
        AND DATE >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2
)

-- =============================================
-- INSTALL METRICS (from network-level Adjust API)
-- =============================================
, installs_daily AS (
    SELECT
        DATE
        , PLATFORM
        , SUM(INSTALLS) AS INSTALLS
        , SUM(PAID_INSTALLS) AS PAID_INSTALLS
        , SUM(SESSIONS) AS SESSIONS
        , SUM(REATTRIBUTIONS) AS REATTRIBUTIONS
    FROM {{ ref('stg_adjust__report_daily_network') }}
    WHERE DATE IS NOT NULL
    {% if is_incremental() %}
        AND DATE >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2
)

-- =============================================
-- REVENUE METRICS (from WGT.EVENTS — all users, no attribution)
-- =============================================
, revenue_daily AS (
    SELECT
        DATE(EVENTTIME) AS DATE
        , PLATFORM
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
    GROUP BY 1, 2
)

-- =============================================
-- COMBINE
-- =============================================
, combined AS (
    SELECT
        COALESCE(s.DATE, i.DATE, r.DATE) AS DATE
        , COALESCE(s.PLATFORM, i.PLATFORM, r.PLATFORM) AS PLATFORM

        -- Spend metrics
        , COALESCE(s.SPEND, 0) AS SPEND
        , COALESCE(s.IMPRESSIONS, 0) AS IMPRESSIONS
        , COALESCE(s.CLICKS, 0) AS CLICKS

        -- Install metrics (network-level, accurate)
        , COALESCE(i.INSTALLS, 0) AS INSTALLS
        , COALESCE(i.PAID_INSTALLS, 0) AS PAID_INSTALLS
        , COALESCE(i.SESSIONS, 0) AS SESSIONS
        , COALESCE(i.REATTRIBUTIONS, 0) AS REATTRIBUTIONS

        -- Revenue metrics
        , COALESCE(r.ALL_PLATFORM_REVENUE, 0) AS ALL_PLATFORM_REVENUE
        , COALESCE(r.PURCHASE_REVENUE, 0) AS PURCHASE_REVENUE
        , COALESCE(r.AD_REVENUE, 0) AS AD_REVENUE
        , COALESCE(r.REVENUE_EVENTS, 0) AS REVENUE_EVENTS
        , COALESCE(r.REVENUE_USERS, 0) AS REVENUE_USERS
        , COALESCE(r.PURCHASERS, 0) AS PURCHASERS
        , COALESCE(r.AD_REVENUE_USERS, 0) AS AD_REVENUE_USERS

    FROM spend_daily s
    FULL OUTER JOIN installs_daily i
        ON s.DATE = i.DATE
        AND s.PLATFORM = i.PLATFORM
    FULL OUTER JOIN revenue_daily r
        ON COALESCE(s.DATE, i.DATE) = r.DATE
        AND COALESCE(s.PLATFORM, i.PLATFORM) = r.PLATFORM
)

SELECT
    DATE
    , PLATFORM

    -- Spend
    , SPEND
    , IMPRESSIONS
    , CLICKS
    , PAID_INSTALLS
    , SESSIONS
    , REATTRIBUTIONS

    -- Installs
    , INSTALLS

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
