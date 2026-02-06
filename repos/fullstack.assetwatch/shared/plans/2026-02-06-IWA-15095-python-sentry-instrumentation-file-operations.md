---
date: 2026-02-06T13:47:27-0500
researcher: aw-jwalker
git_commit: aef6609646df1ec10108205f749be14f7d84fce3
branch: dev
repository: fullstack.assetwatch
ticket: IWA-15095
status: draft
last_updated: 2026-02-06
last_updated_by: aw-jwalker
type: implementation_plan
related_tickets: [IWA-15084, IWA-15096]
---

# Python Sentry Instrumentation for File Operations (IWA-15095)

## Overview

Add comprehensive Sentry instrumentation to track ALL file deletion operations (12 stored procedures) in Python lambdas. This provides operational visibility and audit trail to prevent future incidents like IWA-15083 (23 photos incorrectly deleted with no trace).

**Focus**: Teach and implement Sentry best practices for operational observability.

**Related Tickets**:
- **IWA-15084**: Stored procedure bug fixes (prerequisite)
- **IWA-15096**: JS Sentry utilities for salesforce-work-orders lambda

## Current State Analysis

### Sentry Infrastructure (Python Lambdas)

**Status**: ✅ Sentry already integrated, but features disabled

**Key Files**:
- `lambdas/layers/db_resources_311/python/sentry_utils.py` - Shared Sentry utilities
- `lambdas/layers/db_resources_311/python/db_resources.py` - DB operations layer
- `sentry-sdk==1.35.0` (pinned in requirements.txt)

**Current Setup**:
- ✅ All ~25 Python lambdas use shared `sentry_utils.py`
- ✅ `initialize_sentry()` called at module level
- ✅ `setup_sentry_scope()` called in each handler
- ✅ Transaction names set: `{function_name}.{method}`
- ✅ User context captured (Cognito ID)
- ❌ **Tracing disabled**: `traces_sample_rate = 0.0` (line 23)
- ❌ **Spans disabled**: Early returns in `measure_db_connect()` and `measure_db_query()` (lines 62, 82)
- ❌ **No file operation tracking**: No breadcrumbs or context for file deletions

**Key Discovery**:
The infrastructure for DB spans exists as **dead code** below the early returns. We could enable it, but for this ticket we're using targeted breadcrumbs instead (lower overhead, no noise).

### Stored Procedures That Modify Files

**12 procedures total** (all set `FileStatusID = 2`):

**Buggy (being fixed in IWA-15084):**
1. `Cradlepoint_RemoveCradlepoint`
2. `Cradlepoint_AddCradlepoint`
3. `Cradlepoint_AddBulkCradlepointWithFundingProject`
4. `Transponder_RemoveHubAndChangeFacility`
5. `Transponder_AddTransponder_Notes`
6. `EnclosureCradlepointDevice_UpdateFacility`
7. `EnclosureTransponder_UpdateFacility`
8. `WorkOrder_LinkHardwareToRbom`
9. `WorkOrder_UpdateCradlepoints`
10. `WorkOrder_UpdateTransponders`

**Already correct:**
11. `Files_Remove`
12. `MonitoringPoint_Reassign`

**Goal**: Instrument ALL 12 so we have complete visibility into file operations.

## Desired End State

### Success Criteria

After completing this plan:

1. **Breadcrumbs Added**: Every file deletion operation creates a Sentry breadcrumb with full context
2. **Searchable Tags**: Can search Sentry by:
   - `procedure:<procedure_name>`
   - `file_operation:delete`
   - `facility_id:<id>` (when applicable)
3. **Rich Context**: Breadcrumbs include:
   - Procedure name
   - All parameters
   - User context (Cognito ID)
   - Request ID
4. **Centralized Implementation**: Single change in `db_resources.py` instruments all call sites
5. **No Performance Impact**: Breadcrumbs add <1ms overhead

### How to Verify

**Automated Verification:**
- [ ] Python type checking passes: `cd lambdas/lf-vero-prod-cradlepoint && make check`
- [ ] Lambda layer builds: `cd lambdas/layers/db_resources_311 && make build`
- [ ] All Python lambdas still deploy successfully

