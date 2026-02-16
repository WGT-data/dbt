-- int_web_mta__user_journey.sql
-- Maps all anonymous web sessions (touchpoints) to registrations (conversions)
-- This is the web equivalent of int_mta__user_journey.sql for mobile installs
--
-- IDENTITY RESOLUTION:
-- Amplitude's web SDK assigns a browser DEVICE_ID (UUIDv4) to anonymous visitors.
-- When a user registers, the game sets USER_ID on the SDK, so post-registration
-- browser events carry both the browser DEVICE_ID and the numeric game USER_ID.
-- We use this transition (NULL USER_ID → numeric USER_ID on the same DEVICE_ID)
-- to link anonymous pre-registration sessions back to the registration.
--
-- Note: The server-side FTE_REGISTERED event uses a DIFFERENT DEVICE_ID (UUIDv5,
-- server-generated) and SESSION_ID = -1. It cannot be used to link browser sessions.
--
-- TOUCHPOINTS: Each anonymous session_start event with UTM params or referrer data
-- CONVERSION: Registration (first identified browser event with numeric USER_ID)
-- LOOKBACK: 30 days before registration
--
-- Grain: One row per BROWSER_DEVICE_ID + SESSION_ID + REGISTRATION_TIMESTAMP

{{ config(
    materialized='table',
    tags=['web_mta', 'attribution']
) }}

{% set lookback_window_days = 30 %}

-- =============================================
-- IDENTITY BRIDGE
-- Find browser DEVICE_IDs that transition from anonymous to identified
-- The first identified browser event tells us when registration happened
-- =============================================
WITH registered_devices AS (
    SELECT
        DEVICE_ID AS BROWSER_DEVICE_ID
        , MIN(USER_ID) AS GAME_USER_ID
        , MIN(EVENT_TIME) AS REGISTRATION_TIME
    FROM {{ source('amplitude', 'EVENTS_726530') }}
    WHERE PLATFORM = 'Web'
      AND SESSION_ID != -1                                    -- browser events only
      AND USER_ID IS NOT NULL
      AND TRY_CAST(USER_ID AS INTEGER) IS NOT NULL            -- numeric game USER_ID
    GROUP BY 1
    -- Only include devices that also had anonymous events (the transition)
    HAVING BROWSER_DEVICE_ID IN (
        SELECT DISTINCT DEVICE_ID
        FROM {{ source('amplitude', 'EVENTS_726530') }}
        WHERE PLATFORM = 'Web'
          AND EVENT_TYPE = 'session_start'
          AND USER_ID IS NULL
    )
)

-- =============================================
-- ANONYMOUS PRE-REGISTRATION SESSIONS
-- All session_start events before registration, with UTM attribution
-- =============================================
, anonymous_sessions AS (
    SELECT
        DEVICE_ID AS BROWSER_DEVICE_ID
        , SESSION_ID
        , EVENT_TIME AS SESSION_TIMESTAMP

        -- Session-level attribution
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
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):referring_domain::STRING, 'EMPTY')
            AS REFERRING_DOMAIN
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):gclid::STRING, 'EMPTY')
            AS GCLID
        , NULLIF(TRY_PARSE_JSON(USER_PROPERTIES):fbclid::STRING, 'EMPTY')
            AS FBCLID

    FROM {{ source('amplitude', 'EVENTS_726530') }}
    WHERE PLATFORM = 'Web'
      AND EVENT_TYPE = 'session_start'
      AND USER_ID IS NULL  -- anonymous pre-registration sessions
      AND EVENT_TIME IS NOT NULL
)

