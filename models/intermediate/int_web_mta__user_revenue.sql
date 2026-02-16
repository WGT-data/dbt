-- int_web_mta__user_revenue.sql
-- Per-user revenue metrics for web registrants, used for MTA revenue attribution.
-- Calculates D7/D30/Total revenue windows anchored to REGISTRATION_TIMESTAMP.
--
-- Revenue is CROSS-PLATFORM (no platform filter): a user who registers on web
-- but later pays on iOS/Android still counts as web-acquired revenue.
-- This represents the true LTV of web-acquired users.
--
-- Grain: One row per GAME_USER_ID

{{ config(
    materialized='table',
    tags=['web_mta', 'attribution']
) }}

-- Deduplicated web registrants from the user journey
-- Also count distinct journeys per user so revenue can be divided evenly
-- across journeys in the report (prevents double-counting when a user has
-- multiple browser DEVICE_IDs that each resolve to the same GAME_USER_ID)
WITH web_registrants AS (
    SELECT
        GAME_USER_ID
        , MIN(REGISTRATION_TIMESTAMP) AS REGISTRATION_TIMESTAMP
        , MIN(DATE(REGISTRATION_TIMESTAMP)) AS REGISTRATION_DATE
        , COUNT(DISTINCT BROWSER_DEVICE_ID || '|' || REGISTRATION_TIMESTAMP) AS JOURNEY_COUNT
    FROM {{ ref('int_web_mta__user_journey') }}
    WHERE GAME_USER_ID IS NOT NULL
    GROUP BY 1
)

-- Revenue events from WGT.EVENTS.REVENUE — all platforms, no filter
, revenue_events AS (
    SELECT
        USERID AS USER_ID
        , EVENTTIME AS EVENT_TIME
        , COALESCE(REVENUE, 0) AS REVENUE
    FROM {{ source('events', 'REVENUE') }}
    WHERE REVENUE IS NOT NULL
)

-- Calculate revenue metrics per user
SELECT
    u.GAME_USER_ID
    , u.REGISTRATION_DATE
    , u.REGISTRATION_TIMESTAMP

    -- D7 Total Revenue (within 7 days of registration)
    , SUM(CASE
        WHEN r.EVENT_TIME <= DATEADD(day, 7, u.REGISTRATION_TIMESTAMP)
        THEN r.REVENUE
        ELSE 0
    END) AS D7_REVENUE

    -- D30 Total Revenue (within 30 days of registration)
    , SUM(CASE
        WHEN r.EVENT_TIME <= DATEADD(day, 30, u.REGISTRATION_TIMESTAMP)
        THEN r.REVENUE
        ELSE 0
    END) AS D30_REVENUE

    -- Lifetime Total Revenue (all revenue post-registration)
    , SUM(COALESCE(r.REVENUE, 0)) AS TOTAL_REVENUE

    -- Payer flag
    , MAX(CASE WHEN r.REVENUE > 0 THEN 1 ELSE 0 END) AS IS_PAYER

    -- Journey count for revenue conservation in MTA attribution
    -- When a user has N journeys, each journey's revenue = user_revenue / N
    , MAX(u.JOURNEY_COUNT) AS JOURNEY_COUNT

FROM web_registrants u
LEFT JOIN revenue_events r
    ON u.GAME_USER_ID = r.USER_ID
    AND r.EVENT_TIME >= u.REGISTRATION_TIMESTAMP
GROUP BY 1, 2, 3
