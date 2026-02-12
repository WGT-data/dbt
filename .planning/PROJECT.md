# WGT dbt Analytics

## What This Is

A dbt project that transforms raw mobile attribution (Adjust), product analytics (Amplitude), ad spend (Supermetrics), and revenue data into unified marketing performance marts for WGT Golf. Provides MMM-ready aggregate models for budget allocation, MTA models for iOS tactical analysis, and comprehensive data quality testing across the pipeline.

## Core Value

Accurately measure marketing channel performance by aggregating spend, installs, and revenue at the channel+platform level, enabling data-driven budget allocation through Marketing Mix Modeling.

## Requirements

### Validated

- ✓ Staging layer: Adjust (iOS/Android installs, touchpoints, activity splitters), Amplitude (events, merge IDs), Supermetrics (ad spend), Revenue (purchase events) — pre-v1.0
- ✓ Device mapping: Adjust IDFV → Amplitude USER_ID (iOS path confirmed 69.78% match) — v1.0
- ✓ MTA engine: 5 attribution models with configurable weights (iOS-only tactical use) — pre-v1.0
- ✓ User cohort metrics: D7/D30/lifetime revenue, retention, payer status — pre-v1.0
- ✓ Campaign + Network performance marts — pre-v1.0
- ✓ Schema routing: `generate_schema_name` macro for dev/prod targeting — pre-v1.0
- ✓ Device ID audit with baseline match rates documented — v1.0
- ✓ MTA limitations documented with stakeholder-facing explanation — v1.0
- ✓ MMM pipeline: daily/weekly channel summaries with date spine, SKAN installs, zero-fill flags — v1.0
- ✓ AD_PARTNER macro: centralized mapping logic with regression test — v1.0
- ✓ Test suite: 29 tests (25 generic + 4 singular) covering all model layers — v1.0
- ✓ Source freshness: 16 sources monitored via dbt Cloud (every 6h) — v1.0
- ✓ Static table staleness detection for ADJUST_AMPLITUDE_DEVICE_MAPPING — v1.0

### Active

- [ ] CI/CD pipeline gates PRs on test passage (deferred from v1.0)
- [ ] dbt-expectations package for advanced validation tests
- [ ] Elementary anomaly detection on mart models
- [ ] Unit tests for macros (dbt v1.8+ framework)
- [ ] Automated backfill detection for incremental model gaps
- [ ] Hardcoded date filters replaced with dbt vars

### Out of Scope

- MTA development work — formally closed, models preserved with limitation headers
- Fuzzy/ML device ID matching — non-deterministic, breaks auditability
- Real-time alerting infrastructure — dbt Cloud freshness checks sufficient
- Adjust/Amplitude SDK changes — outside dbt scope, flagged as external dependency
- Android device matching fix — requires Amplitude SDK reconfiguration (useAdvertisingIdForDeviceId)

## Context

- **Environment:** dbt Cloud (production), Snowflake warehouse, no local dbt run capability (key-pair auth)
- **Schema routing:** Dev → `DBT_WGTDATA`/`DEV_S3_DATA`, Prod → `PROD`/`S3_DATA`
- **Codebase:** 17,825 LOC (SQL + YAML + CSV). 90 files across staging, intermediate, and mart layers.
- **Test coverage:** 29 tests passing in dbt Cloud (25 generic + 4 singular)
- **Source monitoring:** 16 sources monitored (13 Adjust S3, 1 Adjust API, 2 Amplitude) + 1 staleness test
- **Android mapping:** Amplitude DEVICE_ID is random SDK UUID, NOT GPS_ADID. 0% match structural. Requires SDK change.
- **iOS mapping:** IDFV = Amplitude device_id. 69.78% match rate. UPPER() normalization correct.
- **MTA status:** Formally closed for strategic use. Preserved for iOS-only tactical analysis with limitation headers.
- **MMM pipeline:** 3 intermediate + 2 mart models validated in dbt Cloud. All tests pass. SKAN installs integrated.

## Constraints

- **Platform:** Snowflake SQL + dbt (Jinja)
- **Execution:** dbt Cloud only — no local dbt runs
- **Data sources:** Read-only access to Adjust S3, Amplitude share, Supermetrics, WGT revenue tables
- **SDK changes:** Outside dbt scope — flag as external dependency

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Flip `generate_schema_name` to check `dev` | dbt Cloud production target name isn't literally 'prod' | ✓ Good — fixed stale S3 activity tables |
| Network-level MTA mart (drop CAMPAIGN_NAME) | Campaign names don't match between spend and MTA sources | ✓ Good — MTA installs populate at network level |
| FULL OUTER JOIN for spend + attribution + MTA | See all data even when sources don't overlap | ⚠️ Revisit — creates orphan rows |
| Pivot from MTA to MMM for budget allocation | Android 0% match, iOS IDFA 0% (uses IDFV instead) — MTA cannot serve strategic use | ✓ Good — MMM pipeline fully independent of device matching |
| Use Adjust API revenue (not user cohort) for MMM | Avoid dependency on broken device mapping pipeline | ✓ Good — MMM pipeline works without device matching |
| SKAN installs additive via UNION ALL | S3 and SKAN are non-overlapping populations | ✓ Good — iOS installs now complete (+15-20%) |
| Hardcode date spine to 2024-01-01 | Avoid CROSS JOIN of three intermediate models for min date | ✓ Good — simple, staging filters already exclude pre-2024 |
| COALESCE all MMM metrics to 0 with HAS_*_DATA flags | Gap-free time series critical for MMM regression | ✓ Good — distinguishes zero-fill from real data |
| 60-day lookback for all test filters | Balance data quality coverage with test execution performance | ✓ Good — avoids historical false positive flood |
| AD_PARTNER macro extraction | Eliminate duplication between installs and touchpoints models | ✓ Good — single source of truth, 18 CASE branches |
| Metadata-based freshness for Amplitude | No timestamp columns in data share | ✓ Good — falls back to INFORMATION_SCHEMA.TABLES.LAST_ALTERED |

---
*Last updated: 2026-02-12 after v1.0 milestone*
