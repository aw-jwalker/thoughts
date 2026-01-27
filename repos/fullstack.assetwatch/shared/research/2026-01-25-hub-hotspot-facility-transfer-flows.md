---
date: 2025-01-25T10:30:00-06:00
researcher: Jackson Walker
git_commit: 96c1227ad9195977f08f44385ca861757ccdcedb
branch: IWA-14033
repository: fullstack.assetwatch
topic: "Hub and Hotspot Facility Transfer Flows"
tags: [research, codebase, hubs, hotspots, enclosures, facility-transfers, inventory]
status: complete
last_updated: 2025-01-25
last_updated_by: Jackson Walker
---

# Research: Hub and Hotspot Facility Transfer Flows

**Date**: 2025-01-25T10:30:00-06:00
**Researcher**: Jackson Walker
**Git Commit**: 96c1227ad9195977f08f44385ca861757ccdcedb
**Branch**: IWA-14033
**Repository**: fullstack.assetwatch

## Research Question
How are hubs and hotspots moved to different facilities? This includes:
- Live customer facilities
- Inventory facilities
- Hubs and hotspots moved by themselves (standalone)
- Hubs and hotspots moved when contained in an enclosure

## Summary . 

The system tracks facility assignments for hubs (transponders), hotspots (cradlepoint devices), and enclosures through junction tables that maintain temporal history. When devices are moved between facilities:

1. **Standalone devices** have their current facility assignment ended (EndDate set) and a new assignment record created
2. **Enclosed devices** can be moved either individually (keeping enclosure at original facility) or as part of an enclosure move that cascades to all contained devices
3. **Inventory facilities** are identified by `FacilityStatusName LIKE 'Inv%'` pattern - there is no explicit `IsInventory` flag
4. **Live customer facilities** have `FacilityStatusID = 1` ("Live Customer")

Key architectural pattern: The system uses a **soft-delete with history** approach - facility assignments are never deleted, instead `EndDate` is set and `ActiveFlag` is toggled, preserving complete audit trail.

## Detailed Findings

### Database Schema Overview

#### Core Tables

| Table | Purpose | Key Facility Column |
|-------|---------|---------------------|
| `Transponder` | Hub devices | `FacilityID` (legacy/denormalized) |
| `Receiver` | Sensors | N/A (uses junction table) |
| `CradlepointDevice` | Hotspots | N/A (uses junction table) |
| `Enclosure` | Physical enclosures | N/A (uses junction table) |

#### Junction Tables for Facility Tracking

| Table | Tracks | Has Temporal Fields |
|-------|--------|---------------------|
| `Facility_Transponder` | Hub-to-facility | Yes (`StartDate`, `EndDate`, `ActiveFlag`) |
| `Facility_CradlepointDevice` | Hotspot-to-facility | Partial (`FacilityCradlepointStatusID`) |
| `Facility_Receiver` | Sensor-to-facility | No (uses delete/insert + history table) |
| `Facility_Enclosure` | Enclosure-to-facility | Yes (`StartDate`, `EndDate`) |

#### Enclosure Relationships
- `Transponder.EnclosureID` → links hub to enclosure
- `Receiver.EnclosureID` → links sensor to enclosure
- `CradlepointDevice.EnclosureID` → links hotspot to enclosure

### Inventory vs Live Customer Facilities

**How Inventory Facilities Are Identified:**
- Query pattern: `WHERE FacilityStatusName LIKE 'Inv%'`
- Location: `mysql/db/procs/R__PROC_Facility_GetFacilityInventoryList.sql:38`

**Known Inventory Facility Status Names:**
- "Inv-Good New Hazloc"
- "Inv-Good Service Hazloc"
- "Inv-IQA"
- "Inv-development"

**Live Customer Facility:**
- `FacilityStatusID = 1` with `FacilityStatusName = "Live Customer"`

**Key Differences in Handling:**
| Aspect | Inventory Facility | Live Customer Facility |
|--------|-------------------|----------------------|
| Hub MonitorFlag | Set to `False` | Can be `True` when deployed |
| Default Status | TransponderStatusID=1 (Available) | TransponderStatusID=1 (Active) |
| Validation | Minimal | Checks for active monitoring points |

---

## Hub (Transponder) Facility Transfers

### Standalone Hub Transfer

#### Primary Procedures

**1. `Transponder_RemoveHubAndChangeFacility`**
- File: `mysql/db/procs/R__PROC_Transponder_RemoveHubAndChangeFacility.sql`
- Purpose: Remove hub from current facility and assign to new facility
- Handles enclosure cascade if hub is enclosed

