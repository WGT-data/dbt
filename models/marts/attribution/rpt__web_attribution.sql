-- rpt__web_attribution.sql
-- Web traffic attribution report from Amplitude events
--
-- PURPOSE: Surface web attribution data that Amplitude captures but no dbt model
-- currently exposes. Shows traffic sources, UTM parameters, and downstream
-- conversion metrics (registrations, revenue) for the wgt.com web platform.
--
-- ATTRIBUTION: Session-level (current visit UTMs), not first-touch.
-- Each session gets its own source/medium/campaign based on the UTM params
-- or referrer that brought the user to the site for that visit.
--
-- DATA SOURCE: Amplitude web events (PLATFORM = 'Web')
--   - session_start events carry session-level UTM params in USER_PROPERTIES
--   - FTE_REGISTERED events track new player registrations
--   - Revenue events track purchases with dollar amounts
--
-- NOTE: Amplitude stores 'EMPTY' (literal string) for missing attribution
-- values, not NULL. All extractions use NULLIF to normalize.
--
-- GRAIN: DATE + TRAFFIC_SOURCE + TRAFFIC_MEDIUM + TRAFFIC_CAMPAIGN

{{ config(
    materialized='table',
    tags=['mart', 'attribution', 'web']
) }}

-- =============================================
-- WEB SESSIONS WITH ATTRIBUTION
-- One row per session, with UTM params from the session_start event
-- =============================================
WITH web_sessions AS (
    SELECT
        DATE(EVENT_TIME) AS DATE
        , USER_ID
        , SESSION_ID

        -- Session-level attribution (updates each visit)
        , COALESCE(
            NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):utm_source::STRING, 'EMPTY'),
            NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):referring_domain::STRING, 'EMPTY'),
            'direct'
          ) AS TRAFFIC_SOURCE
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):utm_medium::STRING, 'EMPTY')
            AS TRAFFIC_MEDIUM
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):utm_campaign::STRING, 'EMPTY')
            AS TRAFFIC_CAMPAIGN
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):utm_content::STRING, 'EMPTY')
            AS TRAFFIC_CONTENT
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):utm_term::STRING, 'EMPTY')
            AS TRAFFIC_TERM

        -- Referrer context
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):referring_domain::STRING, 'EMPTY')
            AS REFERRING_DOMAIN

        -- Click IDs for paid channel attribution
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):gclid::STRING, 'EMPTY')
            AS GCLID
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):fbclid::STRING, 'EMPTY')
            AS FBCLID

    FROM {{ source('amplitude', 'EVENTS_726530') }}
    WHERE PLATFORM = 'Web'
      AND EVENT_TYPE = 'session_start'
      AND EVENT_TIME IS NOT NULL
)

-- =============================================
-- NEW PLAYER REGISTRATIONS
-- FTE_REGISTERED = first-time experience registration completed
-- =============================================
, registrations AS (
    SELECT
        DATE(EVENT_TIME) AS DATE
        , USER_ID
    FROM {{ source('amplitude', 'EVENTS_726530') }}
    WHERE PLATFORM = 'Web'
      AND EVENT_TYPE = 'FTE_REGISTERED'
      AND EVENT_TIME IS NOT NULL
)

-- =============================================
-- REVENUE EVENTS
-- Purchases with dollar amounts in EVENT_PROPERTIES
-- =============================================
, revenue_events AS (
    SELECT
        DATE(EVENT_TIME) AS DATE
        , USER_ID
        , TRY_PARSE_JSON(EVENT_PROPERTIES):"$revenue"::FLOAT AS REVENUE_AMOUNT
    FROM {{ source('amplitude', 'EVENTS_726530') }}
    WHERE PLATFORM = 'Web'
      AND EVENT_TYPE = 'Revenue'
      AND EVENT_TIME IS NOT NULL
)

-- =============================================
-- SESSION-USER-DATE BRIDGE
-- Link sessions to their registrations and revenue on the same date
-- =============================================
, session_conversions AS (
    SELECT
        ws.DATE
        , ws.TRAFFIC_SOURCE
        , ws.TRAFFIC_MEDIUM
        , ws.TRAFFIC_CAMPAIGN
        , ws.SESSION_ID
        , ws.USER_ID
        , ws.GCLID
        , ws.FBCLID

        -- Did this user register on this date?
        , CASE WHEN r.USER_ID IS NOT NULL THEN 1 ELSE 0 END AS IS_REGISTRATION

        -- Revenue from this user on this date
        , rev.REVENUE_AMOUNT
        , CASE WHEN rev.USER_ID IS NOT NULL THEN 1 ELSE 0 END AS IS_PAYING

    FROM web_sessions ws
    LEFT JOIN registrations r
        ON ws.USER_ID = r.USER_ID
        AND ws.DATE = r.DATE
    LEFT JOIN (
        SELECT DATE, USER_ID, SUM(REVENUE_AMOUNT) AS REVENUE_AMOUNT
        FROM revenue_events
        GROUP BY 1, 2
    ) rev
        ON ws.USER_ID = rev.USER_ID
        AND ws.DATE = rev.DATE
)

-- =============================================
-- FINAL AGGREGATION
-- =============================================
SELECT
    DATE
    , TRAFFIC_SOURCE
    , TRAFFIC_MEDIUM
    , TRAFFIC_CAMPAIGN

    -- Traffic volume
    , COUNT(DISTINCT SESSION_ID) AS SESSIONS
    , COUNT(DISTINCT USER_ID) AS UNIQUE_USERS

    -- Conversions
    , COUNT(DISTINCT CASE WHEN IS_REGISTRATION = 1 THEN USER_ID END) AS REGISTRATIONS
    , COUNT(DISTINCT CASE WHEN IS_PAYING = 1 THEN USER_ID END) AS PAYING_USERS
    , COALESCE(SUM(CASE WHEN IS_PAYING = 1 THEN REVENUE_AMOUNT END), 0) AS REVENUE

    -- Paid channel indicators
    , COUNT(DISTINCT CASE WHEN GCLID IS NOT NULL THEN SESSION_ID END) AS GCLID_SESSIONS
    , COUNT(DISTINCT CASE WHEN FBCLID IS NOT NULL THEN SESSION_ID END) AS FBCLID_SESSIONS

FROM session_conversions
GROUP BY 1, 2, 3, 4
