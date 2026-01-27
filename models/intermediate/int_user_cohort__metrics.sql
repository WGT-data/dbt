-- int_user_cohort__metrics.sql
-- Comprehensive user-level cohort metrics with revenue windows and retention flags
-- This model joins Adjust installs with Amplitude user data to calculate:
-- - D7, D30, and lifetime revenue per user
-- - D1, D7, D30 retention flags per user
-- Grain: One row per user_id/platform combination
--
-- INCREMENTAL STRATEGY: Re-process users who:
-- 1. Have new install records (new users)
-- 2. Are within 30-day maturity window (metrics still changing)
-- 3. Have recent revenue/session events (existing user updates)

{{ config(
    materialized='incremental',
    unique_key=['USER_ID', 'PLATFORM'],
    incremental_strategy='merge',
    merge_update_columns=['D7_REVENUE', 'D30_REVENUE', 'TOTAL_REVENUE', 'D7_PURCHASE_REVENUE', 'D30_PURCHASE_REVENUE', 'TOTAL_PURCHASE_REVENUE', 'D7_AD_REVENUE', 'D30_AD_REVENUE', 'TOTAL_AD_REVENUE', 'IS_D7_PAYER', 'IS_D30_PAYER', 'IS_PAYER', 'D1_RETAINED', 'D7_RETAINED', 'D30_RETAINED', 'D1_MATURED', 'D7_MATURED', 'D30_MATURED'],
    tags=['cohort', 'user_metrics'],
    on_schema_change='append_new_columns'
) }}

WITH amplitude_events AS (
    SELECT *
    FROM {{ source('amplitude', 'EVENTS_726530') }}
    {% if is_incremental() %}
        -- Process events from last 35 days to capture D30 windows
        WHERE SERVER_UPLOAD_TIME >= DATEADD(day, -35, CURRENT_TIMESTAMP())
    {% endif %}
)

-- Get first install per user from device mapping
, user_installs AS (
    SELECT
        dm.AMPLITUDE_USER_ID AS USER_ID
        , dm.PLATFORM
        , dm.ADJUST_DEVICE_ID
        , dm.FIRST_SEEN_AT AS INSTALL_TIME
        , DATE(dm.FIRST_SEEN_AT) AS INSTALL_DATE
    FROM {{ ref('int_adjust_amplitude__device_mapping') }} dm
    WHERE dm.AMPLITUDE_USER_ID IS NOT NULL
)

-- Dedupe to one row per user/platform, taking earliest install
, user_first_install AS (
    SELECT
        USER_ID
        , PLATFORM
        , MIN(INSTALL_TIME) AS INSTALL_TIME
        , MIN(INSTALL_DATE) AS INSTALL_DATE
    FROM user_installs
    GROUP BY 1, 2
)

-- Identify users that need to be processed
, users_to_process AS (
    SELECT USER_ID, PLATFORM, INSTALL_TIME, INSTALL_DATE
    FROM user_first_install
    {% if is_incremental() %}
        -- Re-process users within D30 maturity window (metrics still evolving)
        WHERE INSTALL_DATE >= DATEADD(day, -35, CURRENT_DATE())
    {% endif %}
)

-- Revenue events with parsed revenue value
, revenue_events AS (
    SELECT
        USER_ID
        , EVENT_TIME
        , PLATFORM
        , COALESCE(
            TRY_CAST(EVENT_PROPERTIES:"$revenue"::STRING AS FLOAT),
            0
        ) AS REVENUE
        , COALESCE(EVENT_PROPERTIES:"tu"::STRING, 'unknown') AS REVENUE_TYPE
    FROM amplitude_events
    WHERE EVENT_TYPE = 'Revenue'
    AND EVENT_PROPERTIES:"$revenue" IS NOT NULL
)

-- Session events for retention calculation
-- Using ClientOpened instead of session_start because session_start has USER_ID for only ~13% of events
-- ClientOpened has USER_ID for 100% of events and represents app opens
, session_events AS (
    SELECT
        USER_ID
        , PLATFORM
        , DATE(EVENT_TIME) AS SESSION_DATE
    FROM amplitude_events
    WHERE EVENT_TYPE = 'ClientOpened'
    GROUP BY 1, 2, 3
)

