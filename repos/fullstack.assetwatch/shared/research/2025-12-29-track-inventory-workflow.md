---
date: 2025-12-29T12:00:00-06:00
researcher: Claude
git_commit: c6de208eed426a2ad9aa93b03a4979072bc041dc
branch: dev
repository: fullstack.assetwatch
topic: "Track Inventory Workflow - Serial Number Input, Dropdowns, Lookups, and Validation"
tags: [research, codebase, track-inventory, serial-numbers, validation, dropdowns]
status: complete
last_updated: 2025-12-29
last_updated_by: Claude
---

# Research: Track Inventory Workflow

**Date**: 2025-12-29T12:00:00-06:00
**Researcher**: Claude
**Git Commit**: c6de208eed426a2ad9aa93b03a4979072bc041dc
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question
How does Track Inventory work? When a user enters a serial number in the input field, and selects values from the drop-downs, what lookups are done, what validation is done?

## Summary

The Track Inventory feature allows users to assign hardware (Hubs, Sensors, Hotspots/CradlePoints, and Enclosures) to facilities with specific statuses. The workflow involves:

1. **Serial Number Input**: A textarea that validates format on every keystroke, strips part number prefixes, and enforces a 300-item limit
2. **7 Dropdown Fields**: Part Number, Facility, Status, Funding Project, Revision (conditional), Removal Reason, Enclosure Type (conditional), and Hotspot Group (conditional)
3. **Multi-Layer Validation**: Frontend format validation, business rule validation, pre-submission active hardware checks, and backend database validation
4. **API Integration**: Uses AWS Amplify API with Lambda handlers routing to MySQL stored procedures

---

## Detailed Findings

### 1. File Structure

#### Main Components
| File | Description |
|------|-------------|
| `frontend/src/pages/TrackInventory.tsx` | Main page component with inventory data table |
| `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx` | Form component with all dropdowns and submission logic |
| `frontend/src/components/common/forms/SerialNumberInput.tsx` | Serial number textarea with validation |
| `frontend/src/components/TrackInventoryPage/useTrackInventorySubmit.ts` | Mutation hooks for submission |

#### API Layer
| File | Description |
|------|-------------|
| `frontend/src/shared/api/InventoryService.ts` | Frontend API service functions |
| `lambdas/lf-vero-prod-inventory/main.py` | Lambda handler for inventory operations |

#### Database
| File | Description |
|------|-------------|
| `mysql/db/procs/R__PROC_Inventory_AddTransponder.sql` | Hub assignment stored procedure |
| `mysql/db/procs/R__PROC_Inventory_AddSensor.sql` | Sensor assignment stored procedure |
| `mysql/db/procs/R__PROC_Inventory_AssignEnclosure.sql` | Enclosure assignment stored procedure |
| `mysql/db/procs/R__PROC_Inventory_CheckSerialNumbers.sql` | Serial validation stored procedure |

---

### 2. Serial Number Input Workflow

#### Entry Point
`SerialNumberInput.tsx:336-350` - Mantine Textarea component

#### On Every Keystroke (`handleInput` at line 204-275):

```
User Types → handleInput() triggered
    ↓
1. stripPartNumber() - Removes "710-001F:" prefix patterns
    ↓
2. setSerialNumbers() - Updates textarea state
    ↓
3. createListFromCommaString() - Splits by spaces/commas/newlines
    ↓
4. validateSerialNumbers() - Format validation based on hardware type
    ↓
5. Update error states (duplicates, limitReached, serials)
    ↓
6. queryClient.invalidateQueries(["getPartnerSensorList"]) - Cache invalidation
```

#### Format Validation Rules

| Hardware Type | Validation | File Location |
|---------------|------------|---------------|
| **Hubs** | Exactly 7 characters, no spaces/commas | `SerialNumberInput.tsx:148-159` |
| **Hotspots (MAC)** | 17 chars with colons, or 12/6 chars auto-formatted | `SerialNumberInput.tsx:161-202` |
| **Enclosures** | Exactly 9 characters, first 2 must match SerialNumberPrefix enum | `SerialNumberInput.tsx:121-135` |
| **Hub/Hotspot Enclosure** | Routes based on length: ≤8 chars → hub, >8 chars → hotspot | `SerialNumberInput.tsx:110-117` |

