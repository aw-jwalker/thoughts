---
date: 2026-01-05T09:42:34-05:00
researcher: Claude
git_commit: bf9f8b9946e034c4f98b60c5f99311ca8e9db637
branch: dev
repository: AssetWatch1/fullstack.assetwatch
topic: "Track Inventory Page - Moving Hubs, Hotspots, and Enclosures"
tags: [research, codebase, track-inventory, hubs, hotspots, enclosures, transponders, cradlepoints]
status: complete
last_updated: 2026-01-05
last_updated_by: Claude
---

# Research: Track Inventory Page - Moving Hubs, Hotspots, and Enclosures

**Date**: 2026-01-05T09:42:34-05:00
**Researcher**: Claude
**Git Commit**: bf9f8b9946e034c4f98b60c5f99311ca8e9db637
**Branch**: dev
**Repository**: AssetWatch1/fullstack.assetwatch

## Research Question

Document the functionality of the Track Inventory page as it relates to moving hubs (transponders), hotspots (cradlepoints), and enclosures (containing a hub and hotspot). Understand the business logic, assumptions, and full-stack flow from stored procedures up to frontend to establish a baseline for future bug fixes.

## Summary

The Track Inventory page is a comprehensive inventory management system that tracks **hubs (transponders)**, **hotspots (cradlepoints)**, and **enclosures** across facilities. The system supports:

1. **Adding inventory** to facilities with status tracking (Spare, In Transit, Ready to Install)
2. **Moving inventory** between facilities with full audit trails
3. **Enclosure assembly** - linking hubs and hotspots into physical enclosures
4. **Hardware issue tracking** - recording removal reasons and creating issue tickets

The architecture follows a standard pattern: **Frontend Form → API Service → Lambda Handler → Stored Procedure → Database**

## Terminology Mapping

| User-Facing Term | Database/Code Term | Table |
|------------------|-------------------|-------|
| Hub | Transponder | `Transponder` |
| Hotspot | CradlepointDevice | `CradlepointDevice` |
| Enclosure | Enclosure | `Enclosure` |
| Sensor | Receiver | `Receiver` |

## Detailed Findings

### 1. Frontend Components

#### Main Page Component
**File:** `frontend/src/pages/TrackInventory.tsx`

The main page displays a facility inventory summary with:
- DataTable showing: Facility, Customer, Product Type, Part Number, Part Version, Rev, In Transit count, Spare count, Ready to Install count
- Toggle between "AssetWatch" and "Customer" inventory views
- Modal for viewing serial number details when clicking counts
- CSV export capability
- Pagination (page size 250)

#### Header Form Component (Add Inventory)
**File:** `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx` (1,294 lines)

This is the primary form for adding inventory items. Key features:

**Part Selection Logic:**
- Grouped dropdown options: Hub v2, PBSM v2, Hub v3, Enclosures
- Part selection determines available status options and validation rules

**Dynamic Status Options by Product Type:**
| Product Type | Available Statuses |
|--------------|-------------------|
| Hub (standalone) | Spare, In Transit |
| Hotspot (standalone) | Spare, In Transit |
| Sensor | Spare, In Transit, Ready to Install |
| Enclosure | Ready to Install, In Transit |

**Serial Number Validation:**
- Duplicate detection across input
- Format validation per hardware type
- Enclosure part number prefix matching (e.g., "100-006" prefix validation)
- Checks for already-active hardware conflicts

**Conditional Form Fields:**
- **Funding Project**: Optional with confirmation modal for changes
- **Removal Reason**: Shown when hardware is being reassigned
- **Enclosure Type**: For Hub v2 only
- **Hotspot Group**: For Cradlepoints and Hub-Hotspot enclosures
- **Revision Selection**: For sensors (PBSM) - restricted to SupplyChain/Engineering roles

#### Submission Hook
**File:** `frontend/src/components/TrackInventoryPage/useTrackInventorySubmit.ts`

Four mutation paths based on hardware type:
```typescript
addHubsMutation      → addBulkSerialNumbersForHubs
addEnclosuresMutation → addBulkSerialNumbersForEnclosures
addSensorsMutation   → addBulkSerialNumbersForSensors
addCradlePointMutation → addBulkCradlePointDevices
```

Post-submit actions:
- Success toast notification
- Query invalidation to refresh inventory display
- Hardware issue creation if removal reason selected

### 2. API Services Layer

#### InventoryService
**File:** `frontend/src/shared/api/InventoryService.ts`

