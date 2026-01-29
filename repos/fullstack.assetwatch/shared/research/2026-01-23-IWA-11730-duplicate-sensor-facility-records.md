---
date: 2026-01-23T13:24:23-05:00
researcher: jwalker
git_commit: 1b7b250ae0999f06eaf6f8c3e4e038b07b1a7d86
branch: IWA-11730
repository: AssetWatch1/fullstack.assetwatch
topic: "Duplicate Sensor Facility Records Investigation"
tags: [research, duplicate-sensors, Facility_Receiver, MonitoringPoint_Receiver, data-integrity]
status: in_progress
last_updated: 2026-01-26
last_updated_by: jwalker
---

# Research: Duplicate Sensor Facility Records Investigation

**Date**: 2026-01-23T13:24:23-05:00
**Researcher**: jwalker
**Git Commit**: 1b7b250ae0999f06eaf6f8c3e4e038b07b1a7d86
**Branch**: IWA-11730
**Repository**: AssetWatch1/fullstack.assetwatch

## Research Question

Investigate sensors that appear in both `MonitoringPoint_Receiver` (with `ActiveFlag=1`) and `Facility_Receiver` tables simultaneously - a state that should not occur since a sensor should either be deployed at a customer site OR in inventory, not both.

## Summary

A sensor can exist in an invalid "dual assignment" state where it is:
1. Actively assigned to a monitoring point (`MonitoringPoint_Receiver.ActiveFlag = 1`)
2. AND also present in facility inventory (`Facility_Receiver` table)

This investigation documents queries to identify these duplicates and trace user activity that may have caused them.

## Key Tables

| Table | Purpose |
|-------|---------|
| `MonitoringPoint_Receiver` | Tracks sensors deployed at customer monitoring points |
| `Facility_Receiver` | Tracks sensors in inventory facilities |
| `Facility_ReceiverHistory` | Historical record of facility inventory movements |
| `UserPathLog` | Logs user navigation in the web app |
| `Customer` | Customer records (note: `ExternalCustomerID` is the UUID used in URLs) |

### Key Columns

**MonitoringPoint_Receiver:**
- `AssignedByUserID` - Who assigned the sensor to the monitoring point
- `RemovedByUserID` - Who removed the sensor from the monitoring point
- `ActiveFlag` - 1 if currently assigned, 0 if removed

**Facility_Receiver:**
- `UserID` - Who added the sensor to inventory

**Facility_ReceiverHistory:**
- `UserID` - Who originally created the record (not who removed it)
- `DateRemoved` - When the sensor was removed from this inventory location

## Investigation Queries

### Query 1: Find All Duplicate Sensor Records

This query returns sensors that exist in **both** tables simultaneously:

```sql
SELECT
    r.ReceiverID,
    r.SerialNumber,
    CONCAT(c_mp.CustomerName, ' - ', f_mp.FacilityName) AS MonitoringPoint_Facility,
    mpr.StartDate AS `MPR DateCreated`,
    CONCAT(c_fr.CustomerName, ' - ', f_fr.FacilityName) AS FacilityReceiver_Facility,
    fr.DateCreated AS `FR DateCreated`,
    fr.UserID AS `FR UserID`,
    CONCAT(u_fr.FirstName, ' ', u_fr.LastName) AS `FR UserName`
FROM MonitoringPoint_Receiver mpr
    INNER JOIN Receiver r ON r.ReceiverID = mpr.ReceiverID
    INNER JOIN MonitoringPoint mp ON mp.MonitoringPointID = mpr.MonitoringPointID
    INNER JOIN Machine m ON m.MachineID = mp.MachineID
    INNER JOIN Line l ON l.LineID = m.LineID
    INNER JOIN Facility f_mp ON f_mp.FacilityID = l.FacilityID
    INNER JOIN Customer c_mp ON c_mp.CustomerID = f_mp.CustomerID
    INNER JOIN Facility_Receiver fr ON fr.ReceiverID = mpr.ReceiverID
    INNER JOIN Facility f_fr ON f_fr.FacilityID = fr.FacilityID
    INNER JOIN Customer c_fr ON c_fr.CustomerID = f_fr.CustomerID
    LEFT JOIN Users u_fr ON u_fr.UserID = fr.UserID
WHERE mpr.ActiveFlag = 1
ORDER BY fr.DateCreated DESC;
```

**How it works:**
- The `INNER JOIN` between `MonitoringPoint_Receiver` and `Facility_Receiver` on `ReceiverID` only returns rows where the sensor exists in **both** tables
- `WHERE mpr.ActiveFlag = 1` ensures we only find sensors that are actively deployed (the problematic state)
- Results show both facility assignments side-by-side for comparison

### Query 2: Count of Duplicates

```sql
SELECT
    COUNT(DISTINCT mpr.ReceiverID) AS total_overlapping_receivers,
    COUNT(*) AS total_overlapping_assignments
FROM MonitoringPoint_Receiver mpr
    INNER JOIN Facility_Receiver fr ON mpr.ReceiverID = fr.ReceiverID
WHERE mpr.ActiveFlag = 1
    AND mpr.ReceiverID IS NOT NULL
    AND fr.ReceiverID IS NOT NULL;
```

## User Activity Tracing

### Investigated Incident: 2026-01-05

| Field | Value |
|-------|-------|
| **Duplicate Sensor** | ReceiverID 392262, Serial 8023716 |
| **Related Sensor** | ReceiverID 403814, Serial 8033519 |
| **User** | Lyes Mezreb (UserID 8786) |
| **FR DateCreated** | 2026-01-05 22:30:43 UTC |
| **Customer Being Worked On** | Balcan Plastics (ExternalCustomerID: `96ecba33-d027-4f78-98a5-791bee39345c`) |
| **Sensor's Actual Location** | La-Z-Boy - Dayton, TN (CustomerID 71) |

