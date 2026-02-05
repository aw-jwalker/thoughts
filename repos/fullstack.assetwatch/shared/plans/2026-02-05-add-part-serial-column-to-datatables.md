---
date: 2026-02-05T09:18:09-0500
researcher: aw-jwalker
git_commit: df49b4205f0d43611d4842f9536bc5a929bc70bf
branch: dev
repository: fullstack.assetwatch
status: draft
last_updated: 2026-02-05
last_updated_by: aw-jwalker
type: implementation_plan
---

# Add Part:Serial Column to Datatables Implementation Plan

## Overview

Add a new "Part:Serial" column to all datatables that display serial numbers for hardware (Sensors/Receivers, Hubs/Transponders, Hotspots/Cradlepoints). The column will display `{PartNumber}{PartRevision}:{SerialNumber}` format (or `{PartNumber}:{MAC}` for Hotspots). This column will replace the current pinned "Serial#" column (which will remain but be unpinned).

## Current State Analysis

### Affected Datatables Identified:

| Location | File | Serial Field | Part# Field | Rev Field | Status |
|----------|------|--------------|-------------|-----------|--------|
| **CustomerDetail > Sensors (Active)** | `apps/frontend/src/components/CustomerDetailPage/Sensors/ColumnDefs.tsx` | `ssn` | `smpn` | `partRevision` | ✅ All fields available |
| **CustomerDetail > Sensors (Spare)** | `apps/frontend/src/components/CustomerDetailPage/Sensors/ColumnDefs.tsx` | `serialNumber` | `partNumber` | `partRevision` | ✅ All fields available |
| **CustomerDetail > Hubs** | `apps/frontend/src/components/CustomerDetailPage/Hubs/ColumnDefs.tsx` | `hsn` | `pn` | `partRevision` | ✅ All fields available |
| **CustomerDetail > Hotspots** | `apps/frontend/src/components/CustomerDetailPage/Hotspots/ColumnDefs.tsx` | `MAC` | `partNumber` | N/A | ⚠️ No revision (format: `{PartNumber}:{MAC}`) |
| **Sensor Check** | `apps/frontend/src/components/SensorCheckPage/SensorCheckResults.tsx` | `smsn` | `pn` | `partRevision` | ✅ All fields available (HW Rev column exists) |
| **Work Order Hardware Status** | `apps/frontend/src/components/CustomerDetailPage/WorkOrders/HardwareStatusTable.tsx` | `serialNumber` | `partNumber` | `partRevision` | ✅ All fields available |

### Current Column Patterns:

All existing Serial# columns follow similar patterns:
- `pinned: "left" as const` - Pinned to left for easy access
- `checkboxSelection` and `headerCheckboxSelection` - For bulk operations
- `cellRenderer` - Conditional link rendering based on user role
- Link to detail pages: `/receivers/$id`, `/hubs/$id`, `/enclosures/$id`

### Key Discoveries:

1. **Data availability**: All required fields (`partNumber`, `partRevision`, `serialNumber`/`MAC`) are already returned by backend APIs
2. **Column positioning**: Serial# columns are currently pinned left for quick reference
3. **Link patterns**: Serial numbers are often clickable links to detail pages (role-dependent)
4. **Naming variations**: Different tables use different field names for the same data:
   - Part Number: `smpn`, `partNumber`, `pn`
   - Serial Number: `ssn`, `smsn`, `serialNumber`, `hsn`, `MAC`

## Desired End State

### Success Criteria:

#### Automated Verification:

- [ ] TypeScript compilation passes: `pnpm --filter frontend typecheck`
- [ ] ESLint passes: `cd apps/frontend && pnpm exec eslint src/`
- [ ] Frontend tests pass: `pnpm --filter frontend test`
- [ ] No console errors when viewing any of the affected pages

#### Manual Verification:

