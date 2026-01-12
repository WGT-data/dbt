-- Device to User mapping for attribution
-- Maps each device to the FIRST user seen on that device
-- This ensures install attribution goes to the user who actually installed

{{
    config(
        materialized='incremental',
        unique_key=['DEVICE_ID_UUID', 'USER_ID_INTEGER', 'PLATFORM'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

WITH DEVICE_USER_ACTIVITY AS (
    SELECT AE.DEVICE_ID
         , AE.USER_ID
         , AE.PLATFORM
         , MIN(AE.EVENT_TIME) AS FIRST_EVENT_TIME
         , MAX(IFF(AE.EVENT_TYPE = 'NewPlayerCreation_Success', 1, 0)) AS IS_NEW_USER
    FROM {{ source('amplitude', 'EVENTS_726530') }} AE
    WHERE AE.DEVICE_ID IS NOT NULL
      AND AE.USER_ID IS NOT NULL
      AND AE.PLATFORM IN ('iOS', 'Android')
      AND TRY_PARSE_JSON(AE.EVENT_PROPERTIES):EventSource::STRING = 'Client'
      AND AE.EVENT_TYPE IN ('Cookie_Existing_Account', 'NewPlayerCreation_Success')
    {% if is_incremental() %}
      -- 7-day lookback to capture new device-user mappings
      AND AE.SERVER_UPLOAD_TIME >= DATEADD(day, -7, (SELECT MAX(FIRST_SEEN_AT) FROM {{ this }}))
    {% endif %}
    GROUP BY AE.DEVICE_ID, AE.USER_ID, AE.PLATFORM
)

, RANKED_USERS AS (
    SELECT DEVICE_ID
         , USER_ID
         , PLATFORM
         , FIRST_EVENT_TIME
         , ROW_NUMBER() OVER (
             PARTITION BY DEVICE_ID, PLATFORM
             ORDER BY IS_NEW_USER DESC
                    , FIRST_EVENT_TIME ASC
           ) AS USER_RANK
    FROM DEVICE_USER_ACTIVITY
)

-- Normalize device IDs to match Adjust format:
-- iOS: uppercase UUID to match Adjust IDFV
-- Android: strip trailing 'R' suffix that Amplitude appends
SELECT UPPER(
           IFF(PLATFORM = 'Android' AND RIGHT(DEVICE_ID, 1) = 'R'
              , LEFT(DEVICE_ID, LENGTH(DEVICE_ID) - 1)
              , DEVICE_ID
           )
       ) AS DEVICE_ID_UUID
     , USER_ID AS USER_ID_INTEGER
     , PLATFORM
     , FIRST_EVENT_TIME AS FIRST_SEEN_AT
FROM RANKED_USERS
WHERE USER_RANK = 1