**Read Operations:**
| Method | Purpose |
|--------|---------|
| `getSpareInTransitInventory(type)` | Fetch inventory summary by type |
| `getInventorySerialNumberList(params)` | Get serial numbers for selected inventory |
| `checkInventorySerialNumbers(list, partId)` | Validate serial numbers exist |
| `getInventoryFundingProjects()` | Fetch funding project options |
| `getPartRevisionList()` | Fetch part revision options |

**Write Operations:**
| Method | Purpose |
|--------|---------|
| `addBulkSerialNumbersForHubs(values)` | Add hubs to inventory |
| `addBulkSerialNumbersForEnclosures(values)` | Add enclosures to inventory |
| `addBulkSerialNumbersForSensors(values)` | Add sensors to inventory |
| `bulkMoveHubsToInventoryFacility(snList, fid)` | Move hubs between facilities |
| `bulkMoveSensorsToInventoryFacility(snList, fid)` | Move sensors between facilities |

#### CradlePointService
**File:** `frontend/src/shared/api/CradlePointService.ts`

| Method | Purpose |
|--------|---------|
| `checkCradlepointAvailability(macAddresses)` | Check if devices are assigned |
| `getHubHotspotEnclosureInfo(hubSerialList, cpMacList)` | Get enclosure pairing info |
| `addBulkCradlePointDevices(values)` | Add multiple cradlepoints |
| `updateNetcloudCradlepointFacility()` | Move cradlepoint to new facility |

#### HubService
**File:** `frontend/src/shared/api/HubService.ts`

| Method | Purpose |
|--------|---------|
| `checkActiveHubs(hubList)` | Check if hubs are in use |
| `getEnclosureHubsBySerial(hubList)` | Get enclosure info for hubs |

### 3. Lambda Functions

#### Inventory Lambda
**File:** `lambdas/lf-vero-prod-inventory/main.py`

**Key Methods for Moving Inventory:**

```python
# Add hubs to inventory with optional enclosure
addBulkHubsToInventory(
    hubSerialNumberList,  # Comma-separated
    facilityId,
    hubStatusId,
    partId,
    fundingProjectId,
    removalReasonTypeId,  # Optional
    enclosurePartId       # Optional
)

# Add enclosures to inventory
addBulkSerialNumbersForEnclosures(
    enclosureSerialNumberList,
    facilityId,
    partId,
    facilityEnclosureStatusId,
    fundingProjectId,
    groupName,            # NetCloud group
    removalReasonTypeId   # Optional
)

# Move hubs between facilities
bulkMoveHubsToInventoryFacility(
    ssnlist,              # Serial number list
    fid,                  # Target facility ID
)

# Move sensors between facilities
bulkMoveSensorsToInventoryFacility(
    ssnlist,
    fid,
    removalReasonTypeID   # Optional
)
```

#### Hub Lambda
**File:** `lambdas/lf-vero-prod-hub/main.py`

**Critical Method for Complex Moves:**

```python
# Move hub AND its enclosure AND hotspot together
removeHubAndChangeStatus(
    hubId,
    facilityId,           # New facility
    hubStatusId,          # New status
    removalReasonTypeId,
    enclosureId,          # If hub is in enclosure
    enclosureHotspotId,   # If enclosure has hotspot
    enclosureHotspotStatusId,
    groupName             # NetCloud group for hotspot
)
```

This is the most complex operation - it coordinates moving all three components together.

#### Cradlepoint Lambda
**File:** `lambdas/lf-vero-prod-cradlepoint/main.py`

```python
# Add multiple cradlepoints to inventory
addBulkCradlepoints(
    macAddresses,
    extfacilityId,
    groupURL,             # NetCloud group
    cradlePointStatusId,
    fundingProjectId,
    partId,
    removalReasonTypeId
)

# Move enclosures to new facility
cpEnclosureUpdateFacility(
    enclosureIdList,
    fid,
    facilityEnclosureStatusId,
    removalReasonId
)

# Update cradlepoint facility assignment
updateNetcloudCradlepointFacility(
    macAddresses,
    externalFacilityID,
    groupURL
)
```

### 4. Stored Procedures

#### Hub Movement Procedures

**`Inventory_BulkMoveHubsToInventoryFacility`**
**File:** `mysql/db/procs/R__PROC_Inventory_BulkMoveHubsToInventoryFacility.sql`

```sql
-- Parameters:
-- inSerialNumberList TEXT (comma-separated)
-- inFacilityID INT
-- inCognitoID VARCHAR(50)

-- Logic:
1. Parse comma-separated serial numbers
2. For each hub:
   a. Get TransponderID by SerialNumber
   b. Get current FacilityTransponderID where active
   c. UPDATE Facility_Transponder SET
        EndDate = NOW(),
        ActiveFlag = 0,
        TransponderStatusID = 3  -- Removed
   d. INSERT new Facility_Transponder with:
        FacilityID = target,
        TransponderStatusID = 1,  -- Active
        ActiveFlag = 1,
        StartDate = NOW()
```

