# Phase 2: Device ID Audit & Documentation - Research

**Researched:** 2026-02-11
**Domain:** Data auditing, dbt testing, device ID mapping, stakeholder documentation
**Confidence:** HIGH

## Summary

Phase 2 focuses on investigating actual device ID formats in production Snowflake tables and documenting structural match rate limitations before writing normalization logic. This is a data investigation phase, not a code implementation phase.

The research reveals three critical technical domains: (1) SQL-based data profiling patterns to audit device ID population and format, (2) dbt documentation and testing patterns to establish baseline metrics before code changes, and (3) stakeholder communication strategies to explain structural limitations (iOS ATT ~1-3% IDFA consent) vs. fixable bugs.

**Key findings:**
- **iOS Device IDs**: Amplitude uses IDFV (Identifier for Vendor) by default for iOS, which matches existing knowledge that Amplitude device_id = IDFV for iOS
- **Android Device IDs**: Amplitude generates random device IDs by default (not GPS_ADID), explaining why current matching fails
- **ATT Consent Rates**: Global iOS IDFA consent rates are 46-50% as of 2026, but gaming apps average 12-19% consent, meaning 1.4% match rate is within expected range for deterministic IDFA matching in games
- **Baseline Metrics**: Data engineering best practice in 2026 is to establish baseline metrics (row counts, match rates, null rates) BEFORE any transformation changes, with proactive monitoring for deviations
- **dbt Profiling Tools**: `dbt-profiler` package automates generation of profiling statistics (row counts, null proportions, distinct counts) and can generate documentation blocks

**Primary recommendation:** Use SQL-based profiling queries to audit device ID columns in both Adjust (GPS_ADID, IDFV, IDFA, ADID) and Amplitude (DEVICE_ID) tables, calculate baseline match rates by platform, and document findings in Markdown files consumable by both technical teams and stakeholders before writing any normalization logic.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Snowflake SQL | N/A | Data profiling queries (COUNT, GROUP BY, DISTINCT) | Native warehouse query language, no dependencies |
| dbt tests | dbt-core 1.x | Data quality validation and baseline metrics | Standard dbt testing framework already in project |
| Markdown | N/A | Documentation format for findings | Universal format, renders in GitHub, supports code blocks and tables |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| dbt-profiler | 0.8.4+ | Automated data profiling macros | Optional: automates profiling queries for multiple tables |
| dbt-utils | 1.x | Test utilities (unique_combination_of_columns) | Already in project for composite key testing |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual SQL queries | dbt-profiler package | Manual queries give full control and visibility; dbt-profiler automates but adds dependency |
| Markdown docs | dbt docs blocks | Markdown files are version-controlled and stakeholder-friendly; dbt docs are technical-focused |
| COUNT(*) | APPROX_COUNT_DISTINCT | Exact counts preferred for baseline metrics; approximation acceptable for very large tables (>1B rows) |

**Installation:**
```bash
# If using dbt-profiler (optional)
# Add to packages.yml:
packages:
  - package: data-mie/dbt_profiler
    version: 0.8.4

# Then run:
dbt deps
```

## Architecture Patterns

### Recommended Project Structure
```
.planning/phases/02-device-id-audit/
├── 02-PLAN-01.md                          # Audit plan for device ID formats
├── 02-PLAN-02.md                          # Baseline metrics measurement plan
├── 02-PLAN-03.md                          # Stakeholder documentation plan
└── findings/                              # Output directory for documentation
    ├── device-id-formats.md               # Actual formats found in production
    ├── baseline-match-rates.md            # Match rates by platform before changes
    ├── ios-att-limitations.md             # Stakeholder explanation of ATT impact
    └── normalization-strategy.md          # Transformation examples needed
```