**Process Flow:**
```
1. End current Facility_Transponder (EndDate=now, ActiveFlag=0, TransponderStatusID=3)
2. Deactivate photos (Files.FileStatusID=2)
3. Update Transponder.MonitorFlag=0, FacilityID=new facility
4. Insert new Facility_Transponder (ActiveFlag=1, StartDate=now)
```

**2. `Inventory_BulkMoveHubsToInventoryFacility`**
- File: `mysql/db/procs/R__PROC_Inventory_BulkMoveHubsToInventoryFacility.sql`
- Purpose: Bulk move hubs to inventory facility by serial number list
- Does NOT update `Transponder.FacilityID` (commented out)

**Process Flow:**
```
FOR EACH serial number:
  1. Lookup TransponderID from SerialNumber
  2. Find active Facility_Transponder (EndDate IS NULL)
  3. Update existing: EndDate=now, ActiveFlag=0, TransponderStatusID=3
  4. Insert new: FacilityID=inventory, TransponderStatusID=1, ActiveFlag=1
```

**3. `FacilityTransponder_UpdateTransponderStatus`**
- File: `mysql/db/procs/R__PROC_FacilityTransponder_UpdateTransponderStatus.sql`
- Purpose: Update hub status and facility assignment
- Preserves LocationNotes during transfers

#### API Endpoints

| Endpoint | Lambda | Method | Procedure Called |
|----------|--------|--------|------------------|
| POST /hub/list | lf-vero-prod-hub | `removeHubAndChangeStatus` | `Transponder_RemoveHubAndChangeFacility` |
| POST /inventory/update | lf-vero-prod-inventory | `bulkMoveHubsToInventoryFacility` | `Inventory_BulkMoveHubsToInventoryFacility` |
| POST /inventory/update | lf-vero-prod-inventory | `addBulkHubsToInventory` | `Inventory_AddTransponder` |

#### Frontend Components

- `RemoveHub.tsx` - Individual hub removal with facility selection
- `MoveHubsNextStepModal.tsx` - Bulk move hubs to next-step facilities
- `AddHubs.tsx` - Assign hubs to facilities

---

## Hotspot (CradlepointDevice) Facility Transfers

### Standalone Hotspot Transfer

#### Primary Procedures

**1. `Cradlepoint_RemoveCradlepoint`**
- File: `mysql/db/procs/R__PROC_Cradlepoint_RemoveCradlepoint.sql`
- Purpose: Remove hotspot from facility and reassign
- Updates NetCloud GroupName

**Process Flow:**
```
1. Update CradlepointDevice (Notes=NULL, DateUpdated, GroupName)
2. End Facility_CradlepointDevice (FacilityCradlepointStatusID=2)
3. Deactivate photos (Files.FileStatusID=2)
4. Insert new Facility_CradlepointDevice
```

**2. `Cradlepoint_AddCradlepoint`**
- File: `mysql/db/procs/R__PROC_Cradlepoint_AddCradlepoint.sql`
- Purpose: Add hotspot and assign to facility
- Handles facility changes for existing devices

**3. `EnclosureCradlepointDevice_UpdateFacility`**
- File: `mysql/db/procs/R__PROC_EnclosureCradlepointDevice_UpdateFacility.sql`
- Purpose: Move hotspots within enclosure to new facility
- Requires GroupName parameter

#### API Endpoints

| Endpoint | Lambda | Method | Procedure Called |
|----------|--------|--------|------------------|
| POST /cradlepoint/update | lf-vero-prod-cradlepoint | `removeCradlepoint` | `Cradlepoint_RemoveCradlepoint` |
| POST /cradlepoint/update | lf-vero-prod-cradlepoint | `addCradlepoint` | `Cradlepoint_AddCradlepoint` |

#### Frontend Components

- `RemoveHotspot.tsx` - Individual hotspot removal with facility/group selection
- `AddHotspot.tsx` - Assign hotspots to facilities

---

## Enclosure Facility Transfers (with Cascade)

### When Enclosure Moves, Contained Devices Move Too

#### Primary Cascade Procedure

**`Inventory_AssignEnclosureSubAssembly`**
- File: `mysql/db/procs/R__PROC_Inventory_AssignEnclosureSubAssembly.sql`
- Purpose: Move all sub-assemblies when enclosure moves

