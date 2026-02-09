Use the snowflake-wgt MCP to validate all DOWNSTREAM dbt models built on top of the Adjust activity tables. The staging activity tables themselves are fine. Validate the staging views, intermediate layer, and marts layer.

Read the dbt model SQL files in models/ to understand the logic before querying. Run validation queries one layer at a time, bottom-up.

DATABASE/SCHEMA LOCATIONS:

- Adjust activity tables: ADJUST.S3_DATA.*
- dbt intermediate/marts tables: WGT.DBT_ANALYTICS.* (prod) or WGT.DBT_WGTDATA.* (dev)
- Amplitude source: WGT.AMPLITUDE.EVENTS_726530
- Revenue source: WGT.REVENUE.DIRECT_REVENUE_EVENTS
- Supermetrics source: WGT.SUPERMETRICS.ADJ_CAMPAIGN
- Facebook source: FIVETRAN_DATABASE.FACEBOOK_ADS.*
- Adjust API source: ADJUST.API_DATA.*

If the above database/schema paths fail, run these discovery queries first:
  SHOW DATABASES;
  SHOW SCHEMAS IN DATABASE WGT;
  SHOW SCHEMAS IN DATABASE ADJUST;
  SHOW TABLES IN SCHEMA WGT.DBT_ANALYTICS;
Then adjust all queries to match what you find.

# ======================================================================

LAYER 1: STAGING VIEWS (validate these first)

1A. v_stg_adjust__installs (built on IOS_ACTIVITY_INSTALL + ANDROID_ACTIVITY_INSTALL)

- Verify row counts: combined iOS + Android installs vs view output
- Check dedup logic: confirm no duplicate DEVICE_ID + PLATFORM combos
SELECT DEVICE_ID, PLATFORM, COUNT(*) AS CNT
FROM **
GROUP BY DEVICE_ID, PLATFORM
HAVING COUNT(*) > 1
LIMIT 20;
- Verify NULL filtering worked: no rows with NULL DEVICE_ID or NULL INSTALLED_AT
- Check AD_PARTNER mapping: sample 100 rows, verify NETWORK_NAME maps to expected AD_PARTNER
- Check CAMPAIGN_ID regex extraction: spot-check that CAMPAIGN_ID parsed correctly from CAMPAIGN_NAME

1B. v_stg_adjust__touchpoints (built on IOS/ANDROID ACTIVITY_IMPRESSION + ACTIVITY_CLICK)

- Row count: union of all 4 source tables vs target
- Check PLATFORM + TOUCHPOINT_TYPE distribution:
SELECT PLATFORM, TOUCHPOINT_TYPE, COUNT(*) AS CNT
FROM 
GROUP BY PLATFORM, TOUCHPOINT_TYPE;
- Verify no rows with both DEVICE_ID and IDFA null (iOS) or DEVICE_ID and IP_ADDRESS null (Android)
- Verify epoch filter: no CREATED_AT < 1704067200

1C. v_stg_amplitude__merge_ids (device-to-user mapping)

- Check for one-to-many: each DEVICE_ID_UUID + PLATFORM should map to exactly 1 USER_ID
SELECT DEVICE_ID_UUID, PLATFORM, COUNT(DISTINCT USER_ID_INTEGER) AS USER_CNT
FROM 
GROUP BY DEVICE_ID_UUID, PLATFORM
HAVING COUNT(DISTINCT USER_ID_INTEGER) > 1
LIMIT 20;
- Verify Android R-suffix stripping: no DEVICE_ID_UUID ending in 'R'
- Verify all DEVICE_ID_UUID values are uppercase

1D. v_stg_amplitude__events

- Row count sanity check
- Verify SERVER_UPLOAD_TIME >= '2025-01-01' filter

1E. v_stg_revenue__events

- Row count sanity check
- Verify EVENT_TIME >= '2025-01-01'
- Check for NULL REVENUE_AMOUNT (should only exist where revenue event has no dollar value)

1F. stg_supermetrics__adj_campaign

- Row count vs source
- Check dedup: run the QUALIFY ROW_NUMBER logic and verify no dupes remain
- Verify PLATFORM standardization: only 'iOS' and 'Android' values

1G. Facebook staging views (v_stg_facebook_spend, v_stg_facebook_conversions, etc.)

- v_stg_facebook_spend: verify JOIN to history tables produces results
- v_stg_facebook_conversions: verify DIVIDEND column is not zero (would cause divide-by-zero downstream)
SELECT COUNT(*) FROM  WHERE DIVIDEND = 0;

