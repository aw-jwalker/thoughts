# IWA-13768: Review, Cleanup, Testing & PR Preparation Plan

## Overview

This plan covers the final steps to review the current IWA-13768 implementation, clean up any issues, test the functionality in dev, and perform a self PR review before merging.

## Current State Analysis

### Branch Status
- **Branch**: `IWA-13768`
- **Commit**: `21266632d` - "Clear hub schedules when removing/moving hubs from facilities"
- **Files Changed**: 3 files, 169 insertions, 1 deletion

### Implementation Summary
The implementation follows the original plan exactly:

1. **`lf-vero-prod-hub/main.py`** (+68 lines):
   - Added `clear_hub_schedules()` - async clear without sync
   - Added `get_hub_info_for_schedule_handling()` - lookup hub serial/part number, skip Gen3
   - Modified `removeHubAndChangeStatus` - calls sync for active, clear for non-active

2. **`lf-vero-prod-inventory/main.py`** (+94 lines):
   - Added imports (`os`, `time`, `boto3`)
   - Added environment variables for Lambda function name
   - Added `create_clear_schedules_content()`, `clear_hub_schedules()`, `get_hub_part_numbers_for_serials()`
   - Modified `bulkMoveHubsToInventoryFacility` - clears schedules for each hub

3. **`terraform/lambda-iam-roles.tf`** (+8 lines):
   - Added IAM permission for inventory Lambda to invoke clear schedules Lambda

### What Original Plan Says Is Complete
From the original plan's success criteria:
- [x] Existing unit tests pass
- [x] No Python syntax errors
- [x] Terraform plan shows expected changes

### What Still Needs Manual Verification
- [ ] Lambda deploys successfully
- [ ] Remove hub: Facility A → Facility B with status "active" → hub gets Facility B's schedules
- [ ] Remove hub: Facility A → inventory with status "removed" → schedules cleared
- [ ] Check CloudWatch logs for appropriate schedule handling messages
- [ ] Verify hub removal completes successfully (no regression)
- [ ] Bulk move multiple hubs using Hub Check page
- [ ] Check CloudWatch logs for clear schedules invocations
- [ ] Verify performance is acceptable (should be near-instant due to async invocations)

---

## How It Works (Code Walkthrough)

This section explains the implementation logic for a junior developer. The feature ensures that when hubs are removed or moved from facilities, their schedules are properly handled.

### The Problem Being Solved

When a hub is removed from a facility, it may still have schedule data telling it when to take sensor readings. If we don't clear these schedules:
- **Orphaned hubs** continue trying to follow stale schedules
- **Moved hubs** use the wrong facility's schedule parameters
- This wastes battery and causes incorrect data collection behavior

### Flow 1: Single Hub Removal (`removeHubAndChangeStatus`)

**Location**: `lambdas/lf-vero-prod-hub/main.py:950-998`

**Step-by-step logic:**

```
1. EXTRACT parameters from request
   └── hubId, facilityId, hubStatusId, etc.

2. GET hub info BEFORE the database removal
   └── Call get_hub_info_for_schedule_handling(hubId)
   └── Returns (serial_number, part_number) or (None, None)
   └── Returns None if hub not found OR if it's a Gen3 hub

3. EXECUTE the database removal
   └── Call stored procedure: Transponder_RemoveHubAndChangeFacility

4. IF database succeeded AND we have hub info:
   │
   ├── IF hubStatusId == "1" (Active):
   │   └── Hub is moving to a new facility while still active
   │   └── Call sync_hub_schedules(facilityId, serial, part)
   │   └── This CLEARS old schedules, then SYNCS new facility's schedules
   │
   └── ELSE (Non-active status like "Removed", "RMA", etc.):
       └── Hub is being decommissioned/returned
       └── Call clear_hub_schedules(serial, part)
       └── This ONLY clears schedules (no new ones to sync)

5. CATCH any schedule errors
   └── Log warning but DON'T fail the hub removal
   └── Schedule handling is "best-effort"
```

**Why get hub info BEFORE the DB call?**
The stored procedure may change the hub's facility association, so we need the original data before the change.

**Why the status check?**
- Status "1" = Active → Hub is going to a new customer facility, needs that facility's schedules
- Other statuses = Hub is being removed from service, just needs schedules cleared

### Flow 2: Bulk Move to Inventory (`bulkMoveHubsToInventoryFacility`)

**Location**: `lambdas/lf-vero-prod-inventory/main.py:345-365`

**Step-by-step logic:**

