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

# File Deletion Bug Fix & Sentry Instrumentation Implementation Plan

## Overview

Fix a critical bug where 23 hotspot photos were incorrectly deleted without updating AWS DataStore sync fields (`_version`, `_deleted`), breaking mobile app synchronization. We identified 10 stored procedures with this bug across 14 UPDATE statements. Additionally, implement comprehensive Sentry instrumentation following best practices to ensure complete visibility into all file deletion operations going forward.

This plan focuses on teaching proper Sentry usage patterns for error traceability and operational observability.

## Current State Analysis

### Bug Pattern Discovered

**Root Cause**: 10 stored procedures delete files by setting `FileStatusID = 2` but fail to update:
- `_version` (should increment: `_version = _version + 1`)
- `_deleted` (should be set: `_deleted = 1`)

This breaks AWS DataStore synchronization, causing deleted files to remain visible in the mobile app.

**Incident Timeline** (from handoff IWA-15083):
- **2026-01-29**: 11 hotspots moved to FacilityID 5196
- **2026-02-05 22:16:21 UTC**: 23 photos incorrectly deleted
- **2026-02-06**: Photos manually restored (Phase 3 complete ✓)

### Key Discoveries

**All 10 buggy procedures are ACTIVELY USED** - none can be removed:

| Procedure | Lambda | Call Type | Files with Bug |
|-----------|--------|-----------|----------------|
| `Cradlepoint_RemoveCradlepoint` | cradlepoint | Direct | R__PROC_Cradlepoint_RemoveCradlepoint.sql:59 |
| `Cradlepoint_AddCradlepoint` | cradlepoint | Direct (2 paths) | R__PROC_Cradlepoint_AddCradlepoint.sql:131 |
| `Cradlepoint_AddBulkCradlepointWithFundingProject` | cradlepoint | Direct | R__PROC_Cradlepoint_AddBulkCradlepointWithFundingProject.sql:96 |
| `Transponder_RemoveHubAndChangeFacility` | hub | Direct | R__PROC_Transponder_RemoveHubAndChangeFacility.sql:52 |
| `Transponder_AddTransponder_Notes` | hub | Direct | R__PROC_Transponder_AddTransponder_Notes.sql:139, 181 (2 instances) |
| `EnclosureCradlepointDevice_UpdateFacility` | hub, salesforce-wo, inventory | Indirect (via 4 parent procs) | R__PROC_EnclosureCradlepointDevice_UpdateFacility.sql:52 |
| `EnclosureTransponder_UpdateFacility` | cradlepoint, salesforce-wo, inventory | Indirect (via 4 parent procs) | R__PROC_EnclosureTransponder_UpdateFacility.sql:42 |
| `WorkOrder_LinkHardwareToRbom` | salesforce-wo | Direct | R__PROC_WorkOrder_LinkHardwareToRbom.sql:73, 111, 160, 186 (4 instances) |
| `WorkOrder_UpdateCradlepoints` | salesforce-wo | Indirect (via 4 parent procs) | R__PROC_WorkOrder_UpdateCradlepoints.sql:64 |
| `WorkOrder_UpdateTransponders` | salesforce-wo | Indirect (via 4 parent procs) | R__PROC_WorkOrder_UpdateTransponders.sql:57 |

**Total**: 10 procedures, 14 buggy UPDATE statements

**Correct implementations** (for reference):
- `Files_Remove` (R__PROC_Files_Remove.sql:11) - ✓ Properly updates all fields
- `MonitoringPoint_Reassign` (R__PROC_MonitoringPoint_Reassign.sql:41) - ✓ Properly updates all fields

### Sentry Infrastructure Discovery

**Python Lambdas** (~25 lambdas):
- ✅ Sentry already integrated via shared `sentry_utils.py` layer
- ✅ `measure_db_query()` context manager already wraps ALL `mysql_call_proc()` calls
- ❌ **BUT** tracing is completely disabled (early return at lines 62, 82 of sentry_utils.py)
- ❌ `traces_sample_rate` hardcoded to `0.0` (line 23)
- 📍 Infrastructure exists as dead code - just needs enabling

**JavaScript Lambda** (salesforce-work-orders):
- ❌ Zero Sentry integration
- 📋 **Recommendation**: Create separate ticket (IWA-XXXX) for JS lambda Sentry utilities similar to Python `sentry_utils.py`

