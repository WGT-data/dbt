SELECT CAST(date AS DATE) AS Date
     , ACC.NAME AS ACCOUNT
     , CAM.NAME AS CAMPAIGN
     , ADT.NAME AS ADSET
     , ADS.NAME AS AD
     , ADI.AD_ID
     , COALESCE(CC.COUNTRY_NAME, '__none__') AS COUNTRY
     , sum(SPEND) as SPEND
     , sum(IMPRESSIONS) AS IMPRESSIONS
     , sum(INLINE_LINK_CLICKS) as CLICKS
FROM {{ source('facebook_ads', 'ADS_INSIGHTS') }} ADI
LEFT JOIN {{ ref('v_stg_facebook_accounts') }} ACC ON ACC.ID = ADI.ACCOUNT_ID
LEFT JOIN {{ ref('v_stg_facebook_campaigns') }} CAM ON CAM.ID = ADI.CAMPAIGN_ID
LEFT JOIN {{ ref('v_stg_facebook_adsets') }} ADT ON ADT.ID = ADI.ADSET_ID
LEFT JOIN {{ ref('v_stg_facebook_ads') }} ADS ON ADS.ID = ADI.AD_ID
LEFT JOIN {{ ref('country_codes') }} CC ON LOWER(ADI.COUNTRY) = CC.CODE_ALPHA2
GROUP BY Date
     , ACC.NAME
     , CAM.NAME
     , ADT.NAME
     , ADS.NAME
     , ADI.AD_ID
     , CC.COUNTRY_NAME
