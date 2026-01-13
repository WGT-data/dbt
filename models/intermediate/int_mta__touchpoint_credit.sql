-- int_mta__touchpoint_credit.sql
-- Calculates attribution credit for each touchpoint using multiple methodologies:
-- 1. Last-Touch: 100% to last touchpoint
-- 2. First-Touch: 100% to first touchpoint
-- 3. Linear: Equal credit to all touchpoints
-- 4. Time-Decay: More credit to touchpoints closer to conversion (half-life = 3 days)
-- 5. Position-Based (U-Shaped): 40% first, 40% last, 20% middle
--
-- Grain: One row per device + touchpoint (with credit scores)

{{
    config(
        materialized='incremental',
        unique_key=['DEVICE_ID', 'PLATFORM', 'TOUCHPOINT_TIMESTAMP', 'TOUCHPOINT_TYPE', 'NETWORK_NAME'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        tags=['mta', 'attribution']
    )
}}

-- Configuration parameters
{% set time_decay_half_life_days = 3 %}  -- Half-life in days for time decay
{% set position_first_weight = 0.4 %}    -- Weight for first touch in position-based
{% set position_last_weight = 0.4 %}     -- Weight for last touch in position-based

WITH user_journey AS (
    SELECT *
    FROM {{ ref('int_mta__user_journey') }}
    {% if is_incremental() %}
        WHERE INSTALL_TIMESTAMP >= DATEADD(day, -10, (SELECT MAX(INSTALL_TIMESTAMP) FROM {{ this }}))
    {% endif %}
)

-- Calculate raw time-decay weights
, with_time_decay_raw AS (
    SELECT *
         -- Time decay formula: weight = 2^(-days_to_install / half_life)
         -- This gives weight of 1.0 at install, 0.5 at half-life days before, 0.25 at 2x half-life, etc.
         , POWER(2, -1.0 * DAYS_TO_INSTALL / {{ time_decay_half_life_days }}) AS TIME_DECAY_RAW
         -- Apply type weight (clicks > impressions)
         , POWER(2, -1.0 * DAYS_TO_INSTALL / {{ time_decay_half_life_days }}) * BASE_TYPE_WEIGHT AS TIME_DECAY_WEIGHTED
    FROM user_journey
)

-- Calculate normalized weights per install
, with_normalized_weights AS (
    SELECT *
         -- Sum of weights per install (for normalization)
         , SUM(TIME_DECAY_WEIGHTED) OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
           ) AS TOTAL_TIME_DECAY_WEIGHT
         -- Sum of base type weights (for linear with type weighting)
         , SUM(BASE_TYPE_WEIGHT) OVER (
               PARTITION BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
           ) AS TOTAL_TYPE_WEIGHT
    FROM with_time_decay_raw
)

-- Calculate all attribution credits
, with_credits AS (
    SELECT DEVICE_ID
         , PLATFORM
         , TOUCHPOINT_TYPE
         , NETWORK_NAME
         , AD_PARTNER
         , CAMPAIGN_NAME
         , CAMPAIGN_ID
         , ADGROUP_NAME
         , ADGROUP_ID
         , CREATIVE_NAME
         , TOUCHPOINT_TIMESTAMP
         , INSTALL_TIMESTAMP
         , INSTALL_NETWORK
         , INSTALL_AD_PARTNER
         , INSTALL_CAMPAIGN_ID
         , HOURS_TO_INSTALL
         , DAYS_TO_INSTALL
         , TOUCHPOINT_POSITION
         , TOTAL_TOUCHPOINTS
         , IS_FIRST_TOUCH
         , IS_LAST_TOUCH
         , BASE_TYPE_WEIGHT

         -- =============================================
         -- LAST-TOUCH ATTRIBUTION
         -- 100% credit to the last touchpoint before install
         -- =============================================
         , CASE WHEN IS_LAST_TOUCH = 1 THEN 1.0 ELSE 0.0 END AS CREDIT_LAST_TOUCH

         -- =============================================
         -- FIRST-TOUCH ATTRIBUTION
         -- 100% credit to the first touchpoint in the journey
         -- =============================================
         , CASE WHEN IS_FIRST_TOUCH = 1 THEN 1.0 ELSE 0.0 END AS CREDIT_FIRST_TOUCH

         -- =============================================
         -- LINEAR ATTRIBUTION
         -- Equal credit to all touchpoints (weighted by type)
         -- =============================================
         , BASE_TYPE_WEIGHT / NULLIF(TOTAL_TYPE_WEIGHT, 0) AS CREDIT_LINEAR

         -- =============================================
         -- TIME-DECAY ATTRIBUTION
         -- More credit to touchpoints closer to conversion
         -- Half-life: {{ time_decay_half_life_days }} days
         -- =============================================
         , TIME_DECAY_WEIGHTED / NULLIF(TOTAL_TIME_DECAY_WEIGHT, 0) AS CREDIT_TIME_DECAY

         -- =============================================
         -- POSITION-BASED (U-SHAPED) ATTRIBUTION
         -- {{ position_first_weight * 100 }}% first, {{ position_last_weight * 100 }}% last, remaining split among middle
         -- =============================================
         , CASE
               -- Single touchpoint gets 100%
               WHEN TOTAL_TOUCHPOINTS = 1 THEN 1.0
               -- Two touchpoints: 50/50 (or configured weights if they sum to 1)
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

    FROM with_normalized_weights
)

SELECT *
     -- Add a default/recommended credit column (Time-Decay is our recommendation)
     , CREDIT_TIME_DECAY AS CREDIT_RECOMMENDED
FROM with_credits
