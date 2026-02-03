---
date: 2026-02-03T13:55:22-0500
researcher: aw-jwalker
git_commit: d4df633f97a07d9b0c72b0779af99d56b952d005
branch: dev
repository: fullstack.assetwatch
topic: "Hub Diagnostic Empty PartNumber Bug Investigation"
tags: [bug-investigation, hub-diagnostic, backend, lambda]
status: completed
last_updated: 2026-02-03
last_updated_by: aw-jwalker
type: bug_investigation
---

# Handoff: Hub Diagnostic Empty PartNumber Bug Investigation

## Task(s)

**Status: Fix Implemented**

Investigating a bug reported by Tracy Elsinger where `jobs-request-schedule` lambda received a malformed Hub value `"()_0015594"` causing "invalid topic" errors. The part number portion was empty parentheses `()` instead of a valid part number like `710-002`.

## Critical References

1. `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/lf-vero-prod-hub/main.py:32-48` - **ROOT CAUSE LOCATION** - `get_hub_part_number_from_id()` function
2. `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/lf-vero-prod-hub/main.py:212-231` - `update_hub_diagnostic_interval()` that constructs the malformed Hub string

## Recent changes

### Fix Implemented (2026-02-03)

**File:** `lambdas/lf-vero-prod-hub/main.py`

1. **Fixed `get_hub_part_number_from_id()` (lines 32-49):**
   - Changed to return `None` when no part number is found instead of returning the empty database result
   - Added more detailed error logging including the `partID` and result count

2. **Added validation in `addHub` handler (lines 881-893):**
   - Added check `if HubPartNumber is None` before calling downstream functions
   - Logs an error and skips `sync_hub_schedules()` and `update_hub_diagnostic_interval()` when part number lookup fails
   - Prevents malformed Hub strings like `"()_0015594"` from being sent to the jobs-request-schedule lambda

## Learnings

### Complete Root Cause Analysis

The bug is a **multi-layer failure** spanning both frontend and backend:

#### Layer 1: Frontend Missing Validation

**File:** `apps/frontend/src/components/CustomerDetailPage/Hubs/AddHubs.tsx`

1. `PartSelect` component (line 526) is `clearable`, allowing users to clear the part number selection
2. When cleared, `onPartSelected` receives `null`, converted to empty string `""` (line 531)
3. The SaveModal `disabled` condition (lines 494-500) does NOT check for empty `selectedPartNumber`:
   ```typescript
   disabled={
     Object.values(errors).some((val) => val === true) ||
     validSerialNumbers.length === 0 ||
     notes.length === 3000 ||
     hubStatusID === "" ||
     selectedFacilityId === ""
     // MISSING: selectedPartNumber === ""
   }
   ```
4. **Result:** User can submit form with `partID: ""` (empty string)

#### Layer 2: TypeScript Type Missing

**File:** `apps/frontend/src/shared/api/HubService.ts:417-424`

The `assignHub` function interface doesn't include `partID`:
```typescript
export async function assignHub(hubDetails: {
  hubList: string;
  facilityID: string;
  hubStatusID: string;
  locationNotes: string;
  removalReason: number;
  workOrderBOMID: number;
  // partID is MISSING - no compile-time check!
})
```

#### Layer 3: Backend Missing Validation

**File:** `lambdas/lf-vero-prod-hub/main.py`

1. `addHub` handler (line 878) calls `get_hub_part_number_from_id(jsonBody["partID"])` without validating partID
2. The function's SQL query: `SELECT PartNumber FROM Part WHERE PartID='{hub_part_id}'`
3. With empty string: `WHERE PartID=''` → MySQL coerces to `WHERE PartID=0` → No match

#### Layer 4: Poor Error Handling (FIXED)

**Original Bug:** `get_hub_part_number_from_id()` returned the raw empty db result instead of `None`
- Empty tuple `()` stringified to `"()"` → malformed Hub `"()_0015594"`