**Manual Verification:**
- [ ] Trigger hotspot removal → Search Sentry for `procedure:Cradlepoint_RemoveCradlepoint` → Verify breadcrumb appears
- [ ] Breadcrumb includes: procedure name, args, request_id, user context
- [ ] Tags set: `procedure`, `file_operation:delete`
- [ ] Context set: `stored_procedure` with details
- [ ] Trigger hub removal → Verify breadcrumb in Sentry
- [ ] Trigger work order operation → Verify breadcrumb
- [ ] Search Sentry for `file_operation:delete` → See all test operations

## What We're NOT Doing

1. **NOT enabling full tracing** (`traces_sample_rate > 0`) - Would add spans for ALL DB operations, creating noise/cost
2. **NOT using `capture_message()`** - Breadcrumbs are better for high-frequency operations (no noise, free)
3. **NOT removing early returns from `measure_db_query()`** - Keeping those disabled to avoid span overhead
4. **NOT instrumenting JS lambdas** - Separate ticket (IWA-15096)
5. **NOT adding per-lambda instrumentation** - Using centralized layer approach instead

## Implementation Approach

### Strategy: Centralized Instrumentation

Modify the shared `db_resources.py` to automatically detect and instrument file-deletion procedures. This:
- **DRY**: Single change point, no code duplication
- **Complete**: Impossible to miss a call site
- **Best Practice**: Centralized observability pattern
- **Future-Proof**: Easy to add more procedures to watch list

### Sentry Patterns We're Using

| Feature | Purpose | Our Usage |
|---------|---------|-----------|
| **Breadcrumbs** | Leave event trail; attached to errors | Add before every file-deletion procedure call |
| **Tags** | Searchable metadata | `procedure`, `file_operation`, `facility_id` |
| **Context** | Rich debugging data | Full args, user info, request ID |
| **Levels** | Event severity | `warning` for file deletions (important but not errors) |

**Why Breadcrumbs Over `capture_message()`**:
- **Cost**: Breadcrumbs are free, `capture_message()` creates standalone events ($$)
- **Noise**: Breadcrumbs don't clutter Sentry UI
- **Context**: Breadcrumbs automatically attach to subsequent errors in same request
- **Best Practice**: Standard pattern for high-frequency operational events

---

## Changes Required

### 1. Define File-Operation Procedures List

**File**: `lambdas/layers/db_resources_311/python/db_resources.py`
**Location**: After imports, before function definitions (~line 30)

