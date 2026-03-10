-- mart_blended_performance.sql
-- Blended web + mobile performance view
--
-- PURPOSE: Unified daily channel/campaign performance combining mobile spend+attribution
-- and web traffic+attribution into a single BI-ready view. Answers "how is each channel
-- performing across ALL acquisition types?"
--
-- Unlike mart_attribution__combined (which stacks web + mobile with separate rows),
-- this model aggregates to CHANNEL + CAMPAIGN + DATE grain, summing mobile spend/installs
-- alongside web sessions/registrations. This enables cross-platform channel comparison.
--
-- SPEND: Mobile-only (from Adjust API via mta__campaign_performance)
-- WEB TRAFFIC: From rpt__web_attribution (sessions, registrations)
-- REVENUE: Attributed revenue from both pipelines (time-decay recommended model)
--
-- Grain: DATE + CHANNEL + CAMPAIGN

{{ config(
    materialized='table',
    tags=['mart', 'attribution', 'blended']
) }}

-- =============================================
-- MOBILE: Spend + MTA installs + revenue (time-decay recommended)
-- =============================================
WITH mobile AS (
    SELECT
        DATE
        , AD_PARTNER AS CHANNEL
        , CAMPAIGN_NAME AS CAMPAIGN
        , SUM(COST) AS MOBILE_SPEND
        , SUM(IMPRESSIONS) AS MOBILE_IMPRESSIONS
        , SUM(CLICKS) AS MOBILE_CLICKS
        , SUM(INSTALLS_TIME_DECAY) AS MOBILE_INSTALLS
        , SUM(D7_REVENUE_TIME_DECAY) AS MOBILE_D7_REVENUE
        , SUM(D30_REVENUE_TIME_DECAY) AS MOBILE_D30_REVENUE
        , SUM(TOTAL_REVENUE_TIME_DECAY) AS MOBILE_TOTAL_REVENUE
        , SUM(UNIQUE_DEVICES) AS MOBILE_UNIQUE_DEVICES
    FROM {{ ref('mta__campaign_performance') }}
    GROUP BY 1, 2, 3
)

-- =============================================
-- WEB: Traffic + MTA registrations + revenue (time-decay)
-- =============================================
, web AS (
    SELECT
        DATE
        , TRAFFIC_SOURCE AS CHANNEL
        , TRAFFIC_CAMPAIGN AS CAMPAIGN
        , SUM(SESSIONS) AS WEB_SESSIONS
        , SUM(UNIQUE_DEVICES) AS WEB_UNIQUE_DEVICES
        , SUM(REGS_TIME_DECAY) AS WEB_REGISTRATIONS
        , SUM(D7_REVENUE_TIME_DECAY) AS WEB_D7_REVENUE
        , SUM(D30_REVENUE_TIME_DECAY) AS WEB_D30_REVENUE
        , SUM(TOTAL_REVENUE_TIME_DECAY) AS WEB_TOTAL_REVENUE
        , SUM(UNIQUE_PAYERS) AS WEB_PAYERS
    FROM {{ ref('rpt__web_attribution') }}
    GROUP BY 1, 2, 3
)

