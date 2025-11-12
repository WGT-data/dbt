 {{config(materialized = "table")}} 

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
ORDER BY DATE DESC
     , CAMPAIGN ASC
     , ADSET ASC
     , AD ASC
     , CONVERSIONNAME ASC