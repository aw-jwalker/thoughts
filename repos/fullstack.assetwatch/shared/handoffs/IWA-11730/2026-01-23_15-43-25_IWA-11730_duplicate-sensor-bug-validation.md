---
date: 2026-01-23T15:43:25-05:00
researcher: jwalker
git_commit: 1b7b250ae0999f06eaf6f8c3e4e038b07b1a7d86
branch: IWA-11730
repository: AssetWatch1/fullstack.assetwatch
topic: "Duplicate Sensor Bug - Stored Procedure Validation"
tags: [investigation, duplicate-sensors, stored-procedures, FacilityReceiver_UpdateReceiverStatus]
status: in_progress
last_updated: 2026-01-23
last_updated_by: jwalker
type: implementation_strategy
---

# Handoff: IWA-11730 Duplicate Sensor Bug - Validating Root Cause

## Task(s)

| Task | Status |
|------|--------|
| Validate `FacilityReceiver_UpdateReceiverStatus` as bug location | **In Progress** |
| CloudWatch log investigation | Blocked (timestamp mystery) |
| Full code path tracing | In Progress |

Working from research document: `thoughts/shared/research/2026-01-23-IWA-11730-duplicate-sensor-facility-records.md`

## Critical References

1. `thoughts/shared/research/2026-01-23-IWA-11730-duplicate-sensor-facility-records.md` - Main research document
2. `mysql/db/procs/R__PROC_FacilityReceiver_UpdateReceiverStatus.sql` - The suspected buggy procedure
3. `mysql/db/procs/R__PROC_MonitoringPoint_RemoveMonitoringPoint.sql` - Correctly handles MPR deactivation (contrast)

## Recent changes

No code changes made - this session was investigation/validation only.

## Learnings

### Key Validation Finding: Bug Hypothesis Is Correct

**Compared two stored procedures that handle sensor removal:**

1. **`MonitoringPoint_RemoveMonitoringPoint`** (lines 34-43) - **CORRECT**:
   ```sql
   SET mpr.ActiveFlag = 0, mpr.EndDate = UTC_TIMESTAMP(),
       mpr.RemovedByUserID = localUserID, mpr._deleted = 1
   ```

2. **`FacilityReceiver_UpdateReceiverStatus`** (lines 33-35) - **BUG**:
   ```sql
   SET ReceiverRemovalTypeID=localReceiverRemovalTypeID, _version=_version+1
   -- MISSING: ActiveFlag=0, EndDate, RemovedByUserID, _deleted=1
   ```

### Frontend Flow Traced

```
handleFormSubmit() (useMonitoringPointSubmit.ts:538)
  ├─> addNewMP()              → addMonitoringPoint API
  ├─> updateMP()              → addMonitoringPoint API
  ├─> removeMP()              → MonitoringPoint_RemoveMonitoringPoint ✅ (correct)
  └─> updateSensorFacilityStatus() → FacilityReceiver_UpdateReceiverStatus ❌ (BUG)
```

**When `updateSensorFacilityStatus()` is called:**
- User removes a sensor from an MP via `onRemoveSelected()` (UpdateMonitoringPointModal.tsx:372)
- Sensor is added to `updateSensorsAndMpRef.current`
- On submit, sensors in that ref but NOT in final gridData are "reassigned" to inventory
- This calls `FacilityReceiver_UpdateReceiverStatus` which inserts into `Facility_Receiver` WITHOUT deactivating MPR

### CloudWatch Investigation Learnings (documented in research doc)

- **Cognito ID for UserID 8786**: `d16b9d27-096d-4586-af06-f7c6774b393c`
- **CloudWatch limit**: 200 results per query - use narrow time windows
- **Timestamp mystery**: No logs found at 22:30 UTC despite database showing activity then
- **Hypothesis**: Database timestamps may be stored in local time (EST), not UTC

## Artifacts

1. `thoughts/shared/research/2026-01-23-IWA-11730-duplicate-sensor-facility-records.md` - Updated with:
   - Lesson 5: CloudWatch search best practices using cognito_id
   - Lesson 6: CloudWatch 200 result limit workarounds
   - Detailed investigation results and timestamp mystery
   - Next session checklist

## Action Items & Next Steps

### Immediate (Bug Fix)

1. **Fix `FacilityReceiver_UpdateReceiverStatus`** (lines 33-35) to add:
   ```sql
   SET ActiveFlag = 0,
       EndDate = UTC_TIMESTAMP(),
       RemovedByUserID = localUserID,
       _deleted = 1,
       ReceiverRemovalTypeID = localReceiverRemovalTypeID,
       _version = _version + 1
   ```

2. **But first**: Verify this is the actual code path by continuing the `updateMP()` trace - need to confirm `addMonitoringPoint` API handles sensor replacement correctly

### Investigation (if needed)

3. Test timezone hypothesis: Search CloudWatch for Jan 6, 03:00-04:00 UTC
4. Search other Lambdas (inventory, sensor) for the cognito_id

## Other Notes

### File Locations for Code Path

| Component | File | Key Lines |
|-----------|------|-----------|
| Modal submit | `frontend/src/components/UpdateMonitoringPointModal/hooks/useMonitoringPointSubmit.ts` | 538-640 |
| Remove sensor UI | `frontend/src/components/UpdateMonitoringPointModal/UpdateMonitoringPointModal.tsx` | 372-412 |
| API call | `frontend/src/shared/api/FacilityServices.ts` | 1052-1073 |
| Lambda handler | `lambdas/lf-vero-prod-facilities/main.py` | 1301-1319 |
| Buggy procedure | `mysql/db/procs/R__PROC_FacilityReceiver_UpdateReceiverStatus.sql` | 32-53 |
| Correct procedure | `mysql/db/procs/R__PROC_MonitoringPoint_RemoveMonitoringPoint.sql` | 34-43 |

### The Two Code Paths for Sensor Removal

1. **Remove entire MP** → `removeMP()` → `MonitoringPoint_RemoveMonitoringPoint` → ✅ Correctly deactivates MPR
2. **Remove sensor from MP (keep MP)** → `updateSensorFacilityStatus()` → `FacilityReceiver_UpdateReceiverStatus` → ❌ Does NOT deactivate MPR

The bug occurs in path #2 - when a sensor is removed from an MP but the MP itself is NOT deleted.
