---
date: 2025-12-16T14:06:38-05:00
researcher: Claude
git_commit: 4ceed103ddcc404d0b33f54d34fae110a684bd70
branch: dev
repository: fullstack.assetwatch
topic: "Impact Analysis: ReceiverSchedule to MonitoringPointSchedule Migration"
tags: [research, codebase, ReceiverSchedule, MonitoringPointSchedule, database-migration, architecture]
status: complete
last_updated: 2025-12-16
last_updated_by: Claude
---

# Research: Impact Analysis - ReceiverSchedule to MonitoringPointSchedule Migration

**Date**: 2025-12-16T14:06:38-05:00
**Researcher**: Claude
**Git Commit**: 4ceed103ddcc404d0b33f54d34fae110a684bd70
**Branch**: dev
**Repository**: fullstack.assetwatch (with cross-repo analysis of assetwatch-jobs, assetwatch.mobile, assetwatch-mobile-backend)

## Research Question

What would be the impact of switching from ReceiverSchedule (current implementation where schedules are tied to sensors/receivers) to MonitoringPointSchedule (schedules tied to monitoring point locations)?

## Summary

**Current State**: Schedules are stored per-Receiver (sensor) in the `ReceiverSchedule` table. When sensors are replaced on a MonitoringPoint, a schedule inheritance mechanism copies the old sensor's schedule to the new one.

**Proposed Change**: Move schedules to be per-MonitoringPoint, so the schedule "lives" with the location rather than the hardware.

**Impact Assessment**: This is a **HIGH COMPLEXITY** migration affecting:
- **4 repositories** (fullstack.assetwatch, assetwatch-jobs, assetwatch-mobile-backend; assetwatch.mobile unaffected)
- **~35+ stored procedures**
- **~15+ Lambda functions/jobs**
- **Frontend service layer and hooks**
- **Mobile backend synchronization logic**

**Key Insight**: The current schedule inheritance pattern (`MonitoringPoint_GetLastReceiverSchedule`) exists precisely because schedules are tied to Receivers. Switching to MonitoringPointSchedule would **eliminate the need for schedule inheritance** but require significant refactoring.

---

## Detailed Findings

### Current Architecture Overview

```
┌─────────────────┐     ┌────────────────────────┐     ┌──────────────┐
│ MonitoringPoint │────▶│ MonitoringPoint_Receiver│◀────│   Receiver   │
└─────────────────┘     │     (ActiveFlag=1)     │     └──────┬───────┘
                        └────────────────────────┘            │
                                                              ▼
                                                   ┌──────────────────┐
                                                   │ ReceiverSchedule │
                                                   │ (StatusID=1)     │
                                                   └────────┬─────────┘
                                                            │
                                                            ▼
                                                   ┌────────────────────┐
                                                   │ReceiverScheduleTime│
                                                   └────────────────────┘
```

**Key Relationships**:
- One Receiver can only be **actively assigned** to one MonitoringPoint at a time (enforced via `ActiveFlag=1`)
- One Receiver can have multiple schedules (historical), but only **one active** schedule (`ReceiverScheduleStatusID=1`)
- Schedule inheritance occurs when a new sensor is installed on a MonitoringPoint that previously had a sensor

---

### Repository Impact Analysis

#### 1. fullstack.assetwatch (This Repository)

##### Database Schema

**Tables to Create**:
| New Table | Based On | Key Change |
|-----------|----------|------------|
| `MonitoringPointSchedule` | `ReceiverSchedule` | FK changes from `ReceiverID` to `MonitoringPointID` |
| `MonitoringPointScheduleTime` | `ReceiverScheduleTime` | FK to new schedule table |
| `MonitoringPointScheduleStatus` | `ReceiverScheduleStatus` | Can potentially reuse |

**Current ReceiverSchedule Schema** (`V000000001__IWA-2898_init.sql:3164-3178`):
```sql
CREATE TABLE `ReceiverSchedule` (
  `ReceiverScheduleID` int NOT NULL AUTO_INCREMENT,
  `ReceiverID` int NOT NULL,  -- Would become MonitoringPointID
  `UserID` int NOT NULL,
  `RQID` int NOT NULL,
  `DateCreated` datetime DEFAULT NULL,
  `ReceiverScheduleStatusID` int DEFAULT NULL,
  `Frequency` int DEFAULT NULL,
  `Samples` int DEFAULT NULL,
  `GRange` varchar(10) NOT NULL DEFAULT '32',
  PRIMARY KEY (`ReceiverScheduleID`)
);
```

