# Unlicensed CradlePoint Status Implementation Plan

## Overview

Add an "Unlicensed" status to CradlePoint devices to:
1. Clearly identify devices whose NetCloud license has expired
2. Display "N/A (Unlicensed)" in the online status column instead of stale data
3. Allow facility movements to non-Live/non-Pending Install facilities for unlicensed devices

## Quick Summary

### Implementation Phases

| Phase | Description | Key Files |
|-------|-------------|-----------|
| **1** | Add "Unlicensed" (ID 5) to `FacilityCradlepointDeviceStatus` | Migration script, init_enum_tables.sql |
| **2** | Frontend: Add enum value, update Online Status to show "N/A (Unlicensed)" | FacilityHardwareStatus.ts, ColumnDefs.tsx |
| **3** | Lambda: Add detection logic (`is_device_unlicensed`, `can_receive_unlicensed_device`) | main.py |
| **4** | New stored procedure for moving unlicensed devices | Cradlepoint_MoveUnlicensedDevice.sql |

### Key Decisions

1. **Status Table**: Use `FacilityCradlepointDeviceStatus` (ID 5 = "Unlicensed") - this is what's displayed in the UI "Status" column
2. **Facility Restriction**: Block movements to "Live Customer" (1) and "Pending Install" (9) only - allow all other facility statuses
3. **Detection Logic**: If device has `ExternalCradlepointID` in our DB but NetCloud returns empty → it's unlicensed (not "not found")

---

## Key Decision: Which Status Table?

**Use `FacilityCradlepointDeviceStatus`** (not `CradlepointDeviceStatus`) because:
- It's what's displayed in the UI "Status" column (`cpStatus` field)
- It has consistent frontend usage throughout the codebase
- It's the table queried by `getFacilityCradlepointStatus` Lambda method
- Current values: Assigned (1), Removed (2), Ready to Install (3), In Transit to HQ (4)
- New value: **Unlicensed (5)**

## Current State Analysis

### How It Works Today (Fails for Unlicensed Devices)

**File**: `lambdas/lf-vero-prod-cradlepoint/main.py:861-875`

```python
# addBulkFacilityCradlepoints - FAILS FAST on unlicensed devices
elif meth == "addBulkFacilityCradlepoints":
    for i in range(len(inCPList)):
        macCP = str(inCPList[i])
        old_cp_data = get_cradlepoint_data(macCP)  # Returns None for unlicensed

        if old_cp_data is None:
            statusCode = 404
            retVal = cradlepoint_not_found_error  # "No Cradlepoint data found or unlisted in Netcloud"
            return cradlepoint_not_found_response()  # BLOCKS THE OPERATION
```

**File**: `lambdas/lf-vero-prod-cradlepoint/main.py:175-188`

```python
def get_cradlepoint_data(MAC):
    cp_url = "https://cradlepointecm.com/api/v2/routers/?expand=group&mac=" + apiMAC
    cradlepoint_data = common_resources.CallAPI(...)

    # PROBLEM: Returns None for BOTH unlicensed AND invalid MAC addresses
    if cradlepoint_data["data"] is None or len(cradlepoint_data["data"]) == 0:
        return None  # Cannot distinguish unlicensed from invalid

    return cradlepoint_data["data"][0]
```

### How EASE/3PL Handles It (Continues Despite Failures)

**File**: `lambdas/lf-vero-prod-cradlepoint/main.py:1043-1087`

```python
# updateNetcloudCradlepointFacility - Continues processing, tracks failures
elif meth == "updateNetcloudCradlepointFacility":
    successful_count = 0
    failed_count = 0
    failed_macs = []

    for i in range(len(inCPList)):
        old_cp_data = get_cradlepoint_data(macCP)

        if old_cp_data is None:
            failed_count += 1
            failed_macs.append(macCP)
            continue  # CONTINUES with other devices instead of failing

        update_response = update_cradlepoint(old_cp_data["id"], ...)

    # Returns partial success (207) if some failed
    if "aw-3pl-scheduled-jobs" in usergroup:
        if failed_count == 0:
            retVal = {"status": "success", ...}
        elif successful_count == 0:
            retVal = {"status": "failed", ...}
        else:
            retVal = {"status": "partial_success", ...}  # 207 Multi-Status
```

### Current Status Display

**File**: `frontend/src/components/CustomerDetailPage/Hotspots/ColumnDefs.tsx:41-65`

