-- test_mmm_date_spine_completeness.sql (TEST-06)
-- Validates that mmm__daily_channel_summary has no gaps in the date spine.
-- For every active PLATFORM+CHANNEL combination, every date since 2024-01-01 should have a row.
--
-- This test ensures the MMM regression model receives a complete time series with no missing dates.
-- Missing date+channel combinations would create gaps that could break MMM model fitting.
--
-- Test passes when zero rows returned (no gaps).
-- Test fails if any expected date+channel+platform combination is missing from the mart.

WITH date_spine AS (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="'2024-01-01'",
        end_date="current_date()"
    ) }}
),

dates AS (
    SELECT CAST(date_day AS DATE) AS DATE
    FROM date_spine
),

-- Get all distinct PLATFORM + CHANNEL combinations that exist in the mart
active_channels AS (
    SELECT DISTINCT PLATFORM, CHANNEL
    FROM {{ ref('mmm__daily_channel_summary') }}
),

-- Create expected grid: every date x every active channel
expected_grid AS (
    SELECT
        d.DATE,
        c.PLATFORM,
        c.CHANNEL
    FROM dates d
    CROSS JOIN active_channels c
),

-- Get actual data
actual_data AS (
    SELECT
        DATE,
        PLATFORM,
        CHANNEL
    FROM {{ ref('mmm__daily_channel_summary') }}
)

-- Return missing combinations (left join finds gaps)
SELECT
    e.DATE,
    e.PLATFORM,
    e.CHANNEL,
    'Missing from mart - date spine gap detected' AS error_reason
FROM expected_grid e
LEFT JOIN actual_data a
    ON e.DATE = a.DATE
    AND e.PLATFORM = a.PLATFORM
    AND e.CHANNEL = a.CHANNEL
WHERE a.DATE IS NULL
ORDER BY e.DATE DESC, e.PLATFORM, e.CHANNEL
