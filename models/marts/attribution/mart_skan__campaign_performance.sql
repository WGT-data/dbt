-- mart_skan__campaign_performance.sql
-- Standalone SKAN performance mart
--
-- PURPOSE: Join SKAN aggregate postback data with spend to produce a standalone
-- campaign performance view for iOS SKAdNetwork attribution. Previously SKAN data
-- was only available embedded in mart_exec_summary.
--
-- SKAN LIMITATIONS:
--   - No device identifiers — cannot join to individual users or revenue
--   - SKAN 3.0: campaign-level only (no adgroup/creative granularity)
--   - SANs (Meta, Google): campaign names don't match Adjust API spend data.
--     These partners are aggregated to partner/date level with NULL campaign.
--   - Conversion values are a proxy for engagement, not actual revenue
--
-- COUNTRY HANDLING:
--   - SKAN postbacks have no country dimension
--   - Country is inferred from campaign name patterns (iOS_US_, WGT_AU_, etc.)
--   - Unmatched campaigns get COUNTRY = 'unknown'
--
-- Grain: AD_PARTNER + CAMPAIGN_NAME + INSTALL_DATE + COUNTRY

{{ config(
    materialized='incremental',
    unique_key=['AD_PARTNER', 'CAMPAIGN_NAME', 'INSTALL_DATE', 'COUNTRY'],
    incremental_strategy='merge',
    on_schema_change='append_new_columns',
    tags=['mart', 'skan', 'attribution']
) }}

-- Map spend partner names to canonical AD_PARTNER names
WITH partner_map AS (
    SELECT DISTINCT
        ADJUST_NETWORK_NAME AS PARTNER_NAME
        , AD_PARTNER
    FROM {{ ref('network_mapping') }}
    WHERE AD_PARTNER IS NOT NULL

    UNION

    SELECT DISTINCT
        SUPERMETRICS_PARTNER_NAME || ' (Ad Spend)' AS PARTNER_NAME
        , AD_PARTNER
    FROM {{ ref('network_mapping') }}
    WHERE AD_PARTNER IS NOT NULL
)