### Investigation Outcome

We attempted to identify the root cause via CloudWatch logs but found:
- ✅ All 4 candidate lambdas had activity during incident window
- ❌ None performed write operations on our affected resources
- ❌ Only read operations (`getCradlepointStats`, `getHubList`) logged

**Conclusion**: Unable to determine which lambda/procedure caused the Feb 5th deletion. This validates the need for comprehensive Sentry instrumentation.

## Desired End State

### Success Criteria

After completing this plan:

1. **Bug Fix**: All 10 stored procedures properly update `_version` and `_deleted` when setting `FileStatusID = 2`
2. **Sentry Visibility**: Every file deletion operation (all 12 procedures) creates a Sentry breadcrumb with full context:
   - Procedure name
   - All parameters (device IDs, facility IDs, etc.)
   - User context (CognitoID)
   - Timestamp
3. **Searchability**: Can search Sentry by:
   - `procedure:<procedure_name>`
   - `facility_id:<id>`
   - `file_operation:delete`
   - User ID
4. **Future-Proof**: If this bug recurs or a new procedure has the same issue, we have full audit trail

### How to Verify

**Automated Verification:**
- [ ] Run SQL queries to verify all 14 UPDATE statements include `_version` and `_deleted` updates
- [ ] Type checking passes: `make -C mysql check` (if applicable)
- [ ] All Python lambdas still build/deploy successfully

**Manual Verification:**
- [ ] Trigger a hotspot removal via UI → Check Sentry for breadcrumb with procedure name and parameters
- [ ] Trigger a hub facility change → Check Sentry for breadcrumb
- [ ] Query Files table → Verify `_version` increments and `_deleted` is set correctly
- [ ] Verify mobile app receives DataStore sync updates

## What We're NOT Doing

1. **NOT enabling full Sentry tracing** (`traces_sample_rate > 0`) - This would create spans for ALL DB operations, which has cost/noise implications. We're using targeted instrumentation instead.
2. **NOT adding Sentry to JS lambdas** - Separate ticket (scope too large for this bug fix)
3. **NOT changing procedure behavior** - We're only fixing the missing fields, not changing deletion logic
4. **NOT removing any procedures** - All are actively used
5. **NOT restoring files in this ticket** - Already done manually

## Implementation Approach

### Strategy: Centralized Instrumentation Layer

Rather than adding Sentry calls to every lambda method that calls these procedures (dozens of locations), we'll modify the **shared `db_resources.py`** to automatically detect and instrument file-deletion procedures. This:
- Teaches best practice: centralized instrumentation
- Minimizes code duplication
- Ensures ALL call sites get instrumented (impossible to miss one)
- Makes it easy to add more procedures to the watch list later

### Sentry Concepts We'll Use

| Sentry Feature | When to Use | Our Usage |
|----------------|-------------|-----------|
| **Breadcrumbs** | Leave a trail of events; attached to errors | Add before every file-deletion procedure call with full context |
| **Tags** | Searchable metadata | `procedure`, `facility_id`, `file_operation:delete` |
| **Context** | Rich data attached to events | Full procedure args, user info |
| **Levels** | `info`, `warning`, `error` | Use `warning` level for file deletions (non-error but important) |

**Why not `capture_message()`?** While `capture_message()` creates standalone Sentry events, using breadcrumbs is more cost-effective and provides better context when errors DO occur. Breadcrumbs are free and always attached to the next error in that request. For non-error operational visibility, breadcrumbs are the right tool.

---

## Phase 1: Fix All 10 Buggy Stored Procedures

### Overview

Update all 14 UPDATE statements across 10 stored procedures to properly maintain DataStore sync fields.

### Changes Required

#### Fix Pattern (Apply to All)

**Before (broken):**
```sql
UPDATE Files SET FileStatusID = 2 WHERE <condition>;
```

**After (correct):**
```sql
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE <condition>;
```

#### 1. `Cradlepoint_RemoveCradlepoint`

**File**: `mysql/db/procs/R__PROC_Cradlepoint_RemoveCradlepoint.sql`
**Line**: 59

```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE CradlePointDeviceID = localCradlepointDeviceID;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE CradlePointDeviceID = localCradlepointDeviceID;
```

