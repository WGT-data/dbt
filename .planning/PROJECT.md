# WGT dbt Analytics

## What This Is

A dbt project that transforms raw mobile attribution (Adjust), product analytics (Amplitude), ad spend (Supermetrics), and revenue data into unified marketing performance marts for WGT Golf. Enables multi-touch attribution analysis, campaign ROI measurement, and user cohort metrics across iOS and Android.

## Core Value

Accurately attribute user acquisition spend to downstream revenue by connecting ad touchpoints to in-app behavior across Adjust and Amplitude.

## Current Milestone: v1.0 Data Integrity

**Goal:** Fix the broken device mapping between Adjust and Amplitude so MTA revenue actually works, and add foundational data quality guardrails across the project.

**Target features:**
- Investigate and fix Android device ID mapping (GPS_ADID doesn't match Amplitude device_id)
- Investigate and improve iOS MTA touchpoint-to-Amplitude match rate (currently 1.4%)
- Add uniqueness and not-null tests for all model grain definitions
- Add source freshness checks for Adjust, Amplitude, Supermetrics pipelines
- Refactor duplicated AD_PARTNER mapping logic into a centralized macro or seed
- Centralize device ID normalization at the staging layer

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- Staging layer: Adjust (iOS/Android installs, touchpoints, activity splitters), Amplitude (events, merge IDs), Supermetrics (ad spend), Revenue (purchase events)
- Device mapping: Adjust IDFV → Amplitude USER_ID (iOS path confirmed working)
- MTA engine: 5 attribution models (last-touch, first-touch, linear, time-decay, position-based) with configurable weights
- User cohort metrics: D7/D30/lifetime revenue, retention (D1/D7/D30), payer status
- Campaign performance mart: Spend + Adjust attribution + MTA at campaign level
- Network performance mart: Spend + Adjust attribution + MTA at partner level (newly built)
- Schema routing: `generate_schema_name` macro for dev/prod environment targeting in dbt Cloud

### Active

<!-- Current scope. Building toward these. -->

- [ ] Fix Android device mapping between Adjust and Amplitude
- [ ] Improve iOS MTA touchpoint mapping rate
- [ ] Add dbt uniqueness and not-null tests
- [ ] Add source freshness checks
- [ ] Refactor duplicated AD_PARTNER mapping logic
- [ ] Centralize device ID normalization

### Out of Scope

- New mart models or dashboards — focus is on data integrity first
- Real-time alerting or monitoring infrastructure — freshness checks only
- CI/CD pipeline setup — defer to future milestone
- dbt packages (dbt-utils, dbt-expectations) — evaluate later

## Context

- **Environment:** dbt Cloud (production), Snowflake warehouse, no local dbt run capability (key-pair auth)
- **Schema routing:** Dev → `DBT_WGTDATA`/`DEV_S3_DATA`, Prod → `PROD`/`S3_DATA` (via `generate_schema_name` macro checking `target.name == 'dev'`)
- **Android mapping gap:** `ANDROID_EVENTS` has GPS_ADID (Google Advertising ID) and ADID (Adjust hash) but neither matches Amplitude's device_id. IDFV column exists but is 0% populated. IDFA on Android touchpoints = GPS_ADID (same value, different casing).
- **iOS mapping confirmed:** IDFV from Adjust = Amplitude device_id. Works when device exists in both systems.
- **SAN limitation:** Self-Attributing Networks (Meta, Google, Apple, TikTok) don't share touchpoint data — MTA will always be 0 for them. Use Adjust attribution columns instead.
- **Stale data fixed:** S3 activity tables were stale until Nov 2025; fixed by correcting schema routing so splitter models write to `S3_DATA` in production.

## Constraints

- **Platform:** Snowflake SQL + dbt (Jinja) — all transformations must be expressible in this stack
- **Execution:** dbt Cloud only — cannot run dbt locally (RSA key-pair not configured)
- **Data sources:** Read-only access to Adjust S3, Amplitude share, Supermetrics, WGT revenue tables
- **SDK changes:** Any fix requiring Adjust/Amplitude SDK modifications is outside dbt scope (flag as external dependency)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Flip `generate_schema_name` to check `dev` instead of `prod` | dbt Cloud production target name isn't literally 'prod' | ✓ Good — fixed stale S3 activity tables |
| Create network-level MTA mart (drop CAMPAIGN_NAME dimension) | Campaign names don't match between spend and MTA sources; partner-level reporting is the primary use case | ✓ Good — MTA installs now populate at network level |
| FULL OUTER JOIN pattern for combining spend + attribution + MTA | Need to see all data even when sources don't overlap | ⚠️ Revisit — creates orphan rows, consider LEFT JOIN alternatives |

---
*Last updated: 2026-02-10 after milestone v1.0 initialization*
