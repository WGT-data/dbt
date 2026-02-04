-- int_skan__aggregate_attribution.sql
-- Aggregate-level attribution from SKAdNetwork postbacks
-- Grain: One row per partner/campaign/install_date
--
-- IMPORTANT: SKAN data has NO device identifiers. These installs CANNOT be joined
-- to individual users. This model provides aggregate install counts and conversion
-- value distributions for iOS users who did not consent to tracking.
--
-- There is potential overlap with device-level installs (int_user_cohort__attribution)
-- for users who consented to tracking. Deduplication logic should be applied before
-- combining these models.

{{ config(
    materialized='incremental',
    unique_key=['PARTNER', 'CAMPAIGN_NAME', 'INSTALL_DATE'],
    incremental_strategy='merge',
    tags=['skan', 'attribution', 'aggregate'],
    on_schema_change='append_new_columns'
) }}

WITH skan_installs AS (
    SELECT
        PARTNER
        , CAMPAIGN_NAME
        , DATE(TO_TIMESTAMP(SK_TS)) AS INSTALL_DATE
        , SK_CONVERSION_VALUE
        , SK_REDOWNLOAD
        , SK_FIDELITY_TYPE
        , SK_DID_WIN
        , SK_VERSION
        , SK_TRANSACTION_ID
    FROM {{ ref('stg_adjust__ios_activity_sk_install') }}
    WHERE SK_TS IS NOT NULL
    {% if is_incremental() %}
        AND DATE(TO_TIMESTAMP(SK_TS)) >= DATEADD(day, -7, (SELECT MAX(INSTALL_DATE) FROM {{ this }}))
    {% endif %}
)

, aggregated AS (
    SELECT
        PARTNER
        , CAMPAIGN_NAME
        , INSTALL_DATE

        -- Install counts
        , COUNT(DISTINCT SK_TRANSACTION_ID) AS INSTALL_COUNT
        , COUNT(DISTINCT CASE WHEN SK_REDOWNLOAD = '0' THEN SK_TRANSACTION_ID END) AS NEW_INSTALL_COUNT
        , COUNT(DISTINCT CASE WHEN SK_REDOWNLOAD = '1' THEN SK_TRANSACTION_ID END) AS REDOWNLOAD_COUNT

        -- Conversion value metrics (proxy for user quality/engagement)
        , AVG(TRY_CAST(SK_CONVERSION_VALUE AS FLOAT)) AS AVG_CONVERSION_VALUE
        , MEDIAN(TRY_CAST(SK_CONVERSION_VALUE AS FLOAT)) AS MEDIAN_CONVERSION_VALUE
        , MAX(TRY_CAST(SK_CONVERSION_VALUE AS INTEGER)) AS MAX_CONVERSION_VALUE
        , COUNT(DISTINCT CASE WHEN SK_CONVERSION_VALUE IS NOT NULL THEN SK_TRANSACTION_ID END) AS INSTALLS_WITH_CV

        -- Conversion value distribution buckets
        , COUNT(DISTINCT CASE WHEN TRY_CAST(SK_CONVERSION_VALUE AS INTEGER) = 0 THEN SK_TRANSACTION_ID END) AS CV_BUCKET_0
        , COUNT(DISTINCT CASE WHEN TRY_CAST(SK_CONVERSION_VALUE AS INTEGER) BETWEEN 1 AND 10 THEN SK_TRANSACTION_ID END) AS CV_BUCKET_1_10
        , COUNT(DISTINCT CASE WHEN TRY_CAST(SK_CONVERSION_VALUE AS INTEGER) BETWEEN 11 AND 20 THEN SK_TRANSACTION_ID END) AS CV_BUCKET_11_20
        , COUNT(DISTINCT CASE WHEN TRY_CAST(SK_CONVERSION_VALUE AS INTEGER) BETWEEN 21 AND 40 THEN SK_TRANSACTION_ID END) AS CV_BUCKET_21_40
        , COUNT(DISTINCT CASE WHEN TRY_CAST(SK_CONVERSION_VALUE AS INTEGER) BETWEEN 41 AND 63 THEN SK_TRANSACTION_ID END) AS CV_BUCKET_41_63

        -- Fidelity type breakdown (1 = StoreKit rendered, 0 = view-through)
        , COUNT(DISTINCT CASE WHEN SK_FIDELITY_TYPE = '1' THEN SK_TRANSACTION_ID END) AS STOREKIT_RENDERED_COUNT
        , COUNT(DISTINCT CASE WHEN SK_FIDELITY_TYPE = '0' THEN SK_TRANSACTION_ID END) AS VIEW_THROUGH_COUNT

        -- Win rate (did this network win the attribution)
        , COUNT(DISTINCT CASE WHEN SK_DID_WIN = '1' THEN SK_TRANSACTION_ID END) AS WINNING_POSTBACKS

        -- SKAN version distribution
        , COUNT(DISTINCT CASE WHEN SK_VERSION LIKE '3%' THEN SK_TRANSACTION_ID END) AS SKAN_V3_COUNT
        , COUNT(DISTINCT CASE WHEN SK_VERSION LIKE '4%' THEN SK_TRANSACTION_ID END) AS SKAN_V4_COUNT

    FROM skan_installs
    GROUP BY PARTNER, CAMPAIGN_NAME, INSTALL_DATE
)

-- Apply partner name standardization
SELECT
    a.PARTNER AS SKAN_PARTNER
    , CASE
        WHEN UPPER(a.PARTNER) IN ('FACEBOOK', 'INSTAGRAM', 'META') THEN 'Meta'
        WHEN UPPER(a.PARTNER) IN ('GOOGLE ADS', 'GOOGLE', 'ADMOB') THEN 'Google'
        WHEN UPPER(a.PARTNER) LIKE '%TIKTOK%' THEN 'TikTok'
        WHEN UPPER(a.PARTNER) = 'APPLE' THEN 'Apple'
        WHEN UPPER(a.PARTNER) LIKE '%APPLOVIN%' THEN 'AppLovin'
        WHEN UPPER(a.PARTNER) LIKE '%UNITY%' THEN 'Unity'
        WHEN UPPER(a.PARTNER) LIKE '%MOLOCO%' THEN 'Moloco'
        WHEN UPPER(a.PARTNER) LIKE '%SMADEX%' THEN 'Smadex'
        WHEN UPPER(a.PARTNER) LIKE '%VUNGLE%' THEN 'Vungle'
        WHEN UPPER(a.PARTNER) LIKE '%LIFTOFF%' THEN 'Liftoff'
        ELSE 'Other'
    END AS AD_PARTNER
    , a.CAMPAIGN_NAME
    , a.INSTALL_DATE
    , a.INSTALL_COUNT
    , a.NEW_INSTALL_COUNT
    , a.REDOWNLOAD_COUNT
    , a.AVG_CONVERSION_VALUE
    , a.MEDIAN_CONVERSION_VALUE
    , a.MAX_CONVERSION_VALUE
    , a.INSTALLS_WITH_CV
    , a.CV_BUCKET_0
    , a.CV_BUCKET_1_10
    , a.CV_BUCKET_11_20
    , a.CV_BUCKET_21_40
    , a.CV_BUCKET_41_63
    , a.STOREKIT_RENDERED_COUNT
    , a.VIEW_THROUGH_COUNT
    , a.WINNING_POSTBACKS
    , a.SKAN_V3_COUNT
    , a.SKAN_V4_COUNT
FROM aggregated a
