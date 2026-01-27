# IWA-11730: UpdateMonitoringPointModal State Management Problem

## Problem Statement

The **UpdateMonitoringPointModal** (also known as "Add/Edit MP" modal) tracks sensors for modification using internal lists, but **these lists do not accurately reflect the user's intent**. Sensors get added to tracking lists and are never removed, even when the user corrects a mistake.

## The Core Issue

When a user:
1. Types a serial number (intentionally or by mistake)
2. Later changes or clears that serial number

The modal **still remembers** the first serial number and may process it on submit, even though the user's final intent was to NOT modify that sensor.

---

## Internal State Tracking Overview

The modal uses **two separate tracking mechanisms** for sensors that need modification:

| Tracking Mechanism | Type | Purpose | Problem |
|-------------------|------|---------|---------|
| `removedSensors` | `useState<AssetMp[]>` | UI display - shows sensors pending removal confirmation | **Accumulates but never auto-cleans** |
| `updateSensorsAndMpRef` | `useRef<AssetMp[]>` | Submit processing - sensors to update via API | Only populated when user confirms in RemoveSensor UI |

### File Locations

- `removedSensors`: `frontend/src/components/UpdateMonitoringPointModal/UpdateMonitoringPointModal.tsx:154`
- `updateSensorsAndMpRef`: `frontend/src/components/UpdateMonitoringPointModal/hooks/useMonitoringPointSubmit.ts:159`

---

## When Sensors Are ADDED to `removedSensors`

| Trigger | What Happens | File:Line |
|---------|--------------|-----------|
| User types NEW serial over EXISTING | Old serial added to `removedSensors` | `UpdateMonitoringPointModal.tsx:965-994` |
| User clears a cell that HAD a serial | Old serial added to `removedSensors` | `UpdateMonitoringPointModal.tsx:965-994` |
| User changes part number on MP with sensor | Old sensor added to `removedSensors` | `UpdateMonitoringPointModal.tsx:669-703` |
| User clicks "Remove Selected MPs" | MP's sensor added to `removedSensors` | `UpdateMonitoringPointModal.tsx:414-487` |

## When Sensors Are REMOVED from `removedSensors`

| Trigger | What Happens | File:Line |
|---------|--------------|-----------|
| User clicks "X" button in RemoveSensor UI | Sensor removed from `removedSensors` | `UpdateMonitoringPointModal.tsx:489-548` |
| Modal closes/resets | List cleared | `UpdateMonitoringPointModal.tsx:564-581` |
| Submit completes | List cleared | `useMonitoringPointSubmit.ts:639` |

### CRITICAL GAP: What DOESN'T Remove Sensors

| User Action | Expected Behavior | Actual Behavior |
|-------------|-------------------|-----------------|
| User clears cell and types DIFFERENT serial | Remove old serial from tracking | ❌ Old serial STAYS in `removedSensors` |
| User clicks "No" on cross-facility warning | Don't track sensor | ❌ N/A (not added at this point) |
| User types wrong serial, then correct serial | Only track correct serial | ❌ Wrong serial added when cleared, never removed |

---

## Bug Scenario: Step-by-Step Trace

### Scenario: User types wrong serial, corrects it, saves

**Setup:**
- User opens modal for an MP that has NO sensor assigned
- They want to assign sensor "8000015"
- They accidentally type "8000017" first (which belongs to a different facility)

### Step 1: User opens modal

```
removedSensors: []
gridData[0].ssn: null  (no sensor on this MP)
```

### Step 2: User types "8000017" (wrong serial)

The `onCellValueChanged` function fires:
- `newValue`: "8000017"
- `oldValue`: "" (empty - no previous sensor)

**Code path (lines 954-956):**
```typescript
if (!oldValue) {
  return;  // EXITS EARLY - nothing added to removedSensors
}
```

```
removedSensors: []  // Still empty
gridData[0].ssn: "8000017"
```

### Step 3: Cross-facility warning appears, user clicks "Yes"

**Code path (lines 842-846):**
```typescript
if (shouldUseRSN) {
  data.ssnIsValid = true;
  data.rrtid = RemovalReasonType.HUMAN_ERROR;
  rowNode.setData(data);
}
```

```
removedSensors: []  // Still empty
gridData[0].ssn: "8000017"
gridData[0].rrtid: HUMAN_ERROR
```

### Step 4: User realizes mistake, CLEARS the cell

The `onCellValueChanged` function fires:
- `newValue`: "" (cleared)
- `oldValue`: "8000017"

**Code path (lines 954-994):**
```typescript
if (!oldValue) {
  return;  // Does NOT return - oldValue is "8000017"
}

// ... index check ...

if (index === -1 && oldValue !== "") {
  // ...
  sensorList.push({
    ssn: "8000017",  // THE WRONG SENSOR!
    deletesensor: true,
    updated: true,
    // ...
  });
  setRemovedSensors(sensorList);  // ADDS WRONG SENSOR!
}
```

```
removedSensors: [{ ssn: "8000017", deletesensor: true, ... }]  // BUG!
gridData[0].ssn: ""
```