### Why the Part Lookup Failed

**Most Likely Scenario:**
1. User opened "Add Hub" modal (default partID = "4")
2. User cleared the Part Number dropdown (partID → "")
3. User clicked Save (validation didn't block submission)
4. Backend received `partID: ""`
5. SQL: `SELECT PartNumber FROM Part WHERE PartID=''` returned empty
6. Function returned empty tuple → `"()_0015594"`

### Database Findings

- Serial number `0015594` has **TWO Transponder records**:
  - TransponderID 97386 → PartID 4 → `710-002` (Hub 2.0)
  - TransponderID 105508 → PartID 37 → `710-200` (Hub 3.0)
- The PartNumber values in the database are valid - the lookup failed because `partID` was empty, NOT because the data was missing
- User (UserID 8786) was on the "Add Hub" modal at 16:20:48 UTC, error occurred at 16:22:01 UTC

### User Activity (from UserPathLog)

The user was actively adding/removing hubs and hotspots on customer `df491f55-d0bd-434f-8173-77737397e79f`. The error occurred during an "Add Hub" operation.

## Artifacts

- This handoff document

## Action Items & Next Steps

### Completed ✅

1. **Backend Fix: `get_hub_part_number_from_id()`** - Now returns `None` instead of empty tuple when lookup fails
2. **Backend Fix: `addHub` handler validation** - Added check for `HubPartNumber is None` before calling downstream functions
3. **Verified `db.mysql_read()` return type** - Uses `pymysql.cursors.DictCursor` with `fetchall()`, returns tuple (empty `()` when no results)

### Remaining (Frontend Fixes)

1. **Add frontend validation** - Add `selectedPartNumber === ""` to SaveModal disabled condition in `AddHubs.tsx`
2. **Fix TypeScript interface** - Add `partID: string` to `assignHub` function interface in `HubService.ts`
3. **Consider removing `clearable`** from PartSelect in AddHubs, or add required indicator

2. **Fix `get_hub_part_number_from_id()`** - The function should:
   - Return `None` or raise an exception when no part number is found
   - NOT return the raw database query result

3. **Add validation in `update_hub_diagnostic_interval()`** - Before constructing the Hub string, validate that `pn` is a valid string part number

4. **Add validation in `addHub` handler** - Before calling `update_hub_diagnostic_interval()`, check that `HubPartNumber` is valid (line 877-890)

5. **Investigate why the part lookup failed** - The `partID` passed from frontend should be valid (e.g., `4` for `710-002`). Why did the query `SELECT PartNumber FROM Part WHERE PartID='...'` return no results?

6. **Consider the duplicate serial number situation** - Two transponders with same serial `0015594` but different part numbers could cause confusion

## Other Notes

### Key Files

- Frontend "Add Hub" component: `/home/aw-jwalker/repos/fullstack.assetwatch/apps/frontend/src/components/CustomerDetailPage/Hubs/AddHubs.tsx`
- Backend hub lambda: `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/lf-vero-prod-hub/main.py`
- Hub diagnostic lambda: `/home/aw-jwalker/repos/assetwatch-jobs/terraform/jobs/request_v2/request-hub-diagnostic/main.py`

### Error Details from Tracy's Report

```json
{
  "RequestType": "HubDiagnostic",
  "Hub": "()_0015594",
  "DiagnosticInterval": 360,
  "User": "d16b9d27-096d-4586-af06-f7c6774b393c",
  "RQID": 1770135721
}
```

- RQID `1770135721` = 2026-02-03 16:22:01 UTC = 11:22:01 AM EST
- User: lmezreb@assetwatch.com (UserID 8786)
- `DiagnosticInterval: 360` indicates the facility diagnostic flag was OFF (360 = default, 15 = diagnostic mode)

### Database Timezone

- MySQL server timezone: `SYSTEM` (UTC on AWS RDS)
- CloudWatch logs: UTC by default
- RQID timestamps: UTC Unix timestamps
