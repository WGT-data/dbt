# Roadmap: WGT dbt Analytics v1.0

## Overview

This roadmap addresses critical data quality issues in the WGT dbt analytics pipeline. The journey starts with establishing baseline test coverage (defensive), then auditing device ID mappings to understand current state, documenting MTA limitations and pivoting to MMM aggregate models. The remaining phases focus on code quality (DRY refactor), MMM pipeline hardening with comprehensive testing, and production observability through source freshness monitoring.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Test Foundation** - Establish baseline data quality tests before making code changes
- [x] **Phase 2: Device ID Audit** - Investigate actual device ID formats and document iOS limitations
- [x] **Phase 3: Document MTA Limitations + MMM Data Foundation** - Document MTA structural limitations and build aggregate MMM input models
- [x] **Phase 4: DRY Refactor** - Extract duplicated AD_PARTNER logic into reusable macro
- [ ] **Phase 5: MMM Pipeline Hardening + Expand Test Coverage** - Validate MMM models in dbt Cloud and add comprehensive test suite
- [ ] **Phase 6: Source Freshness & Observability** - Add production monitoring and freshness checks

## Phase Details

### Phase 1: Test Foundation
**Goal**: Establish baseline data quality tests before making any code changes to catch regressions from upcoming device ID normalization
**Depends on**: Nothing (first phase)
**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04, TEST-05
**Success Criteria** (what must be TRUE):
  1. All staging model primary keys have unique and not_null tests passing on new data
  2. All intermediate model composite keys have unique and not_null tests passing on new data
  3. Device mapping foreign keys validate that Adjust device_id exists in Amplitude mapping
  4. Platform columns only accept iOS and Android values (no NULL, no typos)
  5. Tests run in CI/CD and use forward-looking filters to avoid historical false positive flood
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md — Install dbt-utils and add staging model tests (PKs, platform, where filters)
- [x] 01-02-PLAN.md — Add intermediate model tests (composite keys, FK relationships, platform)

### Phase 2: Device ID Audit & Documentation
**Goal**: Investigate actual device ID formats in source systems and document iOS structural limitations before writing normalization logic
**Depends on**: Phase 1
**Requirements**: DMAP-01, DMAP-02, DMAP-04
**Success Criteria** (what must be TRUE):
  1. Documentation exists showing actual Amplitude DEVICE_ID format for Android and iOS with real examples from production
  2. Baseline match rate metrics exist for Android GPS_ADID, iOS IDFA, and iOS IP-based mapping before any code changes
  3. iOS ATT limitations are documented with stakeholder-facing explanation of why 1.4% IDFA match rate is structural, not a bug
  4. Device ID normalization strategy document exists with concrete examples of transformations needed
**Plans**: 2 plans

Plans:
- [x] 02-01-PLAN.md — Write SQL audit queries for device ID format profiling and baseline match rates
- [x] 02-02-PLAN.md — Run audit queries, document findings, write iOS ATT stakeholder doc and normalization strategy

### Phase 3: Document MTA Limitations + MMM Data Foundation
**Goal**: Document why MTA is not viable for strategic budget allocation, formally close MTA development, and build aggregate dbt models for MMM input data
**Depends on**: Phase 2
**Requirements**: DMAP-03 (alternative path documented), CODE-03 (staging normalization already centralized)
**Success Criteria** (what must be TRUE):
  1. MTA limitations formally documented with stakeholder-facing explanation of why device-level attribution cannot work for Android (0% match) and has limited iOS coverage (~7% IDFA)
  2. Aggregate MMM input models exist: daily channel spend, daily channel installs, daily channel revenue
  3. MMM daily summary mart joins spend + installs + revenue at channel+platform+date grain
  4. Existing MTA models preserved as-is (not deleted) with documentation of limitations
  5. Date spine ensures complete time series for MMM (no gaps)
**Plans**: 3 plans

Plans:
- [x] 03-01-PLAN.md — Document MTA limitations and add limitation headers to existing MTA models
- [x] 03-02-PLAN.md — Build MMM intermediate models (daily channel spend, installs, revenue)
- [x] 03-03-PLAN.md — Build MMM mart models (daily summary with date spine, weekly rollup) and compile verification