-- =============================================
-- JOIN: Link anonymous sessions to registrations
-- Only sessions within lookback window before registration
-- =============================================
, journey_raw AS (
    SELECT
        a.BROWSER_DEVICE_ID
        , rd.GAME_USER_ID
        , a.SESSION_ID
        , a.TRAFFIC_SOURCE
        , a.TRAFFIC_MEDIUM
        , a.TRAFFIC_CAMPAIGN
        , a.TRAFFIC_CONTENT
        , a.TRAFFIC_TERM
        , a.REFERRING_DOMAIN
        , a.GCLID
        , a.FBCLID
        , a.SESSION_TIMESTAMP
        , rd.REGISTRATION_TIME AS REGISTRATION_TIMESTAMP
        , DATEDIFF('hour', a.SESSION_TIMESTAMP, rd.REGISTRATION_TIME) AS HOURS_TO_REGISTRATION
        , DATEDIFF('day', a.SESSION_TIMESTAMP, rd.REGISTRATION_TIME) AS DAYS_TO_REGISTRATION
    FROM anonymous_sessions a
    INNER JOIN registered_devices rd
        ON a.BROWSER_DEVICE_ID = rd.BROWSER_DEVICE_ID
    WHERE a.SESSION_TIMESTAMP < rd.REGISTRATION_TIME
      AND a.SESSION_TIMESTAMP >= DATEADD('day', -{{ lookback_window_days }}, rd.REGISTRATION_TIME)
)

-- =============================================
-- DEDUPLICATE
-- Multiple session_start events can fire in the same session
-- Keep the first one per SESSION_ID per user
-- =============================================
, journey_deduped AS (
    SELECT *
    FROM journey_raw
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY BROWSER_DEVICE_ID, SESSION_ID, REGISTRATION_TIMESTAMP
        ORDER BY SESSION_TIMESTAMP ASC
    ) = 1
)

-- =============================================
-- CALCULATE JOURNEY POSITION
-- =============================================
, journey_with_position AS (
    SELECT *
        -- Position from first touchpoint (1 = first)
        , ROW_NUMBER() OVER (
              PARTITION BY BROWSER_DEVICE_ID, REGISTRATION_TIMESTAMP
              ORDER BY SESSION_TIMESTAMP ASC
          ) AS TOUCHPOINT_POSITION
        -- Position from last touchpoint (1 = last)
        , ROW_NUMBER() OVER (
              PARTITION BY BROWSER_DEVICE_ID, REGISTRATION_TIMESTAMP
              ORDER BY SESSION_TIMESTAMP DESC
          ) AS REVERSE_POSITION
        -- Total touchpoints in journey
        , COUNT(*) OVER (
              PARTITION BY BROWSER_DEVICE_ID, REGISTRATION_TIMESTAMP
          ) AS TOTAL_TOUCHPOINTS
        -- First touch flag
        , CASE WHEN ROW_NUMBER() OVER (
              PARTITION BY BROWSER_DEVICE_ID, REGISTRATION_TIMESTAMP
              ORDER BY SESSION_TIMESTAMP ASC
          ) = 1 THEN 1 ELSE 0 END AS IS_FIRST_TOUCH
        -- Last touch flag
        , CASE WHEN ROW_NUMBER() OVER (
              PARTITION BY BROWSER_DEVICE_ID, REGISTRATION_TIMESTAMP
              ORDER BY SESSION_TIMESTAMP DESC
          ) = 1 THEN 1 ELSE 0 END AS IS_LAST_TOUCH
    FROM journey_deduped
)

SELECT
    BROWSER_DEVICE_ID
    , GAME_USER_ID
    , SESSION_ID
    , TRAFFIC_SOURCE
    , TRAFFIC_MEDIUM
    , TRAFFIC_CAMPAIGN
    , TRAFFIC_CONTENT
    , TRAFFIC_TERM
    , REFERRING_DOMAIN
    , GCLID
    , FBCLID
    , SESSION_TIMESTAMP
    , REGISTRATION_TIMESTAMP
    , HOURS_TO_REGISTRATION
    , DAYS_TO_REGISTRATION
    , TOUCHPOINT_POSITION
    , REVERSE_POSITION
    , TOTAL_TOUCHPOINTS
    , IS_FIRST_TOUCH
    , IS_LAST_TOUCH
    , MD5(
        CONCAT(
            COALESCE(BROWSER_DEVICE_ID, '')
            , '||', COALESCE(TO_VARCHAR(SESSION_ID), '')
            , '||', COALESCE(TO_VARCHAR(SESSION_TIMESTAMP), '')
            , '||', COALESCE(TO_VARCHAR(REGISTRATION_TIMESTAMP), '')
        )
      ) AS JOURNEY_ROW_KEY
FROM journey_with_position
