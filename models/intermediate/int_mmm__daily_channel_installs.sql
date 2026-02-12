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

    Sources:
    - v_stg_adjust__installs: Device-level S3 data (all platforms)
    - int_skan__aggregate_attribution: SKAdNetwork postbacks (iOS only)

    SKAN installs represent ~15-20% of daily iOS installs from users who did
    not consent to ATT tracking. Without SKAN, iOS installs are undercounted.
    S3 and SKAN are non-overlapping (S3 uses device IDs, SKAN has no device IDs),
    so summing the two sources gives the correct total.

    Channel mapping: AD_PARTNER from installs view and SKAN model
    Grain: one row per DATE + PLATFORM + CHANNEL
*/

WITH s3_installs AS (
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
),

skan_installs AS (
    SELECT
        INSTALL_DATE AS DATE,
        'iOS' AS PLATFORM,
        AD_PARTNER AS CHANNEL,
        SUM(INSTALL_COUNT) AS INSTALLS
    FROM {{ ref('int_skan__aggregate_attribution') }}
    WHERE INSTALL_DATE IS NOT NULL
    {% if is_incremental() %}
      AND INSTALL_DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY 1, 2, 3
)

SELECT
    DATE,
    PLATFORM,
    CHANNEL,
    SUM(INSTALLS) AS INSTALLS
FROM (
    SELECT * FROM s3_installs
    UNION ALL
    SELECT * FROM skan_installs
)
GROUP BY 1, 2, 3
