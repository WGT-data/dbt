# Roadmap: WGT dbt Analytics v1.0

## Overview

This roadmap addresses critical data quality issues in the WGT dbt analytics pipeline. The journey starts with establishing baseline test coverage (defensive), then auditing device ID mappings to understand current state, fixing broken Android device ID normalization with full-refresh backfills, extracting duplicated logic into DRY macros, expanding test coverage to business rules, and finally adding production monitoring through source freshness checks. The phases are ordered to manage incremental model dependencies and avoid regression risks.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Test Foundation** - Establish baseline data quality tests before making code changes
- [ ] **Phase 2: Device ID Audit** - Investigate actual device ID formats and document iOS limitations
- [ ] **Phase 3: Device ID Normalization Fix** - Fix Android GPS_ADID mapping with full-refresh backfills
- [ ] **Phase 4: DRY Refactor** - Extract duplicated AD_PARTNER logic into reusable macro
- [ ] **Phase 5: Expand Test Coverage** - Add comprehensive business rule and cross-layer tests
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
- [ ] 01-01-PLAN.md — Install dbt-utils and add staging model tests (PKs, platform, where filters)
- [ ] 01-02-PLAN.md — Add intermediate model tests (composite keys, FK relationships, platform)

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
- [ ] 02-01-PLAN.md — Write SQL audit queries for device ID format profiling and baseline match rates
- [ ] 02-02-PLAN.md — Run audit queries, document findings, write iOS ATT stakeholder doc and normalization strategy

### Phase 3: Device ID Normalization Fix
**Goal**: Fix broken Android GPS_ADID normalization with full-refresh strategy that preserves D30 cohort windows
**Depends on**: Phase 2
**Requirements**: DMAP-03, DMAP-05, DMAP-06, CODE-03
**Success Criteria** (what must be TRUE):
  1. Android device mapping normalization applies correct transformations so GPS_ADID matches Amplitude device_id
  2. Full-refresh of staging and downstream models preserves D30 cohort windows using full_history_mode variable
  3. Android match rate improves measurably from baseline (targeting 80%+ vs current unknown baseline)
  4. Device ID normalization is centralized at staging layer (no duplicate logic in intermediate/marts)
  5. Validation tests confirm row counts and D30 metrics match pre-refresh backup tables
**Plans**: TBD

Plans:
- [ ] TBD (set during planning)

### Phase 4: DRY Refactor (AD_PARTNER Macro)
**Goal**: Extract duplicated AD_PARTNER CASE statement from installs and touchpoints into single reusable macro to prevent drift
**Depends on**: Phase 3
**Requirements**: CODE-01, CODE-02, CODE-04
**Success Criteria** (what must be TRUE):
  1. AD_PARTNER CASE statement logic exists in a reusable macro, not duplicated across models
  2. Consistency test validates that macro produces identical AD_PARTNER values as original CASE statement
  3. Device ID normalization (UPPER, strip 'R' suffix) is centralized at staging layer with no duplication
  4. Both staging models (installs and touchpoints) produce identical AD_PARTNER for every NETWORK_NAME after refactor
**Plans**: TBD

Plans:
- [ ] TBD (set during planning)

### Phase 5: Expand Test Coverage
**Goal**: Add comprehensive test suite including singular tests for complex business rules after critical tests stabilize
**Depends on**: Phase 1, Phase 4
**Requirements**: TEST-06, TEST-07, TEST-08
**Success Criteria** (what must be TRUE):
  1. Singular test validates that touchpoint credit sums to 1.0 per install per attribution model
  2. Singular test validates user journey lookback window coverage with no gaps in recent installs
  3. Cross-layer consistency test validates device counts match from staging to intermediate to marts
  4. Test suite includes business rules validation, not just data shape tests (uniqueness, not_null)
**Plans**: TBD

Plans:
- [ ] TBD (set during planning)

### Phase 6: Source Freshness & Observability
**Goal**: Add production monitoring including source freshness checks and stale static table detection
**Depends on**: Phase 5
**Requirements**: FRESH-01, FRESH-02, FRESH-03, FRESH-04
**Success Criteria** (what must be TRUE):
  1. Source freshness configured for Adjust sources with appropriate loaded_at_field or proxy timestamp
  2. Source freshness configured for Amplitude sources with appropriate loaded_at_field or proxy timestamp
  3. Stale static table detection alerts when ADJUST_AMPLITUDE_DEVICE_MAPPING hasn't been refreshed in more than 30 days
  4. Source freshness runs as scheduled job separate from model builds
**Plans**: TBD

Plans:
- [ ] TBD (set during planning)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Test Foundation | 0/2 | Planning complete | - |
| 2. Device ID Audit | 0/2 | Planning complete | - |
| 3. Device ID Normalization Fix | 0/TBD | Not started | - |
| 4. DRY Refactor | 0/TBD | Not started | - |
| 5. Expand Test Coverage | 0/TBD | Not started | - |
| 6. Source Freshness & Observability | 0/TBD | Not started | - |

---
*Roadmap created: 2026-02-10 for milestone v1.0 Data Integrity*