### Step 5: User types "8000015" (correct serial)

The `onCellValueChanged` function fires:
- `newValue`: "8000015"
- `oldValue`: "" (cell was empty)

**Code path (lines 954-956):**
```typescript
if (!oldValue) {
  return;  // EXITS EARLY - nothing changes in removedSensors
}
```

```
removedSensors: [{ ssn: "8000017", ... }]  // WRONG SENSOR STILL THERE!
gridData[0].ssn: "8000015"  // Correct sensor in grid
```

### Step 6: User clicks Save

**What happens:**
- `gridData[0]` has the correct serial "8000015" ✅
- `removedSensors` still contains "8000017" ❌

**If user had interacted with the RemoveSensor UI before saving:**
- The RemoveSensor component would show "8000017" as needing removal confirmation
- If user clicked "Confirm" (thinking it was for something else), "8000017" would be pushed to `updateSensorsAndMpRef`
- On submit, `updateSensorFacilityAndStatusAPI` would be called for "8000017"
- The stored procedure would add "8000017" to the user's inventory facility
- **Result:** A sensor at a completely different customer now has a ghost `Facility_Receiver` record

---

## The Fundamental Design Flaw

The modal was designed with this mental model:

```
User types over existing sensor → Old sensor goes to "removed" list → User confirms removal → Sensor processed on submit
```

But this doesn't account for:

```
User types wrong serial → User clears/changes to correct serial → OLD (wrong) serial should be FORGOTTEN
```

### The Missing Logic

When a serial number is entered in a cell, the modal should check:
1. Is there already an entry in `removedSensors` for this MP/row?
2. If yes, is that entry the sensor we're now assigning?
3. If the entry is DIFFERENT from what's now in the grid, it means the user corrected their mistake

**Example:**
- `removedSensors` has entry: `{ rowIndex: 0, ssn: "8000017" }`
- `gridData[0].ssn` is now: `"8000015"`
- These don't match → The "8000017" entry is stale and should be removed

---

## Visual Diagram: Current vs Expected Behavior

### Current (Buggy) Behavior

```
User types "8000017"     User clears cell        User types "8000015"     User saves
        │                       │                        │                    │
        ▼                       ▼                        ▼                    ▼
   grid: 8000017           grid: ""                 grid: 8000015       grid: 8000015
   removed: []             removed: [8000017]       removed: [8000017]  removed: [8000017] ❌
                                  ▲                                            │
                                  │                                            ▼
                           BUG: Added here                        MAY BE PROCESSED!
```

### Expected Behavior

```
User types "8000017"     User clears cell        User types "8000015"     User saves
        │                       │                        │                    │
        ▼                       ▼                        ▼                    ▼
   grid: 8000017           grid: ""                 grid: 8000015       grid: 8000015
   removed: []             removed: [8000017]       removed: []  ✅     removed: []  ✅
                                  ▲                        ▲
                                  │                        │
                           Added here              REMOVED: User corrected,
                                                   8000017 was never the
                                                   "real" sensor for this MP
```

---

## Questions to Consider Before Fixing

1. **When should a sensor in `removedSensors` be kept vs removed?**
   - If user had an ORIGINAL sensor on the MP and replaced it → KEEP (sensor really was removed)
   - If user typed wrong serial and corrected → REMOVE (it was a mistake)

2. **How do we distinguish "replacement" from "correction"?**
   - Compare against `originalMPs` - if the sensor was there when modal opened, it's a real removal
   - If the sensor was typed by the user during this session, it might be a correction

3. **Should `removedSensors` track the original state?**
   - Currently it doesn't track whether the sensor was "original" or "typed this session"
   - Adding this distinction could help determine user intent

4. **What about the `updateSensorsAndMpRef` - is it also affected?**
   - It's only populated when user clicks "Confirm" in RemoveSensor UI
   - If user doesn't interact with that UI, it stays empty
   - But it still inherits bad data from `removedSensors`

---

## Summary

| Aspect | Current State | Problem |
|--------|--------------|---------|
| `removedSensors` population | Adds sensor when cell value changes FROM something | Accumulates corrections as if they were intentional |
| `removedSensors` cleanup | Only via explicit user action (X button) or modal close | No automatic cleanup when user corrects mistake |
| User intent tracking | Assumes all typed serials were intentional | Doesn't distinguish typo/correction from intentional change |
| Original sensor tracking | `originalMPs` exists but not used for cleanup | Could be used to determine "real" removals vs corrections |

---

## Related Files

| File | Purpose | Key Lines |
|------|---------|-----------|
| `UpdateMonitoringPointModal.tsx` | Main modal component | 154 (state), 954-994 (add to removed), 489-548 (remove from removed) |
| `useMonitoringPointSubmit.ts` | Submit logic | 159 (ref), 527-536 (process on submit) |
| `RemoveSensor.tsx` | UI for confirming removals | Displays `removedSensors`, calls `onRemoveSelected` |

## References

- Bug reproduction: `thoughts/shared/research/2026-01-23-IWA-11730-duplicate-sensor-facility-records.md`
- Original investigation: Section "Bug Reproduction (2026-01-26)"
