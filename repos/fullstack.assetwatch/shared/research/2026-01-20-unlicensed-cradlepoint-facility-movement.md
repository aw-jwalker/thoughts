---
date: 2026-01-20T15:45:04-05:00
researcher: Jackson Walker
git_commit: 35bb96c8a286eb1705ca2dd97fea4b5f4c8cc648
branch: dev
repository: fullstack.assetwatch
topic: "Unlicensed CradlePoint Facility Movement Blocking"
tags: [research, codebase, cradlepoint, netcloud, facility-movement, hotspots]
status: complete
last_updated: 2026-01-20
last_updated_by: Jackson Walker
---

# Research: Unlicensed CradlePoint Facility Movement

**Date**: 2026-01-20T15:45:04-05:00
**Researcher**: Jackson Walker
**Git Commit**: 35bb96c8a286eb1705ca2dd97fea4b5f4c8cc648
**Branch**: dev
**Repository**: fullstack.assetwatch

## Problem Summary

Field technicians cannot remove unlicensed CradlePoints from customer facilities in AssetWatch. The system requires a NetCloud API lookup to move hotspots between facilities, but unlicensed devices return empty results from NetCloud, blocking the operation.

**Impact**: ~2,400 hotspots are currently unlicensed. Technicians cannot remove old/damaged hardware from customer sites without temporarily licensing the device first.

## Technical Root Cause

### NetCloud API Behavior

When querying the NetCloud API at `/api/v2/routers/?expand=group&mac={MAC}`:
- **Licensed devices**: Return device data with group information
- **Unlicensed devices**: Return empty array `{"data": []}`

The current code treats empty results as "device not found" and blocks the operation.

### Detection Logic (Validated)

**File**: `lambdas/lf-vero-prod-cradlepoint/main.py:175-188`
```python
def get_cradlepoint_data(MAC):
    cp_url = "https://cradlepointecm.com/api/v2/routers/?expand=group&mac=" + apiMAC
    cradlepoint_data = common_resources.CallAPI(...)

    if cradlepoint_data["data"] is None or (isinstance(cradlepoint_data["data"], list) and len(cradlepoint_data["data"]) == 0):
        return None  # Triggers 404 error downstream

    return cradlepoint_data["data"][0]
```

### Error Response (Validated)

**File**: `lambdas/lf-vero-prod-cradlepoint/main.py:323`
```python
cradlepoint_not_found_error = { "error": "No Cradlepoint data found or Cradlepoint is unlisted in Netcloud"}
```

This error is returned at multiple locations: lines 553-556, 662-663, 773-774, 874-875.

## Current Status System (Validated)

### CradlepointDeviceStatus (Device-Level)
| ID | Name |
|----|------|
| 1 | Spare |
| 2 | In Transit |

**Source**: `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:558-562`

### FacilityCradlepointDeviceStatus (Facility Assignment)
| ID | Name |
|----|------|
| 1 | Assigned |
| 2 | Removed |
| 3 | Ready to Install |
| 4 | In Transit to HQ |

**Source**: `lambdas/tests/db/dockerDB/init_scripts/init_enum_tables.sql:235-241`

**Key Finding**: There is NO existing "Unlicensed", "Inactive", "Offline", or "Active" status in either table.

## EASE Automation Precedent (Validated)

The EASE/3PL automation (`updateNetcloudCradlepointFacility`) handles partial failures gracefully:

**File**: `lambdas/lf-vero-prod-cradlepoint/main.py:1043-1087`

```python
elif meth == "updateNetcloudCradlepointFacility":
    for i in range(len(inCPList)):
        old_cp_data = get_cradlepoint_data(macCP)

        if old_cp_data is None:
            failed_count += 1
            failed_macs.append(macCP)
            continue  # Skips unlicensed, continues with others

        update_response = update_cradlepoint(old_cp_data["id"], jsonBody["externalFacilityID"], jsonBody["groupURL"])
```

**Key Difference**: EASE continues processing other hotspots when one fails, tracking failures separately. Standard operations (`addBulkFacilityCradlepoints`) fail-fast and stop on the first missing device.

## NetCloud API Capabilities

Based on [NetCloud API documentation](https://developer.cradlepoint.com/):

**Routers Endpoint Fields**:
- `mac` - MAC address (supports `mac__in` filtering)
- `state` - Device operational state
- `state_updated_at` - Last state change timestamp
- `id`, `name`, `serial_number` - Device identifiers

**License Detection Limitation**: The NetCloud API does not expose a `license_status` field. Unlicensed devices simply don't appear in query results, which is why detecting them requires checking for empty responses.

## Potential Solutions

### Option A: Add "Unlicensed" Status (Proposed in Slack)

Add a new status to track devices that fail NetCloud lookup:

1. Add `CradlepointDeviceStatus` value: `(3, 'Unlicensed')`
2. When `get_cradlepoint_data()` returns `None` for a **known** device (exists in DB), update status to "Unlicensed"
3. Allow facility movements for "Unlicensed" devices to inventory facilities only
4. Skip NetCloud group update for unlicensed devices (nothing to update)

**Pros**: Explicit tracking, queryable status, clear audit trail
**Cons**: Requires DB migration, new sync logic, status maintenance

### Option B: Bypass NetCloud for Inventory Movements (Brandon's suggestion)

Allow movements without NetCloud lookup when:
- Device already exists in AssetWatch DB
- Destination is an inventory facility (not live customer)

**Pros**: Simpler implementation, no new status needed
**Cons**: Less visibility into which devices are unlicensed

### Option C: Hybrid Approach

Combine both: track "Unlicensed" status AND allow inventory movements:

1. When NetCloud returns empty for known device, set status to "Unlicensed"
2. For movements TO inventory: allow regardless of NetCloud status
3. For movements TO customer: require valid NetCloud license
4. Display "Unlicensed" status in UI for visibility

## Code References

| Component | Location |
|-----------|----------|
| NetCloud API lookup | `lambdas/lf-vero-prod-cradlepoint/main.py:175-188` |
| Error response | `lambdas/lf-vero-prod-cradlepoint/main.py:323` |
| Update function | `lambdas/lf-vero-prod-cradlepoint/main.py:292-307` |
| Bulk facility assignment | `lambdas/lf-vero-prod-cradlepoint/main.py:861-973` |
| EASE automation | `lambdas/lf-vero-prod-cradlepoint/main.py:1043-1087` |
| Status enum (frontend) | `frontend/src/shared/enums/FacilityHardwareStatus.ts:16-21` |
| Status table init | `lambdas/tests/db/dockerDB/init_scripts/init_enum_tables.sql:188-194, 235-241` |

## Related Research

- `thoughts/shared/research/2026-01-08-netcloud-groups-management.md` - NetCloud groups architecture
- `thoughts/shared/research/2026-01-19-wifi-tab-netcloud-groups-bug-investigation.md` - NetCloud data flow
- `thoughts/shared/research/2026-01-08-hardware-whitelist-system.md` - QA whitelist limitations

## Open Questions

1. Should "Unlicensed" be a CradlepointDeviceStatus or FacilityCradlepointDeviceStatus?
2. How frequently should we sync license status from NetCloud?
3. Should we expose unlicensed count in admin dashboards?
4. What notification should trigger when a device becomes unlicensed?
