---
date: 2026-01-19T15:18:17-05:00
researcher: jwalker
git_commit: 35bb96c8a286eb1705ca2dd97fea4b5f4c8cc648
branch: dev
repository: fullstack.assetwatch
topic: "What happens to alert statuses when an account is churned"
tags: [research, codebase, churn, asset-alerts, facility-status]
status: complete
last_updated: 2026-01-19
last_updated_by: jwalker
---

# Research: What Happens to Alert Statuses When an Account is Churned

**Date**: 2026-01-19T15:18:17-05:00
**Researcher**: jwalker
**Git Commit**: 35bb96c8a286eb1705ca2dd97fea4b5f4c8cc648
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question

When we churn an account, are all the alerts being flipped to "No Action Needed" (including Resolved ones)? The suspicion is that this is happening, but we should be preserving the Resolved ones.

**Context:**
- `FacilityStatusID = 2` is "Churned"
- `AssetAlertStatusID = 1` is "Resolved"
- `AssetAlertStatusID = 5` is "No Action Needed"

## Summary

**ANSWER: NO - Churning a facility does NOT directly update any alert statuses.**

When a facility is churned (FacilityStatusID changes to 2), **there is no stored procedure, trigger, or Lambda code that updates AssetAlertStatusID for any alerts**. The alerts remain in their existing status (including Resolved alerts, which stay as status 1).

**HOWEVER**, there are two **indirect** scenarios where alerts DO get set to "No Action Needed" (status 5):

1. **Machine Removal** (`Machine_RemoveMachine`): If machines are explicitly removed as part of the churn process, ALL alerts for those machines are set to status 5 - **including Resolved ones**.

2. **MonitoringPoint Deactivation** (trigger `TR_MonitoringPoint_ON_UPDATE`): If monitoring points are deactivated, alerts with status 2 (Watching) or 4 (Maintenance Recommended) are set to status 5. **Resolved alerts (status 1) are preserved in this case.**

## Detailed Findings

### 1. The Churn Process Flow

When a facility is churned, the following happens in sequence:

**Step 1: Facility Status Update**
- `Facility_RemoveFacility` or `Facility_UpdateFacilityStatus` is called
- Changes `FacilityStatusID` from 1 (Live Customer) to 2 (Churned)
- **No alert status updates occur here**

**Step 2: Lambda Handler Actions** (`lf-vero-prod-facilities/main.py:1205-1244`)
When `facilityStatus == 2`:
1. Calls `FacilityService_DisableIntegrationServices` - disables CMMS/APIs
2. Calls `FacilityUser_GetFacilityUsers` - gets user list
3. Calls `FacilityUser_RemoveFromFacility` - removes users
4. **No alert-related procedures are called**

### 2. Where Alerts DO Get Set to "No Action Needed"

#### A. Machine Removal - **DOES Affect Resolved Alerts**

**File:** `mysql/db/procs/R__PROC_Machine_RemoveMachine.sql:11`

```sql
UPDATE AssetAlert SET AssetAlertStatusID=5 WHERE FIND_IN_SET(MachineID,inMachineIDList);
```

**Behavior:**
- Sets **ALL** alerts for the removed machines to status 5
- **No WHERE clause excludes Resolved alerts (status 1)**
- This WOULD flip Resolved alerts to "No Action Needed"

**When called:** Only when machines are explicitly removed from the system, NOT automatically during churn.

#### B. MonitoringPoint Deactivation - **Preserves Resolved Alerts**

**File:** `mysql/db/triggers/R__TRIGGER_UPDATE_MonitoringPointTrigger.sql:10-16`

```sql
IF NEW.ActiveFlag = 0 THEN
    UPDATE AssetAlert
    SET
        AssetAlertStatusID = 5,
        DateResolved = NOW()
    WHERE MonitoringPointID = OLD.MonitoringPointID
    AND AssetAlertStatusID IN (2,4);  -- Only Watching and Maintenance Recommended
END IF;
```

