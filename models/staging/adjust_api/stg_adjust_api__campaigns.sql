{{
    config(
        materialized='view',
        schema='staging'
    )
}}

/*
    Staging model for Adjust API campaign data.
    This model provides a clean interface to the API-loaded data,
    with column naming and typing consistent with the Supermetrics source.
*/

with source as (

    select * from {{ source('adjust_api', 'adj_campaign_api') }}

),

renamed as (

    select
        -- Dimensions
        date as report_date,
        app as app_name,
        os_name,
        device_type,
        country,
        country_code,
        region,
        partner_id,
        partner_name,
        campaign_id_network,
        campaign_network as campaign_name,
        adgroup_id_network,
        adgroup_network as adgroup_name,
        ad_id,
        ad_name,
        store_id,
        store_type,
        platform,
        currency_code,
        data_source_name,

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

        -- Revenue Events
        coalesce(c_datascape_bundle_purchase_events, 0) as bundle_purchase_events,
        coalesce(c_datascape_bundle_purchase_revenue, 0) as bundle_purchase_revenue,
        coalesce(c_datascape_coin_purchase_events, 0) as coin_purchase_events,
        coalesce(c_datascape_coin_purchase_revenue, 0) as coin_purchase_revenue,
        coalesce(c_datascape_credit_purchase_events, 0) as credit_purchase_events,
        coalesce(c_datascape_credit_purchase_revenue, 0) as credit_purchase_revenue,
        coalesce(c_datascape_playforcashclick_events, 0) as playforcash_click_events,
        coalesce(c_datascape_playforcashclick_revenue, 0) as playforcash_click_revenue,

        -- Level Events
        coalesce(c_datascape_reachlevel_5_events, 0) as reach_level_5_events,
        coalesce(c_datascape_reachlevel_10_events, 0) as reach_level_10_events,
        coalesce(c_datascape_reachlevel_20_events, 0) as reach_level_20_events,
        coalesce(c_datascape_reachlevel_30_events, 0) as reach_level_30_events,
        coalesce(c_datascape_reachlevel_40_events, 0) as reach_level_40_events,
        coalesce(c_datascape_reachlevel_50_events, 0) as reach_level_50_events,
        coalesce(c_datascape_reachlevel_60_events, 0) as reach_level_60_events,
        coalesce(c_datascape_reachlevel_70_events, 0) as reach_level_70_events,
        coalesce(c_datascape_reachlevel_80_events, 0) as reach_level_80_events,
        coalesce(c_datascape_reachlevel_90_events, 0) as reach_level_90_events,
        coalesce(c_datascape_reachlevel_100_events, 0) as reach_level_100_events,
        coalesce(c_datascape_reachlevel_110_events, 0) as reach_level_110_events,

        -- Onboarding Events
        coalesce(c_datascape_registration_events, 0) as registration_events,
        coalesce(c_datascape_tutorial_completed_events, 0) as tutorial_completed_events,
        coalesce(c_datascape_tutorial_completed_revenue, 0) as tutorial_completed_revenue,

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

        -- Total Revenue (sum of all revenue events)
        coalesce(c_datascape_bundle_purchase_revenue, 0)
        + coalesce(c_datascape_coin_purchase_revenue, 0)
        + coalesce(c_datascape_credit_purchase_revenue, 0)
        + coalesce(c_datascape_playforcashclick_revenue, 0)
        as total_revenue,

        -- Metadata
        loaded_at

    from source

)

select * from renamed
