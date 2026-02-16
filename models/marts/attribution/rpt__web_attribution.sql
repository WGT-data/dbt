-- rpt__web_attribution.sql
-- Web traffic attribution report with multi-touch attribution for registrations AND revenue
--
-- PURPOSE: Surface web attribution data from Amplitude with proper multi-touch
-- attribution for registrations and revenue. Shows 5 attribution models side-by-side
-- so you can see how credit shifts between channels (e.g., Facebook drives discovery
-- but users return via Google/direct to register).
--
-- MULTI-TOUCH ATTRIBUTION:
-- Uses the int_web_mta pipeline which links anonymous pre-registration browser
-- sessions to registrations via Amplitude's DEVICE_ID identity bridge.
-- 5 attribution models: last-touch, first-touch, linear, time-decay, position-based.
--
-- REVENUE ATTRIBUTION:
-- Revenue is attributed using CREDIT_X * USER_REVENUE multiplication (same pattern
-- as mta__campaign_performance.sql). Revenue is cross-platform — a web registrant's
-- iOS/Android/Desktop purchases all count toward the web channel that acquired them.
--
-- TOTAL TRAFFIC VOLUME:
-- Also counts ALL anonymous web sessions (not just converting ones) to show
-- the full traffic funnel: sessions → registrations → revenue.
--
-- GRAIN: DATE + TRAFFIC_SOURCE + TRAFFIC_MEDIUM + TRAFFIC_CAMPAIGN

{{ config(
    materialized='table',
    tags=['mart', 'attribution', 'web', 'web_mta']
) }}

-- =============================================
-- USER REVENUE METRICS (cross-platform LTV per web registrant)
-- =============================================
WITH user_revenue AS (
    SELECT
        GAME_USER_ID
        -- Divide revenue by journey count so total is conserved across MTA attribution.
        -- A user with N browser journeys gets 1/N of their revenue per journey,
        -- then each journey's touchpoints split that share by credit weight.
        , D7_REVENUE / JOURNEY_COUNT AS D7_REVENUE
        , D30_REVENUE / JOURNEY_COUNT AS D30_REVENUE
        , TOTAL_REVENUE / JOURNEY_COUNT AS TOTAL_REVENUE
        , IS_PAYER
    FROM {{ ref('int_web_mta__user_revenue') }}
)

-- =============================================
-- MTA REGISTRATION CREDITS + USER REVENUE
-- Fractional registration credit per session touchpoint, joined to user revenue
-- =============================================
, mta_credits AS (
    SELECT
        DATE(tc.SESSION_TIMESTAMP) AS DATE
        , tc.TRAFFIC_SOURCE
        , tc.TRAFFIC_MEDIUM
        , tc.TRAFFIC_CAMPAIGN
        , tc.GAME_USER_ID
        , tc.SESSION_ID
        , tc.GCLID
        , tc.FBCLID
        , tc.CREDIT_LAST_TOUCH
        , tc.CREDIT_FIRST_TOUCH
        , tc.CREDIT_LINEAR
        , tc.CREDIT_TIME_DECAY
        , tc.CREDIT_POSITION_BASED
        , COALESCE(ur.D7_REVENUE, 0) AS USER_D7_REVENUE
        , COALESCE(ur.D30_REVENUE, 0) AS USER_D30_REVENUE
        , COALESCE(ur.TOTAL_REVENUE, 0) AS USER_TOTAL_REVENUE
        , COALESCE(ur.IS_PAYER, 0) AS IS_PAYER
    FROM {{ ref('int_web_mta__touchpoint_credit') }} tc
    LEFT JOIN user_revenue ur
        ON tc.GAME_USER_ID = ur.GAME_USER_ID
)

-- =============================================
-- ALL ANONYMOUS WEB SESSIONS (full traffic volume)
-- Not just converting users — this is the denominator for conversion rates
-- =============================================
, all_sessions AS (
    SELECT
        DATE(EVENT_TIME) AS DATE
        , COALESCE(
            NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):utm_source::STRING, 'EMPTY'),
            NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):referring_domain::STRING, 'EMPTY'),
            'direct'
          ) AS TRAFFIC_SOURCE
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):utm_medium::STRING, 'EMPTY')
            AS TRAFFIC_MEDIUM
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):utm_campaign::STRING, 'EMPTY')
            AS TRAFFIC_CAMPAIGN
        , SESSION_ID
        , DEVICE_ID AS BROWSER_DEVICE_ID
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):gclid::STRING, 'EMPTY')
            AS GCLID
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):fbclid::STRING, 'EMPTY')
            AS FBCLID
    FROM {{ source('amplitude', 'EVENTS_726530') }}
    WHERE PLATFORM = 'Web'
      AND EVENT_TYPE = 'session_start'
      AND USER_ID IS NULL  -- anonymous sessions (86% of web traffic)
      AND EVENT_TIME IS NOT NULL
)

