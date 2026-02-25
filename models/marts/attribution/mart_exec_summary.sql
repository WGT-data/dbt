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

-- Country code ↔ name mapping (used for both spend name→code and final code→name)
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
        ('ke', 'Kenya'),
        ('tr', 'Turkey'),
        ('ua', 'Ukraine'),
        ('cl', 'Chile'),
        ('pe', 'Peru'),
        ('ec', 'Ecuador'),
        ('cr', 'Costa Rica'),
        ('pa', 'Panama'),
        ('gt', 'Guatemala'),
        ('sv', 'El Salvador'),
        ('hn', 'Honduras'),
        ('ni', 'Nicaragua'),
        ('bo', 'Bolivia'),
        ('py', 'Paraguay'),
        ('uy', 'Uruguay'),
        ('ve', 'Venezuela'),
        ('tt', 'Trinidad and Tobago'),
        ('jm', 'Jamaica'),
        ('tz', 'Tanzania'),
        ('ug', 'Uganda'),
        ('gh', 'Ghana'),
        ('et', 'Ethiopia'),
        ('np', 'Nepal'),
        ('lk', 'Sri Lanka'),
        ('pk', 'Pakistan'),
        ('bd', 'Bangladesh'),
        ('kh', 'Cambodia'),
        ('mm', 'Myanmar'),
        ('la', 'Laos'),
        ('hr', 'Croatia'),
        ('rs', 'Serbia'),
        ('bg', 'Bulgaria'),
        ('si', 'Slovenia'),
        ('sk', 'Slovakia'),
        ('lt', 'Lithuania'),
        ('lv', 'Latvia'),
        ('ee', 'Estonia'),
        ('cy', 'Cyprus'),
        ('mt', 'Malta'),
        ('lu', 'Luxembourg'),
        ('is', 'Iceland'),
        ('ba', 'Bosnia and Herzegovina'),
        ('mk', 'North Macedonia'),
        ('al', 'Albania'),
        ('me', 'Montenegro'),
        ('md', 'Moldova'),
        ('ge', 'Georgia'),
        ('am', 'Armenia'),
        ('az', 'Azerbaijan'),
        ('kz', 'Kazakhstan'),
        ('uz', 'Uzbekistan'),
        ('qa', 'Qatar'),
        ('kw', 'Kuwait'),
        ('bh', 'Bahrain'),
        ('om', 'Oman'),
        ('jo', 'Jordan'),
        ('lb', 'Lebanon'),
        ('iq', 'Iraq'),
        ('ma', 'Morocco'),
        ('tn', 'Tunisia'),
        ('dz', 'Algeria'),
        ('ly', 'Libya'),
        ('mo', 'Macau'),
        ('mn', 'Mongolia'),
        ('fj', 'Fiji'),
        ('pg', 'Papua New Guinea'),
        ('rw', 'Rwanda'),
        ('cm', 'Cameroon'),
        ('sn', 'Senegal'),
        ('ci', 'Ivory Coast'),
        ('mg', 'Madagascar'),
        ('mz', 'Mozambique'),
        ('zm', 'Zambia'),
        ('zw', 'Zimbabwe'),
        ('bw', 'Botswana'),
        ('na', 'Namibia'),
        ('mu', 'Mauritius'),
        ('mw', 'Malawi'),
        ('unknown', 'Unknown')
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
         , SUM(s.ALL_REVENUE) AS ADJUST_TOTAL_REVENUE
         , SUM(s.REVENUE) AS ADJUST_PURCHASE_REVENUE
         , SUM(s.AD_REVENUE) AS ADJUST_AD_REVENUE
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
            REPLACE(
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
            , 'UK', 'GB')  -- normalize UK → GB (ISO standard)
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

        -- Revenue from Adjust API (event-date based, more complete)
        , COALESCE(s.ADJUST_TOTAL_REVENUE, 0) AS TOTAL_REVENUE
        , COALESCE(s.ADJUST_PURCHASE_REVENUE, 0) AS TOTAL_PURCHASE_REVENUE
        , COALESCE(s.ADJUST_AD_REVENUE, 0) AS TOTAL_AD_REVENUE

        -- Cohort revenue (install-date based, D7/D30 windows)
        , COALESCE(c.D7_REVENUE, 0) AS D7_REVENUE
        , COALESCE(c.D30_REVENUE, 0) AS D30_REVENUE
        , COALESCE(c.D7_PURCHASE_REVENUE, 0) AS D7_PURCHASE_REVENUE
        , COALESCE(c.D30_PURCHASE_REVENUE, 0) AS D30_PURCHASE_REVENUE
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

        -- Revenue from Adjust API (event-date based)
        , COALESCE(cb.TOTAL_REVENUE, 0) AS TOTAL_REVENUE
        , COALESCE(cb.TOTAL_PURCHASE_REVENUE, 0) AS TOTAL_PURCHASE_REVENUE
        , COALESCE(cb.TOTAL_AD_REVENUE, 0) AS TOTAL_AD_REVENUE

        -- Cohort revenue (D7/D30 windows)
        , COALESCE(cb.D7_REVENUE, 0) AS D7_REVENUE
        , COALESCE(cb.D30_REVENUE, 0) AS D30_REVENUE
        , COALESCE(cb.D7_PURCHASE_REVENUE, 0) AS D7_PURCHASE_REVENUE
        , COALESCE(cb.D30_PURCHASE_REVENUE, 0) AS D30_PURCHASE_REVENUE
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
    ws.DATE
    , ws.AD_PARTNER
    , CASE
        WHEN ws.AD_PARTNER IN ('Meta', 'Google', 'Apple', 'AppLovin', 'Moloco', 'Unity', 'TikTok', 'Smadex') THEN ws.AD_PARTNER
        WHEN ws.AD_PARTNER = 'Organic' THEN 'Organic'
        WHEN ws.AD_PARTNER = 'Unattributed' THEN 'Unattributed'
        WHEN ws.AD_PARTNER LIKE '%Vungle%' THEN 'Vungle'
        WHEN ws.AD_PARTNER LIKE '%Liftoff%' OR ws.AD_PARTNER LIKE '%liftoff%' THEN 'Liftoff'
        WHEN ws.AD_PARTNER LIKE '%Chartboost%' OR ws.AD_PARTNER LIKE '%chartboost%' THEN 'Chartboost'
        WHEN ws.AD_PARTNER LIKE '%AdColony%' OR ws.AD_PARTNER LIKE '%adcolony%' THEN 'AdColony'
        WHEN ws.AD_PARTNER LIKE '%AdAction%' THEN 'AdAction'
        WHEN ws.AD_PARTNER LIKE '%ironSource%' THEN 'ironSource'
        WHEN ws.AD_PARTNER LIKE '%Cross%Install%' OR ws.AD_PARTNER LIKE '%cross%install%' THEN 'Cross-Install'
        WHEN ws.AD_PARTNER LIKE '%Tapjoy%' THEN 'Tapjoy'
        WHEN ws.AD_PARTNER LIKE '%Topgolf%' THEN 'Topgolf (Internal)'
        WHEN ws.AD_PARTNER LIKE '%applift%' OR ws.AD_PARTNER LIKE '%Applift%' OR ws.AD_PARTNER LIKE '%AppLift%' THEN 'AppLift'
        WHEN ws.AD_PARTNER LIKE '%Google%' THEN 'Google'
        WHEN ws.AD_PARTNER LIKE 'Untrusted%' THEN 'Untrusted Devices'
        WHEN ws.AD_PARTNER IS NULL THEN 'Unknown'
        ELSE 'Other'
      END AS AD_PARTNER_GROUPED
    , COALESCE(ws.NETWORK_NAME, '__none__') AS NETWORK_NAME
    , COALESCE(ws.CAMPAIGN_NAME, '__none__') AS CAMPAIGN_NAME
    , COALESCE(ws.CAMPAIGN_ID, '__none__') AS CAMPAIGN_ID
    , ws.PLATFORM
    , COALESCE(cn.name, UPPER(ws.COUNTRY), '__none__') AS COUNTRY

    -- Date grain columns (for Power BI granularity selector)
    , DATE_TRUNC('week', ws.DATE)::DATE AS WEEK_START
    , DATE_TRUNC('month', ws.DATE)::DATE AS MONTH_START
    , DATE_TRUNC('quarter', ws.DATE)::DATE AS QUARTER_START
    , DATE_TRUNC('year', ws.DATE)::DATE AS YEAR_START

    -- Core spend metrics
    , ws.COST
    , ws.CLICKS
    , ws.IMPRESSIONS

    -- Install metrics
    , ws.ADJUST_INSTALLS
    , ws.SKAN_INSTALLS
    , ws.ADJUST_INSTALLS + ws.SKAN_INSTALLS AS TOTAL_INSTALLS
    , ws.ATTRIBUTION_INSTALLS

    -- Efficiency metrics (denominator = Adjust + SKAN Installs)
    , CASE WHEN (ws.ADJUST_INSTALLS + ws.SKAN_INSTALLS) > 0
        THEN ws.COST / (ws.ADJUST_INSTALLS + ws.SKAN_INSTALLS)
        ELSE NULL END AS CPI

    , CASE WHEN ws.IMPRESSIONS > 0
        THEN (ws.COST / ws.IMPRESSIONS) * 1000
        ELSE NULL END AS CPM

    , CASE WHEN ws.IMPRESSIONS > 0
        THEN ws.CLICKS / ws.IMPRESSIONS
        ELSE NULL END AS CTR

    , CASE WHEN ws.CLICKS > 0
        THEN (ws.ADJUST_INSTALLS + ws.SKAN_INSTALLS)::FLOAT / ws.CLICKS
        ELSE NULL END AS CVR

    , CASE WHEN ws.IMPRESSIONS > 0
        THEN ((ws.ADJUST_INSTALLS + ws.SKAN_INSTALLS)::FLOAT / ws.IMPRESSIONS) * 1000
        ELSE NULL END AS IPM

    -- Revenue from Adjust API (event-date based, more complete coverage)
    , ws.TOTAL_REVENUE
    , ws.TOTAL_PURCHASE_REVENUE
    , ws.TOTAL_AD_REVENUE

    -- Cohort revenue (install-date based D7/D30 windows, device-matched only)
    , ws.D7_REVENUE
    , ws.D30_REVENUE
    , ws.D7_PURCHASE_REVENUE
    , ws.D30_PURCHASE_REVENUE
    , ws.D7_AD_REVENUE
    , ws.D30_AD_REVENUE

    -- ROAS (based on total revenue)
    , CASE WHEN ws.COST > 0 THEN ws.TOTAL_REVENUE / ws.COST ELSE NULL END AS TOTAL_ROAS
    , CASE WHEN ws.COST > 0 THEN ws.D7_REVENUE / ws.COST ELSE NULL END AS D7_ROAS
    , CASE WHEN ws.COST > 0 THEN ws.D30_REVENUE / ws.COST ELSE NULL END AS D30_ROAS

    -- ARPI (Average Revenue Per Install — uses Adjust + SKAN Installs)
    , CASE WHEN (ws.ADJUST_INSTALLS + ws.SKAN_INSTALLS) > 0
        THEN ws.TOTAL_REVENUE / (ws.ADJUST_INSTALLS + ws.SKAN_INSTALLS)
        ELSE NULL END AS ARPI
    , CASE WHEN (ws.ADJUST_INSTALLS + ws.SKAN_INSTALLS) > 0
        THEN ws.D7_REVENUE / (ws.ADJUST_INSTALLS + ws.SKAN_INSTALLS)
        ELSE NULL END AS D7_ARPI
    , CASE WHEN (ws.ADJUST_INSTALLS + ws.SKAN_INSTALLS) > 0
        THEN ws.D30_REVENUE / (ws.ADJUST_INSTALLS + ws.SKAN_INSTALLS)
        ELSE NULL END AS D30_ARPI

    -- Paying users
    , ws.TOTAL_PAYING_USERS
    , ws.D7_PAYING_USERS
    , ws.D30_PAYING_USERS

    -- ARPPU (Average Revenue Per Paying User)
    , CASE WHEN ws.TOTAL_PAYING_USERS > 0
        THEN ws.TOTAL_REVENUE / ws.TOTAL_PAYING_USERS
        ELSE NULL END AS ARPPU
    , CASE WHEN ws.D7_PAYING_USERS > 0
        THEN ws.D7_REVENUE / ws.D7_PAYING_USERS
        ELSE NULL END AS D7_ARPPU
    , CASE WHEN ws.D30_PAYING_USERS > 0
        THEN ws.D30_REVENUE / ws.D30_PAYING_USERS
        ELSE NULL END AS D30_ARPPU

    -- Cost Per Paying User
    , CASE WHEN ws.TOTAL_PAYING_USERS > 0
        THEN ws.COST / ws.TOTAL_PAYING_USERS
        ELSE NULL END AS COST_PER_PAYING_USER
    , CASE WHEN ws.D7_PAYING_USERS > 0
        THEN ws.COST / ws.D7_PAYING_USERS
        ELSE NULL END AS D7_COST_PER_PAYING_USER
    , CASE WHEN ws.D30_PAYING_USERS > 0
        THEN ws.COST / ws.D30_PAYING_USERS
        ELSE NULL END AS D30_COST_PER_PAYING_USER

    -- Retention raw counts
    , ws.D1_RETAINED_USERS
    , ws.D7_RETAINED_USERS
    , ws.D30_RETAINED_USERS
    , ws.D1_MATURED_USERS
    , ws.D7_MATURED_USERS
    , ws.D30_MATURED_USERS

    -- Retention rates
    , CASE WHEN ws.D1_MATURED_USERS > 0
        THEN ws.D1_RETAINED_USERS::FLOAT / ws.D1_MATURED_USERS
        ELSE NULL END AS D1_RETENTION
    , CASE WHEN ws.D7_MATURED_USERS > 0
        THEN ws.D7_RETAINED_USERS::FLOAT / ws.D7_MATURED_USERS
        ELSE NULL END AS D7_RETENTION
    , CASE WHEN ws.D30_MATURED_USERS > 0
        THEN ws.D30_RETAINED_USERS::FLOAT / ws.D30_MATURED_USERS
        ELSE NULL END AS D30_RETENTION

FROM with_skan ws
LEFT JOIN country_code_map cn ON ws.COUNTRY = cn.code
WHERE ws.DATE IS NOT NULL
