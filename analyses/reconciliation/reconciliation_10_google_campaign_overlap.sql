-- reconciliation_10_google_campaign_overlap.sql
-- Detects Google campaigns that exist in BOTH Adjust and Fivetran.
--
-- Any rows returned represent potential double-counting in
-- mart_daily_overview_by_platform (which uses both sources without dedup).
-- int_spend__unified handles this via dedup, but other marts do not.

WITH adjust_google AS (
    SELECT DISTINCT
        CAMPAIGN_ID_NETWORK AS CID,
        CAMPAIGN_NETWORK AS CNAME
    FROM {{ ref('stg_adjust__report_daily') }}
    WHERE LOWER(PARTNER_NAME) LIKE '%google%'
),

fivetran_google AS (
    SELECT DISTINCT
        CAMPAIGN_ID::VARCHAR AS CID,
        CAMPAIGN_NAME AS CNAME
    FROM {{ ref('v_stg_google_ads__spend') }}
)

SELECT
    a.CID AS ADJUST_CID,
    f.CID AS FIVETRAN_CID,
    a.CNAME AS ADJUST_NAME,
    f.CNAME AS FIVETRAN_NAME
FROM adjust_google a
INNER JOIN fivetran_google f ON a.CID = f.CID
