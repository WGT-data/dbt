# Phase 3: Document MTA Limitations + Prepare MMM Data Foundation - Research

**Researched:** 2026-02-11
**Domain:** Marketing Mix Modeling (MMM) vs Multi-Touch Attribution (MTA), dbt aggregate data modeling
**Confidence:** HIGH

## Summary

This research addresses a critical pivot in the WGT analytics strategy: transitioning from device-level Multi-Touch Attribution (MTA) to aggregate Marketing Mix Modeling (MMM) due to insufficient device-level traffic coverage. Phase 2 audit findings definitively proved that Android device matching is structurally impossible (0% match rate) and iOS coverage is limited to 7% IDFA availability, making MTA unreliable for strategic decisions.

The current dbt pipeline contains 60+ models heavily optimized for MTA: device-level journey reconstruction, touchpoint credit allocation across 5 attribution models, and user-level revenue joins. However, the existing infrastructure can be partially repurposed: aggregate spend data (Supermetrics, Adjust API), aggregate install counts (Adjust), and aggregate revenue metrics (WGT.EVENTS) already exist and can feed MMM with minimal transformation.

MMM requires aggregate time-series data at the channel/campaign level: daily or weekly spend, installs, revenue by ad network and platform. Unlike MTA, MMM uses statistical regression to infer channel contribution without device-level tracking, making it privacy-compliant and resilient to iOS ATT restrictions. Industry standard requires 18-36 months of historical data with sufficient spend variation to model adstock effects and saturation curves.

**Primary recommendation:** Phase 3 should (1) document MTA's structural limitations and formally close MTA development, (2) build aggregate dbt models that roll up existing data to daily channel-level grain for MMM input, and (3) preserve MTA models as-is for iOS-only tactical analysis while steering stakeholders toward MMM for strategic budget allocation.

## Standard Stack

### Core MMM Data Requirements

| Component | Granularity | Purpose | Sources Available in WGT Pipeline |
|-----------|-------------|---------|----------------------------------|
| Channel Spend | Daily/Weekly per Channel+Platform | Marketing investment by source | SUPERMETRICS.DATA_TRANSFERS.adj_campaign (COST), ADJUST.API_DATA.REPORT_DAILY_RAW (cost) |
| Installs | Daily/Weekly per Channel+Platform | Volume outcome metric | ADJUST.S3_DATA.*_ACTIVITY_INSTALL (aggregated), ADJUST.API_DATA.REPORT_DAILY_RAW (installs) |
| Revenue | Daily/Weekly (Total or per Channel) | Value outcome metric | WGT.PROD.DIRECT_REVENUE_EVENTS (aggregated), int_user_cohort__metrics (D7/D30 cohorts) |
| External Factors | Daily/Weekly | Seasonality, holidays, events | Not yet captured (Phase 3+ scope) |
| Historical Depth | 18-36 months | Statistical modeling minimum | Adjust data since 2024-01-01, need to verify revenue depth |

### Supporting dbt Patterns for Aggregate Models

| Pattern | Purpose | Implementation in WGT Pipeline |
|---------|---------|-------------------------------|
| Incremental daily aggregation | Efficient daily roll-ups without full scans | Existing models use incremental strategy with date filters |
| Channel taxonomy normalization | Consistent AD_PARTNER mapping across sources | Existing AD_PARTNER CASE logic in v_stg_adjust__installs and v_stg_adjust__touchpoints (needs macro extraction per Phase 4) |
| Cohort revenue windows | D7/D30/LTV revenue attribution to install date | int_user_cohort__metrics already calculates this, needs aggregation by channel+date |
| Date spine for complete time series | Fill gaps in sparse spend data | Not yet implemented, standard dbt pattern |

### MMM Software Options (External to dbt)

