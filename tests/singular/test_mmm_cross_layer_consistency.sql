-- test_mmm_cross_layer_consistency.sql (TEST-07)
-- Validates that the intermediate layer totals match the mart layer totals within tolerance.
-- This ensures the date spine and LEFT JOIN logic in mmm__daily_channel_summary preserves data accuracy.
--
-- Compares:
-- - int_mmm__daily_channel_spend (SPEND + IMPRESSIONS + CLICKS + PAID_INSTALLS)
-- - int_mmm__daily_channel_installs (INSTALLS)
-- - int_mmm__daily_channel_revenue (REVENUE + ALL_REVENUE + AD_REVENUE + API_INSTALLS)
-- Against:
-- - mmm__daily_channel_summary (same metrics after zero-filling)
--
-- Only checks rows where HAS_*_DATA = 1 to exclude purely zero-filled date spine rows
-- (zero-filled rows by definition have no intermediate data to compare against).
-- Filters intermediate data to >= 2024-01-01 to match the mart's date spine boundary.
--
-- Test passes when zero rows returned (all totals match within tolerance).
-- Test fails if ABS(intermediate - mart) > 0.01 for currency metrics or > 0 for counts.

WITH intermediate_totals AS (
    -- Aggregate all metrics from intermediate layer at DATE + PLATFORM grain
    -- Use UNION ALL to combine metrics from three separate models
    SELECT
        DATE,
        PLATFORM,
        SUM(SPEND) AS intermediate_spend,
        SUM(IMPRESSIONS) AS intermediate_impressions,
        SUM(CLICKS) AS intermediate_clicks,
        SUM(PAID_INSTALLS) AS intermediate_paid_installs,
        SUM(INSTALLS) AS intermediate_installs,
        SUM(REVENUE) AS intermediate_revenue,
        SUM(ALL_REVENUE) AS intermediate_all_revenue,
        SUM(AD_REVENUE) AS intermediate_ad_revenue,
        SUM(API_INSTALLS) AS intermediate_api_installs
    FROM (
        -- Spend metrics
        SELECT
            DATE,
            PLATFORM,
            SPEND,
            IMPRESSIONS,
            CLICKS,
            PAID_INSTALLS,
            0 AS INSTALLS,
            0 AS REVENUE,
            0 AS ALL_REVENUE,
            0 AS AD_REVENUE,
            0 AS API_INSTALLS
        FROM {{ ref('int_mmm__daily_channel_spend') }}
        WHERE DATE >= '2024-01-01'

        UNION ALL

        -- Install metrics
        SELECT
            DATE,
            PLATFORM,
            0 AS SPEND,
            0 AS IMPRESSIONS,
            0 AS CLICKS,
            0 AS PAID_INSTALLS,
            INSTALLS,
            0 AS REVENUE,
            0 AS ALL_REVENUE,
            0 AS AD_REVENUE,
            0 AS API_INSTALLS
        FROM {{ ref('int_mmm__daily_channel_installs') }}
        WHERE DATE >= '2024-01-01'

        UNION ALL

        -- Revenue metrics
        SELECT
            DATE,
            PLATFORM,
            0 AS SPEND,
            0 AS IMPRESSIONS,
            0 AS CLICKS,
            0 AS PAID_INSTALLS,
            0 AS INSTALLS,
            REVENUE,
            ALL_REVENUE,
            AD_REVENUE,
            API_INSTALLS
        FROM {{ ref('int_mmm__daily_channel_revenue') }}
        WHERE DATE >= '2024-01-01'
    )
    GROUP BY DATE, PLATFORM
),

mart_totals AS (
    -- Aggregate mart metrics at DATE + PLATFORM grain
    -- Filter to rows with actual data (HAS_*_DATA = 1) to exclude zero-filled date spine rows
    SELECT
        DATE,
        PLATFORM,
        SUM(SPEND) AS mart_spend,
        SUM(IMPRESSIONS) AS mart_impressions,
        SUM(CLICKS) AS mart_clicks,
        SUM(PAID_INSTALLS_SUPERMETRICS) AS mart_paid_installs,
        SUM(INSTALLS) AS mart_installs,
        SUM(REVENUE) AS mart_revenue,
        SUM(ALL_REVENUE) AS mart_all_revenue,
        SUM(AD_REVENUE) AS mart_ad_revenue,
        SUM(INSTALLS_API) AS mart_api_installs
    FROM {{ ref('mmm__daily_channel_summary') }}
    WHERE HAS_SPEND_DATA = 1
       OR HAS_INSTALL_DATA = 1
       OR HAS_REVENUE_DATA = 1
    GROUP BY DATE, PLATFORM
),

