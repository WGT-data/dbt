{{
    config(
        materialized='incremental',
        unique_key=['DATE', 'AD_ID', 'CONVERSIONNAME'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

SELECT CAST(DATE AS DATE) AS DATE
     , ACCOUNT
     , CAMPAIGN
     , ADSET
     , AD
     , AD_ID
     , CONVERSIONNAME
     , SPEND_RAW/DIVIDEND AS SPEND
     , IMPRESSIONS_RAW/DIVIDEND AS IMPRESSIONS
     , CLICKS_RAW/DIVIDEND AS CLICKS
     , ALLCONV
FROM {{ ref('v_stg_facebook_conversions') }}
{% if is_incremental() %}
    -- 3-day lookback to capture late-arriving Facebook conversion data
    WHERE DATE >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
{% endif %}
ORDER BY DATE DESC
     , CAMPAIGN ASC
     , ADSET ASC
     , AD ASC
     , CONVERSIONNAME ASC