```typescript
// Online Status column - shows "Online" or "Offline" from NetCloud State field
{
  headerName: "Hotspot Online Status",
  field: "State",  // Contains "online", "offline", etc. from NetCloud
  cellClassRules: {
    "grid-cell-critical": ({ value }) => value.toLowerCase() !== "online",
  },
  valueFormatter: ({ value }) => toTitleCase(value) ?? "",
},

// Status column - shows "Assigned", "Ready to Install", etc.
{
  headerName: "Status",
  field: "cpStatus",  // From FacilityCradlepointDeviceStatus table
},
```

## Desired End State

### Status Column Display

| Current Status | New Status |
|----------------|------------|
| Assigned | Assigned |
| Ready to Install | Ready to Install |
| In Transit to HQ | In Transit to HQ |
| (none for unlicensed) | **Unlicensed** |

### Online Status Column Display

| Scenario | Current Display | New Display |
|----------|-----------------|-------------|
| Licensed, Online | "Online" | "Online" |
| Licensed, Offline | "Offline" | "Offline" |
| Unlicensed | Stale "Offline" | **"N/A (Unlicensed)"** |

### Facility Movement Behavior

| Movement Type | Current | New |
|---------------|---------|-----|
| Unlicensed → Inventory | BLOCKED | ALLOWED |
| Unlicensed → Customer | BLOCKED | BLOCKED (correct) |

## What We're NOT Doing

- Adding automatic license status sync from NetCloud (no such API exists)
- Modifying the EASE/3PL flow (already handles failures gracefully)
- Changing how licensed devices are handled
- Adding license procurement or renewal features

## Implementation Approach

The key insight: **If a device exists in our DB with an `ExternalCradlepointID`, it was previously licensed.** If NetCloud now returns empty for that MAC, we can confidently mark it as "Unlicensed" (not "Not Found").

```python
def diagnose_netcloud_failure(mac_address, device_record):
    """
    Distinguish unlicensed from truly not found.

    Returns:
        "UNLICENSED" - Device was licensed before (has ExternalCradlepointID), license expired
        "NOT_FOUND" - Device never synced with NetCloud (unknown device)
    """
    if device_record is None:
        return "NOT_FOUND"  # Not in our DB at all

    if device_record.ExternalCradlepointID is not None:
        return "UNLICENSED"  # Had NetCloud ID before, license expired
    else:
        return "NOT_FOUND"  # In DB but never synced (shouldn't happen normally)
```

---

## Phase 1: Database Schema Changes

### Overview
Add the "Unlicensed" status to `FacilityCradlepointDeviceStatus` table (the one displayed in UI).

### Changes Required

#### 1. Add FacilityCradlepointDeviceStatus Value

**File**: `mysql/db/table_change_scripts/V000000XXX__Add_Unlicensed_Status.sql`

```sql
-- Add "Unlicensed" to FacilityCradlepointDeviceStatus (facility assignment status)
CREATE PROCEDURE FacilityCradlepointDeviceStatus_Add_Unlicensed()
BEGIN
    IF NOT EXISTS(SELECT * FROM FacilityCradlepointDeviceStatus WHERE FacilityCradlepointDeviceStatusID = 5) THEN
        INSERT INTO FacilityCradlepointDeviceStatus (FacilityCradlepointDeviceStatusID, FacilityCradlepointDeviceStatusName)
        VALUES (5, 'Unlicensed');
    END IF;
END;

CALL FacilityCradlepointDeviceStatus_Add_Unlicensed();
DROP PROCEDURE IF EXISTS FacilityCradlepointDeviceStatus_Add_Unlicensed;
```

#### 2. Update Test DB Init Script

**File**: `lambdas/tests/db/dockerDB/init_scripts/init_enum_tables.sql`

```sql
-- Update line 241 to include Unlicensed status
INSERT INTO `FacilityCradlepointDeviceStatus` VALUES (1,'Assigned'),(2,'Removed'),(3,'Ready to Install'),(4,'In Transit to HQ'),(5,'Unlicensed');
```

### Success Criteria

#### Automated Verification:
- [ ] Migration runs without errors: `make migrate`
- [ ] Test DB initializes correctly

#### Manual Verification:
- [ ] Query confirms new status exists: `SELECT * FROM CradlepointDeviceStatus`

---

## Phase 2: Frontend Enum and Type Updates

### Overview
Add the Unlicensed status to frontend enums and update the online status display logic.

### Changes Required

#### 1. Add Enum Value