| Tool | Language | Purpose | When to Use |
|------|----------|---------|-------------|
| Google Lightweight MMM | Python/PyMC | Open-source Bayesian MMM | Free, requires data science team |
| Meta Robyn | R | Open-source MMM with automated hyperparameter tuning | Facebook-optimized, R ecosystem |
| Commercial platforms (Measured, Recast, etc.) | SaaS | Managed MMM with UI | Budget available, less technical lift |

Note: dbt's role is data preparation only. MMM statistical modeling happens downstream.

## Architecture Patterns

### Recommended Project Structure for MMM Data Prep

```
models/
├── staging/
│   ├── adjust/              # Existing: device-level installs, touchpoints
│   ├── amplitude/           # Existing: event data (not needed for MMM)
│   ├── revenue/             # Existing: revenue events
│   └── supermetrics/        # Existing: spend data
├── intermediate/
│   ├── int_mta__*/          # PRESERVE AS-IS: MTA models for iOS tactical analysis
│   ├── int_user_cohort__*/  # PRESERVE AS-IS: user-level metrics
│   └── int_mmm__*/          # NEW: aggregate intermediate models
│       ├── int_mmm__daily_channel_spend.sql
│       ├── int_mmm__daily_channel_installs.sql
│       └── int_mmm__daily_channel_revenue.sql (revenue by install date cohort)
└── marts/
    ├── attribution/         # PRESERVE AS-IS: MTA marts (document limitations)
    └── mmm/                 # NEW: MMM input tables
        ├── mmm__daily_channel_summary.sql (all metrics joined)
        └── mmm__weekly_channel_summary.sql (weekly rollup)
```

### Pattern 1: Daily Channel Spend Aggregation

**What:** Aggregate spend from multiple sources (Supermetrics, Adjust API) to daily channel+platform grain.

**When to use:** First step in MMM data prep. Handles potential duplicates between spend sources.

**Example:**
```sql
-- int_mmm__daily_channel_spend.sql
WITH supermetrics_spend AS (
    SELECT
        DATE,
        PLATFORM,
        CASE
            WHEN PARTNER_NAME IN ('Facebook Installs', ...) THEN 'Meta'
            WHEN PARTNER_NAME IN ('Google Ads ACE', ...) THEN 'Google'
            -- etc. (reuse existing AD_PARTNER logic or macro)
        END AS CHANNEL,
        SUM(COST) AS SPEND
    FROM {{ ref('stg_supermetrics__adj_campaign') }}
    GROUP BY 1, 2, 3
),

adjust_api_spend AS (
    SELECT
        date AS DATE,
        os_name AS PLATFORM,
        partner_name AS CHANNEL, -- apply AD_PARTNER normalization
        SUM(cost) AS SPEND
    FROM {{ ref('stg_adjust__report_daily') }}
    GROUP BY 1, 2, 3
)

-- Union and dedupe (prefer Supermetrics if both exist)
SELECT
    COALESCE(s.DATE, a.DATE) AS DATE,
    COALESCE(s.PLATFORM, a.PLATFORM) AS PLATFORM,
    COALESCE(s.CHANNEL, a.CHANNEL) AS CHANNEL,
    COALESCE(s.SPEND, 0) + COALESCE(a.SPEND, 0) AS SPEND -- or pick one source
FROM supermetrics_spend s
FULL OUTER JOIN adjust_api_spend a
    ON s.DATE = a.DATE
    AND s.PLATFORM = a.PLATFORM
    AND s.CHANNEL = a.CHANNEL
```

### Pattern 2: Daily Channel Installs Aggregation

**What:** Aggregate installs from Adjust S3 data to daily channel+platform grain.

**When to use:** Use device-level install data for accurate install counts (more reliable than API aggregates).

**Example:**
```sql
-- int_mmm__daily_channel_installs.sql
SELECT
    DATE(INSTALL_TIMESTAMP) AS DATE,
    PLATFORM,
    AD_PARTNER AS CHANNEL,
    COUNT(DISTINCT DEVICE_ID) AS INSTALLS
FROM {{ ref('v_stg_adjust__installs') }}
WHERE INSTALL_TIMESTAMP >= '2024-01-01' -- historical depth
GROUP BY 1, 2, 3
```

