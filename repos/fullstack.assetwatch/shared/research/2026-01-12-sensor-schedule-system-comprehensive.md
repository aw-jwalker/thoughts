---
date: 2026-01-12T09:05:06-05:00
researcher: Claude
git_commit: 1b7a1d72090fbb48d71ae622e2a24b12d45dac9d
branch: dev
repository: fullstack.assetwatch
topic: "Sensor Schedule System - Comprehensive Architecture and Troubleshooting Guide"
tags: [research, codebase, ReceiverSchedule, schedule-inheritance, troubleshooting, sensor-schedules]
status: complete
last_updated: 2026-01-12
last_updated_by: Claude
---

# Research: Sensor Schedule System - Comprehensive Architecture and Troubleshooting Guide

**Date**: 2026-01-12T09:05:06-05:00
**Researcher**: Claude
**Git Commit**: 1b7a1d72090fbb48d71ae622e2a24b12d45dac9d
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question

Comprehensive documentation of the sensor schedule system including:
1. All entry points that can create or modify schedules
2. Schedule inheritance mechanism
3. Available troubleshooting tools and queries
4. Database schema and stored procedures

**Context**: Investigating a recurring bug where after an intentional schedule request, a second unintentional request is made with wrong parameters (different frequency, sampling rate).

## Summary

The sensor schedule system allows users to configure when sensors take vibration readings. Schedules are stored **per-Receiver** (sensor) in the `ReceiverSchedule` table, with reading times stored in `ReceiverScheduleTime`. When sensors are replaced on a monitoring point, a **schedule inheritance mechanism** automatically copies the previous sensor's schedule to the new sensor.

**Key architectural components:**
- **6 entry points** that can create/modify schedules
- **2 schedule inheritance pathways** (frontend and provision)
- **3 stored procedures** for schedule retrieval
- **Multiple troubleshooting tools** including CloudWatch queries and database audit queries

---

## Detailed Findings

### 1. Database Schema

#### ReceiverSchedule Table
```sql
CREATE TABLE `ReceiverSchedule` (
  `ReceiverScheduleID` int NOT NULL AUTO_INCREMENT,
  `ReceiverID` int NOT NULL,           -- Links to sensor
  `UserID` int NOT NULL,               -- Who created the schedule
  `RQID` int NOT NULL,                 -- Request ID that created it
  `DateCreated` datetime DEFAULT NULL,
  `ReceiverScheduleStatusID` int DEFAULT NULL,  -- 1=active, 2=superseded
  `Frequency` int DEFAULT NULL,        -- Sample rate in Hz (e.g., 6400)
  `Samples` int DEFAULT NULL,          -- Samples per reading (e.g., 8192)
  `GRange` varchar(10) NOT NULL DEFAULT '32',
  PRIMARY KEY (`ReceiverScheduleID`)
);
```

#### ReceiverScheduleTime Table
```sql
CREATE TABLE `ReceiverScheduleTime` (
  `ReceiverScheduleTimeID` int NOT NULL AUTO_INCREMENT,
  `ReadingDayOfWeek` smallint NOT NULL,  -- 0=Monday through 6=Sunday
  `ReadingTime` time NOT NULL,           -- Time of day for reading
  `ReceiverScheduleID` int DEFAULT NULL,
  PRIMARY KEY (`ReceiverScheduleTimeID`)
);
```

#### ReceiverScheduleStatus Reference
| ID | Status | Description |
|----|--------|-------------|
| 1 | Active | Currently in use |
| 2 | Superseded | Historical, replaced by newer schedule |

---

### 2. Entry Points That Create/Modify Schedules

