{{
    config(
        materialized='view'
    )
}}

/*
    Unified spend model combining four sources:
    1. Fivetran Facebook (web/desktop ad account — no overlap with Adjust mobile campaigns)
    2. Fivetran Google (all rows — preferred over Adjust for overlapping campaigns)
    3. Adjust API granular (mobile Meta + Google campaigns needing campaign-ID dedup)
    4. Adjust API network-level (all other networks — accurate totals, no fragmentation)

    Dedup logic:
    - Meta: Fivetran has web/desktop account, Adjust granular has mobile accounts — zero overlap, include both
    - Google: Fivetran preferred where campaign IDs overlap; Adjust granular fills the rest
    - All others: Adjust network-level endpoint (4 dimensions, matches dashboard)

    Grain: DATE + SOURCE + CHANNEL + CAMPAIGN_ID + PLATFORM
*/

WITH fb_spend AS (
    SELECT
        DATE
        , 'fivetran_facebook' AS SOURCE
        , 'Meta' AS CHANNEL
        , AD_ID::VARCHAR AS CAMPAIGN_ID
        , CAMPAIGN AS CAMPAIGN_NAME
        , NULL AS PLATFORM
        , SPEND
        , IMPRESSIONS
        , CLICKS
        , NULL::NUMBER AS PAID_INSTALLS
        , NULL::NUMBER AS PAID_CLICKS
        , NULL::NUMBER AS PAID_IMPRESSIONS
        , NULL::NUMBER AS SESSIONS
        , NULL::NUMBER AS REATTRIBUTIONS
    FROM {{ ref('v_stg_facebook_spend') }}
),

google_spend AS (
    SELECT
        DATE
        , 'fivetran_google' AS SOURCE
        , 'Google' AS CHANNEL
        , CAMPAIGN_ID::VARCHAR AS CAMPAIGN_ID
        , CAMPAIGN_NAME
        , NULL AS PLATFORM
        , SPEND
        , IMPRESSIONS
        , CLICKS
        , NULL::NUMBER AS PAID_INSTALLS
        , NULL::NUMBER AS PAID_CLICKS
        , NULL::NUMBER AS PAID_IMPRESSIONS
        , NULL::NUMBER AS SESSIONS
        , NULL::NUMBER AS REATTRIBUTIONS
    FROM {{ ref('v_stg_google_ads__spend') }}
),

-- Collect campaign IDs from Fivetran sources for dedup against Adjust
google_campaign_ids AS (
    SELECT DISTINCT CAMPAIGN_ID
    FROM google_spend
),

fb_campaign_ids AS (
    SELECT DISTINCT CAMPAIGN_ID
    FROM fb_spend
),

-- Granular Adjust API: only Meta and Google (need campaign-ID dedup against Fivetran)
adjust_spend AS (
    SELECT
        s.DATE
        , 'adjust_api' AS SOURCE
        , COALESCE(nm.AD_PARTNER, s.PARTNER_NAME) AS CHANNEL
        , s.CAMPAIGN_ID_NETWORK AS CAMPAIGN_ID
        , s.CAMPAIGN_NETWORK AS CAMPAIGN_NAME
        , s.PLATFORM
        , s.NETWORK_COST AS SPEND
        , s.IMPRESSIONS
        , s.CLICKS
        , NULL::NUMBER AS PAID_INSTALLS
        , NULL::NUMBER AS PAID_CLICKS
        , NULL::NUMBER AS PAID_IMPRESSIONS
        , NULL::NUMBER AS SESSIONS
        , NULL::NUMBER AS REATTRIBUTIONS
    FROM {{ ref('stg_adjust__report_daily') }} s
    LEFT JOIN {{ ref('network_mapping') }} nm
        ON s.PARTNER_NAME = nm.ADJUST_NETWORK_NAME
    WHERE s.DATE IS NOT NULL
      AND s.NETWORK_COST > 0
      -- Only keep Meta and Google from granular endpoint (campaign-ID dedup needed)
      AND (
          COALESCE(nm.AD_PARTNER, '') IN ('Meta', 'Google')
          OR LOWER(s.PARTNER_NAME) LIKE '%facebook%'
          OR LOWER(s.PARTNER_NAME) LIKE '%instagram%'
          OR LOWER(s.PARTNER_NAME) LIKE '%google%'
      )
      -- Exclude Meta campaigns that already exist in Fivetran Facebook (dedup by campaign ID)
      AND NOT (
          (COALESCE(nm.AD_PARTNER, '') = 'Meta' OR LOWER(s.PARTNER_NAME) LIKE '%facebook%' OR LOWER(s.PARTNER_NAME) LIKE '%instagram%')
          AND s.CAMPAIGN_ID_NETWORK IN (SELECT CAMPAIGN_ID FROM fb_campaign_ids)
      )
      -- Exclude Google campaigns that already exist in Fivetran Google (dedup by campaign ID)
      AND NOT (
          (COALESCE(nm.AD_PARTNER, '') = 'Google' OR LOWER(s.PARTNER_NAME) LIKE '%google%')
          AND s.CAMPAIGN_ID_NETWORK IN (SELECT CAMPAIGN_ID FROM google_campaign_ids)
      )
),

-- Network-level Adjust API: all channels except Meta and Google
-- Uses 4-dimension endpoint that matches Adjust dashboard (no data fragmentation)
network_adjust_spend AS (
    SELECT
        s.DATE
        , 'adjust_api_network' AS SOURCE
        , COALESCE(nm.AD_PARTNER, s.PARTNER_NAME) AS CHANNEL
        , NULL AS CAMPAIGN_ID
        , NULL AS CAMPAIGN_NAME
        , s.PLATFORM
        , s.NETWORK_COST AS SPEND
        , s.IMPRESSIONS
        , s.CLICKS
        , s.PAID_INSTALLS
        , s.PAID_CLICKS
        , s.PAID_IMPRESSIONS
        , s.SESSIONS
        , s.REATTRIBUTIONS
    FROM {{ ref('stg_adjust__report_daily_network') }} s
    LEFT JOIN {{ ref('network_mapping') }} nm
        ON s.PARTNER_NAME = nm.ADJUST_NETWORK_NAME
    WHERE s.DATE IS NOT NULL
      AND s.NETWORK_COST > 0
      AND COALESCE(nm.AD_PARTNER, s.PARTNER_NAME) NOT IN ('Meta', 'Google')
)

SELECT * FROM fb_spend
UNION ALL
SELECT * FROM google_spend
UNION ALL
SELECT * FROM adjust_spend
UNION ALL
SELECT * FROM network_adjust_spend
