# IWA-11730: Duplicate Sensor Facility Records Bug Fix

## Overview

Fix the bug where sensors can exist in both `MonitoringPoint_Receiver` (with `ActiveFlag=1`) AND `Facility_Receiver` tables simultaneously, caused by the UpdateMonitoringPointModal tracking sensors for modification that the user didn't intend to modify.

**Root Cause:** The modal's `removedSensors` state accumulates ANY sensor that was typed and then cleared/changed, even if that sensor was never originally on the monitoring point. This causes "correction" scenarios (user types wrong serial, then corrects) to be treated as "removal" scenarios.

## Current State Analysis

### The Problem

When a user:
1. Types a wrong serial number (e.g., "8000017" from a different facility)
2. Clears or changes to the correct serial number (e.g., "8000015")

The modal still has "8000017" in `removedSensors` and may process it on submit, even though:
- The user's intent was to assign "8000015" only
- "8000017" was never the "real" sensor for this monitoring point
- "8000017" belongs to a completely different customer/facility

### Key Discoveries

1. **`removedSensors` accumulates but never auto-cleans** - sensors are added when cell values change, but only removed via explicit user action (clicking X button)
2. **No distinction between "original" vs "typed this session"** - the modal doesn't differentiate between sensors that were on the MP when it opened vs sensors the user typed during editing
3. **`originalMPs` exists but isn't used for filtering** - the modal captures a snapshot of the original state but doesn't use it to determine which sensors "really" need removal actions

### The Data Flow (Current - Buggy)

```
User types "8000017"     User clears cell        User types "8000015"     User saves
        │                       │                        │                    │
        ▼                       ▼                        ▼                    ▼
   grid: 8000017           grid: ""                 grid: 8000015       grid: 8000015
   removed: []             removed: [8000017]       removed: [8000017]  removed: [8000017] ❌
                                  ▲                                            │
                             BUG: Added                               MAY BE PROCESSED!
```

### The Data Flow (After Fix)

```
User types "8000017"     User clears cell        User types "8000015"     User saves
        │                       │                        │                    │
        ▼                       ▼                        ▼                    ▼
   grid: 8000017           grid: ""                 grid: 8000015       grid: 8000015
   removed: []             removed: []  ✅          removed: []  ✅     removed: []  ✅
                                  │
                           NOT ADDED: 8000017 was
                           not in originalMPs
```

## Desired End State

After this fix:

1. **Only original sensors are tracked for removal:** A sensor is only added to `removedSensors` if it was present in `originalMPs` when the modal opened
2. **Corrections are ignored:** If a user types a wrong serial and corrects it, the wrong serial is never added to any tracking list
3. **Real replacements still work:** If an MP originally had sensor A and user replaces with sensor B, sensor A is correctly tracked for removal

### Verification Scenarios

| Scenario | Expected Behavior |
|----------|-------------------|
| MP empty → user types wrong serial → corrects to right serial | Only right serial assigned, wrong serial NOT in `removedSensors` |
| MP has sensor A → user replaces with sensor B | Sensor A IS in `removedSensors`, sensor B assigned |
| MP has sensor A → user clears cell (removes sensor) | Sensor A IS in `removedSensors` |
| MP empty → user types serial → saves | Serial assigned, `removedSensors` empty |

## What We're NOT Doing (This Phase)

- **NOT fixing the stored procedure** (defense-in-depth fix, separate phase)
- **NOT adding database triggers** (long-term improvement, separate ticket)
- **NOT fixing `updateSensorsAndMpRef` cleanup** (it inherits from `removedSensors`, so fixing the source fixes this too)

## Implementation Approach

Add a check before adding sensors to `removedSensors`: only add if the sensor was in `originalMPs` for this monitoring point.

---

## Phase 1: Fix `removedSensors` Population Logic

### Overview

Modify the `onCellValueChanged` handler to only add sensors to `removedSensors` if they were originally assigned to the monitoring point when the modal opened.

