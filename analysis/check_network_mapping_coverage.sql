-- check_network_mapping_coverage.sql
-- Identifies unmapped PARTNER_NAME values across Supermetrics spend and Adjust API revenue sources.
-- This analysis helps ensure the network_mapping seed covers all active ad partners before production deployment.
--
-- Run with: dbt compile --select check_network_mapping_coverage
-- Then execute the compiled SQL in Snowflake worksheet to see results.
--
-- Output:
-- - Summary: Mapped vs UNMAPPED partners with counts and partner lists
-- - Detail: Each unmapped partner with its source and recent activity

WITH supermetrics_partners AS (
    -- Get distinct partners from Supermetrics spend data (last 90 days with spend)
    SELECT DISTINCT
        PARTNER_NAME,
        'Supermetrics' AS source
    FROM {{ ref('stg_supermetrics__adj_campaign') }}
    WHERE DATE >= DATEADD(day, -90, CURRENT_DATE)
      AND COST > 0
      AND PARTNER_NAME IS NOT NULL
),

adjust_partners AS (
    -- Get distinct partners from Adjust API revenue data (last 90 days with revenue or installs)
    SELECT DISTINCT
        PARTNER_NAME,
        'Adjust API' AS source
    FROM {{ ref('stg_adjust__report_daily') }}
    WHERE DATE >= DATEADD(day, -90, CURRENT_DATE)
      AND (REVENUE > 0 OR INSTALLS > 0)
      AND PARTNER_NAME IS NOT NULL
),

all_partners AS (
    SELECT * FROM supermetrics_partners
    UNION
    SELECT * FROM adjust_partners
),

mapping_status AS (
    SELECT
        a.PARTNER_NAME,
        a.source,
        CASE
            WHEN (a.source = 'Supermetrics' AND nm_super.AD_PARTNER IS NOT NULL) THEN 'Mapped'
            WHEN (a.source = 'Adjust API' AND nm_adjust.AD_PARTNER IS NOT NULL) THEN 'Mapped'
            ELSE 'UNMAPPED - will map to Other'
        END AS coverage_status,
        COALESCE(nm_super.AD_PARTNER, nm_adjust.AD_PARTNER) AS mapped_to
    FROM all_partners a
    -- Left join to network_mapping for Supermetrics partners
    LEFT JOIN {{ ref('network_mapping') }} nm_super
        ON a.PARTNER_NAME = nm_super.SUPERMETRICS_PARTNER_NAME
        AND a.source = 'Supermetrics'
    -- Left join to network_mapping for Adjust API partners
    LEFT JOIN {{ ref('network_mapping') }} nm_adjust
        ON a.PARTNER_NAME = nm_adjust.ADJUST_NETWORK_NAME
        AND a.source = 'Adjust API'
),

summary AS (
    SELECT
        coverage_status,
        COUNT(DISTINCT PARTNER_NAME) AS partner_count,
        LISTAGG(DISTINCT PARTNER_NAME, ', ') WITHIN GROUP (ORDER BY PARTNER_NAME) AS partners
    FROM mapping_status
    GROUP BY coverage_status
),

detail AS (
    SELECT
        PARTNER_NAME,
        source,
        coverage_status,
        mapped_to,
        'Review network_mapping.csv to add this partner' AS recommendation
    FROM mapping_status
    WHERE coverage_status = 'UNMAPPED - will map to Other'
    ORDER BY source, PARTNER_NAME
)

-- Output both summary and detail
SELECT 'SUMMARY' AS section, coverage_status AS category, partner_count, partners, NULL AS partner_name, NULL AS source, NULL AS mapped_to, NULL AS recommendation
FROM summary

UNION ALL

SELECT 'DETAIL' AS section, coverage_status AS category, NULL AS partner_count, NULL AS partners, PARTNER_NAME, source, mapped_to, recommendation
FROM detail

ORDER BY section DESC, category, partner_name
