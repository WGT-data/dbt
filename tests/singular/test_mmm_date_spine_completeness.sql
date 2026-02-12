-- test_mmm_date_spine_completeness.sql (TEST-06)
-- Validates that mmm__daily_channel_summary has a complete date spine with no gaps.
--
-- Checks two things:
-- 1. No gaps in date sequence (every date from MIN to MAX is present)
-- 2. Every date has the full set of channel+platform combinations (complete grid)
--
-- Uses self-referencing approach: checks internal consistency of the mart data
-- rather than generating an independent date spine (avoids date type comparison issues).
--
-- Test passes when zero rows returned (no gaps, complete grid).
-- Test fails if dates are missing or any date has fewer channel combos than expected.

WITH date_summary AS (
    SELECT
        DATE,
        COUNT(*) AS channel_count
    FROM {{ ref('mmm__daily_channel_summary') }}
    GROUP BY DATE
),

expected AS (
    SELECT
        DATEDIFF(day, MIN(DATE), MAX(DATE)) + 1 AS expected_date_count,
        COUNT(*) AS actual_date_count
    FROM date_summary
),

expected_channels AS (
    SELECT COUNT(DISTINCT PLATFORM || '||' || CHANNEL) AS expected_channel_count
    FROM {{ ref('mmm__daily_channel_summary') }}
)

-- Check 1: Missing dates in sequence
SELECT
    'DATE_SEQUENCE_GAP' AS error_type,
    NULL AS DATE,
    expected_date_count AS expected_value,
    actual_date_count AS actual_value,
    'Missing ' || (expected_date_count - actual_date_count) || ' dates in sequence' AS error_reason
FROM expected
WHERE actual_date_count != expected_date_count

UNION ALL

-- Check 2: Dates with incomplete channel combinations
SELECT
    'INCOMPLETE_GRID' AS error_type,
    ds.DATE,
    ec.expected_channel_count AS expected_value,
    ds.channel_count AS actual_value,
    'Date has ' || ds.channel_count || ' channel combos, expected ' || ec.expected_channel_count AS error_reason
FROM date_summary ds
CROSS JOIN expected_channels ec
WHERE ds.channel_count != ec.expected_channel_count

ORDER BY error_type, DATE DESC
