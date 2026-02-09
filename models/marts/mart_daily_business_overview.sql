-- mart_daily_business_overview.sql
-- Top-line daily business trends combining Adjust spend/install data
-- with all-platform game event metrics from WGT.EVENTS
--
-- Adjust metrics: Spend, clicks, impressions, installs, sessions (iOS/Android only)
-- Event metrics: Revenue, DAU (round players), rounds played (ALL platforms)
--
-- Grain: One row per DATE

{{
    config(
        materialized='incremental',
        unique_key='DATE',
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        tags=['mart', 'business', 'overview']
    )
}}

-- =============================================
-- ADJUST DAILY METRICS (aggregated across all campaigns/platforms)
-- =============================================
WITH adjust_daily AS (
    SELECT
        DATE
        , SUM(NETWORK_COST) AS TOTAL_SPEND
        , SUM(IMPRESSIONS) AS TOTAL_IMPRESSIONS
        , SUM(CLICKS) AS TOTAL_CLICKS
        , SUM(INSTALLS) AS TOTAL_INSTALLS
        , SUM(PAID_INSTALLS) AS TOTAL_PAID_INSTALLS
        , SUM(SESSIONS) AS TOTAL_ADJUST_SESSIONS
        , SUM(UNINSTALLS) AS TOTAL_UNINSTALLS
        , SUM(REATTRIBUTIONS) AS TOTAL_REATTRIBUTIONS
        , SUM(AD_REVENUE) AS ADJUST_AD_REVENUE
    FROM {{ ref('stg_adjust__report_daily') }}
    {% if is_incremental() %}
        WHERE DATE >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY DATE
)

-- =============================================
-- REVENUE FROM WGT.EVENTS.REVENUE (ALL platforms)
-- =============================================
, daily_revenue AS (
    SELECT
        DATE(EVENTTIME) AS DATE
        , COUNT(*) AS REVENUE_EVENTS
        , COUNT(DISTINCT USERID) AS REVENUE_USERS
        , SUM(COALESCE(REVENUE, 0)) AS TOTAL_REVENUE
        , SUM(CASE WHEN REVENUETYPE = 'direct' THEN COALESCE(REVENUE, 0) ELSE 0 END) AS PURCHASE_REVENUE
        , SUM(CASE WHEN REVENUETYPE = 'indirect' THEN COALESCE(REVENUE, 0) ELSE 0 END) AS AD_REVENUE
        , COUNT(DISTINCT CASE WHEN REVENUETYPE = 'direct' THEN USERID END) AS PURCHASERS
        , COUNT(DISTINCT CASE WHEN REVENUETYPE = 'indirect' THEN USERID END) AS AD_REVENUE_USERS
    FROM {{ source('events', 'REVENUE') }}
    WHERE REVENUE IS NOT NULL
    {% if is_incremental() %}
        AND EVENTTIME >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY DATE(EVENTTIME)
)

-- =============================================
-- DAU & ROUNDS FROM WGT.EVENTS.ROUNDSTARTED (ALL platforms)
-- =============================================
, daily_rounds AS (
    SELECT
        DATE(EVENTTIME) AS DATE
        , COUNT(*) AS TOTAL_ROUNDS
        , COUNT(DISTINCT USERID) AS DAU
        , COUNT(DISTINCT GAMEID) AS UNIQUE_GAMES
    FROM {{ source('events', 'ROUNDSTARTED') }}
    WHERE USERID IS NOT NULL
    {% if is_incremental() %}
        AND EVENTTIME >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY DATE(EVENTTIME)
)