### UserPathLog Results

**Timeline around incident (UTC):**

| Time | Path | Modal | Notes |
|------|------|-------|-------|
| 22:29:21 | `/customers/.../facility-layout` | Update MonitoringPoints | |
| **22:30:36** | — | — | **← Sensor 403814 assigned to MP** |
| **22:30:43** | — | — | **← Sensor 392262 added to inventory (BUG)** |
| 22:37:37 | `/receivers/403814` | — | |
| 22:42:12 | `/customers/.../facility-layout` | Update MonitoringPoints | |

**Key Finding**: Both operations were performed by **the same user (Lyes Mezreb)** within **7 seconds**, confirming this is a single workflow issue in the **Update MonitoringPoints** modal.

### UserPathLog Investigation Queries

The `UserPathLog` table tracks user navigation in the web app:

| Column | Description |
|--------|-------------|
| `UserPathLogID` | Primary key |
| `UserID` | User who navigated |
| `PathURL` | URL path visited |
| `Tab` | Tab within the page |
| `Modal` | Modal that was open |
| `DateCreated` | Timestamp (UTC) |

#### Query 1: Activity around incident time (±1 hour)

```sql
SELECT
    UserPathLogID,
    UserID,
    PathURL,
    Tab,
    Modal,
    DateCreated
FROM UserPathLog
WHERE UserID = 8786
  AND DateCreated BETWEEN '2026-01-05 21:30:00' AND '2026-01-05 23:30:00'
ORDER BY DateCreated;
```

#### Query 2: Check for Track Inventory / Sensor Check activity

```sql
SELECT
    UserPathLogID,
    UserID,
    PathURL,
    Tab,
    Modal,
    DateCreated
FROM UserPathLog
WHERE UserID = 8786
  AND DateCreated BETWEEN '2026-01-05 00:00:00' AND '2026-01-06 00:00:00'
  AND (PathURL LIKE '%trackinventory%' OR PathURL LIKE '%inventory%' OR PathURL LIKE '%sensorcheck%')
ORDER BY DateCreated;
```

#### Query 3: All activity on the customer that day

```sql
SELECT
    UserPathLogID,
    PathURL,
    Tab,
    Modal,
    DateCreated
FROM UserPathLog
WHERE UserID = 8786
  AND DateCreated BETWEEN '2026-01-05 12:00:00' AND '2026-01-05 23:59:59'
  AND PathURL LIKE '%96ecba33-d027-4f78-98a5-791bee39345c%'
ORDER BY DateCreated;
```

### Two-Sensor Transaction Tracing Queries

These queries trace the relationship between the correctly-handled sensor (403814) and the incorrectly-added duplicate (392262).

#### Query 4: Check who assigned sensor to MonitoringPoint (use AssignedByUserID)

```sql
SELECT
    mpr.MonitoringPointReceiverID,
    mpr.ReceiverID,
    r.SerialNumber,
    mpr.StartDate,
    mpr.AssignedByUserID,
    CONCAT(u_assigned.FirstName, ' ', u_assigned.LastName) as AssignedByUserName,
    mpr.RemovedByUserID,
    CONCAT(u_removed.FirstName, ' ', u_removed.LastName) as RemovedByUserName,
    mp.MonitoringPointName,
    f.FacilityName,
    c.CustomerName
FROM MonitoringPoint_Receiver mpr
    INNER JOIN Receiver r ON r.ReceiverID = mpr.ReceiverID
    INNER JOIN MonitoringPoint mp ON mp.MonitoringPointID = mpr.MonitoringPointID
    INNER JOIN Machine m ON m.MachineID = mp.MachineID
    INNER JOIN Line l ON l.LineID = m.LineID
    INNER JOIN Facility f ON f.FacilityID = l.FacilityID
    INNER JOIN Customer c ON c.CustomerID = f.CustomerID
    LEFT JOIN Users u_assigned ON u_assigned.UserID = mpr.AssignedByUserID
    LEFT JOIN Users u_removed ON u_removed.UserID = mpr.RemovedByUserID
WHERE mpr.ReceiverID = 403814  -- The sensor being assigned to MP
  AND mpr.ActiveFlag = 1;
```

#### Query 5: Check Facility_ReceiverHistory for related sensor

```sql
SELECT
    frh.FacilityReceiverID,
    frh.ReceiverID,
    r.SerialNumber,
    frh.DateCreated,
    frh.DateRemoved,
    frh.UserID,
    CONCAT(u.FirstName, ' ', u.LastName) as OriginalCreatorName,
    f.FacilityName,
    c.CustomerName
FROM Facility_ReceiverHistory frh
    INNER JOIN Receiver r ON r.ReceiverID = frh.ReceiverID
    INNER JOIN Facility f ON f.FacilityID = frh.FacilityID
    INNER JOIN Customer c ON c.CustomerID = f.CustomerID
    LEFT JOIN Users u ON u.UserID = frh.UserID
WHERE frh.ReceiverID = 403814  -- The sensor that was in inventory
ORDER BY frh.DateRemoved DESC
LIMIT 5;
```

#### Query 6: Check who added the duplicate sensor to Facility_Receiver

```sql
SELECT
    fr.FacilityReceiverID,
    fr.ReceiverID,
    r.SerialNumber,
    fr.DateCreated,
    fr.UserID,
    CONCAT(u.FirstName, ' ', u.LastName) as UserName,
    f.FacilityName,
    c.CustomerName
FROM Facility_Receiver fr
    INNER JOIN Receiver r ON r.ReceiverID = fr.ReceiverID
    INNER JOIN Facility f ON f.FacilityID = fr.FacilityID
    INNER JOIN Customer c ON c.CustomerID = f.CustomerID
    LEFT JOIN Users u ON u.UserID = fr.UserID
WHERE fr.ReceiverID = 392262;  -- The duplicate sensor
```