##### Stored Procedures Requiring Changes

**High Priority - Core Schedule CRUD** (6 procedures):
| Procedure | File | Change Required |
|-----------|------|-----------------|
| `Receiver_AddReceiverSchedule` | `R__PROC_Receiver_AddReceiverSchedule.sql:5-44` | Rename, change to accept MonitoringPointID |
| `Receiver_AddReceiverSchedule_Iterator` | `R__PROC_Receiver_AddReceiverSchedule_Iterator.sql:5-46` | Rename, update FK references |
| `Receiver_GetReceiverSchedule` | `R__PROC_Receiver_GetReceiverSchedule.sql:5-28` | Rename, query by MonitoringPointID |
| `Receiver_GetProvisionReceiverSchedule` | `R__PROC_Receiver_GetProvisionReceiverSchedule.sql:5-112` | Simplify - direct MP lookup |
| `Request_PopulateScheduledReadings` | `R__PROC_Request_PopulateScheduledReadings.sql:5-47` | Update JOIN logic |
| `Request_DeleteScheduleReadingData` | `R__PROC_Request_DeleteScheduleReadingData.sql` | Update table references |

**Medium Priority - Schedule Queries** (8 procedures):
| Procedure | File | Change Required |
|-----------|------|-----------------|
| `MonitoringPoint_GetLastReceiverSchedule` | `R__PROC_MonitoringPoint_GetLastReceiverSchedule.sql` | **Can be eliminated** - direct lookup |
| `MonitoringPoint_GetLastReceiverSchedule_v2` | `R__PROC_MonitoringPoint_GetLastReceiverSchedule_v2.sql` | **Can be eliminated** |
| `Facility_GetReceiverSchedules` | `R__PROC_Facility_GetReceiverSchedules.sql:35-36` | Simplify JOINs |
| `Facility_GetReceiversWithSchedules` | `R__PROC_Facility_GetReceiversWithSchedules.sql:37-44` | Simplify JOINs |
| `Facility_GetSchedules` | `R__PROC_Facility_GetSchedules.sql:10-27` | Update table references |
| `Hub_GetSchedulesGraph` | `R__PROC_Hub_GetSchedulesGraph.sql` | Update JOINs |
| `Facility_GetMostRecentOptimizeScheduleAudit` | `R__PROC_Facility_GetMostRecentOptimizeScheduleAudit.sql` | Update references |
| `Request_PopulateScheduledReadingsMissing` | `R__PROC_Request_PopulateScheduledReadingsMissing.sql:32-38` | Update JOINs |

**Low Priority - Schedule Cleanup/Status** (4 procedures):
| Procedure | File | Change Required |
|-----------|------|-----------------|
| `ReceiverSchedule_FindHubsMissingSchedule` | `R__PROC_ReceiverSchedule_FindHubsMissingSchedule.sql` | Rename, update logic |
| `ReceiverSchedule_FindSchedulesNotNeeded` | `R__PROC_ReceiverSchedule_FindSchedulesNotNeeded.sql` | Rename, update logic |
| `Receiver_UpdateScheduledReadingUptime14d` | `R__PROC_Receiver_UpdateScheduledReadingUptime14d.sql` | Update column references |
| `Receiver_RemoveReceiver` | `R__PROC_Receiver_RemoveReceiver.sql:39-44` | Remove schedule status update |

**Affected Indirectly** (procedures that JOIN to ReceiverSchedule):
- `MonitoringPoint_RemoveMonitoringPoint.sql:55-60`
- All procedures that filter by `ReceiverScheduleStatusID=1`

##### API Layer (Lambda Functions)

| Lambda | File | Method | Change |
|--------|------|--------|--------|
| `lf-vero-prod-sensor` | `main.py:765-773` | `getSensorSchedule` | Rename to `getMonitoringPointSchedule`, accept `mpid` |
| `lf-vero-prod-monitoringpoint` | `main.py:1205-1213` | `getLastReceiverSchedule` | **Can be eliminated** |

##### Frontend Layer

**Services**:
| File | Functions | Change |
|------|-----------|--------|
| `SensorServices.ts:90-101` | `getReceiverScheduleList()` | Move to MonitoringPointService |
| `SensorServices.ts:596-613` | `getReceiverSchedule()` | Move to MonitoringPointService |
| `MonitoringPointService.ts:110-121` | `getLastReceiverSchedule()` | **Can be eliminated** |
| `RequestServiceV2.ts:193-215` | `scheduleRequestV2()` | Accept MonitoringPointID |