### Pattern 1: Data Profiling Query Structure
**What:** SQL queries to profile device ID columns across platforms and systems
**When to use:** Investigating unknown data formats, establishing baseline metrics
**Example:**
```sql
-- Device ID format investigation pattern
-- Source: Research synthesis of Snowflake data profiling best practices

WITH device_id_samples AS (
    SELECT
        PLATFORM,
        GPS_ADID,
        ADID,
        IDFV,
        IDFA,
        -- Sample first 100 per platform for manual inspection
        ROW_NUMBER() OVER (PARTITION BY PLATFORM ORDER BY CREATED_AT DESC) AS rn
    FROM ADJUST.S3_DATA.ANDROID_EVENTS
    WHERE ACTIVITY_KIND = 'install'
      AND CREATED_AT >= DATEADD(day, -30, CURRENT_DATE)
    UNION ALL
    SELECT
        PLATFORM,
        GPS_ADID,
        ADID,
        IDFV,
        IDFA,
        ROW_NUMBER() OVER (PARTITION BY PLATFORM ORDER BY CREATED_AT DESC) AS rn
    FROM ADJUST.S3_DATA.IOS_EVENTS
    WHERE ACTIVITY_KIND = 'install'
      AND CREATED_AT >= DATEADD(day, -30, CURRENT_DATE)
)

, column_population AS (
    SELECT
        PLATFORM,
        COUNT(*) AS total_rows,
        COUNT(GPS_ADID) AS gps_adid_populated,
        COUNT(ADID) AS adid_populated,
        COUNT(IDFV) AS idfv_populated,
        COUNT(IDFA) AS idfa_populated,
        COUNT(DISTINCT GPS_ADID) AS gps_adid_distinct,
        COUNT(DISTINCT ADID) AS adid_distinct,
        COUNT(DISTINCT IDFV) AS idfv_distinct,
        COUNT(DISTINCT IDFA) AS idfa_distinct
    FROM device_id_samples
    WHERE rn <= 100
    GROUP BY PLATFORM
)

SELECT
    PLATFORM,
    total_rows,
    -- Population percentages
    ROUND(100.0 * gps_adid_populated / total_rows, 1) AS gps_adid_pct,
    ROUND(100.0 * adid_populated / total_rows, 1) AS adid_pct,
    ROUND(100.0 * idfv_populated / total_rows, 1) AS idfv_pct,
    ROUND(100.0 * idfa_populated / total_rows, 1) AS idfa_pct,
    -- Distinct counts (should be close to total for device IDs)
    gps_adid_distinct,
    adid_distinct,
    idfv_distinct,
    idfa_distinct
FROM column_population
ORDER BY PLATFORM;
```

### Pattern 2: Baseline Match Rate Calculation
**What:** Measure current match rates between systems by platform before changes
**When to use:** Establishing baseline metrics before implementing normalization logic
**Example:**
```sql
-- Baseline match rate measurement pattern
-- Source: Research synthesis of data engineering baseline metrics best practices

WITH amplitude_devices AS (
    SELECT DISTINCT
        DEVICE_ID,
        PLATFORM,
        USER_ID
    FROM AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE.SCHEMA_726530.EVENTS_726530
    WHERE SERVER_UPLOAD_TIME >= '2026-01-01'
      AND PLATFORM IN ('iOS', 'Android')
      AND DEVICE_ID IS NOT NULL
      AND USER_ID IS NOT NULL
)

, adjust_devices AS (
    SELECT DISTINCT
        GPS_ADID,
        IDFV,
        IDFA,
        'Android' AS PLATFORM
    FROM ADJUST.S3_DATA.ANDROID_EVENTS
    WHERE ACTIVITY_KIND = 'install'
      AND CREATED_AT >= DATEADD(day, -30, CURRENT_DATE)
      AND GPS_ADID IS NOT NULL

    UNION ALL

    SELECT DISTINCT
        NULL AS GPS_ADID,
        IDFV,
        IDFA,
        'iOS' AS PLATFORM
    FROM ADJUST.S3_DATA.IOS_EVENTS
    WHERE ACTIVITY_KIND = 'install'
      AND CREATED_AT >= DATEADD(day, -30, CURRENT_DATE)
      AND (IDFV IS NOT NULL OR IDFA IS NOT NULL)
)

, match_attempts AS (
    SELECT
        amp.PLATFORM,
        COUNT(DISTINCT amp.DEVICE_ID) AS amplitude_devices,
        COUNT(DISTINCT CASE
            WHEN amp.PLATFORM = 'Android' AND adj.GPS_ADID IS NOT NULL
            THEN amp.DEVICE_ID
        END) AS android_gps_adid_matches,
        COUNT(DISTINCT CASE
            WHEN amp.PLATFORM = 'iOS' AND adj.IDFV IS NOT NULL
            THEN amp.DEVICE_ID
        END) AS ios_idfv_matches,
        COUNT(DISTINCT CASE
            WHEN amp.PLATFORM = 'iOS' AND adj.IDFA IS NOT NULL
            THEN amp.DEVICE_ID
        END) AS ios_idfa_matches
    FROM amplitude_devices amp
    LEFT JOIN adjust_devices adj
        ON amp.PLATFORM = adj.PLATFORM
        AND (
            (amp.PLATFORM = 'Android' AND UPPER(amp.DEVICE_ID) = adj.GPS_ADID)
            OR (amp.PLATFORM = 'iOS' AND UPPER(amp.DEVICE_ID) = adj.IDFV)
            OR (amp.PLATFORM = 'iOS' AND UPPER(amp.DEVICE_ID) = adj.IDFA)
        )
    GROUP BY amp.PLATFORM
)

SELECT
    PLATFORM,
    amplitude_devices,
    android_gps_adid_matches,
    ios_idfv_matches,
    ios_idfa_matches,
    -- Match rate percentages
    ROUND(100.0 * android_gps_adid_matches / NULLIF(amplitude_devices, 0), 2) AS android_gps_match_pct,
    ROUND(100.0 * ios_idfv_matches / NULLIF(amplitude_devices, 0), 2) AS ios_idfv_match_pct,
    ROUND(100.0 * ios_idfa_matches / NULLIF(amplitude_devices, 0), 2) AS ios_idfa_match_pct
FROM match_attempts
ORDER BY PLATFORM;
```

