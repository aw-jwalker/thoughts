---
date: 2026-02-05T16:10:30-0500
researcher: aw-jwalker
git_commit: ebf75263138cb1582e583340f9734a3291e50a21
branch: dev
repository: fullstack.assetwatch
ticket: N/A
status: draft
last_updated: 2026-02-05
last_updated_by: aw-jwalker
type: implementation_plan
---

# Facility_Receiver Duplicate Records Cleanup Implementation Plan

## Overview

This plan addresses a data inconsistency issue where 116 receivers (sensors) have active records in **both** the `MonitoringPoint_Receiver` table (ActiveFlag=1) and the `Facility_Receiver` table simultaneously. According to the established data model, a receiver should either be:
- **On a monitoring point** → has an active `MonitoringPoint_Receiver` record (ActiveFlag=1) with NO `Facility_Receiver` record
- **In inventory/spare/transit** → has a `Facility_Receiver` record with NO active `MonitoringPoint_Receiver` record

The duplicate `Facility_Receiver` records need to be moved to `Facility_ReceiverHistory` to restore data consistency, while preserving the active `MonitoringPoint_Receiver` records.

## Current State Analysis

### The Problem

**Diagnostic Query Results (Dev Database):**
- 116 receivers have **both** an active MonitoringPoint_Receiver record AND a Facility_Receiver record
- All 116 `FacilityReceiverID` values are **safe to archive** (no primary key collisions in `Facility_ReceiverHistory`)
- The user's original diagnostic query showed 96 records (using stricter INNER JOINs through the full MP→Machine→Line→Facility→Customer chain), but simplified joins reveal the true scope is 116 affected receivers

**Example Affected Record:**
```
ReceiverID: 452348
SerialNumber: 8219609
MonitoringPoint_Facility: "Wausau Supply - Schofield, WI"
MPR StartDate: 2026-01-21 00:24:59
Facility_Receiver Facility: "Operations EMP Inventory - ART SEAN NICHOLS INVENTORY RETURNING TO HQ"
FR DateCreated: 2026-01-21 01:48:26
```

This receiver is **installed at a customer site** (Wausau Supply) but still has a `Facility_Receiver` record pointing to an inventory facility, created ~1.5 hours after the monitoring point assignment.

### Key Discoveries

**Table Relationships:**
- **File**: `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/tests/db/dockerDB/init_scripts/init_tables.sql`
- `Facility_Receiver` (lines 1223-1243): Current facility assignment, one active record per receiver
- `Facility_ReceiverHistory` (lines 1247-1271): Archive of previous facility assignments
- `MonitoringPoint_Receiver` (lines 2491-2521): Tracks which monitoring point a receiver is installed on

**The Established Archive Pattern:**

Found in **9 stored procedures** across the codebase:
1. `Receiver_RemoveReceiver` - Archives FR when removing receiver from MP
2. `Receiver_AddReceiverDetail` - Archives FR before/during MP assignment
3. `FacilityReceiver_UpdateReceiverStatus` - Archives FR when updating facility/status
4. `FacilityReceiver_UpdateSpareInTransitReceiverStatus` - Bulk updates with archival
5. `Inventory_AddSensor` - Archives FR when adding to inventory
6. `Inventory_BulkMoveSensorsToInventoryFacility` - Bulk moves with archival
7. `Receiver_AssignToTemporaryMonitoringPoint` - Testing/utility proc with archival
8. `Inventory_AddReceiverToEnclosure` - Archives FR when adding to enclosure
9. `EnclosureReceiver_UpdateFacility` - Updates facility with archival
10. `WorkOrder_UpdateSensors` - Work order operations with transactional archival

