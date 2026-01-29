---
date: 2026-01-09T10:40:39-05:00
researcher: Claude
git_commit: f8b42b0de4ae18e489f939c4f139c4b25efe61e7
branch: IWA-14514
repository: fullstack.assetwatch
topic: "Monitoring Point Deletion and Restoration Process"
tags: [research, codebase, monitoring-point, soft-delete, restoration, stored-procedures]
status: complete
last_updated: 2026-01-09
last_updated_by: Claude
---

# Research: Monitoring Point Deletion and Restoration Process

**Date**: 2026-01-09T10:40:39-05:00
**Researcher**: Claude
**Git Commit**: f8b42b0de4ae18e489f939c4f139c4b25efe61e7
**Branch**: IWA-14514
**Repository**: fullstack.assetwatch

## Research Question

Understand the process of deleting monitoring points so that we can understand how to reverse the deletion. Then check if we already have any stored procedures for use by engineers to restore deleted monitoring points.

## Summary

The codebase uses a **soft-delete mechanism** for monitoring points, setting `ActiveFlag=0`, `_deleted=1`, and `EndDate=timestamp` rather than performing hard deletes. This preserves historical data while marking records as inactive.

**Key Finding:** There is **no dedicated restore stored procedure** for engineers. However, restoration functionality exists through:
1. A frontend UI button (`RestoreInactiveMPButton`) for restoring MPs within the application
2. The `MonitoringPoint_AddMonitoringPointFromAW` procedure which implicitly restores MPs when called with an existing `ExternalMonitoringPointID`

**For direct database restoration by engineers**, manual SQL UPDATE statements are required to reverse the soft-delete fields.

---

## Detailed Findings

### 1. Deletion Process Overview

When monitoring points are deleted, three main tables are affected:

| Table | Changes Applied |
|-------|-----------------|
| `MonitoringPoint` | `ActiveFlag=0`, `EndDate=timestamp`, `_deleted=1`, `_version+1` |
| `MonitoringPoint_Receiver` | `ActiveFlag=0`, `EndDate=timestamp`, `_deleted=1`, `RemovedByUserID` set |
| `ReceiverSchedule` | `ReceiverScheduleStatusID=2` (replaced) |

### 2. Primary Deletion Stored Procedure

#### `MonitoringPoint_RemoveMonitoringPoint`

**File:** `mysql/db/procs/R__PROC_MonitoringPoint_RemoveMonitoringPoint.sql`

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `inExternalMonitoringPointIDList` | TEXT | JSON array of ExternalMonitoringPointIDs |
| `inCognitoID` | VARCHAR(200) | User performing the action |

**Operations (in order):**

1. **Resolve UserID** (lines 12-15): Looks up UserID from CognitoID
2. **Create temp table** (lines 20-31): Parses JSON array into temp table for efficient joins
3. **Deactivate receiver associations** (lines 34-43):
   ```sql
   UPDATE MonitoringPoint_Receiver mpr
   SET mpr.ActiveFlag = 0,
       mpr.EndDate = UTC_TIMESTAMP(),
       mpr.RemovedByUserID = localUserID,
       mpr._version = mpr._version + 1,
       mpr._deleted = 1
   WHERE mpr.ActiveFlag = 1;
   ```
4. **Soft delete monitoring points** (lines 46-52):
   ```sql
   UPDATE MonitoringPoint mp
   SET mp.ActiveFlag = 0,
       mp.EndDate = UTC_TIMESTAMP(),
       mp._version = mp._version + 1,
       mp._deleted = 1;
   ```
5. **Mark schedules as replaced** (lines 55-60):
   ```sql
   UPDATE ReceiverSchedule rs SET rs.ReceiverScheduleStatusID = 2;
   ```
6. **Create audit log entries** (lines 63-88): Records changes to AuditLog table

### 3. Other Deletion-Related Procedures

| Procedure | File | Purpose |
|-----------|------|---------|
| `MonitoringPoint_RemoveOilMonitoringPointWithData` | `R__PROC_MonitoringPoint_RemoveOilMonitoringPointWithData.sql` | Removes oil MP (ProductID 12/17) and detaches related data |
| `MonitoringPoint_RemoveReceiver` | `R__PROC_MonitoringPoint_RemoveReceiver.sql` | Removes single sensor; auto-deletes MP if no sensors remain |
| `MonitoringPoint_Receiver_Remove` | `R__PROC_MonitoringPoint_Receiver_Remove.sql` | Legacy procedure for Vero sync |
| `Receiver_RemoveReceiver` | `R__PROC_Receiver_RemoveReceiver.sql` | Removes receivers and updates MP associations |

