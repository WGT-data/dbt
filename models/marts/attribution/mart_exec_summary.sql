-- mart_exec_summary.sql
-- Executive Summary BI model at Campaign grain
--
-- PURPOSE: Campaign-level daily metrics combining spend, device-attributed cohort
-- data, and SKAN installs. Rolled up from adgroup/creative to campaign level to
-- allow clean SKAN join (SKAN 3.0 only provides campaign-level postbacks).
--
-- DIMENSIONS:
--   - OS (PLATFORM), Channel (AD_PARTNER), Campaign, Country
--   - Adgroup and Creative removed — use mart_campaign_performance_full for that grain
--
-- COUNTRY HANDLING:
--   - Spend data: has real country (full names → mapped to 2-letter ISO codes)
--   - Cohort data: has real country (2-letter ISO codes from Adjust device attribution)
--   - SKAN data: NO country dimension — inferred from campaign name patterns where possible
--     e.g. WGT_iOS_US_AppInstall → 'us', WGT_TopGolf_US_iOS → 'us'
--     Campaigns without extractable country get COUNTRY = 'unknown'
--
-- SKAN COVERAGE:
--   - iOS only, SKAN 3.0 (campaign level only — no adgroup/creative in postback)
--   - NEW_INSTALL_COUNT used (excludes redownloads)
--
-- Grain: One row per AD_PARTNER / NETWORK_NAME / CAMPAIGN_NAME / CAMPAIGN_ID / PLATFORM / COUNTRY / DATE

{{ config(
    materialized='incremental',
    unique_key=['AD_PARTNER', 'NETWORK_NAME', 'CAMPAIGN_NAME', 'CAMPAIGN_ID', 'PLATFORM', 'COUNTRY', 'DATE'],
    incremental_strategy='merge',
    on_schema_change='append_new_columns',
    tags=['mart', 'performance', 'executive']
) }}

-- Country name → ISO 2-letter code mapping for spend data (which uses full names)
WITH country_code_map AS (
    SELECT code, name FROM (VALUES
        ('us', 'United States'),
        ('gb', 'United Kingdom'),
        ('ca', 'Canada'),
        ('au', 'Australia'),
        ('nz', 'New Zealand'),
        ('za', 'South Africa'),
        ('ie', 'Ireland'),
        ('fr', 'France'),
        ('de', 'Germany'),
        ('es', 'Spain'),
        ('it', 'Italy'),
        ('nl', 'Netherlands'),
        ('se', 'Sweden'),
        ('no', 'Norway'),
        ('dk', 'Denmark'),
        ('fi', 'Finland'),
        ('ch', 'Switzerland'),
        ('at', 'Austria'),
        ('be', 'Belgium'),
        ('pt', 'Portugal'),
        ('jp', 'Japan'),
        ('kr', 'South Korea'),
        ('cn', 'China'),
        ('th', 'Thailand'),
        ('ph', 'Philippines'),
        ('my', 'Malaysia'),
        ('sg', 'Singapore'),
        ('id', 'Indonesia'),
        ('vn', 'Viet Nam'),
        ('in', 'India'),
        ('mx', 'Mexico'),
        ('br', 'Brazil'),
        ('ar', 'Argentina'),
        ('co', 'Colombia'),
        ('ru', 'Russia'),
        ('pr', 'Puerto Rico'),
        ('do', 'Dominican Republic'),
        ('tw', 'Taiwan'),
        ('hk', 'Hong Kong'),
        ('pl', 'Poland'),
        ('cz', 'Czech Republic'),
        ('hu', 'Hungary'),
        ('ro', 'Romania'),
        ('gr', 'Greece'),
        ('il', 'Israel'),
        ('ae', 'United Arab Emirates'),
        ('sa', 'Saudi Arabia'),
        ('eg', 'Egypt'),
        ('ng', 'Nigeria'),
        ('ke', 'Kenya')
    ) AS t(code, name)
)

