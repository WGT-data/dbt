-- rpt__mta_vs_adjust_installs.sql
-- Side-by-side comparison of MTA-attributed installs vs Adjust's reported installs
--
-- PURPOSE: Understand where multi-touch attribution redistributes install credit
-- compared to Adjust's built-in last-touch attribution, and quantify the MTA
-- coverage gap per network.
--
-- THREE INSTALL PERSPECTIVES:
--   1. ADJUST_REPORTED_INSTALLS — Adjust API daily report (what the dashboard shows)
--   2. ADJUST_S3_INSTALLS — Device-level count from raw S3 install data
--   3. MTA_*_INSTALLS — MTA fractional installs (5 attribution models)
--
-- KEY COMPARISON METRICS:
--   - MTA_COVERAGE_PCT: What fraction of Adjust's installs can MTA see?
--     ~0% for SANs (Meta, Google, TikTok, Apple) — they don't share touchpoint data
--     >0% for programmatic (Moloco, Smadex, etc.) — they do share touchpoint data
--   - MTA_CREDIT_SHIFT_PCT: How much does time-decay redistribute vs last-touch?
--     Positive = network gains credit from multi-touch analysis
--     Negative = network loses credit (was over-credited by last-touch)
--
-- DATA SOURCES: All Adjust — no Amplitude dependency
-- GRAIN: AD_PARTNER + PLATFORM + DATE (network level)

{{ config(
    materialized='table',
    tags=['mart', 'attribution', 'mta', 'comparison']
) }}

-- =============================================
-- PARTNER NAME MAPPING
-- =============================================
WITH partner_map AS (
    SELECT DISTINCT
        ADJUST_NETWORK_NAME AS PARTNER_NAME
        , AD_PARTNER
    FROM {{ ref('network_mapping') }}
    WHERE AD_PARTNER IS NOT NULL
)

-- =============================================
-- ADJUST API REPORTED INSTALLS
-- What Adjust's dashboard/API reports (their last-touch attribution)
-- =============================================
, adjust_reported AS (
    SELECT
        s.DATE
        , COALESCE(pm.AD_PARTNER, s.PARTNER_NAME) AS AD_PARTNER
        , s.PLATFORM
        , SUM(s.INSTALLS) AS ADJUST_REPORTED_INSTALLS
        , SUM(s.NETWORK_COST) AS COST
        , SUM(s.CLICKS) AS CLICKS
        , SUM(s.IMPRESSIONS) AS IMPRESSIONS
    FROM {{ ref('stg_adjust__report_daily') }} s
    LEFT JOIN partner_map pm ON s.PARTNER_NAME = pm.PARTNER_NAME
    WHERE s.DATE IS NOT NULL
    GROUP BY 1, 2, 3
)

