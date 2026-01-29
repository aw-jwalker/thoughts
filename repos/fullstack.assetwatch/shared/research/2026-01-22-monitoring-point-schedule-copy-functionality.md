---
date: 2026-01-22T13:08:57-05:00
researcher: Claude
git_commit: 204f8a2aa609b15b6cda46032852b59a4a1809ae
branch: dev
repository: fullstack.assetwatch
topic: "Monitoring Point Schedule Copy Functionality - How Schedule Inheritance Works"
tags: [research, codebase, ReceiverSchedule, MonitoringPoint_GetLastReceiverSchedule, schedule-inheritance, sensor-replacement]
status: complete
last_updated: 2026-01-22
last_updated_by: Claude
---

# Research: Monitoring Point Schedule Copy Functionality

**Date**: 2026-01-22T13:08:57-05:00
**Researcher**: Claude
**Git Commit**: 204f8a2aa609b15b6cda46032852b59a4a1809ae
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question

Understanding how the schedule copying functionality works when a monitoring point's schedule changes, specifically the `MonitoringPoint_GetLastReceiverSchedule` stored procedure and related schedule inheritance mechanisms in the web repository.

## Summary

**The schedule inheritance system** exists to preserve schedule settings when sensors are replaced on a monitoring point. Since schedules are stored per-Receiver (sensor) rather than per-MonitoringPoint, when a sensor is replaced, the system must explicitly copy the previous sensor's schedule to the new sensor.

**Key architectural insight**: Schedules are tied to **Receivers** (sensors), not MonitoringPoints. The `MonitoringPoint_GetLastReceiverSchedule` procedure is a workaround that looks up what schedule the *previous* sensor on a monitoring point had, so it can be copied to the *new* sensor.

**Two parallel pathways trigger schedule copying:**
1. **Frontend pathway**: When a user assigns a different sensor to a monitoring point via the UpdateMonitoringPointModal
2. **Provision pathway**: When a sensor physically provisions (connects to a hub) and the backend automatically assigns a schedule

---

## Detailed Findings

### 1. Database Schema

#### ReceiverSchedule Table
The schedule is stored per-Receiver:
```sql
CREATE TABLE `ReceiverSchedule` (
  `ReceiverScheduleID` int NOT NULL AUTO_INCREMENT,
  `ReceiverID` int NOT NULL,              -- Links to sensor, NOT MonitoringPoint
  `UserID` int NOT NULL,                  -- Who created the schedule
  `RQID` int NOT NULL,                    -- Request ID that created it
  `DateCreated` datetime DEFAULT NULL,
  `ReceiverScheduleStatusID` int DEFAULT NULL,  -- 1=active, 2=superseded
  `Frequency` int DEFAULT NULL,           -- Sample rate in Hz (e.g., 6400)
  `Samples` int DEFAULT NULL,             -- Samples per reading (e.g., 8192)
  `GRange` varchar(10) NOT NULL DEFAULT '32',
  PRIMARY KEY (`ReceiverScheduleID`)
);
```

#### ReceiverScheduleTime Table
Individual reading times per schedule:
```sql
CREATE TABLE `ReceiverScheduleTime` (
  `ReceiverScheduleTimeID` int NOT NULL AUTO_INCREMENT,
  `ReadingDayOfWeek` smallint NOT NULL,  -- 0=Monday through 6=Sunday
  `ReadingTime` time NOT NULL,           -- Time of day for reading
  `ReceiverScheduleID` int DEFAULT NULL,
  PRIMARY KEY (`ReceiverScheduleTimeID`)
);
```

### 2. The MonitoringPoint_GetLastReceiverSchedule_v2 Stored Procedure

**Location**: `mysql/db/procs/R__PROC_MonitoringPoint_GetLastReceiverSchedule_v2.sql`

**Purpose**: Given a MonitoringPointID, find the *previous* sensor that was assigned to this monitoring point (now inactive), and return that sensor's *most recent* schedule.

