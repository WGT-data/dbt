-- ============================================================================
-- LIMITATION NOTICE (documented Phase 3, 2026-02)
--
-- This model is part of the Multi-Touch Attribution (MTA) pipeline.
-- Phase 2 audit (Feb 2026) found that MTA has structural coverage limitations:
--   - Android: 0% device match rate (Amplitude SDK uses random UUID, not GPS_ADID)
--   - iOS IDFA: 7.37% availability (Apple ATT framework)
--   - SANs (Meta, Google, Apple, TikTok): 0% touchpoint data (never shared)
--
-- This model is PRESERVED for iOS tactical analysis only.
-- For strategic budget allocation, use MMM models in marts/mmm/.
--
-- To fix Android: Amplitude SDK must be configured with useAdvertisingIdForDeviceId()
-- See: .planning/phases/03-device-id-normalization-fix/mta-limitations.md
-- ============================================================================

-- int_ltv__device_revenue.sql
-- Bridge device-level installs to user-level revenue via device mapping.
-- Foundation for MTA-attributed LTV models.
--
-- Join path:
--   v_stg_adjust__installs (device + attribution)
--     → int_adjust_amplitude__device_mapping (device → user_id)
--     → WGT.EVENTS.REVENUE (user_id → revenue events)
--
-- Grain: One row per DEVICE_ID + PLATFORM

{{
    config(
        materialized='incremental',
        unique_key=['DEVICE_ID', 'PLATFORM'],
        incremental_strategy='merge',
        merge_update_columns=[
            'AMPLITUDE_USER_ID', 'HAS_USER_MAPPING',
            'D1_REVENUE', 'D7_REVENUE', 'D30_REVENUE', 'D180_REVENUE', 'D365_REVENUE', 'TOTAL_REVENUE',
            'D1_PURCHASE_REVENUE', 'D7_PURCHASE_REVENUE', 'D30_PURCHASE_REVENUE', 'D180_PURCHASE_REVENUE', 'D365_PURCHASE_REVENUE', 'TOTAL_PURCHASE_REVENUE',
            'D1_AD_REVENUE', 'D7_AD_REVENUE', 'D30_AD_REVENUE', 'D180_AD_REVENUE', 'D365_AD_REVENUE', 'TOTAL_AD_REVENUE',
            'D1_MATURED', 'D7_MATURED', 'D30_MATURED', 'D180_MATURED', 'D365_MATURED'
        ],
        on_schema_change='append_new_columns',
        tags=['ltv', 'device']
    )
}}

-- Device installs with attribution from Adjust
WITH device_installs AS (
    SELECT
        DEVICE_ID
        , PLATFORM
        , INSTALL_TIMESTAMP
        , CAST(INSTALL_TIMESTAMP AS DATE) AS INSTALL_DATE
    FROM {{ ref('v_stg_adjust__installs') }}
    WHERE DEVICE_ID IS NOT NULL
    {% if is_incremental() %}
        AND INSTALL_TIMESTAMP >= DATEADD(day, -370, CURRENT_TIMESTAMP())
    {% endif %}
)

-- Map devices to Amplitude user IDs
, device_mapping AS (
    SELECT
        ADJUST_DEVICE_ID
        , AMPLITUDE_USER_ID
        , PLATFORM
    FROM {{ ref('int_adjust_amplitude__device_mapping') }}
)

-- Devices with user mapping
, devices_with_users AS (
    SELECT
        d.DEVICE_ID
        , d.PLATFORM
        , d.INSTALL_TIMESTAMP
        , d.INSTALL_DATE
        , dm.AMPLITUDE_USER_ID
        , dm.AMPLITUDE_USER_ID IS NOT NULL AS HAS_USER_MAPPING
    FROM device_installs d
    LEFT JOIN device_mapping dm
        ON d.DEVICE_ID = dm.ADJUST_DEVICE_ID
        AND d.PLATFORM = dm.PLATFORM
)

-- Revenue events
, revenue_events AS (
    SELECT
        USERID AS USER_ID
        , EVENTTIME AS EVENT_TIME
        , PLATFORM
        , COALESCE(REVENUE, 0) AS REVENUE
        , COALESCE(REVENUETYPE, 'unknown') AS REVENUE_TYPE
    FROM {{ source('events', 'REVENUE') }}
    WHERE REVENUE IS NOT NULL
        AND PLATFORM IN ('iOS', 'Android')
    {% if is_incremental() %}
        AND EVENTTIME >= DATEADD(day, -370, CURRENT_TIMESTAMP())
    {% endif %}
)