#### Entry Point 1: Frontend Schedule Request (Primary User Flow)
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
      // ... other days
    },
    cognitoUserID: username,
  });
}
```

**Trigger**: User clicks "Send Schedule" in UI
**Lambda**: `lf-vero-prod-request` → `request-schedule` job
**Stored Procedure**: `Receiver_AddReceiverSchedule`

#### Entry Point 2: Schedule Inheritance on Sensor Replacement (Frontend)
**Location**: `frontend/src/components/UpdateMonitoringPointModal/hooks/useMonitoringPointSubmit.ts:242-258`

```typescript
const sendScheduleToAssignedSensor = async (monitoringPoint: AssetMp) => {
  const lastSchedule = await getLastReceiverSchedule(monitoringPoint.mpid);
  if (!lastSchedule) return;

  const scheduleToPush = {
    ...DAY_DEFAULTS_V2,
    ...lastSchedule,
  };

  return scheduleRequestV2(
    monitoringPoint.ssn,
    getPartNumberFromSerialNumber(String(monitoringPoint.ssn)),
    cognitoUserID,
    scheduleToPush,
  );
};
```

**Trigger**: When user assigns a different sensor to an existing monitoring point
**Detection Logic** (line 370-373):
```typescript
const originalMP = originalMPs.find((orig) => orig.mpid === mp.mpid);
const isSensorAssigned = mp.ssn && originalMP && originalMP.ssn !== mp.ssn;
```

#### Entry Point 3: Schedule Inheritance on New MP with Sensor
**Location**: `frontend/src/components/UpdateMonitoringPointModal/hooks/useMonitoringPointSubmit.ts:260-346`

When adding a new monitoring point with a sensor assigned, the system also triggers schedule inheritance if the MP had a previous sensor (though for truly new MPs, `getLastReceiverSchedule` returns null).

#### Entry Point 4: Provision Flow (Backend Automatic)
**Location**: `mysql/db/procs/R__PROC_Receiver_GetProvisionReceiverSchedule.sql`

When a sensor provisions (connects to hub), the stored procedure checks for schedule inheritance:

```sql
SET localLastReceiverID = (SELECT ReceiverID FROM MonitoringPoint_Receiver
  WHERE MonitoringPointID=localCurrentMonitoringPointID
  AND ActiveFlag=0
  ORDER BY EndDate DESC LIMIT 1);

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

#### Entry Point 5: Hub Schedule Sync (Mobile Backend)
**Location**: `assetwatch-mobile-backend/lambda/lf-assetwatch-collect-cf/src/service/HubService.ts`

Methods: `manageHubSchedule()`, `syncHubSchedule()`, `clearHubSchedules()`, `createHubSchedules()`, `sendHubSchedules()`

#### Entry Point 6: Lambda Direct Schedule Operations
**Location**: `lambdas/lf-vero-prod-sensor/main.py`

Method `getSensorSchedule` can retrieve schedules; related operations may modify schedules.

---

### 3. Schedule Inheritance Mechanism

#### Two Parallel Pathways

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SCHEDULE INHERITANCE PATHWAYS                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  PATHWAY 1: Frontend (User-Initiated)                                │
│  ───────────────────────────────────                                  │
│  1. User replaces sensor in UpdateMonitoringPointModal                │
│  2. Hook detects: mp.ssn !== originalMP.ssn                          │
│  3. Calls sendScheduleToAssignedSensor()                             │
│  4. API: getLastReceiverSchedule(mpid)                               │
│  5. Proc: MonitoringPoint_GetLastReceiverSchedule_v2                 │
│  6. Returns MAX(ReceiverScheduleID) from last inactive receiver       │
│  7. Sends schedule to new sensor via scheduleRequestV2()             │
│                                                                       │
│  PATHWAY 2: Provision (Device-Initiated)                             │
│  ─────────────────────────────────────                               │
│  1. Sensor connects to hub (provision message)                        │
│  2. Proc: Receiver_GetProvisionReceiverSchedule                       │
│  3. Finds last receiver on same MP (ActiveFlag=0)                    │
│  4. Gets schedule with ReceiverScheduleStatusID=2                    │
│  5. OR applies default schedule (every 3 hrs, 8192@6400Hz)           │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

#### Key Stored Procedures for Inheritance

