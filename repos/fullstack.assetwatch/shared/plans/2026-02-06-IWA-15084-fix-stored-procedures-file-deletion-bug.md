---
date: 2026-02-06T13:47:27-0500
researcher: aw-jwalker
git_commit: aef6609646df1ec10108205f749be14f7d84fce3
branch: dev
repository: fullstack.assetwatch
ticket: IWA-15084
status: draft
last_updated: 2026-02-06
last_updated_by: aw-jwalker
type: implementation_plan
---

# Fix Stored Procedures - File Deletion Bug (IWA-15084)

## Overview

Fix a critical bug in 10 stored procedures where files are deleted (FileStatusID set to 2) without updating AWS DataStore sync fields (`_version`, `_deleted`), breaking mobile app synchronization.

**Scope**: SQL fixes only. Sentry instrumentation is handled in separate tickets:
- **IWA-15095**: Python Sentry instrumentation
- **IWA-15096**: JS Sentry utilities + salesforce-work-orders instrumentation

## Current State Analysis

### Bug Pattern

**Root Cause**: 10 stored procedures delete files by setting `FileStatusID = 2` but fail to update:
- `_version` (should increment: `_version = _version + 1`)
- `_deleted` (should be set: `_deleted = 1`)

This breaks AWS DataStore synchronization, causing deleted files to remain visible in the mobile app.

**Incident** (from IWA-15083 investigation):
- **2026-01-29**: 11 hotspots moved to FacilityID 5196
- **2026-02-05 22:16:21 UTC**: 23 photos incorrectly deleted
- **2026-02-06**: Photos manually restored ✓

### Affected Procedures (All Actively Used)

| Procedure | Lambda | Line(s) | Instances |
|-----------|--------|---------|-----------|
| `Cradlepoint_RemoveCradlepoint` | cradlepoint | 59 | 1 |
| `Cradlepoint_AddCradlepoint` | cradlepoint | 131 | 1 |
| `Cradlepoint_AddBulkCradlepointWithFundingProject` | cradlepoint | 96 | 1 |
| `Transponder_RemoveHubAndChangeFacility` | hub | 52 | 1 |
| `Transponder_AddTransponder_Notes` | hub | 139, 181 | 2 |
| `EnclosureCradlepointDevice_UpdateFacility` | hub, salesforce-wo, inventory | 52 | 1 |
| `EnclosureTransponder_UpdateFacility` | cradlepoint, salesforce-wo, inventory | 42 | 1 |
| `WorkOrder_LinkHardwareToRbom` | salesforce-wo | 73, 111, 160, 186 | 4 |
| `WorkOrder_UpdateCradlepoints` | salesforce-wo | 64 | 1 |
| `WorkOrder_UpdateTransponders` | salesforce-wo | 57 | 1 |

**Total**: 10 procedures, **14 buggy UPDATE statements**

### Correct Implementations (Reference)

These already properly update all fields:
- `Files_Remove` (R__PROC_Files_Remove.sql:11) ✓
- `MonitoringPoint_Reassign` (R__PROC_MonitoringPoint_Reassign.sql:41) ✓

**Correct pattern:**
```sql
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE <condition>;
```

## Desired End State

All 10 stored procedures properly update `_version` and `_deleted` when setting `FileStatusID = 2`.

### How to Verify

**Automated Verification:**
- [ ] Run verification command - should return ZERO buggy UPDATEs:
  ```bash
  grep -n "UPDATE Files SET FileStatusID = 2" mysql/db/procs/R__PROC_*.sql | \
    grep -v "_version" | grep -v "_deleted"
  ```
- [ ] Flyway migration deploys successfully

**Manual Verification:**
- [ ] Review each changed file for correct syntax
- [ ] Trigger test hotspot removal in dev/qa → Query Files table → Verify `_version` incremented and `_deleted = 1`
- [ ] Trigger test hub removal → Verify same
- [ ] Verify mobile app receives DataStore sync updates

## What We're NOT Doing

1. **NOT adding Sentry instrumentation** - Separate ticket (IWA-15095)
2. **NOT changing deletion logic** - Only fixing missing fields
3. **NOT removing any procedures** - All are actively used
4. **NOT restoring files** - Already done manually

## Implementation Approach

Simple find-and-replace pattern applied to 14 UPDATE statements across 10 stored procedure files.

**Pattern:**
```sql
-- FIND:
UPDATE Files SET FileStatusID = 2 WHERE <condition>;

-- REPLACE WITH:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE <condition>;
```

---

## Changes Required