**File**: `frontend/src/shared/enums/FacilityHardwareStatus.ts`

```typescript
// Update FacilityHotspotStatus to include Unlicensed
export enum FacilityHotspotStatus {
  ASSIGNED = 1,
  REMOVED = 2,
  READY_TO_INSTALL = 3,
  IN_TRANSIT_TO_HQ = 4,
  UNLICENSED = 5,  // NEW
}
```

#### 2. Update Column Definitions for Online Status

**File**: `frontend/src/components/CustomerDetailPage/Hotspots/ColumnDefs.tsx`

```typescript
import { FacilityHotspotStatus } from "@shared/enums/FacilityHardwareStatus";

// Update the Hotspot Online Status column (around line 41-52)
{
  headerName: "Hotspot Online Status",
  field: "State",
  sort: "asc" as const,
  cellClassRules: {
    "grid-cell-critical": function ({
      data,
      value,
    }: {
      data: Hotspot;
      value: string;
    }) {
      if (data.cpStatusId === FacilityHotspotStatus.UNLICENSED) {
        return false;
      }
      return value.toLowerCase() !== "online";
    },
  },
  valueFormatter: ({ data, value }: { data: Hotspot; value: string }) => {
    if (data.cpStatusId === FacilityHotspotStatus.UNLICENSED) {
      return "N/A (Unlicensed)";
    }
    return toTitleCase(value) ?? "";
  },
},
```

#### 3. Update Hotspot Type (if needed)

**File**: `frontend/src/shared/types/hotspots/Hotspot.ts`

```typescript
// Verify cpStatusId exists (may need to add if not present)
export type Hotspot = {
  // ... existing fields ...
  cpStatus: string;        // Status name ("Assigned", "Ready to Install", etc.)
  cpStatusId?: number;     // Status ID - ADD if not present (links to FacilityCradlepointDeviceStatus)
  // ... existing fields ...
};
```

#### 4. Update SQL Query to Return Status ID

**File**: `mysql/db/procs/R__PROC_Cradlepoint_GetCradlepointDevices.sql`

```sql
-- Add to the SELECT list (near the cpStatus field around line 174)
fcds.FacilityCradlepointDeviceStatusName AS cpStatus,
fcds.FacilityCradlepointDeviceStatusID AS cpStatusId,  -- NEW
```

### Success Criteria

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npm run typecheck`
- [ ] Linting passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] Column displays "N/A (Unlicensed)" for test data with status ID 5

---

## Phase 3: Backend Lambda Changes

### Overview
Update the Lambda to:
1. Detect unlicensed devices (was licensed, now returns empty from NetCloud)
2. Allow facility movements to inventory for unlicensed devices
3. Set the Unlicensed status when detected

### Changes Required

#### 1. Add Helper to Check if Device Was Previously Licensed

**File**: `lambdas/lf-vero-prod-cradlepoint/main.py`

```python
# Add after line 188 (after get_cradlepoint_data function)

def get_device_from_db(mac_address, request_id, cognito_id):
    """Check if device exists in our database and has been synced with NetCloud before."""
    sql = f"""
        SELECT CradlepointDeviceID, ExternalCradlepointID, CradlepointDeviceStatusID
        FROM CradlepointDevice
        WHERE MAC = '{mac_address}'
    """
    result = db.mysql_read(sql, request_id, "get_device_from_db", cognito_id)
    if result and len(result) > 0:
        return result[0]
    return None


def is_device_unlicensed(mac_address, request_id, cognito_id):
    """Check if a device that returns None from NetCloud is actually unlicensed."""
    device = get_device_from_db(mac_address, request_id, cognito_id)
    if device is None:
        return False

    return device.get("ExternalCradlepointID") is not None


def mark_device_unlicensed(mac_address, request_id, cognito_id):
    """Update device status to Unlicensed (FacilityCradlepointDeviceStatus ID 5)."""
    sql = f"""
        UPDATE CradlepointDevice
        SET CradlepointDeviceStatusID = 5, DateUpdated = UTC_TIMESTAMP()
        WHERE MAC = '{mac_address}'
    """
    db.mysql_write(sql, request_id, "mark_device_unlicensed", cognito_id)
```

#### 2. Update addBulkFacilityCradlepoints to Allow Inventory Movements

**File**: `lambdas/lf-vero-prod-cradlepoint/main.py`

```python
# Modify the addBulkFacilityCradlepoints method (around line 861)