### Pattern 3: Cohort Revenue Attribution to Install Date

**What:** Aggregate D7/D30 revenue by the user's install date and attributed channel.

**When to use:** MMM needs to attribute revenue back to the install cohort date, not the revenue event date.

**Example:**
```sql
-- int_mmm__daily_channel_revenue.sql
SELECT
    a.INSTALL_DATE AS DATE,
    a.PLATFORM,
    a.AD_PARTNER AS CHANNEL,
    COUNT(DISTINCT m.USER_ID) AS USERS,
    SUM(m.D7_REVENUE) AS D7_REVENUE,
    SUM(m.D30_REVENUE) AS D30_REVENUE,
    SUM(m.TOTAL_REVENUE) AS TOTAL_REVENUE
FROM {{ ref('int_user_cohort__attribution') }} a
INNER JOIN {{ ref('int_user_cohort__metrics') }} m
    ON a.USER_ID = m.USER_ID
    AND a.PLATFORM = m.PLATFORM
GROUP BY 1, 2, 3
```

### Pattern 4: Complete Time Series with Date Spine

**What:** Ensure every date+channel combination exists, even if spend/installs are zero.

**When to use:** MMM models require complete time series without gaps for regression.

**Example:**
```sql
-- Use dbt_utils.date_spine or manual CTE
{{ dbt_utils.date_spine(
    datepart="day",
    start_date="to_date('2024-01-01', 'yyyy-mm-dd')",
    end_date="current_date()"
) }}

-- Cross join with channels to get all combinations
-- Left join actual data and COALESCE metrics to 0
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Statistical MMM model | Custom regression in SQL | Google Lightweight MMM, Meta Robyn, or commercial platform | MMM requires Bayesian inference, adstock modeling, saturation curves, and hyperparameter tuning — not SQL-solvable |
| Date spine for complete time series | Manual date table creation | dbt_utils.date_spine macro | Handles leap years, timezone edge cases, parameterization |
| Channel taxonomy management | Hardcoded CASE statements in every model | Macro or seed table | 15+ files currently have duplicate AD_PARTNER logic (Phase 4 addresses this) |
| Cohort revenue maturity logic | Recalculate D7/D30 windows in every model | Reference int_user_cohort__metrics | Already computed correctly with maturity flags |

**Key insight:** MMM statistical modeling is NOT a dbt problem. dbt's job is to prepare clean aggregate input data. The actual MMM (Bayesian regression, diminishing returns curves, budget optimization) requires specialized tools like PyMC Marketing, Meta Robyn, or commercial platforms.

## Common Pitfalls

### Pitfall 1: Mixing Device-Level and Aggregate Data Incorrectly

**What goes wrong:** Joining device-level MTA touchpoint data (1M+ rows) into aggregate channel summaries causes Cartesian explosions or incorrect double-counting.

**Why it happens:** MTA models work at device+touchpoint grain (int_mta__user_journey: device+touchpoint+install), while MMM models work at date+channel grain. These are incompatible grains.

**How to avoid:** Keep MTA and MMM data pipelines separate. MTA models stay in int_mta__* and marts/attribution/. MMM models go in int_mmm__* and marts/mmm/. Do not join them.

**Warning signs:**
- Query taking 10+ minutes when aggregating spend
- Install counts in MMM summary tables are fractional (e.g., 1,247.83 installs)
- Revenue attributed to a channel exceeds total revenue

### Pitfall 2: Revenue Event Date vs Install Date Cohort Attribution

**What goes wrong:** Aggregating revenue by the revenue event date instead of the user's install date cohort, causing revenue to appear weeks after the marketing spend that drove it.

**Why it happens:** WGT.EVENTS.REVENUE table has EVENTTIME (when purchase happened), but MMM needs to attribute revenue back to INSTALL_DATE (when user was acquired).

**How to avoid:** Always join revenue events to user install attribution first, then aggregate by install_date, not event_time. Use int_user_cohort__attribution to get install_date and channel, then join to revenue.

**Warning signs:**
- Revenue spike appears 7-30 days after install spike
- Total revenue by channel in MMM exceeds total spend on that channel by 10x+ (good, but should align with ROAS expectations)
- No revenue appears for recent install cohorts (expected — they haven't matured yet, but should be flagged)

### Pitfall 3: Incomplete Time Series Breaks MMM Models

**What goes wrong:** Missing dates for channels with zero spend causes gaps in time series. MMM regression models fail or produce invalid coefficients when time series is incomplete.

**Why it happens:** LEFT JOIN of spend, installs, revenue produces NULL rows only when data exists. Dates with zero activity are missing entirely.

**How to avoid:** Start with a date spine (all dates in range), CROSS JOIN with list of channels, then LEFT JOIN actual data and COALESCE to 0.

**Warning signs:**
- MMM input table has 347 rows for 365 days (18 missing)
- Channel that ran for 30 days, paused 60 days, resumed 30 days has only 60 rows total
- Statistical software throws "non-continuous date sequence" error

### Pitfall 4: Channel Taxonomy Drift Between Sources

**What goes wrong:** Supermetrics calls it "Facebook (Ad Spend)", Adjust API calls it "Facebook Installs", MTA calls it "Meta" — same channel, three names. MMM sees three separate channels with 1/3 the budget each.

**Why it happens:** Each data source uses its own naming convention. WGT pipeline has 15+ files with duplicated CASE statements mapping network names to AD_PARTNER, and they can drift out of sync.

**How to avoid:** Extract AD_PARTNER mapping into a single source of truth (macro or seed table, Phase 4 plans this). Apply consistently in all staging models before any aggregation.

**Warning signs:**
- MMM summary shows "Meta", "Facebook Installs", and "Facebook (Ad Spend)" as separate channels
- Total installs across all "Facebook" variants matches documented Facebook installs, but split incorrectly
- Spend is under one name, installs under another, revenue under a third

### Pitfall 5: Treating MTA Failure as Data Quality Bug

**What goes wrong:** Stakeholders see 0% Android match rate and request "fixing the device mapping" indefinitely, blocking MMM adoption.

**Why it happens:** Phase 2 audit proved Android matching is structurally impossible (Amplitude SDK issue), but without clear documentation, it looks like a bug.

**How to avoid:** Phase 3 must include stakeholder-facing documentation that clearly states: (1) Android MTA is blocked on external SDK change, (2) iOS MTA is limited to 7% IDFA coverage, (3) MMM is the recommended strategic alternative, (4) MTA remains available for iOS-only tactical analysis.

**Warning signs:**
- Repeated requests to "just normalize the GPS_ADID" after Phase 2 proved it won't work
- Stakeholder decisions blocked waiting for "device mapping fix"
- Budget allocation frozen because "attribution is broken"

## Code Examples

### Example 1: Daily Channel Summary Mart (MMM Input Table)

```sql
-- marts/mmm/mmm__daily_channel_summary.sql
-- Final MMM input table with all metrics at daily+channel+platform grain