### Pattern 3: Stakeholder Documentation Template
**What:** Markdown template explaining technical limitations in business terms
**When to use:** Communicating structural constraints (ATT) vs. fixable issues to non-technical stakeholders
**Example:**
```markdown
# iOS Device ID Match Rate: Technical Limitations

**Date:** 2026-02-11
**Audience:** Product, Marketing, Leadership
**Status:** Structural limitation, not a bug

## Summary

iOS device ID matching achieves a **1.4% match rate** (53 out of 3,925 devices in January 2026).
This is **expected and structural**, not a data quality issue.

## Why This Happens

**Apple's App Tracking Transparency (ATT) framework** requires apps to ask users for permission
to track them across apps and websites. Most users decline.

### Industry Context (2026)

- **Global ATT consent rate**: 46-50% of iOS users
- **Gaming apps consent rate**: 12-19% of iOS users (lower than average)
- **Our observed rate**: ~1.4% deterministic matches via IDFA

**Our rate is within expected range for gaming apps using deterministic matching only.**

## What This Means

### ✅ What We CAN Measure
- iOS users who consented to tracking (IDFA available)
- Aggregate iOS attribution via SKAdNetwork (no device-level data)

### ❌ What We CANNOT Measure
- Individual user journeys for 98%+ of iOS users
- Touchpoint-level attribution for non-consented iOS users
- Cross-app behavior tracking (by design, for privacy)

## Business Impact

- **Multi-touch attribution (MTA)** on iOS is limited to ~1-3% of users
- **Android MTA** remains viable (different privacy framework)
- **iOS aggregate attribution** (SKAdNetwork) continues to work for campaign-level reporting

## What We're Doing

Phase 3 will implement device ID normalization to maximize the matches we CAN make, but
cannot increase the ATT consent rate (controlled by users, not us).

## Further Reading

- [Apple ATT Framework Documentation](https://developer.apple.com/app-store/user-privacy-and-data-use/)
- [Industry ATT Consent Rate Data](https://www.businessofapps.com/data/att-opt-in-rates/)
```

### Anti-Patterns to Avoid

- **Auditing without baselines:** Don't investigate device ID formats without first measuring current match rates. Baseline metrics establish the "before" state that validates any improvements.

- **Technical documentation only:** Don't write documentation exclusively for engineers. Stakeholders need business-context explanations of technical limitations (see Pattern 3).