elif meth == "addBulkFacilityCradlepoints":
    removalReasonTypeID = jsonBody.get("removalReasonTypeID", 0)
    target_facility_id = jsonBody["extfid"]

    # Check if target facility can receive unlicensed devices
    allow_unlicensed = can_receive_unlicensed_device(target_facility_id, requestId, cognito_id)

    inCPList = str(jsonBody["mac"]).split(",")

    for i in range(len(inCPList)):
        macCP = str(inCPList[i])
        old_cp_data = get_cradlepoint_data(macCP)

        if old_cp_data is None:
            # Check if this is an unlicensed device we can move to non-live facility
            if not allow_unlicensed or not is_device_unlicensed(macCP, requestId, cognito_id):
                statusCode = 404
                retVal = cradlepoint_not_found_error
                return cradlepoint_not_found_response()

            # Unlicensed device moving to allowed facility - process it
            mark_device_unlicensed(macCP, requestId, cognito_id)

            args = (
                macCP,
                target_facility_id,
                removalReasonTypeID,
                jsonBody.get("notes", ""),
                cognito_id,
            )
            retVal = db.mysql_call_proc(
                "Cradlepoint_MoveUnlicensedDevice",
                args,
                requestId,
                cognito_id,
                allow_write=True,
            )
            continue

        # ... rest of existing code for licensed devices ...
```

#### 3. Add Facility Status Check Helper

**File**: `lambdas/lf-vero-prod-cradlepoint/main.py`

```python
# Add helper function to check if facility allows unlicensed device movements
# Based on FacilityStatus table - block only "Live Customer" (1) and "Pending Install" (9)

BLOCKED_FACILITY_STATUS_IDS = [1, 9]  # Live Customer, Pending Install

def can_receive_unlicensed_device(facility_id, request_id, cognito_id):
    """Check if the target facility can receive unlicensed devices."""
    sql = f"""
        SELECT fs.FacilityStatusID
        FROM Facility f
        JOIN FacilityStatus fs ON f.FacilityStatusID = fs.FacilityStatusID
        WHERE f.ExternalFacilityID = '{facility_id}'
    """
    result = db.mysql_read(sql, request_id, "can_receive_unlicensed_device", cognito_id)
    if not result or len(result) == 0:
        return False

    facility_status_id = result[0].get("FacilityStatusID")
    return facility_status_id not in BLOCKED_FACILITY_STATUS_IDS
```

### Success Criteria

#### Automated Verification:
- [ ] Lambda deploys without errors
- [ ] Unit tests pass (if any exist)

#### Manual Verification:
- [ ] Unlicensed device can be moved to inventory facility
- [ ] Unlicensed device still blocked from customer facility
- [ ] Device status updates to "Unlicensed" in database

---

## Phase 4: New Stored Procedure for Unlicensed Movement

### Overview
Create a stored procedure that moves an unlicensed device without requiring NetCloud data.

### Changes Required

**File**: `mysql/db/procs/R__PROC_Cradlepoint_MoveUnlicensedDevice.sql`

```sql
USE `Vero`;
DROP procedure IF EXISTS `Cradlepoint_MoveUnlicensedDevice`;