**`Transponder_RemoveHubAndChangeFacility`**
**File:** `mysql/db/procs/R__PROC_Transponder_RemoveHubAndChangeFacility.sql`

This is the **most critical procedure** for complex moves involving hub + enclosure + hotspot:

```sql
-- Parameters:
-- inTransponderID INT
-- inFacilityID INT (target)
-- inTransponderStatusID INT
-- inRemovalReasonTypeID INT
-- inEnclosureID INT
-- inEnclosedHotspotId INT
-- inEnclosedHotspotFacilityStatusID INT
-- inGroupName TEXT
-- inCognitoID VARCHAR(50)

-- Logic (transactional):
1. IF enclosureId provided:
   a. Call EnclosureCradlepointDevice_UpdateFacility for hotspot
   b. End previous Facility_Enclosure (EndDate, Status=2)
   c. Insert new Facility_Enclosure (Status=3 Ready to Install)

2. End previous Facility_Transponder:
   a. SET EndDate = NOW(), ActiveFlag = 0, Status = 3

3. Deactivate old hub photos (FileStatusID = 2)

4. Update Transponder.FacilityID and MonitorFlag

5. Insert new Facility_Transponder with new facility
```

#### Hotspot Movement Procedures

**`EnclosureCradlepointDevice_UpdateFacility`**
**File:** `mysql/db/procs/R__PROC_EnclosureCradlepointDevice_UpdateFacility.sql`

```sql
-- Parameters:
-- inCradlepointDeviceIDList TEXT (comma-separated)
-- inFacilityID INT
-- inGroupName TEXT (REQUIRED - throws error if NULL)
-- inWorkOrderBomID INT
-- inFacilityCradlepointStatusID INT
-- inUserID INT

-- Logic:
1. Validate GroupName is provided
2. For each cradlepoint:
   a. Update CradlepointDevice.GroupName
   b. Set previous facility status to 2 (inactive)
   c. Deactivate old photos
   d. Insert new Facility_CradlepointDevice record
```

**Business Rule:** Hotspots REQUIRE a NetCloud group name when being moved.

#### Enclosure Movement Procedures

**`Enclosure_UpdateEnclosureFacility`**
**File:** `mysql/db/procs/R__PROC_Enclosure_UpdateEnclosureFacility.sql`

```sql
-- Parameters:
-- inEnclosureIDList VARCHAR(255) (comma-separated)
-- inFacilityID INT
-- inFacilityCradlepointStatusID INT
-- inRemovalReasonID INT (0 = NULL)
-- inUserID INT

-- Logic:
1. For each enclosure:
   a. End previous Facility_Enclosure with EndDate and RemovalReasonTypeID
   b. Insert new Facility_Enclosure with:
      - Target FacilityID
      - FacilityEnclosureStatusID
      - StartDate = NOW()
```

### 5. Data Model

#### Core Tables