#### 2. `Cradlepoint_AddCradlepoint`

**File**: `mysql/db/procs/R__PROC_Cradlepoint_AddCradlepoint.sql`
**Line**: 131

```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE CradlePointDeviceID = localCradlepointDeviceID;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE CradlePointDeviceID = localCradlepointDeviceID;
```

#### 3. `Cradlepoint_AddBulkCradlepointWithFundingProject`

**File**: `mysql/db/procs/R__PROC_Cradlepoint_AddBulkCradlepointWithFundingProject.sql`
**Line**: 96

```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE CradlePointDeviceID = localCradlepointDeviceID;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE CradlePointDeviceID = localCradlepointDeviceID;
```

#### 4. `Transponder_RemoveHubAndChangeFacility`

**File**: `mysql/db/procs/R__PROC_Transponder_RemoveHubAndChangeFacility.sql`
**Line**: 52

```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE TransponderID = inTransponderID;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE TransponderID = inTransponderID;
```

#### 5. `Transponder_AddTransponder_Notes` (2 instances)

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

#### 6. `EnclosureCradlepointDevice_UpdateFacility`

**File**: `mysql/db/procs/R__PROC_EnclosureCradlepointDevice_UpdateFacility.sql`
**Line**: 52

```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE CradlePointDeviceID = localNextCradlepointDeviceID AND DidUpload = 1 AND FileStatusID = 1;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE CradlePointDeviceID = localNextCradlepointDeviceID AND DidUpload = 1 AND FileStatusID = 1;
```

#### 7. `EnclosureTransponder_UpdateFacility`

**File**: `mysql/db/procs/R__PROC_EnclosureTransponder_UpdateFacility.sql`
**Line**: 42

```sql
-- OLD:
UPDATE Files SET FileStatusID = 2 WHERE TransponderID = localNextTransponderID AND DidUpload = 1 AND FileStatusID = 1;

-- NEW:
UPDATE Files SET FileStatusID = 2, _version = _version + 1, _deleted = 1 WHERE TransponderID = localNextTransponderID AND DidUpload = 1 AND FileStatusID = 1;
```

#### 8. `WorkOrder_LinkHardwareToRbom` (4 instances)

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

#### 9. `WorkOrder_UpdateCradlepoints`

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

#### 10. `WorkOrder_UpdateTransponders`

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

### Success Criteria

#### Automated Verification:

- [ ] All 14 UPDATE statements in 10 files include `_version = _version + 1, _deleted = 1`
- [ ] Verify with SQL query:
  ```bash
  grep -n "UPDATE Files SET FileStatusID = 2" mysql/db/procs/R__PROC_*.sql | \
    grep -v "_version" | grep -v "_deleted"
  ```
  Should return ZERO results (except for Files_Remove and MonitoringPoint_Reassign which already have them)

#### Manual Verification:

- [ ] Review each file individually to ensure syntax is correct
- [ ] Check that no other SET clauses were accidentally removed
- [ ] Verify WHERE conditions remain unchanged

**Implementation Note**: After completing all edits, run the grep command above to verify no buggy UPDATEs remain before deploying.

---

## Phase 2: Add Comprehensive Sentry Instrumentation

### Overview

Instrument ALL 12 stored procedures that set FileStatusID=2 (10 buggy + 2 correct) to provide complete operational visibility. We'll modify the shared `db_resources.py` layer to automatically detect and instrument these procedure calls.

This teaches **Sentry best practices**:
- Centralized instrumentation (DRY principle)
- Breadcrumbs for operational visibility
- Tags for searchability
- Context for debugging

### Changes Required

#### 1. Define File-Operation Procedures List

**File**: `lambdas/layers/db_resources_311/python/db_resources.py`
**Location**: After imports, before function definitions (around line 30)

```python
# Stored procedures that modify Files.FileStatusID
# We track these for operational visibility in Sentry
FILE_DELETION_PROCEDURES = {
    # Buggy procedures (now fixed in Phase 1)
    "Cradlepoint_RemoveCradlepoint",
    "Cradlepoint_AddCradlepoint",
    "Cradlepoint_AddBulkCradlepointWithFundingProject",
    "Transponder_RemoveHubAndChangeFacility",
    "Transponder_AddTransponder_Notes",
    "EnclosureCradlepointDevice_UpdateFacility",
    "EnclosureTransponder_UpdateFacility",
    "WorkOrder_LinkHardwareToRbom",
    "WorkOrder_UpdateCradlepoints",
    "WorkOrder_UpdateTransponders",
    # Correct implementations (for comparison)
    "Files_Remove",
    "MonitoringPoint_Reassign",
}
```

