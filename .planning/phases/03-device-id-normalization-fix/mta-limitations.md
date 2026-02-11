# Multi-Touch Attribution (MTA) Limitations: Why We're Pivoting to MMM

**Date:** 2026-02-11
**Audience:** Marketing Leadership, Product, Finance
**Status:** Formal documentation of structural limitations discovered in Phase 2 audit

## Executive Summary

Multi-Touch Attribution (MTA) requires matching individual ad touchpoints (clicks and impressions) to in-app user behavior via device identifiers. Phase 2 audit (February 2026) proved this matching is **structurally broken for Android** with a **0% match rate** and **limited for iOS** to approximately **7% IDFA consent**. Additionally, the largest spend channels (Meta, Google, Apple Search Ads, TikTok) never share touchpoint data, making MTA incapable of measuring 70-80% of typical marketing budgets. We recommend pivoting to **Marketing Mix Modeling (MMM)** for strategic budget allocation, while preserving existing MTA models for iOS-only tactical analysis.

## What We Investigated

Phase 2 ran 17 audit queries against production Snowflake data covering:
- **84,145 Android installs** from the last 60 days (2025-12-13 to 2026-02-11)
- **81,463 iOS installs** from the same period
- **9.97 million ad touchpoints** (clicks and impressions)
- **1.61 million Amplitude unique users** across both platforms
- Full cross-system device ID matching analysis at production scale

These queries were executed on live production data, not samples or estimates.

## Android: Why MTA Cannot Work

**Bottom line: 0% device match rate. This is structural, not a bug.**

### The Problem

Amplitude's Android SDK generates a **random UUID as the device identifier** (DEVICE_ID), not the Google Advertising ID (GPS_ADID) that Adjust uses to track ad touchpoints. These are two completely different identifiers with zero relationship to each other:

