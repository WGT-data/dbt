-- reconciliation_11_google_country_code_validation.sql
-- Validates the +2000 offset assumption used to map Google Ads COUNTRY_CRITERION_ID
-- to ISO numeric country codes in v_stg_google_ads__country_spend.
--
-- Any MISMATCH rows indicate country codes where the +2000 mapping fails.
-- NULL COUNTRY_NAME rows indicate unmapped Google criterion IDs.

SELECT
    ccr.COUNTRY_CRITERION_ID,
    cc.CODE_NUMERIC,
    cc.CODE_NUMERIC + 2000 AS EXPECTED,
    cc.COUNTRY_NAME,
    CASE
        WHEN ccr.COUNTRY_CRITERION_ID = cc.CODE_NUMERIC + 2000 THEN 'MATCH'
        ELSE 'MISMATCH'
    END AS STATUS
FROM (
    SELECT DISTINCT COUNTRY_CRITERION_ID
    FROM FIVETRAN_DATABASE.GOOGLE_ADS.CAMPAIGN_COUNTRY_REPORT
) ccr
LEFT JOIN {{ ref('country_codes') }} cc
    ON ccr.COUNTRY_CRITERION_ID = cc.CODE_NUMERIC + 2000
ORDER BY STATUS DESC