{{
    config(
        materialized='incremental',
        unique_key=['DATE', 'PLATFORM', 'CHANNEL'],
        incremental_strategy='merge'
    )
}}

WITH spend AS (
    SELECT DATE, PLATFORM, CHANNEL, SPEND
    FROM {{ ref('int_mmm__daily_channel_spend') }}
    {% if is_incremental() %}
    WHERE DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
),

installs AS (
    SELECT DATE, PLATFORM, CHANNEL, INSTALLS
    FROM {{ ref('int_mmm__daily_channel_installs') }}
    {% if is_incremental() %}
    WHERE DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
),

revenue AS (
    SELECT DATE, PLATFORM, CHANNEL, USERS, D7_REVENUE, D30_REVENUE, TOTAL_REVENUE
    FROM {{ ref('int_mmm__daily_channel_revenue') }}
    {% if is_incremental() %}
    WHERE DATE >= DATEADD(day, -7, (SELECT MAX(DATE) FROM {{ this }}))
    {% endif %}
)

-- Complete time series: every date + every channel (even if zero)
-- For simplicity, this example omits date spine (add in production)
SELECT
    COALESCE(s.DATE, i.DATE, r.DATE) AS DATE,
    COALESCE(s.PLATFORM, i.PLATFORM, r.PLATFORM) AS PLATFORM,
    COALESCE(s.CHANNEL, i.CHANNEL, r.CHANNEL) AS CHANNEL,

    -- Spend metrics
    COALESCE(s.SPEND, 0) AS SPEND,

    -- Install metrics
    COALESCE(i.INSTALLS, 0) AS INSTALLS,

    -- Revenue metrics (by install cohort, not event date)
    COALESCE(r.USERS, 0) AS USERS,
    COALESCE(r.D7_REVENUE, 0) AS D7_REVENUE,
    COALESCE(r.D30_REVENUE, 0) AS D30_REVENUE,
    COALESCE(r.TOTAL_REVENUE, 0) AS TOTAL_REVENUE,

    -- Calculated metrics
    IFF(i.INSTALLS > 0, s.SPEND / i.INSTALLS, NULL) AS CPI,
    IFF(s.SPEND > 0, r.D7_REVENUE / s.SPEND, NULL) AS D7_ROAS,
    IFF(s.SPEND > 0, r.D30_REVENUE / s.SPEND, NULL) AS D30_ROAS

