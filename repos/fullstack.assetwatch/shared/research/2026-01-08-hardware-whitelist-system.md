---
date: 2026-01-08T11:36:39-05:00
researcher: Jackson Walker
git_commit: 388a82789530c737ce21a6f8835db261ac801e82
branch: dev
repository: fullstack.assetwatch
topic: "Hardware Whitelist System for QA Environments"
tags: [research, codebase, qa, whitelist, sensors, hubs, hotspots, hardware, timestream, netcloud, iot, s3]
status: complete
last_updated: 2026-01-08
last_updated_by: Jackson Walker
last_updated_note: "Added comprehensive hotspot/cradlepoint operations documentation with MySQL vs NetCloud distinction"
---

# Research: Hardware Whitelist System for QA Environments

**Date**: 2026-01-08T11:36:39-05:00
**Researcher**: Jackson Walker
**Git Commit**: 388a82789530c737ce21a6f8835db261ac801e82
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question

Explain how the hardware whitelist (sensors, hubs, hotspots) works. Understand why the whitelist is necessary, what is special about whitelisted hardware, how they are handled by the backend and frontend, the complete list of whitelisted devices, and how to add to the whitelist.

## Summary

The hardware whitelist system is a **QA environment protection mechanism** that restricts operations on physical hardware (sensors, hubs, and hotspots) to a predefined set of approved devices. This prevents accidental modifications to production hardware when testing in QA environments.

**Key Points:**
- Whitelists are **only enforced in non-production environments** (QA, dev, localhost)
- Three separate whitelists exist: sensors (14 devices), hubs (8 devices), and hotspots (6 MAC addresses)
- Both **frontend and backend** have independent whitelist implementations for defense-in-depth
- Whitelist checks are **hardcoded** in source code (no database tables)
- To add a device, you must update **3-4 files** depending on device type

**⚠️ Critical Understanding:**
- **NOT all "database operations" work without whitelist** - Many operations that appear to be simple CRUD (like "add hotspot to facility") actually call external APIs (NetCloud, IoT, Timestream) and **will fail** for non-whitelisted devices
- For hotspots specifically: `addBulkFacilityCradlepoints` and `removeCradlepoint` are NOT MySQL-only operations - they call NetCloud API and require whitelist validation

---

## Why the Whitelist is Necessary

### Problem Statement
AssetWatch manages physical IoT hardware (sensors, hubs, hotspots) deployed at customer facilities. Operations like:
- Invoking sensors to collect data
- Scheduling sensor measurements
- Assigning/removing hubs and hotspots to facilities
- Sending firmware updates

...can affect **real production hardware** if accidentally executed in the wrong environment.

### Solution
The whitelist ensures that in QA/test environments, only **designated QA hardware** can be operated on. This provides:

1. **Protection of production devices**: Prevents test operations from affecting live customer hardware
2. **Controlled testing**: Ensures QA team uses known, available test hardware
3. **Defense-in-depth**: Both frontend and backend validate, preventing bypass

### What Makes Whitelisted Hardware Special
- **Dedicated QA equipment**: These are physical devices set aside specifically for testing
- **Not deployed to customers**: They exist in test facilities or the office
- **Known good state**: QA team maintains these devices for consistent test results

---

## Whitelist Validation Architecture

Understanding **where** validation happens is critical for security and debugging.

### Validation Layers by Device Type