-- =============================================
-- ADJUST S3 DEVICE-LEVEL INSTALLS
-- Raw device count from S3 install events (Adjust's attribution at device level)
-- =============================================
, adjust_s3_installs AS (
    SELECT
        DATE(INSTALL_TIMESTAMP) AS DATE
        , AD_PARTNER
        , PLATFORM
        , COUNT(DISTINCT DEVICE_ID) AS ADJUST_S3_INSTALLS
    FROM {{ ref('v_stg_adjust__installs') }}
    WHERE INSTALL_TIMESTAMP IS NOT NULL
    GROUP BY 1, 2, 3
)

-- =============================================
-- MTA-ATTRIBUTED INSTALLS
-- Fractional installs from touchpoint credit pipeline (5 models)
-- Grouped by TOUCHPOINT's AD_PARTNER — MTA redistributes credit
-- =============================================
, mta_attributed AS (
    SELECT
        CAST(INSTALL_TIMESTAMP AS DATE) AS DATE
        , AD_PARTNER
        , PLATFORM
        , SUM(CREDIT_LAST_TOUCH) AS MTA_LAST_TOUCH_INSTALLS
        , SUM(CREDIT_FIRST_TOUCH) AS MTA_FIRST_TOUCH_INSTALLS
        , SUM(CREDIT_LINEAR) AS MTA_LINEAR_INSTALLS
        , SUM(CREDIT_TIME_DECAY) AS MTA_TIME_DECAY_INSTALLS
        , SUM(CREDIT_POSITION_BASED) AS MTA_POSITION_BASED_INSTALLS
        , COUNT(DISTINCT DEVICE_ID) AS MTA_UNIQUE_DEVICES
    FROM {{ ref('int_mta__touchpoint_credit') }}
    WHERE INSTALL_TIMESTAMP IS NOT NULL
    GROUP BY 1, 2, 3
)

-- =============================================
-- COMBINE ALL THREE PERSPECTIVES
-- =============================================
, combined AS (
    SELECT
        COALESCE(ar.DATE, s3.DATE, mta.DATE) AS DATE
        , COALESCE(ar.AD_PARTNER, s3.AD_PARTNER, mta.AD_PARTNER) AS AD_PARTNER
        , COALESCE(ar.PLATFORM, s3.PLATFORM, mta.PLATFORM) AS PLATFORM

        -- Spend & engagement (from Adjust API report)
        , COALESCE(ar.COST, 0) AS COST
        , COALESCE(ar.CLICKS, 0) AS CLICKS
        , COALESCE(ar.IMPRESSIONS, 0) AS IMPRESSIONS

        -- Adjust's reported installs
        , COALESCE(ar.ADJUST_REPORTED_INSTALLS, 0) AS ADJUST_REPORTED_INSTALLS
        , COALESCE(s3.ADJUST_S3_INSTALLS, 0) AS ADJUST_S3_INSTALLS

        -- MTA installs (5 models)
        , COALESCE(mta.MTA_LAST_TOUCH_INSTALLS, 0) AS MTA_LAST_TOUCH_INSTALLS
        , COALESCE(mta.MTA_FIRST_TOUCH_INSTALLS, 0) AS MTA_FIRST_TOUCH_INSTALLS
        , COALESCE(mta.MTA_LINEAR_INSTALLS, 0) AS MTA_LINEAR_INSTALLS
        , COALESCE(mta.MTA_TIME_DECAY_INSTALLS, 0) AS MTA_TIME_DECAY_INSTALLS
        , COALESCE(mta.MTA_POSITION_BASED_INSTALLS, 0) AS MTA_POSITION_BASED_INSTALLS
        , COALESCE(mta.MTA_UNIQUE_DEVICES, 0) AS MTA_UNIQUE_DEVICES

    FROM adjust_reported ar
    FULL OUTER JOIN adjust_s3_installs s3
        ON ar.DATE = s3.DATE
        AND ar.AD_PARTNER = s3.AD_PARTNER
        AND ar.PLATFORM = s3.PLATFORM
    FULL OUTER JOIN mta_attributed mta
        ON COALESCE(ar.DATE, s3.DATE) = mta.DATE
        AND COALESCE(ar.AD_PARTNER, s3.AD_PARTNER) = mta.AD_PARTNER
        AND COALESCE(ar.PLATFORM, s3.PLATFORM) = mta.PLATFORM
)

-- =============================================
-- FINAL OUTPUT WITH COMPARISON METRICS
-- =============================================
SELECT
    DATE
    , AD_PARTNER
    , PLATFORM

    -- Spend & engagement
    , COST
    , CLICKS
    , IMPRESSIONS

    -- Three install perspectives
    , ADJUST_REPORTED_INSTALLS
    , ADJUST_S3_INSTALLS
    , MTA_LAST_TOUCH_INSTALLS
    , MTA_FIRST_TOUCH_INSTALLS
    , MTA_LINEAR_INSTALLS
    , MTA_TIME_DECAY_INSTALLS
    , MTA_POSITION_BASED_INSTALLS
    , MTA_UNIQUE_DEVICES

    -- =============================================
    -- COVERAGE: What % of Adjust's installs can MTA see?
    -- Near 0% for SANs, >0% for programmatic
    -- =============================================
    , MTA_TIME_DECAY_INSTALLS / NULLIF(ADJUST_REPORTED_INSTALLS, 0)
        AS MTA_COVERAGE_PCT

    -- =============================================
    -- CREDIT SHIFT: How much does time-decay redistribute vs last-touch?
    -- Positive = network gains credit from multi-touch
    -- Negative = network was over-credited by last-touch
    -- =============================================
    , (MTA_TIME_DECAY_INSTALLS - MTA_LAST_TOUCH_INSTALLS)
        / NULLIF(MTA_LAST_TOUCH_INSTALLS, 0)
        AS MTA_CREDIT_SHIFT_PCT

    -- =============================================
    -- LAST-TOUCH DELTA: Does MTA last-touch agree with Adjust?
    -- Should be close when both have the same data
    -- =============================================
    , MTA_LAST_TOUCH_INSTALLS - ADJUST_REPORTED_INSTALLS
        AS MTA_VS_ADJUST_LAST_TOUCH_DELTA

    -- =============================================
    -- CPI COMPARISON
    -- =============================================
    , COST / NULLIF(ADJUST_REPORTED_INSTALLS, 0) AS ADJUST_CPI
    , COST / NULLIF(MTA_TIME_DECAY_INSTALLS, 0) AS MTA_TIME_DECAY_CPI

    -- =============================================
    -- SAN FLAG: Does this network share device-level touchpoint data?
    -- SANs (Meta, Google, TikTok, Apple) do not — MTA cannot run
    -- =============================================
    , CASE
        WHEN AD_PARTNER IN ('Meta', 'Google', 'TikTok', 'Apple')
            THEN FALSE
        ELSE TRUE
      END AS HAS_TOUCHPOINT_DATA

FROM combined
WHERE DATE IS NOT NULL