#### Hotspot MAC Address Formatting
- `12 chars` → Inserts colons every 2 chars (e.g., `5E5CFC123456` → `5E:5C:FC:12:34:56`)
- `6 chars` → Prepends `00:30:44:` prefix
- `8 chars with colons` → Prepends `00:30:44:` prefix
- All converted to uppercase

#### Error Limit
- Maximum 300 serial numbers per submission (`SerialNumberInput.tsx:240`)

---

### 3. Dropdown Fields and Lookups

#### 3.1 Part Number Dropdown
**Location**: `TrackInventoryHeader.tsx:1072-1086`
**State**: `partId`

**API Call on Mount**:
```typescript
getPartNumbers(0, 0) // PartService.ts:37-54
→ POST apiVeroPart /list { meth: "getPartNumbers" }
```

**Special Groupings Added**:
- "Hub v2" (value: "4")
- "PBSM v2" (value: "0")
- "Hub v3" (value: "710-200")
- "Enclosure" (value: "999")

**Cascading Effects** (on selection change at `handlePartSelection` line 376-426):
1. Switches status dropdown list based on product type
2. Sets default status value
3. Clears revision selection
4. Updates `isHubHotspotEnclosure` flag
5. Triggers revision list population for PBSM v2

---

#### 3.2 Facility Dropdown
**Location**: `TrackInventoryHeader.tsx:1089-1105`
**State**: `selectedFacility`

**API Call on Mount**:
```typescript
getInventoryFacilityList() // FacilityServices.ts:389-398
→ POST apiVeroFacility /list { meth: "getInventoryFacilityList" }
```

**Special Logic for Partner/Nikola Users** (lines 231-245):
```typescript
getDefaultUserFacility() // Auto-selects default facility
```

---

#### 3.3 Status Dropdown
**Location**: `TrackInventoryHeader.tsx:1107-1123`
**State**: `selectedStatus` (default: "2" = SPARE)

**Dynamic Population Based on Part Number**:

| Product Type | API Call | Hook |
|--------------|----------|------|
| Hub/Transponder | `getTransponderStatus()` | `useGetTransponderStatus` |
| Hotspot/CradlePoint | `getFacilityCradlepointStatus()` | `useGetHotspotFacilityStatus` |
| Enclosure | `getFacilityEnclosureStatusList()` | useEffect line 328 |
| Sensor | `getFacilityReceiverStatus()` | useEffect line 321 |

---

#### 3.4 Funding Project Dropdown
**Location**: `TrackInventoryHeader.tsx:1125-1143`
**State**: `selectedFundingProjectId`

**API Call on Mount**:
```typescript
getInventoryFundingProjects() // InventoryService.ts:125-140
→ POST apiVeroInventory /list { meth: "getInventoryFundingProjects" }
```

**Filtering**: Excludes projects where `lockFlag === 1`

**On Selection**: Shows confirmation modal (line 1139)

---

#### 3.5 Revision Dropdown (Conditional)
**Location**: `TrackInventoryHeader.tsx:1163-1192`
**State**: `selectedRevision`
**Visibility**: Only for "SupplyChain" or "Engineering" roles
**Enabled**: Only when `partId === "0"` (PBSM v2) AND valid serial numbers exist

**API Call**:
```typescript
getPartRevisionList() // InventoryService.ts:209-221
→ POST apiVeroInventory /list { meth: "getPartRevisionList" }
```

**Filtering Logic** (lines 333-374):
1. Groups serial numbers by first character
2. Validates all serials have same part number
3. Filters revisions for that part ID
4. Shows only ACTIVE or DEFAULT status revisions

---

#### 3.6 Removal Reason Dropdown
**Location**: `TrackInventoryHeader.tsx:1193-1221`
**State**: `removalReasonTypeId`

**API Call on Mount**:
```typescript
getReceiverRemovalList() // SensorServices.ts:376-387
→ useGetReceiverRemovalList hook
```

**Usage**: Required when reassigning hardware from active customer assignments

---

