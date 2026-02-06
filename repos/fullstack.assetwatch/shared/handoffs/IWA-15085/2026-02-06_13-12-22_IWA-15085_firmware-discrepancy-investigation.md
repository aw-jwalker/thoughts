---
date: 2026-02-06T13:12:22-0500
researcher: aw-jwalker
git_commit: aef6609646df1ec10108205f749be14f7d84fce3
branch: dev
repository: fullstack.assetwatch
topic: "Firmware FirmwareID Discrepancy and FirmwareVersion Update Bug Investigation"
tags: [firmware, investigation, data-cleanup, lazy-loader, receiver-table]
status: complete
last_updated: 2026-02-06
last_updated_by: aw-jwalker
type: investigation
---

# Handoff: IWA-15085 Firmware Discrepancy Investigation

## Task(s)

**Status: Investigation Complete - Ready for Implementation**

### Completed Tasks

1. ✅ **Researched end-to-end firmware management system**
   - Traced complete flow from upload → lazy loader → request creation → MQTT delivery → acknowledgement
   - Investigated both `fullstack.assetwatch` and `assetwatch-jobs` repositories
   - Documented all code paths and identified 5 critical failure points

2. ✅ **Identified root cause of FirmwareID discrepancy**
   - ~3000 sensors have FirmwareID=460 (2.8.0 for 710-001) instead of FirmwareID=455 (2.8.0 for 710-008)
   - Root cause: Provision process looked up firmware by Version only, not Version + PartID
   - Bug likely already fixed in provision code; requires data cleanup

3. ✅ **Investigated FirmwareVersion field not updating**
   - Confirmed `Receiver.FirmwareVersion` is NOT updated by any firmware update procedures
   - Version retrieved via FK join: `Firmware.Version` through `Receiver.FirmwareID`
   - Field appears to be legacy/unused for sensor products (ProductID 3,16)

### Next Phase

Implementation of data cleanup script and decision on FirmwareVersion field retention.

## Critical References

**Primary Research Document:**
- `thoughts/shared/research/2026-02-06-firmware-version-management-lazy-loader.md` — Complete firmware system architecture with external service flow

**Jira Ticket:**
- IWA-15085: Fix FirmwareID Discrepancy and FirmwareVersion Update Bug

**Key Stored Procedures:**
- `fullstack.assetwatch/mysql/db/procs/R__PROC_Firmware_GetSensorsToUpdate.sql` — Lazy loader targeting logic
- `assetwatch-jobs/mysql/db/procs/R__PROC_Request_AcknowledgeRequest_v2.sql` — Firmware update flow

## Recent Changes

**No code changes made** — This was a pure investigation/research session.

**Documents created:**
- `thoughts/shared/research/2026-02-06-firmware-version-management-lazy-loader.md` — Complete research document

## Learnings

### Architecture Insights

1. **Dual Firmware Fields on Receiver Table:**
   - `FirmwareID` (INT FK) — Updated on successful firmware deployment, used by lazy loader
   - `FirmwareVersion` (VARCHAR) — NOT updated for sensors, appears legacy
   - For sensors: version displayed via `SELECT Version FROM Firmware WHERE FirmwareID = Receiver.FirmwareID`

2. **Critical FirmwareID Lookup Chain:**
   ```
   Lazy Loader → FileName
   Request Lambda → SELECT FirmwareID WHERE FileName=? AND PartNumber=?
   Request Record → FirmwareID stored
   Acknowledgement → SELECT FirmwareID FROM Request
   Receiver Update → FirmwareID copied to Receiver
   ```

3. **Five Validated Failure Points:**
   - **Point A:** Lazy loader returns wrong FileName (FacilityFirmware or Part.DefaultFirmwareID misconfigured)
   - **Point B:** FirmwareID lookup fails (`firmware_common.get_firmware_id()` in jobs repo)
   - **Point C:** Request created with NULL FirmwareID
   - **Point D:** Acknowledgement lookup fails (RQID/ReceiverID mismatch)
   - **Point E:** FirmwareVersion not updated (intentional design, not a bug)