-- =============================================
-- BLEND: Full outer join on channel + campaign + date
-- =============================================
, blended AS (
    SELECT
        COALESCE(m.DATE, w.DATE) AS DATE
        , COALESCE(m.CHANNEL, w.CHANNEL) AS CHANNEL
        , COALESCE(m.CAMPAIGN, w.CAMPAIGN) AS CAMPAIGN

        -- Mobile metrics
        , COALESCE(m.MOBILE_SPEND, 0) AS MOBILE_SPEND
        , COALESCE(m.MOBILE_IMPRESSIONS, 0) AS MOBILE_IMPRESSIONS
        , COALESCE(m.MOBILE_CLICKS, 0) AS MOBILE_CLICKS
        , COALESCE(m.MOBILE_INSTALLS, 0) AS MOBILE_INSTALLS
        , COALESCE(m.MOBILE_D7_REVENUE, 0) AS MOBILE_D7_REVENUE
        , COALESCE(m.MOBILE_D30_REVENUE, 0) AS MOBILE_D30_REVENUE
        , COALESCE(m.MOBILE_TOTAL_REVENUE, 0) AS MOBILE_TOTAL_REVENUE
        , COALESCE(m.MOBILE_UNIQUE_DEVICES, 0) AS MOBILE_UNIQUE_DEVICES

        -- Web metrics
        , COALESCE(w.WEB_SESSIONS, 0) AS WEB_SESSIONS
        , COALESCE(w.WEB_UNIQUE_DEVICES, 0) AS WEB_UNIQUE_DEVICES
        , COALESCE(w.WEB_REGISTRATIONS, 0) AS WEB_REGISTRATIONS
        , COALESCE(w.WEB_D7_REVENUE, 0) AS WEB_D7_REVENUE
        , COALESCE(w.WEB_D30_REVENUE, 0) AS WEB_D30_REVENUE
        , COALESCE(w.WEB_TOTAL_REVENUE, 0) AS WEB_TOTAL_REVENUE
        , COALESCE(w.WEB_PAYERS, 0) AS WEB_PAYERS

    FROM mobile m
    FULL OUTER JOIN web w
        ON m.DATE = w.DATE
        AND LOWER(m.CHANNEL) = LOWER(w.CHANNEL)
        AND LOWER(COALESCE(m.CAMPAIGN, '___NULL___')) = LOWER(COALESCE(w.CAMPAIGN, '___NULL___'))
)

SELECT
    DATE
    , CHANNEL
    , CAMPAIGN

    -- Blended totals
    , MOBILE_SPEND AS TOTAL_SPEND
    , MOBILE_INSTALLS + WEB_REGISTRATIONS AS TOTAL_CONVERSIONS
    , MOBILE_D7_REVENUE + WEB_D7_REVENUE AS TOTAL_D7_REVENUE
    , MOBILE_D30_REVENUE + WEB_D30_REVENUE AS TOTAL_D30_REVENUE
    , MOBILE_TOTAL_REVENUE + WEB_TOTAL_REVENUE AS TOTAL_REVENUE

    -- Blended efficiency
    , CASE WHEN (MOBILE_INSTALLS + WEB_REGISTRATIONS) > 0 AND MOBILE_SPEND > 0
        THEN MOBILE_SPEND / (MOBILE_INSTALLS + WEB_REGISTRATIONS)
        ELSE NULL END AS BLENDED_CPA
    , CASE WHEN MOBILE_SPEND > 0
        THEN (MOBILE_D7_REVENUE + WEB_D7_REVENUE) / MOBILE_SPEND
        ELSE NULL END AS BLENDED_D7_ROAS
    , CASE WHEN MOBILE_SPEND > 0
        THEN (MOBILE_D30_REVENUE + WEB_D30_REVENUE) / MOBILE_SPEND
        ELSE NULL END AS BLENDED_D30_ROAS
    , CASE WHEN MOBILE_SPEND > 0
        THEN (MOBILE_TOTAL_REVENUE + WEB_TOTAL_REVENUE) / MOBILE_SPEND
        ELSE NULL END AS BLENDED_TOTAL_ROAS

    -- Mobile detail
    , MOBILE_SPEND
    , MOBILE_IMPRESSIONS
    , MOBILE_CLICKS
    , MOBILE_INSTALLS
    , MOBILE_D7_REVENUE
    , MOBILE_D30_REVENUE
    , MOBILE_TOTAL_REVENUE
    , MOBILE_UNIQUE_DEVICES

    -- Web detail
    , WEB_SESSIONS
    , WEB_UNIQUE_DEVICES
    , WEB_REGISTRATIONS
    , WEB_D7_REVENUE
    , WEB_D30_REVENUE
    , WEB_TOTAL_REVENUE
    , WEB_PAYERS

    -- Platform flags for filtering
    , MOBILE_INSTALLS > 0 OR MOBILE_SPEND > 0 AS HAS_MOBILE_DATA
    , WEB_SESSIONS > 0 OR WEB_REGISTRATIONS > 0 AS HAS_WEB_DATA

FROM blended
WHERE DATE IS NOT NULL