```
                    ┌─────────────────────────────────────────────────────────────┐
                    │                    REQUEST FLOW                             │
                    └─────────────────────────────────────────────────────────────┘
                                              │
                                              ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  LAYER 1: Frontend (fullstack.assetwatch)                                       │
│  ────────────────────────────────────────                                       │
│  CheckQA.ts validates ALL device types before API call                          │
│                                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                              │
│  │   Sensors   │  │    Hubs     │  │  Hotspots   │                              │
│  │      ✅     │  │      ✅     │  │      ✅     │                              │
│  └─────────────┘  └─────────────┘  └─────────────┘                              │
└─────────────────────────────────────────────────────────────────────────────────┘
                                              │
                                              ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  LAYER 2: API Lambdas (fullstack.assetwatch/lambdas/)                           │
│  ────────────────────────────────────────────────────                           │
│  Backend validation for sensors and hotspots ONLY                               │
│                                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                              │
│  │   Sensors   │  │    Hubs     │  │  Hotspots   │                              │
│  │      ✅     │  │      ❌     │  │      ✅     │                              │
│  │ lf-vero-    │  │ lf-vero-    │  │ lf-vero-    │                              │
│  │ prod-sensor │  │ prod-hub    │  │ prod-       │                              │
│  │             │  │ NO WHITELIST│  │ cradlepoint │                              │
│  └─────────────┘  └─────────────┘  └─────────────┘                              │
└─────────────────────────────────────────────────────────────────────────────────┘
                                              │
                                              ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  LAYER 3: Jobs Lambdas (assetwatch-jobs/terraform/jobs/)                        │
│  ───────────────────────────────────────────────────────                        │
│  Request processing with Terraform-injected whitelists                          │
│                                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                              │
│  │   Sensors   │  │    Hubs     │  │  Hotspots   │                              │
│  │      ✅     │  │      ✅     │  │      ❌     │                              │
│  │ request-    │  │ request-    │  │ (not in     │                              │
│  │ invoke,     │  │ hub-wifi,   │  │  jobs repo) │                              │
│  │ schedule    │  │ diagnostic  │  │             │                              │
│  └─────────────┘  └─────────────┘  └─────────────┘                              │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Validation Matrix

| Device Type | Frontend (CheckQA.ts) | API Lambda (fullstack) | Jobs Lambda (assetwatch-jobs) |
|-------------|----------------------|------------------------|------------------------------|
| **Sensors** | ✅ `CheckQA()` | ✅ `lf-vero-prod-sensor` | ✅ `request-invoke`, `request-schedule` |
| **Hubs** | ✅ `CheckQAHub()` | ❌ **NO VALIDATION** | ✅ `request-hub-*` lambdas |
| **Hotspots** | ✅ `checkQAHotspotList()` | ✅ `lf-vero-prod-cradlepoint` | ❌ N/A (handled in fullstack) |
| **Facilities** | ❌ None | ✅ `lf-vero-prod-file` | ✅ `jobs-schedule-optimizer` |

### Security Implications

**Hub Validation Gap in fullstack.assetwatch**:
- The `lf-vero-prod-hub` lambda has **NO backend whitelist**
- If frontend validation is bypassed (e.g., direct API call), the hub lambda will execute
- Protection comes from `assetwatch-jobs` when it processes the request
- This means the hub API will accept the request, but the actual command won't execute on non-whitelisted hubs

**Defense-in-Depth Status**:
- **Sensors**: ✅ Triple validation (frontend + API lambda + jobs lambda)
- **Hotspots**: ✅ Double validation (frontend + API lambda)
- **Hubs**: ⚠️ Single layer gap - API lambda has no validation, relies on jobs layer
- **Facilities**: ✅ Double validation (API lambda + jobs lambda, no frontend)

---

## Data Systems: MySQL vs External Systems

Understanding **which operations work without whitelist** requires understanding the different data systems involved.

### System Architecture Overview

Each environment (dev, QA, prod, feature branches) has:
- **Its own MySQL Aurora database** - isolated per environment
- **Shared or cross-account access** to external systems that store real device data

**⚠️ IMPORTANT**: While MySQL is isolated, many API operations that appear to be simple CRUD operations actually make calls to external systems (NetCloud, AWS IoT, Timestream). These operations will **fail or behave differently** for non-whitelisted devices.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         QA/Dev Environment                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────┐     ┌──────────────────────────────────────────────┐  │
│  │  MySQL Aurora    │     │           External Systems                    │  │
│  │  (Isolated DB)   │     │                                              │  │
│  ├──────────────────┤     │  ┌────────────┐  ┌────────────┐              │  │
│  │ ✓ Pure MySQL ops │     │  │ Timestream │  │ NetCloud   │              │  │
│  │   work for any   │     │  │ (Sensors)  │  │ (Hotspots) │              │  │
│  │   device         │     │  ├────────────┤  ├────────────┤              │  │
│  │                  │     │  │ Whitelist  │  │ Whitelist  │              │  │
│  │ ⚠️ BUT many ops  │     │  │ Required   │  │ Required   │              │  │
│  │   call external  │     │  └────────────┘  └────────────┘              │  │
│  │   systems too!   │     │                                              │  │
│  └──────────────────┘     │  ┌────────────┐  ┌────────────┐              │  │
│                           │  │ AWS IoT    │  │ S3 Buckets │              │  │
│                           │  │ (Hubs)     │  │ (Files)    │              │  │
│                           │  ├────────────┤  ├────────────┤              │  │
│                           │  │ Shared     │  │ Whitelist  │              │  │
│                           │  │ Endpoint   │  │ Required   │              │  │
│                           │  └────────────┘  └────────────┘              │  │
│                           └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Operations That Work WITHOUT Whitelist (MySQL-Only)

These operations **only** touch the isolated MySQL Aurora database and work for **any** device:

| Operation | Description | Why No Whitelist Needed |
|-----------|-------------|------------------------|
| **View device lists** | List sensors, hubs, hotspots | Reads from `CradlepointDevice`, `Transponder` tables |
| **Check device availability** | Verify if device is already assigned | MySQL query only |
| **View device history** | Historical assignment, status changes | Stored in MySQL |
| **View facility hardware** | List hardware at a facility | MySQL query |
| **Update device notes** | Add location notes | MySQL update to `Facility_CradlepointDevice` |
| **Update device status** | Change hardware status in DB | MySQL update only (no external call) |
| **View hotspot groups** | List available NetCloud groups | Reads from cached `CradlepointDevice_Group` table |
| **Work order management** | Create/edit work orders, link hardware | All in MySQL |

**⚠️ CAUTION**: The following operations **appear** to be simple CRUD but actually call external systems:

| Operation | Appears To Be | Actually Does |
|-----------|---------------|---------------|
| **Add hotspot to facility** | MySQL insert | Calls NetCloud API to update device group |
| **Remove hotspot from facility** | MySQL delete | Calls NetCloud API to clear group assignment |
| **Invoke sensor** | Simple API call | Sends command through AWS IoT to physical device |
| **Schedule sensor** | MySQL insert | Creates schedule AND triggers physical device |

### Operations That REQUIRE Whitelist (External Systems)

These operations interact with systems outside MySQL:

#### 1. Timestream Database (Sensor Data)

**What it stores**: Vibration readings, temperature data, electrical measurements, spectrum insights

**Whitelist behavior**:
- **Whitelisted sensors** → Query QA Timestream tables (`vibration_sensor-{env}-{branch}`)
- **Non-whitelisted sensors** → Cross-account role assumption to query **production** Timestream

```python
# From lf-vero-prod-sensor/main.py
if ENV_VAR != "prod" and sensor in valid_qa_sensors:
    # Use QA Timestream (isolated test data)
    client = boto3.client("timestream-query")
else:
    # Assume role to production Timestream (real sensor data)
    sts_connection.assume_role(
        RoleArn="arn:aws:iam::975740733715:role/qa-timestream-access-role"
    )
```

| Operation | Whitelisted Sensor | Non-Whitelisted Sensor |
|-----------|-------------------|------------------------|
| View vibration trends | QA Timestream (test data) | Prod Timestream (real data) |
| View temperature data | QA Timestream | Prod Timestream |
| View spectrum insights | QA Timestream | Prod Timestream |
| **Invoke sensor** | ✓ Works (collects to QA) | ✗ Blocked by frontend |
| **Schedule sensor** | ✓ Works | ✗ Blocked by frontend |

**Key insight**: Non-whitelisted sensors can still **view** production data in QA, but **write operations** (invoke, schedule) are blocked by frontend validation.

#### 2. NetCloud API (Cradlepoint Hotspots) - DETAILED

**What it does**: Manages hotspot device configuration, group assignments, firmware updates via Cradlepoint's cloud platform.

**API Endpoint**: `https://www.cradlepointecm.com/api/v2/`

**Backend Lambda**: `lambdas/lf-vero-prod-cradlepoint/main.py`

##### Whitelist Validation Logic

The backend performs whitelist validation at lines 418-491:

```python
# Line 418-491 in main.py
if ENV_VAR != "prod":
    # For single MAC operations (removeCradlepoint)
    if meth == "removeCradlepoint":
        if mac_address not in valid_qa_cradlepoint_mac_addresses:
            execute_qa_request = False

    # For bulk MAC operations (ALL MACs must be whitelisted)
    elif meth in ["addBulkCradlepoints", "updateNetcloudCradlepointFacility", "addBulkFacilityCradlepoints"]:
        mac_list = set(mac_addresses)
        if not mac_list.issubset(set(valid_qa_cradlepoint_mac_addresses)):
            execute_qa_request = False
```

