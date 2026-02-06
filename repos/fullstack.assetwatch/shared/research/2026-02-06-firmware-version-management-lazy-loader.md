---
date: 2026-02-06T09:42:23-05:00
researcher: Jackson Walker
git_commit: aef6609646df1ec10108205f749be14f7d84fce3
branch: dev
repository: fullstack.assetwatch
topic: "Firmware Version Management, Lazy Loader, and FirmwareID/FirmwareVersion Update Flow"
tags: [research, codebase, firmware, lazy-loader, receiver, sensor, firmware-update, jobs-repo, mqtt]
status: complete
last_updated: 2026-02-06
last_updated_by: Jackson Walker
last_updated_note: "Added complete external service flow from assetwatch-jobs repo"
---

# Research: Firmware Version Management, Lazy Loader, and FirmwareID/FirmwareVersion Update Flow

**Date**: 2026-02-06T09:42:23-05:00
**Researcher**: Jackson Walker
**Git Commit**: aef6609646df1ec10108205f749be14f7d84fce3
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question

How does the firmware management system work end-to-end? Specifically:
1. How does the firmware lazy loader determine which sensors need updates?
2. How does FirmwareID get set/updated on the Receiver table?
3. How does FirmwareVersion get set/updated on the Receiver table?
4. What is the full lifecycle of a firmware update from targeting to completion?

Context: Hardware engineer reported a data discrepancy with FirmwareID in the Receiver table causing the lazy loader to target already-updated sensors, and a potential bug preventing FirmwareVersion from being updated after successful firmware updates.

## Summary

The firmware management system consists of a **lazy loader** that automatically identifies sensors needing firmware updates, a **request processing pipeline** that creates and tracks update requests, and an **acknowledgement flow** that updates the Receiver table upon successful completion.

Key architectural finding: The Receiver table has **two separate firmware-tracking fields** — `FirmwareID` (integer FK to Firmware table) and `FirmwareVersion` (varchar string). These fields serve different purposes and are updated by different code paths. The `Receiver_UpdateFirmwareVersion` stored procedure updates `FirmwareID` but does **NOT** update `FirmwareVersion`. Meanwhile, the `Sensor_GetFirmwareVersion` procedure reads firmware version by looking up `Firmware.Version` through the `FirmwareID` FK join, effectively ignoring `Receiver.FirmwareVersion` for sensor products.

## Detailed Findings

### 1. Database Schema — Firmware-Related Tables

#### Receiver Table (Sensors)
File: `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:2923-2973`

The Receiver table stores sensor hardware records with two firmware fields:
- **`FirmwareID`** (INT, FK → Firmware.FirmwareID) — Tracks *which* firmware record is assigned
- **`FirmwareVersion`** (VARCHAR(45)) — Stores a version string independently
- **`PartID`** (INT, FK → Part.PartID) — Links to the Part table which has `DefaultFirmwareID`

#### Firmware Table
File: `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:1526-1545`

- `FirmwareID` (PK), `Version` (varchar), `FileName`, `FirmwareStatusID`, `TargetFirmewareID`, `PartID`, `DateCreated`, `DateUpdated`, `Notes`, `FileBytes`, `UserID`
- Note the typo: `TargetFirmewareID` (missing 'w')

#### Part Table
File: `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:2595-2613`

- **`DefaultFirmwareID`** (INT, FK → Firmware.FirmwareID) — The "default" firmware the lazy loader uses
- `TargetFirmewareID` — Also present but not used in the active lazy loader query

#### FacilityFirmware Table (Lazy Loader Exceptions)
File: `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:1101-1117`

- `FacilityFirmwareID` (PK), `FacilityID`, `FirmwareID`, `ProductID`, `PartID`, `LockFirmwareVersion`
- Stores per-facility firmware overrides that take priority over the Part default
- `LockFirmwareVersion` flag prevents automatic updates when set to 1

#### ReceiverFirmwareHistory Table
File: `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:3082-3094`

- `ReceiverFirmwareHistoryID` (PK), `ReceiverID`, `FirmwareID`, `StartDate`, `EndDate`
- Tracks firmware change history per receiver

#### Transponder Table (Hubs)
File: `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:3872-3900`

- Uses `FirmwareVersion` (VARCHAR) only — no `FirmwareID` FK
- Different architecture from sensors: hub firmware tracked by version string only

### 2. Lazy Loader — Sensor Targeting Logic

#### Primary Procedure: `Firmware_GetSensorsToUpdate`
File: `mysql/db/procs/R__PROC_Firmware_GetSensorsToUpdate.sql`

This is the core lazy loader logic. The active code path (lines 9-43) runs when `HOUR(CURRENT_TIMESTAMP()) < 24` (always true — effectively runs 24/7).

**How it determines the target firmware for each sensor:**
```
FacilityFirmware override exists? → Use FacilityFirmware.FirmwareID
No override?                      → Use Part.DefaultFirmwareID
```

Specifically (line 11-13):
```sql
(CASE WHEN fw.FirmwareID IS NULL THEN dfw.FirmwareID ELSE fw.FirmwareID END) AS FirmwareID
```
Where `fw` is joined from FacilityFirmware (LEFT JOIN) and `dfw` is the default from Part.

**How it determines which sensors are "out of date" (line 37):**
```sql
AND ((CASE WHEN ffw.FirmwareID IS NOT NULL
      THEN ffw.FirmwareID <> r.FirmwareID AND fw.Version <> 'NOUPDATE'
      ELSE r.FirmwareID IS NULL OR p.DefaultFirmwareID <> r.FirmwareID END))
```