```
1. EXTRACT serial number list from request
   └── Comma-separated string: "SN001,SN002,SN003"

2. GET part numbers for ALL serials BEFORE move
   └── Call get_hub_part_numbers_for_serials(serial_list)
   └── Returns dict: {"SN001": "710-002-XXX", "SN002": "710-002-YYY"}
   └── Gen3 hubs (710-003*) are EXCLUDED from the mapping

3. EXECUTE the database bulk move
   └── Call stored procedure: Inventory_BulkMoveHubsToInventoryFacility

4. IF database succeeded:
   └── FOR EACH hub in the mapping:
       └── Call clear_hub_schedules(serial, part)
       └── Fire-and-forget (async Lambda invoke)
       └── Errors logged but don't fail the bulk move
```

**Why no status check here?**
Bulk move to inventory always means hubs are being decommissioned - they always need schedules cleared, never synced.

### Helper Functions Explained

#### `get_hub_info_for_schedule_handling(transponder_id)`
**Location**: `lambdas/lf-vero-prod-hub/main.py:132-157`

```
INPUT:  transponder_id (the hub's database ID)
OUTPUT: (serial_number, part_number) tuple OR (None, None)

1. Query database for hub's SerialNumber and PartNumber
2. IF no result found → return (None, None)
3. IF part_number starts with "710-003" → Gen3 hub → return (None, None)
4. ELSE → return (serial_number, part_number)
```

**Why skip Gen3?** Gen3 hubs use a different schedule system and don't need this handling.

#### `get_hub_part_numbers_for_serials(serial_number_list)`
**Location**: `lambdas/lf-vero-prod-inventory/main.py:48-83`

```
INPUT:  "SN001,SN002,SN003" (comma-separated string)
OUTPUT: {"SN001": "PN001", "SN002": "PN002"} (dict mapping serial→part)

1. Split input string into list of serials
2. Query database for all matching SerialNumber/PartNumber pairs
3. Build mapping dict, EXCLUDING any Gen3 hubs (710-003*)
4. Return the mapping
```

#### `clear_hub_schedules(serial, part)`
**Location**: Both Lambda files (duplicated)

```
1. Create payload with RequestType="ClearSchedules"
2. Invoke jobs-request-hub-clear-schedules Lambda
3. InvocationType="Event" → async, returns immediately
4. Print response status for logging
```

#### `sync_hub_schedules(facility_id, serial, part)`
**Location**: `lambdas/lf-vero-prod-hub/main.py:51-98`

```
1. Clear existing schedules (same as clear_hub_schedules)
2. Wait 1.5 seconds for clear to process
3. Get the destination facility's sensor schedules
4. FOR EACH sensor schedule at the facility:
   └── Send schedule to the hub via jobs-request-schedule Lambda
```

### Error Handling Philosophy

The implementation uses **"best-effort"** error handling:

- Schedule operations are wrapped in try/except
- Errors are logged with `print(f"Warning: ...")`
- The main operation (hub removal/move) is NOT failed
- Rationale: A hub removal should succeed even if schedule handling fails
  - The hub may be physically removed anyway
  - Stale schedules are inconvenient but not catastrophic
  - Operations can be retried or fixed manually if needed

### Key Decision Points Summary

| Condition | Action | Why |
|-----------|--------|-----|
| Gen3 hub (710-003*) | Skip all schedule handling | Different schedule system |
| Single remove + Active status | Clear + Sync new facility | Hub needs destination's schedules |
| Single remove + Non-active status | Clear only | Hub being decommissioned |
| Bulk move to inventory | Clear only | Always decommissioning |
| Schedule operation fails | Log warning, continue | Best-effort, don't block removal |

---

## Phase 1: Code Quality Review

### Overview
Self-review the code changes for quality, consistency, and potential issues.

### Checklist

