{{
    config(
        materialized='view',
        schema='staging'
    )
}}

/*
    Staging model for Adjust API campaign data.
    Maps ADJUST.API_DATA.REPORT_DAILY_RAW columns to match
    the Supermetrics source schema for compatibility with
    stg_adjust__campaigns_unified.
*/

with source as (

    select * from {{ source('adjust_api', 'REPORT_DAILY_RAW') }}

),

renamed as (

    select
        -- Dimensions
        day as report_date,
        app as app_name,
        os_name,
        device_type,
        country,
        country_code,
        region,
        network as partner_id,
        network as partner_name,
        campaign_id_network,
        campaign_network as campaign_name,
        adgroup_id_network,
        adgroup_network as adgroup_name,
        creative_id_network as ad_id,
        creative_network as ad_name,
        store_id,
        store_type,
        case
            when upper(os_name) = 'IOS' then 'iOS'
            when upper(os_name) = 'ANDROID' then 'Android'
            else os_name
        end as platform,
        null as currency_code,
        source_network as data_source_name,

        -- Standard Metrics
        coalesce(installs, 0) as installs,
        coalesce(clicks, 0) as clicks,
        coalesce(impressions, 0) as impressions,
        coalesce(sessions, 0) as sessions,
        coalesce(base_sessions, 0) as base_sessions,
        coalesce(cost, 0) as cost,
        coalesce(adjust_cost, 0) as adjust_cost,
        coalesce(network_cost, 0) as network_cost,
        coalesce(reattributions, 0) as reattributions,
        coalesce(reattribution_reinstalls, 0) as reattribution_reinstalls,
        coalesce(reinstalls, 0) as reinstalls,
        coalesce(uninstalls, 0) as uninstalls,
        coalesce(deattributions, 0) as deattributions,
        coalesce(events, 0) as events,
        coalesce(paid_clicks, 0) as paid_clicks,
        coalesce(paid_impressions, 0) as paid_impressions,
        coalesce(paid_installs, 0) as paid_installs,

        -- Revenue Events (not broken out in API data)
        0 as bundle_purchase_events,
        0 as bundle_purchase_revenue,
        0 as coin_purchase_events,
        0 as coin_purchase_revenue,
        0 as credit_purchase_events,
        0 as credit_purchase_revenue,
        0 as playforcash_click_events,
        0 as playforcash_click_revenue,

        -- Level Events (not available in API data)
        0 as reach_level_5_events,
        0 as reach_level_10_events,
        0 as reach_level_20_events,
        0 as reach_level_30_events,
        0 as reach_level_40_events,
        0 as reach_level_50_events,
        0 as reach_level_60_events,
        0 as reach_level_70_events,
        0 as reach_level_80_events,
        0 as reach_level_90_events,
        0 as reach_level_100_events,
        0 as reach_level_110_events,

        -- Onboarding Events (not available in API data)
        0 as registration_events,
        0 as tutorial_completed_events,
        0 as tutorial_completed_revenue,

        -- Calculated Metrics
        case
            when clicks > 0 then installs::float / clicks
            else 0
        end as click_conversion_rate,

        case
            when impressions > 0 then clicks::float / impressions
            else 0
        end as ctr,

        case
            when installs > 0 then cost / installs
            else 0
        end as cpi,

        -- Total Revenue (aggregate from API)
        coalesce(revenue, 0) as total_revenue,

        -- Metadata
        null as loaded_at

    from source

)

select * from renamed