This compares `Receiver.FirmwareID` against either:
- The FacilityFirmware override (if present), excluding 'NOUPDATE' versions
- The Part default `DefaultFirmwareID` (if no facility override)

**Additional filters:**
- `mpr.ActiveFlag=1` — Only active monitoring point assignments
- `f.FacilityID NOT IN (504, 505)` — Hardcoded facility exclusions
- `mpr.Startdate < DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 DAY)` — Sensor must be assigned for 3+ days
- `r.LastReadingDate >= DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)` — Sensor must have reported in last 7 days
- `t.LastReadingDate >= DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 DAY)` — Hub must have reported in last 3 days
- `p.ProductID IN (3,16)` — ProductID 3 = standard sensors, 16 = Hazloc sensors
- `NOT EXISTS(Request WHERE RequestTypeID=6 AND DateCreated > INTERVAL 6 HOUR)` — No pending request in last 6 hours
- `GROUP BY TransponderSerialNumber` — One sensor per hub at a time
- `LIMIT 75` — Max 75 sensors per batch

**Join path to reach facility:**
```
Receiver → MonitoringPoint_Receiver → MonitoringPoint → Machine → Line → Facility
```

#### Inventory Sensor Variant: `Firmware_GetInventorySensorsToUpdate`
File: `mysql/db/procs/R__PROC_Firmware_GetInventorySensorsToUpdate.sql`

Uses a different join path for inventory/spare sensors:
```
Receiver → Facility_Receiver → Facility
```
Also uses `HubDiagnostic` + `HubDiagnosticReceiverScan` to identify which hub can reach which sensor. Creates a temporary table to ensure one-to-one hub-sensor pairing. Currently hardcoded to FacilityID 2309.

### 3. Firmware Update Request Creation

#### `Request_ProcessConnectedHub`
File: `mysql/db/procs/R__PROC_Request_ProcessConnectedHub.sql`

When a hub connects and reports to the system, this procedure:
1. Looks up the target firmware: `DefaultFirmwareID FROM Part WHERE PartNumber = inTransponderPartNumber` (line 31)
2. Creates a new Transponder record if one doesn't exist
3. Calls `Request_AddRequest` to create the firmware update request
4. Calls `RequestHub_UpdateStatus` to track hub-level progress

**Note:** This procedure uses `Part.DefaultFirmwareID` directly for hub firmware, not FacilityFirmware overrides. The hub firmware request targets the global default.

### 4. Firmware Update Acknowledgement Flow

#### `Request_AcknowledgeRequest`
File: `mysql/db/procs/R__PROC_Request_AcknowledgeRequest.sql`

This is the critical procedure called when the system receives confirmation of a firmware update completion. The flow for **sensor firmware** (RequestTypeID=6):

1. Looks up the RequestTypeID (line 26)
2. For sensor/hub firmware (RequestTypeID IN (6,3)), calls `Request_GetRequestID` to find the matching request (line 58)
3. Gets the current request's status and hub status (lines 59-60)
4. **Critical logic for sensor firmware (RequestTypeID=6), lines 61-70:**
   ```
   If inRequestHubStatusID == 3 (success):
     → Sets localRequestStatusID = 3 (completed)
     → BUT ALSO: Sets inRequestHubStatusID = localCurrentRequestHubStatusID (line 68)
       (This overwrites the incoming hub status with the current DB value for sensor FW)
   If inRequestHubStatusID == 2 (MQTT Received):
     → Only updates if current DB value is 1 (MQTT Sent)
   ```
5. **Line 81-83:** If sensor firmware (type=6) AND request completed successfully (status=3):
   ```sql
   CALL Receiver_UpdateFirmwareVersion(inRQID, inReceiverSerialNumber, inReceiverPartNumber);
   ```
6. **Line 86-88:** If hub firmware (type=3) AND request completed successfully (status=3):
   ```sql
   CALL Transponder_UpdateFirmwareVersion(inRQID, inTransponderSerialNumber, inTransponderPartNumber);
   ```

### 5. How Receiver.FirmwareID Gets Updated

#### `Receiver_UpdateFirmwareVersion`
File: `mysql/db/procs/R__PROC_Receiver_UpdateFirmwareVersion.sql`

```sql
SET localReceiverID = (SELECT ReceiverID FROM Receiver
    WHERE SerialNumber = inReceiverSerialNumber AND PartID = localReceiverPartID);

SET localFirmwareID = (SELECT FirmwareID FROM Request
    WHERE RQID = inRQID AND ReceiverID = localReceiverID AND RequestTypeID = 6);

UPDATE Receiver SET FirmwareID = localFirmwareID, _version = _version + 1
    WHERE ReceiverID = localReceiverID;
```

**What this procedure does:**
1. Finds the ReceiverID from serial number + part number
2. Looks up the FirmwareID from the matching Request record
3. **Updates `Receiver.FirmwareID`** to the new firmware ID
4. **Does NOT update `Receiver.FirmwareVersion`** — only FirmwareID and _version counter
5. Closes the previous ReceiverFirmwareHistory record (sets EndDate)
6. Creates a new ReceiverFirmwareHistory record with the new FirmwareID

#### Contrast: `Transponder_UpdateFirmwareVersion` (Hub Update)
File: `mysql/db/procs/R__PROC_Transponder_UpdateFirmwareVersion.sql`

For hubs, this procedure DOES update the version string:
```sql
SET localFirmwareVersion = (SELECT Version FROM Firmware WHERE FirmwareID = localFirmwareID);
UPDATE Transponder SET FirmwareVersion = localFirmwareVersion WHERE TransponderID=localTransponderID;
```

