{{
    config(
        materialized='incremental',
        unique_key='USER_ID',
        incremental_strategy='merge',
        merge_update_columns=['PURCHASE_COUNT', 'TOTAL_REVENUE'],
        on_schema_change='append_new_columns'
    )
}}

-- Note: This model re-aggregates all data for users with new events
-- Uses a lookback window to identify which users have new activity
WITH users_with_recent_activity AS (
    SELECT DISTINCT USER_ID
    FROM {{ ref('v_stg_revenue__events') }}
    {% if is_incremental() %}
        -- 3-day lookback to capture users with recent revenue events
        WHERE EVENT_TIME >= DATEADD(day, -3, (SELECT MAX(EVENT_TIME) FROM {{ ref('v_stg_revenue__events') }}))
    {% endif %}
)

SELECT r.USER_ID
     , COUNT(*) AS PURCHASE_COUNT
     , SUM(r.REVENUE_AMOUNT) AS TOTAL_REVENUE
FROM {{ ref('v_stg_revenue__events') }} r
{% if is_incremental() %}
    INNER JOIN users_with_recent_activity u
        ON r.USER_ID = u.USER_ID
{% endif %}
GROUP BY r.USER_ID