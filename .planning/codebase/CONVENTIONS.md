# Coding Conventions

**Analysis Date:** 2026-01-19

## File Naming Patterns

**Staging Models:**
- Source-specific prefix: `stg_{source}__{entity}.sql`
- View prefix for unified models: `v_stg_{source}__{entity}.sql`
- Examples:
  - `stg_adjust__ios_activity_install.sql` - Raw source staging
  - `v_stg_adjust__installs.sql` - Unified view combining iOS/Android
  - `v_stg_amplitude__events.sql` - View over Amplitude events

**Intermediate Models:**
- Pattern: `int_{domain}__{purpose}.sql`
- Examples:
  - `int_mta__user_journey.sql` - Multi-touch attribution user journey
  - `int_adjust_amplitude__device_mapping.sql` - Cross-source device mapping
  - `int_user_cohort__metrics.sql` - User cohort metric calculations

**Mart Models:**
- Entity-first for dimensions/facts: `{entity}__{metric}.sql`
- Report prefix for dashboard models: `rpt__{description}.sql`
- MTA prefix for attribution models: `mta__{metric}.sql`
- Examples:
  - `attribution__installs.sql` - Attribution fact table
  - `rpt__attribution_model_comparison.sql` - Dashboard report
  - `mta__campaign_performance.sql` - MTA-specific mart

**YAML Files:**
- Source definitions: `_{source}__sources.yml`
- Model documentation: `_{domain}__models.yml`
- Located in same directory as related models

## SQL Style Conventions

**Column Naming:**
- Use SCREAMING_SNAKE_CASE for all columns
- Prefix boolean flags: `IS_`, `HAS_`, `CAN_`
- Suffix timestamps: `_TIMESTAMP`, `_AT`
- Suffix dates: `_DATE`
- Suffix IDs: `_ID`
- Examples:
  - `DEVICE_ID`, `CAMPAIGN_ID`, `USER_ID`
  - `IS_FIRST_TOUCH`, `IS_LAST_TOUCH`, `IS_PAYER`
  - `INSTALL_TIMESTAMP`, `FIRST_SEEN_AT`
  - `INSTALL_DATE`, `WEEK_START`

**SELECT Formatting:**
```sql
SELECT COLUMN_ONE
     , COLUMN_TWO
     , COLUMN_THREE
     , CASE
           WHEN condition THEN value_a
           ELSE value_b
       END AS CALCULATED_COLUMN
FROM source_table
```
- First column on SELECT line, subsequent columns on new lines with leading comma
- Align commas vertically
- CASE statements indented with keywords aligned

**CTE Structure:**
```sql
WITH first_cte AS (
    SELECT *
    FROM source
)

, second_cte AS (
    SELECT *
    FROM first_cte
)

SELECT *
FROM second_cte
```
- Blank line between CTEs
- CTE names use snake_case (lowercase)
- Descriptive names: `touchpoints_with_install`, `with_time_decay_raw`

**JOIN Formatting:**
```sql
FROM table_a a
INNER JOIN table_b b
    ON a.KEY = b.KEY
    AND a.PLATFORM = b.PLATFORM
LEFT JOIN table_c c
    ON a.OTHER_KEY = c.OTHER_KEY
```
- JOIN type on its own line
- ON clause indented
- Multiple join conditions on separate lines with AND

## Jinja/dbt Patterns

**Config Block:**
```sql
{{
    config(
        materialized='incremental',
        unique_key=['KEY1', 'KEY2', 'KEY3'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        tags=['mta', 'attribution']
    )
}}
```
- Opening `{{` on its own line
- Each config option on its own line
- Always specify `on_schema_change='append_new_columns'` for incremental models

**Incremental Logic:**
```sql
{% if is_incremental() %}
    -- 3-day lookback to capture late-arriving data
    WHERE LOAD_TIMESTAMP >= DATEADD(day, -3, (SELECT MAX(LOAD_TIMESTAMP) FROM {{ this }}))
{% endif %}
```
- Always include a comment explaining the lookback window rationale
- Standard lookback windows: 3 days (general), 7 days (device mapping), 35 days (cohort metrics)

**Variable Definitions:**
```sql
{% set lookback_window_days = 7 %}
{% set click_weight_multiplier = 2.0 %}
{% set time_decay_half_life_days = 3 %}
```
- Define at top of model after config block
- Use descriptive names
- Include unit in name when applicable

**Source/Ref Usage:**
- Use `{{ source('source_name', 'TABLE_NAME') }}` for external sources
- Use `{{ ref('model_name') }}` for dbt models
- Source names lowercase, table names UPPERCASE
- Model names lowercase with underscores

## Platform/OS Handling

**Standardization Pattern:**
```sql
CASE
    WHEN LOWER(OS_NAME) = 'ios' THEN 'iOS'
    WHEN LOWER(OS_NAME) = 'android' THEN 'Android'
    ELSE OS_NAME
END AS PLATFORM
```
- Always standardize to `iOS` or `Android` (proper casing)
- Use `LOWER()` for case-insensitive matching