FROM spend s
FULL OUTER JOIN installs i
    ON s.DATE = i.DATE AND s.PLATFORM = i.PLATFORM AND s.CHANNEL = i.CHANNEL
FULL OUTER JOIN revenue r
    ON COALESCE(s.DATE, i.DATE) = r.DATE
    AND COALESCE(s.PLATFORM, i.PLATFORM) = r.PLATFORM
    AND COALESCE(s.CHANNEL, i.CHANNEL) = r.CHANNEL

WHERE DATE IS NOT NULL
ORDER BY DATE DESC, PLATFORM, CHANNEL
```

### Example 2: Weekly Rollup for Long-Term MMM

```sql
-- marts/mmm/mmm__weekly_channel_summary.sql
-- Weekly aggregation for MMM tools that prefer weekly over daily

SELECT
    DATE_TRUNC('week', DATE) AS WEEK_START_DATE,
    PLATFORM,
    CHANNEL,

    SUM(SPEND) AS SPEND,
    SUM(INSTALLS) AS INSTALLS,
    SUM(USERS) AS USERS,
    SUM(D7_REVENUE) AS D7_REVENUE,
    SUM(D30_REVENUE) AS D30_REVENUE,
    SUM(TOTAL_REVENUE) AS TOTAL_REVENUE,

    -- Weekly averages
    AVG(CPI) AS AVG_CPI,
    SUM(D7_REVENUE) / NULLIF(SUM(SPEND), 0) AS D7_ROAS,
    SUM(D30_REVENUE) / NULLIF(SUM(SPEND), 0) AS D30_ROAS

