-- test_ad_partner_mapping_consistency.sql
-- Validates that the map_ad_partner macro produces correct AD_PARTNER values for all known NETWORK_NAME inputs.
-- This test ensures the macro covers all 18 CASE branches including Tapjoy and TikTok_Paid_Ads_Android.
--
-- Test passes when zero rows returned (no mismatches).
-- Test fails if any expected_partner != actual_partner.

WITH known_mappings AS (
    -- Meta (Facebook)
    SELECT 'Facebook Installs' AS network_name, 'Meta' AS expected_partner
    UNION ALL SELECT 'Instagram Installs', 'Meta'
    UNION ALL SELECT 'Off-Facebook Installs', 'Meta'
    UNION ALL SELECT 'Facebook Messenger Installs', 'Meta'

    -- Google
    UNION ALL SELECT 'Google Ads ACE', 'Google'
    UNION ALL SELECT 'Google Ads ACI', 'Google'
    UNION ALL SELECT 'Google Organic Search', 'Google'
    UNION ALL SELECT 'google', 'Google'

    -- TikTok (including new TikTok_Paid_Ads_Android coverage)
    UNION ALL SELECT 'TikTok SAN', 'TikTok'
    UNION ALL SELECT 'TikTok_Paid_Ads_iOS', 'TikTok'
    UNION ALL SELECT 'TikTok_Paid_Ads_Android', 'TikTok'
    UNION ALL SELECT 'Tiktok Installs', 'TikTok'

    -- Apple
    UNION ALL SELECT 'Apple Search Ads', 'Apple'

    -- AppLovin (LIKE pattern)
    UNION ALL SELECT 'AppLovin_iOS_2019', 'AppLovin'
    UNION ALL SELECT 'AppLovin DSP - Android', 'AppLovin'

    -- Unity (LIKE pattern)
    UNION ALL SELECT 'UnityAds_2023_iOS_Launch_Campaign', 'Unity'
    UNION ALL SELECT 'UnityAds DSP', 'Unity'

    -- Moloco (LIKE pattern)
    UNION ALL SELECT 'Moloco_DSP_iOS', 'Moloco'
    UNION ALL SELECT 'Moloco - Android Campaign', 'Moloco'

    -- Smadex (LIKE pattern)
    UNION ALL SELECT 'Smadex DSP - iOS', 'Smadex'
    UNION ALL SELECT 'Smadex_Android_2024', 'Smadex'

    -- AdAction (LIKE pattern)
    UNION ALL SELECT 'AdAction_iOS_2021', 'AdAction'
    UNION ALL SELECT 'AdAction - Android', 'AdAction'

    -- Vungle (LIKE pattern)
    UNION ALL SELECT 'Vungle_Something', 'Vungle'
    UNION ALL SELECT 'Vungle DSP iOS', 'Vungle'

    -- Tapjoy (LIKE pattern - NEW coverage)
    UNION ALL SELECT 'Tapjoy', 'Tapjoy'
    UNION ALL SELECT 'Tapjoy_Android_CPE_Campaign2021', 'Tapjoy'
    UNION ALL SELECT 'Tapjoy iOS Offerwall', 'Tapjoy'

    -- Organic
    UNION ALL SELECT 'Organic', 'Organic'

    -- Unattributed
    UNION ALL SELECT 'Unattributed', 'Unattributed'

    -- Untrusted
    UNION ALL SELECT 'Untrusted Devices', 'Untrusted'

    -- WGT
    UNION ALL SELECT 'wgtgolf', 'WGT'
    UNION ALL SELECT 'WGT_Events_SocialPosts_iOS', 'WGT'
    UNION ALL SELECT 'WGT_GiftCards_Social', 'WGT'

    -- Phigolf (LIKE pattern)
    UNION ALL SELECT 'Phigolf_2024', 'Phigolf'
    UNION ALL SELECT 'Phigolf Partnership', 'Phigolf'

    -- Ryder Cup (LIKE pattern)
    UNION ALL SELECT 'Ryder_Cup_Campaign', 'Ryder Cup'
    UNION ALL SELECT 'Ryder 2024', 'Ryder Cup'

    -- Other (ELSE branch)
    UNION ALL SELECT 'SomeUnknownNetwork', 'Other'
    UNION ALL SELECT 'Random_New_Partner_2025', 'Other'
    UNION ALL SELECT NULL, 'Other'
)

, actual_output AS (
    SELECT network_name
         , expected_partner
         , {{ map_ad_partner('network_name') }} AS actual_partner
    FROM known_mappings
)

-- Return only mismatches (zero rows = test passes)
SELECT network_name
     , expected_partner
     , actual_partner
FROM actual_output
WHERE expected_partner != actual_partner
   OR (expected_partner IS NULL AND actual_partner IS NOT NULL)
   OR (expected_partner IS NOT NULL AND actual_partner IS NULL)