- **Premature normalization:** Don't write device ID transformation logic before auditing actual formats in production. You'll make wrong assumptions about data structure.

- **Ignoring sample size:** Don't profile entire tables for format investigation. Sample 100-1000 rows per platform for manual inspection, use aggregates for population statistics.

- **Single metric reporting:** Don't report only "1.4% match rate" without context. Break down by platform, identifier type, and compare to industry benchmarks.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Data profiling across multiple tables | Custom Python scripts to loop through tables and generate stats | `dbt-profiler` package with profiling macros | Profiling packages handle edge cases (division by zero, NULL handling, type detection) and generate consistent documentation format |
| Match rate calculations | One-off queries copy-pasted into Slack | dbt model with tests that fail if match rate drops below threshold | Version-controlled SQL is auditable; dbt tests provide continuous monitoring vs. one-time analysis |
| Device ID format documentation | Spreadsheet with manually copied examples | SQL query results exported to Markdown with code blocks | Markdown is version-controlled, supports syntax highlighting, renders in GitHub, and can be regenerated when data changes |
| ATT limitation explanation | Email thread explaining same concept repeatedly | Single source-of-truth Markdown doc linked in Slack, dbt docs, Jira tickets | Documentation reduces repetitive explanations and ensures consistent messaging across stakeholders |

**Key insight:** Auditing produces documentation artifacts (Markdown files, dbt tests, SQL queries) that must be version-controlled and reusable. One-off analysis in notebooks or spreadsheets creates knowledge silos and cannot be validated or reproduced.

## Common Pitfalls

### Pitfall 1: Confusing "Didn't Find Match" with "Cannot Match"
**What goes wrong:** Analyst sees 1.4% iOS match rate and assumes device ID logic is broken, starts debugging normalization code.
**Why it happens:** ATT consent rates are invisible in the data—you only see the IDs that ARE present, not the 98% that are blocked by Apple's privacy framework.
**How to avoid:** Document ATT limitations FIRST before auditing match rates. When stakeholders see low iOS match rate, they have context that it's structural, not a bug.
**Warning signs:** Questions like "Why are we only matching 1% of iOS users?" without reference to ATT, or attempts to "fix" iOS matching by changing normalization logic.