#### Query 7: Check full history of duplicate sensor

```sql
SELECT
    frh.FacilityReceiverID,
    frh.ReceiverID,
    r.SerialNumber,
    frh.DateCreated,
    frh.DateRemoved,
    f.FacilityName,
    c.CustomerName
FROM Facility_ReceiverHistory frh
    INNER JOIN Receiver r ON r.ReceiverID = frh.ReceiverID
    INNER JOIN Facility f ON f.FacilityID = frh.FacilityID
    INNER JOIN Customer c ON c.CustomerID = f.CustomerID
WHERE frh.ReceiverID = 392262  -- The duplicate sensor
ORDER BY frh.DateCreated DESC;
```

### Key Paths to Look For

| Path | Description |
|------|-------------|
| `/trackinventory` | Track Inventory page - adds sensors to `Facility_Receiver` |
| `/inventory` | Inventory page |
| `/sensorcheck` | Sensor Check page - can move sensors to inventory |
| `/customers/.../sensors` | Customer sensors page |

### Key Modals to Look For

| Modal | Description | Bug Source? |
|-------|-------------|-------------|
| **`Update MonitoringPoints`** | Assign/remove sensors from monitoring points | **YES - Confirmed** |
| `Add Spare Sensor` | Adding to facility inventory | Not observed |
| `Add/Edit Monitoring Points` | Could involve sensor assignment | Not observed |
| `Update Asset` | Asset updates on facility layout | Not observed |

**Note**: If `UserPathLog` has no records for the user around the incident time, the action was likely performed via the **mobile app** (which may not log to this table) or via a **direct API call**.

**Finding**: Both investigated incidents (UserID 12155 on 2026-01-20 and UserID 8786 on 2026-01-05) were traced to the **Update MonitoringPoints** modal on the Facility Layout page.

## Historical Context

### Related Notes (from ~/repos/notes/)

#### 1. duplicate-sensor-bug/

**Location**: `~/repos/notes/duplicate-sensor-bug/`

Contains comprehensive investigation with SQL queries AND result data from September 2025:

**investigate_sensor_duplicates.sql** - Queries including:
- Facility comparison (same vs different facilities)
- Race condition detection (same-day assignments)
- Workflow direction analysis (which system assigned first)
- Removal reason tracking

**CSV Result Files** - Historical data showing actual duplicate occurrences:

| File | Description |
|------|-------------|
| `recreate_bug_before.csv` | State before fix attempt |
| `recreate_bug_after_88_and_129.csv` | State after removing sensors 88 and 129 |
| `investigate_sensor_duplicates_results_1-5.csv` | Multiple investigation runs |

**Key Example from Historical Data (September 2025):**

Sensor 83 (ReceiverID 43765) was in BOTH tables simultaneously:
- **MonitoringPoint_Receiver**: ActiveFlag=1, StartDate=2021-04-09, EndDate=NULL (still active!)
- **Facility_Receiver**: FacilityID=1192 "ART LUKE WALTERS INVENTORY RETURNING TO HQ", DateCreated=2025-09-09

This shows a sensor that was deployed at QTP1 facility on a monitoring point BUT also added to ART inventory - the exact bug pattern we're investigating

#### 2. moving-active-sensors/

**Location**: `~/repos/notes/moving-active-sensors/`

**current-app-flows.md** - Documents ALL entry points where sensors can be moved to inventory facilities:

**Stored Procedures That Insert Into Facility_Receiver:**

| Procedure | Purpose | Key Operations |
|-----------|---------|----------------|
| `Inventory_AddSensor` | Adding new sensors | Moves sensors to inventory, deactivates MPR |
| `Inventory_BulkMoveSensorsToInventoryFacility` | Bulk movement | Only PBSM sensors, deactivates MPR |
| `Receiver_RemoveReceiver` | Remove from MP | Deactivates MPR, moves to inventory |
| `FacilityReceiver_UpdateReceiverStatus` | Single sensor move | Deactivates MPR, archives FR to history |
| `FacilityReceiver_UpdateReceiverStatusAtFacility` | Bulk facility transfers | Updates existing FR or creates new |
| `WorkOrder_UpdateSensors` | Work order movements | Archives FR to history, creates new FR |

**API Endpoints:**

| Lambda | Method | Stored Procedure |
|--------|--------|------------------|
| Inventory | `addBulkSensorToInventory` | `Inventory_AddSensor` |
| Inventory | `bulkMoveSensorsToInventoryFacility` | `Inventory_BulkMoveSensorsToInventoryFacility` |
| Sensor | `removeReceiver` | `Receiver_RemoveReceiver` |
| Facilities | `updateReceiverStatus` | `FacilityReceiver_UpdateReceiverStatus` |

**Frontend Entry Points:**

| Component | Function | API Call |
|-----------|----------|----------|
| SensorCheck Page | `moveSensorsToInventory` | `bulkMoveSensorsToInventoryFacility` |
| MoveSensorsNextStepModal | `moveSensors` | `bulkMoveSensorsToInventoryFacility` |
| useRemoveAsset hook | `removeReceivers` | `removeReceiver` |
| Track Inventory Submit | `addSensorsMutation` | `addBulkSensorToInventory` |

**overlapping_receivers.sql** - Query to find sensors in both tables:
```sql
-- Find overlapping ReceiverIDs with detailed information
FROM MonitoringPoint_Receiver mpr
    INNER JOIN Facility_Receiver fr ON mpr.ReceiverID = fr.ReceiverID
WHERE mpr.ActiveFlag = 1
```

**duplicate_receiver_count.sql** - Count of receivers appearing multiple times in Facility_Receiver

#### 3. salesforce-duplicate-sensor-investigation/

