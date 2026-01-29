# Implementation Plan: IWA-13437 AddHubs Hotspot Movement Bug Fix

**Date**: 2025-12-01
**Author**: Jackson Walker
**Ticket**: IWA-13437
**Branch**: IWA-13437

## Problem Summary

When using the "Add Hubs" button on CustomerDetail/Hubs tab to move a hub that is in an enclosure with an S400 hotspot, the hub moves but the hotspot does NOT move.

### Root Cause Analysis

**Three interconnected issues:**

1. **Frontend Group Filter Bug** (AddHubs.tsx:555)
   - `InventoryHotspotGroupSelection` is hardcoded to filter by `productId={Product.CRADLEPOINT}` (value: 5, IBR200)
   - S400 hotspots have ProductID 33, so S400-compatible NetCloud groups are filtered out
   - Users can only select IBR200 groups, even for S400 hotspots

2. **Missing ProductID in Response** (SQL proc)
   - `Enclosure_GetHubHotspotWithEnclosureInfo` returns `cradlepointPartId` but not `cradlepointProductId`
   - Frontend cannot determine which ProductID to use for group filtering

3. **Silent NetCloud API Failure** (Lambda main.py:901-903)
   - When NetCloud API rejects the group assignment (wrong model), the error is ignored
   - Lambda continues with database updates even though NetCloud operation failed
   - Hub moves in database, hotspot doesn't move in NetCloud or database

### Database Reference

| PartID | PartNumber | Model | ProductID |
|--------|------------|-------|-----------|
| 30 | 500-101 | IBR200 | 5 |
| 52 | 500-103 | S400 | 33 |

## Implementation Plan

### Fix 1: Add cradlepointProductId to SQL and Types

**File**: `mysql/db/procs/R__PROC_Enclosure_GetHubHotspotWithEnclosureInfo.sql`

**Change**: Add JOIN to Part table and include ProductID in SELECT:

```sql
SELECT
    t.TransponderID AS transponderId,
    cp.CradlepointDeviceID AS cradlepointDeviceId,
    e.SerialNumber AS enclosureSerialNumber,
    t.SerialNumber AS transponderSerialNumber,
    e.PartID AS enclosurePartId,
    t.EnclosureID AS enclosureId,
    cp.MAC AS cradlepointMac,
    cp.PartID AS cradlepointPartId,
    cpPart.ProductID AS cradlepointProductId,  -- ADD THIS
    t.PartID AS transponderPartId
FROM
    Transponder t
    LEFT JOIN Enclosure e ON e.EnclosureID = t.EnclosureID
    LEFT JOIN CradlepointDevice cp ON e.EnclosureID = cp.EnclosureID
    LEFT JOIN Part cpPart ON cp.PartID = cpPart.PartID  -- ADD THIS JOIN
WHERE
    (find_in_set(t.SerialNumber, inSerialIDList)
    OR FIND_IN_SET(cp.MAC, inCpMacList))
    AND t.EnclosureID IS NOT NULL
    AND cp.EnclosureID IS NOT NULL
    AND e.PartID IN (42, 49, 53);
```

**File**: `frontend/src/shared/types/hubs/EnclosureComponentInfo.ts`

**Change**: Add cradlepointProductId field:

```typescript
export interface EnclosureComponentInfo {
  transponderId: number | null;
  cradlepointDeviceId: number | null;
  enclosureSerialNumber: string | null;
  transponderSerialNumber: string | null;
  cradlepointMac: string | null;
  enclosurePartId: number | null;
  enclosureId: number | null;
  cradlepointPartId: number | null;
  cradlepointProductId: number | null;  // ADD THIS
  transponderPartId: number | null;
}
```

### Fix 2: Update AddHubs.tsx Group Filtering

**File**: `frontend/src/components/CustomerDetailPage/Hubs/AddHubs.tsx`

**Changes**:

1. Add state to track the hotspot's ProductID:
```typescript
const [hotspotProductId, setHotspotProductId] = useState<number | null>(null);
```

