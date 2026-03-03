{{
    config(
        materialized='incremental',
        unique_key=['DATE', 'PLATFORM', 'CHANNEL'],
        incremental_strategy='merge',
        tags=['mmm', 'spend']
    )
}}

/*
    Daily marketing spend aggregated by channel and platform for MMM input

    Source: Unified spend model (Adjust API + Fivetran Facebook + Fivetran Google)
    Channel mapping: Already standardized in int_spend__unified
    Grain: one row per DATE + PLATFORM + CHANNEL
*/

WITH spend_with_channel AS (
    SELECT
        DATE,
        COALESCE(PLATFORM, 'All') AS PLATFORM,
        CHANNEL,
        SUM(SPEND) AS SPEND,
        SUM(IMPRESSIONS) AS IMPRESSIONS,
        SUM(CLICKS) AS CLICKS
    FROM {{ ref('int_spend__unified') }}
    WHERE DATE IS NOT NULL
      AND SPEND > 0
    {% if is_incremental() %}
      AND DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3
)

SELECT
    DATE,
    PLATFORM,
    CHANNEL,
    SPEND,
    IMPRESSIONS,
    CLICKS
FROM spend_with_channel
