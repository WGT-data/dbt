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

    Source: v_stg_adjust__installs (device-level S3 data, more accurate than API aggregates)
    Channel mapping: AD_PARTNER from the installs view for consistent taxonomy
    Grain: one row per DATE + PLATFORM + CHANNEL

    Note: Counts distinct devices (first install only) for accurate install metrics
*/

SELECT
    DATE(INSTALL_TIMESTAMP) AS DATE,
    PLATFORM,
    AD_PARTNER AS CHANNEL,
    COUNT(DISTINCT DEVICE_ID) AS INSTALLS
FROM {{ ref('v_stg_adjust__installs') }}
WHERE INSTALL_TIMESTAMP IS NOT NULL
{% if is_incremental() %}
  AND DATE(INSTALL_TIMESTAMP) >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
{% endif %}
GROUP BY 1, 2, 3
