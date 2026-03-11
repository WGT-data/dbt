{{
    config(
        materialized='incremental',
        unique_key=['DATE', 'PLATFORM', 'CHANNEL'],
        incremental_strategy='merge',
        tags=['mmm', 'skan']
    )
}}

/*
    Daily SKAN metrics aggregated by channel for MMM input (iOS only)

    Source: int_skan__aggregate_attribution (campaign-level → channel-level rollup)
    Grain: one row per DATE + PLATFORM('iOS') + CHANNEL

    IMPORTANT: SKAN installs overlap with device-level installs — do NOT sum
    these with INSTALLS from int_mmm__daily_channel_installs for total counts.
*/

SELECT
    INSTALL_DATE AS DATE,
    'iOS' AS PLATFORM,
    AD_PARTNER AS CHANNEL,
    SUM(INSTALL_COUNT) AS SKAN_INSTALLS,
    SUM(NEW_INSTALL_COUNT) AS SKAN_NEW_INSTALLS,
    SUM(REDOWNLOAD_COUNT) AS SKAN_REDOWNLOADS,
    AVG(AVG_CONVERSION_VALUE) AS SKAN_AVG_CV,
    SUM(INSTALLS_WITH_CV) AS SKAN_INSTALLS_WITH_CV,
    SUM(CV_BUCKET_0) AS SKAN_CV_BUCKET_0,
    SUM(CV_BUCKET_1_10) AS SKAN_CV_BUCKET_1_10,
    SUM(CV_BUCKET_11_20) AS SKAN_CV_BUCKET_11_20,
    SUM(CV_BUCKET_21_40) AS SKAN_CV_BUCKET_21_40,
    SUM(CV_BUCKET_41_63) AS SKAN_CV_BUCKET_41_63,
    SUM(STOREKIT_RENDERED_COUNT) AS SKAN_STOREKIT_RENDERED,
    SUM(VIEW_THROUGH_COUNT) AS SKAN_VIEW_THROUGH,
    SUM(WINNING_POSTBACKS) AS SKAN_WINNING_POSTBACKS,
    SUM(SKAN_V3_COUNT) AS SKAN_V3_COUNT,
    SUM(SKAN_V4_COUNT) AS SKAN_V4_COUNT
FROM {{ ref('int_skan__aggregate_attribution') }}
WHERE INSTALL_DATE IS NOT NULL
{% if is_incremental() %}
  AND INSTALL_DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
{% endif %}
GROUP BY 1, 2, 3