#### 2. Add Sentry Instrumentation Helper Function

**File**: `lambdas/layers/db_resources_311/python/db_resources.py`
**Location**: Before `mysql_call_proc()` function (around line 295)

```python
def _add_file_operation_breadcrumb(proc_name, args, cognito_id, request_id):
    """
    Add Sentry breadcrumb for file deletion operations.

    Best Practice: Use breadcrumbs for operational events (not errors).
    Breadcrumbs are free, attached to subsequent errors, and provide context.

    :param proc_name: Stored procedure name
    :param args: Procedure arguments tuple
    :param cognito_id: User's Cognito ID
    :param request_id: API Gateway request ID
    """
    if sentry_sdk is None:
        return

    # Only track file-operation procedures
    if proc_name not in FILE_DELETION_PROCEDURES:
        return

    # Extract meaningful parameters from args for context
    # Args structure varies by procedure, so we capture everything
    breadcrumb_data = {
        "procedure": proc_name,
        "args_count": len(args) if args else 0,
        "request_id": request_id,
    }

    # Add args (truncate if too large to avoid payload limits)
    if args:
        # Convert args to strings, truncate each to 100 chars
        args_str = [str(arg)[:100] for arg in args[:10]]  # Max 10 args
        breadcrumb_data["args"] = args_str

    # Best Practice: Use structured categories for filtering
    sentry_sdk.add_breadcrumb(
        category="database.file_operation",
        message=f"Calling {proc_name} - modifies Files.FileStatusID",
        level="warning",  # Warning level for important operational events
        data=breadcrumb_data,
    )

    # Best Practice: Set tags for searchability
    # Tags appear in Sentry search UI and can be used for filtering
    scope = sentry_sdk.get_current_scope()
    scope.set_tag("procedure", proc_name)
    scope.set_tag("file_operation", "delete")  # Searchable tag

    # Best Practice: Set context for rich debugging info
    # Context appears in the "Additional Data" section of Sentry events
    scope.set_context("stored_procedure", {
        "name": proc_name,
        "arg_count": len(args) if args else 0,
        "is_file_operation": True,
    })
```

#### 3. Modify `mysql_call_proc()` to Use Instrumentation

**File**: `lambdas/layers/db_resources_311/python/db_resources.py`
**Line**: ~325 (inside `mysql_call_proc()`, right after getting connection)

**Find this code** (around line 316):
```python
try:
    conn = get_connection(DB_OPTION)

except pymysql.MySQLError as e:
    duration = time.time() - t_start
    print(f"proc_name=<{proc_name}>, args=<{args}>...")
    sys.exit()
```

**Add instrumentation call AFTER the successful connection** (around line 323):
```python
try:
    conn = get_connection(DB_OPTION)

except pymysql.MySQLError as e:
    duration = time.time() - t_start
    print(f"proc_name=<{proc_name}>, args=<{args}>...")
    sys.exit()

# ADD THIS: Instrument file operations for Sentry visibility
_add_file_operation_breadcrumb(proc_name, args, cognito_id, request_id)

try:
    with sentry_utils.measure_db_query(f"{proc_name}{args}"):
        # ... existing code
```

#### 4. Modify `mysql_call_proc_mult_sets()` to Use Instrumentation

**File**: `lambdas/layers/db_resources_311/python/db_resources.py`
**Line**: ~385 (inside `mysql_call_proc_mult_sets()`)

**Same pattern - add after successful connection:**
```python
try:
    conn = get_connection(DB_OPTION)
except pymysql.MySQLError as e:
    # ... existing error handling

# ADD THIS: Instrument file operations for Sentry visibility
_add_file_operation_breadcrumb(proc_name, args, cognito_id, request_id)

try:
    with sentry_utils.measure_db_query(f"{proc_name}{args}"):
        # ... existing code
```

### Success Criteria

#### Automated Verification:

- [ ] Python lambda type checking passes: `cd lambdas/lf-vero-prod-cradlepoint && make check`
- [ ] Lambda builds successfully: `cd lambdas && make build`
- [ ] Layer deploys without errors

#### Manual Verification:

- [ ] Trigger hotspot removal via UI (calls `Cradlepoint_RemoveCradlepoint`)
- [ ] Go to Sentry → Search for `procedure:Cradlepoint_RemoveCradlepoint`
- [ ] Verify breadcrumb appears with:
  - ✓ Category: `database.file_operation`
  - ✓ Message includes procedure name
  - ✓ Data includes args, request_id
  - ✓ Level: `warning`
- [ ] Verify tags are set:
  - ✓ `procedure:<proc_name>`
  - ✓ `file_operation:delete`
- [ ] Verify context includes stored procedure details
- [ ] Repeat test for at least 2 other procedures (hub removal, work order operation)

**Implementation Note**: Test in dev/qa environment first. Verify breadcrumbs appear in Sentry console before deploying to prod.

---

## Phase 3: File Restoration (✓ COMPLETE)

**Status**: Already completed manually on 2026-02-06

The 23 affected files (FileIDs: 395501, 395507, 395543, 395544, 395555, 395572, 395573, 395904, 395905, 396059, 396060, 396078, 396080, 396091, 396092, 396105, 396106, 396115, 396116, 396126, 396127, 396718, 396720) have been restored with:
```sql
UPDATE Files
SET FileStatusID = 1, _version = _version + 1, _deleted = 0
WHERE FileID IN (...);
```

No further action required.

---

## Phase 4: Verification & Deployment

### Overview

Comprehensive testing to verify both bug fixes and Sentry instrumentation work correctly.

### Testing Strategy

#### 1. Dev Environment Testing

**Test Case 1: Verify Stored Procedure Fixes**
```sql
-- In dev database, create test cradlepoint and files
-- Trigger removal
-- Verify _version and _deleted are updated correctly
SELECT FileID, FileStatusID, _version, _deleted, _lastChangedAt
FROM Files
WHERE CradlePointDeviceID = <test_device_id>;
```

Expected: `FileStatusID=2, _deleted=1, _version incremented`

**Test Case 2: Verify Sentry Breadcrumbs**
- Trigger test operation that calls one of the 12 procedures
- Check Sentry console for breadcrumb with correct structure
- Verify searchability via tags

**Test Case 3: Verify Mobile App Sync**
- Delete a test file
- Verify AWS DataStore receives sync update
- Verify mobile app reflects deletion

#### 2. QA Environment Testing

Repeat all dev tests in QA environment with:
- Real-like data volumes
- Multiple concurrent operations
- Different user roles

#### 3. Production Deployment

**Deployment Order**:
1. Deploy stored procedure fixes (Flyway migration)
2. Deploy updated `db_resources_311` Lambda Layer
3. Deploy/redeploy affected lambdas to pick up new layer version

**Monitoring**:
- Watch Sentry for new breadcrumbs
- Monitor CloudWatch for any DB errors
- Check DataStore sync metrics

### Success Criteria

#### Automated Verification:

- [ ] All stored procedure changes deployed successfully via Flyway
- [ ] Lambda layer updated and propagated to all lambdas
- [ ] No increase in error rates post-deployment
- [ ] CloudWatch shows normal lambda execution times (no performance degradation)

#### Manual Verification:

- [ ] Perform 3 test operations in prod (different procedure types)
- [ ] Verify all 3 create Sentry breadcrumbs
- [ ] Verify Files table shows correct `_version` and `_deleted` values
- [ ] Verify mobile app receives DataStore sync for test deletions
- [ ] Search Sentry for `file_operation:delete` → Should see all test operations
- [ ] Check Sentry performance impact (breadcrumbs should be minimal)

**Implementation Note**: Keep this Sentry ticket open for 7 days post-deployment to monitor for any issues. If another file deletion occurs, we should immediately have visibility.

---

## Testing Strategy

### Unit Tests

**Not applicable** - These are stored procedure fixes (SQL) and shared layer instrumentation. Testing is via integration and manual verification.

### Integration Tests

**Recommended** (but not blocking for this ticket):
- Create backend integration test that calls each buggy procedure
- Verify `_version` and `_deleted` are set correctly
- Mock Sentry SDK and verify breadcrumbs are added