-- Calculate revenue per device across LTV windows
, device_revenue AS (
    SELECT
        d.DEVICE_ID
        , d.PLATFORM
        , d.INSTALL_TIMESTAMP
        , d.INSTALL_DATE
        , d.AMPLITUDE_USER_ID
        , d.HAS_USER_MAPPING

        -- D1 Revenue
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 1, d.INSTALL_TIMESTAMP)
            THEN r.REVENUE ELSE 0
        END) AS D1_REVENUE
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 1, d.INSTALL_TIMESTAMP) AND r.REVENUE_TYPE = 'direct'
            THEN r.REVENUE ELSE 0
        END) AS D1_PURCHASE_REVENUE
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 1, d.INSTALL_TIMESTAMP) AND r.REVENUE_TYPE = 'indirect'
            THEN r.REVENUE ELSE 0
        END) AS D1_AD_REVENUE

        -- D7 Revenue
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 7, d.INSTALL_TIMESTAMP)
            THEN r.REVENUE ELSE 0
        END) AS D7_REVENUE
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 7, d.INSTALL_TIMESTAMP) AND r.REVENUE_TYPE = 'direct'
            THEN r.REVENUE ELSE 0
        END) AS D7_PURCHASE_REVENUE
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 7, d.INSTALL_TIMESTAMP) AND r.REVENUE_TYPE = 'indirect'
            THEN r.REVENUE ELSE 0
        END) AS D7_AD_REVENUE

        -- D30 Revenue
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 30, d.INSTALL_TIMESTAMP)
            THEN r.REVENUE ELSE 0
        END) AS D30_REVENUE
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 30, d.INSTALL_TIMESTAMP) AND r.REVENUE_TYPE = 'direct'
            THEN r.REVENUE ELSE 0
        END) AS D30_PURCHASE_REVENUE
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 30, d.INSTALL_TIMESTAMP) AND r.REVENUE_TYPE = 'indirect'
            THEN r.REVENUE ELSE 0
        END) AS D30_AD_REVENUE

        -- D180 Revenue
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 180, d.INSTALL_TIMESTAMP)
            THEN r.REVENUE ELSE 0
        END) AS D180_REVENUE
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 180, d.INSTALL_TIMESTAMP) AND r.REVENUE_TYPE = 'direct'
            THEN r.REVENUE ELSE 0
        END) AS D180_PURCHASE_REVENUE
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 180, d.INSTALL_TIMESTAMP) AND r.REVENUE_TYPE = 'indirect'
            THEN r.REVENUE ELSE 0
        END) AS D180_AD_REVENUE

        -- D365 Revenue
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 365, d.INSTALL_TIMESTAMP)
            THEN r.REVENUE ELSE 0
        END) AS D365_REVENUE
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 365, d.INSTALL_TIMESTAMP) AND r.REVENUE_TYPE = 'direct'
            THEN r.REVENUE ELSE 0
        END) AS D365_PURCHASE_REVENUE
        , SUM(CASE
            WHEN r.EVENT_TIME <= DATEADD(day, 365, d.INSTALL_TIMESTAMP) AND r.REVENUE_TYPE = 'indirect'
            THEN r.REVENUE ELSE 0
        END) AS D365_AD_REVENUE

        -- Total Revenue
        , SUM(COALESCE(r.REVENUE, 0)) AS TOTAL_REVENUE
        , SUM(CASE WHEN r.REVENUE_TYPE = 'direct' THEN r.REVENUE ELSE 0 END) AS TOTAL_PURCHASE_REVENUE
        , SUM(CASE WHEN r.REVENUE_TYPE = 'indirect' THEN r.REVENUE ELSE 0 END) AS TOTAL_AD_REVENUE

    FROM devices_with_users d
    LEFT JOIN revenue_events r
        ON d.AMPLITUDE_USER_ID = r.USER_ID
        AND LOWER(d.PLATFORM) = LOWER(r.PLATFORM)
        AND r.EVENT_TIME >= d.INSTALL_TIMESTAMP
    GROUP BY 1, 2, 3, 4, 5, 6
)

SELECT
    DEVICE_ID
    , PLATFORM
    , INSTALL_TIMESTAMP
    , INSTALL_DATE
    , AMPLITUDE_USER_ID
    , HAS_USER_MAPPING

    -- Revenue windows
    , D1_REVENUE
    , D1_PURCHASE_REVENUE
    , D1_AD_REVENUE
    , D7_REVENUE
    , D7_PURCHASE_REVENUE
    , D7_AD_REVENUE
    , D30_REVENUE
    , D30_PURCHASE_REVENUE
    , D30_AD_REVENUE
    , D180_REVENUE
    , D180_PURCHASE_REVENUE
    , D180_AD_REVENUE
    , D365_REVENUE
    , D365_PURCHASE_REVENUE
    , D365_AD_REVENUE
    , TOTAL_REVENUE
    , TOTAL_PURCHASE_REVENUE
    , TOTAL_AD_REVENUE

    -- Maturity flags
    , CASE WHEN DATEDIFF(day, INSTALL_DATE, CURRENT_DATE()) >= 1 THEN 1 ELSE 0 END AS D1_MATURED
    , CASE WHEN DATEDIFF(day, INSTALL_DATE, CURRENT_DATE()) >= 7 THEN 1 ELSE 0 END AS D7_MATURED
    , CASE WHEN DATEDIFF(day, INSTALL_DATE, CURRENT_DATE()) >= 30 THEN 1 ELSE 0 END AS D30_MATURED
    , CASE WHEN DATEDIFF(day, INSTALL_DATE, CURRENT_DATE()) >= 180 THEN 1 ELSE 0 END AS D180_MATURED
    , CASE WHEN DATEDIFF(day, INSTALL_DATE, CURRENT_DATE()) >= 365 THEN 1 ELSE 0 END AS D365_MATURED

FROM device_revenue
