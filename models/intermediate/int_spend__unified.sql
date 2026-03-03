{{
    config(
        materialized='view'
    )
}}

/*
    Unified spend model combining three sources:
    1. Fivetran Facebook (all rows — zero campaign overlap with Adjust)
    2. Fivetran Google (all rows — preferred over Adjust for overlapping campaigns)
    3. Adjust API (excluding Meta entirely + overlapping Google campaigns)

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
    FROM {{ ref('v_stg_google_ads__spend') }}
),

-- Collect Google campaign IDs for dedup against Adjust
google_campaign_ids AS (
    SELECT DISTINCT CAMPAIGN_ID
    FROM google_spend
),

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
    FROM {{ ref('stg_adjust__report_daily') }} s
    LEFT JOIN {{ ref('network_mapping') }} nm
        ON s.PARTNER_NAME = nm.ADJUST_NETWORK_NAME
    WHERE s.DATE IS NOT NULL
      AND s.NETWORK_COST > 0
      -- Exclude all Meta spend (different ad accounts, Fivetran is source of truth)
      AND COALESCE(nm.AD_PARTNER, '') != 'Meta'
      -- Exclude overlapping Google campaigns (Fivetran preferred)
      AND NOT (
          COALESCE(nm.AD_PARTNER, '') = 'Google'
          AND s.CAMPAIGN_ID_NETWORK IN (SELECT CAMPAIGN_ID FROM google_campaign_ids)
      )
)

SELECT * FROM fb_spend
UNION ALL
SELECT * FROM google_spend
UNION ALL
SELECT * FROM adjust_spend