```
┌─────────────────────────────────────────────────────────────┐
│                       CUSTOMER                               │
│  CustomerID, CustomerName, ExternalCustomerID               │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ 1:N
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       FACILITY                               │
│  FacilityID, FacilityName, CustomerID, FacilityStatusID     │
└─────────────────────────────────────────────────────────────┘
          │                   │                    │
          │                   │                    │
          ▼                   ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ TRANSPONDER     │  │CRADLEPOINTDEVICE│  │    ENCLOSURE    │
│ (Hub)           │  │ (Hotspot)       │  │                 │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤
│ TransponderID   │  │CradlepointDeviceID│ │ EnclosureID    │
│ SerialNumber    │  │ MAC             │  │ SerialNumber    │
│ PartID          │  │ PartID          │  │ PartID          │
│ FacilityID      │  │ FacilityID      │  │ CreatedByUserID │
│ EnclosureID ────┼──┼─EnclosureID ────┼──┤                 │
│ FundingProjectID│  │ FundingProjectID│  │                 │
│ MonitorFlag     │  │ GroupName       │  │                 │
│ FirmwareVersion │  │ State (online)  │  │                 │
└─────────────────┘  └─────────────────┘  └─────────────────┘
          │                   │                    │
          ▼                   ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│FACILITY_        │  │FACILITY_        │  │FACILITY_        │
│TRANSPONDER      │  │CRADLEPOINTDEVICE│  │ENCLOSURE        │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤
│FacilityTransponderID│FacilityCradlepointDeviceID│FacilityEnclosureID│
│ FacilityID      │  │ FacilityID      │  │ FacilityID      │
│ TransponderID   │  │CradlepointDeviceID│ │ EnclosureID    │
│TransponderStatusID│ │FacilityCradlepointStatusID│FacilityEnclosureStatusID│
│ ActiveFlag      │  │ WorkOrderBOMID  │  │ WorkOrderBOMID  │
│ StartDate       │  │ StartDate       │  │ StartDate       │
│ EndDate         │  │ EndDate         │  │ EndDate         │
│ LocationNotes   │  │                 │  │RemovalReasonTypeID│
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

#### Status Values

**TransponderStatus (Hubs):**
| ID | Name |
|----|------|
| 1 | Active |
| 2 | Spare |
| 3 | Removed |

**FacilityEnclosureStatus:**
| ID | Name |
|----|------|
| 1 | Assigned |
| 2 | Removed |
| 3 | Ready to Install |
| 4 | In Transit to HQ |

**FacilityCradlepointStatus:**
| ID | Name |
|----|------|
| 1 | Active |
| 2 | Inactive |
| 3 | Ready to Install |

#### Enclosure Relationship Pattern

An **enclosure** physically contains:
- 1 Hub (Transponder) - via `Transponder.EnclosureID`
- 1 Hotspot (CradlepointDevice) - via `CradlepointDevice.EnclosureID`
- Optionally sensors (Receiver) - via `Receiver.EnclosureID`

When moving an enclosure, **all contained components must move together**.

### 6. Business Logic & Validation Rules

#### Pre-Move Validations

**For Hubs:**
1. Check if hub is already active at a customer facility (`checkActiveHubs`)
2. If active, require removal reason selection
3. Validate serial number format and existence

**For Hotspots:**
1. Check cradlepoint availability (`checkCradlepointAvailability`)
2. Validate MAC address format
3. **NetCloud group is REQUIRED** for all hotspot moves

**For Enclosures:**
1. Validate enclosure part number prefix matches hub part
2. Check facility assignments for both hub AND hotspot
3. If either component is at different facility, prompt for confirmation

**For Hub-Hotspot Enclosures (Combined):**
1. Validate both hub serial and hotspot MAC
2. Check both are available or prompt for reassignment
3. Require NetCloud group selection
4. Facility must match for both components

#### Movement Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                    USER FILLS FORM                          │
│  - Selects part number                                      │
│  - Selects facility                                         │
│  - Enters serial numbers                                    │
│  - Selects status                                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  VALIDATION CHECKS                          │
│  - Serial number format                                     │
│  - Duplicate detection                                      │
│  - Check if hardware is already assigned                    │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              │ Hardware already assigned?    │
              └───────────────┬───────────────┘
                    YES │           │ NO
                        ▼           │
┌─────────────────────────────────┐ │
│ CONFIRMATION MODAL              │ │
│ - Shows current assignment      │ │
│ - Requires removal reason       │ │
└─────────────────────────────────┘ │
                    │               │
                    └───────┬───────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    SUBMIT TO API                            │
│  - Calls appropriate mutation based on hardware type        │
│  - Includes removal reason if provided                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  DATABASE OPERATIONS                        │
│  1. End previous facility assignment (EndDate = NOW)        │
│  2. Set previous status to Removed (3)                      │
│  3. Deactivate old photos (FileStatusID = 2)                │
│  4. Create new facility assignment (StartDate = NOW)        │
│  5. If removal reason: Create HardwareIssue record          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  POST-SUBMIT ACTIONS                        │
│  - Toast notification                                       │
│  - Invalidate queries to refresh UI                         │
│  - Hardware issue created if removal reason selected        │
└─────────────────────────────────────────────────────────────┘
```

#### Soft Delete Pattern

The system uses a **soft delete** pattern for all facility assignments:
- Never deletes `Facility_*` records
- Sets `EndDate = NOW()` and `ActiveFlag = 0` on old records
- Creates new record with `StartDate = NOW()` and `ActiveFlag = 1`
- This preserves complete movement history for audit purposes

### 7. Key Assumptions

1. **One Active Assignment**: Each piece of hardware can only be active at ONE facility at a time
2. **Enclosure Atomicity**: When moving enclosures, hub and hotspot move together
3. **NetCloud Groups Required**: Hotspots cannot be moved without specifying a NetCloud group
4. **Audit Trail**: All movements create history records - nothing is deleted
5. **Status Transitions**: Hardware follows defined status state machine (Active → Removed → Active)
6. **User Authentication**: All operations track the cognito user ID for audit
7. **Photo Deactivation**: Moving hardware deactivates associated photos at old location