**Hooks**:
| File | Change |
|------|--------|
| `useGetSensorSchedule.ts:1-36` | Rename to `useGetMonitoringPointSchedule`, change params |

**Components**:
| File | Change |
|------|--------|
| `Invoke.tsx:51-68` | Query by MonitoringPointID instead of serial/part number |
| `InvokeSensors.tsx:75-99` | Query by MonitoringPointID |
| `UpdateMonitoringPointModal.tsx:1189-1205` | `sendScheduleToAssignedSensor()` simplifies significantly |

---

#### 2. assetwatch-jobs Repository

##### Jobs Requiring Changes

**Schedule Processing Jobs**:

| Job | Key Files | Impact |
|-----|-----------|--------|
| **request-schedule** | `request-schedule/main.py`, `master_schedule.py`, `request_sql.py` | High - queries ReceiverSchedule, calls stored procs |
| **request-master-schedule** | `request-master-schedule/main.py`, `gen2.py`, `gen3.py` | Medium - schedule distribution |
| **schedule-optimizer** | `jobs_schedule_optimizer/main.py` | High - queries ReceiverSchedule for optimization |
| **jobs-daemon** | `jobs-daemon/main.py`, `objectspectrum.py`, `unleashed.py` | High - calls schedule procs |

**Hardware Jobs**:
| Job | Key Files | Impact |
|-----|-----------|--------|
| **jobs-hardware** | `sensor.py` | Medium - queries ReceiverSchedule |
| **jobs-descase-hardware** | `uptime.py` | Low - schedule references |

**ML Jobs**:
| Job | Key Files | Impact |
|-----|-----------|--------|
| **jobs-ml-rca-v2** | `main.py` | Medium - JOINs ReceiverSchedule |

**Request Processing**:
| Job | Key Files | Impact |
|-----|-----------|--------|
| **request-lambda** | `request_resources.py` | Medium - calls Receiver_AddReceiverSchedule |
| **request-processor-v1** | `request_resources.py` | Medium - calls Receiver_AddReceiverSchedule |

##### Stored Procedures in assetwatch-jobs

| Procedure | File | Impact |
|-----------|------|--------|
| `Receiver_GetProvisionReceiverSchedule` | `mysql/db/procs/R__PROC_Receiver_GetProvisionReceiverSchedule.sql` | High - duplicate of fullstack, needs sync |
| `Request_ProvisionSensor` | `mysql/db/procs/R__PROC_Request_ProvisionSensor.sql` | Medium - calls schedule proc |
| `Request_ProvisionSensor_new` | `mysql/db/procs/R__PROC_Request_ProvisionSensor_new.sql` | Medium - calls schedule proc |

---

#### 3. assetwatch-mobile-backend Repository

##### Services

| File | Methods | Impact |
|------|---------|--------|
| `HubService.ts` | `manageHubSchedule()`, `syncHubSchedule()`, `clearHubSchedules()`, `createHubSchedules()`, `sendHubSchedules()` | High - hub schedule sync |
| `SensorService.ts` | `updateSensorSchedule()` | Medium - sensor removal |

##### Repositories

| File | Methods | Impact |
|------|---------|--------|
| `HubRepository.ts` | `getFacilityHubSchedule()` - calls `Facility_GetSchedules` | Medium - proc call |
| `SensorRepository.ts` | `updateSensorSchedule()` - updates ReceiverScheduleStatusID | Medium - status updates |

##### SQL Queries

| File | Lines | Impact |
|------|-------|--------|
| `MonitoringPointOperations.ts` | 72, 224 | LEFT JOINs ReceiverSchedule |

---

#### 4. assetwatch.mobile Repository

**NO IMPACT** - The mobile app does not directly interact with ReceiverSchedule. It handles:
- Work order scheduling (`DateScheduled` field)
- Marketing call scheduling
- Local notification scheduling

The mobile app receives schedule data indirectly through the mobile backend, which would handle the translation.

---

### Data Migration Strategy