-- Map spend partner names to canonical AD_PARTNER names
, partner_map AS (
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

-- Spend data rolled up to campaign + country grain
, spend_data AS (
    SELECT DATE
         , COALESCE(pm.AD_PARTNER, s.PARTNER_NAME) AS AD_PARTNER
         , s.CAMPAIGN_NETWORK AS CAMPAIGN_NAME
         , s.CAMPAIGN_ID_NETWORK AS CAMPAIGN_ID
         , s.PLATFORM
         , LOWER(COALESCE(ccm.code, '__none__')) AS COUNTRY
         , SUM(s.NETWORK_COST) AS COST
         , SUM(s.CLICKS) AS CLICKS
         , SUM(s.IMPRESSIONS) AS IMPRESSIONS
         , SUM(s.INSTALLS) AS ADJUST_INSTALLS
    FROM {{ ref('stg_adjust__report_daily') }} s
    LEFT JOIN partner_map pm ON s.PARTNER_NAME = pm.PARTNER_NAME
    LEFT JOIN country_code_map ccm ON LOWER(s.COUNTRY) = LOWER(ccm.name)
    WHERE s.DATE IS NOT NULL
    {% if is_incremental() %}
        AND s.DATE >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3, 4, 5, 6
)

-- User attribution data
, user_attribution AS (
    SELECT * FROM {{ ref('int_user_cohort__attribution') }}
    {% if is_incremental() %}
        WHERE INSTALL_DATE >= DATEADD(day, -35, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
)

-- User metrics (revenue + retention)
, user_metrics AS (
    SELECT * FROM {{ ref('int_user_cohort__metrics') }}
    {% if is_incremental() %}
        WHERE INSTALL_DATE >= DATEADD(day, -35, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
)

-- Join attribution with metrics
, user_full AS (
    SELECT
        a.USER_ID
        , a.PLATFORM
        , a.AD_PARTNER
        , a.NETWORK_NAME
        , a.CAMPAIGN_NAME
        , a.ADGROUP_NAME
        , LOWER(COALESCE(a.COUNTRY, '__none__')) AS COUNTRY
        , a.INSTALL_DATE
        , m.D7_REVENUE
        , m.D30_REVENUE
        , m.TOTAL_REVENUE
        , m.D7_PURCHASE_REVENUE
        , m.D30_PURCHASE_REVENUE
        , m.TOTAL_PURCHASE_REVENUE
        , m.D7_AD_REVENUE
        , m.D30_AD_REVENUE
        , m.TOTAL_AD_REVENUE
        , m.IS_D7_PAYER
        , m.IS_D30_PAYER
        , m.IS_PAYER
        , m.D1_RETAINED
        , m.D7_RETAINED
        , m.D30_RETAINED
        , m.D1_MATURED
        , m.D7_MATURED
        , m.D30_MATURED
    FROM user_attribution a
    LEFT JOIN user_metrics m
        ON a.USER_ID = m.USER_ID
        AND a.PLATFORM = m.PLATFORM
)

-- SKAN installs (campaign level only — SKAN 3.0 limitation)
-- Infer country from campaign name patterns since SKAN has no country dimension
-- Valid target countries: US, UK, AU, CA, NZ, ZA, EU (region)
, skan_data AS (
    SELECT
        AD_PARTNER
        , CAMPAIGN_NAME
        , INSTALL_DATE
        , LOWER(
            CASE
                -- Pattern: ...iOS_US_... or ...Android_US_... or ...IOS-US-...
                WHEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), '(IOS|ANDROID)[_-]([A-Z]{2})[_+-]', 1, 1, 'e', 2)
                     IN ('US','UK','CA','AU','NZ','ZA')
                THEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), '(IOS|ANDROID)[_-]([A-Z]{2})[_+-]', 1, 1, 'e', 2)

                -- Pattern: ...AU+NZ_... → treat as AU (Australian market)
                WHEN UPPER(CAMPAIGN_NAME) LIKE '%AU+NZ%' OR UPPER(CAMPAIGN_NAME) LIKE '%AU_NZ%'
                THEN 'AU'

                -- Pattern: WGT_US_... (Apple campaigns like WGT_AU_Keyword_GOLF)
                WHEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), 'WGT[_-]([A-Z]{2})[_-]', 1, 1, 'e', 1)
                     IN ('US','UK','CA','AU','NZ','ZA')
                THEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), 'WGT[_-]([A-Z]{2})[_-]', 1, 1, 'e', 1)

                -- Pattern: TopGolf_US_iOS
                WHEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), 'TOPGOLF[_-]([A-Z]{2})[_-]', 1, 1, 'e', 1)
                     IN ('US','UK','CA','AU','NZ','ZA')
                THEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), 'TOPGOLF[_-]([A-Z]{2})[_-]', 1, 1, 'e', 1)

                -- Pattern: _US-only or _USOnly or _US_Only
                WHEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), '[_-]([A-Z]{2})[_-]?ONLY', 1, 1, 'e', 1)
                     IN ('US','UK','CA','AU','NZ','ZA')
                THEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), '[_-]([A-Z]{2})[_-]?ONLY', 1, 1, 'e', 1)

                -- Pattern: _ROAS_US or _ROAS_US_Static (end-of-name country)
                WHEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), '_([A-Z]{2})(_[A-Z]+)?$', 1, 1, 'e', 1)
                     IN ('US','UK','CA','AU','NZ','ZA')
                THEN REGEXP_SUBSTR(UPPER(CAMPAIGN_NAME), '_([A-Z]{2})(_[A-Z]+)?$', 1, 1, 'e', 1)

                -- Pattern: ZAR → South Africa (Google uses ZAR for ZA market)
                WHEN UPPER(CAMPAIGN_NAME) LIKE '%_ZAR_%'
                THEN 'ZA'

                -- Pattern: UK_Only (Meta iOS14+ campaigns)
                WHEN UPPER(CAMPAIGN_NAME) LIKE '%_UK_%' OR UPPER(CAMPAIGN_NAME) LIKE '%_UK %'
                THEN 'UK'

                ELSE 'unknown'
            END
          ) AS INFERRED_COUNTRY
        , SUM(NEW_INSTALL_COUNT) AS NEW_INSTALL_COUNT
    FROM {{ ref('int_skan__aggregate_attribution') }}
    {% if is_incremental() %}
        WHERE INSTALL_DATE >= DATEADD(day, -35, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY AD_PARTNER, CAMPAIGN_NAME, INSTALL_DATE, 4
)