4. **External Service Architecture:**
   - EventBridge runs lazy loader every 2 minutes via `jobs_hardware` Lambda
   - `assetwatch-jobs/terraform/jobs/jobs_hardware/jobs-hardware/hardware.py:40-72` invokes request Lambda
   - `assetwatch-jobs/terraform/jobs/request_v2/request-sensor-firmware/firmware_common.py:64-78` performs critical FileName→FirmwareID lookup
   - `assetwatch-jobs/terraform/jobs/jobs_data_ingestion_firmware/jobs-data-ingestion-firmware/dataParser.py:54-96` processes acknowledgements

5. **Root Cause of Current Issue:**
   - Provision process: `assetwatch-jobs/terraform/jobs/jobs_data_ingestion_provision/` (exact file not examined)
   - Looked up firmware by `Version` only instead of `Version + PartID`
   - Query returned first match: FirmwareID=460 (710-001) instead of FirmwareID=455 (710-008)
   - All 710-008 sensors provisioned with wrong FirmwareID

### Key Patterns

- **Lazy loader scheduling:** `assetwatch-jobs/terraform/jobs/jobs_hardware/eventbridge.tf:31-57`
- **Request creation:** `assetwatch-jobs/terraform/jobs/request_v2/request-sensor-firmware/main.py:67-228`
- **Acknowledgement:** `assetwatch-jobs/terraform/jobs/jobs_data_ingestion_firmware/jobs-data-ingestion-firmware/dataParser.py:54-96`

## Artifacts

**Research Documents:**
- `thoughts/shared/research/2026-02-06-firmware-version-management-lazy-loader.md`

**Key Code Files Examined:**

*fullstack.assetwatch:*
- `mysql/db/procs/R__PROC_Firmware_GetSensorsToUpdate.sql` — Lazy loader query
- `mysql/db/procs/R__PROC_Receiver_UpdateFirmwareVersion.sql` — Updates FirmwareID only
- `mysql/db/procs/R__PROC_Request_AcknowledgeRequest.sql` — Original acknowledgement procedure
- `mysql/db/procs/R__PROC_Request_AddRequest.sql` — Creates Request records
- `mysql/db/procs/R__PROC_Sensor_GetFirmwareVersion.sql` — Reads version via FK join
- `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:2923-2973` — Receiver table schema
- `lambdas/lf-vero-prod-firmware/main.py` — Firmware CRUD Lambda

*assetwatch-jobs:*
- `terraform/jobs/jobs_hardware/eventbridge.tf:31-57` — Lazy loader schedule
- `terraform/jobs/jobs_hardware/jobs-hardware/hardware.py:32-72` — Lazy loader invocation
- `terraform/jobs/request_v2/request-sensor-firmware/main.py:67-228` — Request Lambda handler
- `terraform/jobs/request_v2/request-sensor-firmware/firmware_common.py:64-78` — FirmwareID lookup
- `terraform/jobs/jobs_data_ingestion_firmware/jobs-data-ingestion-firmware/dataParser.py:54-96` — MQTT acknowledgement processor
- `mysql/db/procs/R__PROC_Request_AcknowledgeRequest_v2.sql:298-322` — Optimized acknowledgement procedure

## Action Items & Next Steps

### Issue 1: FirmwareID Data Cleanup (High Priority)

1. **Audit all sensors with wrong FirmwareID:**
   ```sql
   -- Identify sensors with FirmwareID that doesn't match their PartID
   SELECT
       r.ReceiverID, r.SerialNumber, r.PartID, p.PartNumber,
       r.FirmwareID AS CurrentFirmwareID,
       fw.PartID AS FirmwarePartID,
       p_fw.PartNumber AS FirmwarePartNumber,
       fw.Version, fw.FileName
   FROM Receiver r
   INNER JOIN Part p ON p.PartID = r.PartID
   LEFT JOIN Firmware fw ON fw.FirmwareID = r.FirmwareID
   LEFT JOIN Part p_fw ON p_fw.PartID = fw.PartID
   WHERE r.FirmwareID IS NOT NULL
   AND p.ProductID IN (3, 16)  -- Sensors only
   AND (fw.PartID IS NULL OR fw.PartID != r.PartID);
   ```

2. **Specifically identify the 3000 affected sensors:**
   ```sql
   -- 710-008 sensors with 710-001 firmware (FirmwareID=460 instead of 455)
   SELECT COUNT(*)
   FROM Receiver r
   INNER JOIN Part p ON p.PartID = r.PartID
   WHERE p.PartNumber = '710-008'
   AND r.FirmwareID = 460;
   ```

