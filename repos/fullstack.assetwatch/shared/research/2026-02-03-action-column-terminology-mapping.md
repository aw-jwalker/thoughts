# Action Column Terminology Mapping

**Purpose**: Mapping between database, code, and user-facing terminology for the Sensor Action column

**Date**: 2026-02-03

---

## Hardware Issue Names

| Database Name | Code Enum | CSR Sees |
|---------------|-----------|----------|
| Temp Over Fire Risk | `TEMP_OVER_FIRE_RISK` (59) | "Temp Over Fire Risk" |
| CSR - Remove | `CSR_REMOVE` (61) | "CSR - Remove" |
| TOFR - Remove | `TOFR_REMOVE` (67) | "TOFR - Remove" |
| TOFR - Replace | `TOFR_REPLACE` (66) | "TOFR - Replace" |
| CSR - Strengthen Network | `CSR_STRENGTHEN_NETWORK` (64) | "CSR - Strengthen Network" |
| CSR - Check Placement | `CSR_CHECK_PLACEMENT` (49) | "CSR - Check Placement" |
| Low Battery Voltage | `LOW_BATTERY_VOLTAGE` (15) | "Low Battery Voltage" |

**Note**: Database uses human-readable names, code uses SCREAMING_SNAKE_CASE enums with IDs

---

## Action Column Values

| What CSR Sees | Internal Logic | Database Equivalent |
|---------------|----------------|---------------------|
| **Remove** | Hardware issue IDs 59, 61, or 67<br/>OR MP Status = "Blacklist" | HardwareIssueTypeActionID 4 = "Remove"<br/>(but logic doesn't use this!) |
| **Replace** | `hasReplaceAction = 1`<br/>OR Hardware issue ID 66<br/>OR MP Status = "Released" | HardwareIssueTypeActionID 1 = "Replace" |
| **Check/Add Network Equipment** | Hardware issue ID 64 | HardwareIssueTypeActionID 5 |
| **Check Placement** | Hardware issue ID 49 | HardwareIssueTypeActionID 2 = "Move"<br/>(different name!) |
| **Turn On** | Sensor Status = "Offline" | ReceiverStatusID 4 = "Offline" |
| **Ok** | Default (no issues) | ReceiverStatusID 5 = "Ok" |

**Important**: The Action column values are **hardcoded in the frontend** (`ColumnDefs.tsx`) and do NOT come from the `HardwareIssueTypeAction` table!

---

## Hardware Issue Type Actions (Database)

These are stored in the database but **NOT directly used** for the Action column display:

| ActionID | Action Name (DB) | Purpose |
|----------|------------------|---------|
| 1 | Replace | Contributes to `hasReplaceAction` calculation |
| 2 | Move | Categorization only (not displayed) |
| 3 | No Action Needed | Categorization only (not displayed) |
| 4 | Remove | Categorization only (not displayed) |
| 5 | Check/Add Network Equipment | Categorization only (not displayed) |

**Key Insight**: `HardwareIssueTypeActionID = 1` is used in the **database query** to calculate `hasReplaceAction`, which then triggers "Replace" in the Action column.

---

## Monitoring Point Status

| StatusID | Status Name (DB) | CSR Terminology | Triggers Action |
|----------|------------------|-----------------|-----------------|
| 1 | Pending Review | "Pending Review" | - |
| 2 | Released | "Released" | "Replace" (with feature flag) |
| 3 | Pending Whitelist (Waiver Needed) | "Pending Whitelist" | - |
| 4 | Whitelist (Waiver Signed) | "Whitelist" | - |
| 5 | Blacklist | "Blacklist" | "Remove" (with feature flag) |

---

## Sensor Status

| StatusID | Status Name (DB) | CSR Sees | Triggers Action |
|----------|------------------|----------|-----------------|
| 1 | Replace Sensor | "Replace Sensor" | - |
| 2 | Reclamation | "Reclamation" | - |
| 3 | Missed Readings | "Missed Readings" | - |
| 4 | Offline | "Offline" | "Turn On" |
| 5 | Ok | "Ok" | - |
| 6 | Recharge Battery | "Recharge Battery" | - |
| 7 | Provisioned | "Provisioned" | - |

---

## Critical Battery Status

| Source | Field Name | Value | CSR Terminology | Triggers Action |
|--------|-----------|-------|-----------------|-----------------|
| SensorLife table | `PredictedBatteryStatus` | "Critical" | Not directly visible | "Replace" (via `hasReplaceAction`) |

**Note**: Battery predictions come from ML model, CSRs see this indirectly through the Action column

---

## Summary: Database vs Code vs UI

### Example 1: "Temp Over Fire Risk" Issue

- **Database**: `HardwareIssueTypeName = "Temp Over Fire Risk"`, `HardwareIssueTypeActionID = 3` ("No Action Needed")
- **Code Enum**: `HardwareIssueType.TEMP_OVER_FIRE_RISK` (59)
- **Frontend Logic**: Checks if `hardwareIssueIDs` includes "59"
- **CSR Sees in Hardware Events column**: "Temp Over Fire Risk"
- **CSR Sees in Action column**: "Remove"

### Example 2: "hasReplaceAction" Calculation

- **Database Query**: Calculates boolean from battery status OR open issues with `ActionID = 1`
- **Frontend Receives**: `hasReplaceAction: 1` or `0`
- **Frontend Logic**: Checks `Boolean(data.hasReplaceAction)`
- **CSR Sees in Action column**: "Replace"
- **CSR Never Sees**: The term "hasReplaceAction"

### Example 3: Monitoring Point "Released"

- **Database**: `MonitoringPointStatusID = 2`, `MonitoringPointStatus = "Released"`
- **Frontend Receives**: `mpStatusId: 2`
- **Frontend Logic**: Checks `mpStatusId === mpStatuses.Released` (with feature flag)
- **CSR Sees**: Monitoring point has "Released" status
- **CSR Sees in Action column**: "Replace"

---

## Naming Conventions

### Database
- Human-readable names: "Temp Over Fire Risk", "CSR - Remove"
- Status tables use descriptive names: "Pending Review", "Offline"

### Code (TypeScript)
- Enums use SCREAMING_SNAKE_CASE: `TEMP_OVER_FIRE_RISK`, `CSR_REMOVE`
- Numeric IDs used for comparison: `HardwareIssueType.TEMP_OVER_FIRE_RISK` = 59

### Frontend Display (What CSRs See)
- Action column: Simple action verbs ("Remove", "Replace", "Turn On")
- Hardware Events column: Same as database names ("Temp Over Fire Risk")
- Status columns: Same as database names ("Offline", "Released")

---

## Key Differences for CSR Flowchart

When creating a CSR-friendly flowchart, use:

✅ **USE**: "Temp Over Fire Risk" (database name)
❌ **AVOID**: `TEMP_OVER_FIRE_RISK` (code enum)

✅ **USE**: "Hardware Event: Temp Over Fire Risk"
❌ **AVOID**: "hardwareIssueIDs includes 59"

✅ **USE**: "Monitoring Point Status: Released"
❌ **AVOID**: "mpStatusId === 2"

✅ **USE**: "Sensor Status: Offline"
❌ **AVOID**: "rstid === 4"

✅ **USE**: "Battery Status: Critical"
❌ **AVOID**: "hasReplaceAction = 1"