### 1. `Cradlepoint_RemoveCradlepoint`

**File**: `mysql/db/procs/R__PROC_Cradlepoint_RemoveCradlepoint.sql`
**Line**: 59

```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE CradlePointDeviceID = localCradlepointDeviceID;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE CradlePointDeviceID = localCradlepointDeviceID;
```

---

### 2. `Cradlepoint_AddCradlepoint`

**File**: `mysql/db/procs/R__PROC_Cradlepoint_AddCradlepoint.sql`
**Line**: 131

```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE CradlePointDeviceID = localCradlepointDeviceID;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE CradlePointDeviceID = localCradlepointDeviceID;
```

---

### 3. `Cradlepoint_AddBulkCradlepointWithFundingProject`

**File**: `mysql/db/procs/R__PROC_Cradlepoint_AddBulkCradlepointWithFundingProject.sql`
**Line**: 96

```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE CradlePointDeviceID = localCradlepointDeviceID;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE CradlePointDeviceID = localCradlepointDeviceID;
```

---

### 4. `Transponder_RemoveHubAndChangeFacility`

**File**: `mysql/db/procs/R__PROC_Transponder_RemoveHubAndChangeFacility.sql`
**Line**: 52

```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE TransponderID = inTransponderID;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE TransponderID = inTransponderID;
```

---

### 5. `Transponder_AddTransponder_Notes` (2 instances)

**File**: `mysql/db/procs/R__PROC_Transponder_AddTransponder_Notes.sql`

**Line 139:**
```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE TransponderID = localTxID AND DidUpload = 1 AND FileStatusID = 1;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE TransponderID = localTxID AND DidUpload = 1 AND FileStatusID = 1;
```

**Line 181:**
```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE TransponderID = localTxID;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE TransponderID = localTxID;
```

---

### 6. `EnclosureCradlepointDevice_UpdateFacility`

**File**: `mysql/db/procs/R__PROC_EnclosureCradlepointDevice_UpdateFacility.sql`
**Line**: 52

```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE CradlePointDeviceID = localNextCradlepointDeviceID AND DidUpload = 1 AND FileStatusID = 1;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE CradlePointDeviceID = localNextCradlepointDeviceID AND DidUpload = 1 AND FileStatusID = 1;
```

---

### 7. `EnclosureTransponder_UpdateFacility`

**File**: `mysql/db/procs/R__PROC_EnclosureTransponder_UpdateFacility.sql`
**Line**: 42

```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE TransponderID = localNextTransponderID AND DidUpload = 1 AND FileStatusID = 1;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE TransponderID = localNextTransponderID AND DidUpload = 1 AND FileStatusID = 1;
```

---

### 8. `WorkOrder_LinkHardwareToRbom` (4 instances)

**File**: `mysql/db/procs/R__PROC_WorkOrder_LinkHardwareToRbom.sql`

**Line 73-77 (Hub photos):**
```sql
-- OLD:
UPDATE Files
SET FileStatusID = 2
WHERE TransponderID = inHardwareID
AND DidUpload = 1
AND FileStatusID = 1;

-- NEW:
UPDATE Files
SET FileStatusID = 2, _version = _version + 1, _deleted = 1
WHERE TransponderID = inHardwareID
AND DidUpload = 1
AND FileStatusID = 1;
```

**Line 111-115 (Hotspot photos):**
```sql
-- OLD:
UPDATE Files
SET FileStatusID = 2
WHERE CradlepointDeviceID = inHardwareID
AND DidUpload = 1
AND FileStatusID = 1;

-- NEW:
UPDATE Files
SET FileStatusID = 2, _version = _version + 1, _deleted = 1
WHERE CradlepointDeviceID = inHardwareID
AND DidUpload = 1
AND FileStatusID = 1;
```

**Line 160-164 (Enclosed hub photos):**
```sql
-- OLD:
UPDATE Files
SET FileStatusID = 2
WHERE TransponderID = localEnclosedTransponderID
AND DidUpload = 1
AND FileStatusID = 1;

-- NEW:
UPDATE Files
SET FileStatusID = 2, _version = _version + 1, _deleted = 1
WHERE TransponderID = localEnclosedTransponderID
AND DidUpload = 1
AND FileStatusID = 1;
```

**Line 186-190 (Enclosed hotspot photos):**
```sql
-- OLD:
UPDATE Files
SET FileStatusID = 2
WHERE CradlepointDeviceID = localEnclosedCradlepointDeviceID
AND DidUpload = 1
AND FileStatusID = 1;

-- NEW:
UPDATE Files
SET FileStatusID = 2, _version = _version + 1, _deleted = 1
WHERE CradlepointDeviceID = localEnclosedCradlepointDeviceID
AND DidUpload = 1
AND FileStatusID = 1;
```

