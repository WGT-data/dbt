-- int_web_mta__touchpoint_credit.sql
-- Calculates attribution credit for each web session touchpoint using 5 methodologies:
-- 1. Last-Touch: 100% to last session before registration
-- 2. First-Touch: 100% to first session in journey
-- 3. Linear: Equal credit across all sessions
-- 4. Time-Decay: More credit to sessions closer to registration (half-life = 3 days)
-- 5. Position-Based (U-Shaped): 40% first, 40% last, 20% middle
--
-- This is the web equivalent of int_mta__touchpoint_credit.sql for mobile installs.
-- Unlike mobile, there is no click vs impression weighting — all sessions are active visits.
--
-- Grain: One row per touchpoint (session) with credit scores added

{{ config(
    materialized='table',
    tags=['web_mta', 'attribution']
) }}

{% set time_decay_half_life_days = 3 %}
{% set position_first_weight = 0.4 %}
{% set position_last_weight = 0.4 %}

WITH user_journey AS (
    SELECT *
    FROM {{ ref('int_web_mta__user_journey') }}
)

-- Calculate raw time-decay weights
, with_time_decay_raw AS (
    SELECT *
        -- Time decay formula: weight = 2^(-days_to_registration / half_life)
        -- Weight of 1.0 at registration, 0.5 at 3 days before, 0.25 at 6 days, etc.
        , POWER(2, -1.0 * DAYS_TO_REGISTRATION / {{ time_decay_half_life_days }}) AS TIME_DECAY_RAW
    FROM user_journey
)

-- Calculate normalized weights per registration
, with_normalized_weights AS (
    SELECT *
        -- Sum of time-decay weights per user (for normalization to 1.0)
        , SUM(TIME_DECAY_RAW) OVER (
              PARTITION BY BROWSER_DEVICE_ID, REGISTRATION_TIMESTAMP
          ) AS TOTAL_TIME_DECAY_WEIGHT
    FROM with_time_decay_raw
)

-- Calculate all 5 attribution credits
SELECT
    JOURNEY_ROW_KEY
    , BROWSER_DEVICE_ID
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

    -- =============================================
    -- LAST-TOUCH ATTRIBUTION
    -- 100% credit to the last session before registration
    -- =============================================
    , CASE WHEN IS_LAST_TOUCH = 1 THEN 1.0 ELSE 0.0 END AS CREDIT_LAST_TOUCH

    -- =============================================
    -- FIRST-TOUCH ATTRIBUTION
    -- 100% credit to the first session in the journey
    -- =============================================
    , CASE WHEN IS_FIRST_TOUCH = 1 THEN 1.0 ELSE 0.0 END AS CREDIT_FIRST_TOUCH

    -- =============================================
    -- LINEAR ATTRIBUTION
    -- Equal credit to all sessions (1 / total_touchpoints)
    -- =============================================
    , 1.0 / NULLIF(TOTAL_TOUCHPOINTS, 0) AS CREDIT_LINEAR

    -- =============================================
    -- TIME-DECAY ATTRIBUTION
    -- More credit to sessions closer to registration
    -- Half-life: {{ time_decay_half_life_days }} days
    -- =============================================
    , TIME_DECAY_RAW / NULLIF(TOTAL_TIME_DECAY_WEIGHT, 0) AS CREDIT_TIME_DECAY

    -- =============================================
    -- POSITION-BASED (U-SHAPED) ATTRIBUTION
    -- {{ position_first_weight * 100 }}% first, {{ position_last_weight * 100 }}% last, remaining split among middle
    -- =============================================
    , CASE
          -- Single touchpoint gets 100%
          WHEN TOTAL_TOUCHPOINTS = 1 THEN 1.0
          -- Two touchpoints: split proportionally
          WHEN TOTAL_TOUCHPOINTS = 2 THEN
              CASE
                  WHEN IS_FIRST_TOUCH = 1 THEN {{ position_first_weight }} / ({{ position_first_weight }} + {{ position_last_weight }})
                  WHEN IS_LAST_TOUCH = 1 THEN {{ position_last_weight }} / ({{ position_first_weight }} + {{ position_last_weight }})
                  ELSE 0.0
              END
          -- 3+ touchpoints: first and last get fixed weights, middle shares remainder
          ELSE
              CASE
                  WHEN IS_FIRST_TOUCH = 1 THEN {{ position_first_weight }}
                  WHEN IS_LAST_TOUCH = 1 THEN {{ position_last_weight }}
                  ELSE (1.0 - {{ position_first_weight }} - {{ position_last_weight }}) / NULLIF(TOTAL_TOUCHPOINTS - 2, 0)
              END
      END AS CREDIT_POSITION_BASED

    -- Default/recommended credit (Time-Decay)
    , TIME_DECAY_RAW / NULLIF(TOTAL_TIME_DECAY_WEIGHT, 0) AS CREDIT_RECOMMENDED

FROM with_normalized_weights
