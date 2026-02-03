---
date: 2026-02-03T17:30:00-0500
researcher: aw-jwalker
git_commit: 3c5ebe7271027f0eb17f206e0233c574c76c91ee
branch: dev
repository: fullstack.assetwatch
topic: "Hub Diagnostic Empty PartNumber Bug - Backend Fix Implementation"
tags: [bug-fix, hub-diagnostic, backend, lambda, validation]
status: partial-complete
last_updated: 2026-02-03
last_updated_by: aw-jwalker
type: bug_fix
---

# Handoff: Hub Diagnostic Empty PartNumber Bug - Backend Fix

## Task(s)

**Primary Task:** Fix bug where malformed Hub values like `"()_0015594"` are sent to jobs-request-schedule lambda, causing "invalid topic" errors.

**Status:**
- ✅ **Backend fixes implemented** (not yet committed)
- ⏳ **Frontend fixes pending** (identified but not implemented)
- ⏳ **Production testing in progress** (user was preparing to reproduce bug with serial 0006436)

## Critical References

1. **Original Investigation Handoff:** `/home/aw-jwalker/repos/thoughts/shared/handoffs/general/2026-02-03_13-55-22_hub-diagnostic-empty-partnumber-bug.md`
   - Contains complete root cause analysis and database findings
   - Documents the original bug report from Tracy Elsinger (RQID 1770135721, serial 0015594)

2. **Backend Lambda:** `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/lf-vero-prod-hub/main.py`
   - Lines 32-49: `get_hub_part_number_from_id()` function (FIXED)
   - Lines 878-893: `addHub` handler validation (FIXED)

3. **Frontend Add Hub Modal:** `/home/aw-jwalker/repos/fullstack.assetwatch/apps/frontend/src/components/CustomerDetailPage/Hubs/AddHubs.tsx`
   - Lines 494-500: SaveModal disabled validation (NEEDS FIX)
   - Line 526: PartSelect component usage (clearable)

## Recent Changes

**Backend fixes (uncommitted):**

1. `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/lf-vero-prod-hub/main.py:32-49`
   - Modified `get_hub_part_number_from_id()` to return `None` instead of empty tuple when lookup fails
   - Added detailed error logging with partID and result count

2. `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/lf-vero-prod-hub/main.py:881-893`
   - Added validation check `if HubPartNumber is None` before calling downstream functions
   - Prevents malformed Hub strings from being sent to jobs-request-schedule lambda

## Learnings

### Root Cause: Multi-Layer Failure

The bug was introduced on **October 3, 2024** (commit 119ec8bb2) when a safety guard was removed from `PartSelect` component.

#### Git History Finding
- **Original code** (Feb 7, 2024): Had `clearable` but with guard: `onChange={(value) => value && onPartSelected(value)}`
- **Bug introduced** (Oct 3, 2024): Guard removed: `onChange={(value) => onPartSelected(value)}`
- **Result:** Clearing the field now passes `null` → parent converts to `""` → no validation blocks submission

#### Four-Layer Failure Chain

1. **Frontend validation gap:** SaveModal doesn't check for empty `selectedPartNumber`
2. **TypeScript type gap:** `assignHub` function interface missing `partID` field
3. **Backend validation gap:** `addHub` handler doesn't validate partID before use
4. **Poor error handling:** `get_hub_part_number_from_id()` returned raw empty result → `str(())` = `"()"`

### Key Technical Details

- `db.mysql_read()` uses `pymysql.cursors.DictCursor` with `fetchall()` → returns tuple (empty `()` when no results)
- SQL with empty string: `WHERE PartID=''` → MySQL coerces to `WHERE PartID=0` → No match
- `PartSelect` component has `clearable` hardcoded, affecting all 16 consumers across codebase

## Artifacts

1. **Investigation handoff:** `/home/aw-jwalker/repos/thoughts/shared/handoffs/general/2026-02-03_13-55-22_hub-diagnostic-empty-partnumber-bug.md`
2. **Modified files (uncommitted):**
   - `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/lf-vero-prod-hub/main.py`
3. **Task tracking:**
   - Task #3: Add frontend validation to prevent empty partID submission
   - Task #4: Add partID to assignHub TypeScript interface

## Action Items & Next Steps

### Immediate (Before Committing)

1. **Complete production testing** - User was preparing to test with serial 0006436 to reproduce bug
   - Monitor CloudWatch logs for the reproduction
   - Verify backend fix prevents malformed Hub string

2. **Implement frontend fixes:**
   - **Task #3:** Add `selectedPartNumber === ""` to disabled condition in `AddHubs.tsx:494-500`
   - **Task #4:** Add `partID: string` to `assignHub` interface in `apps/frontend/src/shared/api/HubService.ts:417-424`

3. **Consider `clearable` behavior:**
   - Either remove `clearable` from PartSelect (breaking change for 16 consumers)
   - Or make it a configurable prop with sensible defaults
   - Or add explicit "required" validation where needed

### Before Merging

4. **Create feature branch** - Changes currently on `dev` branch
5. **Test all PartSelect consumers** - Verify none have similar validation gaps:
   - `AddHotspot.tsx`
   - `ModalSensorAddSpare.tsx`
   - `CreateEnclosure.tsx` / `EditEnclosure.tsx`
   - `AddHardwareForm.tsx`
   - Others (16 total files)

6. **Add tests** - Consider adding:
   - Backend unit test for `get_hub_part_number_from_id()` with empty partID
   - Frontend test for AddHubs modal validation

## Other Notes

### Related Files & Components

- **PartSelect component:** `/home/aw-jwalker/repos/fullstack.assetwatch/apps/frontend/src/components/PartSelect.tsx`
  - Used in 16 places across codebase
  - `clearable` hardcoded on line 62

- **Database stored proc:** `/home/aw-jwalker/repos/fullstack.assetwatch/mysql/db/procs/R__PROC_Transponder_AddTransponder_Notes.sql`
  - Line 91: Uses `t.PartID = inPartID` (expects INT, gets empty string)

- **Hub diagnostic lambda:** `/home/aw-jwalker/repos/assetwatch-jobs/terraform/jobs/request_v2/request-hub-diagnostic/main.py`
  - Receives malformed Hub string `"()_0015594"`

### Original Bug Report Context

- **Reporter:** Tracy Elsinger
- **RQID:** 1770135721 (2026-02-03 16:22:01 UTC)
- **User:** lmezreb@assetwatch.com (UserID 8786)
- **Serial:** 0015594 (has TWO transponder records: PartID 4 and 37)
- **Customer:** df491f55-d0bd-434f-8173-77737397e79f

### AWS/CloudWatch Notes

- User attempted to set up CloudWatch log monitoring but encountered permission/configuration issues
- May need proper AWS CLI configuration or log group identification for production lambda monitoring
