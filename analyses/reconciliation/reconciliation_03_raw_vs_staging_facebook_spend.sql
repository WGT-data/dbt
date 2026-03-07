-- reconciliation_03_raw_vs_staging_facebook_spend.sql
-- Validates that v_stg_facebook_spend preserves raw Fivetran Facebook spend.
--
-- Only rows with non-zero DELTA are returned.
-- A zero-row result means raw and staging match perfectly.

WITH raw AS (
    SELECT
        CAST(DATE AS DATE) AS DATE,
        SUM(SPEND) AS RAW_SPEND
    FROM FIVETRAN_DATABASE.FACEBOOK_ADS.ADS_INSIGHTS
    WHERE DATE >= '2025-01-01'
    GROUP BY 1
),

staging AS (
    SELECT
        DATE,
        SUM(SPEND) AS STG_SPEND
    FROM {{ ref('v_stg_facebook_spend') }}
    WHERE DATE >= '2025-01-01'
    GROUP BY 1
)

SELECT
    r.DATE,
    r.RAW_SPEND,
    s.STG_SPEND,
    r.RAW_SPEND - s.STG_SPEND AS DELTA
FROM raw r
FULL OUTER JOIN staging s ON r.DATE = s.DATE
WHERE ABS(COALESCE(r.RAW_SPEND, 0) - COALESCE(s.STG_SPEND, 0)) > 0.01
ORDER BY 1 DESC