#### 3.7 Enclosure Type Dropdown (Hub v2 Only)
**Location**: `TrackInventoryHeader.tsx:1222-1241`
**State**: `enclosurePartId`
**Visibility**: Only when `partId === PartEnum["710-002"]` (Hub v2)

**Data Source**: Filters existing `partList` for part "100-005"

---

#### 3.8 Hotspot Group Dropdown (Conditional)
**Location**: `TrackInventoryHeader.tsx:1242-1256`
**State**: `groupId`
**Visibility**: When `isCradlePoint` OR `isHotspotEnclosure` OR `isHubHotspotEnclosure`

**API Call**:
```typescript
getHotspotGroups() // ProductServices.ts:66-84
→ useGetHotspotGroups hook
```

**Filtering**: By product ID (CradlePoint vs Hotspot S400)

---

### 4. Validation Layers

#### Layer 1: Frontend Format Validation (Real-time)
| Check | Location | Error Key |
|-------|----------|-----------|
| Serial number format | `SerialNumberInput.tsx:105-146` | `serials` |
| 300 item limit | `SerialNumberInput.tsx:240` | `limitReached` |
| Duplicate detection | `TrackInventoryHeader.tsx:519-526` | `duplicates` |
| Enclosure part number consistency | `TrackInventoryHeader.tsx:528-537` | `enclosurePartNumberMismatch` |

#### Layer 2: Required Field Validation (Submit Button)
Button disabled when (`TrackInventoryHeader.tsx:1265-1272`):
- Any error flag is true
- `validSerialNumbers.length === 0`
- `!selectedFacility`
- `!selectedStatus`
- CradlePoint/Hotspot without `groupId`

#### Layer 3: Pre-Submission Active Hardware Checks

**CradlePoint** (`TrackInventoryHeader.tsx:543-566`):
```typescript
checkCradlepointAvailability(validSerialNumbers.join("|"))
→ Filters for facilityStatusID === FacilityStatus.LIVE_CUSTOMER
→ Shows confirmation modal if active hardware found
```

**Sensors** (`TrackInventoryHeader.tsx:567-588`):
```typescript
checkSensorsIfActive(snList, partId, partRevisionId)
→ Shows confirmation modal if active sensors found
```

**Hubs** (`TrackInventoryHeader.tsx:589-615`):
```typescript
checkActiveHubs(snList)
→ Also validates serial isn't a sensor (line 590-599)
→ Shows confirmation modal if active hubs found
```

**Enclosures** (`TrackInventoryHeader.tsx:616-659`):
```typescript
getCurrentFacilityEnclosureAssignment(serialNumberList, enclosurePartId)
→ Uses findActiveEnclosures() filter
→ Shows confirmation modal if active enclosures found
→ Validates all serials exist in response
```

#### Layer 4: Backend Database Validation

**Stored Procedure Checks**:

| Procedure | Validation |
|-----------|------------|
| `Inventory_AddTransponder` | Hub serial not a sensor serial, enclosure not already assigned |
| `Inventory_AddSensor` | Receiver exists with correct part ID |
| `Inventory_AssignEnclosure` | Enclosure exists with correct part ID |
| `Inventory_CheckSerialNumbers` | Serial exists in database for product type |

---

### 5. Submission Flow

```
User clicks "Add Inventory"
    ↓
1. Duplicate check (frontend)
    ↓
2. Active hardware check (API call based on hardware type)
    ↓
3. Confirmation modal if active hardware found
    ↓
4. Mutation call (useMutation hooks)
    ↓
5. Lambda handler routes by `meth` field
    ↓
6. Stored procedure executes with transaction
    ↓
7. Success: Toast notification, query invalidation, form reset
   Error: Toast error, error state update
```

#### Mutation Hooks (`useTrackInventorySubmit.ts`):

| Hardware Type | Mutation | API Method |
|---------------|----------|------------|
| Hubs | `addHubsMutation` | `addBulkSerialNumbersForHubs` |
| Sensors | `addSensorsMutation` | `addBulkSerialNumbersForSensors` |
| Enclosures | `addEnclosuresMutation` | `addBulkSerialNumbersForEnclosures` |
| CradlePoint | `addCradlePointMutation` | `addBulkCradlePointDevices` |