**Key behavior**: For bulk operations, if **ANY** MAC address is not whitelisted, the **ENTIRE** operation fails.

##### Complete Operations Classification

###### MySQL-Only Operations (Work for ANY Hotspot)

| Method | Stored Procedure | What It Does | Line Numbers |
|--------|------------------|--------------|--------------|
| `getCradlepointStats` | `Cradlepoint_GetCradlepointDevices` | List hotspot devices from DB | 498-506 |
| `checkCradlepointAvailability` | `Cradlepoint_CheckBulkAvailability` | Check if MACs are already assigned | 508-515 |
| `checkActiveCradlepointWorkOrder` | `Cradlepoint_CheckAvailabilityWorkOrder` | Check work order conflicts | 517-528 |
| `getCradlepointNotes` | `Cradlepoint_GetNotes` | Read location notes | 530-532 |
| `getHubHotspotWithEnclosureInfo` | `Enclosure_GetHubHotspotWithEnclosureInfo` | Get enclosure details | 534-542 |
| `getHotspotGroups` | `Cradlepoint_GetGroups` | Read cached group list | 611-622 |
| `getFacilityCradlepointStatus` | Direct SQL | Read assignment status | 996-998 |
| `addCradlepointNotes` | `Cradlepoint_UpdateNotes` | Update location notes | 1028-1041 |
| `updateCradlepointStatus` | `FacilityCradepointDevice_Assign` | Update status in DB only | 1093-1111 |
| `cpEnclosureUpdateFacility` | `Enclosure_UpdateEnclosureFacility` | Update enclosure assignment | 975-994 |

###### NetCloud Operations REQUIRING Whitelist

| Method | Whitelist Check | NetCloud API Calls | MySQL Calls | Line Numbers |
|--------|-----------------|-------------------|-------------|--------------|
| `removeCradlepoint` | Single MAC (line 435-439) | GET router, PUT to clear group | `Cradlepoint_RemoveCradlepoint` | 549-609 |
| `addBulkCradlepoints` | ALL MACs (line 441-461) | GET router, PUT to set group | `Cradlepoint_AddBulkCradlepointWithFundingProject` | 763-859 |
| `addBulkFacilityCradlepoints` | ALL MACs (line 463-484) | GET router, PUT to set group | `Cradlepoint_AddCradlepoint` | 861-973 |
| `updateNetcloudCradlepointFacility` | ALL MACs (line 441-461) | GET router, PUT to update group | None (NetCloud only) | 1043-1091 |

###### NetCloud Operations WITHOUT Whitelist Check

| Method | Why No Whitelist | What It Does | Line Numbers |
|--------|------------------|--------------|--------------|
| `createHotspotGroups` | No MAC involved | Creates groups in NetCloud | 624-637 |
| `updateHotspotGroups` | No MAC involved | Updates group WiFi config | 639-652 |
| `getCradlepointNetMetrics` | Read-only | Fetches network metrics from NetCloud | 1000-1026 |

##### Detailed Operation Flows

###### Adding a Hotspot to Facility (`addBulkFacilityCradlepoints`)

```
Frontend                    Backend Lambda                NetCloud API              MySQL
   │                              │                            │                      │
   │  POST /cradlepoint           │                            │                      │
   │  meth=addBulkFacilityCradlepoints                         │                      │
   │  mac_addresses=[...]         │                            │                      │
   │─────────────────────────────>│                            │                      │
   │                              │                            │                      │
   │                              │ [QA ENV CHECK]             │                      │
   │                              │ Are ALL MACs whitelisted?  │                      │
   │                              │                            │                      │
   │                              │── NO ──────────────────────│──────────────────────│
   │<─────────────────────────────│ 422: "MAC address(es) not  │                      │
   │                              │      approved for QA"      │                      │
   │                              │                            │                      │
   │                              │── YES ─────────────────────│                      │
   │                              │                            │                      │
   │                              │ For each MAC:              │                      │
   │                              │─────────────────────────────>                     │
   │                              │ GET /routers/?mac={mac}    │                      │
   │                              │<─────────────────────────────                     │
   │                              │ {cpid, current_group, ...} │                      │
   │                              │                            │                      │
   │                              │─────────────────────────────>                     │
   │                              │ PUT /routers/{cpid}/       │                      │
   │                              │ {group: new_group_url,     │                      │
   │                              │  custom1: ext_facility_id} │                      │
   │                              │<─────────────────────────────                     │
   │                              │                            │                      │
   │                              │─────────────────────────────>                     │
   │                              │ GET /routers/?mac={mac}    │                      │
   │                              │ (verify update)            │                      │
   │                              │<─────────────────────────────                     │
   │                              │                            │                      │
   │                              │────────────────────────────────────────────────────>
   │                              │                            │  Cradlepoint_AddCradlepoint
   │                              │                            │  (insert/update DB record)
   │                              │<────────────────────────────────────────────────────
   │                              │                            │                      │
   │<─────────────────────────────│                            │                      │
   │  200: Success                │                            │                      │
```

###### Removing a Hotspot (`removeCradlepoint`)

```
1. Whitelist check (single MAC)
2. GET /routers/?mac={mac} - fetch current state
3. PUT /routers/{cpid}/ - clear group and custom1 (ext facility ID)
4. GET /routers/?mac={mac} - verify update
5. Call Cradlepoint_RemoveCradlepoint stored procedure
```

##### Error Responses

**Non-whitelisted MAC (HTTP 422)**:
```json
{
  "error": "MAC address(es) not approved for QA environment",
  "message": "The following MAC addresses are not in the QA whitelist: 00:30:44:XX:XX:XX",
  "valid_qa_macs": ["00:30:44:5E:5C:FC", "00:30:44:8C:E5:8C", "00:30:44:B4:92:A3", "00:30:44:B4:92:6B", "00:30:44:B4:93:E7", "00:30:44:48:C1:AC"]
}
```

**Hotspot not found in NetCloud (HTTP 404)**:
```json
{
  "error": "No Cradlepoint data found or Cradlepoint is unlisted in Netcloud"
}
```
This occurs when:
- MAC address is not registered in NetCloud
- Device was deleted from NetCloud
- MAC address format is incorrect

**NetCloud API error (varies)**:
```json
{
  "error": "Failed to update cradlepoint in NetCloud: {error_details}"
}
```

