{{
    config(
        materialized='incremental',
        unique_key=['DATE', 'PLATFORM', 'CHANNEL'],
        incremental_strategy='merge',
        tags=['mmm', 'installs']
    )
}}

/*
    Daily install counts by channel and platform for MMM input

    Source: Adjust API network-level report (stg_adjust__report_daily_network)
    Channel mapping: network_mapping seed (same as spend model)
    Grain: one row per DATE + PLATFORM + CHANNEL

    Uses the network-level API endpoint (4 dimensions) instead of the granular
    endpoint (17 dimensions) because the granular API undercounts installs by
    up to 78% for some networks (Moloco, Apple, TikTok). The network-level
    totals match the Adjust dashboard exactly.
*/

SELECT
    s.DATE,
    s.PLATFORM,
    COALESCE(nm.AD_PARTNER, s.PARTNER_NAME) AS CHANNEL,
    SUM(s.INSTALLS) AS INSTALLS
FROM {{ ref('stg_adjust__report_daily_network') }} s
LEFT JOIN {{ ref('network_mapping') }} nm
    ON s.PARTNER_NAME = nm.ADJUST_NETWORK_NAME
WHERE s.DATE IS NOT NULL
  AND s.INSTALLS > 0
{% if is_incremental() %}
  AND s.DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
{% endif %}
GROUP BY 1, 2, 3