```python
# Stored procedures that modify Files.FileStatusID
# We track these for operational visibility in Sentry
# This enables complete audit trail for file deletion operations
FILE_DELETION_PROCEDURES = {
    # Procedures that delete files (fixed in IWA-15084)
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

---

### 2. Add Sentry Instrumentation Helper Function

**File**: `lambdas/layers/db_resources_311/python/db_resources.py`
**Location**: Before `mysql_call_proc()` function (~line 295)

```python
def _add_file_operation_breadcrumb(proc_name, args, cognito_id, request_id):
    """
    Add Sentry breadcrumb for file deletion operations.

    BEST PRACTICE: Use breadcrumbs for operational events (not errors).
    Breadcrumbs are free, attached to subsequent errors, and provide context.

    This enables:
    - Complete audit trail of file operations
    - Searchability via tags (procedure, facility_id, etc.)
    - Rich context for debugging when errors occur
    - Zero noise in Sentry UI (breadcrumbs only appear with errors)

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

    # Build structured breadcrumb data
    # Truncate to avoid hitting Sentry payload limits (8KB per breadcrumb)
    breadcrumb_data = {
        "procedure": proc_name,
        "args_count": len(args) if args else 0,
        "request_id": request_id,
    }

    # Add args (truncate if too large)
    if args:
        # Convert args to strings, truncate each to 100 chars
        # Limit to first 10 args to avoid payload bloat
        args_str = [str(arg)[:100] for arg in args[:10]]
        breadcrumb_data["args"] = args_str

    # BEST PRACTICE: Structured categories for filtering
    # Format: "{domain}.{action}" makes Sentry UI filtering easier
    sentry_sdk.add_breadcrumb(
        category="database.file_operation",
        message=f"Calling {proc_name} - modifies Files.FileStatusID",
        level="warning",  # Warning level for important operational events
        data=breadcrumb_data,
    )

    # BEST PRACTICE: Tags for searchability
    # Tags appear in Sentry search UI and can filter events
    # Always set tags for dimensions you'll want to search by
    scope = sentry_sdk.get_current_scope()
    scope.set_tag("procedure", proc_name)
    scope.set_tag("file_operation", "delete")  # Generic tag for all file deletions

    # BEST PRACTICE: Context for rich debugging info
    # Context appears in "Additional Data" section of Sentry events
    # Use for data that doesn't need to be searchable but aids debugging
    scope.set_context("stored_procedure", {
        "name": proc_name,
        "arg_count": len(args) if args else 0,
        "is_file_operation": True,
        "category": "file_deletion",
    })
```

**Sentry Concepts Explained**:

- **Breadcrumb**: A trail of events leading up to an error. Lightweight, buffered in memory.
- **Category**: Groups related breadcrumbs (e.g., `database.*`, `http.*`, `user.*`)
- **Level**: `debug`, `info`, `warning`, `error` - we use `warning` for important operational events
- **Tags**: Searchable key-value pairs. Indexed, fast, limited to ~200 bytes per tag.
- **Context**: Rich structured data. Not indexed, unlimited size, appears in event details.

---

### 3. Modify `mysql_call_proc()` to Use Instrumentation

**File**: `lambdas/layers/db_resources_311/python/db_resources.py`
**Line**: ~316 (inside `mysql_call_proc()`)

**Find this section:**
```python
try:
    conn = get_connection(DB_OPTION)

except pymysql.MySQLError as e:
    duration = time.time() - t_start
    print(f"proc_name=<{proc_name}>, args=<{args}>...")
    sys.exit()
try:
    with sentry_utils.measure_db_query(f"{proc_name}{args}"):
        cur = conn.cursor(pymysql.cursors.DictCursor)
        cur.callproc(proc_name, args)
        # ...
```

**Add instrumentation call AFTER successful connection:**
```python
try:
    conn = get_connection(DB_OPTION)

except pymysql.MySQLError as e:
    duration = time.time() - t_start
    print(f"proc_name=<{proc_name}>, args=<{args}>...")
    sys.exit()

# ADD THIS: Instrument file operations for Sentry visibility
# This adds breadcrumb + tags for all file-deletion procedures
_add_file_operation_breadcrumb(proc_name, args, cognito_id, request_id)

try:
    with sentry_utils.measure_db_query(f"{proc_name}{args}"):
        cur = conn.cursor(pymysql.cursors.DictCursor)
        cur.callproc(proc_name, args)
        # ... rest of existing code
```

---

### 4. Modify `mysql_call_proc_mult_sets()` to Use Instrumentation

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
        # ... rest of existing code
```

---

## Success Criteria

### Automated Verification:

- [ ] Python type checking passes:
  ```bash
  cd lambdas/lf-vero-prod-cradlepoint && make check
  cd lambdas/lf-vero-prod-hub && make check
  cd lambdas/lf-vero-prod-inventory && make check
  ```
- [ ] Lambda layer builds successfully:
  ```bash
  cd lambdas/layers/db_resources_311 && make build
  ```
- [ ] All Python lambdas deploy successfully

### Manual Verification (Dev/QA):

**Test 1: Hotspot Removal**
- [ ] Trigger: Remove hotspot via UI (calls `Cradlepoint_RemoveCradlepoint`)
- [ ] Go to Sentry → Search: `procedure:Cradlepoint_RemoveCradlepoint`
- [ ] Verify breadcrumb exists with:
  - ✓ Category: `database.file_operation`
  - ✓ Message: `Calling Cradlepoint_RemoveCradlepoint - modifies Files.FileStatusID`
  - ✓ Level: `warning`
  - ✓ Data includes: procedure, args (truncated), request_id
- [ ] Verify tags set:
  - ✓ `procedure:Cradlepoint_RemoveCradlepoint`
  - ✓ `file_operation:delete`
- [ ] Verify context includes: `stored_procedure` with name, arg_count, category

**Test 2: Hub Removal**
- [ ] Trigger: Remove hub via UI (calls `Transponder_RemoveHubAndChangeFacility`)
- [ ] Search Sentry: `procedure:Transponder_RemoveHubAndChangeFacility`
- [ ] Verify breadcrumb structure (same checklist as Test 1)

**Test 3: Work Order Operation**
- [ ] Trigger: Link hardware to R-BOM (calls `WorkOrder_LinkHardwareToRbom`)
- [ ] Search Sentry: `procedure:WorkOrder_LinkHardwareToRbom`
- [ ] Verify breadcrumb structure

**Test 4: Search All File Operations**
- [ ] Search Sentry: `file_operation:delete`
- [ ] Should see all test operations from Tests 1-3
- [ ] Verify each has correct tags and breadcrumb structure

**Test 5: Performance Check**
- [ ] Trigger 10 file operations rapidly
- [ ] Check CloudWatch lambda duration metrics
- [ ] Verify <5ms overhead (breadcrumbs are extremely lightweight)

---

## Testing Strategy

### Manual Test Plan

**Environment**: Dev first, then QA, then Prod

**For each procedure type, test:**

| Operation | UI Action | Procedure Called | Expected Breadcrumb |
|-----------|-----------|------------------|---------------------|
| Remove hotspot | Customer page → Hotspots → Remove | `Cradlepoint_RemoveCradlepoint` | ✓ |
| Add hotspot to facility | Customer page → Hotspots → Add | `Cradlepoint_AddCradlepoint` | ✓ |
| Bulk add hotspots | Track Inventory → Add | `Cradlepoint_AddBulkCradlepointWithFundingProject` | ✓ |
| Remove hub | Customer page → Hubs → Remove | `Transponder_RemoveHubAndChangeFacility` | ✓ |
| Add hub with notes | Customer page → Hubs → Add | `Transponder_AddTransponder_Notes` | ✓ |
| Link hardware to R-BOM | Work Order → Return → Link | `WorkOrder_LinkHardwareToRbom` | ✓ |

**Sentry Search Patterns to Test:**

```
# Find all file operations
file_operation:delete

# Find specific procedure calls
procedure:Cradlepoint_RemoveCradlepoint

# Find all operations by a specific user
user.id:<cognito_id> file_operation:delete

# Find all operations in a time range
file_operation:delete timestamp:[2026-02-06 TO 2026-02-07]
```

### Integration Tests (Recommended, Not Blocking)

**File**: `lambdas/tests/test_sentry_file_operations.py` (new)

```python
import pytest
from unittest.mock import Mock, patch, call
from db_resources import _add_file_operation_breadcrumb, FILE_DELETION_PROCEDURES

@patch('db_resources.sentry_sdk')
def test_file_operation_breadcrumb_added(mock_sentry):
    """Test that breadcrumb is added for file-deletion procedures."""
    proc_name = "Cradlepoint_RemoveCradlepoint"
    args = (123, 456)
    cognito_id = "test-user-123"
    request_id = "test-request-abc"

    _add_file_operation_breadcrumb(proc_name, args, cognito_id, request_id)

    # Verify add_breadcrumb was called with correct structure
    mock_sentry.add_breadcrumb.assert_called_once()
    breadcrumb_call = mock_sentry.add_breadcrumb.call_args

    assert breadcrumb_call[1]['category'] == 'database.file_operation'
    assert breadcrumb_call[1]['level'] == 'warning'
    assert proc_name in breadcrumb_call[1]['message']

@patch('db_resources.sentry_sdk')
def test_file_operation_sets_tags(mock_sentry):
    """Test that searchable tags are set."""
    proc_name = "Files_Remove"
    mock_scope = Mock()
    mock_sentry.get_current_scope.return_value = mock_scope

    _add_file_operation_breadcrumb(proc_name, (), "user", "req")

    # Verify tags were set
    assert mock_scope.set_tag.call_count == 2
    mock_scope.set_tag.assert_any_call("procedure", proc_name)
    mock_scope.set_tag.assert_any_call("file_operation", "delete")

@patch('db_resources.sentry_sdk')
def test_non_file_operation_no_breadcrumb(mock_sentry):
    """Test that non-file procedures don't create breadcrumbs."""
    proc_name = "SomeOtherProcedure"

    _add_file_operation_breadcrumb(proc_name, (), "user", "req")

    # Should not call Sentry at all
    mock_sentry.add_breadcrumb.assert_not_called()