-- Aggregate user metrics by campaign/date/country
, cohort_metrics AS (
    SELECT
        INSTALL_DATE AS DATE
        , AD_PARTNER
        , NETWORK_NAME
        , CAMPAIGN_NAME
        , PLATFORM
        , COUNTRY

        -- Install counts
        , COUNT(DISTINCT USER_ID) AS ATTRIBUTION_INSTALLS

        -- Total Revenue
        , SUM(TOTAL_REVENUE) AS TOTAL_REVENUE
        , SUM(D7_REVENUE) AS D7_REVENUE
        , SUM(D30_REVENUE) AS D30_REVENUE

        -- Purchase Revenue (IAP)
        , SUM(TOTAL_PURCHASE_REVENUE) AS TOTAL_PURCHASE_REVENUE
        , SUM(D7_PURCHASE_REVENUE) AS D7_PURCHASE_REVENUE
        , SUM(D30_PURCHASE_REVENUE) AS D30_PURCHASE_REVENUE

        -- Ad Revenue
        , SUM(TOTAL_AD_REVENUE) AS TOTAL_AD_REVENUE
        , SUM(D7_AD_REVENUE) AS D7_AD_REVENUE
        , SUM(D30_AD_REVENUE) AS D30_AD_REVENUE

        -- Paying user counts
        , SUM(IS_PAYER) AS TOTAL_PAYING_USERS
        , SUM(IS_D7_PAYER) AS D7_PAYING_USERS
        , SUM(IS_D30_PAYER) AS D30_PAYING_USERS

        -- Retention numerators
        , SUM(D1_RETAINED) AS D1_RETAINED_USERS
        , SUM(D7_RETAINED) AS D7_RETAINED_USERS
        , SUM(D30_RETAINED) AS D30_RETAINED_USERS

        -- Retention denominators (mature cohorts)
        , SUM(D1_MATURED) AS D1_MATURED_USERS
        , SUM(D7_MATURED) AS D7_MATURED_USERS
        , SUM(D30_MATURED) AS D30_MATURED_USERS

    FROM user_full
    WHERE INSTALL_DATE IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 6
)

