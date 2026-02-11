---
phase: 03-mta-limitations-mmm-foundation
plan: 03
subsystem: analytics
tags: [mmm, dbt, date-spine, marts, time-series, snowflake]

# Dependency graph
requires:
  - phase: 03-02
    provides: "Three incremental intermediate models aggregating spend, installs, and revenue by DATE+PLATFORM+CHANNEL"
  - phase: 01-01
    provides: "Test infrastructure and 60-day lookback pattern"
provides:
  - "MMM daily summary mart with complete gap-free time series (date spine + zero-fill)"
  - "MMM weekly rollup for alternative MMM tool granularity"
  - "Schema YAML with dbt_utils primary key tests"
  - "Full MMM pipeline: staging → intermediate → marts"
affects: [Phase 4 (MMM modeling/analysis), external MMM tools]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Date spine with hardcoded bounds (2024-01-01 to current_date) to avoid Cartesian product"
    - "CROSS JOIN dates with distinct channels for complete time series grid"
    - "LEFT JOIN + COALESCE pattern for zero-fill (gap-free metrics)"
    - "Marts as table materialization (not incremental) - full refresh join layer"
    - "Derived KPI calculation (CPI, ROAS) in mart layer"
    - "Data quality flags (HAS_*_DATA) for transparency on zero-filled vs missing data"

key-files:
  created:
    - models/marts/mmm/mmm__daily_channel_summary.sql
    - models/marts/mmm/mmm__weekly_channel_summary.sql
    - models/marts/mmm/_mmm__models.yml
  modified: []

key-decisions:
  - "Use hardcoded start_date='2024-01-01' in date spine (not CROSS JOIN for date bounds)"
  - "Materialize marts as 'table' not 'incremental' since date spine requires full grid regeneration"
  - "COALESCE all metrics to 0 for gap-free time series (critical for MMM regression)"
  - "Weekly rollup recomputes KPIs from weekly totals (not averaged from daily KPIs)"
  - "Add data quality flags (HAS_SPEND_DATA, etc.) to distinguish zero-filled from missing data"

patterns-established:
  - "dbt_utils.date_spine macro usage for complete time series"
  - "Date spine + channels CROSS JOIN + LEFT JOIN metrics pattern"
  - "Zero-fill pattern: COALESCE(metric, 0) for additive metrics, NULL for derived KPIs when denominator is 0"
  - "dbt_utils.unique_combination_of_columns for composite primary key tests"

# Metrics
duration: 2min
completed: 2026-02-11
---

# Phase 03 Plan 03: MMM Marts Summary

**MMM daily summary mart joins spend, installs, revenue with date spine ensuring gap-free time series for regression modeling**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-11T22:04:38Z
- **Completed:** 2026-02-11T22:06:38Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Daily channel summary mart with date spine (2024-01-01 to current) cross-joined with channels for complete time series
- All metrics zero-filled via COALESCE for gap-free series (critical for MMM regression models)
- Weekly rollup with recomputed KPIs and data coverage indicators for alternative MMM tool granularity
- Schema YAML with documentation, dbt tests, and dbt_utils primary key tests
- Full pipeline dependency chain verified: staging → intermediate → marts (no circular dependencies)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create daily channel summary mart with date spine** - `0d801ec` (feat)
2. **Task 2: Create weekly rollup, schema YAML, and compile verification** - `e50bc46` (feat)

## Files Created/Modified
- `models/marts/mmm/mmm__daily_channel_summary.sql` - Primary MMM input table with date spine ensuring no gaps, LEFT JOINs spend/installs/revenue, derived KPIs (CPI, ROAS), data quality flags
- `models/marts/mmm/mmm__weekly_channel_summary.sql` - Weekly rollup of daily summary with DATE_TRUNC('week'), recomputed KPIs, coverage indicators
- `models/marts/mmm/_mmm__models.yml` - Schema definitions with documentation, not_null tests, accepted_values tests, dbt_utils.unique_combination_of_columns tests on primary keys

## Decisions Made

**1. Hardcoded date spine bounds instead of dynamic CROSS JOIN**
- **Rationale:** Using `start_date="'2024-01-01'"` (known data boundary from staging filters) and `end_date="current_date()"` avoids CROSS JOIN of three intermediate models which would create a Cartesian product to find min/max dates.
- **Trade-off:** Requires manual adjustment if historical data pre-2024 is backfilled. Acceptable since data pipeline start is documented as 2024-01-01 in staging model filters.

**2. Marts as 'table' materialization (not incremental)**
- **Rationale:** Date spine must regenerate the full grid on each run. The intermediate models are incremental; this mart is the join layer. Full refresh pattern is correct for date spine + CROSS JOIN architecture.
- **Performance note:** This is acceptable because the date spine only generates ~400 rows (2024-01-01 to current), and the CROSS JOIN with channels (~10-15 distinct channels × 2 platforms) produces ~8,000-12,000 grid rows. The intermediate models handle the heavy lifting incrementally.

**3. Zero-fill pattern with data quality flags**
- **Rationale:** MMM regression models require complete time series with no gaps. COALESCE(metric, 0) for additive metrics ensures every date-channel combination has a value. Data quality flags (HAS_SPEND_DATA, HAS_INSTALL_DATA, HAS_REVENUE_DATA) distinguish actual zeros from zero-filled missing data for transparency.
- **Alternative considered:** NULL for missing data would create gaps. Not viable for MMM time series regression.

**4. Weekly rollup recomputes KPIs from weekly totals**
- **Rationale:** KPIs like CPI and ROAS must be recomputed from weekly aggregated spend/installs/revenue (not averaged from daily KPIs) to avoid mathematical incorrectness. Example: Daily CPI [10, 20] averaged is 15, but weekly CPI computed from weekly totals may be different due to denominator weighting.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**MMM data foundation complete:**
- Phase 3 complete (3/3 plans): MTA limitations documented + MMM pipeline built
- MMM pipeline ready for external MMM tools (Python libraries like PyMC-Marketing, Robyn, Meridian)
- Data exports: mmm__daily_channel_summary or mmm__weekly_channel_summary can be exported to CSV/Parquet for MMM modeling
- Next phase depends on stakeholder decision: continue with Phase 4 (MMM modeling in Python) or pivot to other priorities

**Known context for MMM modeling:**
- Date spine ensures no gaps in time series (required for regression)
- Data start: 2024-01-01 (hardcoded boundary)
- Grain options: daily (mmm__daily_channel_summary) or weekly (mmm__weekly_channel_summary)
- Metrics available: SPEND, INSTALLS, REVENUE, IMPRESSIONS, CLICKS (plus derived CPI, ROAS)
- Dimensions: DATE, PLATFORM (iOS/Android), CHANNEL (Meta, Google, TikTok, etc.)
- Data quality: Flags indicate which metrics are zero-filled vs actual data

**No blockers.** Phase 3 objectives achieved: MTA limitations documented, strategic pivot to MMM recommended, MMM data foundation built and verified.

---
*Phase: 03-mta-limitations-mmm-foundation*
*Completed: 2026-02-11*

## Self-Check: PASSED

All created files and commits verified.