---

### 6. Error Messages

| Error Key | Message | Location |
|-----------|---------|----------|
| `duplicates` | "Please remove the following duplicates from the list:" | `SerialNumberInput.tsx:279` |
| `limitReached` | "Limit has been reached. Only 300 items can be processed at a time." | `SerialNumberInput.tsx:280-281` |
| `notFound` | "Error: Please check the part number, serial number(s), facility, or hardware status..." | `SerialNumberInput.tsx:282-283` |
| `duplicateHardwareIssue` | "Serial numbers entered already have selected hardware events:" | `SerialNumberInput.tsx:284-285` |
| `enclosurePartNumberMismatch` | "Error: All enclosure serial numbers must have the same part number." | `SerialNumberInput.tsx:288-289` |
| `invalidSerialNumbers` | Dynamic list of specific invalid serials | `SerialNumberInput.tsx:296-304` |

---

## Code References

### Frontend
- `frontend/src/pages/TrackInventory.tsx:31` - Main page component
- `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx:101` - Form component
- `frontend/src/components/common/forms/SerialNumberInput.tsx:42` - Serial input component
- `frontend/src/components/TrackInventoryPage/useTrackInventorySubmit.ts:1` - Mutation hooks
- `frontend/src/shared/api/InventoryService.ts:1` - API service layer
- `frontend/src/hooks/services/track-inventory/useGetSpareInTransitInventory.ts:1` - Query hook

### Backend
- `lambdas/lf-vero-prod-inventory/main.py:9` - Lambda entry point
- `lambdas/lf-vero-prod-inventory/main.py:166-194` - Hub handler
- `lambdas/lf-vero-prod-inventory/main.py:226-250` - Sensor handler

### Database
- `mysql/db/procs/R__PROC_Inventory_AddTransponder.sql` - Hub assignment
- `mysql/db/procs/R__PROC_Inventory_AddSensor.sql` - Sensor assignment
- `mysql/db/procs/R__PROC_Inventory_AssignEnclosure.sql` - Enclosure assignment
- `mysql/db/procs/R__PROC_Inventory_CheckSerialNumbers.sql` - Serial validation
- `mysql/db/procs/R__PROC_Inventory_GetAllSpareInTransitInventory.sql` - Inventory listing

### Types
- `frontend/src/shared/types/track-inventory/Inventory.ts` - Inventory data type
- `frontend/src/shared/types/track-inventory/TrackInventorySubmitValues.ts` - Submit types
- `frontend/src/shared/types/track-inventory/SelectedInventory.ts` - Query parameters

---

## Architecture Documentation

### Data Flow Pattern
```
Frontend Component
    ↓ (uses)
React Query Hook (useQuery/useMutation)
    ↓ (calls)
Service Function (InventoryService.ts)
    ↓ (AWS Amplify API.post)
Lambda Handler (main.py)
    ↓ (routes by meth field)
MySQL Stored Procedure
    ↓ (returns)
Response bubbles back up
```

### Key Conventions
- Read operations use `/list` path
- Write operations use `/update` path
- Method name passed in `meth` field of request body
- Serial numbers passed as comma-separated strings
- Stored procedures parse serial number lists in loops
- All write operations use transactions with rollback handlers
- Error states return either "error" string (legacy) or throw errors (new pattern)

### Hardware Types Supported
| Type | Table | Status Table |
|------|-------|--------------|
| Sensors (Receivers) | `Receiver` | `Facility_Receiver` |
| Hubs (Transponders) | `Transponder` | `Facility_Transponder` |
| Hotspots (CradlePoint) | `CradlepointDevice` | `Facility_Cradlepoint` |
| Enclosures | `Enclosure` | `Facility_Enclosure` |

---

## Open Questions

1. **Partner Sensor List**: The `getPartnerSensorList` query is invalidated on every keystroke but it's unclear which UI component consumes this data and when it's displayed
2. **Enclosure Sub-Assembly Assignment**: The `Inventory_AssignEnclosureSubAssembly` procedure is called but its full logic wasn't traced
3. **Hardware Issue Mapping**: The `RemovalReasonHardwareIssueMap` creates hardware issues but the downstream effects weren't fully documented