**Algorithm**:
1. Find the last inactive receiver on this monitoring point:
   ```sql
   SET localLastReceiverID = (
     SELECT ReceiverID
     FROM MonitoringPoint_Receiver
     WHERE MonitoringPointID=inMonitoringPointID AND ActiveFlag=0
     ORDER BY EndDate DESC LIMIT 1
   );
   ```

2. If found, get that receiver's most recent schedule (by MAX ReceiverScheduleID):
   ```sql
   WHERE rs.ReceiverID = localLastReceiverID
   AND rs.ReceiverScheduleID = (
     SELECT MAX(ReceiverScheduleID)
     FROM ReceiverSchedule
     WHERE ReceiverID = localLastReceiverID
   )
   ```

3. Return as JSON with day-named keys:
   ```json
   {
     "MondayTimeList": ["08:00", "12:00", "16:00"],
     "TuesdayTimeList": ["08:00", "12:00", "16:00"],
     ...
     "freq": 6400,
     "smpl": 8192
   }
   ```

**Critical observation**: The procedure looks for `ActiveFlag=0` receivers - meaning it finds sensors that are *no longer* actively assigned to the monitoring point. This is how it finds the "previous" sensor.

### 3. Frontend Schedule Inheritance (User-Initiated)

**Location**: `frontend/src/components/UpdateMonitoringPointModal/hooks/useMonitoringPointSubmit.ts`

#### Detection Logic (lines 369-372)
When updating a monitoring point, the system detects if a *different* sensor is being assigned:
```typescript
const originalMP = originalMPs.find((orig) => orig.mpid === mp.mpid);
const isSensorAssigned = mp.ssn && originalMP && originalMP.ssn !== mp.ssn;
```

#### Schedule Copy Function (lines 241-257)
When a sensor assignment changes, `sendScheduleToAssignedSensor()` is called:
```typescript
const sendScheduleToAssignedSensor = async (monitoringPoint: AssetMp) => {
  // 1. Get the previous sensor's schedule via the stored procedure
  const lastSchedule = await getLastReceiverSchedule(monitoringPoint.mpid);
  if (!lastSchedule) return;

  // 2. Fill in any missing days with defaults (prevents schedule request failure)
  const scheduleToPush = {
    ...DAY_DEFAULTS_V2,
    ...lastSchedule,
  };

  // 3. Send the schedule to the NEW sensor
  return scheduleRequestV2(
    monitoringPoint.ssn,      // New sensor serial number
    monitoringPoint.smpn,     // New sensor part number
    cognitoUserID,
    scheduleToPush,
  );
};
```

#### Trigger Points
The function is called in two scenarios:

1. **Adding a new MP with a sensor assigned** (lines 327-329):
   ```typescript
   if (mp.ssn && newMP[0]?.outmpid) {
     mp.mpid = newMP[0].outmpid;
     await sendScheduleToAssignedSensor(mp);
   }
   ```

2. **Updating an existing MP with a different sensor** (lines 414-419):
   ```typescript
   // When installing or replacing a sensor we must copy the schedule from the monitoring point
   // and send it to the sensor. This is critical in order to preserve very important
   // schedule settings! Failure to do so can result in incorrect readings and alerts failing to trigger.
   if (isSensorAssigned) {
     await sendScheduleToAssignedSensor(mp);
   }
   ```

### 4. API Layer

#### Frontend Service (MonitoringPointService.ts:78-89)
```typescript
export async function getLastReceiverSchedule(mpid: number): Promise<any> {
  return apiVeroMonitoringPoint({
    meth: "getLastReceiverSchedule",
    mpid: mpid,
  });
}
```

#### Lambda Handler (lf-vero-prod-monitoringpoint/main.py:1188-1196)
```python
elif method == "getLastReceiverSchedule":
    mpid = body.get("mpid")
    cursor.execute("CALL MonitoringPoint_GetLastReceiverSchedule_v2(%s)", (mpid,))
    result = cursor.fetchone()
    if result and result[0]:
        return json.loads(result[0])
    return None
```