### 6. How Firmware Version is Retrieved for Display

#### `Sensor_GetFirmwareVersion`
File: `mysql/db/procs/R__PROC_Sensor_GetFirmwareVersion.sql`

```sql
SELECT IF(r.PartID IN (SELECT PartID FROM Part WHERE ProductID IN (3,16)),
    fw.Version,
    r.FirmwareVersion) AS firmwareVersion
FROM Receiver r
LEFT JOIN Firmware fw ON fw.FirmwareID = r.FirmwareID
WHERE r.ReceiverID = localReceiverID;
```

For sensor products (ProductID 3,16): Returns `Firmware.Version` by joining through `Receiver.FirmwareID`
For other products: Returns `Receiver.FirmwareVersion` directly

This means the `FirmwareVersion` varchar field on Receiver is effectively **ignored for sensors** — the displayed version always comes from the Firmware table via the FirmwareID FK join.

### 7. Lazy Loader Configuration (Frontend)

#### Default Firmware Settings
File: `apps/frontend/src/components/FirmwareRolloutPage/LazyLoaderSettings/LazyLoaderSettings.tsx`

Manages the `Part.DefaultFirmwareID` — setting the global default firmware for a given part number.

#### Custom Lazy Loader Exceptions
File: `apps/frontend/src/components/FirmwareRolloutPage/LazyLoaderSettings/CustomLazyLoaderSettings.tsx`

Manages the `FacilityFirmware` table — per-facility firmware overrides including:
- Adding facility-specific firmware versions
- Removing exceptions
- Lock/unlock firmware versions

#### Settings Update Procedure
File: `mysql/db/procs/R__PROC_Firmware_UpdateLazyLoaderSettings.sql`

Handles three operation types:
- `defaultFirmware`: Updates `Part.DefaultFirmwareID`
- `removeException`: Deletes from `FacilityFirmware`
- `addException`: Inserts into `FacilityFirmware`

### 8. Firmware Audit
File: `mysql/db/procs/R__PROC_Facility_GetFirmwareAudit.sql`

The audit query uses two UNION queries:
1. **Sensors**: Joins `Receiver.FirmwareID → Firmware` to get version
2. **Hubs**: Joins `Firmware.Version = Transponder.FirmwareVersion` (string match, not FK)

Note: The sensor audit joins `LEFT JOIN Firmware fw ON fw.FirmwareID=r.FirmwareID`, so sensors with NULL FirmwareID will show no firmware version. It counts those as `norfwv` (no receiver firmware version).

### 9. Firmware Lambda Service
File: `lambdas/lf-vero-prod-firmware/main.py`

Handles firmware CRUD operations:
- `getFirmwareList`, `updateFirmwareStatus`, `getFirmwareStatusList`
- `uploadFirmwareFile` (uploads to S3 bucket `nikola-firmware`)
- `getFirmwareRolloutHistory`, `getFirmwareAudit`
- `updatePartDefaultFirmware`

### 10. Request Flow External Dependencies

The `Firmware_GetSensorsToUpdate` and `Request_AcknowledgeRequest` procedures are **not called directly from lambdas in this repository**. They are invoked from an external **jobs/MQTT processing service** (referenced in `Firmware_GetInventorySensorsToUpdate.sql:1` as "Moved to jobs repo mysql folder"). This means:
- The lazy loader scheduling/invocation logic lives in a separate repository
- The MQTT message processing that triggers `Request_AcknowledgeRequest` also lives externally
- This repo contains the stored procedures (source of truth) and frontend UI

## Code References

### Database Stored Procedures (Core Firmware Flow)
- `mysql/db/procs/R__PROC_Firmware_GetSensorsToUpdate.sql` — Lazy loader targeting logic
- `mysql/db/procs/R__PROC_Firmware_GetSensorsToUpdateTEMP.sql` — Alternative/temp version of lazy loader
- `mysql/db/procs/R__PROC_Firmware_GetInventorySensorsToUpdate.sql` — Inventory sensor lazy loader
- `mysql/db/procs/R__PROC_Request_ProcessConnectedHub.sql` — Hub connection firmware request creation
- `mysql/db/procs/R__PROC_Request_AcknowledgeRequest.sql` — Request completion handler (triggers firmware update)
- `mysql/db/procs/R__PROC_Request_GetRequestID.sql` — Request lookup helper
- `mysql/db/procs/R__PROC_Receiver_UpdateFirmwareVersion.sql` — **Updates Receiver.FirmwareID (NOT FirmwareVersion)**
- `mysql/db/procs/R__PROC_Transponder_UpdateFirmwareVersion.sql` — Updates Transponder.FirmwareVersion string

### Database Stored Procedures (Lazy Loader Configuration)
- `mysql/db/procs/R__PROC_Firmware_UpdateLazyLoaderSettings.sql` — Set default firmware / manage exceptions
- `mysql/db/procs/R__PROC_Firmware_GetLazyLoaderExceptions.sql` — List all facility exceptions
- `mysql/db/procs/R__PROC_FacilityFirmware_Update.sql` — Update facility firmware (global or per-facility)
- `mysql/db/procs/R__PROC_FacilityFirmware_UpdateLock.sql` — Lock/unlock facility firmware

