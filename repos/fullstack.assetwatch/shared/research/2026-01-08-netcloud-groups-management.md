---
date: 2026-01-08T13:10:33-05:00
researcher: Jackson Walker
git_commit: 388a82789530c737ce21a6f8835db261ac801e82
branch: dev
repository: fullstack.assetwatch
topic: "NetCloud Groups Management Between Database and API"
tags: [research, codebase, netcloud, cradlepoint, hotspots, groups, database, api, whitelist, testing]
status: complete
last_updated: 2026-01-08
last_updated_by: Jackson Walker
last_updated_note: "Added clarification that GroupID is available in NetCloud response but not persisted to database"
related_research: "2026-01-08-hardware-whitelist-system.md"
---

# Research: NetCloud Groups Management Between Database and API

**Date**: 2026-01-08T13:10:33-05:00
**Researcher**: Jackson Walker
**Git Commit**: 388a82789530c737ce21a6f8835db261ac801e82
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question

How are NetCloud groups managed between the database and the NetCloud API? How does the whitelist system affect hotspot operations? How can the relationship between `CradlepointDevice.GroupName` and `CradlepointDevice_Group.GroupID` be improved for normalization, reliability, and simplified testing in QA/dev environments?

---

## Executive Summary

NetCloud groups management involves a **dual-system architecture** where NetCloud (Cradlepoint's cloud platform) is the **source of truth** for device group assignments, while MySQL stores a **cached copy** of group names and a **lookup table** of available groups. The current implementation has a critical architectural gap: `CradlepointDevice.GroupName` stores a denormalized string with no foreign key relationship to `CradlepointDevice_Group`, making synchronization fragile and testing difficult.

**Key Findings:**
1. **NetCloud API is the source of truth** - Device group assignments are managed via PUT requests to `/routers/{cpid}/`
2. **No database relationship** - `CradlepointDevice.GroupName` (VARCHAR 200) has no FK to `CradlepointDevice_Group`
3. **Whitelist blocks NetCloud operations** - In QA/dev, hotspot add/remove operations require whitelisted MAC addresses
4. **CradlepointDevice_Group is read-only** - No stored procedures write to this table; it's populated externally
5. **Improvement opportunities exist** - Normalizing GroupName and implementing mock NetCloud mode could significantly improve testability

---

## Concise Whitelist Summary for Hotspots

### What the Whitelist Does

The hardware whitelist is a **QA environment protection mechanism** that prevents accidental modifications to production hotspots. It is enforced in two layers:

| Layer | Location | Enforcement |
|-------|----------|-------------|
| **Frontend** | `frontend/src/components/common/CheckQA.ts:112-119` | `checkQAHotspotList()` blocks UI operations |
| **Backend** | `lambdas/lf-vero-prod-cradlepoint/main.py:418-490` | Returns HTTP 422 for non-whitelisted MACs |

### Whitelisted Hotspots (6 MAC Addresses)

```
00:30:44:5E:5C:FC (IBR200)
00:30:44:8C:E5:8C (IBR200)
00:30:44:B4:92:A3 (S400)
00:30:44:B4:92:6B (S400)
00:30:44:B4:93:E7 (S400)
00:30:44:48:C1:AC (Not in NetCloud)
```

### Operations Affected by Whitelist

| Operation | Requires Whitelist | Why |
|-----------|-------------------|-----|
| View hotspot list | No | MySQL-only query |
| Check availability | No | MySQL-only query |
| View/edit notes | No | MySQL-only update |
| **Add to facility** | **YES** | Calls NetCloud API to set group |
| **Remove from facility** | **YES** | Calls NetCloud API to clear group |
| Update NetCloud assignment | **YES** | Direct NetCloud API call |
| Create/update groups | No | No MAC involved |
| View network metrics | No | Read-only NetCloud call |

### Critical Implication for Testing

**Most hotspot workflow testing in QA is blocked** unless using one of the 6 whitelisted devices. Operations that "appear" to be simple CRUD actually call NetCloud API and fail with HTTP 422 for non-whitelisted MACs.

---

## How NetCloud Groups Are Managed

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          NetCloud API (Source of Truth)                      │
│                    https://cradlepointecm.com/api/v2/                        │
├─────────────────────────────────────────────────────────────────────────────┤
│  /routers/?mac={mac}&expand=group  - Get device with group info             │
│  /routers/{cpid}/                  - PUT to update group assignment          │
│  /groups/                          - POST to create new group               │
│  /groups/{id}/                     - PUT to update group config             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ API Calls
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    lf-vero-prod-cradlepoint Lambda                           │
│              lambdas/lf-vero-prod-cradlepoint/main.py                        │
├─────────────────────────────────────────────────────────────────────────────┤
│  • Extracts GroupName from NetCloud response: group["name"]                  │
│  • Passes GroupName string to stored procedures                              │
│  • Sends group URL to NetCloud for assignments                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Stored Procedure Calls
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          MySQL Database                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  CradlepointDevice                    CradlepointDevice_Group               │
│  ├─ GroupName VARCHAR(200) ────────── (NO FK) ────────┐                     │
│  │  (cached group name string)        ├─ GroupID INT (NetCloud ID)          │
│  │                                    ├─ Name VARCHAR(65)                   │
│  └─ ...                               ├─ URL VARCHAR(100)                   │
│                                       └─ ProductID INT (IBR200/S400)        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### NetCloud API Integration Details

**File:** `lambdas/lf-vero-prod-cradlepoint/main.py`

#### Authentication (lines 166-173)
```python
headers = {
    "X-CP-API-ID": DECRYPTED_CP_API_ID,
    "X-CP-API-KEY": DECRYPTED_CP_API_KEY,
    "X-ECM-API-ID": DECRYPTED_ECM_API_ID,
    "X-ECM-API-KEY": DECRYPTED_ECM_API_KEY,
    "Content-Type": "application/json",
}
```

#### Key API Operations

| Operation | Endpoint | Method | Purpose |
|-----------|----------|--------|---------|
| Get device | `/routers/?expand=group&mac={MAC}` | GET | Retrieve device with group data |
| Update device group | `/routers/{cpid}/` | PUT | Assign device to group |
| Create group | `/groups/` | POST | Create new NetCloud group |
| Update group | `/groups/{id}/` | PUT | Update group WiFi config |

#### Group Assignment Flow (`addBulkFacilityCradlepoints`, lines 861-973)

```
1. Get current device from NetCloud
   GET /routers/?expand=group&mac={MAC}

2. Update device in NetCloud
   PUT /routers/{cpid}/
   Body: {"description": "{extfid}", "group": "{group_url}"}

3. Verify update from NetCloud
   GET /routers/?expand=group&mac={MAC}

4. Extract GroupName from response
   GroupName = response["group"]["name"].replace("'", "")

5. Store in MySQL
   CALL Cradlepoint_AddCradlepoint(..., GroupName, ...)
```

#### Group Creation (`createHotspotGroups`, lines 624-637)

Creates **two groups per request** - one for IBR200 and one for S400:
- Group names formatted as `{name} (IBR200)` and `{name} (S400)`
- IBR200: ProductID 49, Firmware 14812 (v7.23.94)
- S400: ProductID 105, Firmware 16850 (v7.25.80)
- Account URL: `https://www.cradlepointecm.com/api/v2/accounts/42839/`

---

## Database Schema Analysis

### CradlepointDevice Table

**File:** `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql` (lines 498-530)

```sql
CREATE TABLE `CradlepointDevice` (
  `CradlepointDeviceID` int NOT NULL AUTO_INCREMENT,
  `CradlepointDeviceName` varchar(50) DEFAULT NULL,
  `CustomerID` int DEFAULT NULL,
  `GroupName` varchar(200) DEFAULT NULL,  -- Line 503: NO FK constraint
  `MAC` varchar(50) DEFAULT NULL,
  `SerialNumber` varchar(50) DEFAULT NULL,
  -- ... other columns
  PRIMARY KEY (`CradlepointDeviceID`)
);
```

**Key Observation:** `GroupName` is a free-text VARCHAR(200) with no foreign key relationship.

### CradlepointDevice_Group Table

**File:** `mysql/db/table_change_scripts/V20251121_222840__IWA-14010_Add_CradlepointDevice_Group_Table.sql` (lines 16-30)

```sql
CREATE TABLE `CradlepointDevice_Group` (
  `CradlepointDeviceGroupID` INT NOT NULL AUTO_INCREMENT,
  `GroupID` INT NOT NULL COMMENT 'Netcloud Group ID',
  `Name` VARCHAR(65) NOT NULL,
  `ActiveFlag` BIT(1) NOT NULL,
  `URL` VARCHAR(100) NOT NULL,
  `ProductID` INT NOT NULL,  -- FK to Product (IBR200=5, S400=33)
  PRIMARY KEY (`CradlepointDeviceGroupID`),
  FOREIGN KEY (`ProductID`) REFERENCES `Product`(`ProductID`)
);
```

### Current Relationship (or Lack Thereof)

```
CradlepointDevice                          CradlepointDevice_Group
┌──────────────────────┐                   ┌─────────────────────────┐
│ CradlepointDeviceID  │                   │ CradlepointDeviceGroupID│
│ GroupName VARCHAR(200)├── NO FK ──────── │ GroupID INT             │
│ ...                  │                   │ Name VARCHAR(65)        │
└──────────────────────┘                   │ URL VARCHAR(100)        │
                                           │ ProductID INT           │
                                           └─────────────────────────┘
```

**Problems with Current Design:**
1. **No referential integrity** - GroupName can contain any string
2. **Size mismatch** - Device allows 200 chars, Group table only 65
3. **No normalization** - GroupName duplicates data instead of referencing
4. **Sync gaps** - `createHotspotGroups` creates in NetCloud but doesn't insert into `CradlepointDevice_Group`

> **Note on Sync Gap:** The `create_netcloud_group()` function (lines 236-275) **does receive the GroupID** in the NetCloud POST response. The response object contains `id`, `name`, and `resource_url`. However, the current implementation returns this data to the client (line 637) without inserting it into `CradlepointDevice_Group`. A future enhancement could add a database insert after the NetCloud call succeeds, using the response data to populate the lookup table automatically.

---

## Stored Procedures Analysis

### Procedures That WRITE GroupName

| Procedure | File | Action |
|-----------|------|--------|
| `Cradlepoint_AddCradlepoint` | `mysql/db/procs/R__PROC_Cradlepoint_AddCradlepoint.sql` | INSERT/UPDATE GroupName (lines 74-75, 98, 149) |
| `Cradlepoint_RemoveCradlepoint` | `mysql/db/procs/R__PROC_Cradlepoint_RemoveCradlepoint.sql` | UPDATE GroupName (line 54) |
| `EnclosureCradlepointDevice_UpdateFacility` | `mysql/db/procs/R__PROC_EnclosureCradlepointDevice_UpdateFacility.sql` | UPDATE GroupName, requires non-null (line 46) |
| `WorkOrder_UpdateCradlepoints` | `mysql/db/procs/R__PROC_WorkOrder_UpdateCradlepoints.sql` | UPDATE GroupName (line 24) |
| `WorkOrder_LinkHardwareToRbom` | `mysql/db/procs/R__PROC_WorkOrder_LinkHardwareToRbom.sql` | UPDATE GroupName, defaults to 'HQ Shipping To Nikola Labs' |

### Procedures That READ from CradlepointDevice_Group

| Procedure | File | Action |
|-----------|------|--------|
| `Cradlepoint_GetGroups` | `mysql/db/procs/R__PROC_Cradlepoint_GetGroups.sql` | SELECT GroupID, Name, URL, ProductID |

**Critical Finding:** `Cradlepoint_GetGroups` is the **ONLY** procedure that reads from `CradlepointDevice_Group`. **No procedures write to this table** - it must be populated externally (likely manual process). As noted above, the GroupID is available in the `createHotspotGroups` response but not currently persisted.

---

## Frontend Implementation

### Group Selection Components

**InventoryHotspotGroupSelection** (`frontend/src/components/common/forms/Statuses.tsx:404-448`)
- Renders Mantine Select dropdown
- Filters groups by `productId` (IBR200 vs S400)
- Displays `group.name`, stores `group.id`

**AddHotspot Modal** (`frontend/src/components/CustomerDetailPage/Hotspots/AddHotspot.tsx:587-597`)
- Uses `completeGroupList` or filtered `groupList` based on toggle
- Auto-selects group matching facility/customer name

**RemoveHotspot Modal** (`frontend/src/components/CustomerDetailPage/Hotspots/RemoveHotspot.tsx:228-238`)
- Uses only filtered `groupList`
- Retrieves URL from group list for NetCloud API call

### Data Flow

```typescript
// useGetHotspotGroups hook (frontend/src/hooks/services/hotspots/useGetHotspotGroups.ts)
// Returns two lists:
data: HotspotGroup[]          // Filtered to groups containing "HQ "
completeGroupList: HotspotGroup[]  // All groups sorted alphabetically

// HotspotGroup type (frontend/src/shared/types/hotspots/HotspotGroup.ts)
type HotspotGroup = {
  id: number;       // GroupID (from CradlepointDevice_Group.GroupID)
  name: string;     // Group name
  productId: number; // Product type (5=IBR200, 33=S400)
  url: string;      // NetCloud API URL for group
};
```

---

## Improvement Recommendations

### 1. Normalize GroupName with Foreign Key

**Current State:**
- `CradlepointDevice.GroupName` stores denormalized string
- No referential integrity

**Proposed Change:**

```sql
-- Add GroupID column to CradlepointDevice
ALTER TABLE CradlepointDevice
ADD COLUMN CradlepointDeviceGroupID INT NULL,
ADD CONSTRAINT fk_CradlepointDevice_Group
    FOREIGN KEY (CradlepointDeviceGroupID)
    REFERENCES CradlepointDevice_Group(CradlepointDeviceGroupID);

-- Migrate data (one-time)
UPDATE CradlepointDevice cd
JOIN CradlepointDevice_Group cg ON cd.GroupName = cg.Name
SET cd.CradlepointDeviceGroupID = cg.CradlepointDeviceGroupID;

-- Eventually deprecate GroupName column
```

**Benefits:**
- Referential integrity ensures valid groups
- Single source of truth for group names
- Easier queries with JOINs instead of string matching
- Prevents orphaned or invalid GroupName values

### 2. Implement CradlepointDevice_Group Sync

**Current Gap:** `createHotspotGroups` creates groups in NetCloud but doesn't insert into `CradlepointDevice_Group`.

**Proposed Solution:**

```python
# In main.py createHotspotGroups handler (after line 637)
def sync_group_to_database(group_response, product_id):
    """Insert newly created NetCloud group into CradlepointDevice_Group"""
    cursor.callproc("Cradlepoint_InsertGroup", [
        group_response["id"],      # NetCloud GroupID
        group_response["name"],    # Group name
        group_response["resource_url"],  # URL
        product_id
    ])
```

**New Stored Procedure:**
```sql
CREATE PROCEDURE Cradlepoint_InsertGroup(
    IN inGroupID INT,
    IN inName VARCHAR(65),
    IN inURL VARCHAR(100),
    IN inProductID INT
)
BEGIN
    INSERT INTO CradlepointDevice_Group (GroupID, Name, ActiveFlag, URL, ProductID)
    VALUES (inGroupID, inName, 1, inURL, inProductID)
    ON DUPLICATE KEY UPDATE
        Name = inName,
        URL = inURL,
        DateUpdated = CURRENT_TIMESTAMP(3);
END
```

### 3. Mock NetCloud Mode for Dev/QA Testing

**Current Problem:** Testing hotspot workflows in dev/QA requires whitelisted physical devices.

**Proposed Solution: Database-Only Mock Mode**

```python
# Environment variable: MOCK_NETCLOUD=true

def update_cradlepoint(cpid, extfid, group_url):
    if os.environ.get("MOCK_NETCLOUD") == "true":
        # Skip actual NetCloud API call
        # Return mock response based on group_url
        return mock_netcloud_response(cpid, group_url)

    # Normal NetCloud API call
    return actual_netcloud_call(cpid, extfid, group_url)

def mock_netcloud_response(cpid, group_url):
    """Generate mock NetCloud response from database"""
    # Look up group by URL in CradlepointDevice_Group
    cursor.execute("""
        SELECT GroupID, Name FROM CradlepointDevice_Group
        WHERE URL = %s
    """, (group_url,))
    group = cursor.fetchone()

    return {
        "id": cpid,
        "group": {
            "id": group["GroupID"],
            "name": group["Name"],
            "resource_url": group_url
        }
    }
```

**Benefits:**
- All hotspots can be tested in dev/QA without whitelist
- Tests focus on business logic, not NetCloud connectivity
- Faster test execution (no API latency)
- No risk to production NetCloud data
- CradlepointDevice_Group table becomes the mock data source

### 4. Implementation Path for Mock Mode

**Phase 1: Database Preparation**
1. Ensure `CradlepointDevice_Group` has all necessary groups populated
2. Add sync procedure to keep table updated when groups are created

**Phase 2: Lambda Modification**
```python
# main.py modifications

MOCK_NETCLOUD = os.environ.get("MOCK_NETCLOUD", "false").lower() == "true"

# Replace whitelist check (lines 418-490)
if ENV_VAR != "prod":
    if MOCK_NETCLOUD:
        # Skip whitelist check entirely in mock mode
        execute_qa_request = True
    else:
        # Existing whitelist validation
        ...
```

**Phase 3: Testing Infrastructure**
```yaml
# terraform/environments/dev.tfvars
mock_netcloud = true

# terraform/environments/qa.tfvars
mock_netcloud = false  # QA still uses real NetCloud with whitelist
```

### 5. Complete Mock Implementation Example

```python
# lambdas/lf-vero-prod-cradlepoint/mock_netcloud.py

class MockNetCloud:
    """Mock NetCloud API for dev/test environments"""

    def __init__(self, db_cursor):
        self.cursor = db_cursor

    def get_cradlepoint_data(self, mac):
        """Return device data from MySQL, simulating NetCloud response"""
        self.cursor.execute("""
            SELECT cd.*, cg.GroupID, cg.Name as GroupName, cg.URL as GroupURL
            FROM CradlepointDevice cd
            LEFT JOIN CradlepointDevice_Group cg
                ON cd.CradlepointDeviceGroupID = cg.CradlepointDeviceGroupID
            WHERE cd.MAC = %s
        """, (mac,))
        device = self.cursor.fetchone()

        if not device:
            return None

        return {
            "id": device["ExternalCradlepointID"] or hash(mac) % 1000000,
            "mac": mac,
            "description": device["Notes"] or "",
            "group": {
                "id": device["GroupID"],
                "name": device["GroupName"],
                "resource_url": device["GroupURL"]
            } if device["GroupID"] else None
        }

    def update_cradlepoint(self, cpid, extfid, group_url):
        """Update device group in MySQL only, simulating NetCloud update"""
        # Look up group by URL
        self.cursor.execute("""
            SELECT CradlepointDeviceGroupID, GroupID, Name
            FROM CradlepointDevice_Group WHERE URL = %s
        """, (group_url,))
        group = self.cursor.fetchone()

        if group:
            # Update device's group reference
            self.cursor.execute("""
                UPDATE CradlepointDevice
                SET CradlepointDeviceGroupID = %s,
                    GroupName = %s,
                    Notes = %s,
                    DateUpdated = NOW()
                WHERE ExternalCradlepointID = %s
            """, (group["CradlepointDeviceGroupID"], group["Name"], extfid, cpid))

        return {"success": True, "group": group}
```

---

## Testing Implications

### Current QA Testing Constraints

| Test Scenario | Can Test? | Constraint |
|---------------|-----------|------------|
| Add hotspot to facility | Only 6 devices | Whitelist |
| Remove hotspot from facility | Only 6 devices | Whitelist |
| Create new group | Yes | No MAC involved |
| Update group WiFi | Yes | No MAC involved |
| View hotspot list | Yes | MySQL-only |
| Work order with hotspots | Partial | Whitelist for add/remove |

### With Mock NetCloud Mode

| Test Scenario | Can Test? | Constraint |
|---------------|-----------|------------|
| Add hotspot to facility | **All devices** | None |
| Remove hotspot from facility | **All devices** | None |
| Create new group | Yes | Needs DB sync |
| Update group WiFi | Simulated | Mock only |
| View hotspot list | Yes | MySQL-only |
| Work order with hotspots | **Full workflows** | None |

---

## Code References

### NetCloud API Integration
- `lambdas/lf-vero-prod-cradlepoint/main.py:166-173` - API headers
- `lambdas/lf-vero-prod-cradlepoint/main.py:175-188` - `get_cradlepoint_data()`
- `lambdas/lf-vero-prod-cradlepoint/main.py:292-307` - `update_cradlepoint()`
- `lambdas/lf-vero-prod-cradlepoint/main.py:236-275` - `create_netcloud_group()`
- `lambdas/lf-vero-prod-cradlepoint/main.py:861-973` - `addBulkFacilityCradlepoints`

### Database Schema
- `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:498-530` - CradlepointDevice table
- `mysql/db/table_change_scripts/V20251121_222840__IWA-14010_Add_CradlepointDevice_Group_Table.sql:16-30` - CradlepointDevice_Group table

### Stored Procedures
- `mysql/db/procs/R__PROC_Cradlepoint_GetGroups.sql:1-15` - Get groups for UI
- `mysql/db/procs/R__PROC_Cradlepoint_AddCradlepoint.sql:1-167` - Add/update device
- `mysql/db/procs/R__PROC_Cradlepoint_RemoveCradlepoint.sql:1-66` - Remove device

### Frontend Components
- `frontend/src/components/common/forms/Statuses.tsx:404-448` - InventoryHotspotGroupSelection
- `frontend/src/hooks/services/hotspots/useGetHotspotGroups.ts:1-34` - Groups hook
- `frontend/src/components/CustomerDetailPage/Hotspots/AddHotspot.tsx:587-597` - Add modal

### Whitelist Implementation
- `frontend/src/components/common/CheckQA.ts:112-119` - Frontend whitelist
- `lambdas/lf-vero-prod-cradlepoint/main.py:25-32` - Backend whitelist
- `lambdas/lf-vero-prod-cradlepoint/main.py:418-490` - Whitelist enforcement

---

## Related Research

- `thoughts/shared/research/2026-01-08-hardware-whitelist-system.md` - Comprehensive whitelist documentation

---

## Open Questions

1. **CradlepointDevice_Group population**: How is this table currently populated? Is there a sync job or manual process?

2. **Group deletion**: What happens when a group is deleted in NetCloud? Is there a process to mark it inactive in `CradlepointDevice_Group`?

3. **Mock mode scope**: Should mock mode only apply to dev, or also to QA? QA might need real NetCloud for some integration tests.

4. **Migration path**: For the FK normalization, what's the timeline and how do we handle devices with GroupName values not in `CradlepointDevice_Group`?

5. **Performance impact**: Will the FK lookup add latency to high-volume operations? Should we consider caching strategies?