**Device ID Handling:**
```sql
-- iOS: IDFV (already uppercase)
-- Android: GPS_ADID with trailing 'R' stripped from Amplitude
UPPER(
    IFF(PLATFORM = 'Android' AND RIGHT(DEVICE_ID, 1) = 'R'
       , LEFT(DEVICE_ID, LENGTH(DEVICE_ID) - 1)
       , DEVICE_ID
    )
) AS DEVICE_ID_UUID
```
- Always UPPER() device IDs for cross-source joins
- Handle Amplitude's trailing 'R' suffix on Android IDs

## Ad Partner Mapping

**Standard CASE Statement (must match across models):**
```sql
CASE
    WHEN NETWORK_NAME IN ('Facebook Installs', 'Instagram Installs',
                          'Off-Facebook Installs', 'Facebook Messenger Installs') THEN 'Meta'
    WHEN NETWORK_NAME IN ('Google Ads ACE', 'Google Ads ACI',
                          'Google Organic Search', 'google') THEN 'Google'
    WHEN NETWORK_NAME IN ('TikTok SAN', 'TikTok_Paid_Ads_iOS',
                          'Tiktok Installs') THEN 'TikTok'
    WHEN NETWORK_NAME = 'Apple Search Ads' THEN 'Apple'
    WHEN NETWORK_NAME LIKE 'AppLovin%' THEN 'AppLovin'
    WHEN NETWORK_NAME LIKE 'UnityAds%' THEN 'Unity'
    WHEN NETWORK_NAME LIKE 'Moloco%' THEN 'Moloco'
    WHEN NETWORK_NAME LIKE 'Smadex%' THEN 'Smadex'
    WHEN NETWORK_NAME LIKE 'AdAction%' THEN 'AdAction'
    WHEN NETWORK_NAME LIKE 'Vungle%' THEN 'Vungle'
    WHEN NETWORK_NAME = 'Organic' THEN 'Organic'
    WHEN NETWORK_NAME = 'Unattributed' THEN 'Unattributed'
    WHEN NETWORK_NAME = 'Untrusted Devices' THEN 'Untrusted'
    ELSE 'Other'
END AS AD_PARTNER
```
- Used in: `v_stg_adjust__installs.sql`, `v_stg_adjust__touchpoints.sql`
- Also maintained in seed: `seeds/network_mapping.csv`

## Null Handling

**COALESCE for Defaults:**
```sql
COALESCE(um.D7_REVENUE, 0) AS USER_D7_REVENUE
COALESCE(RA.PURCHASERS, 0) AS PURCHASERS
```
- Use COALESCE with 0 for metrics that should default to zero

**NULLIF for Division:**
```sql
BASE_TYPE_WEIGHT / NULLIF(TOTAL_TYPE_WEIGHT, 0) AS CREDIT_LINEAR
```
- Always use NULLIF when dividing to prevent divide-by-zero

**IFF for Conditional Calculations:**
```sql
IFF(INSTALLS_CURRENT > 0, COST / INSTALLS_CURRENT, NULL) AS CPI_CURRENT
IFF(COST > 0, REVENUE / COST, NULL) AS ROAS
```
- Use IFF() for Snowflake (not CASE WHEN for simple conditionals)
- Return NULL rather than 0 for invalid metric calculations

## Deduplication Patterns

**ROW_NUMBER with QUALIFY:**
```sql
SELECT *
FROM combined
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY DEVICE_ID, PLATFORM
    ORDER BY INSTALL_TIMESTAMP ASC
) = 1
```
- Use QUALIFY clause (Snowflake-specific) for cleaner deduplication
- Always specify ORDER BY to make deterministic

**Aggregation Deduplication:**
```sql
SELECT DISTINCT
    COLUMN_A
    , COLUMN_B
FROM table
WHERE condition IS NOT NULL
```

## Comment Style

**Model Header:**
```sql
-- model_name.sql
-- Purpose description in plain English
-- Additional context about join logic or business rules
--
-- Grain: One row per [entity combination]
```

**Section Dividers:**
```sql
-- =============================================
-- SECTION NAME
-- =============================================
```
- Used to separate logical sections in long models
- Examples: INSTALL ATTRIBUTION BY MODEL, D7 REVENUE ATTRIBUTION BY MODEL

**Inline Comments:**
```sql
-- 3-day lookback to capture late-arriving data from S3 ingestion
AND LOAD_TIMESTAMP >= DATEADD(day, -3, ...)
```
- Explain WHY, not WHAT
- Always explain lookback window durations

## Error Handling

**TRY_CAST for Type Coercion:**
```sql
TRY_CAST(EVENT_PROPERTIES:"$revenue"::STRING AS FLOAT)
```
- Use TRY_CAST to handle malformed data gracefully

**JSON Parsing:**
```sql
COALESCE(EVENT_PROPERTIES:"tu"::STRING, 'unknown') AS REVENUE_TYPE
TRY_PARSE_JSON(AE.EVENT_PROPERTIES):EventSource::STRING
```
- Use COALESCE with default when JSON key may be missing
- Use TRY_PARSE_JSON when JSON might be malformed

## Import Organization

**Model Dependencies Order:**
1. Config block
2. Variable definitions ({% set %})
3. CTEs in logical order:
   - Source/ref imports
   - Transformation CTEs
   - Aggregation CTEs
   - Final join/select
4. Final SELECT

---

*Convention analysis: 2026-01-19*
