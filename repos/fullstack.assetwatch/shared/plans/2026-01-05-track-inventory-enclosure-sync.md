# Track Inventory Enclosure Synchronization Fix

## Overview

Fix the Track Inventory page so that when a user moves a standalone hub or hotspot that is part of an enclosure, the partner component (hotspot or hub respectively) is also moved to the same facility. This mirrors the correct behavior already implemented in the Customer Detail page's AddHubs and AddHotspot components.

## Current State Analysis

### The Bug
When a hub and hotspot are physically contained in an enclosure (linked via `EnclosureID`), moving either component independently via Track Inventory does **not** cascade the move to the partner component. This can result in:
- Hub at Facility A, Hotspot at Facility B, even though they're in the same physical enclosure
- Data integrity issues in the `Facility_Enclosure`, `Facility_Transponder`, and `Facility_CradlepointDevice` tables

### Working Reference Implementation
The Customer Detail page (`AddHubs.tsx` and `AddHotspot.tsx`) handles this correctly:
1. Detects enclosure relationships via `getHubHotspotEnclosureInfo()`
2. Shows a warning modal to the user
3. Requires NetCloud group selection for hotspot moves
4. Cascades the move to all three: hub, hotspot, and enclosure

### Track Inventory Current Behavior
- **Hub-Hotspot Enclosure product type** (`isHubHotspotEnclosure`): Works correctly - cascades moves
- **Standalone Hub product type** (`isHub`): Does NOT check for enclosure or cascade
- **Standalone Hotspot product type** (`isCradlePoint`): Does NOT check for enclosure or cascade

### Key Code References
- `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx:821-831` - Standalone hub move (bug location)
- `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx:762-791` - Standalone hotspot move (bug location)
- `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx:855-906` - Hub-Hotspot enclosure move (correct implementation)
- `frontend/src/components/CustomerDetailPage/Hubs/AddHubs.tsx:221-295` - Reference implementation for hub cascade
- `frontend/src/components/CustomerDetailPage/Hotspots/AddHotspot.tsx:344-437` - Reference implementation for hotspot cascade

## Desired End State

After this fix is complete:
1. When a user moves a standalone hub that is part of an enclosure, the system will:
   - Detect the enclosure relationship
   - Show a warning modal explaining the cascade
   - Require NetCloud group selection for the hotspot
   - Move both the hub AND the hotspot to the new facility
   - Update the enclosure's facility assignment

2. When a user moves a standalone hotspot that is part of an enclosure, the system will:
   - Detect the enclosure relationship
   - Show a warning modal explaining the cascade
   - Move both the hotspot AND the hub to the new facility
   - Update the enclosure's facility assignment

### Verification
- Move a hub that is in an enclosure via Track Inventory standalone hub product type
- Verify both hub AND hotspot facility assignments are updated in the database
- Verify `Facility_Enclosure` record is updated
- Repeat for hotspot-initiated move

## What We're NOT Doing

1. **No stored procedure changes** - Fix is frontend-only to minimize scope
2. **No changes to the Hub-Hotspot Enclosure product type** - Already works correctly
3. **No changes to sensor/PBSM moves** - Not related to enclosures
4. **No UI redesign** - Reusing existing components (ModalAlert, InventoryHotspotGroupSelection)
5. **No backend validation changes** - Relying on frontend orchestration

## Implementation Approach

Follow the Customer Detail pattern: detect enclosure → warn user → require group selection → cascade move.

Reuse existing Track Inventory infrastructure:
- `getHubHotspotEnclosureInfo()` - already imported
- `ModalAlert` component - already imported and used
- `InventoryHotspotGroupSelection` component - already used
- `groupId` state and `completeGroupList` data - already available
- `addCradlePointMutation` and `addHubsMutation` - already available
- `updateCradlepointEnclosureFacility` - needs to be imported

---

## Phase 1: Add State Variables for Enclosure Detection

### Overview
Add new state variables to track enclosure detection, similar to Customer Detail's pattern.

### Changes Required:

#### 1. Add State Variables
**File**: `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx`
**Location**: After line 153 (after `enclosurePartId` state)