- [ ] CustomerDetail > Sensors (Active) shows new "Part:Serial" column pinned left (e.g., "710-001A:1234567")
- [ ] CustomerDetail > Sensors (Spare) shows new "Part:Serial" column pinned left
- [ ] CustomerDetail > Hubs shows new "Part:Serial" column pinned left (e.g., "710-002B:7654321")
- [ ] CustomerDetail > Hotspots shows new "Part:Serial" column pinned left (e.g., "710-003:00:1A:2B:3C:4D")
- [ ] Sensor Check shows new "Part:Serial" column pinned left
- [ ] Work Order Hardware Status shows new "Part:Serial" column pinned left
- [ ] Existing Serial# columns remain visible but are no longer pinned
- [ ] Links in Part:Serial column navigate to correct detail pages
- [ ] Checkbox selection works on the new pinned column
- [ ] Column sorting and filtering work correctly
- [ ] CSV export includes the new column with correct values

## What We're NOT Doing

- ❌ NOT modifying Track Inventory DataMatrix popup (backend doesn't return part/revision data)
- ❌ NOT modifying Add/Edit Monitoring Points modal components
- ❌ NOT changing the existing Serial# columns (just unpinning them)
- ❌ NOT making backend changes (all required data is already available)
- ❌ NOT changing data types or API responses

## Implementation Approach

### Strategy:

1. **Consolidate serial number utilities** - Rename and clean up existing utilities
2. **Create reusable utility function** - Centralize the formatting logic for consistency
3. **Update each datatable** - Add new column definition while preserving existing Serial# column
4. **Maintain existing patterns** - Follow established patterns for links, role-based rendering, and styling
5. **Test each table individually** - Verify changes don't break existing functionality

### Design Decision:

**Utility Function Location**: `apps/frontend/src/utils/serialNumberUtils.ts`

This function will:
- Be named `formatPartSerial()` - matching user-facing "Part:Serial" terminology
- Accept `partNumber`, `partRevision?`, and `serialNumber`
- Return formatted string: `{partNumber}{partRevision}:{serialNumber}`
- Handle missing revision gracefully (Hotspots case)
- Be the inverse of existing `extractPartNumberFromBarcode()`

## Phase 0: Consolidate Serial Number Utilities

### Overview

Clean up and consolidate serial number utilities into a single file. Remove dead code from January 2026 when the serial number generator was removed from the UI.

### Changes Required:

#### 1. Rename File

**Current**: `apps/frontend/src/utils/stripPartNumber.ts`
**New**: `apps/frontend/src/utils/serialNumberUtils.ts`

Rationale: File now contains multiple serial number operations (strip, extract, format), not just stripping.

#### 2. Delete Dead Code

**Files to Delete**:
- `apps/frontend/src/utils/receiverSerialNumberGenerator.ts` - Function unused since Jan 16, 2026
- `apps/frontend/src/components/SensorCheckPage/SerialNumberGenerator.tsx` - Component removed from UI Jan 16, 2026

These were removed from the SensorCheck page but the files were left behind.

#### 3. Update Import Statements

**Files with imports to update** (9 files):
1. `apps/frontend/src/utils/__tests__/stripPartNumber.test.ts`
2. `apps/frontend/src/pages/SensorCheck.tsx`
3. `apps/frontend/src/components/common/forms/ProductInput.tsx`
4. `apps/frontend/src/components/common/forms/SerialNumberInput.tsx`
5. `apps/frontend/src/components/common/forms/SimpleSerialNumberInput.tsx`
6. `apps/frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx`
7. `apps/frontend/src/components/UpdateMonitoringPointModal/hooks/useColumnDefinitions.ts`
8. `apps/frontend/src/components/GeneralSearch/SpotlightSearchProvider.tsx`
9. `apps/frontend/src/components/CustomerDetailPage/WorkOrders/Bom.tsx`

**Find/Replace**:
```typescript
// OLD:
from "@utils/stripPartNumber"

// NEW:
from "@utils/serialNumberUtils"
```

#### 4. Rename Test File

**Current**: `apps/frontend/src/utils/__tests__/stripPartNumber.test.ts`
**New**: `apps/frontend/src/utils/__tests__/serialNumberUtils.test.ts`

Update its own import at the top of the file.

### Success Criteria:

#### Automated Verification:

- [ ] TypeScript compilation passes: `pnpm --filter frontend typecheck`
- [ ] ESLint passes: `cd apps/frontend && pnpm exec eslint src/`
- [ ] All tests pass: `pnpm --filter frontend test serialNumberUtils`

#### Manual Verification:

- [ ] No references to `stripPartNumber.ts` remain in codebase
- [ ] No references to `receiverSerialNumberGenerator` remain
- [ ] All existing functionality works (import paths updated correctly)
- [ ] Serial number validation still works in forms
- [ ] Barcode parsing still works in UpdateMonitoringPointModal

**Implementation Note**: After completing this phase and all automated verification passes, continue to Phase 1.

---

## Phase 1: Add Format Utility Function

### Overview

Add the `formatPartSerial()` function to the newly renamed `serialNumberUtils.ts` file. This function is the inverse of the existing `extractPartNumberFromBarcode()` function.

### Changes Required:

#### 1. Add Function to serialNumberUtils.ts

**File**: `apps/frontend/src/utils/serialNumberUtils.ts`
**Changes**: Add new function after `extractPartNumberFromBarcode`

```typescript
/**
 * Formats part serial identifier in the format: {PartNumber}{Revision}:{SerialNumber}
 * This is the inverse of extractPartNumberFromBarcode().
 * For Hotspots (which use MAC instead of serial): {PartNumber}:{MAC}
 *
 * @param partNumber - The part number (e.g., "710-001")
 * @param serialNumber - The serial number or MAC address
 * @param revision - Optional part revision (e.g., "A", "B") - will be normalized to uppercase
 * @returns Formatted part serial string (e.g., "710-001A:1234567" or "710-003:00:1A:2B:3C:4D")
 *
 * @example
 * formatPartSerial("710-001", "1015535", "f")  // "710-001F:1015535"
 * formatPartSerial("710-003", "AA:BB:CC:DD:EE:FF")  // "710-003:AA:BB:CC:DD:EE:FF"
 */
export function formatPartSerial(
  partNumber: string,
  serialNumber: string,
  revision?: string,
): string {
  if (!partNumber || !serialNumber) {
    return serialNumber || "";
  }

  const normalizedRevision = revision?.toUpperCase() || "";
  return `${partNumber}${normalizedRevision}:${serialNumber}`;
}
```

#### 2. Add Tests to serialNumberUtils.test.ts

**File**: `apps/frontend/src/utils/__tests__/serialNumberUtils.test.ts`
**Changes**: Add new test suite after existing tests

```typescript
describe("formatPartSerial", () => {
  it("formats with part number, revision, and serial", () => {
    expect(formatPartSerial("710-001", "1234567", "A")).toBe(
      "710-001A:1234567",
    );
  });

  it("formats without revision (Hotspot case)", () => {
    expect(formatPartSerial("710-003", "00:1A:2B:3C:4D")).toBe(
      "710-003:00:1A:2B:3C:4D",
    );
  });

  it("handles empty revision string", () => {
    expect(formatPartSerial("710-002", "7654321", "")).toBe(
      "710-002:7654321",
    );
  });

  it("normalizes lowercase revision to uppercase", () => {
    expect(formatPartSerial("710-001", "1234567", "f")).toBe(
      "710-001F:1234567",
    );
  });

  it("normalizes mixed-case revision to uppercase", () => {
    expect(formatPartSerial("710-100", "0000017", "Ra")).toBe(
      "710-100RA:0000017",
    );
  });

  it("returns serial number when part number is missing", () => {
    expect(formatPartSerial("", "1234567", "A")).toBe("1234567");
  });

  it("returns empty string when both part and serial are missing", () => {
    expect(formatPartSerial("", "")).toBe("");
  });

  it("handles MAC addresses for Hotspots", () => {
    expect(formatPartSerial("710-003", "AA:BB:CC:DD:EE:FF")).toBe(
      "710-003:AA:BB:CC:DD:EE:FF",
    );
  });

  it("is inverse of extractPartNumberFromBarcode", () => {
    const input = "710-001F:1015535";
    const parsed = extractPartNumberFromBarcode(input);
    const formatted = formatPartSerial(
      parsed.partNumber!,
      parsed.serialNumber,
      parsed.revision!,
    );
    expect(formatted).toBe(input);
  });
});
```

### Success Criteria:

#### Automated Verification:

- [ ] TypeScript compilation passes: `pnpm --filter frontend typecheck`
- [ ] Test passes: `pnpm --filter frontend test serialNumberUtils`
- [ ] ESLint passes: `cd apps/frontend && pnpm exec eslint src/`

#### Manual Verification:

- [ ] Function correctly formats all test cases
- [ ] Revision normalization works (lowercase → uppercase)
- [ ] Function is inverse of `extractPartNumberFromBarcode`
- [ ] No imports or exports errors

**Implementation Note**: After completing this phase and all automated verification passes, continue to Phase 2.

---

## Phase 2: Update CustomerDetail > Sensors (Active) Table

### Overview

Add "Part:Serial" column to the active sensors datatable in CustomerDetail page.

### Changes Required:

#### 1. Update Sensors ColumnDefs

**File**: `apps/frontend/src/components/CustomerDetailPage/Sensors/ColumnDefs.tsx`
**Changes**:
1. Import the utility function
2. Add new "Part:Serial" column after "Action" column
3. Update existing "Serial#" column to remove pinning

**Import addition** (after other imports):
```typescript
import { formatPartSerial } from "@utils/serialNumberUtils";
```

**New column definition** (insert after line 163, before the existing "Serial#" column):
```typescript
{
  headerName: "Part:Serial",
  field: "partSerial",
  minWidth: 140,
  pinned: "left" as const,
  checkboxSelection: !isCustomerHardwareStatusRoleUser,
  headerCheckboxSelection: !isCustomerHardwareStatusRoleUser,
  valueGetter: ({ data }: { data: Sensor }) =>
    formatPartSerial(data.smpn, data.ssn, data.partRevision),
  cellRenderer: ({ data, value }: { data: Sensor; value: string }) =>
    isCustomerHardwareStatusRoleUser || isPartner ? (
      value
    ) : (
      <Link
        to="/receivers/$id"
        params={{
          id: data.sid.toString(),
        }}
        target="_blank"
        rel="noopener noreferrer"
      >
        {value}
      </Link>
    ),
},
```

**Update existing "Serial#" column** (line 169-189):
- Remove `pinned: "left" as const,`
- Remove `checkboxSelection` and `headerCheckboxSelection`
- Update minWidth to 100

```typescript
{
  headerName: "Serial#",
  field: "ssn",
  minWidth: 100,
  cellRenderer: ({ data, value }: { data: Sensor; value: string }) =>
    isCustomerHardwareStatusRoleUser || isPartner ? (
      value
    ) : (
      <Link
        to="/receivers/$id"
        params={{
          id: data.sid.toString(),
        }}
        target="_blank"
        rel="noopener noreferrer"
      >
        {value}
      </Link>
    ),
},
```

### Success Criteria:

#### Automated Verification:

- [ ] TypeScript compilation passes: `pnpm --filter frontend typecheck`
- [ ] ESLint passes: `cd apps/frontend && pnpm exec eslint src/`
- [ ] Frontend tests pass: `pnpm --filter frontend test`

#### Manual Verification:

- [ ] Navigate to CustomerDetail page and click "Sensors" tab
- [ ] New "Part:Serial" column appears pinned left with format like "710-001A:1234567"
- [ ] Clicking Part:Serial value navigates to receiver detail page
- [ ] Serial# column still exists but is no longer pinned
- [ ] Checkbox selection works on the Part:Serial column
- [ ] Column can be sorted and filtered
- [ ] CSV export includes both columns

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding to Phase 3.

---

## Phase 3: Update CustomerDetail > Sensors (Spare) Table

### Overview

Add "Part:Serial" column to the spare sensors datatable in CustomerDetail page.

### Changes Required:

#### 1. Update Spare Receivers ColumnDefs

**File**: `apps/frontend/src/components/CustomerDetailPage/Sensors/ColumnDefs.tsx`
**Changes**: Update `spareReceiverColumnDefs` function

**New column definition** (insert after line 437, before existing Part# column):
```typescript
{
  headerName: "Part:Serial",
  field: "partSerial",
  minWidth: 140,
  pinned: "left" as const,
  valueGetter: ({ data }: { data: SpareSensor }) =>
    formatPartSerial(data.partNumber, data.serialNumber, data.partRevision),
  cellRenderer: ({ data, value }: { data: SpareSensor; value: string }) => {
    return (
      <Link
        to="/receivers/$id"
        params={{
          id: data.receiverID.toString(),
        }}
        target="_blank"
        rel="noopener noreferrer"
      >
        {value}
      </Link>
    );
  },
},
```

**Update existing "Serial#" column** (line 444-461):
- Remove `pinned: "left" as const,`
- Update minWidth to 100

```typescript
{
  headerName: "Serial#",
  field: "serialNumber",
  minWidth: 100,
  cellRenderer: ({ data, value }: { data: SpareSensor; value: string }) => {
    return (
      <Link
        to="/receivers/$id"
        params={{
          id: data.receiverID.toString(),
        }}
        target="_blank"
        rel="noopener noreferrer"
      >
        {value}
      </Link>
    );
  },
},
```

### Success Criteria:

#### Automated Verification:

- [ ] TypeScript compilation passes: `pnpm --filter frontend typecheck`
- [ ] ESLint passes: `cd apps/frontend && pnpm exec eslint src/`
- [ ] Frontend tests pass: `pnpm --filter frontend test`

#### Manual Verification:

- [ ] Navigate to CustomerDetail page and click "Sensors" tab
- [ ] Scroll to "Spare Sensors" section
- [ ] New "Part:Serial" column appears pinned left
- [ ] Clicking Part:Serial value navigates to receiver detail page
- [ ] Serial# column still exists but is no longer pinned

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding to Phase 4.

---

## Phase 4: Update CustomerDetail > Hubs Table

### Overview

Add "Part:Serial" column to the hubs datatable in CustomerDetail page.

### Changes Required:

#### 1. Update Hubs ColumnDefs

**File**: `apps/frontend/src/components/CustomerDetailPage/Hubs/ColumnDefs.tsx`
**Changes**:
1. Import the utility function
2. Add new "Part:Serial" column at the beginning
3. Update existing "Serial#" column to remove pinning

**Import addition** (after other imports):
```typescript
import { formatPartSerial } from "@utils/serialNumberUtils";
```

**New column definition** (insert at line 39, before existing "Serial#" column):
```typescript
{
  headerName: "Part:Serial",
  field: "partSerial",
  minWidth: 140,
  pinned: "left" as const,
  checkboxSelection: () => !isCustomerHardwareStatusRoleUser,
  headerCheckboxSelection: !isCustomerHardwareStatusRoleUser,
  valueGetter: ({ data }: { data: SelectedHub }) =>
    formatPartSerial(data.pn, data.hsn, data.partRevision),
  cellRenderer: function ({
    data,
    value,
  }: {
    data: SelectedHub;
    value: string;
  }) {
    return isCustomerHardwareStatusRoleUser || isPartner ? (
      value
    ) : (
      <Link
        to="/hubs/$id"
        params={{ id: data.hid.toString() }}
        target="_blank"
        rel="noopener noreferrer"
      >
        {value}
      </Link>
    );
  },
},
```

**Update existing "Serial#" column** (line 40-65):
- Remove `pinned: "left" as const,`
- Remove `checkboxSelection` and `headerCheckboxSelection`
- Update minWidth to 100

```typescript
{
  headerName: "Serial#",
  field: "hsn",
  minWidth: 100,
  cellRenderer: function ({
    data,
    value,
  }: {
    data: SelectedHub;
    value: string;
  }) {
    return isCustomerHardwareStatusRoleUser || isPartner ? (
      value
    ) : (
      <Link
        to="/hubs/$id"
        params={{ id: data.hid.toString() }}
        target="_blank"
        rel="noopener noreferrer"
      >
        {value}
      </Link>
    );
  },
},
```

### Success Criteria:

#### Automated Verification:

- [ ] TypeScript compilation passes: `pnpm --filter frontend typecheck`
- [ ] ESLint passes: `cd apps/frontend && pnpm exec eslint src/`
- [ ] Frontend tests pass: `pnpm --filter frontend test`

#### Manual Verification:

- [ ] Navigate to CustomerDetail page and click "Hubs" tab
- [ ] New "Part:Serial" column appears pinned left with format like "710-002B:7654321"
- [ ] Clicking Part:Serial value navigates to hub detail page
- [ ] Serial# column still exists but is no longer pinned
- [ ] Checkbox selection works on the Part:Serial column

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding to Phase 5.

---

## Phase 5: Update CustomerDetail > Hotspots Table

### Overview

Add "Part:Serial" column to the hotspots datatable in CustomerDetail page. Note: Hotspots use MAC address instead of serial number and don't have part revision.

### Changes Required:

#### 1. Update Hotspots ColumnDefs

**File**: `apps/frontend/src/components/CustomerDetailPage/Hotspots/ColumnDefs.tsx`
**Changes**:
1. Import the utility function
2. Add new "Part:Serial" column at the beginning
3. Update existing "MAC" column to remove pinning

**Import addition** (after other imports):
```typescript
import { formatPartSerial } from "@utils/serialNumberUtils";
```

**New column definition** (insert at line 17, before existing "MAC" column):
```typescript
{
  headerName: "Part:Serial",
  field: "partSerial",
  minWidth: 160,
  pinned: "left" as const,
  checkboxSelection: () => !isCustomerHardwareStatusRoleUser,
  headerCheckboxSelection: !isCustomerHardwareStatusRoleUser,
  valueGetter: ({ data }: { data: Hotspot }) =>
    formatPartSerial(data.partNumber, data.MAC),
},
```

**Update existing "MAC" column** (line 18-25):
- Remove `pinned: "left" as const,`
- Remove `checkboxSelection` and `headerCheckboxSelection`
- Update minWidth to 120

```typescript
{
  headerName: "MAC",
  colId: "MAC",
  field: "MAC",
  minWidth: 120,
},
```

### Success Criteria:

#### Automated Verification:

- [ ] TypeScript compilation passes: `pnpm --filter frontend typecheck`
- [ ] ESLint passes: `cd apps/frontend && pnpm exec eslint src/`
- [ ] Frontend tests pass: `pnpm --filter frontend test`

#### Manual Verification:

- [ ] Navigate to CustomerDetail page and click "Hotspots" tab
- [ ] New "Part:Serial" column appears pinned left with format like "710-003:00:1A:2B:3C:4D"
- [ ] MAC column still exists but is no longer pinned
- [ ] Checkbox selection works on the Part:Serial column

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding to Phase 6.

---

## Phase 6: Update Sensor Check Table

### Overview

Add "Part:Serial" column to the Sensor Check results datatable.

### Changes Required:

#### 1. Update Sensor Check ColumnDefs

**File**: `apps/frontend/src/components/SensorCheckPage/SensorCheckResults.tsx`
**Changes**:
1. Import the utility function
2. Add new "Part:Serial" column after "Scan Order"
3. Update existing "Serial #" column to remove pinning

**Import addition** (after other imports):
```typescript
import { formatPartSerial } from "@utils/serialNumberUtils";
```

**New column definition** (insert after line 228, after "Scan Order" column):
```typescript
{
  headerName: "Part:Serial",
  field: "partSerial",
  minWidth: 140,
  pinned: "left" as const,
  lockPosition: "left" as const,
  valueGetter: ({ data }: { data: SensorCheckSensor }) =>
    formatPartSerial(data.pn, data.smsn, data.partRevision),
  cellRenderer({ data, value }: { data: SensorCheckSensor; value: string }) {
    return (
      <span>
        <a
          target="_blank"
          rel="noreferrer noopener"
          href={`/receivers/${data.smid}`}
          data-testid="part-serial-link"
        >
          {value}
        </a>
      </span>
    );
  },
},
```

**Update existing "Serial #" column** (line 230-245):
- Keep as is (it's not currently pinned)
- Ensure it remains after Part:Serial column

The Serial # column should remain as:
```typescript
{
  headerName: "Serial #",
  field: "smsn",
  cellRenderer({ data, value }: { data: SensorCheckSensor; value: string }) {
    return (
      <span>
        <a
          target="_blank"
          rel="noreferrer noopener"
          href={`/receivers/${data.smid}`}
          data-testid="serial-number-link"
        >
          {value}
        </a>
      </span>
    );
  },
},
```

### Success Criteria:

#### Automated Verification:

- [ ] TypeScript compilation passes: `pnpm --filter frontend typecheck`
- [ ] ESLint passes: `cd apps/frontend && pnpm exec eslint src/`
- [ ] Frontend tests pass: `pnpm --filter frontend test`

#### Manual Verification:

- [ ] Navigate to Sensor Check page
- [ ] Submit a sensor check with test sensors
- [ ] New "Part:Serial" column appears after "Scan Order" with format like "710-001A:1234567"
- [ ] Clicking Part:Serial value navigates to receiver detail page
- [ ] Serial # column still exists
- [ ] Both columns are sortable and filterable
- [ ] CSV export includes both columns

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding to Phase 7.

---

## Phase 7: Update Work Order Hardware Status Table

### Overview

Add "Part:Serial" column to the Work Order Hardware Status datatable.

### Changes Required:

#### 1. Update Hardware Status Table Columns

**File**: `apps/frontend/src/components/CustomerDetailPage/WorkOrders/HardwareStatusTable.tsx`
**Changes**:
1. Import the utility function
2. Add new "Part:Serial" column at the beginning
3. Update existing "Serial #" column

**Import addition** (after other imports):
```typescript
import { formatPartSerial } from "@utils/serialNumberUtils";
```

**Update columns array** (line 76-141):

Add new column definition at the beginning of the columns array (after the conditional "Keep" column):
```typescript
{
  headerName: "Part:Serial",
  field: "partSerial",
  minWidth: 140,
  pinned: "left" as const,
  valueGetter: ({ data }: { data: HardwareData }) =>
    formatPartSerial(data.partNumber, data.serialNumber, data.partRevision),
  cellRenderer({
    data: { productName, hardwareID, serialNumber, partNumber, partRevision },
    value,
  }: {
    data: HardwareData;
    value: string;
  }) {
    if (productName === "Hotspot") return value;

    const truncatedProductName = productName.slice(
      0,
      productName.lastIndexOf("-"),
    );
    const hardwareType = renderHardwareType(truncatedProductName);

    return hardwareType ? (
      <Link
        target="_blank"
        rel="noreferrer"
        to={hardwareType === "hubs" ? "/hubs/$id" : "/receivers/$id"}
        params={{ id: hardwareID.toString() }}
      >
        {value}
      </Link>
    ) : (
      <span>{value}</span>
    );
  },
},
```

**Update existing "Serial #" column** (remove pinning if it exists):
```typescript
{
  headerName: "Serial #",
  field: "serialNumber",
  cellRenderer({
    data: { productName, hardwareID },
    value,
  }: {
    data: HardwareData;
    value: string;
  }) {
    if (productName === "Hotspot") return value;

    const truncatedProductName = productName.slice(
      0,
      productName.lastIndexOf("-"),
    );
    const hardwareType = renderHardwareType(truncatedProductName);

    return hardwareType ? (
      <Link
        target="_blank"
        rel="noreferrer"
        to={hardwareType === "hubs" ? "/hubs/$id" : "/receivers/$id"}
        params={{ id: hardwareID.toString() }}
      >
        {value}
      </Link>
    ) : (
      <span>{value}</span>
    );
  },
},
```

### Success Criteria:

#### Automated Verification:

- [ ] TypeScript compilation passes: `pnpm --filter frontend typecheck`
- [ ] ESLint passes: `cd apps/frontend && pnpm exec eslint src/`
- [ ] Frontend tests pass: `pnpm --filter frontend test`

#### Manual Verification:

- [ ] Navigate to CustomerDetail page, select a Work Order
- [ ] View "Hardware Summary" or hardware status section
- [ ] New "Part:Serial" column appears pinned left
- [ ] Clicking Part:Serial value for Sensors/Hubs navigates to detail page
- [ ] Hotspot Part:Serial values show correctly but are not clickable
- [ ] Serial # column still exists but is no longer pinned

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding to testing.

---

## Testing Strategy

### Unit Tests:

**Utility Function Tests** (created in Phase 1):
- ✅ Test formatting with all fields present
- ✅ Test formatting without revision (Hotspot case)
- ✅ Test handling of missing/empty values
- ✅ Test MAC address formatting

### Integration Tests:

Run existing test suites to ensure no regressions:
```bash
pnpm --filter frontend test
```

Key test files to verify:
- `apps/frontend/src/components/CustomerDetailPage/Sensors/__tests__/*`
- `apps/frontend/src/components/CustomerDetailPage/Hubs/__tests__/*`
- `apps/frontend/src/components/CustomerDetailPage/Hotspots/__tests__/*`
- `apps/frontend/src/pages/__tests__/SensorCheck*.test.tsx`

### Manual Testing Steps:

1. **CustomerDetail > Sensors (Active)**:
   - Navigate to any customer with active sensors
   - Verify Part:Serial column shows correct format
   - Click on Part:Serial value, verify navigation
   - Test sorting, filtering, CSV export
   - Verify checkbox selection works

2. **CustomerDetail > Sensors (Spare)**:
   - Navigate to same customer, check Spare Sensors section
   - Verify Part:Serial column shows correct format
   - Click on Part:Serial value, verify navigation

3. **CustomerDetail > Hubs**:
   - Navigate to any customer with hubs
   - Verify Part:Serial column shows correct format
   - Click on Part:Serial value, verify navigation
   - Test checkbox selection

4. **CustomerDetail > Hotspots**:
   - Navigate to any customer with hotspots
   - Verify Part:Serial column shows format: `{PartNumber}:{MAC}`
   - Test checkbox selection

5. **Sensor Check**:
   - Navigate to Sensor Check page
   - Submit check for 2-3 test sensors
   - Verify Part:Serial column shows correct format
   - Click on Part:Serial value, verify navigation
   - Test sorting and filtering
   - Download CSV, verify column is included

6. **Work Order Hardware Status**:
   - Navigate to any work order with hardware
   - Verify Part:Serial column shows correct format
   - Click on values for sensors/hubs, verify navigation
   - Verify hotspot values show correctly (no link)

### Edge Cases to Test:

- [ ] Sensors with missing part revision (should show `{PartNumber}:{Serial}`)
- [ ] Hotspots with MAC addresses in different formats
- [ ] Empty tables (no data)
- [ ] Large datasets (100+ rows)
- [ ] User roles: AssetWatch team vs Customer vs Partner
- [ ] Column reordering (Part:Serial should stay pinned left)
- [ ] Responsive behavior on smaller screens

## Performance Considerations

### Impact Analysis:

- **Additional column rendering**: Minimal impact - using existing data fields
- **valueGetter function**: Called once per row, simple string concatenation
- **No additional API calls**: All data already fetched
- **Sorting/filtering**: ag-grid handles efficiently with valueGetter

### Optimization Notes:

- The `formatHardwareSerial` utility is a pure function - could be memoized if performance issues arise
- Consider virtual scrolling for tables with 1000+ rows (ag-grid already handles this)

## Migration Notes

N/A - This is a non-breaking addition. Existing Serial# columns remain intact.

## Rollback Plan

If issues arise:
1. Remove the new "Part:Serial" column definitions from each file
2. Re-add pinning to existing Serial# columns
3. Re-add checkbox selection to Serial# columns
4. Remove the utility function (if not used elsewhere)

Changes are isolated to frontend column definitions - no database or API changes required.

## References

- Research findings: Exploration agents identified 6 datatables with serial numbers
- Type definitions: `apps/frontend/src/shared/types/sensors/*`, `apps/frontend/src/shared/types/hubs/*`, `apps/frontend/src/shared/types/hotspots/*`
- Existing column patterns: Each datatable's ColumnDefs file
- ag-grid documentation: Column definitions, pinning, cellRenderer, valueGetter