-- =============================================
-- AGGREGATE TOTAL SESSIONS BY SOURCE
-- =============================================
, session_totals AS (
    SELECT
        DATE
        , TRAFFIC_SOURCE
        , TRAFFIC_MEDIUM
        , TRAFFIC_CAMPAIGN
        , COUNT(DISTINCT SESSION_ID) AS SESSIONS
        , COUNT(DISTINCT BROWSER_DEVICE_ID) AS UNIQUE_DEVICES
        , COUNT(DISTINCT CASE WHEN GCLID IS NOT NULL THEN SESSION_ID END) AS GCLID_SESSIONS
        , COUNT(DISTINCT CASE WHEN FBCLID IS NOT NULL THEN SESSION_ID END) AS FBCLID_SESSIONS
    FROM all_sessions
    GROUP BY 1, 2, 3, 4
)

-- =============================================
-- AGGREGATE MTA CREDITS BY SOURCE (registrations + revenue)
-- =============================================
, registration_credits AS (
    SELECT
        DATE
        , TRAFFIC_SOURCE
        , TRAFFIC_MEDIUM
        , TRAFFIC_CAMPAIGN

        -- Registration credits (5 models)
        , SUM(CREDIT_LAST_TOUCH) AS REGS_LAST_TOUCH
        , SUM(CREDIT_FIRST_TOUCH) AS REGS_FIRST_TOUCH
        , SUM(CREDIT_LINEAR) AS REGS_LINEAR
        , SUM(CREDIT_TIME_DECAY) AS REGS_TIME_DECAY
        , SUM(CREDIT_POSITION_BASED) AS REGS_POSITION_BASED
        , COUNT(DISTINCT GAME_USER_ID) AS UNIQUE_REGISTRANTS

        -- D7 Revenue attribution (CREDIT × USER_REVENUE)
        , SUM(CREDIT_LAST_TOUCH * USER_D7_REVENUE) AS D7_REVENUE_LAST_TOUCH
        , SUM(CREDIT_FIRST_TOUCH * USER_D7_REVENUE) AS D7_REVENUE_FIRST_TOUCH
        , SUM(CREDIT_LINEAR * USER_D7_REVENUE) AS D7_REVENUE_LINEAR
        , SUM(CREDIT_TIME_DECAY * USER_D7_REVENUE) AS D7_REVENUE_TIME_DECAY
        , SUM(CREDIT_POSITION_BASED * USER_D7_REVENUE) AS D7_REVENUE_POSITION_BASED

        -- D30 Revenue attribution
        , SUM(CREDIT_LAST_TOUCH * USER_D30_REVENUE) AS D30_REVENUE_LAST_TOUCH
        , SUM(CREDIT_FIRST_TOUCH * USER_D30_REVENUE) AS D30_REVENUE_FIRST_TOUCH
        , SUM(CREDIT_LINEAR * USER_D30_REVENUE) AS D30_REVENUE_LINEAR
        , SUM(CREDIT_TIME_DECAY * USER_D30_REVENUE) AS D30_REVENUE_TIME_DECAY
        , SUM(CREDIT_POSITION_BASED * USER_D30_REVENUE) AS D30_REVENUE_POSITION_BASED

        -- Total Revenue attribution
        , SUM(CREDIT_LAST_TOUCH * USER_TOTAL_REVENUE) AS TOTAL_REVENUE_LAST_TOUCH
        , SUM(CREDIT_FIRST_TOUCH * USER_TOTAL_REVENUE) AS TOTAL_REVENUE_FIRST_TOUCH
        , SUM(CREDIT_LINEAR * USER_TOTAL_REVENUE) AS TOTAL_REVENUE_LINEAR
        , SUM(CREDIT_TIME_DECAY * USER_TOTAL_REVENUE) AS TOTAL_REVENUE_TIME_DECAY
        , SUM(CREDIT_POSITION_BASED * USER_TOTAL_REVENUE) AS TOTAL_REVENUE_POSITION_BASED

        -- Unique payers
        , COUNT(DISTINCT CASE WHEN IS_PAYER = 1 THEN GAME_USER_ID END) AS UNIQUE_PAYERS

    FROM mta_credits
    GROUP BY 1, 2, 3, 4
)

