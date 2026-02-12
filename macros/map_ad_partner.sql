{#
    map_ad_partner

    Maps raw NETWORK_NAME values from Adjust to standardized AD_PARTNER taxonomy.

    Args:
        column_name (str): Name of the source column containing network name (typically 'NETWORK_NAME')

    Returns:
        SQL CASE statement that returns standardized partner name

    Example:
        {{ map_ad_partner('NETWORK_NAME') }} AS AD_PARTNER

    Coverage:
        - SANs: Meta, Google, TikTok, Apple
        - Programmatic: AppLovin, Unity, Moloco, Smadex, AdAction, Vungle, Tapjoy
        - Organic/Unattributed: Organic, Unattributed, Untrusted
        - Direct: WGT, Phigolf, Ryder Cup
        - Fallback: Other
#}
{%- macro map_ad_partner(column_name) -%}
    CASE
        WHEN {{ column_name }} IN ('Facebook Installs', 'Instagram Installs', 'Off-Facebook Installs', 'Facebook Messenger Installs') THEN 'Meta'
        WHEN {{ column_name }} IN ('Google Ads ACE', 'Google Ads ACI', 'Google Organic Search', 'google') THEN 'Google'
        WHEN {{ column_name }} IN ('TikTok SAN', 'TikTok_Paid_Ads_iOS', 'TikTok_Paid_Ads_Android', 'Tiktok Installs') THEN 'TikTok'
        WHEN {{ column_name }} = 'Apple Search Ads' THEN 'Apple'
        WHEN {{ column_name }} LIKE 'AppLovin%' THEN 'AppLovin'
        WHEN {{ column_name }} LIKE 'UnityAds%' THEN 'Unity'
        WHEN {{ column_name }} LIKE 'Moloco%' THEN 'Moloco'
        WHEN {{ column_name }} LIKE 'Smadex%' THEN 'Smadex'
        WHEN {{ column_name }} LIKE 'AdAction%' THEN 'AdAction'
        WHEN {{ column_name }} LIKE 'Vungle%' THEN 'Vungle'
        WHEN {{ column_name }} LIKE 'Tapjoy%' THEN 'Tapjoy'
        WHEN {{ column_name }} = 'Organic' THEN 'Organic'
        WHEN {{ column_name }} = 'Unattributed' THEN 'Unattributed'
        WHEN {{ column_name }} = 'Untrusted Devices' THEN 'Untrusted'
        WHEN {{ column_name }} IN ('wgtgolf', 'WGT_Events_SocialPosts_iOS', 'WGT_GiftCards_Social') THEN 'WGT'
        WHEN {{ column_name }} LIKE 'Phigolf%' THEN 'Phigolf'
        WHEN {{ column_name }} LIKE 'Ryder%' THEN 'Ryder Cup'
        ELSE 'Other'
    END
{%- endmacro -%}
