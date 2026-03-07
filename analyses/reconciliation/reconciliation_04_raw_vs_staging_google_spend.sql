-- reconciliation_04_raw_vs_staging_google_spend.sql
-- Validates that v_stg_google_ads__spend preserves raw Fivetran Google Ads spend.
--
-- Google raw table stores cost in micros (1/1,000,000 of currency unit).
-- Only rows with non-zero DELTA are returned.

WITH raw AS (
    SELECT
        DATE,
        SUM(COST_MICROS) / 1000000.0 AS RAW_SPEND
    FROM FIVETRAN_DATABASE.GOOGLE_ADS.CAMPAIGN_STATS
    WHERE COST_MICROS > 0
      AND DATE >= '2025-01-01'
    GROUP BY 1
),

staging AS (
    SELECT
        DATE,
        SUM(SPEND) AS STG_SPEND
    FROM {{ ref('v_stg_google_ads__spend') }}
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
