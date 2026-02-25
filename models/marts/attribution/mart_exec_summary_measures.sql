-- mart_exec_summary_measures.sql
-- Power BI fact table for Executive Summary Dashboard
--
-- PURPOSE: Exposes the additive base metrics from mart_exec_summary without
-- the pre-computed ratio columns (CPI, ROAS, ARPI, etc.) that produce wrong
-- results when summed across Power BI slicers. All ratio metrics should be
-- created as DAX measures in Power BI (see YAML for formulas).

{{ config(
    materialized='view',
    tags=['mart', 'performance', 'executive', 'powerbi']
) }}

SELECT
    -- Dimensions
    DATE
    , AD_PARTNER
    , NETWORK_NAME
    , CAMPAIGN_NAME
    , CAMPAIGN_ID
    , PLATFORM
    , COUNTRY

    -- Date grains (for granularity selector)
    , WEEK_START
    , MONTH_START
    , QUARTER_START
    , YEAR_START

    -- Spend metrics (additive)
    , COST
    , CLICKS
    , IMPRESSIONS

    -- Install metrics (additive)
    , ADJUST_INSTALLS
    , SKAN_INSTALLS
    , TOTAL_INSTALLS
    , ATTRIBUTION_INSTALLS

    -- Revenue from Adjust API (event-date, additive)
    , TOTAL_REVENUE
    , TOTAL_PURCHASE_REVENUE
    , TOTAL_AD_REVENUE

    -- Cohort revenue (install-date D7/D30, additive)
    , D7_REVENUE
    , D30_REVENUE
    , D7_PURCHASE_REVENUE
    , D30_PURCHASE_REVENUE
    , D7_AD_REVENUE
    , D30_AD_REVENUE

    -- Paying users (additive)
    , TOTAL_PAYING_USERS
    , D7_PAYING_USERS
    , D30_PAYING_USERS

    -- Retention (additive)
    , D1_RETAINED_USERS
    , D7_RETAINED_USERS
    , D30_RETAINED_USERS
    , D1_MATURED_USERS
    , D7_MATURED_USERS
    , D30_MATURED_USERS

FROM {{ ref('mart_exec_summary') }}