DELIMITER ;;
CREATE PROCEDURE `Cradlepoint_MoveUnlicensedDevice`(
    IN inMAC VARCHAR(50),
    IN inExternalFacilityID VARCHAR(100),
    IN inRemovalReasonTypeID INT,
    IN inNotes VARCHAR(3000),
    IN inCognitoID VARCHAR(100)
)
BEGIN
    DECLARE localCradlepointDeviceID INT;
    DECLARE localFacilityID INT;
    DECLARE localOldFacilityCradlepointID INT;
    DECLARE localUserID INT;

    SET localUserID = (SELECT UserID FROM Users WHERE CognitoID = inCognitoID);

    SELECT CradlepointDeviceID INTO localCradlepointDeviceID
    FROM CradlepointDevice
    WHERE MAC = inMAC
    LIMIT 1;

    SELECT FacilityID INTO localFacilityID
    FROM Facility
    WHERE ExternalFacilityID = inExternalFacilityID
    LIMIT 1;

    SELECT FacilityCradlePointID INTO localOldFacilityCradlepointID
    FROM Facility_CradlepointDevice
    WHERE CradlePointDeviceID = localCradlepointDeviceID
      AND FacilityCradlepointStatusID <> 2
    ORDER BY FacilityCradlePointID DESC
    LIMIT 1;

    START TRANSACTION;

    -- Mark old facility assignment as removed
    IF localOldFacilityCradlepointID IS NOT NULL THEN
        UPDATE Facility_CradlepointDevice
        SET FacilityCradlepointStatusID = 2,
            DateUpdated = UTC_TIMESTAMP(),
            RemovalReasonTypeID = inRemovalReasonTypeID,
            UserID = localUserID
        WHERE FacilityCradlePointID = localOldFacilityCradlepointID;
    END IF;

    -- Clear GroupName on device (no longer valid without license)
    UPDATE CradlepointDevice
    SET GroupName = NULL,
        DateUpdated = UTC_TIMESTAMP()
    WHERE CradlepointDeviceID = localCradlepointDeviceID;

    -- Create new facility assignment with Unlicensed status
    INSERT INTO Facility_CradlepointDevice (
        CradlePointDeviceID,
        FacilityID,
        Notes,
        DateCreated,
        DateUpdated,
        FacilityCradlepointStatusID,
        UserID
    ) VALUES (
        localCradlepointDeviceID,
        localFacilityID,
        inNotes,
        UTC_TIMESTAMP(),
        UTC_TIMESTAMP(),
        5,
        localUserID
    );

    COMMIT;

    SELECT 'SUCCESS' AS result;
END;;
DELIMITER ;
```

### Success Criteria

#### Automated Verification:
- [ ] Procedure creates without errors: `make migrate`

#### Manual Verification:
- [ ] Calling procedure moves device and updates status correctly

---

## Testing Strategy

### Unit Tests
- Test `is_device_unlicensed()` with various scenarios
- Test `can_receive_unlicensed_device()` with different facility statuses
- Test that licensed devices still work normally

### Integration Tests
1. **Unlicensed device to Inventory facility**: Should succeed
2. **Unlicensed device to Churned facility**: Should succeed
3. **Unlicensed device to Live Customer facility**: Should fail with clear error
4. **Unlicensed device to Pending Install facility**: Should fail with clear error
5. **Licensed device flow**: Should work unchanged
6. **Never-synced device**: Should fail as "Not Found" (not "Unlicensed")

### Manual Testing Steps
1. Find a hotspot with `ExternalCradlepointID` in the DB
2. Simulate unlicensed by having NetCloud return empty (use test MAC not in NetCloud)
3. Attempt to move to inventory facility → Should succeed
4. Verify status shows "Unlicensed" in Status column
5. Verify Online Status shows "N/A (Unlicensed)"
6. Attempt to move to customer facility → Should fail

## Summary: Current vs Proposed Flow

### Current Flow (Fails)

```
1. User initiates facility movement
2. Lambda calls get_cradlepoint_data(MAC)
3. NetCloud returns empty [] (unlicensed)
4. get_cradlepoint_data returns None
5. Lambda returns 404: "No Cradlepoint data found or unlisted"
6. USER IS BLOCKED ❌
```

### Proposed Flow (Works for Non-Live/Non-Pending Facilities)

```
1. User initiates facility movement
2. Lambda calls get_cradlepoint_data(MAC)
3. NetCloud returns empty [] (unlicensed)
4. get_cradlepoint_data returns None
5. Lambda checks: is this device in our DB with ExternalCradlepointID?
   - YES: Device is UNLICENSED (was licensed before)
   - NO: Device is NOT FOUND (never synced)
6. Lambda checks target facility status:
   - "Live Customer" (1) or "Pending Install" (9) → BLOCKED
   - Any other status (Inventory, Churned, etc.) → ALLOWED
7. If UNLICENSED and target allows unlicensed:
   a. Update FacilityCradlepointDeviceStatus to Unlicensed (5)
   b. Skip NetCloud update (can't update unlicensed device)
   c. Update database with new facility assignment
   d. USER SUCCEEDS ✅
8. If UNLICENSED and target is Live/Pending:
   - Return error: "Device is unlicensed, cannot assign to live customer"
   - USER IS BLOCKED (correctly) ❌
```

## References

- Research document: `thoughts/shared/research/2026-01-20-unlicensed-cradlepoint-facility-movement.md`
- Related: `thoughts/shared/research/2026-01-08-netcloud-groups-management.md`
- Lambda code: `lambdas/lf-vero-prod-cradlepoint/main.py`
- Frontend columns: `frontend/src/components/CustomerDetailPage/Hotspots/ColumnDefs.tsx`
