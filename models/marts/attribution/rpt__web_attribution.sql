-- rpt__web_attribution.sql
-- Web traffic attribution report with multi-touch attribution for registrations
--
-- PURPOSE: Surface web attribution data from Amplitude with proper multi-touch
-- attribution for registrations. Shows 5 attribution models side-by-side so you
-- can see how credit shifts between channels (e.g., Facebook drives discovery
-- but users return via Google/direct to register).
--
-- MULTI-TOUCH ATTRIBUTION:
-- Uses the int_web_mta pipeline which links anonymous pre-registration browser
-- sessions to registrations via Amplitude's DEVICE_ID identity bridge.
-- 5 attribution models: last-touch, first-touch, linear, time-decay, position-based.
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
-- MTA REGISTRATION CREDITS
-- Fractional registration credit per session touchpoint
-- =============================================
WITH mta_credits AS (
    SELECT
        DATE(SESSION_TIMESTAMP) AS DATE
        , TRAFFIC_SOURCE
        , TRAFFIC_MEDIUM
        , TRAFFIC_CAMPAIGN
        , GAME_USER_ID
        , SESSION_ID
        , GCLID
        , FBCLID
        , CREDIT_LAST_TOUCH
        , CREDIT_FIRST_TOUCH
        , CREDIT_LINEAR
        , CREDIT_TIME_DECAY
        , CREDIT_POSITION_BASED
    FROM {{ ref('int_web_mta__touchpoint_credit') }}
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
-- AGGREGATE MTA CREDITS BY SOURCE
-- =============================================
, registration_credits AS (
    SELECT
        DATE
        , TRAFFIC_SOURCE
        , TRAFFIC_MEDIUM
        , TRAFFIC_CAMPAIGN
        , SUM(CREDIT_LAST_TOUCH) AS REGS_LAST_TOUCH
        , SUM(CREDIT_FIRST_TOUCH) AS REGS_FIRST_TOUCH
        , SUM(CREDIT_LINEAR) AS REGS_LINEAR
        , SUM(CREDIT_TIME_DECAY) AS REGS_TIME_DECAY
        , SUM(CREDIT_POSITION_BASED) AS REGS_POSITION_BASED
        , COUNT(DISTINCT GAME_USER_ID) AS UNIQUE_REGISTRANTS
    FROM mta_credits
    GROUP BY 1, 2, 3, 4
)

-- =============================================
-- COMBINE TRAFFIC + REGISTRATIONS
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

    -- Paid channel indicators
    , COALESCE(st.GCLID_SESSIONS, 0) AS GCLID_SESSIONS
    , COALESCE(st.FBCLID_SESSIONS, 0) AS FBCLID_SESSIONS

FROM session_totals st
FULL OUTER JOIN registration_credits rc
    ON st.DATE = rc.DATE
    AND st.TRAFFIC_SOURCE = rc.TRAFFIC_SOURCE
    AND COALESCE(st.TRAFFIC_MEDIUM, '___NULL___') = COALESCE(rc.TRAFFIC_MEDIUM, '___NULL___')
    AND COALESCE(st.TRAFFIC_CAMPAIGN, '___NULL___') = COALESCE(rc.TRAFFIC_CAMPAIGN, '___NULL___')
