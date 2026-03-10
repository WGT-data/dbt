-- mart_attribution__combined.sql
-- Combined web + mobile multi-touch attribution mart
--
-- PURPOSE: Unify mobile MTA (app installs) and web MTA (registrations) into a
-- single view for cross-channel attribution analysis. Uses a stacked UNION ALL
-- approach since the two pipelines use different identity systems (Adjust device
-- ID for mobile vs Amplitude browser ID for web) and cannot be joined at user level.
--
-- IMPORTANT: Conversions are NOT deduplicated between web and mobile.
-- A user who registers on web AND installs mobile will be counted in both.
-- This is intentional — the mart shows each channel's attributed conversions
-- in their respective pipeline.
--
-- Mobile: installs attributed via Adjust S3 touchpoints
-- Web: registrations attributed via Amplitude browser sessions
--
-- Both use the same 5 MTA models with identical methodology:
--   - Last-Touch, First-Touch, Linear, Time-Decay (3-day half-life), Position-Based
--
-- Grain: DATE + ACQUISITION_TYPE + CHANNEL + CAMPAIGN + PLATFORM

{{ config(
    materialized='table',
    tags=['mart', 'attribution', 'combined']
) }}

-- =============================================
-- MOBILE MTA — app installs + revenue
-- =============================================
WITH mobile_mta AS (
    SELECT
        DATE
        , 'mobile_install' AS ACQUISITION_TYPE
        , AD_PARTNER AS CHANNEL
        , CAMPAIGN_NAME AS CAMPAIGN
        , PLATFORM
        , COST
        , IMPRESSIONS
        , CLICKS

        -- Conversions (fractional installs by model)
        , INSTALLS_LAST_TOUCH AS CONVERSIONS_LAST_TOUCH
        , INSTALLS_FIRST_TOUCH AS CONVERSIONS_FIRST_TOUCH
        , INSTALLS_LINEAR AS CONVERSIONS_LINEAR
        , INSTALLS_TIME_DECAY AS CONVERSIONS_TIME_DECAY
        , INSTALLS_POSITION_BASED AS CONVERSIONS_POSITION_BASED
        , INSTALLS_RECOMMENDED AS CONVERSIONS_RECOMMENDED

        -- D7 Revenue by model
        , D7_REVENUE_LAST_TOUCH
        , D7_REVENUE_FIRST_TOUCH
        , D7_REVENUE_LINEAR
        , D7_REVENUE_TIME_DECAY
        , D7_REVENUE_POSITION_BASED
        , D7_REVENUE_RECOMMENDED

        -- D30 Revenue by model
        , D30_REVENUE_LAST_TOUCH
        , D30_REVENUE_FIRST_TOUCH
        , D30_REVENUE_LINEAR
        , D30_REVENUE_TIME_DECAY
        , D30_REVENUE_POSITION_BASED
        , D30_REVENUE_RECOMMENDED

        -- Total Revenue by model
        , TOTAL_REVENUE_LAST_TOUCH
        , TOTAL_REVENUE_FIRST_TOUCH
        , TOTAL_REVENUE_LINEAR
        , TOTAL_REVENUE_TIME_DECAY
        , TOTAL_REVENUE_POSITION_BASED
        , TOTAL_REVENUE_RECOMMENDED

        , UNIQUE_DEVICES AS UNIQUE_USERS

    FROM {{ ref('mta__campaign_performance') }}
)