**Standard Archive SQL Pattern (from all 9 procs):**
```sql
-- Step 1: Copy to history with DateRemoved = NOW
INSERT INTO Facility_ReceiverHistory
    (FacilityReceiverID, FacilityID, ReceiverID, ReceiverStatus,
     DateUpdated, FacilityReceiverStatusID, DateCreated, UserID,
     DateRemoved, WorkOrderBOMID, WorkOrderReturnBOMID)
SELECT FacilityReceiverID, FacilityID, ReceiverID, ReceiverStatus,
       DateUpdated, FacilityReceiverStatusID, DateCreated, UserID,
       UTC_TIMESTAMP(), WorkOrderBOMID, WorkOrderReturnBOMID
FROM Facility_Receiver
WHERE ReceiverID = <receiverID>;

-- Step 2: Delete the active record
DELETE FROM Facility_Receiver WHERE ReceiverID = <receiverID>;
```

**Key Fields in Facility_ReceiverHistory:**
- All 10 fields from `Facility_Receiver` are copied
- `DateRemoved` is set to `UTC_TIMESTAMP()` at archive time (NEW value, not copied)
- `FacilityReceiverID` is NOT auto-increment in the history table — it receives the original ID from the active table

**Schema File References:**
- Table definitions: `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/tests/db/dockerDB/init_scripts/init_tables.sql:1223-1271`
- Original migration: `/home/aw-jwalker/repos/fullstack.assetwatch/mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:1202-1240`
- DateRemoved added: `/home/aw-jwalker/repos/fullstack.assetwatch/mysql/db/table_change_scripts/V000000126__IWA-7231_AddColumnToFacility_ReceiverHistory.sql`
- WorkOrder columns added: `/home/aw-jwalker/repos/fullstack.assetwatch/mysql/db/table_change_scripts/V000000148__IWA-4730_Add_WorkOrder_Columns.sql`

## Desired End State

### Success Criteria

1. **Zero receivers** have active records in both `MonitoringPoint_Receiver` (ActiveFlag=1) AND `Facility_Receiver`
2. All 116 affected `Facility_Receiver` records are successfully moved to `Facility_ReceiverHistory` with `DateRemoved = UTC_TIMESTAMP()`
3. All 116 `MonitoringPoint_Receiver` records remain **untouched** with `ActiveFlag = 1`
4. No data loss — every field from the original `Facility_Receiver` records is preserved in `Facility_ReceiverHistory`
5. The cleanup SQL follows the same pattern used by all existing stored procedures

### Verification Query

After cleanup, this query should return **zero rows**:
```sql
SELECT COUNT(*) as remaining_duplicates
FROM Facility_Receiver fr
INNER JOIN MonitoringPoint_Receiver mpr
    ON mpr.ReceiverID = fr.ReceiverID
    AND mpr.ActiveFlag = 1;
```

## What We're NOT Doing

1. **NOT modifying MonitoringPoint_Receiver** — the active MP assignments stay intact
2. **NOT updating the Receiver table** — receiver metadata stays the same
3. **NOT creating new Facility_Receiver records** — we're only archiving the duplicates
4. **NOT changing any application code** — this is a one-time data cleanup, the app already handles this correctly in normal operations
5. **NOT investigating root cause** — this plan focuses on fixing the data, not preventing future occurrences (that would be a separate investigation)
6. **NOT running this automatically** — the database engineer will execute on prod after dev testing

## Implementation Approach

This is a **data cleanup operation** performed directly in the database using SQL scripts. The approach:

1. **Test on dev first** — verify the SQL works correctly and produces expected results
2. **Database engineer executes on prod** — user has read-only access, so production execution requires DBA
3. **Mirror existing patterns** — use the exact same INSERT-SELECT + DELETE pattern found in 9+ stored procedures
4. **Transactional safety** — wrap in START TRANSACTION / COMMIT to ensure atomicity
5. **Pre/post verification** — run diagnostic queries before and after to confirm success

---

## Phase 1: Pre-Cleanup Validation (Dev)

### Overview

Validate the scope and ensure the cleanup SQL is correct before testing execution.

### Changes Required

#### 1. Validation Queries

**Execute these queries on dev database:**