##### CradlepointDevice_Group Table (Lookup Table)

The `CradlepointDevice_Group` table is a **lookup table** that caches available NetCloud groups for the UI dropdown. It is **NOT** linked to individual devices.

**Source**: `mysql/db/table_change_scripts/V20251121_222840__IWA-14010_Add_CradlepointDevice_Group_Table.sql`

| Column | Type | Description |
|--------|------|-------------|
| `CradlepointDeviceGroupID` | INT (PK) | Primary key, auto-increment |
| `GroupID` | INT | NetCloud Group ID (the ID returned by NetCloud API) |
| `Name` | VARCHAR(65) | Name of the group (e.g., "CustomerName Facility (IBR200)") |
| `ActiveFlag` | BIT(1) | Whether group is active (1=active, 0=inactive) |
| `URL` | VARCHAR(100) | Full NetCloud API URL for the group |
| `ProductID` | INT (FK) | Foreign key to `Product` table (IBR200=49, S400=105) |
| `DateCreated` | TIMESTAMP(3) | Timestamp when record was created |
| `DateUpdated` | TIMESTAMP(3) | Timestamp when record was last updated |

##### Device-to-Group Relationship (IMPORTANT)

**⚠️ There is NO foreign key relationship between `CradlepointDevice` and `CradlepointDevice_Group`.**

```
┌─────────────────────────────────┐          ┌─────────────────────────────────┐
│     CradlepointDevice           │          │   CradlepointDevice_Group       │
├─────────────────────────────────┤          ├─────────────────────────────────┤
│ CradlepointDeviceID (PK)        │          │ CradlepointDeviceGroupID (PK)   │
│ MAC                             │          │ GroupID (NetCloud ID)           │
│ SerialNumber                    │          │ Name                            │
│ GroupName VARCHAR(200) ─────────┼── NO FK ─┼─► (implicit string match only)  │
│ ...                             │          │ URL                             │
└─────────────────────────────────┘          │ ProductID (FK → Product)        │
                                             └─────────────────────────────────┘
```

**How the relationship actually works:**

| System | What It Stores | Source of Truth |
|--------|----------------|-----------------|
| **NetCloud API** | Device's actual group assignment | ✅ **YES** |
| `CradlepointDevice.GroupName` | Cached group name (VARCHAR string) | No - cached copy |
| `CradlepointDevice_Group` | List of available groups for UI | No - lookup table |

**Implications:**
1. Changing `CradlepointDevice.GroupName` in MySQL does **NOT** change the device's actual group in NetCloud
2. The `CradlepointDevice_Group` table is only used for `getHotspotGroups` to populate UI dropdowns
3. When a device is assigned to a facility, the Lambda:
   - Calls NetCloud API to update the device's group (source of truth)
   - Updates `CradlepointDevice.GroupName` with the new group name string
   - Does NOT reference `CradlepointDevice_Group` table

**⚠️ Sync Gaps:**
1. `createHotspotGroups` creates groups in NetCloud but does **NOT** insert into `CradlepointDevice_Group`. Newly created groups won't appear in `getHotspotGroups` until manually synced.
2. If NetCloud group name changes, `CradlepointDevice.GroupName` may become stale until next device update.

##### What Happens for Non-Whitelisted Hotspots in QA

| Operation | Whitelisted Hotspot | Non-Whitelisted Hotspot |
|-----------|---------------------|-------------------------|
| **View in device list** | ✅ Works | ✅ Works (MySQL-only) |
| **Check availability** | ✅ Works | ✅ Works (MySQL-only) |
| **View/edit notes** | ✅ Works | ✅ Works (MySQL-only) |
| **Update status in DB** | ✅ Works | ✅ Works (MySQL-only) |
| **Add to facility** | ✅ Works (updates NetCloud) | ❌ **422 Error** |
| **Remove from facility** | ✅ Works (clears NetCloud) | ❌ **422 Error** |
| **Update NetCloud assignment** | ✅ Works | ❌ **422 Error** |
| **View network metrics** | ✅ Works | ✅ Works (read-only NetCloud) |
| **Create/update groups** | ✅ Works (no MAC involved) | ✅ Works (no MAC involved) |

#### 3. AWS IoT Core (Hub Communication)

**What it does**: Sends commands to physical hubs via IoT shadow documents

**Architecture**:
- Uses `boto3.client("iot-data")` for shadow operations
- Thing naming: `{PartNumber}-{SerialNumber}` (e.g., "HUB3-0002228")
- QA and Dev share IoT endpoint with different Lambda functions

| Operation | System | Notes |
|-----------|--------|-------|
| `updateHubShadowSettings` | AWS IoT Core | Updates hub configuration |
| `getHubShadowSettings` | AWS IoT Core | Reads current hub state |
| Hub diagnostic request | IoT + Lambda | Triggers `jobs-request-hub-diagnostic-{env}-{branch}` |
| Hub WiFi update | IoT + Lambda | Triggers `jobs-request-hub-wifi-{env}-{branch}` |
| Clear schedules | IoT + Lambda | Triggers `jobs-request-hub-clear-schedules-{env}-{branch}` |

**Note**: Hub operations go through frontend whitelist check (`CheckQAHub`) but there is **no backend whitelist** for hubs. The IoT messages are sent regardless if bypassing frontend.

#### 4. S3 Buckets (File Storage)

**What it stores**: Photos, documents, exports for machines/assets

**Whitelist behavior** (uses External Machine ID):
- **Whitelisted facility** → Files stored/read from QA bucket
- **Non-whitelisted facility** → Files stored/read from **production** bucket

| Condition | Bucket Used |
|-----------|-------------|
| QA + Whitelisted Facility | `assetwatch-files-{env}-{branch}` |
| QA + Non-Whitelisted Facility | `nikola-files` (production) |
| Mobile/Hub/Cradlepoint files | `assetwatch-facility-files-{env}-{branch}` |

### Summary: What Works Where

| Device Type | Pure MySQL Operations | External System Operations | Whitelist Enforcement |
|-------------|----------------------|---------------------------|----------------------|
| **Sensors** | ✓ View, status updates | Invoke, Schedule, Graph data | Frontend + Backend |
| **Hubs** | ✓ View, status updates | IoT commands (diagnostic, WiFi, etc.) | Frontend only (API gap) |
| **Hotspots** | ✓ View, notes, status | **Add/Remove from facility** | Frontend + Backend |
| **Facilities** | ✓ All CRUD operations | File uploads to S3 | Backend only |