### Changes Required

#### 1. Update `onCellValueChanged` in UpdateMonitoringPointModal.tsx

**File:** `frontend/src/components/UpdateMonitoringPointModal/UpdateMonitoringPointModal.tsx`
**Location:** Lines 965-994 (inside `onCellValueChanged`)

**Current Code (Buggy):**
```typescript
if (index === -1 && oldValue !== "") {
  const selectedPart = partList.find((part) => part.prid === oldValue);
  const smpn = colID === "ssn" ? originalRowData.smpn : selectedPart?.pn;
  const ssn = colID === "ssn" ? String(oldValue) : originalSSN;
  const pid = colID === "ssn" ? originalRowData.pid : selectedPart?.pid;

  const defaultProactiveReason = /* ... */;

  if (ssn) {
    sensorList.push({
      mpid,
      ssn,
      // ... other fields
    } as AssetMp);
    setRemovedSensors(sensorList);
  }
}
```

**Fixed Code:**
```typescript
if (index === -1 && oldValue !== "") {
  const selectedPart = partList.find((part) => part.prid === oldValue);
  const smpn = colID === "ssn" ? originalRowData.smpn : selectedPart?.pn;
  const ssn = colID === "ssn" ? String(oldValue) : originalSSN;
  const pid = colID === "ssn" ? originalRowData.pid : selectedPart?.pid;

  const defaultProactiveReason = /* ... */;

  // FIX: Only track sensors that were originally on this MP
  // If the sensor was typed during this session (not in originalMPs), don't add to removedSensors
  const originalMP = originalMPs.find((mp) => mp.mpid === mpid);
  const sensorWasOriginal = originalMP?.ssn === ssn;

  if (ssn && sensorWasOriginal) {
    sensorList.push({
      mpid,
      ssn,
      smpn,
      pid,
      sid: originalRowData.sid,
      fid: selectedFacility,
      rstid: FacilitySensorStatus.IN_TRANSIT,
      rrtid:
        originalRowData.defaultRemovalReasonTypeID ||
        defaultProactiveReason,
      rowIndex,
      deletemp: false,
      deletesensor: true,
      updated: true,
    } as AssetMp);
    setRemovedSensors(sensorList);
  }
}
```

**Key Changes:**
1. Added lookup of original MP by `mpid`: `const originalMP = originalMPs.find((mp) => mp.mpid === mpid);`
2. Added check if sensor was original: `const sensorWasOriginal = originalMP?.ssn === ssn;`
3. Changed condition from `if (ssn)` to `if (ssn && sensorWasOriginal)`

### Why This Works

| Scenario | `originalMP?.ssn` | `ssn` (oldValue) | `sensorWasOriginal` | Added to `removedSensors`? |
|----------|-------------------|------------------|---------------------|---------------------------|
| MP was empty, user typed wrong serial then cleared | `undefined` | "8000017" | `false` | ❌ No |
| MP had "A", user replaced with "B" | "A" | "A" | `true` | ✅ Yes |
| MP had "A", user cleared cell | "A" | "A" | `true` | ✅ Yes |
| MP was empty, user typed serial and kept it | `undefined` | N/A (oldValue empty) | N/A | ❌ No (exits early) |

### Success Criteria

#### Automated Verification
- [x] TypeScript compiles: `cd frontend && npm run typecheck`
- [x] Linting passes: `cd frontend && npm run lint`
- [x] Existing tests pass: `cd frontend && npm test -- --testPathPattern="UpdateMonitoringPointModal"`

#### Manual Verification
- [x] **Bug scenario test:**
  1. Open Add/Edit MP modal for an MP with NO sensor
  2. Type wrong serial number (from different facility)
  3. Accept the cross-facility warning
  4. Clear the cell, type correct serial number
  5. Click Save
  6. **Verify:** Only the correct sensor is assigned, wrong sensor NOT in any inventory