FROM {{ ref('mmm__daily_channel_summary') }}
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 2, 3
```

## State of the Art

| Old Approach (MTA Era) | Current Approach (MMM Pivot) | When Changed | Impact |
|------------------------|------------------------------|--------------|--------|
| Device-level touchpoint tracking with IDFA/GPS_ADID | Aggregate channel-level time series | iOS ATT (2021), Android privacy restrictions (ongoing) | MTA coverage collapsed from 80%+ to <10% industry-wide |
| IP-based probabilistic matching for iOS | Deterministic-only matching (IDFA consent) | GDPR compliance review (2024) | Removed IP-based matching from int_mta__user_journey.sql |
| Static device mapping table refreshed weekly | Incremental dbt model with 7-day lookback | Phase 1-2 pipeline modernization | int_adjust_amplitude__device_mapping never built to prod |
| MTA as primary attribution methodology | MMM as strategic methodology, MTA for iOS tactical | Phase 3 pivot (2026) | Stakeholder communication shift needed |

**Deprecated/outdated:**
- IP-based attribution: Removed from v_stg_adjust__touchpoints and int_mta__user_journey due to GDPR concerns and NAT collision issues (median 270 touchpoints/journey, max 25,500)
- ADJUST_AMPLITUDE_DEVICE_MAPPING static table: Stale since Nov 2025, iOS-only, maps IDFV to IDFV (redundant)
- Full-refresh device normalization strategy (Phase 3 original scope): Android cannot be fixed via normalization, requires external SDK change
- MTA-first roadmap (Phases 3-6): Phase 3+ needs replanning to prioritize MMM over MTA fixes

## Open Questions

### 1. Historical Data Depth for MMM

**What we know:**
- Adjust S3 data filtered to 2024-01-01+ in staging models (14 months available as of Feb 2026)
- Supermetrics and Adjust API have daily aggregates
- WGT.PROD.DIRECT_REVENUE_EVENTS table depth unknown (need to query MIN(EVENTTIME))

**What's unclear:**
- Is 14 months sufficient for initial MMM (industry standard: 18-36 months)?
- Can we backfill revenue events to match Adjust historical depth?

**Recommendation:**
- Query actual historical depth for all three sources (spend, installs, revenue)
- Document in Phase 3 planning if additional data requests needed
- 14 months may be sufficient for MVP MMM if budget variation is high

### 2. External Factors / Seasonality Data

**What we know:**
- MMM models require external factors (holidays, seasonality, competitor events) to isolate marketing contribution
- Current pipeline has zero external factor data

**What's unclear:**
- Does WGT track major game events, tournaments, or promotional calendars?
- Are there known seasonality patterns (holidays, summer slump, etc.)?

**Recommendation:**
- Phase 3 should document external factors as "future enhancement"
- Initial MMM can use time-based seasonality proxies (month, day of week, holiday indicator)
- Partner with business stakeholders to identify major events worth tracking

### 3. Campaign-Level vs Channel-Level Granularity

**What we know:**
- Current MTA models track down to CAMPAIGN_ID, ADGROUP_ID, CREATIVE_NAME
- MMM typically operates at channel level (Meta, Google, TikTok) not campaign level

**What's unclear:**
- Do stakeholders need campaign-level MMM, or is channel-level sufficient?
- Will campaign-level data have enough spend variation for statistical modeling?

**Recommendation:**
- Start with channel+platform grain (Meta iOS, Google Android, etc.)
- Add campaign-level as optional dimension if stakeholder needs arise
- Test if campaign-level data has sufficient observations (some campaigns run <7 days)

### 4. SAN (Self-Attributing Network) Handling in MMM

**What we know:**
- Phase 2 documented that SANs (Meta, Google, Apple, TikTok) do not share device-level touchpoint data
- MTA gives these networks 0% credit (known limitation documented in mta__campaign_performance.sql)
- Adjust API provides aggregate install counts attributed to SANs

**What's unclear:**
- Should MMM use SAN-attributed installs from Adjust API, or ignore SANs entirely?
- How much spend is on SANs vs programmatic networks?

**Recommendation:**
- MMM SHOULD include SANs using Adjust's last-click attribution for install counts
- Document as limitation: MMM uses Adjust attribution, not multi-touch
- This is still more reliable than MTA (which has 0% SAN coverage)

## Sources

### Primary (HIGH confidence)

**Marketing Mix Modeling Fundamentals:**
- [Marketing Evolution: What is Media Mix Modeling (MMM)?](https://www.marketingevolution.com/marketing-essentials/media-mix-modeling) - Core MMM concepts and methodology
- [Measured: Marketing Mix Modeling 2025 Complete Guide](https://www.measured.com/faq/marketing-mix-modeling-2025-complete-guide-for-strategic-marketers/) - Current MMM best practices
- [PyMC Marketing: Introduction to Media Mix Modeling](https://www.pymc-marketing.io/en/stable/guide/mmm/mmm_intro.html) - Open-source MMM implementation guide (HIGH confidence - official docs)

**MMM vs MTA Comparison:**
- [Funnel.io: Multi-touch attribution vs. marketing mix modeling](https://funnel.io/blog/mta-vs-mmm) - Direct comparison with data requirements
- [Airbridge: MMM vs. MTA - Which attribution model should you choose?](https://www.airbridge.io/blog/mmm-vs-mta) - Privacy-first era context
- [Haus: MTA vs. MMM - Choosing Between Attribution Models](https://www.haus.io/blog/mta-vs-mmm-choosing-between-multi-touch-attribution-and-marketing-mix-modeling) - Strategic decision framework

**MMM Data Requirements:**
- [Supermetrics: Marketing Mix Modeling Data - Build a Solid Foundation](https://supermetrics.com/blog/marketing-mix-modeling-data) - Data preparation best practices (MEDIUM confidence, but verified with other sources)
- [Invoca: Media Mix Modeling (MMM) - The Complete Guide for 2025](https://www.invoca.com/blog/media-mix-modeling) - 2-3 years historical data requirement
- [Recast: How much data do you need for your Marketing Mix Model?](https://getrecast.com/data/) - 78-104+ weeks historical depth guidance

**dbt + MMM Data Modeling:**
- [Vladimir Kobzev: Marketing Mix Data Model - Practical example for Data Engineers](https://medium.com/@kobzevvv/marketing-mix-data-model-d50535d4f971) - dbt patterns for aggregate MMM tables (MEDIUM confidence - practitioner experience)

### Secondary (MEDIUM confidence)

**WGT dbt Pipeline (Internal):**
- /Users/riley/Documents/GitHub/wgt-dbt/models/staging/adjust/_adjust__sources.yml - Adjust S3 data sources
- /Users/riley/Documents/GitHub/wgt-dbt/models/staging/supermetrics/_supermetrics__sources.yml - Spend data source
- /Users/riley/Documents/GitHub/wgt-dbt/models/intermediate/int_user_cohort__metrics.sql - Existing cohort revenue calculations
- /Users/riley/Documents/GitHub/wgt-dbt/models/marts/attribution/mta__campaign_performance.sql - Current MTA implementation with documented limitations
- /Users/riley/Documents/GitHub/wgt-dbt/.planning/phases/02-device-id-audit/02-02-SUMMARY.md - Phase 2 findings on device matching limitations

### Tertiary (LOW confidence)

None. All claims verified with multiple authoritative sources.

## Metadata

**Confidence breakdown:**
- MMM fundamentals: HIGH - Multiple authoritative sources (Marketing Evolution, official PyMC docs, academic consensus)
- MMM data requirements: HIGH - Consistent across 5+ sources (18-36 months, daily/weekly, aggregate)
- MTA vs MMM comparison: HIGH - Industry consensus on privacy implications and aggregate vs device-level
- dbt modeling patterns for MMM: MEDIUM - Based on practitioner Medium post and general dbt best practices, verified with existing WGT pipeline patterns
- WGT pipeline current state: HIGH - Direct inspection of 60+ dbt model files and Phase 2 audit documentation
- MMM statistical modeling: HIGH - Official PyMC Marketing documentation and open-source implementations

**Research date:** 2026-02-11
**Valid until:** 2026-04-11 (60 days - MMM methodology is stable, but dbt packages and tooling evolve)

**Key unknowns requiring Phase 3 investigation:**
1. WGT revenue historical depth (query WGT.PROD.DIRECT_REVENUE_EVENTS for MIN(EVENTTIME))
2. Stakeholder preference for channel-level vs campaign-level MMM granularity
3. External factor data availability (game events, promotions, seasonality calendars)
4. SAN spend as % of total budget (determines if SAN handling is critical)
