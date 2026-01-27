-- mta__campaign_performance.sql
-- Multi-Touch Attribution Campaign Performance
-- Aggregates fractional attribution credit by campaign with revenue attribution
-- Compare different attribution models side-by-side
--
-- Grain: One row per AD_PARTNER + CAMPAIGN_ID + PLATFORM + DATE

{{
    config(
        materialized='incremental',
        unique_key=['AD_PARTNER', 'CAMPAIGN_ID', 'PLATFORM', 'DATE'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        tags=['mta', 'attribution', 'mart']
    )
}}

-- Get touchpoint credits
WITH touchpoint_credits AS (
    SELECT tc.DEVICE_ID
         , tc.PLATFORM
         , tc.AD_PARTNER
         , tc.NETWORK_NAME
         , tc.CAMPAIGN_NAME
         , tc.CAMPAIGN_ID
         , tc.ADGROUP_NAME
         , tc.ADGROUP_ID
         , CAST(tc.INSTALL_TIMESTAMP AS DATE) AS INSTALL_DATE
         , tc.CREDIT_LAST_TOUCH
         , tc.CREDIT_FIRST_TOUCH
         , tc.CREDIT_LINEAR
         , tc.CREDIT_TIME_DECAY
         , tc.CREDIT_POSITION_BASED
         , tc.CREDIT_RECOMMENDED
    FROM {{ ref('int_mta__touchpoint_credit') }} tc
    {% if is_incremental() %}
        WHERE CAST(tc.INSTALL_TIMESTAMP AS DATE) >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
)

-- Get device mapping to link to Amplitude users
, device_mapping AS (
    SELECT ADJUST_DEVICE_ID
         , AMPLITUDE_USER_ID
         , PLATFORM
    FROM {{ ref('int_adjust_amplitude__device_mapping') }}
)

-- Get user metrics for revenue attribution
, user_metrics AS (
    SELECT USER_ID
         , PLATFORM
         , D7_REVENUE
         , D30_REVENUE
         , TOTAL_REVENUE
    FROM {{ ref('int_user_cohort__metrics') }}
)

-- Join touchpoints to user metrics via device mapping
, touchpoints_with_revenue AS (
    SELECT tc.*
         , dm.AMPLITUDE_USER_ID
         , COALESCE(um.D7_REVENUE, 0) AS USER_D7_REVENUE
         , COALESCE(um.D30_REVENUE, 0) AS USER_D30_REVENUE
         , COALESCE(um.TOTAL_REVENUE, 0) AS USER_TOTAL_REVENUE
    FROM touchpoint_credits tc
    LEFT JOIN device_mapping dm
        ON tc.DEVICE_ID = dm.ADJUST_DEVICE_ID
        AND tc.PLATFORM = dm.PLATFORM
    LEFT JOIN user_metrics um
        ON dm.AMPLITUDE_USER_ID = um.USER_ID
        AND dm.PLATFORM = um.PLATFORM
)

-- Aggregate by campaign and date
, campaign_aggregated AS (
    SELECT AD_PARTNER
         , NETWORK_NAME
         , CAMPAIGN_NAME
         , CAMPAIGN_ID
         , PLATFORM
         , INSTALL_DATE AS DATE

         -- =============================================
         -- INSTALL ATTRIBUTION BY MODEL
         -- =============================================
         -- Last-Touch attributed installs
         , SUM(CREDIT_LAST_TOUCH) AS INSTALLS_LAST_TOUCH
         -- First-Touch attributed installs
         , SUM(CREDIT_FIRST_TOUCH) AS INSTALLS_FIRST_TOUCH
         -- Linear attributed installs
         , SUM(CREDIT_LINEAR) AS INSTALLS_LINEAR
         -- Time-Decay attributed installs
         , SUM(CREDIT_TIME_DECAY) AS INSTALLS_TIME_DECAY
         -- Position-Based attributed installs
         , SUM(CREDIT_POSITION_BASED) AS INSTALLS_POSITION_BASED
         -- Recommended (Time-Decay)
         , SUM(CREDIT_RECOMMENDED) AS INSTALLS_RECOMMENDED

         -- =============================================
         -- D7 REVENUE ATTRIBUTION BY MODEL
         -- =============================================
         , SUM(CREDIT_LAST_TOUCH * USER_D7_REVENUE) AS D7_REVENUE_LAST_TOUCH
         , SUM(CREDIT_FIRST_TOUCH * USER_D7_REVENUE) AS D7_REVENUE_FIRST_TOUCH
         , SUM(CREDIT_LINEAR * USER_D7_REVENUE) AS D7_REVENUE_LINEAR
         , SUM(CREDIT_TIME_DECAY * USER_D7_REVENUE) AS D7_REVENUE_TIME_DECAY
         , SUM(CREDIT_POSITION_BASED * USER_D7_REVENUE) AS D7_REVENUE_POSITION_BASED
         , SUM(CREDIT_RECOMMENDED * USER_D7_REVENUE) AS D7_REVENUE_RECOMMENDED

         -- =============================================
         -- D30 REVENUE ATTRIBUTION BY MODEL
         -- =============================================
         , SUM(CREDIT_LAST_TOUCH * USER_D30_REVENUE) AS D30_REVENUE_LAST_TOUCH
         , SUM(CREDIT_FIRST_TOUCH * USER_D30_REVENUE) AS D30_REVENUE_FIRST_TOUCH
         , SUM(CREDIT_LINEAR * USER_D30_REVENUE) AS D30_REVENUE_LINEAR
         , SUM(CREDIT_TIME_DECAY * USER_D30_REVENUE) AS D30_REVENUE_TIME_DECAY
         , SUM(CREDIT_POSITION_BASED * USER_D30_REVENUE) AS D30_REVENUE_POSITION_BASED
         , SUM(CREDIT_RECOMMENDED * USER_D30_REVENUE) AS D30_REVENUE_RECOMMENDED

         -- =============================================
         -- TOTAL REVENUE ATTRIBUTION BY MODEL
         -- =============================================
         , SUM(CREDIT_LAST_TOUCH * USER_TOTAL_REVENUE) AS TOTAL_REVENUE_LAST_TOUCH
         , SUM(CREDIT_FIRST_TOUCH * USER_TOTAL_REVENUE) AS TOTAL_REVENUE_FIRST_TOUCH
         , SUM(CREDIT_LINEAR * USER_TOTAL_REVENUE) AS TOTAL_REVENUE_LINEAR
         , SUM(CREDIT_TIME_DECAY * USER_TOTAL_REVENUE) AS TOTAL_REVENUE_TIME_DECAY
         , SUM(CREDIT_POSITION_BASED * USER_TOTAL_REVENUE) AS TOTAL_REVENUE_POSITION_BASED
         , SUM(CREDIT_RECOMMENDED * USER_TOTAL_REVENUE) AS TOTAL_REVENUE_RECOMMENDED

         -- Unique devices touched
         , COUNT(DISTINCT DEVICE_ID) AS UNIQUE_DEVICES

    FROM touchpoints_with_revenue
    GROUP BY AD_PARTNER
           , NETWORK_NAME
           , CAMPAIGN_NAME
           , CAMPAIGN_ID
           , PLATFORM
           , INSTALL_DATE
)

-- Get network mapping for standardized partner names (join via PARTNER_ID)
, network_mapping_deduped AS (
    SELECT DISTINCT
        SUPERMETRICS_PARTNER_ID
        , SUPERMETRICS_PARTNER_NAME
    FROM {{ ref('network_mapping') }}
    WHERE SUPERMETRICS_PARTNER_ID IS NOT NULL
)

-- Join with spend data
-- Note: Join via PARTNER_ID to SUPERMETRICS_PARTNER_ID for accurate matching
-- Filter out 'unknown' campaign IDs which cannot be matched
, spend AS (
    SELECT COALESCE(nm.SUPERMETRICS_PARTNER_NAME, s.PARTNER_NAME) AS AD_PARTNER
         , s.CAMPAIGN_ID_NETWORK AS CAMPAIGN_ID
         , s.PLATFORM
         , s.DATE
         , SUM(s.COST) AS COST
         , SUM(s.CLICKS) AS CLICKS
         , SUM(s.IMPRESSIONS) AS IMPRESSIONS
    FROM {{ ref('stg_supermetrics__adj_campaign') }} s
    LEFT JOIN network_mapping_deduped nm
        ON s.PARTNER_ID = nm.SUPERMETRICS_PARTNER_ID
    WHERE LOWER(s.CAMPAIGN_ID_NETWORK) != 'unknown'
    {% if is_incremental() %}
        AND s.DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3, 4
)

-- Final join with spend
, final AS (
    SELECT COALESCE(a.AD_PARTNER, s.AD_PARTNER) AS AD_PARTNER
         , a.NETWORK_NAME
         , a.CAMPAIGN_NAME
         , COALESCE(a.CAMPAIGN_ID, s.CAMPAIGN_ID) AS CAMPAIGN_ID
         , COALESCE(a.PLATFORM, s.PLATFORM) AS PLATFORM
         , COALESCE(a.DATE, s.DATE) AS DATE

         -- Spend metrics
         , COALESCE(s.COST, 0) AS COST
         , COALESCE(s.CLICKS, 0) AS CLICKS
         , COALESCE(s.IMPRESSIONS, 0) AS IMPRESSIONS

         -- Install metrics by model
         , COALESCE(a.INSTALLS_LAST_TOUCH, 0) AS INSTALLS_LAST_TOUCH
         , COALESCE(a.INSTALLS_FIRST_TOUCH, 0) AS INSTALLS_FIRST_TOUCH
         , COALESCE(a.INSTALLS_LINEAR, 0) AS INSTALLS_LINEAR
         , COALESCE(a.INSTALLS_TIME_DECAY, 0) AS INSTALLS_TIME_DECAY
         , COALESCE(a.INSTALLS_POSITION_BASED, 0) AS INSTALLS_POSITION_BASED
         , COALESCE(a.INSTALLS_RECOMMENDED, 0) AS INSTALLS_RECOMMENDED

         -- D7 Revenue by model
         , COALESCE(a.D7_REVENUE_LAST_TOUCH, 0) AS D7_REVENUE_LAST_TOUCH
         , COALESCE(a.D7_REVENUE_FIRST_TOUCH, 0) AS D7_REVENUE_FIRST_TOUCH
         , COALESCE(a.D7_REVENUE_LINEAR, 0) AS D7_REVENUE_LINEAR
         , COALESCE(a.D7_REVENUE_TIME_DECAY, 0) AS D7_REVENUE_TIME_DECAY
         , COALESCE(a.D7_REVENUE_POSITION_BASED, 0) AS D7_REVENUE_POSITION_BASED
         , COALESCE(a.D7_REVENUE_RECOMMENDED, 0) AS D7_REVENUE_RECOMMENDED

         -- D30 Revenue by model
         , COALESCE(a.D30_REVENUE_LAST_TOUCH, 0) AS D30_REVENUE_LAST_TOUCH
         , COALESCE(a.D30_REVENUE_FIRST_TOUCH, 0) AS D30_REVENUE_FIRST_TOUCH
         , COALESCE(a.D30_REVENUE_LINEAR, 0) AS D30_REVENUE_LINEAR
         , COALESCE(a.D30_REVENUE_TIME_DECAY, 0) AS D30_REVENUE_TIME_DECAY
         , COALESCE(a.D30_REVENUE_POSITION_BASED, 0) AS D30_REVENUE_POSITION_BASED
         , COALESCE(a.D30_REVENUE_RECOMMENDED, 0) AS D30_REVENUE_RECOMMENDED

         -- Total Revenue by model
         , COALESCE(a.TOTAL_REVENUE_LAST_TOUCH, 0) AS TOTAL_REVENUE_LAST_TOUCH
         , COALESCE(a.TOTAL_REVENUE_FIRST_TOUCH, 0) AS TOTAL_REVENUE_FIRST_TOUCH
         , COALESCE(a.TOTAL_REVENUE_LINEAR, 0) AS TOTAL_REVENUE_LINEAR
         , COALESCE(a.TOTAL_REVENUE_TIME_DECAY, 0) AS TOTAL_REVENUE_TIME_DECAY
         , COALESCE(a.TOTAL_REVENUE_POSITION_BASED, 0) AS TOTAL_REVENUE_POSITION_BASED
         , COALESCE(a.TOTAL_REVENUE_RECOMMENDED, 0) AS TOTAL_REVENUE_RECOMMENDED

         , COALESCE(a.UNIQUE_DEVICES, 0) AS UNIQUE_DEVICES

    FROM campaign_aggregated a
    FULL OUTER JOIN spend s
        ON a.CAMPAIGN_ID = s.CAMPAIGN_ID
        AND a.PLATFORM = s.PLATFORM
        AND a.DATE = s.DATE
)

SELECT *
     -- =============================================
     -- CPI BY MODEL (Cost Per Install)
     -- =============================================
     , IFF(INSTALLS_LAST_TOUCH > 0, COST / INSTALLS_LAST_TOUCH, NULL) AS CPI_LAST_TOUCH
     , IFF(INSTALLS_FIRST_TOUCH > 0, COST / INSTALLS_FIRST_TOUCH, NULL) AS CPI_FIRST_TOUCH
     , IFF(INSTALLS_LINEAR > 0, COST / INSTALLS_LINEAR, NULL) AS CPI_LINEAR
     , IFF(INSTALLS_TIME_DECAY > 0, COST / INSTALLS_TIME_DECAY, NULL) AS CPI_TIME_DECAY
     , IFF(INSTALLS_POSITION_BASED > 0, COST / INSTALLS_POSITION_BASED, NULL) AS CPI_POSITION_BASED
     , IFF(INSTALLS_RECOMMENDED > 0, COST / INSTALLS_RECOMMENDED, NULL) AS CPI_RECOMMENDED

     -- =============================================
     -- D7 ROAS BY MODEL
     -- =============================================
     , IFF(COST > 0, D7_REVENUE_LAST_TOUCH / COST, NULL) AS D7_ROAS_LAST_TOUCH
     , IFF(COST > 0, D7_REVENUE_FIRST_TOUCH / COST, NULL) AS D7_ROAS_FIRST_TOUCH
     , IFF(COST > 0, D7_REVENUE_LINEAR / COST, NULL) AS D7_ROAS_LINEAR
     , IFF(COST > 0, D7_REVENUE_TIME_DECAY / COST, NULL) AS D7_ROAS_TIME_DECAY
     , IFF(COST > 0, D7_REVENUE_POSITION_BASED / COST, NULL) AS D7_ROAS_POSITION_BASED
     , IFF(COST > 0, D7_REVENUE_RECOMMENDED / COST, NULL) AS D7_ROAS_RECOMMENDED

     -- =============================================
     -- D30 ROAS BY MODEL
     -- =============================================
     , IFF(COST > 0, D30_REVENUE_LAST_TOUCH / COST, NULL) AS D30_ROAS_LAST_TOUCH
     , IFF(COST > 0, D30_REVENUE_FIRST_TOUCH / COST, NULL) AS D30_ROAS_FIRST_TOUCH
     , IFF(COST > 0, D30_REVENUE_LINEAR / COST, NULL) AS D30_ROAS_LINEAR
     , IFF(COST > 0, D30_REVENUE_TIME_DECAY / COST, NULL) AS D30_ROAS_TIME_DECAY
     , IFF(COST > 0, D30_REVENUE_POSITION_BASED / COST, NULL) AS D30_ROAS_POSITION_BASED
     , IFF(COST > 0, D30_REVENUE_RECOMMENDED / COST, NULL) AS D30_ROAS_RECOMMENDED

FROM final
WHERE DATE IS NOT NULL
ORDER BY DATE DESC, COST DESC