**File**: `lambdas/tests/test_file_deletion_procedures.py` (new file)
```python
# Pseudo-code
def test_cradlepoint_remove_updates_version_and_deleted():
    # Setup test cradlepoint with file
    # Call Cradlepoint_RemoveCradlepoint
    # Query Files table
    # Assert _version incremented and _deleted=1
    pass
```

### Manual Testing Checklist

Per procedure type:

**Cradlepoint Operations:**
- [ ] Remove hotspot → Check Files table and Sentry
- [ ] Add hotspot to different facility → Check Files and Sentry
- [ ] Bulk add hotspots → Check Files and Sentry

**Hub/Transponder Operations:**
- [ ] Remove hub → Check Files and Sentry
- [ ] Add hub with notes → Check Files and Sentry
- [ ] Move hub between facilities → Check Files and Sentry

**Work Order Operations:**
- [ ] Link hardware to R-BOM → Check Files and Sentry
- [ ] Remove hardware from work order → Check Files and Sentry

---

## Performance Considerations

### Sentry Breadcrumb Overhead

**Measurement**: Breadcrumbs are extremely lightweight:
- No network call (buffered in memory until error)
- Minimal CPU (simple dict operations)
- Typical overhead: <1ms per breadcrumb

**Mitigation**: None needed - breadcrumbs are designed for high-frequency use

### Stored Procedure Changes

**Measurement**: Adding 2 fields to UPDATE has negligible impact:
- Same transaction
- Same row lock
- No additional I/O

**Mitigation**: None needed

### Lambda Layer Propagation

**Impact**: Updating the layer requires all lambdas using it to pick up the new version. This happens:
- Automatically on next cold start
- Can be forced by redeploying lambdas
- No downtime

---

## Migration Notes

### Deployment Order

1. **Stored Procedures** (Flyway migration):
   - Runs automatically on deploy
   - No data migration needed
   - No rollback concerns (adding fields is backwards compatible)

2. **Lambda Layer** (`db_resources_311`):
   - Package new version
   - Update layer in AWS
   - Note new version number

3. **Lambda Deployments**:
   - Lambdas will pick up new layer on next cold start
   - Or force redeploy to ensure immediate pickup
   - Recommended: Deploy to dev → qa → prod with monitoring

### Rollback Plan

If issues arise:

**Stored Procedures**:
- Create Flyway migration to revert changes
- Deploy via standard process

**Sentry Instrumentation**:
- Redeploy previous layer version
- Lambdas will pick up on next cold start
- Or remove breadcrumb calls from `mysql_call_proc()` and redeploy

---

## References

- Original handoff: `thoughts/shared/handoffs/IWA-15083/2026-02-06_09-15-48_IWA-15083_file-deletion-investigation.md`
- CloudWatch investigation scripts: `/tmp/feb5_investigation/`
- Sentry Python SDK: `sentry-sdk==1.35.0`
- Sentry utilities: `lambdas/layers/db_resources_311/python/sentry_utils.py`
- DB resources: `lambdas/layers/db_resources_311/python/db_resources.py`

## Related Tickets

- **IWA-15083**: Original investigation (completed)
- **IWA-XXXX** (TO CREATE): Add Sentry utilities for JavaScript lambdas (similar to Python `sentry_utils.py`)

---

## Sentry Best Practices Summary

For future reference, this plan demonstrates:

1. **Breadcrumbs vs capture_message()**:
   - Use breadcrumbs for frequent operational events (free, no noise)
   - Use capture_message for rare but important events that should show up independently

2. **Tags for Searchability**:
   - Always set tags for dimensions you'll want to search/filter by
   - Example: `procedure:<name>`, `file_operation:delete`, `facility_id:<id>`

3. **Context for Rich Data**:
   - Use set_context for detailed debugging info that doesn't need to be searchable
   - Appears in "Additional Data" section

4. **Levels**:
   - `info`: Normal operations
   - `warning`: Important but not errors (we use this for file operations)
   - `error`: Actual errors

5. **Centralized Instrumentation**:
   - Instrument at shared layers (like `db_resources.py`) rather than duplicating across lambdas
   - DRY principle applies to observability code too!

6. **Category Naming**:
   - Use dot notation: `database.file_operation`
   - Makes filtering easier in Sentry UI