| System | Identifier Type | Example |
|--------|----------------|---------|
| Adjust (ad tracking) | GPS_ADID (Google Advertising ID) | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` |
| Amplitude (analytics) | Random SDK UUID | `f9e8d7c6-b5a4-3210-9876-543210abcdef-R` |

**Phase 2 findings:**
- **76,159 Android devices** with GPS_ADID in Adjust (90.51% of installs)
- **695,528 Android devices** in Amplitude
- **0 matches** between Adjust GPS_ADID and Amplitude device_id
- **70% of Android Amplitude device IDs have 'R' suffix** marking them as random SDK identifiers
- **0% match rate** verified at full production scale, not a sampling artifact

### Why This Happens

Amplitude SDK has a configuration option called `useAdvertisingIdForDeviceId()`. When set to `true`, the SDK uses GPS_ADID (the same ID Adjust uses). When set to `false` (the default), the SDK generates a random UUID.

Our Amplitude SDK is configured with the default behavior. This means Amplitude has never captured GPS_ADID for Android devices -- it only captures random UUIDs.

### Can We Fix This?

**Not through data engineering.** The fix requires the mobile engineering team to reconfigure the Amplitude SDK in the app code and release a new app version. This is an external dependency outside the scope of dbt data modeling.

**What's required:**
1. Mobile engineering team updates Amplitude SDK configuration
2. New app version released to Play Store
3. Users update to the new version
4. Historical data remains unmatched (only new installs post-update would match)

**Timeline:** Unknown. No pressure or deadline -- this is documented for future reference.

## iOS: Limited Coverage

**Bottom line: iOS device matching works, but only 7% have IDFA consent for MTA.**

### Two Types of iOS Identifiers

| Identifier | Purpose | Availability | Our Match Rate |
|------------|---------|--------------|----------------|
| IDFV (Identifier for Vendor) | Tracks users within one app | 100% (no consent needed) | **69.78%** |
| IDFA (Identifier for Advertisers) | Tracks users across apps and websites | 7.37% (requires ATT consent) | **7.27% available** |

### What Works

**Install-to-Amplitude matching via IDFV: 69.78%**
- This connects Adjust install records to Amplitude user behavior
- Works for the majority of iOS users
- Does not require user consent

### What Doesn't Work for MTA

**Touchpoint-to-user matching via IDFA: ~7% coverage**

In 2021, Apple introduced **App Tracking Transparency (ATT)** requiring apps to ask permission before tracking users across other apps and websites. Most users tap "Ask App Not to Track."

When users decline, Apple blocks access to IDFA (the advertising identifier used in ad touchpoints). Without IDFA, we cannot link ad clicks/impressions to specific users.

**Industry context:**
| Category | ATT Consent Rate | Source |
|----------|-----------------|--------|
| Global average (all apps) | 46-50% | Business of Apps, 2026 |
| Gaming apps | 12-19% | Flurry Analytics, 2026 |
| **WGT (our rate)** | **7.37%** | Production data, Feb 2026 |

Our rate is at the lower end of gaming industry norms, limiting iOS MTA to approximately **7% of users**.

### Can We Fix This?

**Not through data engineering.** The ATT consent rate is controlled by:
1. Each user's response to Apple's tracking prompt
2. UX/messaging in the consent dialog (product/design decision)
3. Apple's framework rules (outside our control)

Data engineering cannot increase the consent rate. We can only ensure we maximize matches for the identifiers that ARE available (which we already do at 69.78% for IDFV).

## Self-Attributing Networks (SANs)

**Bottom line: The biggest spend channels will always show 0% in MTA.**

### What Are SANs?

Self-Attributing Networks (SANs) are advertising platforms that **never share touchpoint data** with attribution providers like Adjust. They only report aggregate results (spend, clicks, installs, revenue) directly to their own dashboards.

**The four major SANs:**
1. **Meta** (Facebook, Instagram)
2. **Google** (UAC, Google Ads)
3. **Apple Search Ads**
4. **TikTok**

These networks typically represent **70-80% of mobile app marketing budgets** across the industry.

### Impact on MTA

**MTA will always assign 0% credit to SANs** regardless of device matching quality, because:
- No click data shared
- No impression data shared
- No user-level touchpoint timestamps
- Only aggregate campaign performance available via API

This means **MTA cannot measure the majority of marketing spend** even if device matching were perfect.

## What This Means for Budget Decisions

### What MTA CANNOT Do

- **Strategic budget allocation across channels** (Android 0%, iOS ~7%, SANs 0%)
- **Multi-touch credit for Android campaigns** (no device matching)
- **Attribution for Meta, Google, Apple, TikTok spend** (no touchpoint data)
- **Full-funnel iOS attribution** (93% of iOS users blocked by ATT)

### What MTA CAN Do (Limited Use)

- **iOS-only tactical analysis** for the ~7% of users with IDFA consent
- **Non-SAN network comparison** (small programmatic networks that do share touchpoint data)
- **Sequential touchpoint analysis** for consented users (user journey mapping)

### Recommended Alternative: Marketing Mix Modeling (MMM)

**MMM uses aggregate data, not device-level matching.**

| MTA (Limited) | MMM (Industry Standard) |
|--------------|-------------------------|
| Requires device ID matching | Uses aggregate daily/weekly data |
| Blocked by privacy frameworks (ATT) | Privacy-compliant (no user tracking) |
| Cannot measure SANs (no touchpoints) | Measures all channels including SANs |
| Android 0%, iOS ~7% coverage | 100% coverage across all platforms |
| Best for user journey analysis | Best for budget allocation |

**What MMM needs (we can provide):**
- Daily spend by channel
- Daily installs by channel
- Daily revenue by cohort/channel
- External factors (seasonality, holidays, competitors)

**What MMM provides:**
- Channel effectiveness coefficients
- Optimal budget allocation recommendations
- Incrementality estimates (what spend is truly incremental vs baseline)
- Diminishing returns curves per channel

**Where MMM modeling happens:**
MMM is a statistical modeling problem, not a SQL problem. After dbt prepares the aggregate input data, modeling happens in specialized tools:
- **PyMC** (open-source Bayesian modeling)
- **Meta Robyn** (open-source MMM framework)
- **Google Meridian** (Google's MMM solution)
- Commercial vendors (Measured, Recast, etc.)

## What Stays Available

### We Are NOT Deleting MTA Models

All existing MTA models remain in the dbt project with limitation notices added:
- `mta__campaign_performance` (mart)
- `mta__network_comparison` (mart)
- `int_mta__user_journey` (intermediate)
- `int_mta__touchpoint_credit` (intermediate)
- `int_adjust_amplitude__device_mapping` (intermediate)

**Use case:** iOS-only tactical analysis for the ~7% IDFA-consented user segment.

### Adjust Attribution Continues to Work

Adjust's built-in **last-click attribution** operates independently of MTA device matching:
- Uses deterministic and probabilistic methods at install level
- Works for all platforms (Android and iOS)
- Provides campaign-level install and revenue attribution
- Available in Adjust dashboard and dbt models

### Aggregate Reporting Unaffected

Total metrics continue to work correctly:
- Total installs by channel (Adjust)
- Total revenue by cohort (Amplitude)
- Spend tracking by campaign
- ROAS calculations at campaign level

**What's limited is only the ability to connect individual ad touchpoints to individual user journeys.**

## Required External Actions

For tracking purposes only -- no timeline or pressure:

### To Enable Android MTA (Future)

**Owner:** Mobile engineering team
**Action:** Configure Amplitude SDK with `useAdvertisingIdForDeviceId()` and release new app version
**Impact:** Would enable Android device matching for users who update to new version
**Priority:** Low -- MMM pivot eliminates urgency

### To Improve iOS MTA Coverage (Optional)

**Owner:** Product/UX team
**Action:** Optimize ATT consent prompt messaging to increase user consent rate
**Impact:** Could increase iOS IDFA consent from 7% toward industry average of 12-19%
**Priority:** Low -- still limited by SAN coverage and small addressable segment

## Conclusion

**MTA is structurally limited and cannot serve as the basis for strategic marketing budget allocation.** The combination of Android 0% match rate, iOS ~7% IDFA consent, and 0% SAN touchpoint coverage means MTA can only measure a small fraction of marketing impact.

**MMM is the recommended path forward** for budget allocation, incrementality testing, and channel optimization. It is privacy-compliant, measures all channels including SANs, and is the industry-standard approach in the post-ATT era.

Existing MTA models remain available for iOS tactical analysis where user-level journey mapping is valuable for the consented segment.

---

**Phase:** 03-mta-limitations-mmm-foundation
**Related:** `.planning/phases/02-device-id-audit/02-02-SUMMARY.md` (Phase 2 findings)
**Next Steps:** Phase 3 builds MMM data foundation; MTA development work formally closed
