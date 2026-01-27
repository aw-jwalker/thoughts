# IWA-13768: Clear Hub Schedules When Removing/Moving Hub from Facility

## Overview

When a hub is removed from a facility in AssetWatch but not physically unplugged, it retains its old schedule settings. If the customer later updates schedule parameters for their facility, this "orphaned" hub doesn't receive those updates and continues taking readings with stale/wrong parameters (different frequency, sampling rate, etc.). This causes mixed data on sensor graphs.

**Solution**: Handle hub schedules appropriately when moving/removing hubs:

- If moving to a new facility as **active** → clear old schedules AND sync new facility's schedules
- If moving with **non-active status** → just clear old schedules

## Current State Analysis

### The Problem

1. Hub is removed from Facility A in AssetWatch (but physically remains connected)
2. Hub retains its schedule cache with Facility A's parameters
3. Customer updates schedule parameters for Facility A
4. Other hubs at Facility A get the new schedule
5. The "orphaned" hub continues using old parameters
6. Sensor data shows mixed readings with different parameters

### Root Cause

The existing `sync_hub_schedules()` function is only called when:

- `changeHubStatus` with status = "1" (active)
- `addHub` with status = "1" (active)

It is **NOT** called in:

- `removeHubAndChangeStatus` (single hub removal) - for ANY status
- `bulkMoveHubsToInventoryFacility` (bulk hub move) - no status parameter

This means hubs being removed/moved never have their schedules cleared or updated.

### Hub Status Reference

| TransponderStatusID | TransponderStatusName |
| ------------------- | --------------------- |
| 1                   | Active                |
| 2                   | Spare                 |
| 3                   | Removed               |
| 4                   | In Transit            |
| 5                   | Ready to Install      |

### Existing Infrastructure

- **Job**: `jobs-request-hub-clear-schedules-{ENV}-{BRANCH}`
- **Functions in `lf-vero-prod-hub/main.py`**:
  - `sync_hub_schedules(FacilityID, HubSerialNumber, HubPartNumber)` - clears + syncs new schedules (1.5s sleep)
  - `create_clear_schedules_content(HubSerialNumber, HubPartNumber, rqid)` - creates payload

## Desired End State

When a hub is removed/moved from a facility:

| Destination      | Status               | Behavior                                                    |
| ---------------- | -------------------- | ----------------------------------------------------------- |
| Any facility     | Active (1)           | Clear old schedules + sync destination facility's schedules |
| Any facility     | Non-active (2,3,4,5) | Clear old schedules only                                    |
| Inventory (bulk) | N/A                  | Clear old schedules only (inventory has no schedules)       |

### Verification

- Remove a hub from Facility A to Facility B with status "active" → hub gets Facility B's schedules
- Remove a hub from Facility A to inventory with status "removed" → hub has no schedules
- Bulk move hubs to inventory → all hubs have schedules cleared

## What We're NOT Doing