-- SKAN postback data with country inference
-- SANs aggregate to partner/date/country (campaign = NULL)
, skan_data AS (
    SELECT
        AD_PARTNER
        , CASE WHEN AD_PARTNER IN ('Meta', 'Google') THEN '__none__' ELSE CAMPAIGN_NAME END AS CAMPAIGN_NAME
        , INSTALL_DATE
        -- Infer country from campaign name patterns
        , LOWER(
            REPLACE(
            CASE
                WHEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), '(IOS|ANDROID)[_-]([A-Z]{2})[_+-]', 1, 1, 'e', 2)
                     IN ('US','UK','CA','AU','NZ','ZA')
                THEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), '(IOS|ANDROID)[_-]([A-Z]{2})[_+-]', 1, 1, 'e', 2)
                WHEN UPPER(CAMPAIGN_NAME) LIKE '%AU+NZ%' OR UPPER(CAMPAIGN_NAME) LIKE '%AU_NZ%'
                THEN 'AU'
                WHEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), 'WGT[_-]([A-Z]{2})[_-]', 1, 1, 'e', 1)
                     IN ('US','UK','CA','AU','NZ','ZA')
                THEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), 'WGT[_-]([A-Z]{2})[_-]', 1, 1, 'e', 1)
                WHEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), 'TOPGOLF[_-]([A-Z]{2})[_-]', 1, 1, 'e', 1)
                     IN ('US','UK','CA','AU','NZ','ZA')
                THEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), 'TOPGOLF[_-]([A-Z]{2})[_-]', 1, 1, 'e', 1)
                WHEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), '[_-]([A-Z]{2})[_-]?ONLY', 1, 1, 'e', 1)
                     IN ('US','UK','CA','AU','NZ','ZA')
                THEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), '[_-]([A-Z]{2})[_-]?ONLY', 1, 1, 'e', 1)
                WHEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), '_([A-Z]{2})(_[A-Z]+)?$', 1, 1, 'e', 1)
                     IN ('US','UK','CA','AU','NZ','ZA')
                THEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), '_([A-Z]{2})(_[A-Z]+)?$', 1, 1, 'e', 1)
                WHEN UPPER(CAMPAIGN_NAME) LIKE '%_ZAR_%' THEN 'ZA'
                WHEN UPPER(CAMPAIGN_NAME) LIKE '%_UK_%' OR UPPER(CAMPAIGN_NAME) LIKE '%_UK %' THEN 'UK'
                ELSE 'unknown'
            END
            , 'UK', 'GB')
          ) AS COUNTRY

        -- Aggregate SKAN metrics
        , SUM(INSTALL_COUNT) AS INSTALL_COUNT
        , SUM(NEW_INSTALL_COUNT) AS NEW_INSTALL_COUNT
        , SUM(REDOWNLOAD_COUNT) AS REDOWNLOAD_COUNT
        , AVG(AVG_CONVERSION_VALUE) AS AVG_CONVERSION_VALUE
        , MAX(MAX_CONVERSION_VALUE) AS MAX_CONVERSION_VALUE
        , SUM(INSTALLS_WITH_CV) AS INSTALLS_WITH_CV
        , SUM(CV_BUCKET_0) AS CV_BUCKET_0
        , SUM(CV_BUCKET_1_10) AS CV_BUCKET_1_10
        , SUM(CV_BUCKET_11_20) AS CV_BUCKET_11_20
        , SUM(CV_BUCKET_21_40) AS CV_BUCKET_21_40
        , SUM(CV_BUCKET_41_63) AS CV_BUCKET_41_63
        , SUM(STOREKIT_RENDERED_COUNT) AS STOREKIT_RENDERED_COUNT
        , SUM(VIEW_THROUGH_COUNT) AS VIEW_THROUGH_COUNT
        , SUM(WINNING_POSTBACKS) AS WINNING_POSTBACKS
        , SUM(SKAN_V3_COUNT) AS SKAN_V3_COUNT
        , SUM(SKAN_V4_COUNT) AS SKAN_V4_COUNT
    FROM {{ ref('int_skan__aggregate_attribution') }}
    {% if is_incremental() %}
        WHERE INSTALL_DATE >= DATEADD(day, -7, (SELECT MAX(INSTALL_DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3, 4
)

-- Spend data for iOS only, rolled up to campaign + country grain
, spend_data AS (
    SELECT
        s.DATE
        , COALESCE(pm.AD_PARTNER, s.PARTNER_NAME) AS AD_PARTNER
        , s.CAMPAIGN_NETWORK AS CAMPAIGN_NAME
        , LOWER(s.COUNTRY) AS COUNTRY
        , SUM(s.NETWORK_COST) AS COST
        , SUM(s.CLICKS) AS CLICKS
        , SUM(s.IMPRESSIONS) AS IMPRESSIONS
        , SUM(s.INSTALLS) AS ADJUST_INSTALLS
    FROM {{ ref('stg_adjust__report_daily') }} s
    LEFT JOIN partner_map pm ON s.PARTNER_NAME = pm.PARTNER_NAME
    WHERE s.DATE IS NOT NULL
      AND LOWER(s.PLATFORM) = 'ios'
    {% if is_incremental() %}
        AND s.DATE >= DATEADD(day, -7, (SELECT MAX(INSTALL_DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3, 4
)

-- Join SKAN installs with spend
, joined AS (
    SELECT
        COALESCE(sk.INSTALL_DATE, sp.DATE) AS INSTALL_DATE
        , COALESCE(sk.AD_PARTNER, sp.AD_PARTNER) AS AD_PARTNER
        , COALESCE(sk.CAMPAIGN_NAME, sp.CAMPAIGN_NAME) AS CAMPAIGN_NAME
        , COALESCE(sk.COUNTRY, sp.COUNTRY, 'unknown') AS COUNTRY

        -- Spend metrics
        , COALESCE(sp.COST, 0) AS COST
        , COALESCE(sp.CLICKS, 0) AS CLICKS
        , COALESCE(sp.IMPRESSIONS, 0) AS IMPRESSIONS
        , COALESCE(sp.ADJUST_INSTALLS, 0) AS ADJUST_INSTALLS

        -- SKAN install metrics
        , COALESCE(sk.INSTALL_COUNT, 0) AS SKAN_INSTALL_COUNT
        , COALESCE(sk.NEW_INSTALL_COUNT, 0) AS SKAN_NEW_INSTALLS
        , COALESCE(sk.REDOWNLOAD_COUNT, 0) AS SKAN_REDOWNLOADS

        -- Conversion value metrics
        , sk.AVG_CONVERSION_VALUE
        , sk.MAX_CONVERSION_VALUE
        , COALESCE(sk.INSTALLS_WITH_CV, 0) AS INSTALLS_WITH_CV

        -- CV distribution
        , COALESCE(sk.CV_BUCKET_0, 0) AS CV_BUCKET_0
        , COALESCE(sk.CV_BUCKET_1_10, 0) AS CV_BUCKET_1_10
        , COALESCE(sk.CV_BUCKET_11_20, 0) AS CV_BUCKET_11_20
        , COALESCE(sk.CV_BUCKET_21_40, 0) AS CV_BUCKET_21_40
        , COALESCE(sk.CV_BUCKET_41_63, 0) AS CV_BUCKET_41_63

        -- Fidelity
        , COALESCE(sk.STOREKIT_RENDERED_COUNT, 0) AS STOREKIT_RENDERED_COUNT
        , COALESCE(sk.VIEW_THROUGH_COUNT, 0) AS VIEW_THROUGH_COUNT
        , COALESCE(sk.WINNING_POSTBACKS, 0) AS WINNING_POSTBACKS

        -- Version distribution
        , COALESCE(sk.SKAN_V3_COUNT, 0) AS SKAN_V3_COUNT
        , COALESCE(sk.SKAN_V4_COUNT, 0) AS SKAN_V4_COUNT

    FROM skan_data sk
    FULL OUTER JOIN spend_data sp
        ON sk.INSTALL_DATE = sp.DATE
        AND LOWER(sk.AD_PARTNER) = LOWER(sp.AD_PARTNER)
        AND LOWER(sk.CAMPAIGN_NAME) = LOWER(sp.CAMPAIGN_NAME)
        AND sk.COUNTRY = sp.COUNTRY
)

SELECT
    INSTALL_DATE
    , AD_PARTNER
    , CAMPAIGN_NAME
    , COUNTRY

    -- Spend
    , COST
    , CLICKS
    , IMPRESSIONS
    , ADJUST_INSTALLS

    -- SKAN installs
    , SKAN_INSTALL_COUNT
    , SKAN_NEW_INSTALLS
    , SKAN_REDOWNLOADS

    -- Efficiency metrics (denominator = SKAN new installs)
    , CASE WHEN SKAN_NEW_INSTALLS > 0
        THEN COST / SKAN_NEW_INSTALLS
        ELSE NULL END AS SKAN_CPI
    , CASE WHEN IMPRESSIONS > 0
        THEN (COST / IMPRESSIONS) * 1000
        ELSE NULL END AS CPM
    , CASE WHEN IMPRESSIONS > 0
        THEN CLICKS::FLOAT / IMPRESSIONS
        ELSE NULL END AS CTR
    , CASE WHEN CLICKS > 0
        THEN SKAN_NEW_INSTALLS::FLOAT / CLICKS
        ELSE NULL END AS SKAN_CVR

    -- Win rate
    , CASE WHEN SKAN_INSTALL_COUNT > 0
        THEN WINNING_POSTBACKS::FLOAT / SKAN_INSTALL_COUNT
        ELSE NULL END AS WIN_RATE

    -- Fidelity mix
    , CASE WHEN SKAN_INSTALL_COUNT > 0
        THEN STOREKIT_RENDERED_COUNT::FLOAT / SKAN_INSTALL_COUNT
        ELSE NULL END AS STOREKIT_RENDERED_RATE
    , CASE WHEN SKAN_INSTALL_COUNT > 0
        THEN VIEW_THROUGH_COUNT::FLOAT / SKAN_INSTALL_COUNT
        ELSE NULL END AS VIEW_THROUGH_RATE

    -- CV coverage
    , CASE WHEN SKAN_INSTALL_COUNT > 0
        THEN INSTALLS_WITH_CV::FLOAT / SKAN_INSTALL_COUNT
        ELSE NULL END AS CV_COVERAGE_RATE

    -- Conversion value metrics
    , AVG_CONVERSION_VALUE
    , MAX_CONVERSION_VALUE
    , INSTALLS_WITH_CV
    , CV_BUCKET_0
    , CV_BUCKET_1_10
    , CV_BUCKET_11_20
    , CV_BUCKET_21_40
    , CV_BUCKET_41_63

    -- Fidelity raw counts
    , STOREKIT_RENDERED_COUNT
    , VIEW_THROUGH_COUNT
    , WINNING_POSTBACKS

    -- SKAN version distribution
    , SKAN_V3_COUNT
    , SKAN_V4_COUNT

FROM joined
WHERE INSTALL_DATE IS NOT NULL
