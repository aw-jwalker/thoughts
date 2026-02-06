---
date: 2026-02-06T09:15:48-0500
researcher: aw-jwalker
git_commit: 92773b6a29887558668aa15116b08eb6c0d25ee8
branch: IWA-15083
repository: fullstack.assetwatch
topic: "File Deletion Investigation - Hotspot Photo Deletion Bug"
tags: [investigation, database, stored-procedures, files, cradlepoint, bug-fix]
status: in-progress
last_updated: 2026-02-06
last_updated_by: aw-jwalker
type: investigation
---

# Handoff: IWA-15083 File Deletion Investigation

## Task(s)

**Status: Investigation In Progress**

Investigating why 23 hotspot (CradlepointDevice) photos were incorrectly deleted on 2026-02-05 at 22:16:21.362. All files show:
- `FileStatusID` changed to 2 (deleted)
- `_version` NOT incremented (bug indicator)
- `_deleted` NOT set to 1 (bug indicator)
- `_lastChangedAt` updated to 2026-02-05 22:16:21.362

This indicates a stored procedure bypassed proper deletion handling.

### Affected Files (23 total)
FileIDs: 395501, 395507, 395543, 395544, 395555, 395572, 395573, 395904, 395905, 396059, 396060, 396078, 396080, 396091, 396092, 396105, 396106, 396115, 396116, 396126, 396127, 396718, 396720

### Affected Devices (11 hotspots)
CradlepointDeviceIDs: 12307, 11113, 13697, 13966, 14558, 12310, 10326, 12851, 13712, 11878, 9610

All 11 hotspots currently at FacilityID 5196 (Little Rock, AR), assigned 2026-01-29 15:29:07.

## Critical References

None - this is a bug investigation and remediation task.

## Recent changes

No code changes made yet - investigation phase only.

## Learnings

### Bug Pattern Identified

Found **3 stored procedures** that incorrectly update Files table without incrementing `_version` and `_deleted`:

1. **`Cradlepoint_RemoveCradlepoint`** (`mysql/db/procs/R__PROC_Cradlepoint_RemoveCradlepoint.sql:59`)
   ```sql
   UPDATE Files SET FileStatusID = 2 WHERE CradlePointDeviceID = localCradlepointDeviceID;
   ```
   Missing: `_version=_version+1, _deleted=1`

2. **`EnclosureCradlepointDevice_UpdateFacility`** (`mysql/db/procs/R__PROC_EnclosureCradlepointDevice_UpdateFacility.sql:52`)
   ```sql
   UPDATE Files SET FileStatusID = 2 WHERE CradlePointDeviceID = localNextCradlepointDeviceID AND DidUpload = 1 AND FileStatusID = 1;
   ```
   Comment states: "Update old photos in Files table to inactive. This is to prevent the hotspot picture from one facility from showing up as a picture in a new facility."
   Missing: `_version=_version+1, _deleted=1`

3. **`EnclosureTransponder_UpdateFacility`** (`mysql/db/procs/R__PROC_EnclosureTransponder_UpdateFacility.sql:42`)
   ```sql
   UPDATE Files SET FileStatusID = 2 WHERE TransponderID = localNextTransponderID AND DidUpload = 1 AND FileStatusID = 1;
   ```
   Comment states: "Update old photos in Files table to inactive. This is to prevent the hub picture from one facility from showing up as a picture in a new facility."
   Missing: `_version=_version+1, _deleted=1`

**Correct pattern** shown in `Files_Remove` (`mysql/db/procs/R__PROC_Files_Remove.sql:11`):
```sql
UPDATE Files SET FileStatusID = 2, _version=_version+1, _deleted=1 WHERE ExternalFileName = inExternalFileName;
```

### Timeline Analysis

- **2026-01-29 15:29:07**: All 11 hotspots moved FROM FacilityID 4478 (Installations/Expansions) TO FacilityID 5196 (Little Rock, AR)
- **2026-02-05 22:16:21.362**: Files deleted (7 days later!)
- **Anomaly**: CradlepointDeviceID 13966 has `DateUpdated: 2026-02-05 20:07:36` on current facility assignment - about 2 hours before file deletion

This suggests a **second facility operation** or bulk update occurred on Feb 5th that triggered the file deletion, even though the hotspots didn't actually change facilities.

### Database Schema Understanding

Relationship chain:
- `Facility` ↔ `Facility_CradlepointDevice` (junction) ↔ `CradlepointDevice` ↔ `Files`
- Files can link directly via `Files.CradlePointDeviceID`
- Files can also link indirectly via `Files.TransponderID` for combo enclosures (PartID 42, 49, 53)

Files table fields:
- `FileStatusID`: 1=active, 2=deleted
- `_version`: Should increment on every update
- `_deleted`: Should be set to 1 when soft-deleted
- `_lastChangedAt`: Auto-updates via `ON UPDATE CURRENT_TIMESTAMP(3)`

## Artifacts

### Query Development

Created comprehensive queries for investigation:

1. **Facility history query** - shows complete facility assignment history for affected hotspots
2. **AuditLog queries** (corrected field names) - ready to run to identify which procedure was called:
   - `AuditLog` fields: `AuditLogID`, `TableName`, `PrimaryKeyID`, `ColumnName`, `PreviousValue`, `NewValue`, `DateCreated`, `UserID`
   - Query templates provided for CradlepointDevice, Facility_CradlepointDevice, and Files tables

### Stored Procedure Analysis

- `R__PROC_Cradlepoint_RemoveCradlepoint.sql` - removes cradlepoint from facility
- `R__PROC_EnclosureCradlepointDevice_UpdateFacility.sql` - moves cradlepoint between facilities (MOST LIKELY CULPRIT)
- `R__PROC_EnclosureTransponder_UpdateFacility.sql` - moves transponder between facilities
- `R__PROC_Files_Remove.sql` - correct implementation reference

## Action Items & Next Steps

### 1. Confirm Root Cause (HIGH PRIORITY)

Run AuditLog queries on production to identify:
- Which stored procedure was called on 2026-02-05 ~22:16:21
- What fields were changed on CradlepointDevice or Facility_CradlepointDevice records
- Which user initiated the operation

**Key query to run first** (corrected field names):
```sql
SELECT
    al.DateCreated,
    al.TableName,
    al.PrimaryKeyID,
    al.ColumnName,
    al.PreviousValue,
    al.NewValue,
    CONCAT(u.FirstName, ' ', u.LastName) AS UserName
FROM AuditLog al
LEFT JOIN Users u ON al.UserID = u.UserID
WHERE (
    (al.TableName = 'CradlepointDevice' AND al.PrimaryKeyID IN (12307, 11113, 13697, 13966, 14558, 12310, 10326, 12851, 13712, 11878, 9610))
    OR (al.TableName = 'Facility_CradlepointDevice')
)
AND al.DateCreated BETWEEN '2026-02-05 22:00:00' AND '2026-02-05 23:00:00'
ORDER BY al.DateCreated DESC;
```

### 2. Restore Affected Files

Once root cause is confirmed, restore the 23 files:
```sql
UPDATE Files
SET
    FileStatusID = 1,
    _version = _version + 1,
    _deleted = 0
WHERE FileID IN (395501, 395507, 395543, 395544, 395555, 395572, 395573, 395904, 395905, 396059, 396060, 396078, 396080, 396091, 396092, 396105, 396106, 396115, 396116, 396126, 396127, 396718, 396720);
```

### 3. Fix Buggy Stored Procedures

Update all 3 procedures to properly increment `_version` and set `_deleted=1`:

**Fix pattern for each:**
```sql
-- OLD (broken):
UPDATE Files SET FileStatusID = 2 WHERE CradlePointDeviceID = ...;

-- NEW (correct):
UPDATE Files SET FileStatusID = 2, _version=_version+1, _deleted=1 WHERE CradlePointDeviceID = ...;
```

Apply to:
- `R__PROC_Cradlepoint_RemoveCradlepoint.sql:59`
- `R__PROC_EnclosureCradlepointDevice_UpdateFacility.sql:52`
- `R__PROC_EnclosureTransponder_UpdateFacility.sql:42`

### 4. Test Changes

- Create test cases for facility transfers
- Verify `_version` and `_deleted` are properly incremented
- Ensure datastore sync works correctly

### 5. Search for Similar Bugs

Check for other stored procedures that might have the same issue:
```bash
grep -r "UPDATE.*Files.*SET.*FileStatusID.*2" mysql/db/procs/
```

Verify each result properly increments `_version` and `_deleted`.

## Other Notes

### Why the Design Works This Way

The procedures intentionally delete old photos when hotspots/hubs move between facilities to prevent photos from one facility appearing at another facility. This is by design (see comments in procedures).

The bug is NOT the deletion logic itself, but the failure to properly maintain the `_version` and `_deleted` fields, which breaks the AWS DataStore sync mechanism.

### Production Data Access

- Queries must be run on production database (files don't exist in local dev DB after last refresh)
- User confirmed they will run queries manually and provide results
- All investigation queries have been provided with corrected field names

### Related Files

- `lambdas/tests/db/dockerDB/init_scripts/init_tables.sql` - schema reference
- `mysql/db/procs/R__PROC_Cradlepoint_GetFiles.sql` - reference for how to query files by cradlepoint

### Query for Facility Photos (Future Reference)

Created a helper query to get all hotspot photos at a facility:
```sql
SELECT f.*, cpd.CradlepointDeviceName, CONCAT(u.FirstName, ' ', u.LastName) AS UserFullName
FROM Facility_CradlepointDevice fcp
INNER JOIN CradlepointDevice cpd ON fcp.CradlePointDeviceID = cpd.CradlepointDeviceID
INNER JOIN Files f ON f.CradlePointDeviceID = cpd.CradlepointDeviceID
LEFT JOIN Users u ON f.UserID = u.UserID
WHERE fcp.FacilityID = ? AND f.FileStatusID <> 2 AND f.DidUpload = 1
ORDER BY f.DateCreated DESC;
```