2. Update the onSubmit function to capture ProductID when enclosure info is retrieved:
```typescript
if (hubsHotspotWithEnclosure.length > 0 && !continueMove) {
  setHubsWithEnclosureInfo(
    hubsHotspotWithEnclosure.map((h) => h.transponderSerialNumber!),
  );
  setHotspotEnclosureInfo(
    hubsHotspotWithEnclosure.map((h) => h.cradlepointMac!),
  );
  // Capture the ProductID from the first enclosure (they should all be same model)
  const productId = hubsHotspotWithEnclosure[0]?.cradlepointProductId;
  setHotspotProductId(productId ?? null);
  setShowGroupNameDropdown(true);
  return setIsAlertModalOpen(true);
}
```

3. Update the InventoryHotspotGroupSelection to use dynamic ProductID:
```typescript
<InventoryHotspotGroupSelection
  groupList={completeGroupList}
  groupID={netCloudGroupId ?? ""}
  netcloudGroupListDidLoad={!!completeGroupList}
  setGroupID={setNetCloutGroupId}
  productId={hotspotProductId ?? Product.CRADLEPOINT}  // Use actual ProductID
/>
```

### Fix 3: Add Lambda Error Handling

**File**: `lambdas/lf-vero-prod-cradlepoint/main.py`

**Change** in `addBulkFacilityCradlepoints` function (around line 900):

```python
# step 2: update the description field on NetCloud with the external facility id
update_cp_data = update_cradlepoint(
    old_cp_data["id"], jsonBody["extfid"], jsonBody["gurl"]
)

# ADD ERROR HANDLING
if update_cp_data is None or (isinstance(update_cp_data, dict) and "error" in update_cp_data):
    error_msg = update_cp_data.get("error", "Unknown error") if isinstance(update_cp_data, dict) else "NetCloud API call failed"
    return {
        "statusCode": 400,
        "body": json.dumps({"error": f"Failed to update hotspot in NetCloud: {error_msg}"})
    }
```

Also verify the `update_cradlepoint` function returns proper error info when NetCloud API fails.

## Testing Plan

### Test Case 1: S400 Hotspot Movement (Primary Bug Fix)
1. Find a hub in enclosure with S400 hotspot (PartID 52)
2. Use "Add Hubs" to move to different facility
3. Verify S400 groups appear in dropdown (not just IBR200)
4. Select S400 group and save
5. Verify both hub AND hotspot moved to new facility

### Test Case 2: IBR200 Hotspot Movement (Regression)
1. Find a hub in enclosure with IBR200 hotspot (PartID 30)
2. Use "Add Hubs" to move to different facility
3. Verify IBR200 groups appear in dropdown
4. Select IBR200 group and save
5. Verify both hub AND hotspot moved to new facility

### Test Case 3: NetCloud Error Handling
1. Intentionally trigger NetCloud error (wrong group type)
2. Verify operation fails with clear error message
3. Verify neither hub nor hotspot moved (transaction rollback)

### Test Case 4: Mixed Model Warning
1. If moving multiple hubs with different hotspot models
2. Verify user sees appropriate warning about model types

## Files Modified

1. `mysql/db/procs/R__PROC_Enclosure_GetHubHotspotWithEnclosureInfo.sql`
2. `frontend/src/shared/types/hubs/EnclosureComponentInfo.ts`
3. `frontend/src/components/CustomerDetailPage/Hubs/AddHubs.tsx`
4. `lambdas/lf-vero-prod-cradlepoint/main.py`

## Risks & Considerations

1. **Database Migration**: SQL proc change is backward compatible (adds new column)
2. **Lambda Error Handling**: May surface previously hidden errors to users - this is intentional
3. **Multiple Hotspot Models**: If user moves multiple hubs with mixed IBR200/S400 hotspots, current UI only shows one dropdown - may need additional handling

## Out of Scope (Separate PRs)

1. Photo deletion bug in `Transponder_AddTransponder_Notes.sql` (Part 1 of ticket)
2. Hub movement consistency across other locations (HubCheckTab, MoveHubsNextStepModal, etc.)