### Database Stored Procedures (Reporting)
- `mysql/db/procs/R__PROC_Facility_GetFirmwareAudit.sql` — Firmware version audit across facilities
- `mysql/db/procs/R__PROC_Request_GetFirmwareRolloutHistory.sql` — Rollout history with counts
- `mysql/db/procs/R__PROC_Firmware_UpdateFirmwareReceiverHistory.sql` — Backfill history from Request table
- `mysql/db/procs/R__PROC_Sensor_GetFirmwareVersion.sql` — Get single sensor firmware version
- `mysql/db/procs/R__PROC_Sensor_GetFirmwareList.sql` — Available sensor firmware list
- `mysql/db/procs/R__PROC_Hub_GetFirmwareList.sql` — Available hub firmware list

### Lambda Functions
- `lambdas/lf-vero-prod-firmware/main.py` — Firmware CRUD Lambda
- `lambdas/lf-vero-prod-sensor/main.py` — Sensor service Lambda (includes `getSensorFirmwareVersion` and `getSensorFirmwareList`)
- `lambdas/lf-vero-prod-hub/hub_check.py` — Hub health check including firmware version comparison

### Frontend
- `apps/frontend/src/components/FirmwareRolloutPage/LazyLoaderSettings/LazyLoaderSettings.tsx` — Default firmware settings UI
- `apps/frontend/src/components/FirmwareRolloutPage/LazyLoaderSettings/CustomLazyLoaderSettings.tsx` — Facility exception management UI
- `apps/frontend/src/components/FirmwareRolloutPage/FirmwareSelection.tsx` — Firmware selection for rollouts
- `apps/frontend/src/components/FirmwareRolloutPage/Rollout.tsx` — Rollout execution
- `apps/frontend/src/pages/FirmwareRollout.tsx` — Main firmware rollout page
- `apps/frontend/src/pages/FirmwareUpload.tsx` — Firmware upload page
- `apps/frontend/src/shared/api/FirmwareService.ts` — Firmware API service
- `apps/frontend/src/shared/api/PartService.ts` — Lazy loader settings API (updateLazyLoaderSettings, getLazyLoaderExceptions)
- `apps/frontend/src/shared/types/firmware/` — All firmware TypeScript types

### Schema
- `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql` — Initial schema with all firmware tables

## Architecture Documentation

### End-to-End Firmware Update Flow

```
1. CONFIGURATION
   Admin sets Part.DefaultFirmwareID via LazyLoaderSettings UI
   Admin optionally sets FacilityFirmware overrides via CustomLazyLoaderSettings UI

2. TARGETING (Lazy Loader)
   Firmware_GetSensorsToUpdate runs periodically (from external jobs repo)
   → Joins Receiver → MonitoringPoint → Machine → Line → Facility
   → LEFT JOINs FacilityFirmware for per-facility overrides
   → Compares Receiver.FirmwareID against target (override or default)
   → Returns up to 75 sensors that need updates (with hub serial numbers)

3. REQUEST CREATION
   External service creates Request records (RequestTypeID=6 for sensors)
   RequestHub records track per-hub progress

4. MQTT DELIVERY
   Firmware file pushed to hub via MQTT
   Hub pushes firmware to sensor via BLE

5. ACKNOWLEDGEMENT
   Hub reports success/failure via MQTT
   Request_AcknowledgeRequest is called:
   → For sensor FW (type=6) with success (status=3):
     → Calls Receiver_UpdateFirmwareVersion
       → Updates Receiver.FirmwareID (from Request table)
       → Updates ReceiverFirmwareHistory
       → Does NOT update Receiver.FirmwareVersion

6. LAZY LOADER RE-EVALUATION
   Next run of GetSensorsToUpdate:
   → Compares Receiver.FirmwareID against target
   → If FirmwareID now matches, sensor is excluded (correctly updated)
```

### Dual Firmware Tracking on Receiver Table

The Receiver table has two firmware fields that serve overlapping purposes:

| Field | Type | Updated By | Used By |
|-------|------|-----------|---------|
| `FirmwareID` | INT (FK) | `Receiver_UpdateFirmwareVersion` (on successful update) | Lazy loader targeting, Firmware audit, `Sensor_GetFirmwareVersion` (via join) |
| `FirmwareVersion` | VARCHAR(45) | **No procedure currently updates this for sensors** | Legacy/non-sensor products, displayed directly for non-sensor receivers |

For sensor products (ProductID 3,16), the `Sensor_GetFirmwareVersion` procedure resolves the version string through the FK join (`Firmware.Version` via `Receiver.FirmwareID`), bypassing `Receiver.FirmwareVersion` entirely.

### Transponder (Hub) vs Receiver (Sensor) Firmware Tracking

| Aspect | Receiver (Sensor) | Transponder (Hub) |
|--------|-------------------|-------------------|
| **FK to Firmware** | `FirmwareID` (INT FK) | None |
| **Version String** | `FirmwareVersion` (VARCHAR) | `FirmwareVersion` (VARCHAR) |
| **Updated on Success** | `FirmwareID` only | `FirmwareVersion` only |
| **History Table** | `ReceiverFirmwareHistory` | None |
| **Lazy Loader Targeting** | Compares `FirmwareID` | N/A (uses `Request_ProcessConnectedHub`) |

## Historical Context (from thoughts/)

- `thoughts/shared/research/2026-01-08-hardware-whitelist-system.md` — Documents firmware update operations (`request-hub-firmware`, `request-sensor-firmware`) as whitelist-protected operations
- `thoughts/shared/research/2026-01-14-IWA-14248-hub-stats-full-stack.md` — Documents Transponder.FirmwareVersion field in hub statistics
- `thoughts/shared/plans/2025-12-02-IWA-14069-hwqa-integration-refactor.md` — References firmware routes (`/firmwarerollout`, `/firmwareupload`) in HWQA integration

## Open Questions

