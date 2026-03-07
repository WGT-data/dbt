-- reconciliation_05_unified_spend_breakdown.sql
-- Shows daily spend breakdown by SOURCE in int_spend__unified.
--
-- Use this to understand the composition of unified/deduped spend
-- and verify that Fivetran vs Adjust dedup is working as expected.

SELECT
    DATE,
    SOURCE,
    SUM(SPEND) AS SPEND
FROM {{ ref('int_spend__unified') }}
WHERE DATE >= '2025-01-01'
GROUP BY 1, 2
ORDER BY 1 DESC, 2