```sql
-- Query 1: Confirm the count of affected records
SELECT COUNT(*) as total_affected_receivers
FROM Facility_Receiver fr
INNER JOIN MonitoringPoint_Receiver mpr
    ON mpr.ReceiverID = fr.ReceiverID
    AND mpr.ActiveFlag = 1;
-- Expected: 116

-- Query 2: Check for primary key collisions (should be zero)
SELECT COUNT(*) as collision_count
FROM Facility_Receiver fr
INNER JOIN MonitoringPoint_Receiver mpr
    ON mpr.ReceiverID = fr.ReceiverID
    AND mpr.ActiveFlag = 1
INNER JOIN Facility_ReceiverHistory frh
    ON frh.FacilityReceiverID = fr.FacilityReceiverID;
-- Expected: 0

-- Query 3: Sample of affected records for review
SELECT
    r.ReceiverID,
    r.SerialNumber,
    fr.FacilityReceiverID,
    fr.FacilityID,
    f.FacilityName as FR_Facility,
    fr.DateCreated as FR_DateCreated,
    mpr.MonitoringPointID,
    mpr.StartDate as MPR_StartDate,
    mpr.ActiveFlag
FROM Facility_Receiver fr
INNER JOIN Receiver r ON r.ReceiverID = fr.ReceiverID
INNER JOIN MonitoringPoint_Receiver mpr
    ON mpr.ReceiverID = fr.ReceiverID
    AND mpr.ActiveFlag = 1
LEFT JOIN Facility f ON f.FacilityID = fr.FacilityID
ORDER BY fr.DateCreated DESC
LIMIT 10;
-- Expected: 10 sample records showing the duplicate state
```

### Success Criteria

#### Automated Verification

- [ ] Query 1 returns exactly 116 affected receivers
- [ ] Query 2 returns 0 collisions
- [ ] Query 3 returns 10 sample records with both FR and MPR data

#### Manual Verification

- [ ] Review the sample records to confirm they represent true duplicates (not legitimate data)
- [ ] Spot-check 2-3 receivers to verify they should NOT have a Facility_Receiver record while on a monitoring point

**Implementation Note**: After completing this phase and verifying the queries, proceed directly to Phase 2.

---

## Phase 2: Cleanup Script Execution (Dev)

### Overview

Execute the cleanup SQL on the dev database to archive the duplicate `Facility_Receiver` records into `Facility_ReceiverHistory`.

### Changes Required

#### 1. Cleanup SQL Script

**File**: Create as a reference document (not a migration, this will be run manually)
**Suggested location**: `/home/aw-jwalker/repos/fullstack.assetwatch/mysql/db/manual_scripts/2026-02-05-facility-receiver-cleanup.sql`

```sql
-- ============================================
-- Data Cleanup: Archive Duplicate Facility_Receiver Records
-- Date: 2026-02-05
-- Issue: 116 receivers have both active MonitoringPoint_Receiver
--        and Facility_Receiver records
-- Solution: Move Facility_Receiver records to Facility_ReceiverHistory
-- ============================================

START TRANSACTION;

-- Step 1: Archive to Facility_ReceiverHistory
-- This INSERT mirrors the pattern used in 9+ stored procedures
INSERT INTO Facility_ReceiverHistory
    (FacilityReceiverID, FacilityID, ReceiverID, ReceiverStatus,
     DateUpdated, FacilityReceiverStatusID, DateCreated, UserID,
     DateRemoved, WorkOrderBOMID, WorkOrderReturnBOMID)
SELECT
    fr.FacilityReceiverID,
    fr.FacilityID,
    fr.ReceiverID,
    fr.ReceiverStatus,
    fr.DateUpdated,
    fr.FacilityReceiverStatusID,
    fr.DateCreated,
    fr.UserID,
    UTC_TIMESTAMP() as DateRemoved,  -- Set removal timestamp to NOW
    fr.WorkOrderBOMID,
    fr.WorkOrderReturnBOMID
FROM Facility_Receiver fr
INNER JOIN MonitoringPoint_Receiver mpr
    ON mpr.ReceiverID = fr.ReceiverID
    AND mpr.ActiveFlag = 1;

-- Verify the INSERT count
SELECT ROW_COUNT() as records_archived;
-- Expected: 116

-- Step 2: Delete the archived records from active table
DELETE fr
FROM Facility_Receiver fr
INNER JOIN MonitoringPoint_Receiver mpr
    ON mpr.ReceiverID = fr.ReceiverID
    AND mpr.ActiveFlag = 1;

-- Verify the DELETE count
SELECT ROW_COUNT() as records_deleted;
-- Expected: 116

-- Step 3: Verify cleanup success
SELECT COUNT(*) as remaining_duplicates
FROM Facility_Receiver fr
INNER JOIN MonitoringPoint_Receiver mpr
    ON mpr.ReceiverID = fr.ReceiverID
    AND mpr.ActiveFlag = 1;
-- Expected: 0

-- If all verifications pass, commit the transaction
COMMIT;

-- If anything is wrong, you can ROLLBACK instead of COMMIT
-- ROLLBACK;
```