-- Calculate revenue metrics per user
, user_revenue AS (
    SELECT
        u.USER_ID
        , u.PLATFORM
        , u.INSTALL_DATE
        , u.INSTALL_TIME

        -- D7 Total Revenue
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 7, u.INSTALL_TIME)
            THEN r.REVENUE
            ELSE 0
        END) AS D7_REVENUE

        -- D30 Total Revenue
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 30, u.INSTALL_TIME)
            THEN r.REVENUE
            ELSE 0
        END) AS D30_REVENUE

        -- Lifetime Total Revenue
        , SUM(COALESCE(r.REVENUE, 0)) AS TOTAL_REVENUE

        -- Purchase Revenue (IAP, tu = 'direct')
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 7, u.INSTALL_TIME)
                AND r.REVENUE_TYPE = 'direct'
            THEN r.REVENUE
            ELSE 0
        END) AS D7_PURCHASE_REVENUE

        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 30, u.INSTALL_TIME)
                AND r.REVENUE_TYPE = 'direct'
            THEN r.REVENUE
            ELSE 0
        END) AS D30_PURCHASE_REVENUE

        , SUM(CASE
            WHEN r.REVENUE_TYPE = 'direct'
            THEN r.REVENUE
            ELSE 0
        END) AS TOTAL_PURCHASE_REVENUE

        -- Ad Revenue (tu = 'indirect')
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 7, u.INSTALL_TIME)
                AND r.REVENUE_TYPE = 'indirect'
            THEN r.REVENUE
            ELSE 0
        END) AS D7_AD_REVENUE

        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 30, u.INSTALL_TIME)
                AND r.REVENUE_TYPE = 'indirect'
            THEN r.REVENUE
            ELSE 0
        END) AS D30_AD_REVENUE

        , SUM(CASE
            WHEN r.REVENUE_TYPE = 'indirect'
            THEN r.REVENUE
            ELSE 0
        END) AS TOTAL_AD_REVENUE

        -- Payer flags (based on purchase revenue only)
        , MAX(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 7, u.INSTALL_TIME)
                AND r.REVENUE_TYPE = 'direct'
                AND r.REVENUE > 0
            THEN 1 ELSE 0
        END) AS IS_D7_PAYER

        , MAX(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 30, u.INSTALL_TIME)
                AND r.REVENUE_TYPE = 'direct'
                AND r.REVENUE > 0
            THEN 1 ELSE 0
        END) AS IS_D30_PAYER

        , MAX(CASE
            WHEN r.REVENUE_TYPE = 'direct' AND r.REVENUE > 0
            THEN 1 ELSE 0
        END) AS IS_PAYER

    FROM users_to_process u
    LEFT JOIN revenue_events r
        ON u.USER_ID = r.USER_ID
        AND LOWER(u.PLATFORM) = LOWER(r.PLATFORM)
        AND r.EVENT_TIME >= u.INSTALL_TIME
    GROUP BY 1, 2, 3, 4
)

-- Calculate retention metrics per user
, user_retention AS (
    SELECT
        u.USER_ID
        , u.PLATFORM
        , u.INSTALL_DATE

        -- D1 Retention
        , MAX(CASE
            WHEN s.SESSION_DATE = DATEADD(day, 1, u.INSTALL_DATE)
            THEN 1 ELSE 0
        END) AS D1_RETAINED

        -- D7 Retention
        , MAX(CASE
            WHEN s.SESSION_DATE = DATEADD(day, 7, u.INSTALL_DATE)
            THEN 1 ELSE 0
        END) AS D7_RETAINED

        -- D30 Retention
        , MAX(CASE
            WHEN s.SESSION_DATE = DATEADD(day, 30, u.INSTALL_DATE)
            THEN 1 ELSE 0
        END) AS D30_RETAINED

        -- Maturity flags
        , CASE WHEN DATEDIFF(day, u.INSTALL_DATE, CURRENT_DATE()) >= 1 THEN 1 ELSE 0 END AS D1_MATURED
        , CASE WHEN DATEDIFF(day, u.INSTALL_DATE, CURRENT_DATE()) >= 7 THEN 1 ELSE 0 END AS D7_MATURED
        , CASE WHEN DATEDIFF(day, u.INSTALL_DATE, CURRENT_DATE()) >= 30 THEN 1 ELSE 0 END AS D30_MATURED

    FROM users_to_process u
    LEFT JOIN session_events s
        ON u.USER_ID = s.USER_ID
        AND LOWER(u.PLATFORM) = LOWER(s.PLATFORM)
        AND s.SESSION_DATE > u.INSTALL_DATE
    GROUP BY 1, 2, 3
)

-- Final join
SELECT
    r.USER_ID
    , r.PLATFORM
    , r.INSTALL_DATE
    , r.INSTALL_TIME

    -- Total Revenue metrics
    , r.D7_REVENUE
    , r.D30_REVENUE
    , r.TOTAL_REVENUE

    -- Purchase Revenue (IAP)
    , r.D7_PURCHASE_REVENUE
    , r.D30_PURCHASE_REVENUE
    , r.TOTAL_PURCHASE_REVENUE

    -- Ad Revenue
    , r.D7_AD_REVENUE
    , r.D30_AD_REVENUE
    , r.TOTAL_AD_REVENUE

    -- Payer flags
    , r.IS_D7_PAYER
    , r.IS_D30_PAYER
    , r.IS_PAYER

    -- Retention flags
    , COALESCE(t.D1_RETAINED, 0) AS D1_RETAINED
    , COALESCE(t.D7_RETAINED, 0) AS D7_RETAINED
    , COALESCE(t.D30_RETAINED, 0) AS D30_RETAINED
    , COALESCE(t.D1_MATURED, 0) AS D1_MATURED
    , COALESCE(t.D7_MATURED, 0) AS D7_MATURED
    , COALESCE(t.D30_MATURED, 0) AS D30_MATURED

FROM user_revenue r
LEFT JOIN user_retention t
    ON r.USER_ID = t.USER_ID
    AND r.PLATFORM = t.PLATFORM