#### Phase 1: Schema Creation
```sql
-- Create new tables
CREATE TABLE MonitoringPointSchedule (
  MonitoringPointScheduleID int NOT NULL AUTO_INCREMENT,
  MonitoringPointID int NOT NULL,
  UserID int NOT NULL,
  RQID int NOT NULL,
  DateCreated datetime DEFAULT NULL,
  MonitoringPointScheduleStatusID int DEFAULT NULL,
  Frequency int DEFAULT NULL,
  Samples int DEFAULT NULL,
  GRange varchar(10) NOT NULL DEFAULT '32',
  PRIMARY KEY (MonitoringPointScheduleID),
  FOREIGN KEY (MonitoringPointID) REFERENCES MonitoringPoint(MonitoringPointID)
);

CREATE TABLE MonitoringPointScheduleTime (
  MonitoringPointScheduleTimeID int NOT NULL AUTO_INCREMENT,
  ReadingDayOfWeek smallint NOT NULL,
  ReadingTime time NOT NULL,
  MonitoringPointScheduleID int DEFAULT NULL,
  PRIMARY KEY (MonitoringPointScheduleTimeID),
  FOREIGN KEY (MonitoringPointScheduleID) REFERENCES MonitoringPointSchedule(MonitoringPointScheduleID)
);
```

#### Phase 2: Data Migration
```sql
-- Migrate active schedules to their current MonitoringPoint
INSERT INTO MonitoringPointSchedule (MonitoringPointID, UserID, RQID, DateCreated, MonitoringPointScheduleStatusID, Frequency, Samples, GRange)
SELECT
  mpr.MonitoringPointID,
  rs.UserID,
  rs.RQID,
  rs.DateCreated,
  rs.ReceiverScheduleStatusID,
  rs.Frequency,
  rs.Samples,
  rs.GRange
FROM ReceiverSchedule rs
JOIN Receiver r ON rs.ReceiverID = r.ReceiverID
JOIN MonitoringPoint_Receiver mpr ON r.ReceiverID = mpr.ReceiverID AND mpr.ActiveFlag = 1
WHERE rs.ReceiverScheduleStatusID = 1;
```

#### Phase 3: Dual-Write Period
- New schedules written to both tables
- Reads from new tables
- Allows rollback if issues discovered

#### Phase 4: Cleanup
- Drop ReceiverSchedule tables after validation
- Remove legacy stored procedures

---

### Business Logic Changes

#### Current Behavior (Schedule Follows Sensor)

```
Day 1: Sensor R1 on MP1 with Schedule S1 (8am, 12pm, 4pm)
       → R1 takes readings at 8am, 12pm, 4pm

Day 2: Sensor R1 moved to MP2
       → R1 still takes readings at 8am, 12pm, 4pm on MP2

Day 2: Sensor R2 installed on MP1
       → R2 inherits S1 from R1 via MonitoringPoint_GetLastReceiverSchedule
       → R2 takes readings at 8am, 12pm, 4pm
```

#### Proposed Behavior (Schedule Follows Location)

```
Day 1: MP1 has Schedule S1 (8am, 12pm, 4pm), Sensor R1 installed
       → R1 takes readings at 8am, 12pm, 4pm

Day 2: Sensor R1 moved to MP2 (which has Schedule S2: 6am, 2pm, 10pm)
       → R1 now takes readings at 6am, 2pm, 10pm

Day 2: Sensor R2 installed on MP1
       → R2 automatically uses MP1's schedule S1
       → NO INHERITANCE NEEDED - schedule is already there
```

#### Advantages of MonitoringPointSchedule
1. **Simpler sensor replacement** - No schedule inheritance needed
2. **Location-centric thinking** - "This pump needs readings every 4 hours" vs "This sensor takes readings every 4 hours"
3. **Spare sensor handling** - Unassigned sensors don't need schedules
4. **Clearer data model** - Schedule belongs to the asset being monitored

#### Disadvantages/Challenges
1. **Large migration effort** across 4 repos
2. **Historical data ambiguity** - Which MP did old schedule S1 apply to?
3. **Edge cases** - What happens to MonitoringPoints that never had sensors?
4. **Testing complexity** - Many integration points to verify

---

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Data loss during migration | Low | High | Dual-write period, extensive testing |
| Missed procedure updates | Medium | Medium | Comprehensive grep audit, integration tests |
| Schedule sync failures | Medium | High | Staged rollout by facility |
| Job failures | Medium | High | Feature flags, rollback capability |
| Mobile backend desync | Low | Medium | Mobile app unaffected, backend isolated |

---

## Code References