```typescript
// Enclosure cascade state - for standalone hub/hotspot moves
const [showEnclosureGroupDropdown, setShowEnclosureGroupDropdown] = useState<boolean>(false);
const [enclosureAlertOpen, setEnclosureAlertOpen] = useState<boolean>(false);
const [continueEnclosureMove, setContinueEnclosureMove] = useState<boolean>(false);
const [detectedEnclosureInfo, setDetectedEnclosureInfo] = useState<EnclosureComponentInfo[]>([]);
const [detectedHotspotProductId, setDetectedHotspotProductId] = useState<number | undefined>();
```

#### 2. Add Import for updateCradlepointEnclosureFacility
**File**: `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx`
**Location**: Line 1-4 (imports from CradlePointService)

Update the import to include `updateCradlepointEnclosureFacility`:
```typescript
import {
  checkCradlepointAvailability,
  getHubHotspotEnclosureInfo,
  updateCradlepointEnclosureFacility,
} from "@api/CradlePointService";
```

#### 3. Add Import for EnclosureComponentInfo Type
**File**: `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx`
**Location**: Near other type imports

```typescript
import { EnclosureComponentInfo } from "@shared/types/hubs/EnclosureComponentInfo";
```

### Success Criteria:

#### Automated Verification:
- [x] Run `/rpi:test-runner` to verify TypeScript compilation and linting pass (compares to baseline to distinguish NEW failures) ✅ No NEW failures

#### Manual Verification:
- [ ] Track Inventory page loads without errors
- [ ] No console errors related to new state variables

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Phase 2.

---

## Phase 2: Add Enclosure Detection to Standalone Hub Path

### Overview
Modify the `processBulkImport` function's `isHub` path to detect enclosures and handle the cascade. Following the Customer Detail pattern: move ALL hubs first, then cascade to hotspots for those that have enclosures.

### Changes Required:

#### 1. Modify processBulkImport for isHub Case
**File**: `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx`
**Location**: Lines 821-831 (the `else if (isHub)` block)

Replace the existing `isHub` block with enclosure-aware logic:

```typescript
} else if (isHub) {
  // Check if any hub is part of an enclosure
  const hubsWithEnclosure = await getHubHotspotEnclosureInfo({
    hubSerialList: validSerialNumbers,
  });

  if (typeof hubsWithEnclosure === "string") {
    toast.error("Error checking enclosure info");
    setAddStatus(false);
    return;
  }

  // Filter to only hubs that ARE in enclosures with hotspots
  const enclosuredHubs = hubsWithEnclosure.filter(
    (e) => e.enclosureId !== null && e.cradlepointMac !== null
  );

  // If ANY enclosure detected and user hasn't confirmed yet, show warning
  if (enclosuredHubs.length > 0 && !continueEnclosureMove) {
    setDetectedEnclosureInfo(enclosuredHubs);
    const productId = enclosuredHubs[0]?.cradlepointProductId;
    setDetectedHotspotProductId(productId ?? undefined);
    setShowEnclosureGroupDropdown(true);
    setEnclosureAlertOpen(true);
    setAddStatus(false);
    return;
  }

  // If enclosure detected and user confirmed, require group selection
  if (enclosuredHubs.length > 0 && continueEnclosureMove && !groupId) {
    toast.error("Please select a NetCloud group for the linked hotspot");
    setAddStatus(false);
    return;
  }

  // Move ALL hubs first (matches Customer Detail pattern)
  addHubsMutation.mutate({
    hubSerialNumberList: snList,
    facilityId: selectedFacility,
    hubStatusId: selectedStatus,
    partId,
    fundingProjectId: selectedFundingProjectId ?? 0,
    removalReasonTypeId,
    enclosurePartId,
    removalReason: removalReason ?? null,
  });

  // If there are enclosured hubs, cascade to their hotspots
  if (enclosuredHubs.length > 0 && continueEnclosureMove) {
    const extfacilityId = inventoryFacilityList.find(
      (f) => f.fid === parseInt(selectedFacility)
    )?.extfid ?? "";

    const foundGroup = completeGroupList.find(
      (g) => g.id === parseInt(groupId)
    );

    const hotspotMoves = enclosuredHubs
      .filter((e): e is EnclosureComponentInfo & { cradlepointMac: string; cradlepointPartId: number } =>
        e.cradlepointMac !== null && e.cradlepointPartId !== null
      )
      .map((enclosure) =>
        addCradlePointMutation.mutateAsync({
          macAddresses: enclosure.cradlepointMac,
          extfacilityId,
          cradlePointStatusId: selectedStatus,
          fundingProjectId: selectedFundingProjectId,
          groupURL: foundGroup?.url,
          partId: enclosure.cradlepointPartId?.toString(),
          removalReasonTypeId: removalReason?.removalTypeID || removalReasonTypeId,
        })
      );

    const enclosureMove = updateCradlepointEnclosureFacility({
      enclosureIdList: enclosuredHubs
        .map((e) => e.enclosureId)
        .filter((id): id is number => id !== null)
        .toString(),
      fid: parseInt(selectedFacility),
      facilityEnclosureStatusId: parseInt(selectedStatus),
      removalReasonId: removalReason?.removalTypeID ?? 0,
    });

    try {
      await Promise.all([...hotspotMoves, enclosureMove]);
      const hubSerials = enclosuredHubs.map((e) => e.transponderSerialNumber).join(", ");
      const hotspotMacs = enclosuredHubs.map((e) => e.cradlepointMac).join(", ");
      toast.success(
        `Successfully moved enclosed hotspots to the selected facility with their linked hubs.\n\nHotspots: ${hotspotMacs}\nHubs: ${hubSerials}`
      );
    } catch (error) {
      toast.error("Failed to move linked hotspots");
    }

    // Reset enclosure state
    setContinueEnclosureMove(false);
    setShowEnclosureGroupDropdown(false);
    setDetectedEnclosureInfo([]);
  }
}
```