# ======================================================================

LAYER 2: INTERMEDIATE MODELS

2A. int_adjust_amplitude__device_mapping

- Compare to v_stg_amplitude__merge_ids: row count should be similar
- Verify uniqueness on ADJUST_DEVICE_ID + AMPLITUDE_USER_ID + PLATFORM

2B. int_mta__user_journey

- This joins touchpoints to installs within a 7-day lookback window
- Verify no touchpoints linked to installs more than 7 days prior:
SELECT COUNT(*) AS VIOLATIONS
FROM 
WHERE DAYS_TO_INSTALL > 7;
- Check touchpoint counts per install are reasonable (not thousands):
SELECT TOTAL_TOUCHPOINTS, COUNT(*) AS INSTALL_CNT
FROM 
GROUP BY TOTAL_TOUCHPOINTS
ORDER BY TOTAL_TOUCHPOINTS DESC
LIMIT 20;
- Verify IS_FIRST_TOUCH and IS_LAST_TOUCH flags: exactly 1 of each per DEVICE_ID + PLATFORM + INSTALL_TIMESTAMP
SELECT DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
 , SUM(CASE WHEN IS_FIRST_TOUCH = 1 THEN 1 ELSE 0 END) AS FIRST_CNT
 , SUM(CASE WHEN IS_LAST_TOUCH = 1 THEN 1 ELSE 0 END) AS LAST_CNT
FROM 
GROUP BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
HAVING FIRST_CNT != 1 OR LAST_CNT != 1
LIMIT 20;

2C. int_mta__touchpoint_credit

- All 5 attribution models should sum to ~1.0 per install:
SELECT DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
 , ROUND(SUM(CREDIT_LAST_TOUCH), 4) AS LT_SUM
 , ROUND(SUM(CREDIT_FIRST_TOUCH), 4) AS FT_SUM
 , ROUND(SUM(CREDIT_LINEAR), 4) AS LIN_SUM
 , ROUND(SUM(CREDIT_TIME_DECAY), 4) AS TD_SUM
 , ROUND(SUM(CREDIT_POSITION_BASED), 4) AS PB_SUM