~~1. **Where is `Firmware_GetSensorsToUpdate` invoked from?**~~ — **ANSWERED** in follow-up research below
~~2. **Where is `Request_AcknowledgeRequest` invoked from?**~~ — **ANSWERED** in follow-up research below
3. **What sets `Receiver.FirmwareVersion` initially?** — No procedure in either repo appears to set `Receiver.FirmwareVersion` for sensor products. It may be set during initial sensor provisioning/check-in from an external process.
4. **What is the FacilityFirmware.LockFirmwareVersion flag used for in the main lazy loader?** — The main `Firmware_GetSensorsToUpdate` procedure does not check `LockFirmwareVersion`. It's used by `FacilityFirmware_Update` to prevent global updates from overwriting locked facilities, but the lazy loader itself would still attempt to update locked facilities if a FacilityFirmware record exists.
5. **What about the `TargetFirmewareID` (sic) fields?** — Both `Firmware.TargetFirmewareID` and `Part.TargetFirmewareID` exist in the schema but are not used in any of the active lazy loader or update procedures examined.

## Follow-up Research [2026-02-06T09:59:38-05:00]

After discovering the `assetwatch-jobs` repository, I traced the complete external service flow that was previously unknown. This research answers Open Questions #1 and #2 above.

### Complete External Service Architecture

**Repositories involved:**
- `fullstack.assetwatch` — Database schemas, stored procedures, frontend, firmware CRUD Lambda
- `assetwatch-jobs` — Scheduled jobs, request processors, MQTT acknowledgement handlers

### Phase 1: Lazy Loader Scheduling (VALIDATED)

**Location:** `assetwatch-jobs/terraform/jobs/jobs_hardware/eventbridge.tf:31-57`

EventBridge scheduler runs **every 2 minutes** in production:
```hcl
resource "aws_scheduler_schedule" "jobs_push_missing_firmware_event" {
  schedule_expression = "cron(*/2 * * * ? *)"
  state = (var.env == "prod" && var.branch == "master") ? "ENABLED" : "DISABLED"

  target {
    arn = aws_lambda_function.jobs_hardware.arn
    input = jsonencode({ "meth" : "pushMissingFW" })
  }
}
```

**Comment in code (line 29):** "My math says we could do 100 every 5 minutes and still update the sensor fleet in ~ a week. Must update the corresponding stored proc to limit 100 from 75. Firmware_GetSensorsToUpdate"

### Phase 2: Lazy Loader Execution (VALIDATED)

**Location:** `assetwatch-jobs/terraform/jobs/jobs_hardware/jobs-hardware/main.py:74-82`

```python
elif meth == "pushMissingFW":
    # Lazy loader to check when sensors have outdated firmware versions
    # and then pushes firmware updates to sensors.
    missing_fw = hardware.get_missing_sensor_fw()
    print(f"get_missing_sensor_fw query output for missing_fw: {missing_fw}")

    if len(missing_fw) > 0:
        hardware.push_missing_sensor_fw(missing_fw)
    else:
        print(f"No missing sensor firwmware found")
```

**Location:** `assetwatch-jobs/terraform/jobs/jobs_hardware/jobs-hardware/hardware.py:32-37`

```python
def get_missing_sensor_fw():
    query = "CALL Firmware_GetSensorsToUpdate();"
    retVal = db.mysql_read(query, "cursor")
    return retVal
```

**Returns:** `[(FirmwareID, FirmwareVersion, FileName, ReceiverID, ReceiverSerialNumber, ReceiverPartNumber, TransponderSerialNumber), ...]`

### Phase 3: Request Lambda Invocation (VALIDATED)

**Location:** `assetwatch-jobs/terraform/jobs/jobs_hardware/jobs-hardware/hardware.py:40-72`

```python
def push_missing_sensor_fw(missing_fw):
    sensor_fw_client = boto3.client("lambda")
    RQID = int(time.time())  # Unix timestamp as request ID

    for data in missing_fw:
        FileName = data[2]  # From lazy loader output
        ReceiverSerialNumber = data[4]
        ReceiverPartNumber = data[5]

        receiver = f"{ReceiverPartNumber}_{ReceiverSerialNumber}"

        request = {
            "RequestType": "SensorFirmware",
            "rqid": RQID,
            "Sensor": receiver,
            "FirmwareFileName": FileName,  # ← Critical: FileName from lazy loader
            "User": "e3ea0b52-21db-45bc-8716-220d9209d14e"  # James Maxwell
        }

        # Invoke request-sensor-firmware Lambda asynchronously
        response = sensor_fw_client.invoke(
            FunctionName=JOBS_REQUEST_SENSOR_FIRMWARE_NAME,
            Payload=json.dumps({"body": json.dumps(request)}),
            InvocationType="Event"
        )
```

### Phase 4: Request Creation with FirmwareID Lookup (VALIDATED)

**Location:** `assetwatch-jobs/terraform/jobs/request_v2/request-sensor-firmware/main.py:67-228`

**Critical FirmwareID lookup (lines 144-152):**
```python
firmware_version = firmware_common.get_firmware_version(firmware_filename, smpn)
firmware_id = firmware_common.get_firmware_id(firmware_filename, smpn)
print(f"firmware_version: {firmware_version} firmware_id: {firmware_id}")
```

**Location:** `assetwatch-jobs/terraform/jobs/request_v2/request-sensor-firmware/firmware_common.py:64-78`

