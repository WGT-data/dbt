-- ============================================================================
-- LIMITATION NOTICE (documented Phase 3, 2026-02)
--
-- This model is part of the Multi-Touch Attribution (MTA) pipeline.
-- Phase 2 audit (Feb 2026) found that MTA has structural coverage limitations:
--   - Android: 0% device match rate (Amplitude SDK uses random UUID, not GPS_ADID)
--   - iOS IDFA: 7.37% availability (Apple ATT framework)
--   - SANs (Meta, Google, Apple, TikTok): 0% touchpoint data (never shared)
--
-- This model is PRESERVED for iOS tactical analysis only.
-- For strategic budget allocation, use MMM models in marts/mmm/.
--
-- To fix Android: Amplitude SDK must be configured with useAdvertisingIdForDeviceId()
-- See: .planning/phases/03-device-id-normalization-fix/mta-limitations.md
--
-- STATUS: Never built to production. Static table ADJUST_AMPLITUDE_DEVICE_MAPPING
-- (stale since Nov 2025) is the only existing mapping. iOS IDFV-only.
-- ============================================================================

{{
    config(
        materialized='incremental',
        unique_key=['ADJUST_DEVICE_ID', 'AMPLITUDE_USER_ID', 'PLATFORM'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

SELECT DEVICE_ID_UUID AS ADJUST_DEVICE_ID
     , USER_ID_INTEGER AS AMPLITUDE_USER_ID
     , PLATFORM
     , FIRST_SEEN_AT
FROM {{ ref('v_stg_amplitude__merge_ids') }}
{% if is_incremental() %}
    -- 7-day lookback to capture new device mappings
    WHERE FIRST_SEEN_AT >= DATEADD(day, -7, (SELECT MAX(FIRST_SEEN_AT) FROM {{ this }}))
{% endif %}