### 5. Schedule Request Flow

When `scheduleRequestV2()` is called, it creates a new schedule for the sensor:

**Location**: `frontend/src/shared/api/RequestServiceV2.ts:200-222`
```typescript
export async function scheduleRequestV2(
  levelIDList: string | undefined,
  smpn: string | number,
  username: string,
  rqmeta: any,
) {
  await sendRequest({
    inputs: {
      RequestType: "Schedule",
      Sensor: `${smpn}_${levelIDList}`,
      SampleRate: rqmeta["freq"],
      Samples: rqmeta["smpl"],
      MondayTimeList: rqmeta["MondayTimeList"],
      TuesdayTimeList: rqmeta["TuesdayTimeList"],
      // ... other days
    },
    cognitoUserID: username,
  });
}
```

This creates a Request that is processed by:
- `lf-vero-prod-request` Lambda → `request-schedule` job
- Stored procedure: `Receiver_AddReceiverSchedule`

### 6. Provision Pathway (Backend Automatic)

**Location**: `mysql/db/procs/R__PROC_Receiver_GetProvisionReceiverSchedule.sql`

When a sensor provisions (physically connects to a hub), the provision stored procedure also does schedule inheritance:

```sql
-- Find the previous sensor on the same monitoring point
SET localLastReceiverID = (
  SELECT ReceiverID FROM MonitoringPoint_Receiver
  WHERE MonitoringPointID = localCurrentMonitoringPointID
  AND ActiveFlag = 0
  ORDER BY EndDate DESC LIMIT 1
);

-- If found, copy that sensor's schedule
IF (localLastReceiverID IS NOT NULL) THEN
  SET outSchedule = (
    SELECT JSON_SET(...)
    FROM ReceiverSchedule rs
    WHERE rs.ReceiverID = localLastReceiverID
      AND rs.ReceiverScheduleStatusID = 2  -- Uses historical schedule
    ORDER BY rs.ReceiverScheduleID DESC LIMIT 1
  );
END IF;
```

**Key difference**: The provision pathway uses `ReceiverScheduleStatusID = 2` (superseded) while the v2 procedure uses `MAX(ReceiverScheduleID)`.

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SCHEDULE INHERITANCE DATA FLOW                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  USER ACTION: Replace sensor on Monitoring Point                             │
│  ───────────────────────────────────────────────                            │
│                                                                              │
│  1. UpdateMonitoringPointModal detects sensor change                        │
│     └─ isSensorAssigned = mp.ssn !== originalMP.ssn                         │
│                                                                              │
│  2. sendScheduleToAssignedSensor(monitoringPoint) called                    │
│     │                                                                        │
│     ├─► getLastReceiverSchedule(mpid)                                       │
│     │   └─► Lambda: lf-vero-prod-monitoringpoint                            │
│     │       └─► Stored Proc: MonitoringPoint_GetLastReceiverSchedule_v2     │
│     │           │                                                            │
│     │           ├─ Find last inactive receiver on MP (ActiveFlag=0)         │
│     │           └─ Return that receiver's most recent schedule              │
│     │                                                                        │
│     └─► scheduleRequestV2(newSensorSSN, scheduleToPush)                     │
│         └─► Lambda: lf-vero-prod-request                                    │
│             └─► Job: request-schedule                                       │
│                 └─► Stored Proc: Receiver_AddReceiverSchedule               │
│                     └─► INSERT INTO ReceiverSchedule (for new sensor)       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Code References

### Stored Procedures
- `mysql/db/procs/R__PROC_MonitoringPoint_GetLastReceiverSchedule_v2.sql` - Main schedule lookup
- `mysql/db/procs/R__PROC_MonitoringPoint_GetLastReceiverSchedule.sql` - Legacy version (short day names)
- `mysql/db/procs/R__PROC_Receiver_GetProvisionReceiverSchedule.sql` - Provision pathway
- `mysql/db/procs/R__PROC_Receiver_AddReceiverSchedule.sql` - Create new schedule