-- Join spend with cohort metrics, then attach SKAN
, combined AS (
    SELECT
        COALESCE(s.DATE, c.DATE) AS DATE
        , COALESCE(s.AD_PARTNER, c.AD_PARTNER) AS AD_PARTNER
        , c.NETWORK_NAME
        , COALESCE(s.CAMPAIGN_NAME, c.CAMPAIGN_NAME) AS CAMPAIGN_NAME
        , s.CAMPAIGN_ID
        , COALESCE(s.PLATFORM, c.PLATFORM) AS PLATFORM
        , COALESCE(s.COUNTRY, c.COUNTRY, '__none__') AS COUNTRY

        -- Spend metrics
        , COALESCE(s.COST, 0) AS COST
        , COALESCE(s.CLICKS, 0) AS CLICKS
        , COALESCE(s.IMPRESSIONS, 0) AS IMPRESSIONS
        , COALESCE(s.ADJUST_INSTALLS, 0) AS ADJUST_INSTALLS

        -- Cohort metrics
        , COALESCE(c.ATTRIBUTION_INSTALLS, 0) AS ATTRIBUTION_INSTALLS

        -- Total Revenue
        , COALESCE(c.TOTAL_REVENUE, 0) AS TOTAL_REVENUE
        , COALESCE(c.D7_REVENUE, 0) AS D7_REVENUE
        , COALESCE(c.D30_REVENUE, 0) AS D30_REVENUE

        -- Purchase Revenue
        , COALESCE(c.TOTAL_PURCHASE_REVENUE, 0) AS TOTAL_PURCHASE_REVENUE
        , COALESCE(c.D7_PURCHASE_REVENUE, 0) AS D7_PURCHASE_REVENUE
        , COALESCE(c.D30_PURCHASE_REVENUE, 0) AS D30_PURCHASE_REVENUE

        -- Ad Revenue
        , COALESCE(c.TOTAL_AD_REVENUE, 0) AS TOTAL_AD_REVENUE
        , COALESCE(c.D7_AD_REVENUE, 0) AS D7_AD_REVENUE
        , COALESCE(c.D30_AD_REVENUE, 0) AS D30_AD_REVENUE

        -- Paying users
        , COALESCE(c.TOTAL_PAYING_USERS, 0) AS TOTAL_PAYING_USERS
        , COALESCE(c.D7_PAYING_USERS, 0) AS D7_PAYING_USERS
        , COALESCE(c.D30_PAYING_USERS, 0) AS D30_PAYING_USERS

        -- Retention
        , COALESCE(c.D1_RETAINED_USERS, 0) AS D1_RETAINED_USERS
        , COALESCE(c.D7_RETAINED_USERS, 0) AS D7_RETAINED_USERS
        , COALESCE(c.D30_RETAINED_USERS, 0) AS D30_RETAINED_USERS
        , COALESCE(c.D1_MATURED_USERS, 0) AS D1_MATURED_USERS
        , COALESCE(c.D7_MATURED_USERS, 0) AS D7_MATURED_USERS
        , COALESCE(c.D30_MATURED_USERS, 0) AS D30_MATURED_USERS

        -- SKAN installs: only join when COUNTRY matches the SKAN inferred country
        -- SKAN joins on iOS only. For spend/cohort rows with real country, we only
        -- attach SKAN installs to the row whose country matches the inferred country.
        -- This prevents fan-out: SKAN installs land on exactly one country row.
        , 0 AS SKAN_INSTALLS  -- placeholder, replaced below

    FROM spend_data s
    FULL OUTER JOIN cohort_metrics c
        ON s.DATE = c.DATE
        AND LOWER(s.AD_PARTNER) = LOWER(c.AD_PARTNER)
        AND LOWER(s.CAMPAIGN_NAME) = LOWER(c.CAMPAIGN_NAME)
        AND LOWER(s.PLATFORM) = LOWER(c.PLATFORM)
        AND s.COUNTRY = c.COUNTRY
)