**⚠️ Key Misconception to Avoid**: "MySQL operations always work" is **misleading** because many user-facing operations that appear to be simple CRUD actually call external systems behind the scenes.

### Practical Implications

1. **Pure MySQL operations work for any device** - Viewing device lists, updating notes, changing status in DB
2. **"Add to facility" is NOT a pure MySQL operation for hotspots** - It calls NetCloud API and will fail for non-whitelisted devices with HTTP 422
3. **Viewing data usually works** - Most read operations work for any device (may show prod data for non-whitelisted)
4. **Device commands require whitelist** - Actually invoking sensors, updating hubs, or modifying hotspots in NetCloud requires whitelisted hardware
5. **File uploads to QA require whitelisted facility** - Otherwise files go to production S3

### Common QA Testing Pitfalls

| What You're Trying To Do | What Happens with Non-Whitelisted Device |
|--------------------------|------------------------------------------|
| Test hotspot assignment workflow | ❌ Fails at "Add to facility" with 422 error |
| Test hotspot removal workflow | ❌ Fails at "Remove from facility" with 422 error |
| Test sensor scheduling | ❌ Blocked by frontend whitelist check |
| Test hub diagnostics | ❌ Blocked by frontend (but API has no backend check) |
| View device details | ✅ Works (MySQL-only) |
| Update device notes | ✅ Works (MySQL-only) |
| Test work order creation | ✅ Works (MySQL-only, doesn't trigger external calls) |

---

## Complete Whitelist of Devices

### Sensors (14 devices)

| Serial Number | Part Number | Monitoring Point UUID | Notes |
|---------------|-------------|----------------------|-------|
| 1309985 | 710-001 | fdecb257-a3f5-4d86-8ef7-18d5fe292f5a | |
| 1311260 | 710-001 | 5c5ed052-6112-4d6f-83dc-1e4fa51e8d48 | |
| 1314966 | 710-001 | c745b9dc-c0b0-42c8-bad5-1f4b1e9ed334 | |
| 1314975 | 710-001 | 2e317749-a2f2-47bf-ba2e-3603b393dc36 | |
| 1314976 | 710-001 | 3e27f2ad-b1a0-43cc-ad63-177ea69ec0fe | |
| 1314983 | 710-001 | ce36eb3e-ba51-4c79-b922-6b6cc79524db | |
| 1329641 | 710-001 | 43ba8aed-bf5d-43b1-b40a-1debc5a3bc45 | |
| 1326672 | 710-001 | c0c8c4f9-ae93-493a-aa96-968e9e383f3d | |
| 8000012 | 710-008 | 54dee81f-a530-4d37-acca-5a1f91e09045 | |
| 8000013 | 710-008 | (not in UUID list) | |
| 8000015 | 710-008 | (not in UUID list) | |
| 0046896 | 710-001 | 3c6c208d-7cad-48a1-8c24-6e0f15b77faf | |
| 0046868 | 710-001 | (not in UUID list) | |
| 0044132 | 710-001 | (not in UUID list) | |

**Note**: The Monitoring Point UUID is used for Timestream table routing in graph queries. Some sensors don't have UUIDs in the whitelist - they will query production Timestream for graph data.

### Hubs (8 devices)

| Part Number | Serial Number | Full Format |
|-------------|---------------|-------------|
| 710-002 | 0005486 | 710-002_0005486 |
| 710-002 | 0006596 | 710-002_0006596 |
| 710-002 | 0000701 | 710-002_0000701 |
| 710-200 | 9990007 | 710-200_9990007 |
| 710-200 | 9992077 | 710-200_9992077 |
| 710-002 | 0010995 | 710-002_0010995 |
| 710-002 | 0006436 | 710-002_0006436 |
| 710-002 | 0007651 | 710-002_0007651 |

### Hotspots (6 MAC addresses)

| MAC Address | Model |
|-------------|-------|
| 00:30:44:5E:5C:FC | IBR200 |
| 00:30:44:8C:E5:8C | IBR200 |
| 00:30:44:B4:92:A3 | S400 |
| 00:30:44:B4:92:6B | S400 |
| 00:30:44:B4:93:E7 | S400 |
| 00:30:44:48:C1:AC | Not in NetCloud |

### External Machine IDs (2 facilities - for file uploads)

| External Machine ID | Purpose |
|---------------------|---------|
| 270bee0e-18d3-4909-b78e-3230f108c5e4 | QA file bucket routing |
| e1ec7cd7-a259-4798-baaa-c3efe6a4562f | QA file bucket routing |

---

## Frontend Implementation

### Environment Detection

**File**: `frontend/src/components/Utilities.ts` (lines 596-614)

```typescript
export function isTestEnvironment() {
  const deployEnvironment = import.meta.env.VITE_DEPLOY_ENVIRONMENT;
  const domain = import.meta.env.VITE_DOMAIN;

  // Check if environment is "qa" or "localhost"
  if (deployEnvironment?.startsWith("qa") || isLocalhost()) {
    return true;
  }

  // Check if VITE_DOMAIN has a first level subdomain of "qa"
  const regex = /^(?:https?:\/\/)?([^./]+)\./;
  const match = domain.match(regex);
  if (match && match.length >= 2 && match[1] === "qa") {
    return true;
  }

  return false;
}
```

Returns `true` when:
- `VITE_DEPLOY_ENVIRONMENT` starts with "qa"
- Running on localhost
- Domain has "qa" as the first subdomain (e.g., `qa.prod.assetwatch.com`)

### Whitelist Validation Functions

**File**: `frontend/src/components/common/CheckQA.ts`

| Function | Purpose | Validates | On Failure |
|----------|---------|-----------|------------|
| `CheckQA(sensor)` | Single sensor validation | Serial number | Toast: "Sensor not in approved QA whitelist." |
| `CheckQASensorList(sensors[])` | Batch sensor validation | All serials in array | Toast: "Not all sensors in approved QA whitelist." |
| `CheckQAHub(hub)` | Hub validation | Serial (with or without part prefix) | Toast: "Hub is NOT in approved QA whitelist." |
| `checkQAHotspotList(macs[])` | Hotspot validation | All MAC addresses | Toast: "Hotspot is not in approved QA whitelist." |

### Where Frontend Whitelist Checks Occur

| Location | Function Used | Trigger | Action Blocked |
|----------|---------------|---------|----------------|
| `RequestServiceV2.ts:136` | `CheckQAHub()` | Hub request submission | All hub operations (diagnostic, firmware, reboot, etc.) |
| `Schedule.tsx:420` | `CheckQA()` | Schedule creation | Sensor scheduling |
| `InvokeSensors.tsx:147` | `CheckQASensorList()` | Bulk sensor invoke | Multi-sensor data collection |
| `AddHotspot.tsx:266` | `checkQAHotspotList()` | Hotspot assignment | Adding hotspot to facility |
| `RemoveHotspot.tsx:122` | `checkQAHotspotList()` | Hotspot removal | Removing hotspot from facility |
| `WorkOrderModal.tsx:416` | `checkQAHotspotList()` | BOM hardware save | Work order hotspot assignment |

---

## Backend Implementation

### Cradlepoint (Hotspot) Lambda

**File**: `lambdas/lf-vero-prod-cradlepoint/main.py` (lines 25-32)

```python
valid_qa_cradlepoint_mac_addresses = [
    "00:30:44:5E:5C:FC", #IBR200
    "00:30:44:8C:E5:8C", #IBR200
    "00:30:44:B4:92:A3", #S400
    "00:30:44:B4:92:6B", #S400
    "00:30:44:B4:93:E7", #S400
    "00:30:44:48:C1:AC", #Not in NetCloud
]
```

**Enforcement** (lines 418-490):
- Only active when `ENV_VAR != "prod"`
- Validates MAC addresses for: `removeCradlepoint`, `addBulkCradlepoints`, `updateNetcloudCradlepointFacility`, `addBulkFacilityCradlepoints`
- Returns HTTP 422 with error: "MAC address(es) not approved for QA environment"

### Sensor Lambda

**File**: `lambdas/lf-vero-prod-sensor/main.py` (lines 13-28, 67-82)

```python
valid_qa_sensors_short_ids = [
    "1309985", "1311260", "1314966", "1314975", "1314976",
    "1314983", "1329641", "1326672", "8000012", "8000013",
    "8000015", "0046896", "0046868", "0044132"
]

valid_qa_sensors = [
    "710-001_1309985", "710-001_1311260", # ... etc with part prefixes
]
```

**Purpose**: Controls which Timestream database (QA vs prod) is used for sensor data queries.

### File Upload Lambda

**File**: `lambdas/lf-vero-prod-file/lambda_function.py` (lines 39-42)

```python
valid_qa_external_machine_ids = [
    "270bee0e-18d3-4909-b78e-3230f108c5e4",
    "e1ec7cd7-a259-4798-baaa-c3efe6a4562f",
]
```

**Purpose**: Routes file uploads to QA S3 bucket when facility's ExternalMachineID is in whitelist.

---

## How to Add a Device to the Whitelist

### Adding a Sensor

**Update 2-4 files depending on what operations you need:**

#### Required (for invoke/schedule operations):

1. **Frontend**: `frontend/src/components/common/CheckQA.ts`
   - Add serial to `approvedSensorListQA` array in `CheckQA()` (lines 20-35)
   - Add serial to `approvedSensorListQA` array in `CheckQASensorList()` (lines 48-60)

2. **Backend Sensor Lambda**: `lambdas/lf-vero-prod-sensor/main.py`
   - Add short ID to `valid_qa_sensors_short_ids` (lines 13-28)
   - Add full format (`710-001_XXXXXXX`) to `valid_qa_sensors` (lines 67-82)

#### Optional (for QA Timestream graph data isolation):

3. **Backend Graph Lambda**: `lambdas/lf-vero-prod-graph/query_timestream.py`
   - Add External Monitoring Point UUID to `valid_external_monitoringpointids` tuple (lines 8-20)
   - Comment with serial number for reference

4. **Backend Monitoring Point Lambda**: `lambdas/lf-vero-prod-monitoringpoint/query_timestream.py`
   - Add External Monitoring Point UUID to `valid_external_monitoringpointids` tuple
   - This ensures temperature queries use QA Timestream

**Note**: If you don't add the monitoring point UUID, the sensor will work for invoke/schedule but graph queries will show production data (cross-account to prod Timestream).

### Adding a Hub

**Update 1 file:**

1. **Frontend**: `frontend/src/components/common/CheckQA.ts`
   - Add to both `approvedQaHubList` arrays in `CheckQAHub` function (lines 81-101)
   - One with underscore format: `"710-002_XXXXXXX"`
   - One without: `"XXXXXXX"`

**Note**: There is no backend hub whitelist - only frontend validation exists.

### Adding a Hotspot

**Update 2 files:**

1. **Frontend**: `frontend/src/components/common/CheckQA.ts`
   - Add MAC address to `approvedQAHotSpotList` (lines 112-119)
   - Format: `"00:30:44:XX:XX:XX"` (uppercase, colon-separated)

2. **Backend**: `lambdas/lf-vero-prod-cradlepoint/main.py`
   - Add MAC address to `valid_qa_cradlepoint_mac_addresses` (lines 25-32)
   - Include model comment (e.g., `#S400`)

### Adding a QA Facility (for file uploads)

**Update 2 files:**

1. **File Lambda**: `lambdas/lf-vero-prod-file/lambda_function.py`
   - Add External Machine ID to `valid_qa_external_machine_ids` (lines 39-42)

2. **Asset Alert Lambda**: `lambdas/lf-vero-prod-assetalert/main.py`
   - Add External Machine ID to `valid_qa_external_machine_ids` (lines 26-29)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Frontend (React)                         │
├─────────────────────────────────────────────────────────────────┤
│  isTestEnvironment() ──► ENV check (qa/localhost/domain)        │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    CheckQA.ts                           │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │  CheckQA()           → Sensor validation                │    │
│  │  CheckQASensorList() → Batch sensor validation          │    │
│  │  CheckQAHub()        → Hub validation                   │    │
│  │  checkQAHotspotList()→ Hotspot MAC validation           │    │
│  └─────────────────────────────────────────────────────────┘    │
│           │                                                     │
│           ▼ (if invalid: show toast, block operation)           │
│           │                                                     │
│           ▼ (if valid: proceed to API call)                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Backend (Lambda)                            │
├─────────────────────────────────────────────────────────────────┤
│  ENV_VAR != "prod" ──► Whitelist enforcement active             │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  lf-vero-prod-cradlepoint                               │    │
│  │    └── valid_qa_cradlepoint_mac_addresses               │    │
│  │                                                         │    │
│  │  lf-vero-prod-sensor                                    │    │
│  │    └── valid_qa_sensors / valid_qa_sensors_short_ids    │    │
│  │                                                         │    │
│  │  lf-vero-prod-file / lf-vero-prod-assetalert            │    │
│  │    └── valid_qa_external_machine_ids                    │    │
│  └─────────────────────────────────────────────────────────┘    │
│           │                                                     │
│           ▼ (if invalid: return 422 error)                      │
│           │                                                     │
│           ▼ (if valid: execute operation)                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Code References

### Frontend
- `frontend/src/components/common/CheckQA.ts` - All whitelist validation functions
- `frontend/src/components/Utilities.ts:596-614` - `isTestEnvironment()` function
- `frontend/src/shared/api/RequestServiceV2.ts:136` - Hub request validation
- `frontend/src/components/Schedule.tsx:420` - Sensor schedule validation
- `frontend/src/components/AssetDetailPage/InvokeSensors.tsx:147` - Bulk invoke validation
- `frontend/src/components/CustomerDetailPage/Hotspots/AddHotspot.tsx:266` - Add hotspot validation
- `frontend/src/components/CustomerDetailPage/Hotspots/RemoveHotspot.tsx:122` - Remove hotspot validation
- `frontend/src/components/CustomerDetailPage/WorkOrders/WorkOrderModal.tsx:416` - Work order hotspot validation

### Backend
- `lambdas/lf-vero-prod-cradlepoint/main.py:25-32` - Hotspot whitelist definition
- `lambdas/lf-vero-prod-cradlepoint/main.py:418-490` - Hotspot whitelist enforcement
- `lambdas/lf-vero-prod-sensor/main.py:13-28` - Sensor short ID whitelist
- `lambdas/lf-vero-prod-sensor/main.py:67-82` - Sensor full format whitelist
- `lambdas/lf-vero-prod-file/lambda_function.py:39-42` - External machine ID whitelist
- `lambdas/lf-vero-prod-assetalert/main.py:26-29` - Asset alert machine ID whitelist

---

## Database

**No database tables exist for whitelisting.** All device validation is performed at the application layer with hardcoded lists. This means:
- No runtime configuration of approved devices
- Changes require code deployment
- No audit trail of whitelist modifications (only git history)

---

## Whitelists in Other Repositories

**CRITICAL**: The hardware whitelist is **not limited to fullstack.assetwatch**. Other repositories have parallel whitelist implementations that must also be updated when adding devices.

### assetwatch-jobs Repository (IMPORTANT)

The `~/repos/assetwatch-jobs` repository contains a **centralized whitelist in Terraform** that is injected as environment variables into Lambda functions.

**Location**: `assetwatch-jobs/terraform/main.tf` (lines 385-387)

#### Sensors Defined in assetwatch-jobs

```hcl
valid_qa_sensors = [
  "710-001_1314983", "710-001_1314966", "710-001_1314976",
  "710-001_1314975", "710-001_1309985", "710-001_1311260",
  "710-001_1329641", "710-001_1326672", "710-001_0046896",
  "710-001_0046868"
]
```

**Note**: This list has **10 sensors** vs. **14 in fullstack.assetwatch** - missing: `8000012`, `8000013`, `8000015`, `0044132`

#### Hubs Defined in assetwatch-jobs

**Short ID Format**:
```hcl
valid_hubs_short_id = [
  "0010995", "5486", "0005486", "0006596", "0000701",
  "9990007", "9992077", "0008412", "0006436"
]
```

**Long ID Format**:
```hcl
valid_hubs_long_id = [
  "710-002_0010995", "710-002_5486", "710-002_0005486",
  "710-002_0006596", "710-002_0000701", "710-200_9990007",
  "710-200_9992077", "710-002_0008412", "710-002_0006436"
]
```

**Note**: This includes `0008412` which is **NOT in fullstack.assetwatch**. Also includes variant `5486` and `0005486`.

#### Additional Whitelists in assetwatch-jobs

| Whitelist | Location | Values |
|-----------|----------|--------|
| **QA Facilities** | `request_lambda/main.py:35` | Facility ID `2510` (Brock facility) |
| **Schedule Optimizer Facilities** | `jobs_schedule_optimizer/main.py:259` | Facility IDs `2510`, `617` |
| **Receiver MAC** | `jobs_descase_hardware/common_resources.py:38-40` | `C6:A5:57:B5:78:51` |
| **Master Schedule Hubs** | `jobs_data_logger_gen2/main.py:35-40` | `710-002_0000701`, `710-002_0000026`, `710-002_0002464`, `710-002_0005486` |

#### Lambda Functions Using These Whitelists

Environment variables `VALID_QA_SENSOR_WHITELIST` and `VALID_QA_HUB_WHITELIST` are injected into:

**Hub Operations**:
- `request-hub-open`, `request-hub-close`, `request-hub-firmware`
- `request-hub-diagnostic`, `request-hub-log-level`, `request-hub-reboot`
- `request-hub-wifi`, `request-hub-clear-queue`, `request-hub-clear-schedules`
- `request-hub-report-schedules`, `request-master-schedule`

**Sensor Operations**:
- `request-sensor-diagnostic`, `request-sensor-firmware`
- `request-invoke`, `request-schedule`, `request-sender-v2`, `request-batch`

### fullstack.jobs Repository

**No hardcoded device whitelists**, but has environment-based routing:

| Feature | QA Behavior | Location |
|---------|-------------|----------|
| **Email Routing** | Forces all emails to `qa.testcustomer@assetwatch.com` | `jobs-email-sender/index.js:51` |
| **Timestream Access** | Cross-account to prod via `qa-timestream-access-role` | `TimestreamOps.js` |
| **Test Procedures** | Uses `_Test` stored procedures with 1 user limit | `fs-jobs-email-weekly/index.js:50` |
| **Salesforce** | Routes to sandbox `nikolatech--partial.sandbox.my.salesforce.com` | `salesforce_config.mjs:55` |

### assetwatch-mobile-backend Repository

**No device whitelists**, but has user email whitelist for Slack:

**Location**: `lambda/oil_and_collect_slack_message/index.js:158-171`

```javascript
const skippable_emails = [
  "assetwatch.tester@gmail.com",
  "kaizawa.customer@assetwatch.com",
  "ssiddiqui.customer@assetwatch.com",
  "blambert.customer@assetwatch.com",
  "etorres.customer@assetwatch.com",
  "cgoodnight.customer@assetwatch.com",
  // ... more test emails
]
```

These emails route Slack notifications to TEST webhook instead of production.

### Repositories WITHOUT Device Whitelists

| Repository | Notes |
|------------|-------|
| **internal.api** | No device whitelists; only has test simulator device IDs |
| **external.api** | Only has client authentication whitelists (Cognito client IDs) |
| **hwqa** | Database-driven device validation; no hardcoded lists |

---

## Updated: How to Add a Device to the Whitelist

### Adding a Sensor (UPDATED - 4+ files across 2 repos)

#### In fullstack.assetwatch:

1. **Frontend**: `frontend/src/components/common/CheckQA.ts`
   - Add to `approvedSensorListQA` in `CheckQA()` (lines 20-35)
   - Add to `approvedSensorListQA` in `CheckQASensorList()` (lines 48-60)

2. **Backend Sensor Lambda**: `lambdas/lf-vero-prod-sensor/main.py`
   - Add to `valid_qa_sensors_short_ids` (lines 13-28)
   - Add to `valid_qa_sensors` (lines 67-82)

3. **Backend Graph Lambda** (optional): `lambdas/lf-vero-prod-graph/query_timestream.py`
   - Add monitoring point UUID to `valid_external_monitoringpointids`

#### In assetwatch-jobs:

4. **Terraform**: `terraform/main.tf`
   - Add to `valid_qa_sensors` local variable (line ~385)

### Adding a Hub (2 files across 2 repos)

**Note**: There is NO backend hub whitelist in `fullstack.assetwatch`. The hub API lambda (`lf-vero-prod-hub`) does not validate - it relies on `assetwatch-jobs` for enforcement.

#### In fullstack.assetwatch:

1. **Frontend ONLY**: `frontend/src/components/common/CheckQA.ts`
   - Add to both `approvedQaHubList` arrays in `CheckQAHub()` (lines 81-101)
   - One with underscore format: `"710-002_XXXXXXX"`
   - One without: `"XXXXXXX"`

#### In assetwatch-jobs:

2. **Terraform**: `terraform/main.tf`
   - Add to `valid_hubs_short_id` local variable (e.g., `"0005486"`)
   - Add to `valid_hubs_long_id` local variable (e.g., `"710-002_0005486"`)

**This is the ONLY backend validation for hubs** - it happens when jobs process the request, not in the hub API lambda.

### Adding a Hotspot (No change - still 2 files)

1. **Frontend**: `frontend/src/components/common/CheckQA.ts`
2. **Backend**: `lambdas/lf-vero-prod-cradlepoint/main.py`

---

## Whitelist Synchronization Issues

**Current inconsistencies found between repositories:**

| Device Type | fullstack.assetwatch | assetwatch-jobs | Status |
|-------------|---------------------|-----------------|--------|
| **Sensors** | 14 devices | 10 devices | ⚠️ **MISMATCH** - jobs missing 4 |
| **Hubs** | 8 devices | 9 devices | ⚠️ **MISMATCH** - jobs has extra `0008412` |
| **Hub `0007651`** | ✓ Present | ✗ Missing | ⚠️ **MISMATCH** |
| **Hub `0008412`** | ✗ Missing | ✓ Present | ⚠️ **MISMATCH** |

These inconsistencies mean some devices may work for certain operations but not others.

---

## Additional Backend Code References (External Systems)

### Timestream
- `lambdas/lf-vero-prod-sensor/main.py:64-119` - `configure_aws_client()` function with sensor whitelist routing
- `lambdas/lf-vero-prod-graph/query_timestream.py:8-20` - Monitoring point UUID whitelist
- `lambdas/lf-vero-prod-graph/query_timestream.py:28-32` - `get_table_name()` function for table routing
- `lambdas/lf-vero-prod-monitoringpoint/query_timestream.py` - Temperature data Timestream queries

### NetCloud API
- `lambdas/lf-vero-prod-cradlepoint/main.py:418-490` - QA whitelist enforcement logic
- `lambdas/lf-vero-prod-cradlepoint/main.py:1114-1121` - Error response for blocked MACs

### AWS IoT Core
- `lambdas/lf-vero-prod-hub/main.py:259` - `iot_client.update_thing_shadow()`
- `lambdas/lf-vero-prod-hub/main.py:296` - `iot_client.get_thing_shadow()`
- `terraform/lambda-iam-roles.tf:1046-1063` - IoT permissions for hub lambda

### S3 Bucket Routing
- `lambdas/lf-vero-prod-file/lambda_function.py:298-312` - Bucket selection logic in `get_files()`
- `lambdas/lf-vero-prod-file/lambda_function.py:1158-1166` - Asset upload bucket routing
- `lambdas/lf-vero-prod-assetalert/main.py:165-170` - Thumbnail bucket selection
- `lambdas/lf-vero-prod-assetalertnextstep/main.py:29-32` - Asset alert next step whitelist

---

## Open Questions

### Critical Issues

1. **Cross-repository whitelist drift**: `fullstack.assetwatch` and `assetwatch-jobs` have different device lists - should these be synchronized?
   - fullstack.assetwatch has 4 more sensors (710-008 series)
   - assetwatch-jobs has hub `0008412` not in fullstack
   - fullstack has hub `0007651` not in assetwatch-jobs

2. **No single source of truth**: Whitelists are duplicated across repositories with no automated synchronization - should a shared configuration be created?

### Existing Issues

3. **Hub backend validation gap**: Hubs only have frontend whitelist check in fullstack.assetwatch - but assetwatch-jobs does validate via Terraform-injected env vars

4. **Sensor whitelist array drift within CheckQA.ts**: `CheckQASensorList` has only 11 sensors while `CheckQA` has 14 (missing 8000012, 8000013, 8000015) - is this intentional?

5. **Monitoring point UUID coverage**: Not all whitelisted sensors have corresponding UUIDs in the graph lambda - should these be added for complete QA isolation?

6. **Cross-account role dependency**: Non-whitelisted devices in QA rely on `qa-timestream-access-role` in prod account - what happens if this role is misconfigured?

### Documentation Questions

7. **Where is the canonical device list?**: Is there a spreadsheet, wiki, or other source that tracks which physical devices are designated as QA equipment?

8. **Hub `0008412` status**: This hub is in assetwatch-jobs but not fullstack.assetwatch - is it a valid QA hub that was missed, or should it be removed?