```

---

## Performance Considerations

### Breadcrumb Overhead

**Measurement**: Breadcrumbs are extremely lightweight:
- **CPU**: Simple dict/string operations, <0.5ms
- **Memory**: Buffered in memory, ~500 bytes per breadcrumb
- **Network**: Zero (not sent until an error occurs)
- **Typical overhead**: <1ms per procedure call

**Sentry Best Practice**: Breadcrumbs are designed for high-frequency use. The SDK maintains a circular buffer (default 100 breadcrumbs) and only sends them when an error is captured.

### No Network Calls

**Important**: Our implementation adds ZERO network overhead:
- Breadcrumbs are buffered locally
- Tags and context are attached to the current scope
- Nothing is sent to Sentry unless an error occurs
- If no error occurs, breadcrumbs are discarded when the lambda exits

### Lambda Cold Start

**Impact**: Negligible
- `sentry_sdk` already imported and initialized
- Adding 1 function and 1 set has no measurable impact
- Layer size increases by <1KB

---

## Migration Notes

### Deployment Order

1. **Build updated layer**:
   ```bash
   cd lambdas/layers/db_resources_311
   make build
   ```

2. **Publish layer to AWS**:
   ```bash
   aws lambda publish-layer-version \
     --layer-name db_resources_311 \
     --zip-file fileb://db_resources_311.zip \
     --compatible-runtimes python3.11
   ```

3. **Update layer version in lambdas**:
   - Lambdas will pick up new layer on next cold start
   - Or force redeploy to ensure immediate pickup

4. **Deploy progression**: Dev → QA → Prod with monitoring

### Rollback Plan

If issues arise:

**Option 1: Revert layer version**
- Point lambdas back to previous layer version
- Cold starts will pick up old version

**Option 2: Comment out instrumentation calls**
- Comment out `_add_file_operation_breadcrumb()` calls in `mysql_call_proc()` and `mysql_call_proc_mult_sets()`
- Redeploy layer

### Monitoring During Rollout

**Watch for**:
- Lambda error rates (should not change)
- Lambda duration (should increase by <5ms)
- Sentry event volume (breadcrumbs alone don't create events)

**Validation**:
- Trigger test operations in each environment
- Verify breadcrumbs appear in Sentry
- Search by tags to ensure searchability works

---

## References

- Sentry Python SDK docs: https://docs.sentry.io/platforms/python/
- Breadcrumbs best practices: https://docs.sentry.io/platforms/python/enriching-events/breadcrumbs/
- Current implementation: `lambdas/layers/db_resources_311/python/sentry_utils.py`
- DB layer: `lambdas/layers/db_resources_311/python/db_resources.py`
- Original investigation: IWA-15083
- Stored procedure fixes: IWA-15084
- JS Sentry utilities: IWA-15096

---

## Sentry Best Practices Summary

This implementation demonstrates:

1. **Breadcrumbs for Operations, Not Errors**
   - Use breadcrumbs for high-frequency events
   - They're free, lightweight, and provide context
   - Only sent when errors occur (zero noise)

2. **Tags for Searchability**
   - Set tags for every dimension you'll search by
   - Keep tags short (<200 bytes)
   - Use consistent naming conventions

3. **Context for Rich Data**
   - Use context for debugging details that don't need search
   - Can include large objects (within reason)
   - Appears in "Additional Data" section

4. **Levels Indicate Importance**
   - `debug`: Verbose operational details
   - `info`: Normal operations
   - `warning`: Important but not errors (our choice)
   - `error`: Actual errors

5. **Centralized Instrumentation**
   - Instrument at shared layers (DRY)
   - Single change point = impossible to miss call sites
   - Easy to extend to more procedures

6. **Category Naming Convention**
   - Use dot notation: `{domain}.{action}`
   - Example: `database.file_operation`
   - Makes Sentry UI filtering intuitive

7. **Performance Awareness**
   - Breadcrumbs are designed for high frequency
   - No network calls until error occurs
   - Truncate large data to avoid payload limits
