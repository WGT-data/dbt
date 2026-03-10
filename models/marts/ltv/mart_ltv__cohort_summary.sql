-- mart_ltv__cohort_summary.sql
-- Classic cohort LTV summary — works for both iOS and Android
-- Groups users by install cohort and acquisition source, then calculates
-- aggregate LTV, payer rates, and retention across all standard windows.
--
-- Join path:
--   int_user_cohort__attribution (user + attribution dims)
--     → int_user_cohort__metrics (user + LTV windows)
--
-- Grain: One row per INSTALL_DATE + AD_PARTNER + NETWORK_NAME + CAMPAIGN_NAME + PLATFORM

{{
    config(
        materialized='incremental',
        unique_key=['INSTALL_DATE', 'AD_PARTNER', 'NETWORK_NAME', 'CAMPAIGN_NAME', 'PLATFORM'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        tags=['ltv', 'cohort', 'mart']
    )
}}

WITH attribution AS (
    SELECT
        USER_ID
        , PLATFORM
        , AD_PARTNER
        , NETWORK_NAME
        , CAMPAIGN_NAME
        , INSTALL_DATE
    FROM {{ ref('int_user_cohort__attribution') }}
    WHERE USER_ID IS NOT NULL
    {% if is_incremental() %}
        AND INSTALL_DATE >= DATEADD(day, -370, CURRENT_DATE())
    {% endif %}
)

, metrics AS (
    SELECT
        USER_ID
        , PLATFORM
        , INSTALL_DATE

        -- Revenue windows
        , D1_REVENUE
        , D7_REVENUE
        , D30_REVENUE
        , D180_REVENUE
        , D365_REVENUE
        , TOTAL_REVENUE

        -- Purchase revenue
        , D1_PURCHASE_REVENUE
        , D7_PURCHASE_REVENUE
        , D30_PURCHASE_REVENUE
        , D180_PURCHASE_REVENUE
        , D365_PURCHASE_REVENUE
        , TOTAL_PURCHASE_REVENUE

        -- Ad revenue
        , D1_AD_REVENUE
        , D7_AD_REVENUE
        , D30_AD_REVENUE
        , D180_AD_REVENUE
        , D365_AD_REVENUE
        , TOTAL_AD_REVENUE

        -- Payer flags
        , IS_D1_PAYER
        , IS_D7_PAYER
        , IS_D30_PAYER
        , IS_D180_PAYER
        , IS_D365_PAYER
        , IS_PAYER

        -- Retention
        , D1_RETAINED
        , D7_RETAINED
        , D30_RETAINED
        , D180_RETAINED
        , D365_RETAINED

        -- Maturity
        , D1_MATURED
        , D7_MATURED
        , D30_MATURED
        , D180_MATURED
        , D365_MATURED
    FROM {{ ref('int_user_cohort__metrics') }}
    {% if is_incremental() %}
        WHERE INSTALL_DATE >= DATEADD(day, -370, CURRENT_DATE())
    {% endif %}
)

-- Join attribution to metrics
, user_data AS (
    SELECT
        a.INSTALL_DATE
        , a.AD_PARTNER
        , a.NETWORK_NAME
        , a.CAMPAIGN_NAME
        , a.PLATFORM

        -- Revenue windows
        , m.D1_REVENUE
        , m.D7_REVENUE
        , m.D30_REVENUE
        , m.D180_REVENUE
        , m.D365_REVENUE
        , m.TOTAL_REVENUE
        , m.D1_PURCHASE_REVENUE
        , m.D7_PURCHASE_REVENUE
        , m.D30_PURCHASE_REVENUE
        , m.D180_PURCHASE_REVENUE
        , m.D365_PURCHASE_REVENUE
        , m.TOTAL_PURCHASE_REVENUE
        , m.D1_AD_REVENUE
        , m.D7_AD_REVENUE
        , m.D30_AD_REVENUE
        , m.D180_AD_REVENUE
        , m.D365_AD_REVENUE
        , m.TOTAL_AD_REVENUE

        -- Payer flags
        , m.IS_D1_PAYER
        , m.IS_D7_PAYER
        , m.IS_D30_PAYER
        , m.IS_D180_PAYER
        , m.IS_D365_PAYER
        , m.IS_PAYER

        -- Retention
        , m.D1_RETAINED
        , m.D7_RETAINED
        , m.D30_RETAINED
        , m.D180_RETAINED
        , m.D365_RETAINED

        -- Maturity
        , m.D1_MATURED
        , m.D7_MATURED
        , m.D30_MATURED
        , m.D180_MATURED
        , m.D365_MATURED
    FROM attribution a
    INNER JOIN metrics m
        ON a.USER_ID = m.USER_ID
        AND a.PLATFORM = m.PLATFORM
)

-- Aggregate by cohort dimensions
-- COALESCE nullable attribution columns to sentinel values — Snowflake MERGE
-- treats NULL ≠ NULL, which causes duplicate row insertion on incremental runs
SELECT
    INSTALL_DATE
    , DATE_TRUNC('week', INSTALL_DATE) AS INSTALL_WEEK
    , DATE_TRUNC('month', INSTALL_DATE) AS INSTALL_MONTH
    , COALESCE(AD_PARTNER, '__none__') AS AD_PARTNER
    , COALESCE(NETWORK_NAME, '__none__') AS NETWORK_NAME
    , COALESCE(CAMPAIGN_NAME, '__none__') AS CAMPAIGN_NAME
    , PLATFORM

    -- Cohort size
    , COUNT(*) AS COHORT_SIZE

    -- =============================================
    -- TOTAL REVENUE SUMS
    -- =============================================
    , SUM(D1_REVENUE) AS D1_REVENUE
    , SUM(D7_REVENUE) AS D7_REVENUE
    , SUM(D30_REVENUE) AS D30_REVENUE
    , SUM(D180_REVENUE) AS D180_REVENUE
    , SUM(D365_REVENUE) AS D365_REVENUE
    , SUM(TOTAL_REVENUE) AS TOTAL_REVENUE

    -- =============================================
    -- PURCHASE REVENUE SUMS
    -- =============================================
    , SUM(D1_PURCHASE_REVENUE) AS D1_PURCHASE_REVENUE
    , SUM(D7_PURCHASE_REVENUE) AS D7_PURCHASE_REVENUE
    , SUM(D30_PURCHASE_REVENUE) AS D30_PURCHASE_REVENUE
    , SUM(D180_PURCHASE_REVENUE) AS D180_PURCHASE_REVENUE
    , SUM(D365_PURCHASE_REVENUE) AS D365_PURCHASE_REVENUE
    , SUM(TOTAL_PURCHASE_REVENUE) AS TOTAL_PURCHASE_REVENUE

    -- =============================================
    -- AD REVENUE SUMS
    -- =============================================
    , SUM(D1_AD_REVENUE) AS D1_AD_REVENUE
    , SUM(D7_AD_REVENUE) AS D7_AD_REVENUE
    , SUM(D30_AD_REVENUE) AS D30_AD_REVENUE
    , SUM(D180_AD_REVENUE) AS D180_AD_REVENUE
    , SUM(D365_AD_REVENUE) AS D365_AD_REVENUE
    , SUM(TOTAL_AD_REVENUE) AS TOTAL_AD_REVENUE

    -- =============================================
    -- LTV PER USER (NULL when cohort not yet mature)
    -- =============================================
    , IFF(SUM(D1_MATURED) > 0, SUM(D1_REVENUE) / SUM(D1_MATURED), NULL) AS D1_LTV
    , IFF(SUM(D7_MATURED) > 0, SUM(D7_REVENUE) / SUM(D7_MATURED), NULL) AS D7_LTV
    , IFF(SUM(D30_MATURED) > 0, SUM(D30_REVENUE) / SUM(D30_MATURED), NULL) AS D30_LTV
    , IFF(SUM(D180_MATURED) > 0, SUM(D180_REVENUE) / SUM(D180_MATURED), NULL) AS D180_LTV
    , IFF(SUM(D365_MATURED) > 0, SUM(D365_REVENUE) / SUM(D365_MATURED), NULL) AS D365_LTV
    , IFF(COUNT(*) > 0, SUM(TOTAL_REVENUE) / COUNT(*), NULL) AS TOTAL_LTV

    -- =============================================
    -- MATURITY
    -- =============================================
    , SUM(D1_MATURED) AS D1_MATURED_USERS
    , SUM(D7_MATURED) AS D7_MATURED_USERS
    , SUM(D30_MATURED) AS D30_MATURED_USERS
    , SUM(D180_MATURED) AS D180_MATURED_USERS
    , SUM(D365_MATURED) AS D365_MATURED_USERS
    , IFF(COUNT(*) > 0, SUM(D1_MATURED) / COUNT(*), NULL) AS D1_MATURITY_RATE
    , IFF(COUNT(*) > 0, SUM(D7_MATURED) / COUNT(*), NULL) AS D7_MATURITY_RATE
    , IFF(COUNT(*) > 0, SUM(D30_MATURED) / COUNT(*), NULL) AS D30_MATURITY_RATE
    , IFF(COUNT(*) > 0, SUM(D180_MATURED) / COUNT(*), NULL) AS D180_MATURITY_RATE
    , IFF(COUNT(*) > 0, SUM(D365_MATURED) / COUNT(*), NULL) AS D365_MATURITY_RATE

    -- =============================================
    -- PAYER METRICS
    -- =============================================
    , SUM(IS_D1_PAYER) AS D1_PAYERS
    , SUM(IS_D7_PAYER) AS D7_PAYERS
    , SUM(IS_D30_PAYER) AS D30_PAYERS
    , SUM(IS_D180_PAYER) AS D180_PAYERS
    , SUM(IS_D365_PAYER) AS D365_PAYERS
    , SUM(IS_PAYER) AS TOTAL_PAYERS
    , IFF(SUM(D1_MATURED) > 0, SUM(IS_D1_PAYER) / SUM(D1_MATURED), NULL) AS D1_PAYER_RATE
    , IFF(SUM(D7_MATURED) > 0, SUM(IS_D7_PAYER) / SUM(D7_MATURED), NULL) AS D7_PAYER_RATE
    , IFF(SUM(D30_MATURED) > 0, SUM(IS_D30_PAYER) / SUM(D30_MATURED), NULL) AS D30_PAYER_RATE
    , IFF(SUM(D180_MATURED) > 0, SUM(IS_D180_PAYER) / SUM(D180_MATURED), NULL) AS D180_PAYER_RATE
    , IFF(SUM(D365_MATURED) > 0, SUM(IS_D365_PAYER) / SUM(D365_MATURED), NULL) AS D365_PAYER_RATE
    , IFF(COUNT(*) > 0, SUM(IS_PAYER) / COUNT(*), NULL) AS TOTAL_PAYER_RATE

    -- =============================================
    -- RETENTION
    -- =============================================
    , SUM(D1_RETAINED) AS D1_RETAINED_USERS
    , SUM(D7_RETAINED) AS D7_RETAINED_USERS
    , SUM(D30_RETAINED) AS D30_RETAINED_USERS
    , SUM(D180_RETAINED) AS D180_RETAINED_USERS
    , SUM(D365_RETAINED) AS D365_RETAINED_USERS
    , IFF(SUM(D1_MATURED) > 0, SUM(D1_RETAINED) / SUM(D1_MATURED), NULL) AS D1_RETENTION_RATE
    , IFF(SUM(D7_MATURED) > 0, SUM(D7_RETAINED) / SUM(D7_MATURED), NULL) AS D7_RETENTION_RATE
    , IFF(SUM(D30_MATURED) > 0, SUM(D30_RETAINED) / SUM(D30_MATURED), NULL) AS D30_RETENTION_RATE
    , IFF(SUM(D180_MATURED) > 0, SUM(D180_RETAINED) / SUM(D180_MATURED), NULL) AS D180_RETENTION_RATE
    , IFF(SUM(D365_MATURED) > 0, SUM(D365_RETAINED) / SUM(D365_MATURED), NULL) AS D365_RETENTION_RATE

FROM user_data
GROUP BY 1, 2, 3, 4, 5, 6, 7
