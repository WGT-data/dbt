-- test_mmm_zero_fill_integrity.sql (TEST-08)
-- Validates that HAS_*_DATA flags correctly match the presence/absence of actual metric data.
-- This ensures the CASE WHEN IS NOT NULL logic in mmm__daily_channel_summary is working correctly.
--
-- The mart uses data quality flags to distinguish:
-- - Zero-filled date spine rows (metric = 0, HAS_*_DATA = 0)
-- - Actual zero values from source data (metric = 0, HAS_*_DATA = 1 if row exists)
-- - Non-zero values (metric > 0, HAS_*_DATA = 1)
--
-- This test checks six violation conditions:
-- 1. SPEND > 0 but HAS_SPEND_DATA = 0 (has data but flag says no)
-- 2. SPEND = 0 but HAS_SPEND_DATA = 1 (legitimately possible if source has $0 row)
-- 3-4. Same for INSTALLS / HAS_INSTALL_DATA
-- 5-6. Same for REVENUE / HAS_REVENUE_DATA
--
-- Note: Condition #2, #4, #6 (zero metric with flag=1) are NOT violations.
-- A source row with $0 spend IS real data and should have flag=1.
-- Only checking conditions #1, #3, #5 (non-zero metric with flag=0).
--
-- Test passes when zero rows returned (no flag mismatches).
-- Test fails if any metric has non-zero value but corresponding HAS_*_DATA = 0.

WITH violations AS (
    SELECT
        DATE,
        PLATFORM,
        CHANNEL,
        SPEND,
        HAS_SPEND_DATA,
        INSTALLS,
        HAS_INSTALL_DATA,
        REVENUE,
        HAS_REVENUE_DATA,
        CASE
            WHEN SPEND > 0 AND HAS_SPEND_DATA = 0 THEN 'SPEND > 0 but HAS_SPEND_DATA = 0'
            WHEN INSTALLS > 0 AND HAS_INSTALL_DATA = 0 THEN 'INSTALLS > 0 but HAS_INSTALL_DATA = 0'
            WHEN REVENUE > 0 AND HAS_REVENUE_DATA = 0 THEN 'REVENUE > 0 but HAS_REVENUE_DATA = 0'
        END AS violation_type
    FROM {{ ref('mmm__daily_channel_summary') }}
)

SELECT
    DATE,
    PLATFORM,
    CHANNEL,
    violation_type,
    SPEND,
    HAS_SPEND_DATA,
    INSTALLS,
    HAS_INSTALL_DATA,
    REVENUE,
    HAS_REVENUE_DATA
FROM violations
WHERE violation_type IS NOT NULL
ORDER BY DATE DESC, PLATFORM, CHANNEL