**Cascade Logic:**
```sql
-- Check for receivers in enclosure
IF EXISTS(SELECT 1 FROM Receiver WHERE EnclosureID = inEnclosureID) THEN
  -- Map enclosure status to receiver status
  -- Call EnclosureReceiver_UpdateFacility

-- Check for transponders in enclosure
IF EXISTS(SELECT 1 FROM Transponder WHERE EnclosureID = inEnclosureID) THEN
  -- Map enclosure status to transponder status
  -- Call EnclosureTransponder_UpdateFacility

-- Check for cradlepoints in enclosure
IF EXISTS(SELECT 1 FROM CradlepointDevice WHERE EnclosureID = inEnclosureID) THEN
  -- Call EnclosureCradlepointDevice_UpdateFacility
```

#### Status Mapping (Enclosure → Sub-Assembly)

**Enclosure Status → Transponder Status:**
| Enclosure Status | Transponder Status |
|------------------|-------------------|
| 1 (Assigned) | 1 (Active) |
| 2 (Removed) | 3 (Removed) |
| 3 (Ready to Install) | 5 (Ready to Install) |
| 4 (In Transit) | 4 (In Transit) |

**Enclosure Status → Receiver Status:**
| Enclosure Status | Receiver Status |
|------------------|-----------------|
| 3 (Ready to Install) | 4 (Ready to Install) |
| All others | 1 (Available) |

#### Enclosure Transfer Procedures

**1. `Inventory_AssignEnclosure`**
- File: `mysql/db/procs/R__PROC_Inventory_AssignEnclosure.sql`
- Purpose: Assign enclosure to facility with full cascade

**Process Flow:**
```
1. Validate enclosure exists with matching part ID
2. Update FundingProjectID if provided
3. End current Facility_Enclosure (EndDate=now, status=2)
4. Insert new Facility_Enclosure
5. Call Inventory_AssignEnclosureSubAssembly for cascade
```

**2. `WorkOrder_UpdateEnclosure`**
- File: `mysql/db/procs/R__PROC_WorkOrder_UpdateEnclosure.sql`
- Purpose: Move enclosure for work order with validation

**Validation Checks:**
- No receivers attached to monitoring points
- No receivers at different customer facility
- No transponders active at different customer facility
- No cradlepoints active at different customer facility

**3. `WorkOrder_RemoveEnclosure`**
- File: `mysql/db/procs/R__PROC_WorkOrder_RemoveEnclosure.sql`
- Purpose: Return enclosure to previous facility

**Process Flow:**
```
1. Find previous facility from Facility_Enclosure history (EndDate IS NOT NULL)
2. End current assignment
3. Create new assignment at previous facility
4. Cascade to sub-assemblies with "available" statuses
```

### Hub+Hotspot Enclosure Special Handling

When a hub or hotspot is in a "Hub+Hotspot Enclosure" (PartID `100-006` or `100-007`), removing either device triggers moving the entire enclosure:

**From `Transponder_RemoveHubAndChangeFacility`:**
```sql
IF inEnclosureID IS NOT NULL THEN
  -- Move enclosed hotspot if present
  IF inEnclosedHotspotId IS NOT NULL THEN
    CALL EnclosureCradlepointDevice_UpdateFacility(...)
  END IF;
  -- End enclosure facility assignment
  UPDATE Facility_Enclosure SET EndDate=UTC_TIMESTAMP()...
  -- Create new enclosure facility assignment
  INSERT INTO Facility_Enclosure...
END IF;
```

**From `Cradlepoint_RemoveCradlepoint`:**
```sql
IF inEnclosureID IS NOT NULL THEN
  -- Move enclosed hub if present
  IF inEnclosedHubID IS NOT NULL THEN
    CALL EnclosureTransponder_UpdateFacility(...)
  END IF;
  -- End/create enclosure facility assignments
END IF;
```

---

## Work Order Integration

Work orders link facility transfers to SalesForce tracking:

### Work Order Procedures

| Procedure | Purpose |
|-----------|---------|
| `WorkOrder_AddBomHardware` | Add hardware to work order, move to WO facility |
| `WorkOrder_UpdateTransponders` | Move hub for work order |
| `WorkOrder_UpdateCradlepoints` | Move hotspot for work order |
| `WorkOrder_UpdateEnclosure` | Move enclosure for work order |
| `WorkOrder_RemoveHardware` | Return hardware to previous facility |
| `WorkOrder_UpdateHardwareReturnFacility` | Move hardware to return facility |

### Work Order Status Codes