-- =============================================
-- WEB MTA — registrations + revenue
-- =============================================
, web_mta AS (
    SELECT
        DATE
        , 'web_registration' AS ACQUISITION_TYPE
        , TRAFFIC_SOURCE AS CHANNEL
        , TRAFFIC_CAMPAIGN AS CAMPAIGN
        , 'Web' AS PLATFORM
        , 0 AS COST  -- web spend not tracked at campaign level in this pipeline
        , 0 AS IMPRESSIONS
        , 0 AS CLICKS

        -- Conversions (fractional registrations by model)
        , REGS_LAST_TOUCH AS CONVERSIONS_LAST_TOUCH
        , REGS_FIRST_TOUCH AS CONVERSIONS_FIRST_TOUCH
        , REGS_LINEAR AS CONVERSIONS_LINEAR
        , REGS_TIME_DECAY AS CONVERSIONS_TIME_DECAY
        , REGS_POSITION_BASED AS CONVERSIONS_POSITION_BASED
        , REGS_TIME_DECAY AS CONVERSIONS_RECOMMENDED  -- web has no RECOMMENDED; use time-decay

        -- D7 Revenue by model
        , D7_REVENUE_LAST_TOUCH
        , D7_REVENUE_FIRST_TOUCH
        , D7_REVENUE_LINEAR
        , D7_REVENUE_TIME_DECAY
        , D7_REVENUE_POSITION_BASED
        , D7_REVENUE_TIME_DECAY AS D7_REVENUE_RECOMMENDED

        -- D30 Revenue by model
        , D30_REVENUE_LAST_TOUCH
        , D30_REVENUE_FIRST_TOUCH
        , D30_REVENUE_LINEAR
        , D30_REVENUE_TIME_DECAY
        , D30_REVENUE_POSITION_BASED
        , D30_REVENUE_TIME_DECAY AS D30_REVENUE_RECOMMENDED

        -- Total Revenue by model
        , TOTAL_REVENUE_LAST_TOUCH
        , TOTAL_REVENUE_FIRST_TOUCH
        , TOTAL_REVENUE_LINEAR
        , TOTAL_REVENUE_TIME_DECAY
        , TOTAL_REVENUE_POSITION_BASED
        , TOTAL_REVENUE_TIME_DECAY AS TOTAL_REVENUE_RECOMMENDED

        , UNIQUE_REGISTRANTS AS UNIQUE_USERS

    FROM {{ ref('rpt__web_attribution') }}
)

-- =============================================
-- STACK BOTH
-- =============================================
, combined AS (
    SELECT * FROM mobile_mta
    UNION ALL
    SELECT * FROM web_mta
)

SELECT
    DATE
    , ACQUISITION_TYPE
    , CHANNEL
    , CAMPAIGN
    , PLATFORM

    -- Spend (mobile only)
    , COST
    , IMPRESSIONS
    , CLICKS

    -- Conversions by model (installs for mobile, registrations for web)
    , CONVERSIONS_LAST_TOUCH
    , CONVERSIONS_FIRST_TOUCH
    , CONVERSIONS_LINEAR
    , CONVERSIONS_TIME_DECAY
    , CONVERSIONS_POSITION_BASED
    , CONVERSIONS_RECOMMENDED

    -- D7 Revenue by model
    , D7_REVENUE_LAST_TOUCH
    , D7_REVENUE_FIRST_TOUCH
    , D7_REVENUE_LINEAR
    , D7_REVENUE_TIME_DECAY
    , D7_REVENUE_POSITION_BASED
    , D7_REVENUE_RECOMMENDED

    -- D30 Revenue by model
    , D30_REVENUE_LAST_TOUCH
    , D30_REVENUE_FIRST_TOUCH
    , D30_REVENUE_LINEAR
    , D30_REVENUE_TIME_DECAY
    , D30_REVENUE_POSITION_BASED
    , D30_REVENUE_RECOMMENDED

    -- Total Revenue by model
    , TOTAL_REVENUE_LAST_TOUCH
    , TOTAL_REVENUE_FIRST_TOUCH
    , TOTAL_REVENUE_LINEAR
    , TOTAL_REVENUE_TIME_DECAY
    , TOTAL_REVENUE_POSITION_BASED
    , TOTAL_REVENUE_RECOMMENDED

    , UNIQUE_USERS

    -- CPI (mobile only)
    , CASE WHEN CONVERSIONS_RECOMMENDED > 0 AND COST > 0
        THEN COST / CONVERSIONS_RECOMMENDED
        ELSE NULL END AS CPI_RECOMMENDED

    -- ROAS by model (recommended)
    , CASE WHEN COST > 0
        THEN D7_REVENUE_RECOMMENDED / COST
        ELSE NULL END AS D7_ROAS_RECOMMENDED
    , CASE WHEN COST > 0
        THEN D30_REVENUE_RECOMMENDED / COST
        ELSE NULL END AS D30_ROAS_RECOMMENDED
    , CASE WHEN COST > 0
        THEN TOTAL_REVENUE_RECOMMENDED / COST
        ELSE NULL END AS TOTAL_ROAS_RECOMMENDED

FROM combined
WHERE DATE IS NOT NULL