Root cause analysis of a related duplicate issue in Salesforce sync:
- Multiple `MonitoringPoint_Receiver` records for the same sensor
- Date filter in query catches overlapping historical records
- Results in duplicate records sent to Salesforce API

### All Related Notes Files (~/repos/notes/)

Full list of files referencing `Facility_Receiver` or `MonitoringPoint_Receiver`:

| Directory | Files |
|-----------|-------|
| `duplicate-sensor-bug/` | `investigate_sensor_duplicates.sql`, 5 CSV result files |
| `moving-active-sensors/` | `current-app-flows.md`, `overlapping_receivers.sql`, `duplicate_receiver_count.sql` |
| `salesforce-duplicate-sensor-investigation/` | `README.md`, `analysis_results.md`, `reproduction_steps.md`, `investigate_duplicate_sensor_0046896.sql`, `demonstrate_duplicate_issue.sql` |
| `offline-sensors-discovery/` | Multiple SQL files for offline sensor queries |
| `facility-layout-export/` | Battle Creek facility layout queries |
| `sensor-status-troubleshooting/` | `sensor-status-by-hub-hotspot.sql` |

### Related Research in thoughts/shared/research/

- `2025-12-29-track-inventory-workflow.md` - Track Inventory workflow documentation
- `2026-01-05-track-inventory-page-functionality.md` - Track Inventory page functionality
- `2025-01-25-hub-hotspot-facility-transfer-flows.md` - Facility transfer flows

## Data Integrity Gap

The duplicate sensor bug stems from a **data integrity gap**: sensors can exist in both `MonitoringPoint_Receiver` (active assignment) and `Facility_Receiver` (inventory) simultaneously because:

1. No database constraint enforces mutual exclusivity
2. Stored procedures *should* deactivate one when creating the other
3. Race conditions or workflow gaps allow both to exist

## Investigation Results (2026-01-23)

### Current Duplicate Count

Query found **20+ duplicate records** currently in the database.

### Most Recent Duplicate (2026-01-05)

| Field | Value |
|-------|-------|
| **ReceiverID** | 392262 |
| **SerialNumber** | 8023716 |
| **Monitoring Point Location** | La-Z-Boy - Dayton, TN (CustomerID 71) |
| **MPR StartDate** | 2025-10-08 |
| **Facility Receiver Location** | ART LYES MEZREB INVENTORY RETURNING TO HQ |
| **FR DateCreated** | 2026-01-05 22:30:43 UTC |
| **UserID** | 8786 |
| **UserName** | Lyes Mezreb |

### UserPathLog Analysis (UserID 8786)

**Timeline Around Incident (2026-01-05 UTC):**

| Time (UTC) | Path | Modal | Notes |
|------------|------|-------|-------|
| 22:29:21 | `/customers/.../facility-layout` | **Update MonitoringPoints** | |
| **22:30:43** | — | — | **← FR DateCreated (duplicate created)** |
| 22:37:37 | `/receivers/403814` | — | |
| 22:42:12 | `/customers/.../facility-layout` | **Update MonitoringPoints** | |

**Key Observations:**
1. User was on **Facility Layout → Update MonitoringPoints** modal **82 seconds before** the duplicate was created
2. User was working on **Balcan Plastics** (CustomerID 321, UUID `96ecba33-d027-4f78-98a5-791bee39345c`)
3. Sensor is deployed at **La-Z-Boy - Dayton, TN** (CustomerID 71) - **completely unrelated customer**
4. **Sensor has NEVER been at Balcan Plastics** - only ever at La-Z-Boy since 2025-10-08
5. **NO activity** on Track Inventory (`/trackinventory`) or Sensor Check (`/sensorcheck`) pages
6. User had extensive activity with "Update MonitoringPoints" modal (30+ times that day)

**Balcan Plastics Facilities in Session:**
- FacilityID 1620: Pleasant Prairie, WI
- FacilityID 2216: Quebec, QC, LAV03
- FacilityID 2236: Montreal, QC - MTL1
- FacilityID 2237: Montreal, QC - MTL2

### Pattern Confirmation

This is the **SAME pattern** observed in the previous investigation (UserID 12155, 2026-01-20):
- Both incidents: **Facility Layout → Update MonitoringPoints** workflow
- Both incidents: User working on different customer than sensor's deployed location
- Both incidents: No Track Inventory or Sensor Check page activity

## Root Cause Analysis

### Two-Sensor Transaction Discovery

The duplicate was created as part of a **single operation by the same user** involving TWO sensors:

| Sensor | Serial | Time (UTC) | Operation | User | Result |
|--------|--------|------------|-----------|------|--------|
| **403814** | 8033519 | 22:30:36 | Assigned to MP "Gearbox Input ODE" at Balcan Plastics | Lyes Mezreb (8786) | ✅ Correct |
| **392262** | 8023716 | 22:30:43 | Added to user's inventory | Lyes Mezreb (8786) | ❌ BUG - Still active at La-Z-Boy |

**Confirmed via `MonitoringPoint_Receiver.AssignedByUserID`** - both operations performed by the same user within 7 seconds.

**Sensor 403814 was handled correctly:**
- Was in `Facility_Receiver` at Balcan Plastics (Quebec, QC, LAV03)
- Correctly moved to `MonitoringPoint_Receiver` (assigned to monitoring point)
- Properly removed from `Facility_Receiver`

**Sensor 392262 was incorrectly included:**
- Was (and still is) actively deployed at La-Z-Boy - Dayton, TN
- Has NO history at Balcan Plastics
- Got added to user's inventory as side effect of the same operation

### Root Cause Hypothesis (Refined)

The **Update MonitoringPoints** modal appears to perform a bulk operation that:
1. Correctly assigns sensor 403814 to a monitoring point
2. Simultaneously adds "spare" sensors to the user's "returning to HQ" inventory
3. **Sensor 392262 was incorrectly included in the "add to inventory" batch**

