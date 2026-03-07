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

    Sources:
    - Adjust API (stg_adjust__report_daily): iOS/Android revenue with campaign attribution
    - WGT.EVENTS.REVENUE + Web MTA: Desktop/web revenue attributed via multi-touch model

    Channel mapping:
    - Mobile: network_mapping seed (Adjust partner → AD_PARTNER)
    - Desktop: web MTA touchpoint credits with GCLID/FBCLID for paid attribution
      (matches mobile: paid clicks → partner channel, everything else → Organic)
    - Desktop users without MTA data → 'Unattributed'

    Grain: one row per DATE + PLATFORM + CHANNEL

    Adjust API revenue is revenue-event-date based (not install-cohort-date based).
    Desktop revenue is also event-date based, distributed across channels by MTA credit weight.
    This is acceptable for MMM because MMM uses aggregate time series and infers
    relationships statistically — install-to-revenue lag is captured implicitly
    in adstock/lag parameters.
*/

-- Mobile revenue from Adjust API (iOS/Android, campaign-attributed)
WITH mobile_revenue AS (
    SELECT
        r.DATE,
        r.PLATFORM,
        COALESCE(nm.AD_PARTNER, 'Other') AS CHANNEL,
        SUM(r.REVENUE) AS REVENUE,
        SUM(r.ALL_REVENUE) AS ALL_REVENUE,
        SUM(r.AD_REVENUE) AS AD_REVENUE,
        SUM(r.INSTALLS) AS API_INSTALLS
    FROM {{ ref('stg_adjust__report_daily') }} r
    LEFT JOIN {{ ref('network_mapping') }} nm
        ON r.PARTNER_NAME = nm.ADJUST_NETWORK_NAME
    WHERE r.DATE IS NOT NULL
      AND r.PLATFORM IN ('iOS', 'Android')
    {% if is_incremental() %}
      AND r.DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3
)

-- Web MTA: determine channel per touchpoint using GCLID/FBCLID for paid attribution,
-- then aggregate credit per user per channel (time-decay recommended model).
-- This matches mobile behavior: paid clicks → partner channel, everything else → Organic.
, web_user_channel_raw AS (
    SELECT
        GAME_USER_ID,
        CASE
            WHEN GCLID IS NOT NULL THEN 'Google'
            WHEN FBCLID IS NOT NULL THEN 'Meta'
            WHEN LOWER(TRAFFIC_SOURCE) IN ('facebook', 'fb', 'instagram', 'meta') THEN 'Meta'
            WHEN LOWER(TRAFFIC_SOURCE) IN ('google', 'googleads') THEN 'Google'
            WHEN LOWER(TRAFFIC_SOURCE) IN ('tiktok') THEN 'TikTok'
            WHEN LOWER(TRAFFIC_SOURCE) IN ('apple') THEN 'Apple'
            WHEN LOWER(TRAFFIC_SOURCE) IN ('unity') THEN 'Unity'
            WHEN LOWER(TRAFFIC_SOURCE) IN ('applovin') THEN 'AppLovin'
            ELSE 'Organic'
        END AS CHANNEL,
        SUM(CREDIT_RECOMMENDED) AS RAW_CREDIT
    FROM {{ ref('int_web_mta__touchpoint_credit') }}
    WHERE GAME_USER_ID IS NOT NULL
    GROUP BY 1, 2
)

-- Normalize so credits sum to 1.0 per user (handles multi-journey users)
, web_user_channel AS (
    SELECT
        GAME_USER_ID,
        CHANNEL,
        RAW_CREDIT / NULLIF(SUM(RAW_CREDIT) OVER (PARTITION BY GAME_USER_ID), 0) AS CHANNEL_WEIGHT
    FROM web_user_channel_raw
)

-- Desktop/web revenue attributed via web MTA touchpoint credits
-- Users with MTA data: revenue distributed across channels by credit weight
-- Users without MTA data: all revenue → 'Unattributed'
, desktop_revenue AS (
    SELECT
        DATE(rev.EVENTTIME) AS DATE,
        'Desktop' AS PLATFORM,
        COALESCE(wuc.CHANNEL, 'Unattributed') AS CHANNEL,
        SUM(
            CASE WHEN rev.REVENUETYPE = 'direct' THEN COALESCE(rev.REVENUE, 0) ELSE 0 END
            * COALESCE(wuc.CHANNEL_WEIGHT, 1.0)
        ) AS REVENUE,
        SUM(
            COALESCE(rev.REVENUE, 0)
            * COALESCE(wuc.CHANNEL_WEIGHT, 1.0)
        ) AS ALL_REVENUE,
        SUM(
            CASE WHEN rev.REVENUETYPE = 'indirect' THEN COALESCE(rev.REVENUE, 0) ELSE 0 END
            * COALESCE(wuc.CHANNEL_WEIGHT, 1.0)
        ) AS AD_REVENUE,
        0 AS API_INSTALLS
    FROM {{ source('events', 'REVENUE') }} rev
    LEFT JOIN web_user_channel wuc
        ON rev.USERID = wuc.GAME_USER_ID
    WHERE rev.REVENUE IS NOT NULL
      AND rev.PLATFORM NOT IN ('iOS', 'Android')
    {% if is_incremental() %}
      AND rev.EVENTTIME >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3
)

, combined AS (
    SELECT * FROM mobile_revenue
    UNION ALL
    SELECT * FROM desktop_revenue
)

SELECT
    DATE,
    PLATFORM,
    CHANNEL,
    REVENUE,
    ALL_REVENUE,
    AD_REVENUE,
    API_INSTALLS
FROM combined