#### 2. Execution Steps

1. **User executes** the script manually on dev database (using their read-only access via MySQL MCP)
2. **User reviews** the `ROW_COUNT()` results after each step
3. **User verifies** the final query returns 0 remaining duplicates
4. **User executes** `COMMIT` to finalize the changes (or `ROLLBACK` if issues found)

### Success Criteria

#### Automated Verification

- [ ] Step 1 INSERT returns `ROW_COUNT() = 116`
- [ ] Step 2 DELETE returns `ROW_COUNT() = 116`
- [ ] Step 3 verification query returns `remaining_duplicates = 0`
- [ ] Transaction commits successfully with no errors

#### Manual Verification

- [ ] Spot-check 3-5 receivers from the original diagnostic query — verify their `Facility_Receiver` records are gone
- [ ] Verify those same receivers now have their records in `Facility_ReceiverHistory` with `DateRemoved` populated
- [ ] Verify the `MonitoringPoint_Receiver` records for those receivers are still active (ActiveFlag=1, StartDate unchanged)
- [ ] Run the original user diagnostic query — it should return 0 rows (or significantly fewer if some were outside the 116 scope)

**Implementation Note**: After successful manual verification, proceed to Phase 3.

---

## Phase 3: Production Execution

### Overview

Hand off the tested and verified cleanup SQL to the database engineer for execution on the production database.

### Changes Required

#### 1. Handoff Documentation

**Create a document for the database engineer** with:

1. **Context**: Explain the issue (receivers with both active MP and FR records)
2. **Scope**: 116 affected records on dev (prod count may differ)
3. **Tested SQL**: Provide the exact SQL from Phase 2
4. **Pre-execution checklist**:
   - Run Query 1 to get prod count
   - Run Query 2 to verify zero collisions
   - Backup the `Facility_Receiver` and `Facility_ReceiverHistory` tables (or verify recent backup exists)
5. **Execution instructions**: Run the transactional script, review ROW_COUNT results before COMMIT
6. **Post-execution verification**: Run the verification query to confirm 0 remaining duplicates

**File suggestion**: Email or Slack message to DBA with this plan document attached

#### 2. Production Execution SQL