Possible causes:
1. **UI selection bug**: Wrong sensor selected in a multi-select interface
2. **Autocomplete/search bug**: User searched and wrong sensor was auto-selected
3. **Stored procedure bug**: Bulk operation catching incorrect ReceiverIDs
4. **Parameter passing bug**: Array of ReceiverIDs includes wrong ID

## Open Questions

1. ~~What user action caused the most recent duplicate?~~ **ANSWERED**: Facility Layout → Update MonitoringPoints modal
2. Is the mobile app logging to `UserPathLog`? (Appears YES based on this investigation)
3. Which stored procedure or API endpoint is failing to clean up the other table?
4. Should a database trigger enforce mutual exclusivity?
5. **NEW**: How does the Update MonitoringPoints modal allow referencing sensors from other customers?

## Next Steps

- [x] Run UserPathLog queries against production database
- [x] Identify the specific workflow that created the duplicate → **Facility Layout → Update MonitoringPoints**
- [x] **Trace the Update MonitoringPoints code path** to find where cleanup is missing
- [x] Examine the frontend component and API endpoint for this modal
- [ ] Query CloudWatch logs to see full request context
- [ ] Determine if this is a race condition or missing logic in the stored procedure
- [ ] Consider adding database trigger to enforce mutual exclusivity

## Code Path Analysis

### Complete Data Flow

```
Frontend: FacilityLayoutTab.tsx
    └─> handleBulkAddMPsModalClick() (line 556)
        └─> UpdateMonitoringPointModal.tsx
            └─> useMonitoringPointSubmit.ts hook
                └─> handleFormSubmit() (line 538)
                    ├─> addNewMP() → addMonitoringPoint() API
                    ├─> updateMP() → addMonitoringPoint() API
                    └─> removeMP() (line 449)
                        └─> updateSensorFacilityAndStatusAPI() (line 533)
```

### API Call Details

**Frontend** (`FacilityServices.ts:1052-1073`):
```typescript
export async function updateSensorFacilityAndStatusAPI(usmp: AssetMp) {
  const myInit = {
    body: {
      meth: "updateSensorFacilityAndStatus",
      mpid: usmp.mpid,    // MonitoringPointID
      ssn: usmp.ssn,      // Serial Number
      fid: usmp.fid,      // FacilityID (inventory destination)
      rstid: usmp.rstid,  // Receiver Status Type ID
      pid: usmp.pid,      // PartID
      rrtid: usmp.rrtid,  // Receiver Removal Type ID
    },
  };
  await API.post("apiVeroFacility", "/update", myInit);
}
```

**Lambda** (`lf-vero-prod-facilities/main.py:1301-1319`):
```python
elif meth == "updateSensorFacilityAndStatus":
    sql = (
        "CALL FacilityReceiver_UpdateReceiverStatus('"
        + str(jsonBody["mpid"]) + "','"
        + str(jsonBody["ssn"]) + "','"
        + str(jsonBody["fid"]) + "','"
        + str(jsonBody["rstid"]) + "','"
        + str(jsonBody["pid"]) + "',"
        + str(jsonBody["rrtid"]) + ",'"
        + cognito_id + "');"
    )
    retVal = db.mysql_write(sql, requestId, meth, cognito_id)
```

### Bug Location: Stored Procedure

**`FacilityReceiver_UpdateReceiverStatus`** (`mysql/db/procs/R__PROC_FacilityReceiver_UpdateReceiverStatus.sql`)

**Lines 39-53 - The problematic logic:**
```sql
IF(EXISTS(SELECT FacilityReceiverID FROM Facility_Receiver WHERE ReceiverID = localReceiverID)) THEN
    -- Archive existing record to history
    INSERT INTO Facility_ReceiverHistory ...
    DELETE FROM Facility_Receiver WHERE ReceiverID = localReceiverID;
    -- Create NEW record in Facility_Receiver
    INSERT INTO Facility_Receiver (...) values (localReceiverID, inFacilityID, ...);
ELSE
    IF(localReceiverID IS NOT NULL) THEN
        -- Create NEW record in Facility_Receiver
        INSERT INTO Facility_Receiver (...) values (localReceiverID, inFacilityID, ...);
    END IF;
END IF;
```

**The Bug**: This procedure **unconditionally inserts into `Facility_Receiver`** (lines 47 and 51) without checking if the sensor is currently active on a `MonitoringPoint_Receiver`:

1. ❌ Does NOT check `MonitoringPoint_Receiver.ActiveFlag = 1`
2. ❌ Does NOT deactivate the MPR record before inserting
3. ✅ Only updates `ReceiverRemovalTypeID` on MPR (line 33-35), but NOT `ActiveFlag` or `EndDate`

## CloudWatch Log Investigation

### Lambda Function & Log Group

**Note**: The codebase directory (`lf-vero-prod-facilities/`) differs from the deployed Lambda name. Terraform naming: `facilities-${env}-${branch}`.

| Environment | Lambda Function | Log Group |
|-------------|-----------------|-----------|
| **Dev (branch X)** | `facilities-dev-{branch}` | `/aws/lambda/facilities-dev-{branch}` |
| **Prod Master** | `facilities-prod-master` | `/aws/lambda/facilities-prod-master` |

**Deployment Configuration**:
- Terraform: `terraform/lambdas.tf:384` → `function_name = "facilities-${var.env}-${var.branch}"`
- API Gateway: `terraform/api-gateway.tf:555` → uses `api/api-vero-facility.yaml`
- OpenAPI: `api/api-vero-facility.yaml:164` → `/update` routes to `${get_lambda_arn}`

### Log Format

The `db_resources.py` module logs all database operations in this format:

**Success (line 230-231):**
```
sql=<{sql}>, db=<MAIN_DB_PROXY>, requestId=<{request_id}>, meth=<{meth}>, cognito_id=<{cognito_id}>, status=<success>, duration=<{duration}>
```

**Failure (line 236-237):**
```
sql=<{sql}>, db=<MAIN_DB_PROXY>, requestId=<{request_id}>, meth=<{meth}>, cognito_id=<{cognito_id}>, status=<fail>, reason=<{error}>, duration=<{duration}>
```

### Key Timestamps for Known Duplicates

| ReceiverID | Serial | FR DateCreated (UTC) | UserID | User Name |
|------------|--------|---------------------|--------|-----------|
| 392262 | 8023716 | **2026-01-05T22:30:43Z** | 8786 | Lyes Mezreb |

### CloudWatch Insights Queries

**Query 1: Search by method and time window**
```
fields @timestamp, @message
| filter @message like /updateSensorFacilityAndStatus/
| sort @timestamp asc
| limit 200
```
*Use time range: 2026-01-05 22:25:00 to 22:35:00 UTC*

**Query 2: Search by serial number**
```
fields @timestamp, @message
| filter @message like /8023716/
| sort @timestamp asc
| limit 100
```

**Query 3: Search by stored procedure name**
```
fields @timestamp, @message
| filter @message like /FacilityReceiver_UpdateReceiverStatus/
| sort @timestamp asc
| limit 200
```

**Query 4: Parse structured fields**
```
fields @timestamp, @message
| parse @message /meth=<(?<method>[^>]+)>.*sql=<(?<sql>[^>]+)>.*status=<(?<status>[^>]+)>/
| filter method = "updateSensorFacilityAndStatus"
| sort @timestamp asc
| limit 200
```

### AWS CLI Commands

**Prod environment (for 2026-01-05 incident):**
```bash
# Set time range around incident (22:30:43 UTC)
START_TIME=$(date -d "2026-01-05T22:25:00Z" +%s)000
END_TIME=$(date -d "2026-01-05T22:35:00Z" +%s)000

# Start query - search for the stored procedure call
aws logs start-query \
  --profile prod \
  --log-group-name "/aws/lambda/facilities-prod-master" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string 'fields @timestamp, @message | filter @message like /FacilityReceiver_UpdateReceiverStatus/ | sort @timestamp asc | limit 200'

# Get results (use query-id from above)
aws logs get-query-results --profile prod --query-id <query-id>
```

**Search by serial number:**
```bash
aws logs start-query \
  --profile prod \
  --log-group-name "/aws/lambda/facilities-prod-master" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string "fields @timestamp, @message | filter @message like /8023716/ | sort @timestamp asc | limit 100"
```

**Dev environment (adjust branch name):**
```bash
aws logs start-query \
  --profile dev \
  --log-group-name "/aws/lambda/facilities-dev-{branch}" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string 'fields @timestamp, @message | filter @message like /FacilityReceiver_UpdateReceiverStatus/ | sort @timestamp asc | limit 200'
```

## Troubleshooting Notes

### Lesson 1: Lambda Naming Convention

**Problem**: The codebase directory names (e.g., `lf-vero-prod-facilities/`) differ from the deployed Lambda function names.

**Solution**: Always trace through Terraform to find actual deployed names:
- Codebase: `lambdas/lf-vero-prod-facilities/`
- Terraform: `function_name = "facilities-${var.env}-${var.branch}"`
- **Deployed**: `facilities-prod-master`

**Deprecated Log Groups**: The old naming convention `/aws/lambda/lf-vero-prod-*` is deprecated (last logs Dec 2023). Always use the new naming.

### Lesson 2: Timestamp Considerations

- **UserPathLog timestamps**: Stored in UTC
- **Facility_Receiver.DateCreated**: Stored in UTC
- **CloudWatch timestamps**: Always use UTC with explicit `Z` suffix
- **AWS CLI time format**: Use milliseconds (multiply epoch seconds by 1000)

```bash
# Correct: explicit UTC with milliseconds
START_TIME=$(($(date -d "2026-01-05T22:25:00Z" +%s) * 1000))
```

### Lesson 3: Modal → Lambda Mapping

**Update MonitoringPoints modal** calls these Lambdas (from `useMonitoringPointSubmit.ts`):

| Operation | API Method | Lambda | Stored Procedure |
|-----------|------------|--------|------------------|
| Add MP with sensor | `addMonitoringPoint` | `monitoringpoint-prod-master` | `MonitoringPoint_AddMonitoringPoint` + `Receiver_AddReceiverDetail` |
| Add MP (from AW) | `addMonitoringPointFromAW` | `monitoringpoint-prod-master` | `MonitoringPoint_AddMonitoringPointFromAW` + `Receiver_AddReceiverDetail` |
| Remove sensor to inventory | `updateSensorFacilityAndStatus` | `facilities-prod-master` | `FacilityReceiver_UpdateReceiverStatus` |

**Key Finding**: When searching for the "add to inventory" operation, check **both** lambdas:
- `facilities-prod-master` - for direct inventory operations
- `monitoringpoint-prod-master` - for sensor assignment operations (which may trigger inventory changes)

### Lesson 4: Two-Sensor Operations

When investigating multi-sensor operations:
1. Sensor A assigned to MP → logs in **MonitoringPoint Lambda**
2. Sensor B added to inventory → logs in **Facilities Lambda**

Both operations may occur within the same user session but through **different Lambdas**.

## CloudWatch Investigation Results (2026-01-23)

### Investigation Goal

Find CloudWatch logs for the 2026-01-05 incident to understand:
1. What API call created the `Facility_Receiver` record for sensor 392262
2. What operations the user performed to trigger the "two-sensor" interaction
3. Full request context to help reproduce the bug

### Search Attempts

#### Attempt 1: Search by Serial Numbers

