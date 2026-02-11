---
phase: 03-mta-limitations-mmm-foundation
plan: 01
subsystem: documentation
tags: [mta, limitations, stakeholder, mmm, pivot, android, ios, att, device-matching]

# Dependency graph
requires:
  - phase: 02-device-id-audit
    plan: 02
    provides: Device ID audit findings with Android 0% match rate, iOS 7.37% IDFA, and normalization impossibility
provides:
  - Stakeholder-facing MTA limitations document with real production data
  - Limitation headers on 5 MTA model files documenting structural constraints
  - Formal documentation that MTA cannot serve strategic budget allocation
  - Clear recommendation to pivot to MMM (Marketing Mix Modeling)
affects: [stakeholder-communication, budget-allocation-strategy, mmm-foundation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Stakeholder-facing limitation documents using plain language CAN/CANNOT format"
    - "SQL model limitation headers pointing to external documentation"
    - "Preserving non-functional models with documented constraints rather than deletion"

key-files:
  created:
    - .planning/phases/03-device-id-normalization-fix/mta-limitations.md
  modified:
    - models/marts/attribution/mta__campaign_performance.sql
    - models/marts/attribution/mta__network_comparison.sql
    - models/intermediate/int_mta__user_journey.sql
    - models/intermediate/int_mta__touchpoint_credit.sql
    - models/intermediate/int_adjust_amplitude__device_mapping.sql

key-decisions:
  - "MTA development work formally closed — cannot serve strategic budget allocation"
  - "Existing MTA models preserved (not deleted) for iOS-only tactical analysis"
  - "MMM (Marketing Mix Modeling) is the recommended strategic alternative"
  - "Android MTA fix requires external dependency (Amplitude SDK reconfiguration)"
  - "iOS ATT consent rate (7.37%) cannot be improved through data engineering"

patterns-established:
  - "Pattern: Document structural limitations with real production data, not just theory"
  - "Pattern: Preserve limited-functionality models with clear limitation notices"
  - "Pattern: Recommend strategic alternatives when technical fixes are infeasible"

# Metrics
duration: 3min
completed: 2026-02-11
---

# Phase 3 Plan 1: Document MTA Limitations and MMM Pivot Summary

**Stakeholder-facing MTA limitations document created with real Phase 2 audit data, limitation headers added to 5 MTA models, formal pivot to MMM recommended**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-11
- **Completed:** 2026-02-11
- **Tasks:** 2 (both auto)
- **Files created:** 1 stakeholder document
- **Files modified:** 5 MTA model SQL files

## Accomplishments

- Created comprehensive stakeholder-facing MTA limitations document (11KB, non-technical language)
- Documented Android 0% match rate with explanation of Amplitude SDK random UUID behavior
- Documented iOS IDFA 7.37% availability with ATT framework context and industry comparison
- Explained SAN (Meta, Google, Apple, TikTok) touchpoint coverage gap and budget allocation impact
- Added limitation headers to all 5 MTA-related model files pointing users to MMM alternatives
- Preserved existing MTA models for iOS-only tactical analysis use cases
- Formally recommended MMM (Marketing Mix Modeling) as strategic budget allocation approach

## Key Content

### Stakeholder Document Structure

The `mta-limitations.md` document targets non-technical stakeholders (marketing leadership, product, finance) and covers:

1. **Executive Summary:** 4-sentence overview of MTA structural limitations and MMM recommendation
2. **Android 0% Match Rate:** Explains Amplitude SDK random UUID vs GPS_ADID with real production data (76,159 devices, 0 matches)
3. **iOS Limited Coverage:** Documents 7.37% IDFA consent (below gaming industry 12-19% average) and 69.78% IDFV working match rate
4. **SAN Coverage Gap:** Explains why Meta, Google, Apple, TikTok (70-80% of typical budgets) have 0% MTA touchpoint data
5. **Budget Decision Implications:** Clear "CAN measure / CANNOT measure" sections for stakeholder clarity
6. **MMM Recommendation:** Explains why aggregate-level MMM is privacy-compliant and measures all channels including SANs
7. **What Stays Available:** Documents that MTA models are preserved for iOS tactical analysis, not deleted
8. **Required External Actions:** Documents Amplitude SDK fix requirement without timeline pressure

### Model Limitation Headers

All 5 MTA model files now have standardized limitation headers including:
- Phase 2 audit findings summary (Android 0%, iOS 7.37%, SAN 0%)
- Preservation notice (models kept for iOS tactical analysis)
- MMM recommendation (use marts/mmm/ for strategic budget allocation)
- Fix documentation pointer (link to mta-limitations.md)
- Production build status for device_mapping model (never built)

## Task Commits

1. **0c2c519** - docs(03-01): create stakeholder-facing MTA limitations document
   - Created `.planning/phases/03-device-id-normalization-fix/mta-limitations.md`
   - 237 lines, 11KB
   - Non-technical language targeting marketing leadership

2. **acf073c** - docs(03-01): add limitation headers to 5 MTA model files
   - Modified 5 SQL model files with prepended limitation comment blocks
   - No SQL logic changes (comment additions only)
   - Headers point to mta-limitations.md for full context

## Decisions Made

1. **MTA cannot serve strategic budget allocation:** Phase 2 proved device-level matching is structurally limited (Android 0%, iOS ~7%) and SAN touchpoint coverage is 0%. MTA development work is formally closed.

2. **Preserve MTA models with limitation headers:** Rather than deleting non-functional models, preserve them with clear limitation notices for the limited use case where they do work (iOS-only tactical analysis for ~7% IDFA-consented users).

3. **Recommend MMM as strategic alternative:** Marketing Mix Modeling uses aggregate data (no device matching needed), is privacy-compliant, measures all channels including SANs, and is the industry-standard post-ATT approach.

4. **Document external dependencies without pressure:** Amplitude SDK fix (useAdvertisingIdForDeviceId) documented as the path to eventual Android MTA, but no timeline or urgency applied since MMM pivot eliminates business need.

5. **Use plain language for stakeholder communication:** Technical limitations (SDK UUIDs, ATT framework, IDFA vs IDFV) translated into business impact language ("CAN measure X%, CANNOT measure Y%").

## Deviations from Plan

None - plan executed exactly as written.

## Next Phase Readiness

**Phase 3 Plan 1 success criteria status:**
- [x] MTA limitations formally documented with real data from Phase 2 audit
- [x] Existing MTA models preserved with clear limitation notices
- [x] Stakeholders can understand why MTA cannot work without reading code
- [x] Path forward (MMM) is clearly stated

**Phase 3 remaining work:**
- Plan 02: Create MMM data foundation models (aggregate daily spend, installs, revenue by channel)
- Additional plans: Define MMM schema, implement cohort revenue models, prepare for external MMM tools

**Blockers/Concerns:**
None. Documentation complete. MTA work formally closed. MMM development can proceed.

## Self-Check: PASSED

**Created files exist:**
- ✓ .planning/phases/03-device-id-normalization-fix/mta-limitations.md (11KB)

**Modified files verified:**
- ✓ models/marts/attribution/mta__campaign_performance.sql (limitation header present)
- ✓ models/marts/attribution/mta__network_comparison.sql (limitation header present)
- ✓ models/intermediate/int_mta__user_journey.sql (limitation header present)
- ✓ models/intermediate/int_mta__touchpoint_credit.sql (limitation header present)
- ✓ models/intermediate/int_adjust_amplitude__device_mapping.sql (limitation header + status present)

**Commits exist:**
- ✓ 0c2c519 (stakeholder doc)
- ✓ acf073c (model headers)

---
*Phase: 03-mta-limitations-mmm-foundation*
*Completed: 2026-02-11*