### fullstack.assetwatch
- `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:3164-3178` - ReceiverSchedule schema
- `mysql/db/procs/R__PROC_Receiver_AddReceiverSchedule.sql:5-44` - Create schedule
- `mysql/db/procs/R__PROC_Receiver_GetReceiverSchedule.sql:5-28` - Get schedule
- `mysql/db/procs/R__PROC_MonitoringPoint_GetLastReceiverSchedule_v2.sql:5-50` - Inheritance pattern
- `mysql/db/procs/R__PROC_Receiver_GetProvisionReceiverSchedule.sql:5-112` - Provision schedule
- `frontend/src/shared/api/SensorServices.ts:90-101` - Frontend service
- `frontend/src/hooks/services/useGetSensorSchedule.ts:1-36` - React hook
- `frontend/src/components/UpdateMonitoringPointModal/UpdateMonitoringPointModal.tsx:1189-1205` - Schedule inheritance UI

### assetwatch-jobs
- `terraform/jobs/request_v2/request-schedule/main.py` - Schedule job entry
- `terraform/jobs/request_v2/request-schedule/request_sql.py` - Schedule SQL calls
- `terraform/jobs/jobs_daemon/jobs-daemon/main.py` - Daemon schedule checks
- `terraform/jobs/jobs_schedule_optimizer/jobs-schedule-optimizer/main.py` - Optimizer

### assetwatch-mobile-backend
- `lambda/lf-assetwatch-collect-cf/src/service/HubService.ts` - Hub schedule sync
- `lambda/lf-assetwatch-collect-cf/src/repository/SensorRepository.ts` - Schedule status updates
- `lambda/lf-assetwatch-collect-cf/src/MonitoringPointOperations.ts:72,224` - Schedule JOINs

---

## Architecture Insights

1. **Schedule Inheritance is a Workaround**: The `MonitoringPoint_GetLastReceiverSchedule` procedures exist because schedules are tied to Receivers. This is conceptual overhead that wouldn't exist with MonitoringPointSchedule.

2. **Active Flag Pattern**: The `ActiveFlag=1` pattern in `MonitoringPoint_Receiver` already treats MonitoringPoints as the "primary" entity. Schedules should follow this pattern.

3. **Hub Schedule Sync**: The `HubService` in mobile-backend syncs schedules to physical hub hardware. This would still work with MonitoringPointSchedule - the hub needs to know "which sensors take readings when" regardless of where the schedule is stored.

4. **Receiver Table Has Schedule Data**: The `Receiver` table contains `Frequency` and `ScheduledReadingUptime14d` columns, suggesting deep coupling between Receiver and schedule concepts that would need cleanup.

---

## Historical Context (from thoughts/)

**No existing documentation found** in the thoughts/ directory regarding:
- ReceiverSchedule architecture decisions
- MonitoringPointSchedule proposals
- Schedule design discussions

This appears to be a new architectural consideration.

---

## Recommendations

### Option A: Full Migration (High Effort, Clean Architecture)
- Create MonitoringPointSchedule tables
- Migrate all data
- Update all procedures, jobs, and frontend
- **Estimated effort**: 4-6 weeks
- **Recommended for**: Long-term maintainability

### Option B: Incremental Abstraction (Medium Effort, Backward Compatible)
- Create abstraction layer that queries ReceiverSchedule via MonitoringPointID
- New APIs use MonitoringPointID, translate internally
- Gradual migration of stored procedures
- **Estimated effort**: 2-3 weeks
- **Recommended for**: Risk-averse approach

### Option C: Status Quo with Documentation (Low Effort)
- Keep ReceiverSchedule
- Document the inheritance pattern clearly
- Accept the conceptual complexity
- **Estimated effort**: 1 week
- **Recommended for**: If business value doesn't justify migration

---

## Open Questions

1. **Historical Schedule Data**: How important is maintaining the history of which MonitoringPoint each schedule applied to?

2. **Unassigned MonitoringPoints**: Should MonitoringPoints without sensors have schedules? (Probably yes - "this location should be monitored every 4 hours")

3. **Multi-Sensor MonitoringPoints**: Are there cases where one MP has multiple active Receivers? (Current model says no via ActiveFlag=1)

4. **Schedule Optimizer Impact**: Does the schedule optimizer need to understand the new model differently?

5. **Regulatory/Audit Requirements**: Are there compliance requirements for schedule history that affect data model choices?
