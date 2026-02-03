---
date: 2026-02-03T13:55:22-0500
researcher: aw-jwalker
git_commit: d4df633f97a07d9b0c72b0779af99d56b952d005
branch: dev
repository: fullstack.assetwatch
topic: "Hub Diagnostic Empty PartNumber Bug Investigation"
tags: [bug-investigation, hub-diagnostic, backend, lambda]
status: in-progress
last_updated: 2026-02-03
last_updated_by: aw-jwalker
type: bug_investigation
---

# Handoff: Hub Diagnostic Empty PartNumber Bug Investigation

## Task(s)

**Status: Root Cause Identified, Fix Not Yet Implemented**

Investigating a bug reported by Tracy Elsinger where `jobs-request-schedule` lambda received a malformed Hub value `"()_0015594"` causing "invalid topic" errors. The part number portion was empty parentheses `()` instead of a valid part number like `710-002`.

## Critical References

1. `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/lf-vero-prod-hub/main.py:32-48` - **ROOT CAUSE LOCATION** - `get_hub_part_number_from_id()` function
2. `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/lf-vero-prod-hub/main.py:212-231` - `update_hub_diagnostic_interval()` that constructs the malformed Hub string

## Recent changes

No code changes were made - this was an investigation session.

## Learnings

### Root Cause Identified

The bug originates in the **backend Lambda** `lf-vero-prod-hub/main.py`, NOT the frontend.

**Flow:**
1. User adds a hub via "Add Hub" modal on Customer Detail page (`/customers/{id}/hubs`)
2. Backend `addHub` handler (line 837) processes the request
3. It calls `get_hub_part_number_from_id(jsonBody["partID"])` (line 877)
4. If the query returns no results, the function returns the **original query result** (empty list/tuple) instead of handling the error
5. `update_hub_diagnostic_interval()` (line 888-890) constructs: `"Hub": str(pn) + "_" + str(hsn)`
6. If `pn` is an empty tuple `()`, then `str(())` = `"()"`, producing `"()_0015594"`

**The Bug in `get_hub_part_number_from_id()`** (lines 32-48):
```python
def get_hub_part_number_from_id(hub_part_id):
    localHubPartNum = db.mysql_read(...)
    if len(localHubPartNum) == 1:
        localHubPartNum = localHubPartNum[0]["PartNumber"]
    else:
        print("error retrieving hub part number")
        # BUG: Returns the raw db result (empty list/tuple) instead of None or raising an error!
    return localHubPartNum
```

### Database Findings

- Serial number `0015594` has **TWO Transponder records**:
  - TransponderID 97386 → PartID 4 → `710-002` (Hub 2.0)
  - TransponderID 105508 → PartID 37 → `710-200` (Hub 3.0)
- The PartNumber values in the database are valid (`710-002`, `710-200`) - the issue is the lookup failing
- User (UserID 8786) was on the "Add Hub" modal at 16:20:48 UTC, error occurred at 16:22:01 UTC

### User Activity (from UserPathLog)

The user was actively adding/removing hubs and hotspots on customer `df491f55-d0bd-434f-8173-77737397e79f`. The error occurred during an "Add Hub" operation.

## Artifacts

- This handoff document

## Action Items & Next Steps

1. **Verify the return type of `db.mysql_read()`** - Check if it returns a tuple `()` or list `[]` when no results are found. This determines whether `str()` produces `"()"` or `"[]"`.
   - Check: `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/lf-vero-prod-hub/db_resources.py`

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
