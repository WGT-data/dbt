-- mart_daily_overview_by_platform_measures.sql
-- Power BI Measures Scaffold for Daily Overview by Platform
--
-- PURPOSE: Single-row anchor table for Power BI DAX measures.
-- Attach all DAX measures to this table so they appear under a clean
-- "Measures" group in the Power BI Fields pane.
--
-- IMPORTANT: Do NOT aggregate columns directly in Power BI visuals.
-- Use the DAX measures defined in the YAML instead — they correctly
-- recalculate ratios (CPI, ROAS, ARPU, etc.) from additive base metrics.
--
-- Fact table reference: mart_daily_overview_by_platform
-- Grain: One row per DATE / PLATFORM

{{ config(
    materialized='table',
    tags=['mart', 'business', 'overview', 'powerbi']
) }}

SELECT
    1                               AS MEASURE_ID
    , 'Daily Overview by Platform'  AS MEASURE_GROUP
    , CURRENT_TIMESTAMP()           AS LAST_REFRESHED
