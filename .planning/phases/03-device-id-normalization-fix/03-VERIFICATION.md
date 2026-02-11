---
phase: 03-mta-limitations-mmm-foundation
verified: 2026-02-11T22:30:00Z
status: passed
score: 5/5 must-haves verified
---

# Phase 3: Document MTA Limitations + MMM Data Foundation Verification Report

**Phase Goal:** Document why MTA is not viable for strategic budget allocation, formally close MTA development, and build aggregate dbt models for MMM input data

**Verified:** 2026-02-11T22:30:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | MTA limitations formally documented with stakeholder-facing explanation of why device-level attribution cannot work for Android (0% match) and has limited iOS coverage (~7% IDFA) | ✓ VERIFIED | mta-limitations.md exists (237 lines), contains "0% match rate" (3 instances), "7.37%" IDFA data (2 instances), executive summary targets non-technical stakeholders |
| 2 | Aggregate MMM input models exist: daily channel spend, daily channel installs, daily channel revenue | ✓ VERIFIED | 3 intermediate models exist: int_mmm__daily_channel_spend.sql (53 lines), int_mmm__daily_channel_installs.sql (30 lines), int_mmm__daily_channel_revenue.sql (64 lines) — all substantive SQL |
| 3 | MMM daily summary mart joins spend + installs + revenue at channel+platform+date grain | ✓ VERIFIED | mmm__daily_channel_summary.sql (112 lines) with date_spine, CROSS JOIN channels, 3 LEFT JOINs to intermediate models, COALESCE for zero-fill |
| 4 | Existing MTA models preserved as-is (not deleted) with documentation of limitations | ✓ VERIFIED | 5 MTA models exist with LIMITATION NOTICE headers: 2 marts + 2 int_mta + 1 device_mapping. mta-limitations.md section "We Are NOT Deleting MTA Models" |
| 5 | Date spine ensures complete time series for MMM (no gaps) | ✓ VERIFIED | dbt_utils.date_spine with start_date='2024-01-01' and end_date=current_date(), CROSS JOIN with channels creates complete grid, COALESCE to 0 fills gaps (15 instances) |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/03-device-id-normalization-fix/mta-limitations.md` | Stakeholder-facing MTA limitations document | ✓ VERIFIED | EXISTS (237 lines), SUBSTANTIVE (8 sections: exec summary, Android 0%, iOS 7.37%, SANs, budget implications, MMM recommendation, preservation notice, external actions), NO STUBS |
| `models/marts/attribution/mta__campaign_performance.sql` | MTA mart with limitation header | ✓ VERIFIED | EXISTS, LIMITATION NOTICE lines 1-14, points to mta-limitations.md, no SQL logic changed |
| `models/marts/attribution/mta__network_comparison.sql` | MTA mart with limitation header | ✓ VERIFIED | EXISTS, LIMITATION NOTICE lines 1-14, points to mta-limitations.md, no SQL logic changed |
| `models/intermediate/int_mta__user_journey.sql` | MTA intermediate with limitation header | ✓ VERIFIED | EXISTS, LIMITATION NOTICE lines 1-14, points to mmm/ alternatives |
| `models/intermediate/int_mta__touchpoint_credit.sql` | MTA intermediate with limitation header | ✓ VERIFIED | EXISTS, LIMITATION NOTICE lines 1-14, points to mmm/ alternatives |
| `models/intermediate/int_adjust_amplitude__device_mapping.sql` | Device mapping with limitation + status header | ✓ VERIFIED | EXISTS, LIMITATION NOTICE lines 1-14 + additional STATUS line documenting never built to production |
| `models/intermediate/int_mmm__daily_channel_spend.sql` | Daily spend by channel | ✓ VERIFIED | EXISTS (53 lines), SUBSTANTIVE (8 SQL keywords: SELECT, FROM, LEFT JOIN, WHERE, GROUP BY), ref('stg_supermetrics__adj_campaign'), ref('network_mapping'), incremental config |
| `models/intermediate/int_mmm__daily_channel_installs.sql` | Daily installs by channel | ✓ VERIFIED | EXISTS (30 lines), SUBSTANTIVE (5 SQL keywords), ref('v_stg_adjust__installs'), COUNT(DISTINCT DEVICE_ID) |
| `models/intermediate/int_mmm__daily_channel_revenue.sql` | Daily revenue by channel | ✓ VERIFIED | EXISTS (64 lines), SUBSTANTIVE (8 SQL keywords), ref('stg_adjust__report_daily'), CRITICAL: does NOT reference int_user_cohort__metrics or int_adjust_amplitude__device_mapping (only in comments explaining why avoided) |
| `models/intermediate/_int_mmm__models.yml` | Schema for MMM intermediate models | ✓ VERIFIED | EXISTS (102 lines), documents 3 models, 3 dbt_utils.unique_combination_of_columns tests, not_null tests, accepted_values tests for PLATFORM |
| `models/marts/mmm/mmm__daily_channel_summary.sql` | Daily summary with date spine | ✓ VERIFIED | EXISTS (112 lines), SUBSTANTIVE (20 SQL keywords), dbt_utils.date_spine, CROSS JOIN channels, 3 LEFT JOINs, 15 COALESCE instances for zero-fill, CPI/ROAS/ALL_ROAS calculations, HAS_*_DATA flags |
| `models/marts/mmm/mmm__weekly_channel_summary.sql` | Weekly rollup | ✓ VERIFIED | EXISTS (55 lines), SUBSTANTIVE (3 SQL keywords + DATE_TRUNC), ref('mmm__daily_channel_summary'), recomputes KPIs from weekly totals |
| `models/marts/mmm/_mmm__models.yml` | Schema for MMM mart models | ✓ VERIFIED | EXISTS (88 lines), documents 2 models, 2 dbt_utils.unique_combination_of_columns tests, not_null/accepted_values tests |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| mta-limitations.md | Phase 2 findings | References audit data | ✓ WIRED | Document contains "0% match rate" and "7.37%" matching Phase 2 findings, references production data scale (84,145 Android, 81,463 iOS installs) |
| int_mmm__daily_channel_spend.sql | stg_supermetrics__adj_campaign | ref() | ✓ WIRED | Line 30: ref('stg_supermetrics__adj_campaign'), staging model exists, JOIN used, SUM(s.COST) aggregation |
| int_mmm__daily_channel_spend.sql | network_mapping | ref() LEFT JOIN | ✓ WIRED | Line 35: ref('network_mapping'), seed exists, LEFT JOIN ON s.PARTNER_NAME = nm.SUPERMETRICS_PARTNER_NAME |
| int_mmm__daily_channel_installs.sql | v_stg_adjust__installs | ref() | ✓ WIRED | Line 25: ref('v_stg_adjust__installs'), staging view exists, COUNT(DISTINCT DEVICE_ID) aggregation |
| int_mmm__daily_channel_revenue.sql | stg_adjust__report_daily | ref() | ✓ WIRED | Line 42: ref('stg_adjust__report_daily'), staging model exists, SUM(r.REVENUE) aggregation |
| int_mmm__daily_channel_revenue.sql | network_mapping | ref() LEFT JOIN | ✓ WIRED | Line 47: ref('network_mapping'), LEFT JOIN ON r.PARTNER_NAME = nm.ADJUST_NETWORK_NAME |
| int_mmm__daily_channel_revenue.sql | AVOIDS device mapping | Design decision | ✓ VERIFIED | Comment lines 17-30 explain why NOT using int_user_cohort__metrics or int_adjust_amplitude__device_mapping (broken for Android), grep confirms NO ref() to these models |
| mmm__daily_channel_summary.sql | int_mmm__daily_channel_spend | ref() LEFT JOIN | ✓ WIRED | Lines 29, 49: ref('int_mmm__daily_channel_spend'), LEFT JOIN line 105-106, COALESCE(s.SPEND, 0) |
| mmm__daily_channel_summary.sql | int_mmm__daily_channel_installs | ref() LEFT JOIN | ✓ WIRED | Lines 31, 54: ref('int_mmm__daily_channel_installs'), LEFT JOIN line 107-108, COALESCE(i.INSTALLS, 0) |
| mmm__daily_channel_summary.sql | int_mmm__daily_channel_revenue | ref() LEFT JOIN | ✓ WIRED | Lines 33, 59: ref('int_mmm__daily_channel_revenue'), LEFT JOIN line 109-110, COALESCE(r.REVENUE, 0) |
| mmm__daily_channel_summary.sql | date_spine macro | dbt_utils | ✓ WIRED | Line 15: dbt_utils.date_spine with start_date='2024-01-01', end_date=current_date(), CROSS JOIN channels line 43 |
| mmm__weekly_channel_summary.sql | mmm__daily_channel_summary | ref() with DATE_TRUNC | ✓ WIRED | Line 53: ref('mmm__daily_channel_summary'), DATE_TRUNC('week', DATE) line 12, SUM aggregations, recomputed KPIs |

### Requirements Coverage

No requirements explicitly mapped to Phase 03 in REQUIREMENTS.md. Phase goal achievement verified via truths and artifacts.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | - | - | - | No TODO, FIXME, placeholder, or stub patterns found in any MMM models |

**Anti-pattern scan results:**
- 0 TODO/FIXME comments in MMM models
- 0 placeholder content patterns
- 0 empty return patterns
- 0 console.log-only implementations
- All 8 MMM files (3 intermediate SQL + 1 intermediate YAML + 2 mart SQL + 1 mart YAML + 1 doc) are substantive

### Human Verification Required

None. All verification criteria are programmatically verifiable:
- File existence and line counts verified
- ref() chains verified by checking file existence
- SQL patterns (date_spine, CROSS JOIN, LEFT JOIN, COALESCE) verified by grep
- Data content (0% match, 7.37% IDFA) verified in documentation
- Limitation headers verified by grep

### Pipeline Dependency Chain Verification

```
Staging Layer:
  stg_supermetrics__adj_campaign.sql (exists ✓)
  stg_adjust__report_daily.sql (exists ✓)
  v_stg_adjust__installs.sql (exists ✓)
  network_mapping.csv seed (exists ✓)
       ↓
