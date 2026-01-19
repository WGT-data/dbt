# Architecture

**Analysis Date:** 2026-01-19

## Pattern Overview

**Overall:** dbt Medallion Architecture (Staging -> Intermediate -> Marts)

**Key Characteristics:**
- Three-layer transformation architecture following dbt best practices
- Staging layer: Light transformations on raw sources (views)
- Intermediate layer: Complex business logic and joins (tables)
- Marts layer: Business-facing aggregated metrics (tables)
- Multi-touch attribution (MTA) modeling as core domain logic

## Layers

**Staging Layer:**
- Purpose: Clean, rename, and lightly transform raw source data
- Location: `models/staging/`
- Contains: Source references, type casting, basic filtering, deduplication
- Depends on: External sources (Snowflake databases)
- Used by: Intermediate models
- Materialization: Views (defined in `dbt_project.yml`)

**Intermediate Layer:**
- Purpose: Complex business logic, joins across sources, derived calculations
- Location: `models/intermediate/`
- Contains: Device mapping, user journeys, cohort metrics, touchpoint credit calculations
- Depends on: Staging models, other intermediate models
- Used by: Mart models
- Materialization: Tables with incremental strategy

**Marts Layer:**
- Purpose: Business-facing aggregated metrics for reporting/dashboards
- Location: `models/marts/`
- Contains: Campaign performance, network comparisons, attribution reports
- Depends on: Intermediate models, staging models, seeds
- Used by: BI tools, dashboards, analysts
- Materialization: Tables with incremental strategy

## Data Flow

**Attribution Data Flow:**

1. Raw install/click/impression events loaded to Snowflake from Adjust (`ADJUST_S3.PROD_DATA`)
2. Staging models unify iOS and Android data: `v_stg_adjust__installs.sql`, `v_stg_adjust__touchpoints.sql`
3. Device mapping joins Adjust device IDs to Amplitude user IDs: `int_adjust_amplitude__device_mapping.sql`
4. User journey model links touchpoints to conversions within 7-day lookback: `int_mta__user_journey.sql`
5. Touchpoint credit calculates 5 attribution models: `int_mta__touchpoint_credit.sql`
6. Campaign/network performance marts aggregate credits with spend: `mta__campaign_performance.sql`

**Revenue Attribution Flow:**

1. Revenue events from Amplitude (`EVENTS_726530`) with `$revenue` property
2. Staging extracts revenue: `v_stg_revenue__events.sql`
3. User metrics calculates D7/D30/lifetime revenue per user: `int_user_cohort__metrics.sql`
4. Revenue joined to attribution via device mapping
5. Fractional revenue attributed to campaigns based on touchpoint credit

**State Management:**
- Incremental models use 3-7 day lookback windows to capture late-arriving data
- `merge` incremental strategy with explicit `unique_key` definitions
- `merge_update_columns` specified for models that need partial updates

## Key Abstractions

**Device Mapping:**
- Purpose: Links mobile attribution device IDs to product analytics user IDs
- Primary model: `int_adjust_amplitude__device_mapping.sql`
- Pattern: Maps Adjust IDFV/GPS_ADID to Amplitude USER_ID via first-seen event
- Critical for: Connecting install attribution to downstream revenue/engagement

**Network Mapping (Seed):**
- Purpose: Standardizes ad partner names across Adjust and Supermetrics
- Location: `seeds/network_mapping.csv`
- Pattern: Lookup table mapping `ADJUST_NETWORK_NAME` to `SUPERMETRICS_PARTNER_ID/NAME`
- Used by: Campaign performance models for spend join

**Attribution Credit:**
- Purpose: Calculate fractional credit for each touchpoint
- Primary model: `int_mta__touchpoint_credit.sql`
- Pattern: Five attribution models in parallel columns (last-touch, first-touch, linear, time-decay, position-based)
- Configurable: `click_weight_multiplier`, `time_decay_half_life_days`, position weights

**AD_PARTNER Standardization:**
- Purpose: Group network names into standardized partner categories
- Pattern: CASE statement mapping (repeated in `v_stg_adjust__installs.sql` and `v_stg_adjust__touchpoints.sql`)
- Values: Meta, Google, TikTok, Apple, AppLovin, Unity, Moloco, Smadex, AdAction, Vungle, Organic, etc.

## Entry Points

**dbt Commands:**
- Location: `dbt_project.yml`
- Triggers: `dbt run`, `dbt build`, `dbt test`
- Responsibilities: Configure project, define materializations by layer

**Staging Sources:**
- Location: `models/staging/*/_{source}__sources.yml`
- Triggers: Referenced via `{{ source() }}` macro
- Key sources:
  - `adjust`: Mobile attribution data from Adjust S3
  - `amplitude`: Product analytics from Amplitude share
  - `revenue`: Purchase events from WGT internal
  - `supermetrics`: Ad spend data from Supermetrics sync

## Error Handling

**Strategy:** Defensive SQL with NULL handling

**Patterns:**
- `COALESCE()` for fallback values in joins
- `NULLIF()` to prevent division by zero in KPI calculations
- `IFF(condition, value, NULL)` for conditional metrics
- `TRY_CAST()` for safe type conversion in Amplitude JSON parsing
- `QUALIFY ROW_NUMBER()` for deduplication instead of failing on duplicates

## Cross-Cutting Concerns

**Incremental Processing:**
- All intermediate and mart models use incremental materialization
- Standard pattern: 3-day lookback for daily data, 7-day for user-level data
- `{% if is_incremental() %}` guards for incremental WHERE clauses

**Platform Handling:**
- iOS and Android processed separately then UNIONed
- Platform normalization: `CASE WHEN LOWER(OS_NAME) = 'ios' THEN 'iOS'...`
- Platform stored as `iOS` or `Android` (proper case)

**Device ID Normalization:**
- iOS: IDFV stored as uppercase UUID
- Android: GPS_ADID with trailing 'R' suffix stripped
- `UPPER()` applied consistently for case-insensitive matching

**Date Filtering:**
- Most models filter to `>= '2025-01-01'` for data freshness
- Incremental models use relative DATEADD lookbacks

---

*Architecture analysis: 2026-01-19*