```python
def get_firmware_id(firmware_file_name, smpn):
    query = f"""
    SELECT fw.FirmwareID
    FROM Firmware fw
        INNER JOIN Part pt ON pt.PartID = fw.PartID
    WHERE fw.FileName = '{firmware_file_name}'
    AND pt.PartNumber = '{smpn}';
    """

    retVal = db.mysql_read(query)
    return_val = retVal[0]["FirmwareID"]

    return return_val if len(retVal) > 0 else None
```

**THIS IS THE CRITICAL LOOKUP:** FileName → FirmwareID translation happens here!

**Get hubs at facility (main.py:154):**
```python
hub_list = get_hubs_at_facility(sensor)
# Calls: Jobs.Receiver_GetFacilityHubsByReceiver(sensor)
```

**Create Request record for each hub (lines 168-181):**
```python
newRequest = firmware_common.get_sql(
    rqid, smsn, 1, 6, hub_part_number, sensor, smpn, user, firmware_id
)
result = db.mysql_write(newRequest)
```

**Location:** `firmware_common.py:27-46`

```python
def get_sql(rqid, smsnList, request_status_id, request_type_id,
            hpn, sensor, smpn, username, fwid):
    query = f"CALL Request_AddRequest({rqid}, '{request_status_id}', '{request_type_id}', '', '{hpn}', '{sensor}', '{smpn}', '{username}', {fwid});"
    return query
```

**Stored Procedure:** `fullstack.assetwatch/mysql/db/procs/R__PROC_Request_AddRequest.sql:69-70`

```sql
INSERT INTO Request (RQID, DateCreated, RequestTypeID, RequestStatusID,
                     ReceiverID, UserID, FacilityID, FirmwareID)
VALUES (inRQID, FROM_UNIXTIME(inRQID), @RequestTypeID, inRequestStatusID,
        @ReceiverID, @UserID, @FacilityID, @FirmwareID);
```

**FirmwareID is stored in Request table!**

**Send MQTT message (main.py:184-210):**
```python
topic = f"nikola/20/down/{hub_part_number}/{hub_serial_number}/firmware"

payload = {
    "rqid": rqid,
    "v": firmware_version,  # Version string for display
    "smsn": smsn,
    "smpn": smpn,
    "filename": firmware_filename,
    "url": presigned_s3_url  # 6-hour expiration from S3
}

mqtt_object = {"topic": topic, "payload": payload, "user": user, "rqid": rqid, "trace_id": trace_id}
send_to_sqs(MQTT_REQUEST_QUEUE, mqtt_object)
```

### Phase 5: Hub Downloads and Installs Firmware

**UNVALIDATED ASSUMPTION:** Hub receives MQTT message, downloads firmware from S3 presigned URL, pushes to sensor via BLE, sensor installs firmware. This logic lives on the physical hub device (embedded firmware).

### Phase 6: Acknowledgement Processing (VALIDATED)

**Trigger:** MQTT message from hub on topic matching `/firmware/updateversion`

**Location:** `assetwatch-jobs/terraform/jobs/jobs_data_ingestion_firmware/jobs-data-ingestion-firmware/dataParser.py:54-96`

```python
def parse_sensor_update_firmware_version(topic, payload, mqtt_message_id):
    """Parse and process sensor firmware version update."""
    topic_split = topic.split("/")
    transponder_serial_number = topic_split[4]
    transponder_part_number = topic_split[3]

    rqid = payload["rqid"]
    sensor_serial_number = str(payload["smsn"]).zfill(7)
    sensor_part_number = payload["smpn"]
    request_status_id = 3  # Success
    request_type = "Sensor Firmware"

    # Log pattern for CloudWatch dashboard
    app_logger.info(
        f"Sensor firmware version update - RQID: {rqid}, "
        f"Hub: {transponder_part_number}/{transponder_serial_number}, "
        f"Sensor: {sensor_part_number}/{sensor_serial_number}"
    )

    sql_query = "CALL Jobs.Request_AcknowledgeRequest_v2(%s, %s, %s, %s, %s, %s, %s, %s);"
    params = (
        rqid, request_status_id, request_type,
        transponder_serial_number, transponder_part_number,
        sensor_serial_number, sensor_part_number, mqtt_message_id
    )

    result = db.mysql_write(sql_query, params=params, use_shared=True)
```

**Stored Procedure:** `assetwatch-jobs/mysql/db/procs/R__PROC_Request_AcknowledgeRequest_v2.sql:298-322`

This is an **optimized v2 procedure** that flattens the original `Request_AcknowledgeRequest` to reduce ~25 queries to ~10 by eliminating redundant lookups.

```sql
-- Sensor Firmware success (type 6, status 3)
IF (localRequestTypeID = 6 AND localRequestStatusID = 3) THEN
    -- Look up FirmwareID from Request record
    SET localFirmwareID = (
        SELECT FirmwareID
        FROM Vero.Request
        WHERE RQID = inRQID
        AND ReceiverID = localReceiverID
        AND RequestTypeID = 6
    );

    -- Update Receiver firmware
    UPDATE Vero.Receiver
    SET FirmwareID = localFirmwareID,
        _version = _version + 1
    WHERE ReceiverID = localReceiverID;

    -- Close out current firmware history
    UPDATE Vero.ReceiverFirmwareHistory
    SET EndDate = NOW()
    WHERE ReceiverID = localReceiverID
    AND EndDate IS NULL;

    -- Create new firmware history record
    INSERT INTO Vero.ReceiverFirmwareHistory (ReceiverID, FirmwareID, StartDate)
    VALUES (localReceiverID, localFirmwareID, NOW());
END IF;
```

**Note:** The fullstack.assetwatch repo has `R__PROC_Request_AcknowledgeRequest.sql` (original version). The jobs repo has `R__PROC_Request_AcknowledgeRequest_v2.sql` (optimized version) that is actually called in production.