**Key Pattern**: This follows the Customer Detail `AddHubs.tsx` approach:
1. Move ALL hubs via `addHubsMutation` (line 232 in AddHubs.tsx)
2. THEN cascade to hotspots only for those with enclosures (lines 243-295 in AddHubs.tsx)
3. Mixed batches (some enclosured, some not) are handled automatically - all hubs move, only enclosured ones cascade

### Success Criteria:

#### Automated Verification:
- [x] Run `/rpi:test-runner` to verify TypeScript compilation and linting pass (compares to baseline to distinguish NEW failures) ✅ No NEW failures

#### Manual Verification:
- [ ] Moving a standalone hub NOT in an enclosure works as before
- [ ] Moving a standalone hub IN an enclosure triggers the enclosure detection (will fail until Phase 4 adds the modal)

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Phase 3.

---

## Phase 3: Add Enclosure Detection to Standalone Hotspot Path

### Overview
Modify the `handleCradlePointMutation` function to detect enclosures and handle the cascade. Following the Customer Detail pattern: move ALL hotspots first, then cascade to hubs for those that have enclosures.

### Changes Required:

#### 1. Modify handleCradlePointMutation
**File**: `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx`
**Location**: Lines 762-791 (the `handleCradlePointMutation` function)

Replace with enclosure-aware logic:

```typescript
const handleCradlePointMutation = async (
  removalReason?: ReceiverRemovalType,
): Promise<void> => {
  const extfacilityId = selectedFacility
    ? inventoryFacilityList.filter(
        (f) => f.fid === parseInt(selectedFacility),
      )[0].extfid
    : "4aef86b4-3fab-4765-aff0-ab4cc32ee24a";

  const foundGroup = completeGroupList.find(
    (g) => g.id === parseInt(groupId),
  );

  if (foundGroup && foundGroup.productId !== parseInt(productId)) {
    setAddStatus(false);
    toast.warn("The selected group does not support the selected product.", {
      autoClose: 3500,
    });
    return;
  }

  // Check if any hotspot is part of an enclosure
  const hotspotsWithEnclosure = await getHubHotspotEnclosureInfo({
    cpMacList: validSerialNumbers,
  });

  if (typeof hotspotsWithEnclosure === "string") {
    toast.error("Error checking enclosure info");
    setAddStatus(false);
    return;
  }

  // Filter to only hotspots that ARE in enclosures with hubs
  const enclosuredHotspots = hotspotsWithEnclosure.filter(
    (e) => e.enclosureId !== null && e.transponderSerialNumber !== null
  );

  // If ANY enclosure detected and user hasn't confirmed yet, show warning
  if (enclosuredHotspots.length > 0 && !continueEnclosureMove) {
    setDetectedEnclosureInfo(enclosuredHotspots);
    setEnclosureAlertOpen(true);
    setAddStatus(false);
    return;
  }

  // Move ALL hotspots first (matches Customer Detail pattern)
  addCradlePointMutation.mutate({
    macAddresses: validSerialNumbers.join(","),
    extfacilityId,
    cradlePointStatusId: selectedStatus,
    fundingProjectId: selectedFundingProjectId,
    groupURL: foundGroup?.url,
    partId,
    removalReasonTypeId: removalReason?.removalTypeID || removalReasonTypeId,
  });

  // If there are enclosured hotspots, cascade to their hubs
  if (enclosuredHotspots.length > 0 && continueEnclosureMove) {
    const hubSerials = enclosuredHotspots
      .map((e) => e.transponderSerialNumber)
      .filter((s): s is string => s !== null)
      .join(",");

    // Move the hub(s)
    addHubsMutation.mutate({
      hubSerialNumberList: hubSerials,
      facilityId: selectedFacility,
      hubStatusId: selectedStatus,
      partId: enclosuredHotspots[0]?.transponderPartId?.toString() ?? "",
      fundingProjectId: selectedFundingProjectId ?? 0,
      removalReasonTypeId: removalReason?.removalTypeID?.toString() || removalReasonTypeId,
      enclosurePartId: "",
      removalReason: removalReason ?? null,
    });

    // Update enclosure facility
    try {
      await updateCradlepointEnclosureFacility({
        enclosureIdList: enclosuredHotspots
          .map((e) => e.enclosureId)
          .filter((id): id is number => id !== null)
          .toString(),
        fid: parseInt(selectedFacility),
        facilityEnclosureStatusId: parseInt(selectedStatus),
        removalReasonId: removalReason?.removalTypeID ?? 0,
      });

      const hubSerialsList = enclosuredHotspots.map((e) => e.transponderSerialNumber).join(", ");
      const hotspotMacs = enclosuredHotspots.map((e) => e.cradlepointMac).join(", ");
      toast.success(
        `Successfully moved enclosed hotspots to the selected facility with their linked hubs.\n\nHotspots: ${hotspotMacs}\nHubs: ${hubSerialsList}`
      );
    } catch (error) {
      toast.error("Failed to move linked hubs");
    }

    // Reset enclosure state
    setContinueEnclosureMove(false);
    setDetectedEnclosureInfo([]);
  }
};
```

**Key Pattern**: This follows the Customer Detail `AddHotspot.tsx` approach:
1. Move ALL hotspots via `addCradlePointMutation` (line 374 in AddHotspot.tsx)
2. THEN cascade to hubs only for those with enclosures (lines 403-437 in AddHotspot.tsx)
3. Mixed batches (some enclosured, some not) are handled automatically - all hotspots move, only enclosured ones cascade

### Success Criteria:

#### Automated Verification:
- [x] Run `/rpi:test-runner` to verify TypeScript compilation and linting pass (compares to baseline to distinguish NEW failures) ✅ No NEW failures

#### Manual Verification:
- [ ] Moving a standalone hotspot NOT in an enclosure works as before
- [ ] Moving a standalone hotspot IN an enclosure triggers the enclosure detection

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Phase 4.

---

## Phase 4: Add UI Components for Enclosure Warning and Group Selection

### Overview
Add the warning modal and conditional NetCloud group dropdown for enclosure cascade scenarios.

### Changes Required:

#### 1. Update Group Dropdown Conditional Display
**File**: `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx`
**Location**: Lines 1243-1256 (the group dropdown render condition)

Update the condition to include `showEnclosureGroupDropdown`:

```typescript
{(isCradlePoint ||
  isHotspotEnclosure ||
  isHubHotspotEnclosure ||
  showEnclosureGroupDropdown) && (
  <Grid.Col span={{ base: 12, md: 4 }}>
    <Space h={"xl"} />

    <InventoryHotspotGroupSelection
      groupList={showEnclosureGroupDropdown
        ? completeGroupList.filter(
            (g) => g.productId === detectedHotspotProductId
          )
        : filteredGroupList}
      groupID={groupId}
      netcloudGroupListDidLoad={netcloudGroupListDidLoad}
      setGroupID={setGroupId}
    />
  </Grid.Col>
)}
```

#### 2. Add Enclosure Warning Modal
**File**: `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx`
**Location**: After the existing ModalAlert (after line 1289)