comparison AS (
    SELECT
        COALESCE(i.DATE, m.DATE) AS DATE,
        COALESCE(i.PLATFORM, m.PLATFORM) AS PLATFORM,
        -- Intermediate values
        COALESCE(i.intermediate_spend, 0) AS intermediate_spend,
        COALESCE(i.intermediate_impressions, 0) AS intermediate_impressions,
        COALESCE(i.intermediate_clicks, 0) AS intermediate_clicks,
        COALESCE(i.intermediate_paid_installs, 0) AS intermediate_paid_installs,
        COALESCE(i.intermediate_installs, 0) AS intermediate_installs,
        COALESCE(i.intermediate_revenue, 0) AS intermediate_revenue,
        COALESCE(i.intermediate_all_revenue, 0) AS intermediate_all_revenue,
        COALESCE(i.intermediate_ad_revenue, 0) AS intermediate_ad_revenue,
        COALESCE(i.intermediate_api_installs, 0) AS intermediate_api_installs,
        -- Mart values
        COALESCE(m.mart_spend, 0) AS mart_spend,
        COALESCE(m.mart_impressions, 0) AS mart_impressions,
        COALESCE(m.mart_clicks, 0) AS mart_clicks,
        COALESCE(m.mart_paid_installs, 0) AS mart_paid_installs,
        COALESCE(m.mart_installs, 0) AS mart_installs,
        COALESCE(m.mart_revenue, 0) AS mart_revenue,
        COALESCE(m.mart_all_revenue, 0) AS mart_all_revenue,
        COALESCE(m.mart_ad_revenue, 0) AS mart_ad_revenue,
        COALESCE(m.mart_api_installs, 0) AS mart_api_installs
    FROM intermediate_totals i
    FULL OUTER JOIN mart_totals m
        ON i.DATE = m.DATE AND i.PLATFORM = m.PLATFORM
)

-- Return rows with mismatches exceeding tolerance
SELECT
    DATE,
    PLATFORM,
    'SPEND' AS error_type,
    intermediate_spend AS intermediate_value,
    mart_spend AS mart_value,
    ABS(intermediate_spend - mart_spend) AS difference
FROM comparison
WHERE ABS(intermediate_spend - mart_spend) > 0.01

UNION ALL

SELECT
    DATE,
    PLATFORM,
    'IMPRESSIONS' AS error_type,
    intermediate_impressions AS intermediate_value,
    mart_impressions AS mart_value,
    ABS(intermediate_impressions - mart_impressions) AS difference
FROM comparison
WHERE ABS(intermediate_impressions - mart_impressions) > 0

UNION ALL

SELECT
    DATE,
    PLATFORM,
    'CLICKS' AS error_type,
    intermediate_clicks AS intermediate_value,
    mart_clicks AS mart_value,
    ABS(intermediate_clicks - mart_clicks) AS difference
FROM comparison
WHERE ABS(intermediate_clicks - mart_clicks) > 0

UNION ALL

SELECT
    DATE,
    PLATFORM,
    'PAID_INSTALLS' AS error_type,
    intermediate_paid_installs AS intermediate_value,
    mart_paid_installs AS mart_value,
    ABS(intermediate_paid_installs - mart_paid_installs) AS difference
FROM comparison
WHERE ABS(intermediate_paid_installs - mart_paid_installs) > 0

UNION ALL

SELECT
    DATE,
    PLATFORM,
    'INSTALLS' AS error_type,
    intermediate_installs AS intermediate_value,
    mart_installs AS mart_value,
    ABS(intermediate_installs - mart_installs) AS difference
FROM comparison
WHERE ABS(intermediate_installs - mart_installs) > 0

UNION ALL

SELECT
    DATE,
    PLATFORM,
    'REVENUE' AS error_type,
    intermediate_revenue AS intermediate_value,
    mart_revenue AS mart_value,
    ABS(intermediate_revenue - mart_revenue) AS difference
FROM comparison
WHERE ABS(intermediate_revenue - mart_revenue) > 0.01

UNION ALL

SELECT
    DATE,
    PLATFORM,
    'ALL_REVENUE' AS error_type,
    intermediate_all_revenue AS intermediate_value,
    mart_all_revenue AS mart_value,
    ABS(intermediate_all_revenue - mart_all_revenue) AS difference
FROM comparison
WHERE ABS(intermediate_all_revenue - mart_all_revenue) > 0.01

UNION ALL

SELECT
    DATE,
    PLATFORM,
    'AD_REVENUE' AS error_type,
    intermediate_ad_revenue AS intermediate_value,
    mart_ad_revenue AS mart_value,
    ABS(intermediate_ad_revenue - mart_ad_revenue) AS difference
FROM comparison
WHERE ABS(intermediate_ad_revenue - mart_ad_revenue) > 0.01

UNION ALL

SELECT
    DATE,
    PLATFORM,
    'API_INSTALLS' AS error_type,
    intermediate_api_installs AS intermediate_value,
    mart_api_installs AS mart_value,
    ABS(intermediate_api_installs - mart_api_installs) AS difference
FROM comparison
WHERE ABS(intermediate_api_installs - mart_api_installs) > 0

ORDER BY DATE DESC, PLATFORM, error_type
