# ADJUST_S3 → ADJUST Database Rename Changes

This document outlines all dbt model and documentation changes required to rename the database from `ADJUST_S3` to `ADJUST`.

## Summary

| Category | File Count | Changes |
|----------|------------|---------|
| Source YAML | 1 | 1 change |
| SQL Models | 28 | 56 changes (2 per file) |
| Documentation | 5 | 14 changes |
| **Total** | **34 files** | **71 changes** |

---

## 1. Source Definition

### File: `models/staging/adjust/_adjust__sources.yml`

**Line 6:**
```yaml
# Before
database: ADJUST_S3

# After
database: ADJUST
```

---

## 2. SQL Staging Models (28 files)

Each staging model has two changes:
1. Config block `database` parameter
2. FROM clause reference

### iOS Models (17 files)

#### `stg_adjust__ios_activity_install.sql`
```sql
-- Line 4: Config block
database='ADJUST_S3'  →  database='ADJUST'

-- Line 13: FROM clause
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_session.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_event.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_click.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_impression.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_reattribution.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_reattribution_update.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_install_update.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_rejected_install.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_rejected_reattribution.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_att_update.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_sk_install.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_sk_install_direct.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_sk_event.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_sk_cv_update.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

#### `stg_adjust__ios_activity_sk_qualifier.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.IOS_EVENTS  →  FROM ADJUST.DATA.IOS_EVENTS
```

### Android Models (11 files)

#### `stg_adjust__android_activity_install.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.ANDROID_EVENTS  →  FROM ADJUST.DATA.ANDROID_EVENTS
```

#### `stg_adjust__android_activity_session.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.ANDROID_EVENTS  →  FROM ADJUST.DATA.ANDROID_EVENTS
```

#### `stg_adjust__android_activity_event.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.ANDROID_EVENTS  →  FROM ADJUST.DATA.ANDROID_EVENTS
```

#### `stg_adjust__android_activity_click.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.ANDROID_EVENTS  →  FROM ADJUST.DATA.ANDROID_EVENTS
```

#### `stg_adjust__android_activity_impression.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.ANDROID_EVENTS  →  FROM ADJUST.DATA.ANDROID_EVENTS
```

#### `stg_adjust__android_activity_reattribution.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.ANDROID_EVENTS  →  FROM ADJUST.DATA.ANDROID_EVENTS
```

#### `stg_adjust__android_activity_reattribution_update.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.ANDROID_EVENTS  →  FROM ADJUST.DATA.ANDROID_EVENTS
```

#### `stg_adjust__android_activity_install_update.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.ANDROID_EVENTS  →  FROM ADJUST.DATA.ANDROID_EVENTS
```

#### `stg_adjust__android_activity_rejected_install.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.ANDROID_EVENTS  →  FROM ADJUST.DATA.ANDROID_EVENTS
```

#### `stg_adjust__android_activity_rejected_reattribution.sql`
```sql
database='ADJUST_S3'  →  database='ADJUST'
FROM ADJUST_S3.DATA.ANDROID_EVENTS  →  FROM ADJUST.DATA.ANDROID_EVENTS
```

---

## 3. Documentation Files

### `README.md`

**Line 215 (Data Sources table):**
```markdown
# Before
| Adjust | ADJUST_S3 | IOS_ACTIVITY, ANDROID_ACTIVITY | Raw install/click/impression data |

# After
| Adjust | ADJUST | IOS_ACTIVITY, ANDROID_ACTIVITY | Raw install/click/impression data |
```

**Line 57 (Model Details section):**
```markdown
# Before
Raw install, click, impression, and SKAN event data from Adjust S3 exports.

# After
Raw install, click, impression, and SKAN event data from Adjust exports.
```

### `.planning/codebase/CONCERNS.md`

**Line 32:**
```markdown
# Before
references sources directly with full paths (`ADJUST_S3.PROD_DATA.IOS_ACTIVITY_INSTALL`)

# After
references sources directly with full paths (`ADJUST.PROD_DATA.IOS_ACTIVITY_INSTALL`)
```

**Line 60:**
```markdown
# Before
Multiple databases referenced (ADJUST_S3, AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE, ...)

# After
Multiple databases referenced (ADJUST, AMPLITUDEANALYTICS_AMPLITUDE_DB_364926_SHARE, ...)
```

### `.planning/codebase/INTEGRATIONS.md`

**Line 9:**
```markdown
Database: `ADJUST_S3`  →  Database: `ADJUST`
```

**Line 46:**
```markdown
Multiple databases: `ADJUST_S3`  →  Multiple databases: `ADJUST`
```

**Line 69:**
```markdown
| Adjust | S3 → Snowflake | `ADJUST_S3` |  →  | Adjust | S3 → Snowflake | `ADJUST` |
```

**Line 110:**
```markdown
`ADJUST_S3.PROD_DATA`  →  `ADJUST.PROD_DATA`
```

**Line 137:**
```markdown
[Adjust S3]          →  ADJUST_S3.PROD_DATA
# Change to:
[Adjust S3]          →  ADJUST.PROD_DATA
```

### `.planning/codebase/ARCHITECTURE.md`

**Line 46:**
```markdown
# Before
loaded to Snowflake from Adjust (`ADJUST_S3.PROD_DATA`)

# After
loaded to Snowflake from Adjust (`ADJUST.PROD_DATA`)
```

### `incremental_predicates_validation_report.md`

**Lines 22, 54, 77, 213, 217:**
```markdown
ADJUST_S3.DATA.IOS_EVENTS  →  ADJUST.DATA.IOS_EVENTS
ADJUST_S3.DATA.ANDROID_EVENTS  →  ADJUST.DATA.ANDROID_EVENTS
```

---

## Execution Script

Run this sed command from the dbt project root to make all changes:

```bash
# Replace in all SQL files
find models/staging/adjust -name "*.sql" -exec sed -i '' "s/ADJUST_S3/ADJUST/g" {} \;

# Replace in source YAML
sed -i '' "s/database: ADJUST_S3/database: ADJUST/g" models/staging/adjust/_adjust__sources.yml

# Replace in documentation
sed -i '' "s/ADJUST_S3/ADJUST/g" README.md
sed -i '' "s/ADJUST_S3/ADJUST/g" .planning/codebase/CONCERNS.md
sed -i '' "s/ADJUST_S3/ADJUST/g" .planning/codebase/INTEGRATIONS.md
sed -i '' "s/ADJUST_S3/ADJUST/g" .planning/codebase/ARCHITECTURE.md
sed -i '' "s/ADJUST_S3/ADJUST/g" incremental_predicates_validation_report.md
```

---

## Pre-Deployment Checklist

1. [ ] Confirm the ADJUST database exists in Snowflake with the same schema structure as ADJUST_S3
2. [ ] Verify permissions are granted on the new ADJUST database
3. [ ] Run `dbt compile` to validate all model references resolve correctly
4. [ ] Run `dbt build --select staging.adjust` in dev environment
5. [ ] Compare row counts between old and new staging models
6. [ ] Deploy to production during low-traffic window

---

## Rollback Plan

If issues occur, revert all changes by replacing `ADJUST` back to `ADJUST_S3` using:

```bash
find models/staging/adjust -name "*.sql" -exec sed -i '' "s/database='ADJUST'/database='ADJUST_S3'/g" {} \;
find models/staging/adjust -name "*.sql" -exec sed -i '' "s/FROM ADJUST\./FROM ADJUST_S3./g" {} \;
sed -i '' "s/database: ADJUST$/database: ADJUST_S3/g" models/staging/adjust/_adjust__sources.yml
```