### Complete Validated Data Flow Chain

```
1. EventBridge (every 2 minutes)
   └─> jobs_hardware Lambda (meth="pushMissingFW")

2. hardware.get_missing_sensor_fw()
   └─> CALL Firmware_GetSensorsToUpdate()
   └─> Returns: [(FirmwareID, Version, FileName, ReceiverID, SerialNumber, PartNumber, HubSerial), ...]

3. hardware.push_missing_sensor_fw(missing_fw)
   └─> For each sensor:
       └─> Invoke request-sensor-firmware Lambda
           └─> Pass: {FileName, Sensor, RQID, User}

4. request-sensor-firmware Lambda
   └─> firmware_common.get_firmware_id(FileName, PartNumber)
       └─> SELECT FirmwareID FROM Firmware WHERE FileName=? AND PartNumber=?
       └─> Returns: FirmwareID (or None if not found)

   └─> get_hubs_at_facility(sensor)
       └─> Returns: list of hubs that can reach this sensor

   └─> For each hub:
       └─> CALL Request_AddRequest(RQID, ..., FirmwareID)
           └─> INSERT INTO Request (..., FirmwareID) VALUES (..., FirmwareID)
       └─> Send MQTT message to hub with presigned S3 URL

5. Hub (embedded firmware - UNVALIDATED)
   └─> Downloads firmware from S3
   └─> Pushes to sensor via BLE
   └─> Sensor installs firmware
   └─> Sends success confirmation via MQTT

6. jobs_data_ingestion_firmware (MQTT processor)
   └─> Receives MQTT on topic /firmware/updateversion
   └─> parse_sensor_update_firmware_version()
   └─> CALL Jobs.Request_AcknowledgeRequest_v2(RQID, 3, ...)
       └─> SELECT FirmwareID FROM Request WHERE RQID=? AND ReceiverID=?
       └─> UPDATE Receiver SET FirmwareID=? WHERE ReceiverID=?
       └─> INSERT INTO ReceiverFirmwareHistory (ReceiverID, FirmwareID, StartDate)

7. Next lazy loader run (2 minutes later)
   └─> Firmware_GetSensorsToUpdate()
   └─> Compares Receiver.FirmwareID vs target
   └─> Sensor excluded (FirmwareID now matches)
```

### Critical Failure Points Where FirmwareID Could Be Wrong

**Point A: Lazy Loader Returns Wrong FileName** (VALIDATED)
- If `Firmware_GetSensorsToUpdate` joins incorrectly to FacilityFirmware or Part
- If `FacilityFirmware.FirmwareID` points to wrong firmware
- If `Part.DefaultFirmwareID` points to wrong firmware
- **Impact:** Wrong firmware file targeted for deployment

**Point B: FirmwareID Lookup Fails** (VALIDATED - `firmware_common.get_firmware_id()`)
```python
# If this query returns 0 rows:
SELECT FirmwareID FROM Firmware fw
INNER JOIN Part pt ON pt.PartID = fw.PartID
WHERE fw.FileName = '{firmware_file_name}'
AND pt.PartNumber = '{smpn}';

# Then: return_val = retVal[0]["FirmwareID"]  ← IndexError or None
```

**Causes:**
- FileName doesn't match any Firmware record (typo, case sensitivity)
- PartNumber doesn't match
- Firmware record was deleted after lazy loader ran but before request created
- **Result:** `firmware_id = None`, Request created with `FirmwareID = NULL`

**Point C: Request Record Created with NULL FirmwareID** (VALIDATED)
```sql
-- R__PROC_Request_AddRequest.sql:26-30
IF (inFirmwareID = 0) THEN
    SET @FirmwareID = NULL;
ELSE
    SET @FirmwareID = (SELECT FirmwareID FROM Firmware WHERE FirmwareID = inFirmwareID);
END IF;
```

If `inFirmwareID` is NULL, 0, or doesn't exist in Firmware table:
- **Result:** `Request.FirmwareID = NULL`

**Point D: Acknowledgement Lookup Fails** (VALIDATED)
```sql
-- R__PROC_Request_AcknowledgeRequest_v2.sql:299-305
SET localFirmwareID = (
    SELECT FirmwareID
    FROM Vero.Request
    WHERE RQID = inRQID
    AND ReceiverID = localReceiverID
    AND RequestTypeID = 6
);
```

**Causes:**
- RQID mismatch (clock skew, incorrect timestamp)
- ReceiverID mismatch (serial number lookup failed)
- Request record doesn't exist
- **Result:** `localFirmwareID = NULL`, then `UPDATE Receiver SET FirmwareID = NULL`

**Point E: Receiver.FirmwareVersion Never Updated** (VALIDATED)
- **Intentional design:** `Receiver.FirmwareVersion` is NOT updated for sensors
- Only `Receiver.FirmwareID` is updated
- Version string retrieved via FK join: `SELECT Version FROM Firmware WHERE FirmwareID = Receiver.FirmwareID`
- **This is not a bug** — it's the intended architecture

### Diagnostic Queries for "Already Updated" Bug