FROM 
GROUP BY DEVICE_ID, PLATFORM, INSTALL_TIMESTAMP
HAVING ABS(LT_SUM - 1) > 0.01
OR ABS(FT_SUM - 1) > 0.01
OR ABS(LIN_SUM - 1) > 0.01
OR ABS(PB_SUM - 1) > 0.01
LIMIT 20;
(Note: TIME_DECAY won't sum to exactly 1.0, but should be close. Flag if wildly off.)
- Verify CREDIT_LAST_TOUCH = 1.0 only for the last touchpoint, 0 for all others
- Verify CREDIT_FIRST_TOUCH = 1.0 only for the first touchpoint, 0 for all others

2D. int_skan__aggregate_attribution

- Verify NO device-level identifiers exist (IDFV, IDFA, GPS_ADID should not be columns)
- Check grain: no duplicate AD_PARTNER + CAMPAIGN_NAME + PLATFORM + DATE rows
- Verify conversion value buckets sum correctly:
SELECT SUM(CV_0) + SUM(CV_1_10) + SUM(CV_11_20) + SUM(CV_21_40) + SUM(CV_41_63) AS BUCKET_TOTAL
 , SUM(TOTAL_INSTALLS) AS INSTALL_TOTAL
FROM ;
(BUCKET_TOTAL should equal INSTALL_TOTAL)

2E. int_user_cohort__attribution

- One row per USER_ID + PLATFORM:
SELECT USER_ID, PLATFORM, COUNT(*) AS CNT
FROM **
GROUP BY USER_ID, PLATFORM
HAVING COUNT(*) > 1
LIMIT 20;
- Verify JOIN to device mapping is working: check NULL rate for USER_ID
SELECT COUNT(*) AS TOTAL
 , COUNT(USER_ID) AS WITH_USER
 , ROUND(COUNT(USER_ID) / COUNT(*) * 100, 1) AS MATCH_RATE_PCT
FROM ;

2F. int_user_cohort__metrics

- Verify retention flags are binary (0 or 1 only):
SELECT DISTINCT D1_RETAINED FROM ;
SELECT DISTINCT D7_RETAINED FROM ;
SELECT DISTINCT D30_RETAINED FROM ;
- Revenue sanity: D7_REVENUE <= D30_REVENUE <= TOTAL_REVENUE for every user
SELECT COUNT(*) AS VIOLATIONS
FROM 
WHERE D7_REVENUE > D30_REVENUE
 OR D30_REVENUE > TOTAL_REVENUE;
- Maturity flags: D7_MATURE = 1 only if install is 7+ days old, etc.
SELECT COUNT(*) AS VIOLATIONS
FROM 
WHERE D7_MATURE = 1
AND DATEDIFF(day, INSTALL_DATE, CURRENT_DATE()) < 7;

2G. int_revenue__user_summary

- No negative TOTAL_REVENUE values
- PURCHASE_COUNT should be >= 0

# ======================================================================

LAYER 3: MARTS

3A. attribution__installs

- Grain check: no dupes on AD_PARTNER + NETWORK_NAME + CAMPAIGN_ID + ADGROUP_ID + PLATFORM + INSTALL_DATE
- Total installs should roughly match v_stg_adjust__installs (minus organic/unattributed if filtered)
- No NULL AD_PARTNER values

3B. attribution__campaign_performance

- Verify spend allocation: total COST in this table should match total from stg_supermetrics__adj_campaign
SELECT SUM(COST) FROM ;
vs
SELECT SUM(NETWORK_COST) FROM  WHERE DATE >= '2025-01-01';
- CPI sanity: no negative CPI, no CPI > $100 (flag outliers)
SELECT * FROM  WHERE CPI > 100 OR CPI < 0 LIMIT 10;
- ROAS sanity: check for any extreme values

3C. attribution__network_performance

- Same spend total check as 3B but at network level
- Full outer join: check for rows with spend but no installs and vice versa
SELECT AD_PARTNER, PLATFORM, SUM(COST) AS COST, SUM(ATTRIBUTION_INSTALLS) AS INSTALLS
FROM 
WHERE COST > 0 AND ATTRIBUTION_INSTALLS = 0
GROUP BY AD_PARTNER, PLATFORM;

3D. mta__campaign_performance

- All 5 attribution model columns should have non-null values
- MTA install totals should be close to last-touch totals (within 5-10%)
SELECT SUM(INSTALLS_LAST_TOUCH) AS LT
 , SUM(INSTALLS_TIME_DECAY) AS TD
 , SUM(INSTALLS_LINEAR) AS LIN
FROM ;

3E. mart_campaign_performance_full

- This is the big one. Validate:
  - No NULL dates
  - Retention rates between 0 and 1
  - D1_RETENTION_RATE >= D7_RETENTION_RATE >= D30_RETENTION_RATE (on average)
  - ROAS values reasonable (typically 0-5x for mobile gaming)
  - Sample 10 rows and manually verify CPI = COST / INSTALLS

3F. mart_campaign_performance_full_mta

- All 6 attribution model columns present and non-null
- Cross-check: ADJUST installs should match attribution__installs totals
- Verify no fan-out: total installs under each model should be comparable
SELECT SUM(ADJUST_INSTALLS) AS ADJ
 , SUM(MTA_LAST_TOUCH_INSTALLS) AS LT
 , SUM(MTA_TIME_DECAY_INSTALLS) AS TD
FROM ;

3G. Spend marts (adjust_daily_performance_by_ad, facebook_conversions)

- adjust_daily_performance_by_ad: verify DATE >= '2025-01-01' filter
- facebook_conversions: verify no DIVIDEND = 0 rows made it through

# ======================================================================

OUTPUT FORMAT

Create a validation report with these sections:

For each model, report:

- TABLE_NAME
- ROW_COUNT
- PASS/FAIL for each check
- Specific error details if FAIL (with sample rows)

Save the full results to a markdown file in the project root called VALIDATION_REPORT.md.

At the end, provide a summary: total models checked, total passes, total failures, and a ranked list of issues by severity.

# ======================================================================

SQL FORMAT

Format all SQL like this:
SELECT CAST(F.DATE AS DATE) AS DATE
     , G.ACCOUNT
     , G.CAMPAIGN
FROM TABLE_A F
JOIN TABLE_B G ON F.ID = G.ID
GROUP BY F.DATE
     , G.ACCOUNT
     , G.CAMPAIGN

# ======================================================================

IMPORTANT NOTES

- Use ONLY the snowflake-wgt MCP for queries. Do not use any other data warehouse connector.
- If a table doesn't exist, note it and move on. Some models may not have been run yet.
- Run discovery queries first if schema paths don't resolve.
- Keep queries efficient. Use LIMIT and COUNT rather than SELECT *.
- For large tables, sample rather than full-scan where possible.