| Procedure | Used By | Status Filter | Day Format |
|-----------|---------|---------------|------------|
| `MonitoringPoint_GetLastReceiverSchedule` | Legacy | `StatusID = 2` | Short (mo, tu...) |
| `MonitoringPoint_GetLastReceiverSchedule_v2` | Frontend | `MAX(ID)` | Long (MondayTimeList...) |
| `Receiver_GetProvisionReceiverSchedule` | Provision | `StatusID = 2` | Short (mo, tu...) |

**Critical Difference**: v2 uses `MAX(ReceiverScheduleID)` without status filter, while v1 and provision use `ReceiverScheduleStatusID = 2`.

---

### 4. Troubleshooting Tools

#### 4.1 Database Query: Schedule Change History

**Source**: `~/repos/notes/schedule-bugs/sensor_schedule_history_query.sql`

This query traces the complete history of schedule changes for a receiver or monitoring point, showing:
- When each schedule was created
- Who created it (UserID)
- Which Request created it (RQID)
- The frequency and sample settings
- The scheduled reading times

**Usage Pattern**:
```sql
-- Find all schedules for a specific receiver
SELECT rs.*, rst.ReadingDayOfWeek, rst.ReadingTime
FROM ReceiverSchedule rs
LEFT JOIN ReceiverScheduleTime rst ON rs.ReceiverScheduleID = rst.ReceiverScheduleID
WHERE rs.ReceiverID = <ReceiverID>
ORDER BY rs.DateCreated DESC;

-- Trace via RQID to find what triggered the schedule
SELECT r.* FROM Request r WHERE r.RQID = <RQID_from_schedule>;
```

#### 4.2 CloudWatch Queries

**Source**: `~/repos/notes/cloudwatch-monitoring-point-schedule-testing.md`

**Log Group**: `/aws/lambda/lf-vero-prod-monitoringpoint`

**Query 1: Detect getLastReceiverSchedule calls**
```
fields @timestamp, @message
| filter @message like /"meth": "getLastReceiverSchedule"/
| sort @timestamp desc
| limit 20
```

**Query 2: Track Stored Procedure Execution**
```
fields @timestamp, @message
| filter @message like /CALL MonitoringPoint_GetLastReceiverSchedule_v2/
| sort @timestamp desc
| limit 20
```

**Query 3: Parse Return Values**
```
fields @timestamp, @message
| filter @message like /getLastReceiverSchedule/ and @message like /receiverSchedule/
| parse @message /.*"receiverSchedule":\s*(?<schedule_data>\{.*\})/
| sort @timestamp desc
| limit 10
```

**Query 4: Track Schedule Requests (request-schedule lambda)**
```
fields @timestamp, @message
| filter @message like /Receiver_AddReceiverSchedule/ or @message like /schedule/
| sort @timestamp desc
| limit 10
```

#### 4.3 Direct Database Testing

```sql
-- Test stored procedure directly
CALL MonitoringPoint_GetLastReceiverSchedule_v2(<MonitoringPointID>);

-- Check schedule inheritance source
SELECT
  mpr.ReceiverID,
  mpr.MonitoringPointID,
  mpr.ActiveFlag,
  mpr.EndDate,
  r.SerialNumber
FROM MonitoringPoint_Receiver mpr
JOIN Receiver r ON mpr.ReceiverID = r.ReceiverID
WHERE mpr.MonitoringPointID = <MonitoringPointID>
ORDER BY mpr.EndDate DESC;
```

---

### 5. Request Processing Flow

When a schedule request is made:

```
User/System
    │
    ▼
scheduleRequestV2() ─────► lf-vero-prod-request Lambda
    │                              │
    │                              ▼
    │                      request-schedule job
    │                              │
    │                              ▼
    │                      Receiver_AddReceiverSchedule_Iterator
    │                              │
    │                              ▼
    │                      Receiver_AddReceiverSchedule
    │                              │
    │                              ▼
    └──────────────────► ReceiverSchedule table (new row)
                                   │
                                   ▼
                         ReceiverScheduleTime table (time entries)
```