### Frontend
- `frontend/src/components/UpdateMonitoringPointModal/hooks/useMonitoringPointSubmit.ts:241-257` - sendScheduleToAssignedSensor
- `frontend/src/components/UpdateMonitoringPointModal/hooks/useMonitoringPointSubmit.ts:369-372` - isSensorAssigned detection
- `frontend/src/components/UpdateMonitoringPointModal/hooks/useMonitoringPointSubmit.ts:414-419` - Trigger on sensor replacement
- `frontend/src/shared/api/MonitoringPointService.ts:78-89` - getLastReceiverSchedule API
- `frontend/src/shared/api/RequestServiceV2.ts:200-222` - scheduleRequestV2

### Lambdas
- `lambdas/lf-vero-prod-monitoringpoint/main.py:1188-1196` - getLastReceiverSchedule handler

---

## Historical Context (from thoughts/)

### Related Research Documents
- `thoughts/shared/research/2026-01-12-sensor-schedule-system-comprehensive.md` - Comprehensive architecture guide including all 6 entry points that create schedules
- `thoughts/shared/research/2025-12-16-receiver-schedule-to-monitoring-point-schedule-impact.md` - Impact analysis of potential migration to MonitoringPointSchedule

### Key Historical Insights
1. **Schedule inheritance exists as a workaround** - The procedures exist precisely because schedules are tied to Receivers instead of MonitoringPoints
2. **Two parallel pathways** can trigger schedule copying (frontend and provision), which can potentially race
3. **v1 vs v2 procedure difference** - v1 uses `ReceiverScheduleStatusID = 2` filter, v2 uses `MAX(ReceiverScheduleID)`

---

## Troubleshooting Resources

### SQL Query for Schedule History
**Location**: `~/repos/notes/schedule-bugs/sensor_schedule_history_query.sql`

This query traces complete schedule change history for a receiver or monitoring point, showing:
- When each schedule was created
- Who created it (UserID)
- Which Request created it (RQID)
- Frequency and sample settings
- Scheduled reading times by day

### SQL Query for CME Custom Schedules Overwritten
**Location**: `~/repos/notes/schedule-bugs/cme_custom_schedule_overwritten.sql`

This query finds active MonitoringPoints where:
- A CME set a custom schedule (non-default frequency/samples)
- A non-CME user (often the system bot) later overwrote it with default
- The overwrite happened after October 10th, 2025

### CloudWatch Queries
**Log Group**: `/aws/lambda/lf-vero-prod-monitoringpoint`

Detect getLastReceiverSchedule calls:
```
fields @timestamp, @message
| filter @message like /"meth": "getLastReceiverSchedule"/
| sort @timestamp desc
| limit 20
```

---

## Key Points for Bug Investigation

When investigating bugs related to schedule copying:

1. **Check which pathway triggered the schedule**: Frontend (user-initiated via modal) vs Provision (sensor connecting to hub)

2. **Race condition potential**: If a user assigns a sensor AND the sensor provisions around the same time, both pathways may create schedules

3. **The schedule lookup finds the PREVIOUS sensor**: It looks for `ActiveFlag=0` to find the sensor that *was* on the monitoring point, not the current one

4. **Default schedule fallback**: If no previous schedule exists, the provision pathway applies a default (6400Hz, 8192 samples, every 3 hours)

5. **Status filter difference**: v2 procedure uses `MAX(ReceiverScheduleID)`, provision uses `ReceiverScheduleStatusID = 2`

---

## Open Questions

1. **What happens if the mobile backend also triggers schedule inheritance?** - The HubService has schedule sync methods that may interact with this system.

2. **Is there coordination between frontend and provision pathways?** - Could they both fire for the same sensor replacement?

3. **What is the bug in the mobile backend repo?** - User mentioned a related bug; the specific details would help understand if the issue is in the lookup logic, the copy logic, or a race condition.