```typescript
<ModalAlert
  showAlert={enclosureAlertOpen}
  alertMessage={`The selected ${isHub ? "hub(s)" : "hotspot(s)"} ${
    detectedEnclosureInfo.map((e) => isHub ? e.transponderSerialNumber : e.cradlepointMac).join(", ")
  } ${detectedEnclosureInfo.length === 1 ? "is" : "are"} part of an enclosure and will be moved along with the linked ${
    isHub ? "hotspot(s)" : "hub(s)"
  }: ${
    detectedEnclosureInfo.map((e) => isHub ? e.cradlepointMac : e.transponderSerialNumber).join(", ")
  }. ${isHub ? "Please select a NetCloud group and then " : ""}Click Continue to proceed.`}
  handleClose={() => {
    setEnclosureAlertOpen(false);
    setShowEnclosureGroupDropdown(false);
    setDetectedEnclosureInfo([]);
    setAddStatus(false);
  }}
  handleSubmit={() => {
    setContinueEnclosureMove(true);
    setEnclosureAlertOpen(false);
  }}
  buttonDisplay
  buttonLabel="Continue"
/>
```

#### 3. Update Submit Button Disabled State
**File**: `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx`
**Location**: Lines 1265-1272 (the disabled condition for Add Inventory button)

Update to require group selection when enclosure dropdown is shown:

```typescript
disabled={
  Object.values(errors).some((val) => val === true) ||
  addStatus ||
  validSerialNumbers.length === 0 ||
  !selectedFacility ||
  !selectedStatus ||
  ((isCradlePoint || isHotspotEnclosure || showEnclosureGroupDropdown) && !groupId)
}
```

#### 4. Reset Enclosure State on Form Reset
**File**: `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx`
**Location**: Find where form state is reset (likely in a useEffect or handler after successful submission)

Add reset logic for enclosure state:

```typescript
// Add to any form reset logic
setShowEnclosureGroupDropdown(false);
setEnclosureAlertOpen(false);
setContinueEnclosureMove(false);
setDetectedEnclosureInfo([]);
setDetectedHotspotProductId(undefined);
```

### Success Criteria:

#### Automated Verification:
- [x] Run `/rpi:test-runner` to verify TypeScript compilation and linting pass (compares to baseline to distinguish NEW failures) ✅ No NEW failures from our changes

#### Manual Verification:
- [ ] Moving a standalone hub IN an enclosure shows the warning modal
- [ ] Warning modal displays correct serial numbers and MAC addresses
- [ ] Clicking "Continue" closes the modal and shows NetCloud group dropdown
- [ ] Selecting a group and clicking "Add Inventory" completes the cascade move
- [ ] Database shows both hub and hotspot at the new facility
- [ ] Moving a standalone hotspot IN an enclosure shows the warning modal
- [ ] Cascade completes correctly for hotspot-initiated moves
- [ ] Clicking cancel/close on the modal resets the form state

**Implementation Note**: After completing this phase and all automated verification passes, pause here for comprehensive manual testing before considering the fix complete.

---

## Phase 5: State Cleanup and Error Handling

### Overview
Ensure proper cleanup of enclosure state after moves and handle error scenarios gracefully.

### Changes Required:

#### 1. Mixed Batch Handling (No Code Change Needed)
Following the Customer Detail pattern, mixed batches are handled automatically:
- Warning modal shows ONLY the enclosure-linked items
- ALL items move together when user confirms
- Cascade only applies to enclosure-linked items
- No additional info toast needed (Customer Detail doesn't show one either)

#### 2. Reset State After Successful Move
Ensure all enclosure-related state is cleared after successful moves.

**File**: `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx`

Add to the `addHubsMutation.onSuccess` and `addCradlePointMutation.onSuccess` handlers in `useTrackInventorySubmit.ts`, or ensure the reset happens at the end of `processBulkImport`:

```typescript
// Reset enclosure state after successful move
setShowEnclosureGroupDropdown(false);
setEnclosureAlertOpen(false);
setContinueEnclosureMove(false);
setDetectedEnclosureInfo([]);
setDetectedHotspotProductId(undefined);
```

#### 3. Handle Error Recovery
Already included in Phase 2 and 3 with try/catch blocks. If the primary move succeeds but cascade fails:
- Primary items are moved (committed)
- Error toast shown for cascade failure
- User can manually retry the cascade or use Hub-Hotspot Enclosure product type

### Success Criteria:

#### Automated Verification:
- [x] Run `/rpi:test-runner` to verify TypeScript compilation and linting pass (compares to baseline to distinguish NEW failures) ✅ No NEW failures from enclosure sync changes

#### Manual Verification:
- [ ] Moving a batch of hubs where some are in enclosures and some are not - all hubs move, enclosured ones cascade
- [ ] Error scenarios show appropriate error messages
- [ ] Form state resets properly after both successful and failed moves
- [ ] Closing the warning modal resets all enclosure state

---

## Testing Strategy

### Unit Tests:
Not adding new unit tests for this fix as it primarily involves UI orchestration logic. The existing API functions and mutations are already tested.

### Integration Tests:
Not applicable for frontend-only change.

### Manual Testing Steps:

#### Scenario 1: Standalone Hub in Enclosure
1. Identify a hub that is part of an enclosure (has EnclosureID, paired with a hotspot)
2. Go to Track Inventory page
3. Select a Hub product type (e.g., Hub v3)
4. Enter the hub serial number
5. Select a different facility than current
6. Click "Add Inventory"
7. **Expected**: Warning modal appears explaining cascade
8. Click "Continue"
9. **Expected**: NetCloud group dropdown appears
10. Select a NetCloud group
11. Click "Add Inventory" again
12. **Expected**: Success toast mentions both hub and hotspot
13. **Verify in database**: Both `Facility_Transponder` and `Facility_CradlepointDevice` have new records for the target facility

#### Scenario 2: Standalone Hotspot in Enclosure
1. Identify a hotspot that is part of an enclosure
2. Go to Track Inventory page
3. Select a Hotspot product type (e.g., Cradlepoint)
4. Enter the hotspot MAC address
5. Select NetCloud group
6. Select a different facility than current
7. Click "Add Inventory"
8. **Expected**: Warning modal appears explaining cascade
9. Click "Continue"
10. Click "Add Inventory" again
11. **Expected**: Success toast mentions both hotspot and hub
12. **Verify in database**: Both records updated

#### Scenario 3: Hub NOT in Enclosure
1. Identify a hub without an EnclosureID
2. Move it via Track Inventory
3. **Expected**: No warning modal, normal move completes

#### Scenario 4: Mixed Batch (Some Hubs in Enclosures, Some Not)
1. Identify 3 hubs: Hub-A (in enclosure with Hotspot-X), Hub-B (standalone), Hub-C (in enclosure with Hotspot-Y)
2. Go to Track Inventory page
3. Select Hub product type
4. Enter all 3 serial numbers: Hub-A, Hub-B, Hub-C
5. Select a different facility than current
6. Click "Add Inventory"
7. **Expected**: Warning modal shows ONLY Hub-A and Hub-C with their linked hotspots
8. Click "Continue", select NetCloud group
9. Click "Add Inventory" again
10. **Expected**:
    - First toast: "Hub(s) Successfully Added!" (all 3 hubs moved)
    - Second toast: "Successfully moved enclosed hotspots..." (only mentions Hub-A, Hub-C, Hotspot-X, Hotspot-Y)
11. **Verify in database**: All 3 hubs moved, plus Hotspot-X and Hotspot-Y cascaded

#### Scenario 5: Cancel Enclosure Move
1. Trigger the enclosure warning modal
2. Click close/cancel
3. **Expected**: Form state resets, no move occurs

## Performance Considerations

- The `getHubHotspotEnclosureInfo` API call adds one additional network request before hub/hotspot moves
- This is acceptable as it's necessary for data integrity
- The call is lightweight (just checking EnclosureID relationships)

## Migration Notes

No migration needed - this is a frontend behavior change only.

## References

- Original research: `thoughts/shared/research/2026-01-05-track-inventory-page-functionality.md`
- Reference implementation (hub): `frontend/src/components/CustomerDetailPage/Hubs/AddHubs.tsx:221-295`
- Reference implementation (hotspot): `frontend/src/components/CustomerDetailPage/Hotspots/AddHotspot.tsx:344-437`
- Bug location (hub): `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx:821-831`
- Bug location (hotspot): `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx:762-791`