**Key stored procedures in order**:
1. `Receiver_AddReceiverSchedule_Iterator` - Entry point, handles batch processing
2. `Receiver_AddReceiverSchedule` - Creates individual schedule record

---

### 6. Potential Sources of Unintentional Schedule Requests

Based on the architecture analysis, the following are potential sources of a "phantom" second schedule request:

#### Hypothesis 1: Race Condition Between Frontend and Provision
If a user sends a schedule AND the sensor provisions around the same time:
- Frontend sends intentional schedule via `scheduleRequestV2()`
- Sensor provisions and `Receiver_GetProvisionReceiverSchedule` also sends a schedule
- Result: Two schedules created in quick succession

#### Hypothesis 2: Schedule Inheritance Triggered Unexpectedly
If `isSensorAssigned` detection fires when it shouldn't:
- Check `useMonitoringPointSubmit.ts:370-373` logic
- Could trigger `sendScheduleToAssignedSensor()` unintentionally

#### Hypothesis 3: Default Schedule from Provision
`Receiver_GetProvisionReceiverSchedule` applies a default schedule (6400Hz, 8192 samples, every 3 hours) when:
- No previous receiver found on MP
- Previous receiver had no schedule
- Sensor not assigned to any MP

This default has **different parameters** than typical user schedules.

#### Hypothesis 4: Mobile Backend Sync
`HubService.syncHubSchedule()` or related methods could trigger schedule changes during hub synchronization.

---

### 7. Key Code References

#### Frontend
- `frontend/src/shared/api/RequestServiceV2.ts:200-222` - scheduleRequestV2
- `frontend/src/shared/api/MonitoringPointService.ts:78-89` - getLastReceiverSchedule
- `frontend/src/components/UpdateMonitoringPointModal/hooks/useMonitoringPointSubmit.ts:242-258` - sendScheduleToAssignedSensor
- `frontend/src/components/UpdateMonitoringPointModal/hooks/useMonitoringPointSubmit.ts:370-373` - isSensorAssigned detection
- `frontend/src/hooks/services/useGetSensorSchedule.ts` - Schedule query hook

#### Lambdas
- `lambdas/lf-vero-prod-monitoringpoint/main.py:1188-1196` - getLastReceiverSchedule handler
- `lambdas/lf-vero-prod-sensor/main.py:765-773` - getSensorSchedule handler
- `lambdas/lf-vero-prod-request/` - Request processing entry

#### Stored Procedures
- `mysql/db/procs/R__PROC_Receiver_AddReceiverSchedule.sql` - Create schedule
- `mysql/db/procs/R__PROC_Receiver_AddReceiverSchedule_Iterator.sql` - Batch schedule creation
- `mysql/db/procs/R__PROC_Receiver_GetReceiverSchedule.sql` - Get current schedule
- `mysql/db/procs/R__PROC_MonitoringPoint_GetLastReceiverSchedule.sql` - Legacy inheritance
- `mysql/db/procs/R__PROC_MonitoringPoint_GetLastReceiverSchedule_v2.sql` - Current inheritance
- `mysql/db/procs/R__PROC_Receiver_GetProvisionReceiverSchedule.sql` - Provision schedule
- `mysql/db/procs/R__PROC_Facility_GetReceiverSchedules.sql` - Facility-wide schedules
- `mysql/db/procs/R__PROC_Hub_GetSchedulesGraph.sql` - Hub schedule visualization

#### Jobs (assetwatch-jobs repository)
- `terraform/jobs/request_v2/request-schedule/main.py` - Schedule processing job
- `terraform/jobs/request_v2/request-schedule/request_sql.py` - Schedule SQL operations
- `terraform/jobs/jobs_daemon/jobs-daemon/main.py` - Background schedule tasks
- `terraform/jobs/jobs_schedule_optimizer/jobs-schedule-optimizer/main.py` - Schedule optimization

---

## Historical Context (from thoughts/)