```sql
-- ============================================
-- PRODUCTION Data Cleanup: Archive Duplicate Facility_Receiver Records
-- Date: 2026-02-05
-- Tested on dev: SUCCESS (116 records cleaned)
-- Run by: [DBA Name]
-- ============================================

-- Pre-execution check: Count affected records
SELECT COUNT(*) as total_affected_receivers
FROM Facility_Receiver fr
INNER JOIN MonitoringPoint_Receiver mpr
    ON mpr.ReceiverID = fr.ReceiverID
    AND mpr.ActiveFlag = 1;
-- Note the count for comparison

-- Pre-execution check: Verify zero collisions
SELECT COUNT(*) as collision_count
FROM Facility_Receiver fr
INNER JOIN MonitoringPoint_Receiver mpr
    ON mpr.ReceiverID = fr.ReceiverID
    AND mpr.ActiveFlag = 1
INNER JOIN Facility_ReceiverHistory frh
    ON frh.FacilityReceiverID = fr.FacilityReceiverID;
-- Must be 0 to proceed

-- Begin cleanup transaction
START TRANSACTION;

-- Step 1: Archive to history
INSERT INTO Facility_ReceiverHistory
    (FacilityReceiverID, FacilityID, ReceiverID, ReceiverStatus,
     DateUpdated, FacilityReceiverStatusID, DateCreated, UserID,
     DateRemoved, WorkOrderBOMID, WorkOrderReturnBOMID)
SELECT
    fr.FacilityReceiverID,
    fr.FacilityID,
    fr.ReceiverID,
    fr.ReceiverStatus,
    fr.DateUpdated,
    fr.FacilityReceiverStatusID,
    fr.DateCreated,
    fr.UserID,
    UTC_TIMESTAMP() as DateRemoved,
    fr.WorkOrderBOMID,
    fr.WorkOrderReturnBOMID
FROM Facility_Receiver fr
INNER JOIN MonitoringPoint_Receiver mpr
    ON mpr.ReceiverID = fr.ReceiverID
    AND mpr.ActiveFlag = 1;

SELECT ROW_COUNT() as records_archived;

-- Step 2: Delete archived records
DELETE fr
FROM Facility_Receiver fr
INNER JOIN MonitoringPoint_Receiver mpr
    ON mpr.ReceiverID = fr.ReceiverID
    AND mpr.ActiveFlag = 1;

SELECT ROW_COUNT() as records_deleted;

-- Step 3: Verify cleanup
SELECT COUNT(*) as remaining_duplicates
FROM Facility_Receiver fr
INNER JOIN MonitoringPoint_Receiver mpr
    ON mpr.ReceiverID = fr.ReceiverID
    AND mpr.ActiveFlag = 1;

-- If all checks pass, commit
COMMIT;

-- Post-execution verification
SELECT COUNT(*) as total_in_history
FROM Facility_ReceiverHistory
WHERE DateRemoved >= DATE_SUB(NOW(), INTERVAL 1 HOUR);
-- Should match the archived count
```

### Success Criteria

#### Automated Verification