**Check if sensors have correct FirmwareID:**
```sql
SELECT
    r.ReceiverID,
    r.SerialNumber,
    r.FirmwareID AS CurrentFirmwareID,
    r.FirmwareVersion AS CurrentFirmwareVersionField,
    fw.Version AS CurrentFirmwareVersionFromFK,
    fw.FileName AS CurrentFirmwareFileName,
    p.DefaultFirmwareID AS PartDefaultFirmwareID,
    dfw.Version AS PartDefaultVersion,
    dfw.FileName AS PartDefaultFileName,
    ffw.FirmwareID AS FacilityOverrideFirmwareID,
    ffw_fw.Version AS FacilityOverrideVersion,
    ffw_fw.FileName AS FacilityOverrideFileName,
    CASE
        WHEN ffw.FirmwareID IS NOT NULL THEN ffw.FirmwareID
        ELSE p.DefaultFirmwareID
    END AS TargetFirmwareID,
    CASE
        WHEN ffw.FirmwareID IS NOT NULL AND ffw.FirmwareID <> r.FirmwareID THEN 'MISMATCH (Facility Override)'
        WHEN ffw.FirmwareID IS NULL AND p.DefaultFirmwareID <> r.FirmwareID THEN 'MISMATCH (Part Default)'
        ELSE 'MATCH'
    END AS Status
FROM Receiver r
INNER JOIN Part p ON p.PartID = r.PartID
INNER JOIN Firmware dfw ON dfw.FirmwareID = p.DefaultFirmwareID
LEFT JOIN Firmware fw ON fw.FirmwareID = r.FirmwareID
INNER JOIN MonitoringPoint_Receiver mpr ON mpr.ReceiverID = r.ReceiverID AND mpr.ActiveFlag = 1
INNER JOIN MonitoringPoint mp ON mp.MonitoringPointID = mpr.MonitoringPointID
INNER JOIN Machine m ON m.MachineID = mp.MachineID
INNER JOIN Line l ON l.LineID = m.LineID
LEFT JOIN FacilityFirmware ffw ON ffw.FacilityID = l.FacilityID AND ffw.PartID = p.PartID
LEFT JOIN Firmware ffw_fw ON ffw_fw.FirmwareID = ffw.FirmwareID
WHERE r.SerialNumber IN ('0012345', '0067890')  -- Problem sensors
ORDER BY r.SerialNumber;
```

**Check recent Request records:**
```sql
SELECT
    r.RequestID,
    r.RQID,
    FROM_UNIXTIME(r.RQID) AS RQIDTimestamp,
    r.ReceiverID,
    rx.SerialNumber AS ReceiverSerialNumber,
    r.FirmwareID AS RequestFirmwareID,
    fw.Version AS RequestFirmwareVersion,
    fw.FileName AS RequestFirmwareFileName,
    r.RequestStatusID,
    rs.RequestStatusName,
    r.RequestTypeID,
    rt.RequestTypeName,
    r.DateCreated,
    TIMESTAMPDIFF(SECOND, r.DateCreated, NOW()) AS SecondsAgo
FROM Request r
INNER JOIN Receiver rx ON rx.ReceiverID = r.ReceiverID
LEFT JOIN Firmware fw ON fw.FirmwareID = r.FirmwareID
INNER JOIN RequestStatus rs ON rs.RequestStatusID = r.RequestStatusID
INNER JOIN RequestType rt ON rt.RequestTypeID = r.RequestTypeID
WHERE rx.SerialNumber IN ('0012345', '0067890')
AND r.RequestTypeID = 6
ORDER BY r.DateCreated DESC
LIMIT 20;
```

**Check for NULL FirmwareID in recent requests:**
```sql
SELECT
    COUNT(*) AS CountWithNullFirmwareID,
    MIN(DateCreated) AS OldestNull,
    MAX(DateCreated) AS NewestNull
FROM Request
WHERE RequestTypeID = 6
AND FirmwareID IS NULL
AND DateCreated > DATE_SUB(NOW(), INTERVAL 7 DAY);
```

### Additional Code References (Jobs Repo)

**Lazy Loader:**
- `assetwatch-jobs/terraform/jobs/jobs_hardware/eventbridge.tf:31-57` — EventBridge schedule (every 2 minutes)
- `assetwatch-jobs/terraform/jobs/jobs_hardware/jobs-hardware/main.py:74-82` — Lazy loader invocation
- `assetwatch-jobs/terraform/jobs/jobs_hardware/jobs-hardware/hardware.py:32-72` — Lazy loader execution and Lambda invocation

**Request Processing:**
- `assetwatch-jobs/terraform/jobs/request_v2/request-sensor-firmware/main.py` — Request Lambda handler
- `assetwatch-jobs/terraform/jobs/request_v2/request-sensor-firmware/firmware_common.py` — FirmwareID lookup logic

**Acknowledgement:**
- `assetwatch-jobs/terraform/jobs/jobs_data_ingestion_firmware/jobs-data-ingestion-firmware/dataParser.py` — MQTT acknowledgement processor
- `assetwatch-jobs/mysql/db/procs/R__PROC_Request_AcknowledgeRequest_v2.sql` — Optimized acknowledgement stored procedure

### Unvalidated Assumptions

**ASSUMPTION 1:** Hub embedded firmware correctly downloads from S3 presigned URL, transfers to sensor via BLE, and reports success/failure via MQTT. *This logic is not in the repos examined — it lives on the physical hub device.*

**ASSUMPTION 2:** MQTT message format from hub matches exactly what `dataParser.py` expects. *The parser code exists but actual MQTT messages from hubs were not examined.*

**ASSUMPTION 3:** The `jobs_data_ingestion_firmware` service is the only path that processes firmware update confirmations. *No other MQTT processors were found that call Request_AcknowledgeRequest, but other services might exist.*

**ASSUMPTION 4:** Clock synchronization between lazy loader RQID generation (Unix timestamp) and acknowledgement lookup is reliable. *If clocks drift or timezones differ between services, RQID matching could fail.*