3. **Create data cleanup script:**
   - Map wrong FirmwareID to correct FirmwareID based on Version + PartNumber
   - **IMPORTANT:** Do NOT change sensors with FirmwareID=470 (per ticket)
   - Update `Receiver.FirmwareID` where mismatch exists
   - Update `ReceiverFirmwareHistory` to reflect correction

4. **Verify provision code fix:**
   - Locate provision procedure in `assetwatch-jobs/terraform/jobs/jobs_data_ingestion_provision/`
   - Confirm firmware lookup now includes `AND pt.PartNumber = ?` clause
   - If not fixed, fix it before running data cleanup

### Issue 2: FirmwareVersion Field Decision (Medium Priority)

**Option A: Remove the field (Recommended)**
- Audit all usages of `Receiver.FirmwareVersion` in fullstack.assetwatch codebase
- Confirm it's only used for non-sensor products or never used at all
- Create migration to drop column: `ALTER TABLE Receiver DROP COLUMN FirmwareVersion;`
- Update any procedures that reference it (likely none for sensors)

**Option B: Keep and sync the field**
- Update `R__PROC_Receiver_UpdateFirmwareVersion.sql` to also update FirmwareVersion:
  ```sql
  UPDATE Receiver
  SET FirmwareID = localFirmwareID,
      FirmwareVersion = (SELECT Version FROM Firmware WHERE FirmwareID = localFirmwareID),
      _version = _version + 1
  WHERE ReceiverID = localReceiverID;
  ```
- Update `R__PROC_Request_AcknowledgeRequest_v2.sql` in jobs repo similarly
- Run backfill to sync existing records

### Verification Steps

1. **After data cleanup:**
   - Run lazy loader manually and verify affected sensors no longer targeted
   - Check CloudWatch logs for `jobs_hardware` Lambda
   - Monitor next lazy loader runs (every 2 minutes) for 1 hour

2. **Test provision flow:**
   - Provision a new 710-008 sensor in QA environment
   - Verify it gets FirmwareID=455, not 460
   - Check `Request` records have correct FirmwareID

## Other Notes

### Diagnostic Queries from Research Doc

The research document (`thoughts/shared/research/2026-02-06-firmware-version-management-lazy-loader.md`) contains detailed diagnostic queries at the end of the "Follow-up Research" section. Key queries:

1. **Check sensor FirmwareID vs target** — Shows current vs expected FirmwareID with facility overrides
2. **Check recent Request records** — Shows FirmwareID in Request table for debugging
3. **Count NULL FirmwareID in requests** — Identifies lookup failures

### Unvalidated Assumptions

Per research document, these assumptions were made but not validated:

1. Hub embedded firmware download/install/report flow (not in git repos)
2. MQTT message format matches parser expectations exactly
3. No other MQTT processors handle firmware confirmations
4. Clock synchronization for RQID matching is reliable across services

### Meeting Notes Context

This investigation was triggered by a meeting with hardware engineers. Key points from meeting:

- Issue discovered: ~600-3000 sensors re-targeted to 2.8.0 every 6 hours despite already on 2.8.0
- Root cause confirmed: Provision lookup by Version only, not Version + PartID
- Data cleanup needed urgently before sensor firmware release
- FirmwareVersion field investigation requested as secondary issue

### Developer Contacts

Based on git history (`thoughts/shared/research/2026-02-06-firmware-version-management-lazy-loader.md`):

- **Darren Ybarra** — Original author of lazy loader (2023)
- **Bailey Ritchie** — Recent work on `Request_AcknowledgeRequest` (Nov 2025) and sensor firmware procedures (April 2025)
- **Ethan Fialkoff** — Modified `Receiver_UpdateFirmwareVersion` (Sept 2024)
- **Venkata Bolneni** — Added timeout logic to acknowledgement (Jan 2025)

### Repository Structure

- `fullstack.assetwatch` — Main codebase (frontend, lambdas, schemas)
- `assetwatch-jobs` — Scheduled jobs, request processors, MQTT handlers
- Hub firmware repo — Not examined (physical device code)