### 4. API Flow for Deletion

```
Frontend (MonitoringPointService.ts:161-173)
    │  removeMonitoringPoint(extmpid: string)
    │  POST /monitoringpoint/update { meth: "removeMonitoringPoint", extmpid: "uuid1,uuid2" }
    ▼
API Gateway (api-vero-monitoringpoint.yaml:86-131)
    │  aws_proxy integration
    ▼
Lambda (lf-vero-prod-monitoringpoint/main.py:1401-1417)
    │  Converts CSV → JSON array
    │  Calls: MonitoringPoint_RemoveMonitoringPoint(json_array, cognito_id)
    ▼
Stored Procedure executes soft-delete cascade
```

---

## Existing Restoration Mechanisms

### 1. Frontend UI Restoration (Application-Level)

**Component:** `RestoreInactiveMPButton`
**File:** `frontend/src/components/UpdateMonitoringPointModal/RestoreInactiveMPButton.tsx`

This provides a UI button for users to restore inactive MPs:
- Sets `restoreMP: true` flag on the AssetMp object
- Sets `activeFlag: 1`
- Sets `mpRemoveFlag: 0`
- Clears sensor assignments

### 2. Implicit Restoration via Add Procedures

The "Add" procedures contain restoration logic that triggers when an MP with a matching `ExternalMonitoringPointID` already exists:

#### `MonitoringPoint_AddMonitoringPointFromAW` (lines 152-172)

**File:** `mysql/db/procs/R__PROC_MonitoringPoint_AddMonitoringPointFromAW.sql`

```sql
UPDATE MonitoringPoint
SET
    ActiveFlag=1,          -- RESTORES the MP
    EndDate=NULL,          -- Clears deletion date
    MonitoringPointName=inMonitoringPointName,
    -- ... other fields
WHERE ExternalMonitoringPointID = inExternalMonitoringPointID;
```

#### Similar procedures:
- `MonitoringPoint_AddMonitoringPoint` (line 40)
- `MonitoringPoint_AddMonitoringPointFromMobile` (line 77)

### 3. What Does NOT Exist

**No dedicated engineer restore procedures exist:**
- No `MonitoringPoint_Restore` procedure
- No `MonitoringPoint_Undelete` procedure
- No `MonitoringPoint_Reactivate` procedure
- No standalone restore scripts
- No procedure that explicitly sets `_deleted = 0`

---

## Database Schema: Soft-Delete Fields

### MonitoringPoint Table

**File:** `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql` (lines 2223-2275)

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `ActiveFlag` | `bit(1)` | `b'1'` | Primary soft-delete flag (0=deleted) |
| `EndDate` | `datetime` | `NULL` | Timestamp when deactivated |
| `_deleted` | `int` | `0` | Mobile sync deletion flag |
| `_version` | `int unsigned` | `1` | Optimistic locking version |
| `RemoveFlag` | `bit(1)` | `NULL` | Additional removal tracking |
| `RemoveDate` | `datetime` | `NULL` | Date removal was requested |

### MonitoringPoint_Receiver Table

**File:** `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql` (lines 2459-2479)

| Column | Type | Purpose |
|--------|------|---------|
| `ActiveFlag` | `bit(1)` | Active state (0=removed) |
| `EndDate` | `datetime` | When sensor was removed |
| `_deleted` | `int` | Mobile sync deletion flag |
| `_version` | `int unsigned` | Optimistic locking version |
| `RemovedByUserID` | `int` | User who removed sensor |
| `ReceiverRemovalTypeID` | `int` | FK to removal reason |

### ReceiverScheduleStatus Values

| ID | Status | Description |
|----|--------|-------------|
| 1 | Active | Currently active schedule |
| 2 | Replaced | Superseded/removed schedule |

---

## Manual Restoration SQL (For Engineers)

To manually restore deleted monitoring points, execute these statements:

```sql
-- 1. Restore the MonitoringPoint record
UPDATE MonitoringPoint
SET
    ActiveFlag = 1,
    EndDate = NULL,
    _deleted = 0,
    _version = _version + 1
WHERE MonitoringPointID = <id>
   OR ExternalMonitoringPointID = '<ext_id>';

-- 2. Restore MonitoringPoint_Receiver associations (if applicable)
UPDATE MonitoringPoint_Receiver
SET
    ActiveFlag = 1,
    EndDate = NULL,
    _deleted = 0,
    _version = _version + 1,
    RemovedByUserID = NULL
WHERE MonitoringPointID = <id>
  AND <identify correct historical record>;

-- 3. Restore ReceiverSchedule status (if applicable)
UPDATE ReceiverSchedule
SET ReceiverScheduleStatusID = 1
WHERE ReceiverID IN (
    SELECT ReceiverID
    FROM MonitoringPoint_Receiver
    WHERE MonitoringPointID = <id>
)
AND <identify correct schedule>;
```

**Important Considerations:**
- The `_deleted` flag is NOT reset by the existing UI restoration flow
- Historical `MonitoringPoint_Receiver` records may exist; identify the correct one
- Multiple `ReceiverSchedule` records may exist for a receiver; identify the correct one
- Create AuditLog entries for compliance tracking

---

## Code References

### Deletion Procedures
- `mysql/db/procs/R__PROC_MonitoringPoint_RemoveMonitoringPoint.sql` - Primary deletion procedure
- `mysql/db/procs/R__PROC_MonitoringPoint_RemoveOilMonitoringPointWithData.sql` - Oil MP deletion
- `mysql/db/procs/R__PROC_MonitoringPoint_RemoveReceiver.sql` - Single sensor removal
- `mysql/db/procs/R__PROC_Receiver_RemoveReceiver.sql` - Bulk receiver removal

### Add/Restore Procedures
- `mysql/db/procs/R__PROC_MonitoringPoint_AddMonitoringPointFromAW.sql:152-172` - Implicit restore logic
- `mysql/db/procs/R__PROC_MonitoringPoint_AddMonitoringPoint.sql:40` - Implicit restore
- `mysql/db/procs/R__PROC_MonitoringPoint_AddMonitoringPointFromMobile.sql:77` - Implicit restore

### API Layer
- `lambdas/lf-vero-prod-monitoringpoint/main.py:1401-1417` - removeMonitoringPoint handler
- `frontend/src/shared/api/MonitoringPointService.ts:161-173` - Frontend service

### Frontend Components
- `frontend/src/components/UpdateMonitoringPointModal/RestoreInactiveMPButton.tsx` - Restore button UI

### Schema
- `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:2223-2275` - MonitoringPoint table
- `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:2459-2479` - MonitoringPoint_Receiver table
- `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:3164-3178` - ReceiverSchedule table

---

## Architecture Documentation

### Soft-Delete Pattern

The codebase consistently uses a multi-layered soft-delete approach:

1. **ActiveFlag**: Primary business-logic flag (1=active, 0=inactive)
2. **EndDate**: Temporal marker for when record was deactivated
3. **_deleted**: Mobile/DataStore sync flag (0=exists, 1=deleted for sync)
4. **_version**: Optimistic locking for concurrent updates

### Cascade Pattern

Monitoring point deletion cascades through related entities:
```
MonitoringPoint (soft-delete)
    ├── MonitoringPoint_Receiver (soft-delete all active associations)
    │       └── ReceiverSchedule (mark as replaced, StatusID=2)
    └── AuditLog (insert change records)
```

---

## Historical Context (from thoughts/)

No existing documentation found in thoughts/ directory specifically about monitoring point deletion or restoration. The soft-delete pattern is documented in:
- `thoughts/shared/research/2025-01-25-hub-hotspot-facility-transfer-flows.md` - Documents similar soft-delete patterns for facility assignments

---

## Open Questions

1. **Should a dedicated restore procedure be created?** Currently engineers must use raw SQL.
2. **Should `_deleted` be reset during restoration?** The UI restoration flow does not reset this flag.
3. **How should historical MPR records be handled?** Multiple records may exist for the same MP-Receiver relationship.
4. **Should AuditLog entries be created for restorations?** Current implicit restore via Add procedures does not create audit entries.