### 8. Common Bug Areas

Based on the complexity of this system, potential bug areas include:

1. **Enclosure Synchronization**: Hub/hotspot/enclosure can get out of sync if one component move fails
2. **Status Mismatches**: Status between junction tables and main tables can diverge
3. **NetCloud Group Handling**: Group assignment errors during hotspot moves
4. **Validation Edge Cases**: Serial numbers that pass format check but don't exist
5. **Concurrent Moves**: Race conditions when multiple users move same hardware
6. **Photo Cleanup**: Photos not properly deactivated during moves
7. **History Gaps**: Missing EndDate on old records creating duplicate "active" assignments

## Code References

### Frontend
- `frontend/src/pages/TrackInventory.tsx` - Main page
- `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx:1-1294` - Add inventory form
- `frontend/src/components/TrackInventoryPage/useTrackInventorySubmit.ts` - Submit hook
- `frontend/src/shared/api/InventoryService.ts` - API calls
- `frontend/src/shared/api/CradlePointService.ts` - Cradlepoint API
- `frontend/src/shared/api/HubService.ts` - Hub API
- `frontend/src/components/AssignedHardwareConfirmationModal.tsx` - Reassignment modal

### Backend (Lambda)
- `lambdas/lf-vero-prod-inventory/main.py` - Inventory operations
- `lambdas/lf-vero-prod-hub/main.py` - Hub operations
- `lambdas/lf-vero-prod-cradlepoint/main.py` - Cradlepoint operations

### Database (Stored Procedures)
- `mysql/db/procs/R__PROC_Inventory_BulkMoveHubsToInventoryFacility.sql`
- `mysql/db/procs/R__PROC_Transponder_RemoveHubAndChangeFacility.sql`
- `mysql/db/procs/R__PROC_EnclosureCradlepointDevice_UpdateFacility.sql`
- `mysql/db/procs/R__PROC_Enclosure_UpdateEnclosureFacility.sql`
- `mysql/db/procs/R__PROC_Inventory_BulkMoveSensorsToInventoryFacility.sql`
- `mysql/db/procs/R__PROC_Inventory_GetHubHotspotEnclosures.sql`
- `mysql/db/procs/R__PROC_Hub_GetHubHistory.sql`
- `mysql/db/procs/R__PROC_Hub_GetCradlepointHistory.sql`

### Data Types
- `frontend/src/shared/types/hubs/HubList.ts`
- `frontend/src/shared/types/hubs/ActiveHub.ts`
- `frontend/src/shared/types/hotspots/Hotspot.ts`
- `frontend/src/shared/types/hotspots/ActiveHostspot.ts`
- `frontend/src/shared/types/enclosures/EnclosureDetail.ts`
- `frontend/src/shared/types/enclosures/ActiveEnclosure.ts`
- `frontend/src/shared/types/enclosures/HubHotspotEnclosure.ts`

### Database Schema
- `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql` - Initial tables
- `mysql/db/table_change_scripts/V000000191__Add_Enclosure.sql` - Enclosure table
- `mysql/db/table_change_scripts/V000000192__Add_EnclosureID_Columns.sql` - FK relationships
- `mysql/db/table_change_scripts/V000000193__Create_Facility_Enclosure_Tables.sql` - Junction tables

## Architecture Insights

1. **API Gateway Pattern**: All APIs use AWS API Gateway with SigV4 authentication
2. **Lambda per Domain**: Separate lambdas for inventory, hub, cradlepoint, component
3. **Stored Procedure Encapsulation**: Business logic lives in MySQL stored procedures
4. **Soft Delete Everywhere**: All assignment tables use StartDate/EndDate pattern
5. **Audit by Design**: User ID (CognitoID) tracked on all operations
6. **Role-Based Access**: Certain operations restricted by user role (SupplyChain, Engineering)

## Open Questions

1. What happens if the NetCloud API call fails during a hotspot move?
2. Is there a cleanup job for orphaned photos after moves?
3. How are concurrent move conflicts detected and handled?
4. What triggers the HardwareIssue creation - is it only via removal reason?
5. Are there any scheduled jobs that reconcile status mismatches?

## Related Files for Future Bug Investigation

When investigating bugs on this page, start with:
1. Check the specific stored procedure for the operation type
2. Verify status values are correct in lookup tables
3. Check for EndDate being properly set on old records
4. Verify ActiveFlag consistency between tables
5. Check photo deactivation logic if visual issues
6. Verify NetCloud group handling for hotspot issues