**Behavior:**
- Only updates alerts with status 2 (Watching) or 4 (Maintenance Recommended)
- **Resolved alerts (status 1) are NOT affected**
- This is the correct behavior for preserving historical data

### 3. Facility Status and Alert Visibility

While alerts aren't modified during churn, they become **hidden** from queries:

**File:** `mysql/db/procs/R__PROC_AssetAlert_GetAssetAlerts.sql:88`

```sql
AND ((f.FacilityStatusID IN (1,3,16) AND mp.ActiveFlag = 1) OR aa.AssetAlertStatusID IN (1,5))
```

This means:
- For churned facilities (status 2), only alerts with status 1 (Resolved) or 5 (No Action Needed) are returned
- Active alerts (status 2, 4) for churned facilities are hidden
- Resolved alerts remain visible for historical reference

### 4. Status Values Reference

| ID | Name | Description |
|----|------|-------------|
| 1 | Resolved | Alert resolved by customer/CME |
| 2 | Watching | Alert being monitored |
| 4 | Maintenance Recommended | Action needed |
| 5 | No Action Needed | Closed without maintenance |

## Code References

- `mysql/db/procs/R__PROC_Facility_RemoveFacility.sql` - Facility status change (no alert updates)
- `mysql/db/procs/R__PROC_Machine_RemoveMachine.sql:11` - Bulk sets alerts to status 5 (affects ALL statuses)
- `mysql/db/triggers/R__TRIGGER_UPDATE_MonitoringPointTrigger.sql:10-16` - Sets status 5 only for status 2,4
- `mysql/db/procs/R__PROC_AssetAlert_GetAssetAlerts.sql:88` - Query filtering for churned facilities
- `lambdas/lf-vero-prod-facilities/main.py:1205-1244` - Churn orchestration (no alert updates)

## Architecture Documentation

### Churn Workflow

```
User triggers churn
        │
        ▼
┌───────────────────────────────┐
│ Facility_RemoveFacility       │
│ - Sets FacilityStatusID = 2   │
│ - NO alert status changes     │
└───────────────────────────────┘
        │
        ▼
┌───────────────────────────────┐
│ Lambda: updateFacilityFromLayout │
│ - Disables integrations       │
│ - Removes users               │
│ - NO alert procedures called  │
└───────────────────────────────┘
        │
        ▼
┌───────────────────────────────┐
│ Alerts remain unchanged       │
│ - Status preserved            │
│ - Just hidden from queries    │
└───────────────────────────────┘
```

### The Machine_RemoveMachine Issue

If `Machine_RemoveMachine` is called separately (not automatically during churn), it DOES flip all alerts including Resolved ones:

```
Machine_RemoveMachine called
        │
        ▼
┌───────────────────────────────┐
│ UPDATE AssetAlert             │
│ SET AssetAlertStatusID = 5    │
│ WHERE MachineID IN (...)      │
│                               │
│ ⚠️ No status filter!          │
│ ALL alerts → "No Action"      │
└───────────────────────────────┘
```

## Key Findings

1. **Standard churn process**: Does NOT modify alert statuses. Resolved alerts are preserved.

2. **Machine removal**: DOES flip ALL alerts (including Resolved) to "No Action Needed". This may be the source of the suspected behavior if machines are being removed as part of churn.

3. **MonitoringPoint deactivation**: Correctly preserves Resolved alerts (only flips status 2 and 4).

4. **Visibility vs. Modification**: Churned facility alerts aren't deleted or modified - they're just filtered from active queries while preserving Resolved/No Action Needed for historical purposes.

## Open Questions

1. **Is `Machine_RemoveMachine` being called as part of the churn workflow?** If so, this would explain Resolved alerts being flipped to "No Action Needed".

2. **Should `Machine_RemoveMachine` preserve Resolved alerts?** The current behavior seems intentional for cleanup, but may need review if historical data should be preserved.

3. **What is the actual observed behavior?** Running queries against the database to check recent churn events would confirm which scenario is occurring.