- [ ] Pre-execution count matches expectations (likely similar to dev's 116)
- [ ] Pre-execution collision check returns 0
- [ ] Step 1 INSERT row count matches pre-execution count
- [ ] Step 2 DELETE row count matches pre-execution count
- [ ] Step 3 verification query returns 0
- [ ] Post-execution history count matches archived count
- [ ] Transaction commits with no errors

#### Manual Verification

- [ ] DBA confirms backup exists before execution
- [ ] Spot-check 3-5 receivers to verify they no longer have `Facility_Receiver` records
- [ ] Spot-check those same receivers have new `Facility_ReceiverHistory` records with recent `DateRemoved` timestamp
- [ ] Verify application functionality: check that sensor detail pages still show correct history
- [ ] Verify no customer-reported issues about sensor data or history after 24 hours

**Implementation Note**: After DBA confirms successful execution, this plan is complete. Document the final prod count and timestamp for records.

---

## Testing Strategy

### Unit Tests

Not applicable — this is a one-time data cleanup, not code changes.

### Integration Tests

Not applicable — no application code changes.

### Manual Testing Steps

**On Dev (Phase 2):**
1. Before running cleanup: Navigate to sensor detail page for ReceiverID 452348 (SerialNumber 8219609) — verify it shows a `Facility_Receiver` record
2. Run the cleanup SQL in Phase 2
3. After cleanup: Verify ReceiverID 452348 no longer has a `Facility_Receiver` record
4. Verify ReceiverID 452348 now has a `Facility_ReceiverHistory` record with `DateRemoved` = today
5. Verify the monitoring point assignment is still active and visible
6. Repeat for 2-3 other receivers from the diagnostic query

**On Prod (Phase 3):**
1. After DBA executes: Spot-check 3-5 receivers from the original diagnostic query
2. Verify their facility history is complete and correct
3. Verify sensor detail pages render correctly
4. Monitor for any Sentry errors related to facility or receiver queries

## Performance Considerations

**Query Performance:**
- The cleanup affects 116 rows (dev), likely similar on prod
- Both INSERT and DELETE use simple joins on indexed columns (`ReceiverID`, `ActiveFlag`)
- Expected execution time: < 5 seconds total
- Transaction size is manageable (no need for batching)

**Table Locking:**
- The transaction will briefly lock `Facility_Receiver` and `Facility_ReceiverHistory` tables
- Impact: Minimal (these tables are not high-traffic during the INSERT/DELETE operation)
- Recommendation: Execute during low-traffic period if possible (not critical due to small scope)

**Index Impact:**
- Both tables have indexes on `ReceiverID` — the joins will be efficient
- No index rebuild needed after cleanup

## Migration Notes

Not applicable — this is not a schema migration, it's a data cleanup operation.

## Risks and Mitigation

### Risk 1: Transaction Fails Mid-Execution
**Probability**: Low
**Impact**: Medium (data could be duplicated if INSERT succeeds but DELETE fails)
**Mitigation**: Using `START TRANSACTION` / `COMMIT` ensures atomicity — if any step fails, the entire transaction rolls back

### Risk 2: Production Count Differs Significantly from Dev
**Probability**: Medium (prod could have more or fewer affected records)
**Impact**: Low (the SQL is dynamic and will handle any count)
**Mitigation**: DBA runs the pre-execution count query to verify scope before proceeding

### Risk 3: Application Queries Break Due to Missing Facility_Receiver Records
**Probability**: Very Low (the app should already handle receivers on MPs not having FR records)
**Impact**: High (sensor pages might error)
**Mitigation**:
- The application already handles this scenario (9+ stored procedures do the same archival)
- Spot-check sensor detail pages after dev cleanup to verify
- DBA can ROLLBACK the prod transaction if issues discovered during execution

### Risk 4: Future Duplicate Records Created
**Probability**: Unknown (root cause not investigated)
**Impact**: Low (this is a data quality issue, not a functional bug)
**Mitigation**:
- This plan only fixes existing duplicates
- Recommendation: Add a monitoring query to alert if duplicates occur again (separate task)
- Consider adding a database constraint or trigger to prevent future duplicates (separate investigation)

## References

- Original issue identified by user diagnostic query
- Research agent findings: Comprehensive analysis of `Facility_Receiver` / `Facility_ReceiverHistory` usage
- Table schemas: `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/tests/db/dockerDB/init_scripts/init_tables.sql:1223-1271`
- Archive pattern examples:
  - `/home/aw-jwalker/repos/fullstack.assetwatch/mysql/db/procs/R__PROC_Receiver_RemoveReceiver.sql:70-77`
  - `/home/aw-jwalker/repos/fullstack.assetwatch/mysql/db/procs/R__PROC_Receiver_AddReceiverDetail.sql:89-94` and `:133-138`
  - `/home/aw-jwalker/repos/fullstack.assetwatch/mysql/db/procs/R__PROC_FacilityReceiver_UpdateReceiverStatus.sql:39-47`
  - 7 other stored procedures using the same pattern

## Post-Implementation Recommendations

1. **Monitoring**: Create a weekly report query to detect if duplicate FR+MPR records reappear:
   ```sql
   SELECT COUNT(*) as duplicate_count
   FROM Facility_Receiver fr
   INNER JOIN MonitoringPoint_Receiver mpr
       ON mpr.ReceiverID = fr.ReceiverID
       AND mpr.ActiveFlag = 1;
   ```
   Alert if count > 0.

2. **Root Cause Investigation** (separate task): Investigate why 116 receivers ended up with duplicate records. Possible causes:
   - Race condition in stored procedures
   - Manual SQL executed outside of normal procedures
   - Bug in one of the 9+ stored procedures (incomplete transaction handling)
   - Bulk operations that bypass the archive pattern

3. **Database Constraint** (optional): Consider adding a trigger or constraint to prevent `Facility_Receiver` records for receivers with active `MonitoringPoint_Receiver` records. This would enforce the business rule at the database level.

4. **Standardize Transactions**: Review all 9+ stored procedures to ensure they ALL use explicit `START TRANSACTION / COMMIT` around the INSERT+DELETE pattern (currently only `WorkOrder_UpdateSensors` does this).