-- =============================================
-- COMBINE TRAFFIC + REGISTRATIONS + REVENUE
-- =============================================
SELECT
    COALESCE(st.DATE, rc.DATE) AS DATE
    , COALESCE(st.TRAFFIC_SOURCE, rc.TRAFFIC_SOURCE) AS TRAFFIC_SOURCE
    , COALESCE(st.TRAFFIC_MEDIUM, rc.TRAFFIC_MEDIUM) AS TRAFFIC_MEDIUM
    , COALESCE(st.TRAFFIC_CAMPAIGN, rc.TRAFFIC_CAMPAIGN) AS TRAFFIC_CAMPAIGN

    -- Traffic volume (all anonymous sessions)
    , COALESCE(st.SESSIONS, 0) AS SESSIONS
    , COALESCE(st.UNIQUE_DEVICES, 0) AS UNIQUE_DEVICES

    -- Multi-touch registration credits (5 models)
    , COALESCE(rc.REGS_LAST_TOUCH, 0) AS REGS_LAST_TOUCH
    , COALESCE(rc.REGS_FIRST_TOUCH, 0) AS REGS_FIRST_TOUCH
    , COALESCE(rc.REGS_LINEAR, 0) AS REGS_LINEAR
    , COALESCE(rc.REGS_TIME_DECAY, 0) AS REGS_TIME_DECAY
    , COALESCE(rc.REGS_POSITION_BASED, 0) AS REGS_POSITION_BASED
    , COALESCE(rc.UNIQUE_REGISTRANTS, 0) AS UNIQUE_REGISTRANTS

    -- D7 Revenue attribution (5 models)
    , COALESCE(rc.D7_REVENUE_LAST_TOUCH, 0) AS D7_REVENUE_LAST_TOUCH
    , COALESCE(rc.D7_REVENUE_FIRST_TOUCH, 0) AS D7_REVENUE_FIRST_TOUCH
    , COALESCE(rc.D7_REVENUE_LINEAR, 0) AS D7_REVENUE_LINEAR
    , COALESCE(rc.D7_REVENUE_TIME_DECAY, 0) AS D7_REVENUE_TIME_DECAY
    , COALESCE(rc.D7_REVENUE_POSITION_BASED, 0) AS D7_REVENUE_POSITION_BASED

    -- D30 Revenue attribution (5 models)
    , COALESCE(rc.D30_REVENUE_LAST_TOUCH, 0) AS D30_REVENUE_LAST_TOUCH
    , COALESCE(rc.D30_REVENUE_FIRST_TOUCH, 0) AS D30_REVENUE_FIRST_TOUCH
    , COALESCE(rc.D30_REVENUE_LINEAR, 0) AS D30_REVENUE_LINEAR
    , COALESCE(rc.D30_REVENUE_TIME_DECAY, 0) AS D30_REVENUE_TIME_DECAY
    , COALESCE(rc.D30_REVENUE_POSITION_BASED, 0) AS D30_REVENUE_POSITION_BASED

    -- Total Revenue attribution (5 models)
    , COALESCE(rc.TOTAL_REVENUE_LAST_TOUCH, 0) AS TOTAL_REVENUE_LAST_TOUCH
    , COALESCE(rc.TOTAL_REVENUE_FIRST_TOUCH, 0) AS TOTAL_REVENUE_FIRST_TOUCH
    , COALESCE(rc.TOTAL_REVENUE_LINEAR, 0) AS TOTAL_REVENUE_LINEAR
    , COALESCE(rc.TOTAL_REVENUE_TIME_DECAY, 0) AS TOTAL_REVENUE_TIME_DECAY
    , COALESCE(rc.TOTAL_REVENUE_POSITION_BASED, 0) AS TOTAL_REVENUE_POSITION_BASED

    -- Payer count
    , COALESCE(rc.UNIQUE_PAYERS, 0) AS UNIQUE_PAYERS

    -- Paid channel indicators
    , COALESCE(st.GCLID_SESSIONS, 0) AS GCLID_SESSIONS
    , COALESCE(st.FBCLID_SESSIONS, 0) AS FBCLID_SESSIONS

FROM session_totals st
FULL OUTER JOIN registration_credits rc
    ON st.DATE = rc.DATE
    AND st.TRAFFIC_SOURCE = rc.TRAFFIC_SOURCE
    AND COALESCE(st.TRAFFIC_MEDIUM, '___NULL___') = COALESCE(rc.TRAFFIC_MEDIUM, '___NULL___')
    AND COALESCE(st.TRAFFIC_CAMPAIGN, '___NULL___') = COALESCE(rc.TRAFFIC_CAMPAIGN, '___NULL___')
