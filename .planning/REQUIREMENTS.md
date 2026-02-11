# Requirements: WGT dbt Analytics

**Defined:** 2026-02-10
**Core Value:** Accurately attribute user acquisition spend to downstream revenue by connecting ad touchpoints to in-app behavior across Adjust and Amplitude.

## v1.0 Requirements

Requirements for milestone v1.0 Data Integrity. Each maps to roadmap phases.

### Device Mapping (DMAP)

- [ ] **DMAP-01**: Audit reveals actual Amplitude DEVICE_ID format for Android and iOS with documented examples
- [ ] **DMAP-02**: Audit establishes baseline match rates by platform (Android GPS_ADID, iOS IDFA, iOS IP-based) before any code changes
- [ ] **DMAP-03**: Android device mapping normalization is fixed so GPS_ADID matches Amplitude device_id (or alternative path documented if impossible)
- [ ] **DMAP-04**: iOS match rate limitations (ATT structural, ~1.4% IDFA) are documented with stakeholder-facing explanation
- [ ] **DMAP-05**: Full-refresh of staging + downstream models preserves D30 cohort windows using full_history_mode variable
- [ ] **DMAP-06**: Android match rate improves measurably from current baseline after normalization fix

### Data Quality Testing (TEST)

- [ ] **TEST-01**: All staging model primary keys have unique and not_null generic tests
- [ ] **TEST-02**: All intermediate model composite keys have unique and not_null generic tests
- [ ] **TEST-03**: Device mapping foreign keys have referential integrity tests (Adjust device_id exists in Amplitude mapping)
- [ ] **TEST-04**: Platform columns have accepted_values tests (iOS, Android only)
- [ ] **TEST-05**: Tests use forward-looking filter (new data only) to avoid historical false positive flood
- [ ] **TEST-06**: Singular test validates touchpoint credit sums to 1.0 per install per model
- [ ] **TEST-07**: Singular test validates user journey lookback window coverage (no gaps in recent installs)
- [ ] **TEST-08**: Cross-layer consistency test validates device counts match staging to intermediate to marts

### Source Freshness (FRESH)

- [ ] **FRESH-01**: Source freshness configured for Adjust sources with appropriate loaded_at_field or proxy timestamp
- [ ] **FRESH-02**: Source freshness configured for Amplitude sources with appropriate loaded_at_field or proxy timestamp
- [ ] **FRESH-03**: Stale static table detection alerts when ADJUST_AMPLITUDE_DEVICE_MAPPING hasn't been refreshed in >30 days
- [ ] **FRESH-04**: Source freshness runs as scheduled job (separate from model builds)

### Code Quality (CODE)

- [ ] **CODE-01**: AD_PARTNER CASE statement extracted from v_stg_adjust__installs and v_stg_adjust__touchpoints into reusable macro
- [ ] **CODE-02**: Consistency test verifies macro produces identical AD_PARTNER values as original CASE statement
- [ ] **CODE-03**: Device ID normalization (UPPER, strip 'R' suffix) centralized at staging layer
- [ ] **CODE-04**: Both staging models produce identical AD_PARTNER for every NETWORK_NAME after refactor

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Advanced Testing

- **ADV-01**: dbt-expectations package installed with advanced validation tests (regex, distributions)
- **ADV-02**: Elementary anomaly detection on mart models (volume, distribution, freshness anomalies)
- **ADV-03**: Unit tests for macros (dbt v1.8+ unit testing framework)
- **ADV-04**: Data quality dashboard in BI tool for test result trends

### Pipeline Reliability

- **REL-01**: CI/CD pipeline gates PRs on test passage
- **REL-02**: Automated backfill detection for incremental model gaps
- **REL-03**: Hardcoded date filters replaced with dbt vars across all staging models

## Out of Scope

| Feature | Reason |
|---------|--------|
| Fuzzy/ML device ID matching | Non-deterministic mappings break attribution auditability; use deterministic matching only |
| Real-time freshness monitoring | Hourly/daily SLA checks sufficient for analytics; adds complexity for marginal benefit |
| New mart models or dashboards | Focus is data integrity, not new reporting surfaces |
| Adjust/Amplitude SDK changes | Outside dbt scope; flag as external dependency if needed |
| Testing every column for uniqueness | Creates test bloat; only test natural/surrogate keys |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| DMAP-01 | Phase 2 | Pending |
| DMAP-02 | Phase 2 | Pending |
| DMAP-03 | Phase 3 | Pending |
| DMAP-04 | Phase 2 | Pending |
| DMAP-05 | Phase 3 | Pending |
| DMAP-06 | Phase 3 | Pending |
| TEST-01 | Phase 1 | Pending |
| TEST-02 | Phase 1 | Pending |
| TEST-03 | Phase 1 | Pending |
| TEST-04 | Phase 1 | Pending |
| TEST-05 | Phase 1 | Pending |
| TEST-06 | Phase 5 | Pending |
| TEST-07 | Phase 5 | Pending |
| TEST-08 | Phase 5 | Pending |
| FRESH-01 | Phase 6 | Pending |
| FRESH-02 | Phase 6 | Pending |
| FRESH-03 | Phase 6 | Pending |
| FRESH-04 | Phase 6 | Pending |
| CODE-01 | Phase 4 | Pending |
| CODE-02 | Phase 4 | Pending |
| CODE-03 | Phase 3 | Pending |
| CODE-04 | Phase 4 | Pending |

**Coverage:**
- v1.0 requirements: 22 total
- Mapped to phases: 22
- Unmapped: 0

---
*Requirements defined: 2026-02-10*
*Last updated: 2026-02-10 after roadmap creation*