**Queries:**
- MonitoringPoint Lambda: `filter @message like /8033519/ or @message like /403814/`
- Facilities Lambda: `filter @message like /8023716/ or @message like /392262/`

**Time Range:** 2026-01-05 22:25:00 - 22:40:00 UTC

**Results:** ❌ Zero matches in both Lambdas

#### Attempt 2: Search by Stored Procedure Names

**Queries:**
- MonitoringPoint Lambda: `filter @message like /addMonitoringPoint/ and @message like /Receiver_AddReceiverDetail/`
- Facilities Lambda: `filter @message like /FacilityReceiver_UpdateReceiverStatus/`

**Time Range:** 2026-01-05 22:25:00 - 22:40:00 UTC

**Results:** ❌ Zero matches for these specific procedures

#### Attempt 3: Verify Logs Exist (Sample Any SQL)

**Query:** `filter @message like /sql=/`

**Results:** ✅ Logs DO exist in this time window:
- **MonitoringPoint Lambda**: 76 matching records - mostly `getThreshold`, `getMonitoringPointDetails`, `updateRpm`
- **Facilities Lambda**: 2,625 matching records - mostly `getMachineAssetAlerts`, `getFacilityServiceList`

### Key Finding: Missing Expected Logs

**The Mystery:** Database records show:
- Sensor 403814 assigned to MP at **22:30:36 UTC** (by UserID 8786)
- Sensor 392262 added to inventory at **22:30:43 UTC** (by UserID 8786)

But CloudWatch shows **NO logs** for:
- `addMonitoringPointFromAW` or `Receiver_AddReceiverDetail` (for MP assignment)
- `updateSensorFacilityAndStatus` or `FacilityReceiver_UpdateReceiverStatus` (for inventory add)

### Possible Explanations

1. **Different code path**: The operation may go through a Lambda we haven't checked
2. **Database timezone mismatch**: The `DateCreated` timestamps may not be in UTC
3. **Different API method**: The operation may use a different method name than expected
4. **Mobile app**: If user was on mobile, it might use different API endpoints

### Next Steps to Try

1. [ ] **HIGH PRIORITY**: Test timezone hypothesis - search CloudWatch for Jan 6, 03:00-04:00 UTC
2. [x] Search for the user's cognito_id in CloudWatch logs around incident time → **Found activity but NOT at incident time**
3. [ ] Check if there are other Lambdas that insert into `Facility_Receiver` (inventory, sensor)
4. [x] Search all Lambda log groups for the serial numbers with wider time range → **No results**
5. [x] Query the database to find the cognito_id for UserID 8786 → **`d16b9d27-096d-4586-af06-f7c6774b393c`**
6. [ ] Verify `Facility_Receiver.DateCreated` timezone by comparing with a known recent operation

### CloudWatch Search Best Practices (Lesson 5)

**Step 1: Get the User's Cognito ID**
```sql
SELECT UserID, CognitoID, FirstName, LastName, Email
FROM Users WHERE UserID = <user_id>;
```

**Step 2: Search by Cognito ID (NOT serial number)**

The log format includes `cognito_id=<uuid>`, so searching by cognito_id is more reliable than searching by serial number (which may or may not appear in the SQL string).

**UserID 8786 (Lyes Mezreb)**: `d16b9d27-096d-4586-af06-f7c6774b393c`

**Step 3: Use a Wide Time Range First**

Start with a 3-day range to confirm logs exist, then narrow down:

```bash
# 3-day range to find all activity
START_TIME=$(($(date -d "2026-01-04T00:00:00Z" +%s) * 1000))
END_TIME=$(($(date -d "2026-01-07T00:00:00Z" +%s) * 1000))

aws logs start-query \
  --profile prod \
  --log-group-name "/aws/lambda/facilities-prod-master" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string "fields @timestamp, @message | filter @message like /d16b9d27-096d-4586-af06-f7c6774b393c/ | sort @timestamp asc | limit 500"
```

**Step 4: Filter by Method Name**

Once you have results, filter by the specific method:
```
filter @message like /<cognito_id>/ and @message like /updateSensorFacilityAndStatus/
```

**Key Finding (2026-01-23):**
- 3-day search (Jan 4-7) returned **many results** for this cognito_id
- BUT: 20-minute window around incident time (22:25-22:45 UTC) returned **zero results**
- This suggests: **Database timestamps may NOT be in UTC** or operation used different Lambda

### Lesson 6: CloudWatch Insights Result Limits

**Problem**: CloudWatch Insights returns a **maximum of 200 results** per query. When searching broad time ranges with active users, you'll hit this limit and only see partial results.

**Example from Jan 5 Investigation:**
- Full day search: 642 records matched, but only 200 returned
- Results sorted ascending: first 200 records = 14:12 - 17:38 UTC
- Incident at 22:30 UTC was NOT in those 200 results

**Solutions:**
1. **Narrow time windows**: Search specific hours instead of full days
2. **Use `| sort @timestamp desc`** to see most recent first
3. **Add method filters**: `filter @message like /cognito_id/ and @message like /specificMethod/`
4. **Increase limit** (max 10,000): `| limit 1000`

**Example - Targeted Search:**
```bash
# Search specific hour with higher limit
aws logs start-query \
  --profile prod \
  --log-group-name "/aws/lambda/facilities-prod-master" \
  --start-time $(($(date -d "2026-01-05T22:00:00Z" +%s) * 1000)) \
  --end-time $(($(date -d "2026-01-05T23:00:00Z" +%s) * 1000)) \
  --query-string "fields @timestamp, @message | filter @message like /d16b9d27-096d-4586-af06-f7c6774b393c/ | sort @timestamp asc | limit 1000"
```

### Detailed Investigation Results (2026-01-23)

#### User Activity Timeline (CloudWatch Logs)

