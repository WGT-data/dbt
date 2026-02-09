{{
    config(
        materialized='incremental',
        unique_key=['AD_PARTNER', 'NETWORK_NAME', 'PLATFORM', 'DATE'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

WITH NETWORK_MAPPING AS (
    SELECT ADJUST_NETWORK_NAME
         , MAX(SUPERMETRICS_PARTNER_ID)::VARCHAR AS SUPERMETRICS_PARTNER_ID
    FROM {{ ref('network_mapping') }}
    GROUP BY ADJUST_NETWORK_NAME
)

, ATTRIBUTION AS (
    SELECT A.AD_PARTNER
         , A.NETWORK_NAME
         , NM.SUPERMETRICS_PARTNER_ID::VARCHAR AS PARTNER_ID
         , A.PLATFORM
         , A.INSTALL_DATE
         , SUM(A.INSTALLS) AS INSTALLS
         , SUM(A.MATCHED_DEVICES) AS MATCHED_DEVICES
         , SUM(A.PURCHASERS) AS PURCHASERS
         , SUM(A.PURCHASE_EVENTS) AS PURCHASE_EVENTS
         , SUM(A.REVENUE) AS REVENUE
         , SUM(A.USERS_LEVELED_UP) AS USERS_LEVELED_UP
         , SUM(A.LEVEL_UP_EVENTS) AS LEVEL_UP_EVENTS
         , SUM(A.LEVEL_UP_COINS_REWARDED) AS LEVEL_UP_COINS_REWARDED
    FROM {{ ref('attribution__installs') }} A
    LEFT JOIN NETWORK_MAPPING NM
      ON A.NETWORK_NAME = NM.ADJUST_NETWORK_NAME
    {% if is_incremental() %}
        -- 3-day lookback to capture late-arriving attribution data
        WHERE A.INSTALL_DATE >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY A.AD_PARTNER
         , A.NETWORK_NAME
         , NM.SUPERMETRICS_PARTNER_ID::VARCHAR
         , A.PLATFORM
         , A.INSTALL_DATE
)

-- Calculate install share per network within each partner/platform/date group
-- This prevents spend duplication when multiple networks map to the same partner
, ATTRIBUTION_WITH_SHARE AS (
    SELECT *
         , SUM(INSTALLS) OVER (
             PARTITION BY PARTNER_ID
                        , PLATFORM
                        , INSTALL_DATE
           ) AS PARTNER_TOTAL_INSTALLS
         , CASE 
             WHEN SUM(INSTALLS) OVER (
                 PARTITION BY PARTNER_ID
                            , PLATFORM
                            , INSTALL_DATE
             ) > 0 
             THEN INSTALLS::FLOAT / SUM(INSTALLS) OVER (
                 PARTITION BY PARTNER_ID
                            , PLATFORM
                            , INSTALL_DATE
             )
             ELSE 0
           END AS INSTALL_SHARE
    FROM ATTRIBUTION
)

, SPEND AS (
    SELECT PARTNER_ID
         , PARTNER_NAME AS NETWORK_NAME
         , PLATFORM
         , DATE AS SPEND_DATE
         , SUM(COST) AS COST
         , SUM(CLICKS) AS CLICKS
         , SUM(IMPRESSIONS) AS IMPRESSIONS
         , SUM(INSTALLS) AS SUPERMETRICS_INSTALLS
    FROM {{ ref('stg_supermetrics__adj_campaign') }}
    {% if is_incremental() %}
        -- 3-day lookback to capture late-arriving spend data
        WHERE DATE >= DATEADD(day, -3, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
    GROUP BY PARTNER_ID
         , PARTNER_NAME
         , PLATFORM
         , DATE
)

, JOINED AS (
    SELECT COALESCE(A.AD_PARTNER, S.NETWORK_NAME) AS AD_PARTNER
         , COALESCE(A.NETWORK_NAME, S.NETWORK_NAME) AS NETWORK_NAME
         , COALESCE(A.PLATFORM, S.PLATFORM) AS PLATFORM
         , COALESCE(A.INSTALL_DATE, S.SPEND_DATE) AS DATE
         -- Allocate spend proportionally based on install share
         , COALESCE(S.COST * A.INSTALL_SHARE, S.COST, 0) AS COST
         , COALESCE(S.CLICKS * A.INSTALL_SHARE, S.CLICKS, 0) AS CLICKS
         , COALESCE(S.IMPRESSIONS * A.INSTALL_SHARE, S.IMPRESSIONS, 0) AS IMPRESSIONS
         , COALESCE(S.SUPERMETRICS_INSTALLS * A.INSTALL_SHARE, S.SUPERMETRICS_INSTALLS, 0) AS SUPERMETRICS_INSTALLS
         , COALESCE(A.INSTALLS, 0) AS ATTRIBUTION_INSTALLS
         , COALESCE(A.MATCHED_DEVICES, 0) AS MATCHED_DEVICES
         , COALESCE(A.PURCHASERS, 0) AS PURCHASERS
         , COALESCE(A.PURCHASE_EVENTS, 0) AS PURCHASE_EVENTS
         , COALESCE(A.REVENUE, 0) AS REVENUE
         , COALESCE(A.USERS_LEVELED_UP, 0) AS USERS_LEVELED_UP
         , COALESCE(A.LEVEL_UP_EVENTS, 0) AS LEVEL_UP_EVENTS
         , COALESCE(A.LEVEL_UP_COINS_REWARDED, 0) AS LEVEL_UP_COINS_REWARDED
    FROM ATTRIBUTION_WITH_SHARE A
    FULL OUTER JOIN SPEND S
      ON A.PARTNER_ID = S.PARTNER_ID
      AND A.PLATFORM = S.PLATFORM
      AND A.INSTALL_DATE = S.SPEND_DATE
)

SELECT AD_PARTNER
     , NETWORK_NAME
     , PLATFORM
     , DATE
     , COST
     , CLICKS
     , IMPRESSIONS
     , SUPERMETRICS_INSTALLS AS ADJUST_INSTALLS
     , ATTRIBUTION_INSTALLS
     , MATCHED_DEVICES
     , PURCHASERS
     , PURCHASE_EVENTS
     , REVENUE
     , USERS_LEVELED_UP
     , LEVEL_UP_EVENTS
     , LEVEL_UP_COINS_REWARDED
     , IFF(ATTRIBUTION_INSTALLS > 0, COST / ATTRIBUTION_INSTALLS, NULL) AS CPI
     , IFF(COST > 0, REVENUE / COST, NULL) AS ROAS
FROM JOINED
ORDER BY DATE DESC
     , COST DESC