**When moving TO work order facility:**
- Hub: TransponderStatusID=5 (On Work Order)
- Hotspot: FacilityCradlepointStatusID=3 (On Work Order)
- Enclosure: FacilityEnclosureStatusID=3 (Ready to Install)

**When RETURNING from work order:**
- Hub: TransponderStatusID=4 (Return)
- Hotspot: FacilityCradlepointStatusID=4 (Return)

---

## Photo/File Management During Transfers

All facility transfer procedures deactivate photos to prevent cross-facility display:

```sql
UPDATE Files
SET FileStatusID = 2  -- Inactive
WHERE TransponderID = inTransponderID
  AND DidUpload = 1
  AND FileStatusID = 1;
```

This applies to:
- Hub transfers (TransponderID)
- Hotspot transfers (CradlepointDeviceID)

---

## Transaction Handling

### Outer Transaction Procedures
- `Inventory_AssignEnclosure` - Wraps entire enclosure list
- `WorkOrder_RemoveEnclosure` - Wraps all device returns
- `Transponder_RemoveHubAndChangeFacility` - Wraps hub and enclosure move

### Per-Item Transaction Procedures
- `EnclosureTransponder_UpdateFacility` - Each hub in separate transaction
- `EnclosureCradlepointDevice_UpdateFacility` - Each hotspot in separate transaction

---

## Code References

### Database Procedures
- `mysql/db/procs/R__PROC_Transponder_RemoveHubAndChangeFacility.sql` - Hub removal with facility change
- `mysql/db/procs/R__PROC_Inventory_BulkMoveHubsToInventoryFacility.sql` - Bulk hub to inventory
- `mysql/db/procs/R__PROC_Cradlepoint_RemoveCradlepoint.sql` - Hotspot removal
- `mysql/db/procs/R__PROC_Inventory_AssignEnclosure.sql` - Enclosure assignment with cascade
- `mysql/db/procs/R__PROC_Inventory_AssignEnclosureSubAssembly.sql` - Cascade logic
- `mysql/db/procs/R__PROC_EnclosureTransponder_UpdateFacility.sql` - Hub facility update for enclosure
- `mysql/db/procs/R__PROC_EnclosureCradlepointDevice_UpdateFacility.sql` - Hotspot facility update for enclosure
- `mysql/db/procs/R__PROC_WorkOrder_UpdateEnclosure.sql` - Work order enclosure with validation

### Lambda Functions
- `lambdas/lf-vero-prod-hub/main.py:879-907` - Hub removal endpoint
- `lambdas/lf-vero-prod-inventory/main.py:166-273` - Inventory bulk operations
- `lambdas/lf-vero-prod-cradlepoint/main.py:582-642` - Hotspot removal endpoint

### Frontend Components
- `frontend/src/components/CustomerDetailPage/Hubs/RemoveHub.tsx` - Hub removal UI
- `frontend/src/components/CustomerDetailPage/Hotspots/RemoveHotspot.tsx` - Hotspot removal UI
- `frontend/src/components/HubCheckPage/MoveHubsNextStepModal.tsx` - Bulk hub movement
- `frontend/src/pages/enclosures/EditEnclosure.tsx` - Enclosure management

### Database Tables
- `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql` - Core table definitions
- `mysql/db/table_change_scripts/V000000191__Add_Enclosure.sql` - Enclosure table
- `mysql/db/table_change_scripts/V000000193__Create_Facility_Enclosure_Tables.sql` - Facility_Enclosure

## Architecture Documentation

### Facility Transfer Pattern
```
1. Find current active assignment (EndDate IS NULL or status = active)
2. End current assignment:
   - Set EndDate = UTC_TIMESTAMP()
   - Set ActiveFlag = 0 (for hubs)
   - Set status to "Removed" (3 for hubs, 2 for hotspots)
3. Deactivate associated photos
4. Create new assignment:
   - Set FacilityID = target facility
   - Set StartDate = UTC_TIMESTAMP()
   - Set appropriate status
5. If enclosed, optionally cascade to enclosure and sibling devices
```

### Enclosure Cascade Pattern
```
1. Update Facility_Enclosure (end old, create new)
2. For each device type in enclosure:
   a. Check if devices exist
   b. Map enclosure status to device status
   c. Collect device IDs
   d. Call device-specific UpdateFacility procedure
```

## Open Questions

1. Why is `Transponder.FacilityID` maintained when `Facility_Transponder` is the source of truth?
2. Why do hotspots not have the same temporal tracking (StartDate/EndDate) as hubs?
3. What happens to sub-assemblies when an enclosure is moved but they're at a different facility?
