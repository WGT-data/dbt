{{
    config(
        materialized='incremental',
        unique_key=['DATE', 'PLATFORM', 'CHANNEL'],
        incremental_strategy='merge',
        tags=['mmm', 'revenue']
    )
}}

/*
    Daily revenue by channel and platform for MMM input

    Source: Adjust API daily report (stg_adjust__report_daily)
    Channel mapping: network_mapping seed for consistent AD_PARTNER taxonomy
    Grain: one row per DATE + PLATFORM + CHANNEL

    CRITICAL DESIGN DECISION:
    This model uses Adjust API's pre-aggregated revenue data rather than the
    user-level cohort pipeline (int_user_cohort__metrics). Why:
    - int_user_cohort__metrics depends on int_adjust_amplitude__device_mapping (never built to production)
    - Device mapping is broken for Android (0% match rate due to SDK config)
    - Adjust API already has revenue attributed at the campaign/partner level
    - This makes the MMM pipeline fully independent of MTA device matching

    TRADEOFF:
    Adjust API revenue is revenue-event-date based (not install-cohort-date based).
    This is acceptable for MMM because:
    - MMM uses aggregate time series and infers relationships statistically
    - Install-to-revenue lag is captured implicitly in adstock/lag parameters of MMM models
    - Using API data ensures complete coverage (all platforms, all channels)
*/

WITH revenue_with_channel AS (
    SELECT
        r.DATE,
        r.PLATFORM,
        COALESCE(nm.AD_PARTNER, r.PARTNER_NAME) AS CHANNEL,
        SUM(r.REVENUE) AS REVENUE,
        SUM(r.ALL_REVENUE) AS ALL_REVENUE,
        SUM(r.AD_REVENUE) AS AD_REVENUE,
        SUM(r.INSTALLS) AS API_INSTALLS  -- for cross-check against S3 installs
    FROM {{ ref('stg_adjust__report_daily') }} r
    -- Note: Snowflake treats unquoted identifiers as case-insensitive.
    -- The seed CSV has lowercase headers (adjust_network_name) but since
    -- quote_columns is not set in dbt_project.yml, Snowflake uppercases them
    -- internally. Using UPPERCASE here for project consistency.
    LEFT JOIN {{ ref('network_mapping') }} nm
        ON r.PARTNER_NAME = nm.ADJUST_NETWORK_NAME
    WHERE r.DATE IS NOT NULL
    {% if is_incremental() %}
      AND r.DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3
)

SELECT
    DATE,
    PLATFORM,
    CHANNEL,
    REVENUE,
    ALL_REVENUE,
    AD_REVENUE,
    API_INSTALLS
FROM revenue_with_channel