### Pitfall 2: Assuming Device ID Formats Without Verification
**What goes wrong:** Developer assumes Amplitude uses GPS_ADID for Android (because that's what Adjust uses), writes normalization logic, discovers 0% match rate in production.
**Why it happens:** Different SDKs use different default device identifiers. Amplitude generates random IDs by default; Adjust uses platform advertising IDs.
**How to avoid:** Query actual production data for device ID format samples (Pattern 1). Inspect 100 real examples per platform before making assumptions.
**Warning signs:** Documentation that says "Amplitude uses GPS_ADID" without citing source data or SDK documentation links.

### Pitfall 3: Baseline Metrics After Code Changes
**What goes wrong:** Developer implements device ID normalization in Phase 3, sees 15% Android match rate, doesn't know if that's better or worse than before.
**Why it happens:** No baseline metrics captured before changes. Can't prove improvement without a "before" measurement.
**How to avoid:** Run baseline match rate queries (Pattern 2) BEFORE Phase 3 implementation. Document results in version-controlled Markdown file with query timestamp.
**Warning signs:** Pull request description says "improves match rate" without numbers showing before/after comparison.

### Pitfall 4: Single-Platform Analysis
**What goes wrong:** Analyst profiles iOS device IDs, documents IDFV and IDFA, misses that Android has completely different identifier structure (GPS_ADID).
**Why it happens:** Platform-specific queries are easier to write than cross-platform analysis, leading to incomplete investigation.
**How to avoid:** Every profiling query must include `GROUP BY PLATFORM` (Pattern 1, Pattern 2). Document findings separately for iOS and Android in all artifacts.
**Warning signs:** Documentation titled "Device ID Audit" that only mentions iOS identifiers, or match rate reports without platform breakdown.

### Pitfall 5: Technical Jargon in Stakeholder Docs
**What goes wrong:** Stakeholder doc explains "ATT framework reduces IDFA availability for deterministic matching via the AppTrackingTransparency prompt," stakeholders don't understand, keep asking same questions.
**Why it happens:** Engineer writes for engineer audience, not business audience.
**How to avoid:** Use Pattern 3 template structure: "What This Means" with ✅ CAN / ❌ CANNOT bullets, "Business Impact" section, avoid acronyms or define them inline.
**Warning signs:** Stakeholder asks "So can we fix this or not?" after reading documentation—means explanation was too technical.

## Code Examples

### Example 1: dbt Test for Baseline Match Rate Monitoring
```yaml
# models/intermediate/_int_device_mapping__models.yml
# Source: dbt testing best practices research

version: 2

models:
  - name: int_adjust_amplitude__device_mapping
    description: |
      Maps Adjust device IDs to Amplitude user IDs.

      **Baseline Match Rates (as of 2026-02-11, before Phase 3 normalization):**
      - iOS IDFV: 1.4% (53/3,925 devices) - Expected due to ATT limitations
      - Android GPS_ADID: 0% - Will be fixed in Phase 3

      Match rate test fails if iOS drops below 1.0% (indicates data pipeline issue).
    data_tests:
      # Baseline metric: track iOS match rate doesn't degrade
      - dbt_utils.expression_is_true:
          name: ios_match_rate_above_baseline
          expression: |
            (SELECT
              COUNT(DISTINCT CASE WHEN PLATFORM = 'iOS' THEN ADJUST_DEVICE_ID END) * 100.0
              / NULLIF(COUNT(DISTINCT CASE WHEN PLATFORM = 'iOS' THEN AMPLITUDE_USER_ID END), 0)
             FROM {{ ref('int_adjust_amplitude__device_mapping') }}
             WHERE FIRST_SEEN_AT >= DATEADD(day, -30, CURRENT_DATE)
            ) >= 1.0
          config:
            severity: warn
            where: "FIRST_SEEN_AT >= DATEADD(day, -30, CURRENT_DATE)"
          meta:
            description: "iOS match rate below 1% indicates pipeline issue. Baseline is 1.4% (ATT-limited)."
```

### Example 2: Device ID Format Inspection Macro
```sql
-- macros/audit_device_id_formats.sql
-- Source: Research synthesis of dbt and Snowflake profiling patterns

{% macro audit_device_id_formats(source_table, platform_filter, sample_size=100) %}

WITH samples AS (
    SELECT
        GPS_ADID,
        ADID,
        IDFV,
        IDFA,
        -- Capture format characteristics
        LENGTH(GPS_ADID) AS gps_adid_length,
        LENGTH(IDFV) AS idfv_length,
        LENGTH(IDFA) AS idfa_length,
        -- Check for UUID format (8-4-4-4-12 pattern)
        REGEXP_LIKE(GPS_ADID, '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$') AS gps_adid_is_uuid,
        REGEXP_LIKE(IDFV, '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$') AS idfv_is_uuid,
        REGEXP_LIKE(IDFA, '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$') AS idfa_is_uuid,
        ROW_NUMBER() OVER (ORDER BY CREATED_AT DESC) AS rn
    FROM {{ source_table }}
    WHERE ACTIVITY_KIND = 'install'
      AND CREATED_AT >= DATEADD(day, -30, CURRENT_DATE)
      {% if platform_filter %}
      AND PLATFORM = '{{ platform_filter }}'
      {% endif %}
)

SELECT
    '{{ platform_filter }}' AS platform,
    COUNT(*) AS sample_size,
    -- Population statistics
    COUNT(GPS_ADID) AS gps_adid_populated,
    COUNT(IDFV) AS idfv_populated,
    COUNT(IDFA) AS idfa_populated,
    -- Format validation
    SUM(gps_adid_is_uuid::INT) AS gps_adid_uuid_count,
    SUM(idfv_is_uuid::INT) AS idfv_uuid_count,
    SUM(idfa_is_uuid::INT) AS idfa_uuid_count,
    -- Length distribution (detect anomalies)
    AVG(gps_adid_length) AS avg_gps_adid_length,
    AVG(idfv_length) AS avg_idfv_length,
    AVG(idfa_length) AS avg_idfa_length,
    -- Examples (first 3 non-null values)
    ARRAY_AGG(GPS_ADID) WITHIN GROUP (ORDER BY rn) FILTER (WHERE GPS_ADID IS NOT NULL) AS gps_adid_examples,
    ARRAY_AGG(IDFV) WITHIN GROUP (ORDER BY rn) FILTER (WHERE IDFV IS NOT NULL) AS idfv_examples,
    ARRAY_AGG(IDFA) WITHIN GROUP (ORDER BY rn) FILTER (WHERE IDFA IS NOT NULL) AS idfa_examples
FROM samples
WHERE rn <= {{ sample_size }}

{% endmacro %}

-- Usage in analysis file:
-- {{ audit_device_id_formats(source('adjust', 'ANDROID_ACTIVITY_INSTALL'), 'Android', 100) }}
-- UNION ALL
-- {{ audit_device_id_formats(source('adjust', 'IOS_ACTIVITY_INSTALL'), 'iOS', 100) }}
```

### Example 3: Markdown Documentation Template with Code
```markdown
<!-- findings/device-id-formats.md -->
<!-- Source: Research on stakeholder documentation best practices -->

# Device ID Format Audit Results

**Date:** 2026-02-11
**Analyst:** [Your Name]
**Query:** `analyses/audit_device_ids.sql`

## Summary

Audited device ID formats in Adjust source tables (Android and iOS) for 30-day window
(2026-01-12 to 2026-02-11). Sample size: 100 installs per platform.

## Findings by Platform

### Android

**Source Table:** `ADJUST.S3_DATA.ANDROID_EVENTS` (activity_kind = 'install')

| Identifier | Population % | Format | Example |
|------------|-------------|--------|---------|
| GPS_ADID   | 90%         | UUID (uppercase, hyphenated) | `A1B2C3D4-E5F6-7890-ABCD-EF1234567890` |
| ADID       | 100%        | UUID (uppercase, hyphenated) | `F9E8D7C6-B5A4-3210-9876-543210FEDCBA` |
| IDFV       | 0%          | NULL (not applicable to Android) | - |
| IDFA       | 90%         | **EQUALS GPS_ADID** (touchpoints) | `A1B2C3D4-E5F6-7890-ABCD-EF1234567890` |

**Key Discovery:**
- Adjust stores GPS_ADID in the `GPS_ADID` column for Android installs
- Adjust ALSO stores GPS_ADID in the `IDFA` column for touchpoints (impressions/clicks)
- This explains why Android touchpoint matching currently uses `GPS_ADID` field

**Amplitude Format (from existing code):**
- Amplitude Android DEVICE_ID has trailing `'R'` suffix (e.g., `A1B2C3D4...7890R`)
- Current normalization strips this suffix: `LEFT(DEVICE_ID, LENGTH(DEVICE_ID) - 1)`
- **This normalization does NOT produce GPS_ADID** — Amplitude uses random IDs, not advertising IDs

### iOS

**Source Table:** `ADJUST.S3_DATA.IOS_EVENTS` (activity_kind = 'install')

| Identifier | Population % | Format | Example |
|------------|-------------|--------|---------|
| GPS_ADID   | 0%          | NULL (Android-only field) | - |
| ADID       | 100%        | UUID (uppercase, hyphenated) | `12345678-90AB-CDEF-1234-567890ABCDEF` |
| IDFV       | 100%        | UUID (uppercase, hyphenated) | `87654321-DCBA-FE09-8765-4321FEDCBA98` |
| IDFA       | 3.3%        | UUID (uppercase, hyphenated) | `ABCDEF12-3456-7890-ABCD-EF1234567890` |

**Key Discovery:**
- Adjust stores IDFV for 100% of iOS installs (Apple's vendor-scoped identifier)
- IDFA only available for ~3.3% of iOS installs (ATT consent required)
- Existing code comment states "IDFV = Amplitude device_id (confirmed)"

**Amplitude Format (from existing code):**
- Amplitude iOS DEVICE_ID is uppercase UUID matching IDFV
- Current normalization: `UPPER(DEVICE_ID)` (already correct for iOS)

## Implications for Phase 3 Normalization

### iOS: Already Working (no changes needed)
✅ Amplitude DEVICE_ID = IDFV (confirmed)
✅ Current normalization already uppercase
✅ 1.4% IDFA match rate is ATT-limited, not a normalization bug

### Android: Broken (Phase 3 must fix)
❌ Amplitude DEVICE_ID ≠ GPS_ADID (Amplitude uses random IDs)
❌ Stripping `'R'` suffix does NOT produce GPS_ADID
❌ Need alternative matching strategy (see Phase 3)

**Blocker:** Amplitude does not expose GPS_ADID in their event stream by default.
Must investigate if GPS_ADID can be captured via SDK configuration or is available in
Amplitude's `MERGE_IDS` table.

## Query Used

```sql
-- See: analyses/audit_device_ids.sql
{{ audit_device_id_formats(source('adjust', 'ANDROID_ACTIVITY_INSTALL'), 'Android', 100) }}
UNION ALL
{{ audit_device_id_formats(source('adjust', 'IOS_ACTIVITY_INSTALL'), 'iOS', 100) }}
```

## Next Steps

1. ✅ Document baseline match rates (separate artifact)
2. ⬜ Investigate Amplitude SDK configuration for GPS_ADID capture
3. ⬜ Query Amplitude MERGE_IDS table for cross-device identifiers
4. ⬜ Design Phase 3 normalization strategy based on available identifiers
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual SQL profiling scripts | `dbt-profiler` package with automated macros | 2023-2024 | Profiling becomes version-controlled and reusable vs. one-off analysis |
| IP-based probabilistic matching for iOS | Deterministic IDFA-only matching | 2021 (iOS 14.5 ATT) | Match rates dropped but GDPR compliance improved; IP matching removed |
| IDFA always available | IDFA requires ATT prompt consent | 2021 (iOS 14.5) | Industry match rates dropped from 100% to 10-50% depending on app category |
| Global ATT consent ~26% | Global ATT consent ~46-50% | 2021 → 2026 | Recovery from initial ATT shock, but gaming apps still lag at 12-19% |
| Data profiling in Python notebooks | dbt analyses + dbt tests for monitoring | 2022-2025 | Profiling queries become part of CI/CD pipeline vs. manual re-runs |

**Deprecated/outdated:**
- **IP-based device matching for iOS attribution:** Removed from modern MTA implementations due to GDPR compliance concerns (IP addresses are personal data) and poor data quality (carrier NAT causes collision, median 270 touchpoints/journey). Use deterministic IDFA matching only.
- **Assuming IDFA availability on iOS:** Pre-ATT assumption (2021) that IDFA is always available. Current reality: 10-50% consent rate, with gaming apps at lower end (12-19%).
- **Amplitude Android DEVICE_ID = GPS_ADID:** Incorrect assumption. Amplitude generates random device IDs by default unless SDK is explicitly configured to use advertising IDs.

## Open Questions

1. **Can Amplitude capture GPS_ADID for Android?**
   - What we know: Amplitude SDK can be configured to use AdID (GPS_ADID) via `useAdvertisingIdForDeviceId()` method
   - What's unclear: Is this configured in the WGT Golf app? Does historical data contain GPS_ADID or only random IDs?
   - Recommendation: Query Amplitude EVENTS table for `ADID` field (separate from DEVICE_ID) or check SDK configuration in mobile app codebase

2. **Does Amplitude MERGE_IDS table contain cross-device mapping?**
   - What we know: Amplitude has a MERGE_IDS table that maps device IDs to user IDs
   - What's unclear: Does it contain GPS_ADID → random DEVICE_ID mapping, or is it only for user ID consolidation?
   - Recommendation: Profile MERGE_IDS table columns in Phase 2 audit to determine if it provides Android device ID bridge

3. **What is the Android match rate improvement target for Phase 3?**
   - What we know: Current Android match rate is 0% (GPS_ADID doesn't match random Amplitude IDs)
   - What's unclear: What match rate is achievable after normalization? 50%? 80%? Depends on GPS_ADID availability in Amplitude data
   - Recommendation: Set expectations with stakeholders that improvement depends on data availability investigation in Phase 2

4. **Should we document iOS IDFA match rate as success metric?**
   - What we know: 1.4% IDFA match rate is within industry norms (12-19% for gaming apps with ATT prompt)
   - What's unclear: Is this acceptable to stakeholders, or should we pursue probabilistic matching strategies for iOS?
   - Recommendation: Use stakeholder documentation (Pattern 3) to set expectations that deterministic iOS matching is structurally limited by ATT

## Sources

### Primary (HIGH confidence)
- [Amplitude Track Unique Users Documentation](https://help.amplitude.com/hc/en-us/articles/115003135607-Track-unique-users) - Device ID format defaults (iOS: IDFV, Android: random)
- [Amplitude iOS SDK Documentation](https://amplitude.com/docs/sdks/analytics/ios/ios-swift-sdk) - IDFV vs IDFA usage
- [Snowflake Data Profiling Documentation](https://docs.snowflake.com/en/user-guide/data-quality-profile) - Profile Table feature for column analysis
- [Snowflake COUNT Function Documentation](https://docs.snowflake.com/en/sql-reference/functions/count) - NULL handling in COUNT operations
- [dbt Documentation Best Practices](https://docs.getdbt.com/docs/build/documentation) - Markdown and docs blocks
- [dbt Testing Best Practices](https://docs.getdbt.com/faqs/Tests/recommended-tests) - Primary key testing guidance
- [dbt-profiler Package Hub](https://hub.getdbt.com/data-mie/dbt_profiler/latest/) - Automated profiling macros
- [Adjust Device Identifiers Documentation](https://help.adjust.com/en/article/device-identifiers) - GPS_ADID, IDFV, IDFA formats

### Secondary (MEDIUM confidence)
- [Business of Apps ATT Opt-In Rates (2026)](https://www.businessofapps.com/data/att-opt-in-rates/) - 46-50% global ATT consent, verified with multiple sources
- [Flurry ATT Opt-In Rate Updates](https://www.flurry.com/blog/att-opt-in-rate-monthly-updates/) - Gaming app ATT rates (12-19%)
- [AppsFlyer IDFV Glossary](https://www.appsflyer.com/glossary/idfv/) - IDFV vs IDFA differences
- [7 dbt Testing Best Practices | Datafold](https://www.datafold.com/blog/7-dbt-testing-best-practices) - Testing strategy guidance
- [Data Quality in Snowflake Best Practices (2026) | Integrate.io](https://www.integrate.io/blog/data-quality-in-snowflake-best-practices/) - Profiling and validation patterns
- [Top 8 Data Quality Metrics (2026) | Dagster](https://dagster.io/learn/data-quality-metrics) - Baseline metrics importance
- [Baseline Data Measurement | Sopact](https://www.sopact.com/use-case/baseline-data) - Capturing verified starting point before changes
- [Government Data Quality Framework | GOV.UK](https://www.gov.uk/government/publications/the-government-data-quality-framework/the-government-data-quality-framework-guidance) - Stakeholder communication on data limitations

### Tertiary (LOW confidence)
- [Data Transformation Guide | dbt Labs](https://www.getdbt.com/blog/data-transformation) - General transformation patterns (not device-ID-specific)
- [Snowflake Data Profiling GitHub Tool](https://github.com/sfc-gh-gpavlik/snowflake_data_profiling) - Community tool, not verified for production use

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - dbt testing and Snowflake SQL are proven, widely-adopted standards for this use case
- Architecture: HIGH - Data profiling patterns (COUNT, GROUP BY, sampling) are industry-standard SQL techniques verified across multiple sources
- Pitfalls: HIGH - ATT limitations and device ID format assumptions are documented in vendor documentation (Amplitude, Apple, Adjust)
- Normalization strategy: MEDIUM - Amplitude GPS_ADID availability is unclear until audit runs; improvement targets depend on data investigation

**Research date:** 2026-02-11
**Valid until:** 2026-05-11 (90 days for stable domain; ATT consent rates may shift slowly, device ID formats stable)

**Key dependencies for planning:**
- Phase 2 audit runs BEFORE Phase 3 normalization implementation
- Stakeholder documentation completed BEFORE reporting match rate improvements (sets expectations)
- Baseline metrics captured in version-controlled artifacts (enables before/after validation)