| Time Range (UTC) | Lambda | Records Found | Notes |
|------------------|--------|---------------|-------|
| Jan 5, 14:12 - 17:38 | Facilities | 200+ | First 200 records (limit hit) |
| Jan 5, 17:29 - 19:31 | Facilities | 200+ | Continued activity |
| Jan 5, 19:00 - 20:04 | Facilities | 348 matched | Last confirmed activity before gap |
| **Jan 5, 22:25 - 22:45** | **Facilities** | **0** | **⚠️ NO LOGS during incident window** |
| **Jan 5, 22:25 - 22:45** | **MonitoringPoint** | **0** | **⚠️ NO LOGS during incident window** |

#### The Timestamp Mystery

**Database says:**
- `Facility_Receiver.DateCreated` = `2026-01-05 22:30:43`
- `UserPathLog.DateCreated` = `2026-01-05 22:29:21` (Update MonitoringPoints modal)
- `MonitoringPoint_Receiver.StartDate` = `2026-01-05 22:30:36` (sensor 403814)

**CloudWatch shows:**
- User's last confirmed activity: ~20:04 UTC
- **Gap of 2+ hours** with no API activity
- Then activity resumes (based on UserPathLog)

**Hypothesis: Database Timestamps May Be Local Time (EST)**
- If `22:30:43` is actually **EST (UTC-5)**, the real UTC time would be **03:30:43 on Jan 6**
- This would explain why searching Jan 5 22:25-22:45 UTC returns nothing
- **Next step**: Search Jan 6, 03:00-04:00 UTC to test this hypothesis

#### Lambdas Still To Check

| Lambda | Checked? | Notes |
|--------|----------|-------|
| `facilities-prod-master` | ✅ | No activity at incident time |
| `monitoringpoint-prod-master` | ✅ | No activity at incident time |
| `inventory-prod-master` | ❌ | May handle inventory operations |
| `sensor-prod-master` | ❌ | May handle sensor operations |

### Next Session Checklist

1. [ ] **Test timezone hypothesis**: Search CloudWatch for Jan 6, 03:00-04:00 UTC
2. [ ] **Search other Lambdas**: inventory, sensor for this cognito_id
3. [ ] **Search ANY `updateSensorFacilityAndStatus`** calls at 22:30 (regardless of user)
4. [ ] **Verify `Facility_Receiver.DateCreated` timezone**: Check if MySQL uses UTC or local time
5. [ ] **Compare with another known record**: Find a recent operation where we know the actual time

## Bug Reproduction (2026-01-26)

### Confirmed Steps to Reproduce

Successfully reproduced in dev environment on 2026-01-24.

**Test Data:**
| Sensor | ReceiverID | Serial | Initial Location | Role in Test |
|--------|------------|--------|------------------|--------------|
| Victim sensor | 222539 | 8000017 | Active on MP at "710-008 Test Facility" | Sensor accidentally entered, should be BLOCKED |
| Intended sensor | 222572 | 8000015 | Spare at Jackson Walker facility | Sensor user intends to use |

**Reproduction Steps:**

1. **Verify initial state:**
   - Check that **8000017** is assigned to an active MP (at facility "710-008 Test Facility")
   - Check that **8000015** is a spare in Jackson Walker facility

2. **Perform the accidental entry:**
   - Go to **Jackson Walker** facility
   - Open **Add/Edit MP** modal for an Asset
   - Add **8000017** to an MP (wrong sensor - from different facility)
   - System shows warning: "This sensor is at 710-008 Test Facility, are you sure?"
   - Click "Yes" (simulating accidental confirmation)

3. **Correct the mistake:**
   - Realize you typed the wrong serial number
   - Type **8000015** (the correct sensor)
   - Click Save

4. **Verify the bug:**
   - Check that **8000017** is now in your returning inventory facility ❌ **BUG - should be BLOCKED**
   - Check that **8000017** is still on its original MP in "710-008 Test Facility" with `ActiveFlag=1`
   - **Result:** Sensor 8000017 now exists in BOTH `MonitoringPoint_Receiver` (active) AND `Facility_Receiver` (inventory)

### Database Evidence (2026-01-24 Test)

**Sensor 8000017 (ReceiverID 222539) after reproduction:**

| Table | Status | Details |
|-------|--------|---------|
| `MonitoringPoint_Receiver` | `ActiveFlag=1` ✅ | Still on "SAFT 5" at "710-008 Test Facility" |
| `Facility_Receiver` | **Record exists** ❌ | Added to "ENG Jackson Walker Inventory" at 02:45:39 UTC |

**Timeline from UserPathLog (UserID 12092):**

| Time (UTC) | Event |
|------------|-------|
| 02:44:59 | User in "Update MonitoringPoints" modal at Jackson Walker |
| 02:45:38 | Sensor 8000015 correctly assigned to MP "Motor DE" |
| 02:45:39 | Sensor 8000017 incorrectly added to inventory **(THE BUG)** |

### Root Cause Confirmed

The bug occurs because:

1. User accidentally enters a sensor from a **different facility**
2. System warns but allows the operation if user confirms
3. User corrects their mistake by entering the correct sensor
4. The accidentally-entered sensor gets added to `removedSensors` list
5. On submit, `updateSensorFacilityStatus()` sends the wrong sensor to inventory
6. `FacilityReceiver_UpdateReceiverStatus` stored procedure:
   - Looks for MPR at the **current facility's MP** (not found - sensor is at different facility)
   - **Still inserts** into `Facility_Receiver` anyway
   - **Never deactivates** the sensor's actual MPR at the other facility

### Required Fix

The stored procedure should **BLOCK** the `Facility_Receiver` insert when:
- The sensor has an active MPR (`ActiveFlag=1`)
- That MPR is at a **different facility** than the one being worked on

This prevents "ghost" inventory records for sensors that are physically deployed elsewhere.