- [x] **Replacement scenario test:**
  1. Open Add/Edit MP modal for an MP WITH an existing sensor
  2. Type a new serial number (replacing the old one)
  3. Confirm the removal in RemoveSensor UI
  4. Click Save
  5. **Verify:** Old sensor is correctly moved to inventory, new sensor is assigned

- [x] **Simple assignment test:**
  1. Open Add/Edit MP modal for an MP with NO sensor
  2. Type correct serial number
  3. Click Save
  4. **Verify:** Sensor is assigned, no inventory operations

**Implementation Note:** After completing this phase and all verification passes, pause for manual confirmation before proceeding.

---

## Phase 2: Add Unit Tests (Optional Enhancement)

### Overview

Add test coverage for the new behavior to prevent regression.

### Test Cases to Add

**File:** `frontend/src/components/UpdateMonitoringPointModal/tests/UpdateMonitoringPointModal.test.tsx` (or new test file)

```typescript
describe('removedSensors state management', () => {
  it('should NOT add sensor to removedSensors when MP was originally empty', () => {
    // Setup: MP with no original sensor
    // Action: User types serial, then clears
    // Assert: removedSensors is empty
  });

  it('should ADD sensor to removedSensors when replacing original sensor', () => {
    // Setup: MP with original sensor "A"
    // Action: User types serial "B"
    // Assert: removedSensors contains "A"
  });

  it('should ADD sensor to removedSensors when clearing original sensor', () => {
    // Setup: MP with original sensor "A"
    // Action: User clears cell
    // Assert: removedSensors contains "A"
  });
});
```

### Success Criteria

#### Automated Verification
- [ ] New tests pass: `cd frontend && npm test -- --testPathPattern="removedSensors"`

---

## Testing Strategy

### Unit Tests
- Test `removedSensors` population logic in isolation
- Mock `originalMPs` to simulate different scenarios

### Integration Tests
- Test full modal flow with AG-Grid interactions

### Manual Testing Steps

1. **Bug reproduction test:**
   - Follow exact reproduction steps from research doc
   - Verify bug no longer occurs

2. **Regression test - replacement workflow:**
   - Ensure normal sensor replacement still works
   - Old sensor should still go to RemoveSensor UI

3. **Regression test - removal workflow:**
   - Ensure removing sensor from MP still works
   - Sensor should appear in RemoveSensor UI for confirmation

4. **Edge case - multiple MPs:**
   - Edit multiple MPs in one session
   - Mix of empty MPs and MPs with sensors
   - Verify correct behavior for each

## Performance Considerations

- The `originalMPs.find()` lookup is O(n) but `originalMPs` is typically small (< 100 items)
- No significant performance impact expected

## Rollback Plan

- Revert the single line change in `UpdateMonitoringPointModal.tsx`
- No database changes, no migration needed

## References

- Problem analysis: `thoughts/shared/research/2026-01-26-IWA-11730-modal-state-management-problem.md`
- Original investigation: `thoughts/shared/research/2026-01-23-IWA-11730-duplicate-sensor-facility-records.md`
- Bug reproduction: Section "Bug Reproduction (2026-01-26)" in original investigation

---

## Future Phases (Separate Tickets)

### Phase 3: Stored Procedure Defense-in-Depth (Future)

Fix `FacilityReceiver_UpdateReceiverStatus` to properly deactivate `MonitoringPoint_Receiver` records. This provides a safety net even if frontend has bugs.

**Details:** See `thoughts/shared/research/2026-01-23-IWA-11730-duplicate-sensor-facility-records.md` section "Code Path Analysis"

### Phase 4: Database Trigger (Future)

Add a BEFORE INSERT trigger on `Facility_Receiver` to prevent sensors with active `MonitoringPoint_Receiver` records from being added to inventory.

### Phase 5: Data Cleanup (Future)

Clean up existing duplicate records in production after fixes are deployed.