#### 1. Code Style & Consistency
- [ ] Verify function naming matches existing patterns in each Lambda
- [ ] Verify new code has NO docstrings (existing code doesn't use them)
- [ ] Verify new code has minimal/no inline comments (existing code relies on print statements)
- [ ] Verify logging statements are consistent with existing patterns
- [ ] Check for any hardcoded values that should be configurable

#### 2. Error Handling
- [ ] Verify try/except blocks don't swallow important errors
- [ ] Check that error messages are informative
- [ ] Verify fire-and-forget pattern is appropriate for all use cases

#### 3. SQL Injection Prevention
- [ ] Review `get_hub_info_for_schedule_handling()` query construction
- [ ] Review `get_hub_part_numbers_for_serials()` query construction
- [ ] Note: Both use parameterized-style building but with f-strings - assess risk

#### 4. Logic Review
- [ ] Verify Gen3 hub detection works correctly (`710-003*` prefix check)
- [ ] Confirm status comparison (`hubStatusId == "1"`) handles string vs int correctly
- [ ] Verify bulk move handles empty list gracefully

### Success Criteria

#### Automated Verification:
- [ ] Python linting passes: `cd lambdas && python -m py_compile lf-vero-prod-hub/main.py lf-vero-prod-inventory/main.py`
- [ ] No Terraform errors: `cd terraform && terraform validate`

#### Manual Verification:
- [ ] All checklist items reviewed and documented

---

## Phase 2: Code Cleanup (If Needed)

### Overview
Address any issues found during the Phase 1 review.

### Potential Cleanup Items

#### 1. Code Style Consistency - Remove Docstrings and Comments (Required)

The new code includes docstrings and inline comments, but the existing codebase style uses neither. The existing pattern relies on descriptive `print()` statements which serve as both documentation and runtime logging.

**Files and changes needed:**

**`lambdas/lf-vero-prod-hub/main.py`:**
- Remove docstring from `clear_hub_schedules()` (lines 113-117)
- Remove docstring from `get_hub_info_for_schedule_handling()` (lines 133-136)
- Remove inline comment `# Async, returns immediately` (line 127)
- Remove inline comment `# Skip Gen3 hubs (part numbers starting with "710-003")` (line 152)

**`lambdas/lf-vero-prod-inventory/main.py`:**
- Remove docstring from `create_clear_schedules_content()` (line 19)
- Remove docstring from `clear_hub_schedules()` (lines 30-33)
- Remove docstring from `get_hub_part_numbers_for_serials()` (lines 49-53)
- Remove inline comment `# Async, returns immediately` (line 43)
- Remove inline comment `# Parse comma-separated list` (line 57)
- Remove inline comment `# Build IN clause` (line 62)
- Remove inline comment `# Build mapping, excluding Gen3` (line 73)

**Rationale:** New code should blend in with existing patterns. The existing Lambdas have zero docstrings and minimal comments - they use `print()` statements for context.

#### 2. SQL Query Safety Enhancement (Recommended)
The current implementation uses f-strings for SQL queries. While the input comes from database results (TransponderID, SerialNumber), this could be improved:

**File**: `lambdas/lf-vero-prod-hub/main.py`
**Current** (line ~135):
```python
query = f"""
    SELECT t.SerialNumber, p.PartNumber
    FROM Transponder t
    JOIN Part p ON t.PartID = p.PartID
    WHERE t.TransponderID = {transponder_id}
"""
```

**Consideration**: `transponder_id` comes from `jsonBody.get("hubId")` which is user input. Should validate it's numeric.

**File**: `lambdas/lf-vero-prod-inventory/main.py`
**Current** (line ~70):
```python
serial_in = ",".join([f"'{s}'" for s in serials])
```

**Consideration**: `serials` comes from comma-split of `jsonBody["ssnlist"]`. Should sanitize input.

#### 2. Duplicate Code Consideration
`create_clear_schedules_content()` and `clear_hub_schedules()` are duplicated between:
- `lf-vero-prod-hub/main.py`
- `lf-vero-prod-inventory/main.py`

**Decision**: Accept duplication for now - these Lambdas don't share a common module, and the functions are small. Future refactoring could extract to a shared layer.

### Success Criteria

#### Automated Verification:
- [ ] All changes pass linting
- [ ] Tests still pass after cleanup

#### Manual Verification:
- [ ] Cleanup changes reviewed

---

## Phase 3: Deploy to Dev Environment

### Overview
Deploy the changes to the dev environment for functional testing.

### Steps

1. **Push branch to remote** (if not already):
   ```bash
   git push -u origin IWA-13768
   ```

2. **Trigger dev deployment**:
   - The branch push workflow (`.github/workflows/wflow-branch-push-dev.yml`) should auto-deploy
   - Monitor GitHub Actions for successful deployment

3. **Verify deployment**:
   - Check AWS Lambda console for updated function code
   - Verify IAM policy was applied to inventory Lambda

### Success Criteria

#### Automated Verification:
- [ ] GitHub Actions workflow completes successfully
- [ ] Lambda functions show recent deployment timestamp

#### Manual Verification:
- [ ] Lambda function code visible in AWS console
- [ ] IAM permissions visible in Lambda configuration

---

## Phase 4: Functional Testing in Dev

### Overview
Test all scenarios from the original plan's test matrix.

### Test Scenarios

#### Scenario 1: Single Hub Removal - Active Status to New Facility
**Steps**:
1. Identify a test hub currently assigned to Facility A
2. Use the UI to remove hub from Facility A → Facility B with status "Active"
3. Check CloudWatch logs for `sync_hub_schedules` call

**Expected**:
- Hub removal succeeds
- CloudWatch shows schedule sync to Facility B
- Hub receives Facility B's schedules

#### Scenario 2: Single Hub Removal - Non-Active Status to Inventory
**Steps**:
1. Identify a test hub currently assigned to a customer facility
2. Use the UI to remove hub to inventory with status "Removed"
3. Check CloudWatch logs for `clear_hub_schedules` call

**Expected**:
- Hub removal succeeds
- CloudWatch shows schedule clear (fire-and-forget)
- Hub schedules are cleared

#### Scenario 3: Bulk Move to Inventory
**Steps**:
1. Navigate to Hub Check page
2. Select 3+ test hubs
3. Perform bulk move to inventory facility

**Expected**:
- Bulk move completes successfully
- CloudWatch shows `clear_hub_schedules` for each non-Gen3 hub
- Operation completes quickly (async invocations)

#### Scenario 4: Gen3 Hub Handling
**Steps**:
1. Identify a Gen3 hub (part number starts with 710-003)
2. Remove it using either single or bulk operation

**Expected**:
- Removal succeeds
- CloudWatch shows "Skipping schedule handling for Gen3 hub" message
- No clear schedules Lambda invocation

#### Scenario 5: Error Handling - Schedule Failure
**Steps**:
1. (If possible) Temporarily break the clear schedules Lambda
2. Perform a hub removal operation

**Expected**:
- Hub removal still succeeds
- Warning logged but operation not failed

### Success Criteria

#### Automated Verification:
- N/A (manual testing)

#### Manual Verification:
- [ ] All 5 test scenarios pass
- [ ] CloudWatch logs show expected behavior
- [ ] No regressions in hub removal functionality

---

## Phase 5: Self PR Review

### Overview
Perform a thorough self-review before requesting formal review.

### PR Review Checklist

#### Code Quality
- [ ] Code follows project conventions
- [ ] No unnecessary code changes
- [ ] Error handling is appropriate
- [ ] Logging is sufficient for debugging

#### Testing
- [ ] Manual testing completed and documented
- [ ] Edge cases considered (empty lists, Gen3 hubs, errors)
- [ ] No regression in existing functionality

#### Documentation
- [ ] Commit message is clear and includes ticket reference
- [ ] Code has appropriate inline comments
- [ ] Implementation plan exists and matches code

#### Security
- [ ] No secrets or credentials exposed
- [ ] SQL queries use safe patterns
- [ ] IAM permissions are minimally scoped

#### Performance
- [ ] Async operations used appropriately
- [ ] No N+1 query issues
- [ ] Bulk operations handle large datasets

### PR Description Template
```markdown
## Summary
- Clear hub schedules when removing/moving hubs from facilities
- Prevents orphaned hubs from continuing to take readings with stale schedule parameters

## Changes
- `lf-vero-prod-hub/main.py`: Added schedule handling to single hub removal
- `lf-vero-prod-inventory/main.py`: Added schedule clearing to bulk hub moves
- `terraform/lambda-iam-roles.tf`: Added IAM permission for inventory Lambda

## Test Plan
- [x] Tested single hub removal with active status → new facility schedules sync
- [x] Tested single hub removal with non-active status → schedules cleared
- [x] Tested bulk move → schedules cleared for all hubs
- [x] Verified Gen3 hubs are skipped
- [x] Verified error handling doesn't break removals

## References
- Ticket: IWA-13768
- Implementation Plan: `thoughts/shared/plans/2026-01-14-IWA-13768-clear-hub-schedules-on-removal.md`
```

### Success Criteria

#### Automated Verification:
- [ ] All CI checks pass
- [ ] No merge conflicts with target branch

#### Manual Verification:
- [ ] All PR checklist items complete
- [ ] PR description is complete and accurate

---

## Phase 6: Create and Submit PR

### Overview
Create the pull request and prepare for review.

### Steps

1. **Rebase on latest master** (if needed):
   ```bash
   git fetch origin master
   git rebase origin/master
   ```

2. **Create PR**:
   ```bash
   gh pr create --title "IWA-13768: Clear hub schedules when removing/moving hubs" --body "..."
   ```

3. **Add reviewers and labels**

4. **Link to Jira ticket**

### Success Criteria

#### Automated Verification:
- [ ] PR created successfully
- [ ] CI pipeline passes

#### Manual Verification:
- [ ] PR linked to Jira ticket
- [ ] Reviewers assigned

---

## References

- Original implementation plan: `thoughts/shared/plans/2026-01-14-IWA-13768-clear-hub-schedules-on-removal.md`
- Schedule system research: `thoughts/shared/research/2026-01-12-sensor-schedule-system-comprehensive.md`
- Hub removal flows: `thoughts/shared/research/2025-01-25-hub-hotspot-facility-transfer-flows.md`
