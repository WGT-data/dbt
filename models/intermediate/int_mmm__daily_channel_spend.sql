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

    Source: Supermetrics adj_campaign (primary spend data source)
    Channel mapping: network_mapping seed for consistent AD_PARTNER taxonomy
    Grain: one row per DATE + PLATFORM + CHANNEL

    Note: This model uses only Supermetrics data to avoid double-counting spend
    (Adjust API also has cost data but overlaps with Supermetrics for most partners)
*/

WITH spend_with_channel AS (
    SELECT
        s.DATE,
        s.PLATFORM,
        COALESCE(nm.AD_PARTNER, 'Other') AS CHANNEL,
        SUM(s.COST) AS SPEND,
        SUM(s.IMPRESSIONS) AS IMPRESSIONS,
        SUM(s.CLICKS) AS CLICKS,
        SUM(s.PAID_INSTALLS) AS PAID_INSTALLS
    FROM {{ ref('stg_supermetrics__adj_campaign') }} s
    -- Note: Snowflake treats unquoted identifiers as case-insensitive.
    -- The seed CSV has lowercase headers (supermetrics_partner_name) but since
    -- quote_columns is not set in dbt_project.yml, Snowflake uppercases them
    -- internally. Using UPPERCASE here for project consistency.
    LEFT JOIN {{ ref('network_mapping') }} nm
        ON s.PARTNER_NAME = nm.SUPERMETRICS_PARTNER_NAME
    WHERE s.DATE IS NOT NULL
      AND s.COST > 0
    {% if is_incremental() %}
      AND s.DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3
)

SELECT
    DATE,
    PLATFORM,
    CHANNEL,
    SPEND,
    IMPRESSIONS,
    CLICKS,
    PAID_INSTALLS
FROM spend_with_channel