- NOT modifying the stored procedures (MySQL can't invoke Lambdas)
- NOT modifying frontend (backend is more reliable)
- NOT clearing schedules for Gen3 hubs (not supported per existing pattern)
- NOT failing the removal if schedule handling fails (fire-and-forget pattern)

## Implementation Approach

**Single hub removal (`removeHubAndChangeStatus`)**: Status-aware logic

- Active status → reuse existing `sync_hub_schedules()` to clear + push new facility's schedules
- Non-active status → new `clear_hub_schedules()` to just clear (no sync needed)

**Bulk hub move (`bulkMoveHubsToInventoryFacility`)**: Always clear only

- Inventory facilities have no schedules to push
- Use new `clear_hub_schedules()` for each hub

---

## Phase 1: Add Schedule Handling to Single Hub Removal

### Overview

Add status-aware schedule handling to the `removeHubAndChangeStatus` method in `lf-vero-prod-hub`.

### Changes Required

#### 1. Add `clear_hub_schedules()` helper function

**File**: `lambdas/lf-vero-prod-hub/main.py`
**Location**: After `create_clear_schedules_content()` function (around line 110)

```python
def clear_hub_schedules(HubSerialNumber, HubPartNumber):
    """
    Clear schedules from a hub without syncing new ones.
    Used when removing a hub with non-active status.
    Fire-and-forget - does not wait for completion.
    """
    lambda_client = boto3.client("lambda")
    rqid = int(time.time())
    clear_schedules_content = create_clear_schedules_content(
        HubSerialNumber=HubSerialNumber, HubPartNumber=HubPartNumber, rqid=rqid
    )
    print(f"Clearing schedules for hub {HubPartNumber}_{HubSerialNumber}")
    response = lambda_client.invoke(
        FunctionName=jobs_request_hub_clear_schedules,
        Payload=json.dumps(clear_schedules_content),
        InvocationType="Event",  # Async, returns immediately
    )
    print(f"Clear schedules invoke response: {response['ResponseMetadata']['HTTPStatusCode']}")
```

#### 2. Add helper to get hub info from TransponderID

**File**: `lambdas/lf-vero-prod-hub/main.py`
**Location**: After the new `clear_hub_schedules()` function

```python
def get_hub_info_for_schedule_handling(transponder_id):
    """
    Get hub serial number and part number needed for schedule handling.
    Returns (serial_number, part_number) tuple, or (None, None) if not found or Gen3.
    """
    query = f"""
        SELECT t.SerialNumber, p.PartNumber
        FROM Transponder t
        JOIN Part p ON t.PartID = p.PartID
        WHERE t.TransponderID = {transponder_id}
    """
    result = db.mysql_read(query, "", "get_hub_info_for_schedule_handling", "system")

    if not result or len(result) == 0:
        print(f"No hub found for TransponderID {transponder_id}")
        return None, None

    serial_number = result[0].get("SerialNumber")
    part_number = result[0].get("PartNumber")

    # Skip Gen3 hubs (part numbers starting with "710-003")
    if part_number and part_number.startswith("710-003"):
        print(f"Skipping schedule handling for Gen3 hub {part_number}_{serial_number}")
        return None, None

    return serial_number, part_number
```

#### 3. Modify `removeHubAndChangeStatus` method

**File**: `lambdas/lf-vero-prod-hub/main.py`
**Location**: Lines 902-930

**Current code** (lines 902-930):

```python
elif meth == "removeHubAndChangeStatus":
    hubId = jsonBody.get("hubId")
    facilityId = jsonBody.get("facilityId")
    # ... parameter extraction ...

    retVal = db.mysql_call_proc(
        "Transponder_RemoveHubAndChangeFacility",
        args,
        requestId,
        cognito_id,
        allow_write=True,
    )
```

**Modified code**:

```python
elif meth == "removeHubAndChangeStatus":
    hubId = jsonBody.get("hubId")
    facilityId = jsonBody.get("facilityId")
    hubStatusId = jsonBody.get("hubStatusId")
    removalReasonTypeId = jsonBody.get("removalReasonTypeId")
    enclosureId = jsonBody.get("enclosureId", "NULL")
    enclosureHotspotId = jsonBody.get("enclosureHotspotId", "NULL")
    enclosureHotspotStatusId = jsonBody.get("enclosureHotspotStatusId", "NULL")
    groupName = jsonBody.get("groupName", "")

    # Get hub info for schedule handling before removal
    hub_serial, hub_part = get_hub_info_for_schedule_handling(hubId)

    args = (
        hubId,
        facilityId,
        hubStatusId,
        removalReasonTypeId,
        enclosureId,
        enclosureHotspotId,
        enclosureHotspotStatusId,
        groupName,
        cognito_id,
    )

    retVal = db.mysql_call_proc(
        "Transponder_RemoveHubAndChangeFacility",
        args,
        requestId,
        cognito_id,
        allow_write=True,
    )

    # Handle hub schedules after successful DB update
    if "error" not in retVal and hub_serial and hub_part:
        try:
            if hubStatusId == "1":
                # Active hub moving to new facility - clear and sync destination's schedules
                sync_hub_schedules(
                    FacilityID=facilityId,
                    HubSerialNumber=hub_serial,
                    HubPartNumber=hub_part,
                )
            else:
                # Non-active hub - just clear schedules (fire-and-forget)
                clear_hub_schedules(hub_serial, hub_part)
        except Exception as e:
            print(f"Warning: Failed to handle schedules for hub {hub_part}_{hub_serial}: {e}")
            # Don't fail the removal - schedule handling is best-effort
```

### Success Criteria

#### Automated Verification:

- [ ] Lambda deploys successfully
- [x] Existing unit tests pass
- [x] No Python syntax errors

#### Manual Verification:

- [ ] Remove hub from Facility A to Facility B with status "active" → hub gets Facility B's schedules
- [ ] Remove hub from Facility A to inventory with status "removed" → schedules cleared
- [ ] Check CloudWatch logs for appropriate schedule handling messages
- [ ] Verify hub removal completes successfully (no regression)

---

## Phase 2: Add Clear Schedules to Bulk Hub Move

### Overview

Add schedule clearing to the `bulkMoveHubsToInventoryFacility` method in `lf-vero-prod-inventory`.

Since bulk moves are specifically to **inventory facilities** (which have no schedules), we only need to clear schedules - no syncing required.

### Changes Required

#### 1. Add imports and Lambda function name

**File**: `lambdas/lf-vero-prod-inventory/main.py`
**Location**: Top of file with other imports/constants

```python
import time
import boto3

ENV_VAR = os.environ["ENV_VAR"]
ENV_BRANCH = os.environ["ENV_BRANCH"]

jobs_request_hub_clear_schedules = (
    f"jobs-request-hub-clear-schedules-{ENV_VAR}-{ENV_BRANCH}"
)
```

#### 2. Add helper functions

**File**: `lambdas/lf-vero-prod-inventory/main.py`
**Location**: After imports, before main handler

```python
def create_clear_schedules_content(HubSerialNumber, HubPartNumber, rqid):
    """Create payload for clear schedules Lambda."""
    clear_schedules_content = {
        "RequestType": "ClearSchedules",
        "Hub": str(HubPartNumber) + "_" + str(HubSerialNumber),
        "User": "e3ea0b52-21db-45bc-8716-220d9209d14e",
        "RQID": rqid,
    }
    return {"body": json.dumps(clear_schedules_content)}


def clear_hub_schedules(HubSerialNumber, HubPartNumber):
    """
    Clear schedules from a hub without syncing new ones.
    Fire-and-forget - does not wait for completion.
    """
    lambda_client = boto3.client("lambda")
    rqid = int(time.time())
    clear_schedules_content = create_clear_schedules_content(
        HubSerialNumber=HubSerialNumber, HubPartNumber=HubPartNumber, rqid=rqid
    )
    print(f"Clearing schedules for hub {HubPartNumber}_{HubSerialNumber}")
    response = lambda_client.invoke(
        FunctionName=jobs_request_hub_clear_schedules,
        Payload=json.dumps(clear_schedules_content),
        InvocationType="Event",  # Async, returns immediately
    )
    print(f"Clear schedules invoke response: {response['ResponseMetadata']['HTTPStatusCode']}")


def get_hub_part_numbers_for_serials(serial_number_list):
    """
    Get part numbers for a list of hub serial numbers.
    Returns dict mapping serial_number -> part_number.
    Excludes Gen3 hubs (710-003*).
    """
    if not serial_number_list:
        return {}

    # Parse comma-separated list
    serials = [s.strip() for s in serial_number_list.split(",") if s.strip()]
    if not serials:
        return {}

    # Build IN clause
    serial_in = ",".join([f"'{s}'" for s in serials])

    query = f"""
        SELECT t.SerialNumber, p.PartNumber
        FROM Transponder t
        JOIN Part p ON t.PartID = p.PartID
        WHERE t.SerialNumber IN ({serial_in})
    """
    result = db.mysql_read(query, "", "get_hub_part_numbers_for_serials", "system")

    # Build mapping, excluding Gen3
    mapping = {}
    for row in result:
        serial = row.get("SerialNumber")
        part = row.get("PartNumber")
        if serial and part and not part.startswith("710-003"):
            mapping[serial] = part
        elif part and part.startswith("710-003"):
            print(f"Skipping schedule clear for Gen3 hub {part}_{serial}")

    return mapping
```

#### 3. Modify `bulkMoveHubsToInventoryFacility` method

**File**: `lambdas/lf-vero-prod-inventory/main.py`
**Location**: Lines 267-273

**Current code**:

```python
elif meth == "bulkMoveHubsToInventoryFacility":
    args = (
        str(jsonBody["ssnlist"]),
        str(jsonBody["fid"]),
        cognito_id,
    )
    retVal = db.mysql_call_proc("Inventory_BulkMoveHubsToInventoryFacility", args, requestId, cognito_id, allow_write=True)
```

**Modified code**:

```python
elif meth == "bulkMoveHubsToInventoryFacility":
    serial_number_list = str(jsonBody["ssnlist"])

    # Get part numbers for schedule clearing before move
    hub_part_mapping = get_hub_part_numbers_for_serials(serial_number_list)

    args = (
        serial_number_list,
        str(jsonBody["fid"]),
        cognito_id,
    )
    retVal = db.mysql_call_proc("Inventory_BulkMoveHubsToInventoryFacility", args, requestId, cognito_id, allow_write=True)

    # Clear schedules only after successful DB move (fire-and-forget)
    if "error" not in retVal:
        for serial, part in hub_part_mapping.items():
            try:
                clear_hub_schedules(serial, part)
            except Exception as e:
                print(f"Warning: Failed to clear schedules for hub {part}_{serial}: {e}")
                # Don't fail the bulk move - schedule clearing is best-effort
```

### Success Criteria

#### Automated Verification:

- [ ] Lambda deploys successfully
- [x] Existing unit tests pass
- [x] No Python syntax errors

#### Manual Verification:

- [ ] Bulk move multiple hubs using the Hub Check page
- [ ] Check CloudWatch logs for `lf-vero-prod-inventory` - should see "Clearing schedules for hub" messages for each hub
- [ ] Check CloudWatch logs for `jobs-request-hub-clear-schedules` - should see multiple invocations
- [ ] Verify bulk move completes successfully (no regression)
- [ ] Verify performance is acceptable (should be near-instant due to async invocations)

---

## Phase 3: Add IAM Permissions (if needed)

### Overview

The inventory Lambda may need IAM permissions to invoke the clear schedules Lambda.

### Changes Required

#### 1. Check existing IAM policy

**File**: `terraform/lambda-iam-roles.tf`

Search for `lf-vero-prod-inventory` IAM role and verify it has permission to invoke `jobs-request-hub-clear-schedules-*`.

If not present, add:

```hcl
# In the inventory Lambda's IAM policy
{
  Effect = "Allow"
  Action = ["lambda:InvokeFunction"]
  Resource = [
    "arn:aws:lambda:us-east-2:${local.account_id}:function:jobs-request-hub-clear-schedules-${var.env}-${var.branch}"
  ]
}
```

### Success Criteria

#### Automated Verification:

- [x] Terraform plan shows expected changes (or no changes if permission exists)
- [ ] Terraform apply succeeds

#### Manual Verification:

- [ ] Bulk move operation doesn't fail with permission errors

---

## Testing Strategy

### Test Scenarios

| Scenario                                         | Expected Behavior                                                      |
| ------------------------------------------------ | ---------------------------------------------------------------------- |
| Remove hub: Facility A → Facility B (active)     | `sync_hub_schedules` called, hub gets Facility B's schedules           |
| Remove hub: Facility A → Inventory (active)      | `sync_hub_schedules` called, hub has no schedules (inventory has none) |
| Remove hub: Facility A → Inventory (removed)     | `clear_hub_schedules` called, hub has no schedules                     |
| Remove hub: Facility A → Facility B (in transit) | `clear_hub_schedules` called, hub has no schedules                     |
| Bulk move: Multiple hubs → Inventory             | `clear_hub_schedules` called for each non-Gen3 hub                     |
| Remove Gen3 hub                                  | No schedule handling (skipped)                                         |

### Unit Tests

- Mock the Lambda client and verify correct function is called based on status
- Test `get_hub_info_for_schedule_handling()` returns correct values
- Test Gen3 hub detection and skipping
- Test `get_hub_part_numbers_for_serials()` with various inputs

### Integration Tests

1. **Live-to-live facility move (active)**:
   - Move hub from Facility A to Facility B with status "active"
   - Verify `sync_hub_schedules` is called
   - Verify hub gets Facility B's schedules

2. **Live-to-inventory move (non-active)**:
   - Move hub from customer facility to inventory with status "removed"
   - Verify `clear_hub_schedules` is called
   - Verify hub has no schedules

3. **Bulk move to inventory**:
   - Move 5+ hubs to inventory
   - Verify `clear_hub_schedules` called for each non-Gen3 hub
   - Verify performance is acceptable

4. **Gen3 handling**:
   - Remove/move Gen3 hub
   - Verify schedule handling is NOT invoked

5. **Error handling**:
   - Simulate schedule handling failure
   - Verify hub removal/move still succeeds

### Manual Testing Steps

1. Remove a single hub from customer facility to another customer facility with status "active"
2. Verify hub stops using old facility's schedules
3. Verify hub starts using new facility's schedules
4. Remove a hub to inventory with status "removed"
5. Verify schedules are cleared
6. Bulk move 3+ hubs using Hub Check page
7. Check CloudWatch logs for clear schedules invocations

## Performance Considerations

- **Single hub removal (active)**: ~1.5s latency from `sync_hub_schedules` (acceptable for single operations)
- **Single hub removal (non-active)**: Near-instant from async `clear_hub_schedules`
- **Bulk move**: Near-instant for all hubs (async invocations, no waiting)
- **No database impact**: Schedule handling happens via Lambda, additional DB query is lightweight

## Migration Notes

- No database migration required
- No frontend changes required
- Changes are additive - existing functionality unchanged
- Rollback: Remove the schedule handling code if issues arise

## References

- Original ticket: IWA-13768
- Related research: `thoughts/shared/research/2026-01-12-sensor-schedule-system-comprehensive.md`
- Hub removal flow: `thoughts/shared/research/2025-01-25-hub-hotspot-facility-transfer-flows.md`
- Existing functions: `lambdas/lf-vero-prod-hub/main.py:51-109`

---

## Diagnostic Queries: Identify Hubs in Bad State

These queries help identify hubs that are reading sensors from facilities they're not assigned to.

**Key insight:** The `Receiver.LastTransponderID` field is updated on every reading, so we can use pure MySQL to find mismatches between:
- Hub's assigned facility (`Transponder.FacilityID`)
- Sensor's assigned facility (via `MonitoringPoint` → `Machine` → `Line` → `Facility`)

### Query 1: Bad-state hubs grouped by hub facility

Shows which facilities have hubs that are reading sensors from OTHER facilities.

**Important**: Must use `Facility_Transponder.ActiveFlag = 1` to get the hub's current facility assignment (not `Transponder.FacilityID` directly).

```sql
SELECT
    hub_f.FacilityID AS HubFacilityID,
    hub_f.FacilityName AS HubFacility,
    hub_fs.FacilityStatusID AS HubFacilityStatusID,
    hub_fs.FacilityStatusName AS HubFacilityStatus,
    COUNT(DISTINCT t.TransponderID) AS BadStateHubCount,
    COUNT(DISTINCT r.ReceiverID) AS SensorsBeingReadWrongly,
    COUNT(DISTINCT sensor_f.FacilityID) AS DistinctSensorFacilities
FROM Receiver r
JOIN Transponder t ON t.TransponderID = r.LastTransponderID
JOIN Facility_Transponder ft ON ft.TransponderID = t.TransponderID AND ft.ActiveFlag = 1
JOIN Facility hub_f ON hub_f.FacilityID = ft.FacilityID
JOIN FacilityStatus hub_fs ON hub_fs.FacilityStatusID = hub_f.FacilityStatusID
JOIN MonitoringPoint_Receiver mpr ON mpr.ReceiverID = r.ReceiverID AND mpr.ActiveFlag = 1
JOIN MonitoringPoint mp ON mp.MonitoringPointID = mpr.MonitoringPointID
JOIN Machine m ON m.MachineID = mp.MachineID
JOIN Line l ON l.LineID = m.LineID
JOIN Facility sensor_f ON sensor_f.FacilityID = l.FacilityID
WHERE ft.FacilityID != sensor_f.FacilityID
  AND r.LastReadingDate > DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY hub_f.FacilityID, hub_f.FacilityName, hub_fs.FacilityStatusID, hub_fs.FacilityStatusName
ORDER BY BadStateHubCount DESC
LIMIT 50;
```

#### Results (2026-01-14)

| HubFacility | Status | BadStateHubCount | SensorsAffected | DistinctFacilities |
|-------------|--------|------------------|-----------------|-------------------|
| DO NOT RENAME - Firmware Updater | Inv-Development | 12 | 36 | 2 |
| CSR JONATHAN HART INVENTORY | Inventory | 10 | 84 | 9 |
| Missing-Customer Liable | Inv-Unknown | 6 | 27 | 6 |
| Installations/Expansions | Inv-Good | 6 | 26 | 2 |
| ART BEN PARSONS INVENTORY RETURNING TO HQ | Inventory | 4 | 20 | 1 |
| CSR SARAH SCHICK INVENTORY RETURNING TO HQ | Inventory | 3 | 25 | 3 |
| CSR JULLY KIPRONO INVENTORY RETURNING TO HQ | Inventory | 3 | 46 | 3 |
| CSR EMILY HALL INVENTORY RETURNING TO HQ | Inventory | 3 | 37 | 3 |

**Key "RETURNING TO HQ" facilities** (the target use case for IWA-13768):
- Total of ~25 hubs across various technician inventory facilities
- Reading sensors from customer facilities they were removed from
- Confirms the problem: hubs moved to inventory retain schedules and continue reading

### Query 2: Drill down on a specific inventory facility

Shows which customer facilities are affected by bad-state hubs in a specific inventory facility.
Replace `3124` with the HubFacilityID you want to investigate (e.g., ART BEN PARSONS = 3124).

```sql
SELECT
    sensor_f.FacilityID AS SensorFacilityID,
    sensor_f.FacilityName AS SensorFacility,
    sensor_fs.FacilityStatusName AS SensorFacilityStatus,
    c.CustomerName,
    COUNT(DISTINCT t.TransponderID) AS BadHubCount,
    COUNT(DISTINCT r.ReceiverID) AS SensorCount,
    MAX(r.LastReadingDate) AS MostRecentReading
FROM Receiver r
JOIN Transponder t ON t.TransponderID = r.LastTransponderID
JOIN Facility_Transponder ft ON ft.TransponderID = t.TransponderID AND ft.ActiveFlag = 1
JOIN Facility hub_f ON hub_f.FacilityID = ft.FacilityID
JOIN MonitoringPoint_Receiver mpr ON mpr.ReceiverID = r.ReceiverID AND mpr.ActiveFlag = 1
JOIN MonitoringPoint mp ON mp.MonitoringPointID = mpr.MonitoringPointID
JOIN Machine m ON m.MachineID = mp.MachineID
JOIN Line l ON l.LineID = m.LineID
JOIN Facility sensor_f ON sensor_f.FacilityID = l.FacilityID
JOIN FacilityStatus sensor_fs ON sensor_fs.FacilityStatusID = sensor_f.FacilityStatusID
JOIN Customer c ON c.CustomerID = sensor_f.CustomerID
WHERE ft.FacilityID = 3124  -- Change this to investigate different inventory facilities
  AND ft.FacilityID != sensor_f.FacilityID
  AND r.LastReadingDate > DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY sensor_f.FacilityID, sensor_f.FacilityName, sensor_fs.FacilityStatusName, c.CustomerName
ORDER BY SensorCount DESC
LIMIT 30;
```

### Query 3: Hub details for a specific inventory facility

Shows individual hubs in an inventory facility that are reading sensors from other facilities.
Includes when the hub was moved to the inventory facility.

```sql
SELECT
    t.TransponderID,
    t.SerialNumber AS HubSerial,
    p.PartNumber AS HubPartNumber,
    t.LastReadingDate AS HubLastReading,
    ft.StartDate AS MovedToInventoryDate,
    DATEDIFF(NOW(), ft.StartDate) AS DaysInInventory,
    COUNT(DISTINCT r.ReceiverID) AS SensorsBeingRead,
    COUNT(DISTINCT sensor_f.FacilityID) AS DistinctCustomerFacilities
FROM Transponder t
JOIN Part p ON p.PartID = t.PartID
JOIN Facility_Transponder ft ON ft.TransponderID = t.TransponderID AND ft.ActiveFlag = 1
JOIN Receiver r ON r.LastTransponderID = t.TransponderID
JOIN MonitoringPoint_Receiver mpr ON mpr.ReceiverID = r.ReceiverID AND mpr.ActiveFlag = 1
JOIN MonitoringPoint mp ON mp.MonitoringPointID = mpr.MonitoringPointID
JOIN Machine m ON m.MachineID = mp.MachineID
JOIN Line l ON l.LineID = m.LineID
JOIN Facility sensor_f ON sensor_f.FacilityID = l.FacilityID
WHERE ft.FacilityID = 3124  -- Change this to investigate different inventory facilities
  AND ft.FacilityID != sensor_f.FacilityID
  AND r.LastReadingDate > DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY t.TransponderID, t.SerialNumber, p.PartNumber, t.LastReadingDate, ft.StartDate
ORDER BY SensorsBeingRead DESC
LIMIT 50;
```