### Phase 4: DRY Refactor
**Goal**: Extract duplicated AD_PARTNER CASE statement into reusable macro to prevent drift between installs and touchpoints models
**Depends on**: Phase 3
**Requirements**: CODE-01, CODE-02, CODE-04
**Success Criteria** (what must be TRUE):
  1. AD_PARTNER CASE statement logic exists in macros/map_ad_partner.sql, not duplicated across staging models
  2. Consistency test validates macro produces identical AD_PARTNER values for all NETWORK_NAME values as original CASE statement
  3. Both v_stg_adjust__installs and v_stg_adjust__touchpoints produce identical AD_PARTNER for every NETWORK_NAME after refactor
  4. No SQL errors introduced by macro extraction when models rebuild in dbt Cloud
**Plans**: 1 plan

Plans:
- [x] 04-01-PLAN.md — Extract AD_PARTNER macro, update staging models, add singular regression test

### Phase 5: MMM Pipeline Hardening + Expand Test Coverage
**Goal**: Validate MMM models run successfully in dbt Cloud and add comprehensive test suite for MMM data quality
**Depends on**: Phase 4
**Requirements**: MMM-01, MMM-02, MMM-03, MMM-04, TEST-06, TEST-07, TEST-08
**Success Criteria** (what must be TRUE):
  1. All MMM models (3 intermediate, 2 marts) compile and run successfully in dbt Cloud with no SQL errors
  2. Incremental intermediate models handle both initial full load and subsequent incremental runs without data duplication
  3. Network mapping seed covers 100% of active PARTNER_NAME values across source data with no unmapped channels in output
  4. MMM daily summary produces correct KPIs (CPI, ROAS) with no division-by-zero errors or NULL values where metrics exist
  5. Singular test validates date spine completeness (every date+channel+platform combination has a row, no gaps)
  6. Singular test validates cross-layer consistency (intermediate spend+installs+revenue totals match daily summary totals)
  7. Singular test validates zero-fill integrity (HAS_SPEND_DATA, HAS_INSTALL_DATA, HAS_REVENUE_DATA flags correctly distinguish real data from COALESCE zero-fills)
**Plans**: 2 plans

Plans:
- [ ] 05-01-PLAN.md — Create singular tests (date spine, cross-layer, zero-fill) and network mapping coverage analysis query
- [ ] 05-02-PLAN.md — Validate MMM pipeline in dbt Cloud, fix issues, confirm all tests pass

### Phase 6: Source Freshness & Observability
**Goal**: Add production monitoring including source freshness checks for data pipelines and stale static table detection
**Depends on**: Phase 5
**Requirements**: FRESH-01, FRESH-02, FRESH-03, FRESH-04
**Success Criteria** (what must be TRUE):
  1. Source freshness configured for Adjust sources using TO_TIMESTAMP(CREATED_AT) for epoch conversion as loaded_at_field
  2. Source freshness configured for Amplitude sources using appropriate timestamp proxy column as loaded_at_field
  3. Stale static table detection alerts when ADJUST_AMPLITUDE_DEVICE_MAPPING hasn't been refreshed in more than 30 days (using INFORMATION_SCHEMA.TABLES.LAST_ALTERED)
  4. Source freshness runs as scheduled job in dbt Cloud separate from model build jobs
**Plans**: TBD

Plans:
- [ ] TBD (set during planning)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Test Foundation | 2/2 | Complete | 2026-02-11 |
| 2. Device ID Audit | 2/2 | Complete | 2026-02-11 |
| 3. MTA Limitations + MMM Foundation | 3/3 | Complete | 2026-02-11 |
| 4. DRY Refactor | 1/1 | Complete | 2026-02-11 |
| 5. MMM Pipeline Hardening + Expand Test Coverage | 0/2 | In Progress | - |
| 6. Source Freshness & Observability | 0/TBD | Not started | - |

---
*Roadmap created: 2026-02-10 for milestone v1.0 Data Integrity*
*Updated: 2026-02-11 after Phase 5 planning*