-- Attach SKAN installs with country-aware join
-- SKAN gets its own rows per inferred country; they match to spend/cohort rows
-- on the same country, or create new rows if no spend/cohort exists for that country
, with_skan AS (
    SELECT
        COALESCE(cb.DATE, sk.INSTALL_DATE) AS DATE
        , COALESCE(cb.AD_PARTNER, sk.AD_PARTNER) AS AD_PARTNER
        , cb.NETWORK_NAME
        , COALESCE(cb.CAMPAIGN_NAME, sk.CAMPAIGN_NAME) AS CAMPAIGN_NAME
        , cb.CAMPAIGN_ID
        , COALESCE(cb.PLATFORM, 'iOS') AS PLATFORM
        , COALESCE(cb.COUNTRY, sk.INFERRED_COUNTRY, '__none__') AS COUNTRY

        -- Spend metrics
        , COALESCE(cb.COST, 0) AS COST
        , COALESCE(cb.CLICKS, 0) AS CLICKS
        , COALESCE(cb.IMPRESSIONS, 0) AS IMPRESSIONS
        , COALESCE(cb.ADJUST_INSTALLS, 0) AS ADJUST_INSTALLS

        -- Cohort metrics
        , COALESCE(cb.ATTRIBUTION_INSTALLS, 0) AS ATTRIBUTION_INSTALLS

        -- Total Revenue
        , COALESCE(cb.TOTAL_REVENUE, 0) AS TOTAL_REVENUE
        , COALESCE(cb.D7_REVENUE, 0) AS D7_REVENUE
        , COALESCE(cb.D30_REVENUE, 0) AS D30_REVENUE

        -- Purchase Revenue
        , COALESCE(cb.TOTAL_PURCHASE_REVENUE, 0) AS TOTAL_PURCHASE_REVENUE
        , COALESCE(cb.D7_PURCHASE_REVENUE, 0) AS D7_PURCHASE_REVENUE
        , COALESCE(cb.D30_PURCHASE_REVENUE, 0) AS D30_PURCHASE_REVENUE

        -- Ad Revenue
        , COALESCE(cb.TOTAL_AD_REVENUE, 0) AS TOTAL_AD_REVENUE
        , COALESCE(cb.D7_AD_REVENUE, 0) AS D7_AD_REVENUE
        , COALESCE(cb.D30_AD_REVENUE, 0) AS D30_AD_REVENUE

        -- Paying users
        , COALESCE(cb.TOTAL_PAYING_USERS, 0) AS TOTAL_PAYING_USERS
        , COALESCE(cb.D7_PAYING_USERS, 0) AS D7_PAYING_USERS
        , COALESCE(cb.D30_PAYING_USERS, 0) AS D30_PAYING_USERS

        -- Retention
        , COALESCE(cb.D1_RETAINED_USERS, 0) AS D1_RETAINED_USERS
        , COALESCE(cb.D7_RETAINED_USERS, 0) AS D7_RETAINED_USERS
        , COALESCE(cb.D30_RETAINED_USERS, 0) AS D30_RETAINED_USERS
        , COALESCE(cb.D1_MATURED_USERS, 0) AS D1_MATURED_USERS
        , COALESCE(cb.D7_MATURED_USERS, 0) AS D7_MATURED_USERS
        , COALESCE(cb.D30_MATURED_USERS, 0) AS D30_MATURED_USERS

        -- SKAN installs (iOS only)
        , COALESCE(sk.NEW_INSTALL_COUNT, 0) AS SKAN_INSTALLS

    FROM combined cb
    FULL OUTER JOIN skan_data sk
        ON cb.DATE = sk.INSTALL_DATE
        AND LOWER(cb.AD_PARTNER) = LOWER(sk.AD_PARTNER)
        AND LOWER(cb.CAMPAIGN_NAME) = LOWER(sk.CAMPAIGN_NAME)
        AND LOWER(cb.PLATFORM) = 'ios'
        AND cb.COUNTRY = sk.INFERRED_COUNTRY
)