-- =============================================
-- COMBINE ALL SOURCES
-- =============================================
, combined AS (
    SELECT
        COALESCE(a.DATE, r.DATE, d.DATE) AS DATE

        -- Adjust spend & acquisition
        , COALESCE(a.TOTAL_SPEND, 0) AS TOTAL_SPEND
        , COALESCE(a.TOTAL_IMPRESSIONS, 0) AS TOTAL_IMPRESSIONS
        , COALESCE(a.TOTAL_CLICKS, 0) AS TOTAL_CLICKS
        , COALESCE(a.TOTAL_INSTALLS, 0) AS TOTAL_INSTALLS
        , COALESCE(a.TOTAL_PAID_INSTALLS, 0) AS TOTAL_PAID_INSTALLS
        , COALESCE(a.TOTAL_ADJUST_SESSIONS, 0) AS TOTAL_ADJUST_SESSIONS
        , COALESCE(a.TOTAL_UNINSTALLS, 0) AS TOTAL_UNINSTALLS
        , COALESCE(a.TOTAL_REATTRIBUTIONS, 0) AS TOTAL_REATTRIBUTIONS
        , COALESCE(a.ADJUST_AD_REVENUE, 0) AS ADJUST_AD_REVENUE

        -- Event-based revenue (all platforms)
        , COALESCE(r.TOTAL_REVENUE, 0) AS TOTAL_REVENUE
        , COALESCE(r.PURCHASE_REVENUE, 0) AS PURCHASE_REVENUE
        , COALESCE(r.AD_REVENUE, 0) AS AD_REVENUE
        , COALESCE(r.REVENUE_EVENTS, 0) AS REVENUE_EVENTS
        , COALESCE(r.REVENUE_USERS, 0) AS REVENUE_USERS
        , COALESCE(r.PURCHASERS, 0) AS PURCHASERS
        , COALESCE(r.AD_REVENUE_USERS, 0) AS AD_REVENUE_USERS

        -- Engagement (all platforms)
        , COALESCE(d.DAU, 0) AS DAU
        , COALESCE(d.TOTAL_ROUNDS, 0) AS TOTAL_ROUNDS
        , COALESCE(d.UNIQUE_GAMES, 0) AS UNIQUE_GAMES

    FROM adjust_daily a
    FULL OUTER JOIN daily_revenue r ON a.DATE = r.DATE
    FULL OUTER JOIN daily_rounds d ON COALESCE(a.DATE, r.DATE) = d.DATE
)

SELECT
    DATE

    -- Spend & Acquisition
    , TOTAL_SPEND
    , TOTAL_IMPRESSIONS
    , TOTAL_CLICKS
    , TOTAL_INSTALLS
    , TOTAL_PAID_INSTALLS
    , TOTAL_ADJUST_SESSIONS
    , TOTAL_UNINSTALLS
    , TOTAL_REATTRIBUTIONS

    -- Revenue (all platforms, from WGT.EVENTS)
    , TOTAL_REVENUE
    , PURCHASE_REVENUE
    , AD_REVENUE
    , REVENUE_EVENTS
    , REVENUE_USERS
    , PURCHASERS
    , AD_REVENUE_USERS
    , ADJUST_AD_REVENUE

    -- Engagement (all platforms, from WGT.EVENTS)
    , DAU
    , TOTAL_ROUNDS
    , UNIQUE_GAMES

    -- Derived KPIs
    , CASE WHEN TOTAL_INSTALLS > 0 THEN TOTAL_SPEND / TOTAL_INSTALLS ELSE NULL END AS BLENDED_CPI
    , CASE WHEN TOTAL_SPEND > 0 THEN TOTAL_REVENUE / TOTAL_SPEND ELSE NULL END AS ROAS
    , CASE WHEN TOTAL_SPEND > 0 THEN PURCHASE_REVENUE / TOTAL_SPEND ELSE NULL END AS PURCHASE_ROAS
    , CASE WHEN DAU > 0 THEN TOTAL_REVENUE / DAU ELSE NULL END AS ARPDAU
    , CASE WHEN DAU > 0 THEN TOTAL_ROUNDS / DAU ELSE NULL END AS ROUNDS_PER_DAU
    , CASE WHEN DAU > 0 THEN PURCHASERS / DAU ELSE NULL END AS PAYER_CONVERSION_RATE

FROM combined
WHERE DATE IS NOT NULL
ORDER BY DATE DESC