Intermediate Layer:
  int_mmm__daily_channel_spend.sql (exists ✓, refs valid ✓)
  int_mmm__daily_channel_installs.sql (exists ✓, refs valid ✓)
  int_mmm__daily_channel_revenue.sql (exists ✓, refs valid ✓)
       ↓
Mart Layer:
  mmm__daily_channel_summary.sql (exists ✓, refs valid ✓)
       ↓
  mmm__weekly_channel_summary.sql (exists ✓, refs valid ✓)
```

**No circular dependencies.** All ref() calls resolve to existing files.

---

## Overall Assessment

**Phase 3 goal ACHIEVED.**

### Success Criteria Checklist

- [x] MTA limitations formally documented with stakeholder-facing explanation of why device-level attribution cannot work for Android (0% match) and has limited iOS coverage (~7% IDFA)
- [x] Aggregate MMM input models exist: daily channel spend, daily channel installs, daily channel revenue
- [x] MMM daily summary mart joins spend + installs + revenue at channel+platform+date grain
- [x] Existing MTA models preserved as-is (not deleted) with documentation of limitations
- [x] Date spine ensures complete time series for MMM (no gaps)

### Key Achievements

1. **Stakeholder Communication:** 237-line non-technical document explains MTA structural limitations with real production data, providing clear business context for the strategic pivot to MMM.

2. **Technical Preservation:** All 5 MTA models preserved with standardized limitation headers pointing users to MMM alternatives and the full documentation.

3. **MMM Foundation Complete:** Full pipeline from staging to marts with 3 intermediate models (spend, installs, revenue) aggregating at consistent DATE+PLATFORM+CHANNEL grain.

4. **Critical Design Decision:** Revenue model deliberately uses Adjust API pre-aggregated data (stg_adjust__report_daily) instead of the broken user-level cohort pipeline (int_user_cohort__metrics → int_adjust_amplitude__device_mapping), making the MMM pipeline fully independent of device matching issues.

5. **Time Series Integrity:** Date spine (2024-01-01 to current_date) cross-joined with channels creates complete grid, COALESCE to 0 ensures gap-free time series (critical for MMM regression models).

6. **Data Quality:** 5 dbt_utils.unique_combination_of_columns tests on composite keys, not_null tests, accepted_values tests, HAS_*_DATA flags for transparency on zero-filled vs actual data.

### No Gaps Found

All must-haves from 3 plans verified:
- Plan 03-01: Documentation (mta-limitations.md + 5 model headers) ✓
- Plan 03-02: MMM intermediate models (spend, installs, revenue + schema YAML) ✓
- Plan 03-03: MMM mart models (daily + weekly summaries + schema YAML) ✓

### Next Phase Readiness

Phase 3 complete. MMM data foundation ready for:
- External MMM modeling tools (PyMC, Robyn, Meridian)
- Data exports (mmm__daily_channel_summary or mmm__weekly_channel_summary)
- Statistical modeling for budget allocation optimization

MTA development work formally closed with clear stakeholder communication.

---

_Verified: 2026-02-11T22:30:00Z_
_Verifier: Claude (gsd-verifier)_