SELECT
    DATE
    , AD_PARTNER
    , CASE
        WHEN AD_PARTNER IN ('Meta', 'Google', 'Apple', 'AppLovin', 'Moloco', 'Unity', 'TikTok', 'Smadex') THEN AD_PARTNER
        WHEN AD_PARTNER = 'Organic' THEN 'Organic'
        WHEN AD_PARTNER = 'Unattributed' THEN 'Unattributed'
        WHEN AD_PARTNER LIKE '%Vungle%' THEN 'Vungle'
        WHEN AD_PARTNER LIKE '%Liftoff%' OR AD_PARTNER LIKE '%liftoff%' THEN 'Liftoff'
        WHEN AD_PARTNER LIKE '%Chartboost%' OR AD_PARTNER LIKE '%chartboost%' THEN 'Chartboost'
        WHEN AD_PARTNER LIKE '%AdColony%' OR AD_PARTNER LIKE '%adcolony%' THEN 'AdColony'
        WHEN AD_PARTNER LIKE '%AdAction%' THEN 'AdAction'
        WHEN AD_PARTNER LIKE '%ironSource%' THEN 'ironSource'
        WHEN AD_PARTNER LIKE '%Cross%Install%' OR AD_PARTNER LIKE '%cross%install%' THEN 'Cross-Install'
        WHEN AD_PARTNER LIKE '%Tapjoy%' THEN 'Tapjoy'
        WHEN AD_PARTNER LIKE '%Topgolf%' THEN 'Topgolf (Internal)'
        WHEN AD_PARTNER LIKE '%applift%' OR AD_PARTNER LIKE '%Applift%' OR AD_PARTNER LIKE '%AppLift%' THEN 'AppLift'
        WHEN AD_PARTNER LIKE '%Google%' THEN 'Google'
        WHEN AD_PARTNER LIKE 'Untrusted%' THEN 'Untrusted Devices'
        WHEN AD_PARTNER IS NULL THEN 'Unknown'
        ELSE 'Other'
      END AS AD_PARTNER_GROUPED
    , COALESCE(NETWORK_NAME, '__none__') AS NETWORK_NAME
    , COALESCE(CAMPAIGN_NAME, '__none__') AS CAMPAIGN_NAME
    , COALESCE(CAMPAIGN_ID, '__none__') AS CAMPAIGN_ID
    , PLATFORM
    , COALESCE(COUNTRY, '__none__') AS COUNTRY

    -- Core spend metrics
    , COST
    , CLICKS
    , IMPRESSIONS

    -- Install metrics
    , ADJUST_INSTALLS
    , SKAN_INSTALLS
    , ADJUST_INSTALLS + SKAN_INSTALLS AS TOTAL_INSTALLS
    , ATTRIBUTION_INSTALLS

    -- Efficiency metrics (denominator = Adjust Installs for spend-side KPIs)
    , CASE WHEN ADJUST_INSTALLS > 0
        THEN COST / ADJUST_INSTALLS
        ELSE NULL END AS CPI

    , CASE WHEN IMPRESSIONS > 0
        THEN (COST / IMPRESSIONS) * 1000
        ELSE NULL END AS CPM

    , CASE WHEN IMPRESSIONS > 0
        THEN CLICKS / IMPRESSIONS
        ELSE NULL END AS CTR

    , CASE WHEN CLICKS > 0
        THEN ADJUST_INSTALLS::FLOAT / CLICKS
        ELSE NULL END AS CVR

    , CASE WHEN IMPRESSIONS > 0
        THEN (ADJUST_INSTALLS::FLOAT / IMPRESSIONS) * 1000
        ELSE NULL END AS IPM

    -- Total Revenue (Purchase + Ad)
    , TOTAL_REVENUE
    , D7_REVENUE
    , D30_REVENUE

    -- Purchase Revenue (IAP)
    , TOTAL_PURCHASE_REVENUE
    , D7_PURCHASE_REVENUE
    , D30_PURCHASE_REVENUE

    -- Ad Revenue
    , TOTAL_AD_REVENUE
    , D7_AD_REVENUE
    , D30_AD_REVENUE

    -- ROAS (based on total revenue)
    , CASE WHEN COST > 0 THEN TOTAL_REVENUE / COST ELSE NULL END AS TOTAL_ROAS
    , CASE WHEN COST > 0 THEN D7_REVENUE / COST ELSE NULL END AS D7_ROAS
    , CASE WHEN COST > 0 THEN D30_REVENUE / COST ELSE NULL END AS D30_ROAS

    -- ARPI (Average Revenue Per Install — uses Adjust Installs)
    , CASE WHEN ADJUST_INSTALLS > 0
        THEN TOTAL_REVENUE / ADJUST_INSTALLS
        ELSE NULL END AS ARPI
    , CASE WHEN ADJUST_INSTALLS > 0
        THEN D7_REVENUE / ADJUST_INSTALLS
        ELSE NULL END AS D7_ARPI
    , CASE WHEN ADJUST_INSTALLS > 0
        THEN D30_REVENUE / ADJUST_INSTALLS
        ELSE NULL END AS D30_ARPI

    -- Paying users
    , TOTAL_PAYING_USERS
    , D7_PAYING_USERS
    , D30_PAYING_USERS

    -- ARPPU (Average Revenue Per Paying User)
    , CASE WHEN TOTAL_PAYING_USERS > 0
        THEN TOTAL_REVENUE / TOTAL_PAYING_USERS
        ELSE NULL END AS ARPPU
    , CASE WHEN D7_PAYING_USERS > 0
        THEN D7_REVENUE / D7_PAYING_USERS
        ELSE NULL END AS D7_ARPPU
    , CASE WHEN D30_PAYING_USERS > 0
        THEN D30_REVENUE / D30_PAYING_USERS
        ELSE NULL END AS D30_ARPPU

    -- Cost Per Paying User
    , CASE WHEN TOTAL_PAYING_USERS > 0
        THEN COST / TOTAL_PAYING_USERS
        ELSE NULL END AS COST_PER_PAYING_USER
    , CASE WHEN D7_PAYING_USERS > 0
        THEN COST / D7_PAYING_USERS
        ELSE NULL END AS D7_COST_PER_PAYING_USER
    , CASE WHEN D30_PAYING_USERS > 0
        THEN COST / D30_PAYING_USERS
        ELSE NULL END AS D30_COST_PER_PAYING_USER

    -- Retention raw counts
    , D1_RETAINED_USERS
    , D7_RETAINED_USERS
    , D30_RETAINED_USERS
    , D1_MATURED_USERS
    , D7_MATURED_USERS
    , D30_MATURED_USERS

    -- Retention rates
    , CASE WHEN D1_MATURED_USERS > 0
        THEN D1_RETAINED_USERS::FLOAT / D1_MATURED_USERS
        ELSE NULL END AS D1_RETENTION
    , CASE WHEN D7_MATURED_USERS > 0
        THEN D7_RETAINED_USERS::FLOAT / D7_MATURED_USERS
        ELSE NULL END AS D7_RETENTION
    , CASE WHEN D30_MATURED_USERS > 0
        THEN D30_RETAINED_USERS::FLOAT / D30_MATURED_USERS
        ELSE NULL END AS D30_RETENTION

FROM with_skan
WHERE DATE IS NOT NULL