### Related Research Documents
- `thoughts/shared/research/2025-12-16-receiver-schedule-to-monitoring-point-schedule-impact.md` - Comprehensive analysis of migrating from ReceiverSchedule to MonitoringPointSchedule architecture

### Key Historical Insights
1. **Schedule inheritance exists as a workaround** - The `MonitoringPoint_GetLastReceiverSchedule` procedures exist precisely because schedules are tied to Receivers instead of MonitoringPoints.

2. **ActiveFlag pattern** - The `ActiveFlag=1` pattern in `MonitoringPoint_Receiver` treats MonitoringPoints as the primary entity, but schedules don't follow this pattern.

3. **v1 vs v2 procedure bug** - A previous bug fix addressed incorrect status filtering in `MonitoringPoint_GetLastReceiverSchedule_v2`.

---

## Troubleshooting Workflow for Phantom Schedule Bug

### Step 1: Identify the Instance
```sql
-- Find recent schedules for the affected receiver
SELECT
  rs.ReceiverScheduleID,
  rs.ReceiverID,
  rs.UserID,
  rs.RQID,
  rs.DateCreated,
  rs.ReceiverScheduleStatusID,
  rs.Frequency,
  rs.Samples,
  u.Username
FROM ReceiverSchedule rs
JOIN User u ON rs.UserID = u.UserID
WHERE rs.ReceiverID = <ReceiverID>
ORDER BY rs.DateCreated DESC
LIMIT 10;
```

### Step 2: Compare the Two Requests
Look for two schedules created within seconds/minutes of each other with different parameters.

### Step 3: Trace via RQID
```sql
-- Find the request that created each schedule
SELECT
  r.RQID,
  r.RequestTypeID,
  r.DateCreated,
  r.CognitoID,
  r.ReceiverID
FROM Request r
WHERE r.RQID IN (<RQID1>, <RQID2>);
```

### Step 4: Check CloudWatch
Use the CloudWatch queries above to trace the API calls that triggered each request.

### Step 5: Check for Provision Activity
```sql
-- Check if sensor provisioned around the same time
SELECT * FROM ReceiverProvision
WHERE ReceiverID = <ReceiverID>
AND DateCreated BETWEEN '<time_before>' AND '<time_after>';
```

---

## Query to Detect Pattern Across Database

To find all instances where this bug pattern may have occurred:

```sql
-- Find receivers with multiple schedules created within 5 minutes with different parameters
SELECT
  rs1.ReceiverID,
  rs1.ReceiverScheduleID as Schedule1_ID,
  rs1.DateCreated as Schedule1_Time,
  rs1.Frequency as Schedule1_Freq,
  rs1.Samples as Schedule1_Samples,
  rs2.ReceiverScheduleID as Schedule2_ID,
  rs2.DateCreated as Schedule2_Time,
  rs2.Frequency as Schedule2_Freq,
  rs2.Samples as Schedule2_Samples,
  TIMESTAMPDIFF(SECOND, rs1.DateCreated, rs2.DateCreated) as SecondsBetween
FROM ReceiverSchedule rs1
JOIN ReceiverSchedule rs2 ON rs1.ReceiverID = rs2.ReceiverID
WHERE rs2.DateCreated > rs1.DateCreated
  AND TIMESTAMPDIFF(MINUTE, rs1.DateCreated, rs2.DateCreated) <= 5
  AND (rs1.Frequency != rs2.Frequency OR rs1.Samples != rs2.Samples)
ORDER BY rs1.DateCreated DESC
LIMIT 100;
```

---

## Open Questions

1. **What triggers provision flow?** - Need to trace when `Receiver_GetProvisionReceiverSchedule` is called to understand if it could race with frontend requests.

2. **Are there other callers of Receiver_AddReceiverSchedule?** - Need comprehensive search across all repositories.

3. **Is there a hub sync that could trigger schedule changes?** - Mobile backend `HubService` methods need deeper investigation.

4. **What is the exact timing of the phantom request?** - Analyzing actual instances will reveal if it's milliseconds or minutes apart.
