# Phase 4: DRY Refactor - Context

**Gathered:** 2026-02-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Extract the duplicated AD_PARTNER CASE statement (identical in `v_stg_adjust__installs.sql` and `v_stg_adjust__touchpoints.sql`) into a single reusable source. Verify output parity after refactor. No new mapping logic or new models.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation decisions deferred to Claude. User indicated they're not opinionated on approach — "go with what you think works."

**Extraction approach:**
- Recommend: Macro with hardcoded CASE statement (`macros/map_ad_partner.sql`) rather than seed JOIN approach
- Rationale: The existing `network_mapping.csv` seed serves a different purpose (SuperMetrics partner mapping with IDs) and uses exact-match names, while the CASE statement uses LIKE patterns (AppLovin%, Moloco%, Smadex%, etc.) that a simple seed JOIN can't replicate. Macro keeps behavior identical with zero risk.
- Both staging models call the macro instead of inlining the CASE

**Coverage gaps:**
- Current CASE statement is missing Tapjoy (2 entries in seed) and TikTok_Paid_Ads_Android (in seed) — these currently fall to 'Other'
- Recommend: Fix coverage gaps during macro extraction since we're touching this logic anyway. Add Tapjoy and TikTok_Paid_Ads_Android to the macro.
- This is a bug fix, not scope creep — the mappings should have been there

**Unmapped network handling:**
- Keep current behavior: unmapped networks fall to 'Other'
- No need to add alerting or flagging for unknown networks in this phase

**Verification:**
- Consistency test should compare macro output to original CASE output for all distinct NETWORK_NAME values in production data
- Both models must produce identical AD_PARTNER values after refactor

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

- Switching to seed-based JOIN approach (would require adding LIKE pattern support or expanding seed with all variant names) — could be a future improvement if mapping changes become frequent
- Network mapping coverage audit (systematic check that all active NETWORK_NAME values map correctly) — Phase 5 already covers this

</deferred>

---

*Phase: 04-dry-refactor*
*Context gathered: 2026-02-11*