---

### 9. `WorkOrder_UpdateCradlepoints`

**File**: `mysql/db/procs/R__PROC_WorkOrder_UpdateCradlepoints.sql`
**Line**: 64-68

```sql
-- OLD:
UPDATE Files
SET FileStatusID = 2
WHERE CradlepointDeviceID = inHardwareID
AND DidUpload = 1
AND FileStatusID = 1;

-- NEW:
UPDATE Files
SET FileStatusID = 2, _version = _version + 1, _deleted = 1
WHERE CradlepointDeviceID = inHardwareID
AND DidUpload = 1
AND FileStatusID = 1;
```

---

### 10. `WorkOrder_UpdateTransponders`

**File**: `mysql/db/procs/R__PROC_WorkOrder_UpdateTransponders.sql`
**Line**: 57-61

```sql
-- OLD:
UPDATE Files
SET FileStatusID = 2
WHERE TransponderID = inHardwareID
AND DidUpload = 1
AND FileStatusID = 1;

-- NEW:
UPDATE Files
SET FileStatusID = 2, _version = _version + 1, _deleted = 1
WHERE TransponderID = inHardwareID
AND DidUpload = 1
AND FileStatusID = 1;
```

---

## Success Criteria

### Automated Verification:

- [ ] All 14 UPDATE statements include `_version` and `_deleted` - verify with:
  ```bash
  grep -n "UPDATE Files SET FileStatusID = 2" mysql/db/procs/R__PROC_*.sql | \
    grep -v "_version" | grep -v "_deleted"
  ```
  Expected: Zero results (except Files_Remove and MonitoringPoint_Reassign which are already correct)

- [ ] Flyway migration passes: `make -C mysql migrate`

### Manual Verification:

- [ ] Code review: Verify all 10 files changed correctly
- [ ] Dev testing: Remove test hotspot → Query Files → Verify `_version` incremented, `_deleted = 1`
- [ ] Dev testing: Remove test hub → Verify same
- [ ] QA testing: Repeat above tests
- [ ] Prod deployment: Monitor for errors
- [ ] Prod verification: Test operation → Query Files → Verify fields correct
- [ ] Mobile app: Verify DataStore sync works (deleted files disappear from mobile)

---

## Testing Strategy

### Manual Test Cases

**Test 1: Hotspot Removal**
```sql
-- Before: Note current _version
SELECT FileID, FileStatusID, _version, _deleted FROM Files WHERE CradlePointDeviceID = <test_id>;

-- Trigger: Remove hotspot via UI

-- After: Verify updates
SELECT FileID, FileStatusID, _version, _deleted FROM Files WHERE CradlePointDeviceID = <test_id>;
-- Expected: FileStatusID=2, _version incremented by 1, _deleted=1
```

**Test 2: Hub Removal**
```sql
-- Before:
SELECT FileID, FileStatusID, _version, _deleted FROM Files WHERE TransponderID = <test_id>;

-- Trigger: Remove hub via UI

-- After:
SELECT FileID, FileStatusID, _version, _deleted FROM Files WHERE TransponderID = <test_id>;
-- Expected: FileStatusID=2, _version incremented by 1, _deleted=1
```

**Test 3: Work Order Hardware Link**
```sql
-- Trigger: Link hardware to R-BOM via work order workflow
-- Verify files deleted with correct fields
```

### Integration Testing

Recommended (not blocking):
- Backend test that calls each procedure
- Verifies _version and _deleted are set
- File: `lambdas/tests/test_file_deletion_procedures.py` (new)

---

## Performance Considerations

**Impact**: Negligible
- Adding 2 fields to UPDATE has no measurable performance impact
- Same transaction, same row lock, no additional I/O
- Backwards compatible (no schema changes)

---

## Migration Notes

### Deployment

Flyway migration runs automatically on deploy:
1. Procedures updated in place
2. No data migration needed
3. No rollback concerns (backwards compatible)

### Rollback

If needed:
1. Create Flyway migration reverting changes
2. Deploy via standard process

---

## References

- Original investigation: `thoughts/shared/handoffs/IWA-15083/2026-02-06_09-15-48_IWA-15083_file-deletion-investigation.md`
- Sentry instrumentation: IWA-15095
- JS Sentry utilities: IWA-15096
- Files table schema: `mysql/db/tables/V000000001__Files.sql`
