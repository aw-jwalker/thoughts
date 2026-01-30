---
date: 2026-01-30T00:00:00Z
researcher: Claude
git_commit: cd7e75fa3b0bf5efd82851c83f92f90d706b047d
branch: dev
repository: fullstack.assetwatch
ticket: IWA-14751
status: draft
last_updated: 2026-01-30
last_updated_by: Claude
type: implementation_plan
---

# IWA-14751: HWQA Date Handling Fixes Implementation Plan

## Overview

Fix the shipment date bug where importing a shipment changes the date to one day before the entered date. Additionally, fix all related date handling issues discovered during the audit of the HWQA module.

## Current State Analysis

The HWQA module has multiple date handling issues caused by improper use of `new Date()` with date-only strings. When JavaScript parses a date-only string like `"2025-01-23"`, it interprets it as **midnight UTC**. When this is then converted to local time (e.g., CST which is UTC-6), the date shifts backward to the previous day.

### Key Discoveries:

1. **Primary Bug** (`LogShipmentForm.tsx:184`): The `formatDate` function uses `DateTime.fromJSDate(new Date(dateStr))` which causes timezone shift
2. **Excel Parsing Issue** (`LogShipmentForm.tsx:141`): Uses `date.toISOString().split("T")[0]` which can shift dates for users in Western timezones
3. **Dashboard Aggregation** (`dateAggregation.ts:82-84, 273-275`): Same `new Date()` pattern causing chart data misalignment
4. **Chart Transformers** (`chartDataTransformers.ts:48-50`): Same issue in fallback date parsing
5. **Date Filtering** (`ShipmentList.tsx`, `TestList.tsx`, `RouteBasedSensorList.tsx`): Using `new Date(cellValue)` in AG Grid filter comparators

### Database Schema (Confirmed):
- `ContractManufacturerShipment.DateShipped` - `DATE` type (no time component)
- `ContractManufacturerShipmentBox.DateReceived` - `DATE` type (no time component)

## Desired End State

1. Importing shipments from Excel preserves the exact date entered (no timezone shift)
2. All dates in the HWQA module display correctly regardless of user timezone
3. Date filtering in data tables works correctly
4. Dashboard aggregation and charts show accurate date groupings

### Verification:
- Import a shipment with date "2025-01-15", verify database contains "2025-01-15"
- View the shipment in the table, verify it shows "1/15/2025"
- Use date filters, verify filtering works correctly
- Check dashboard charts show correct date groupings

## What We're NOT Doing

- Changing database schema (DATE columns are appropriate)
- Modifying backend Python code (Pydantic correctly handles ISO date strings)
- Adding timezone tracking to individual dates (not needed for date-only fields)
- Refactoring the entire codebase's date handling (only HWQA module)

## Implementation Approach

Use Luxon's `DateTime.fromISO()` for all date-only string parsing. This method treats date-only strings as local dates without UTC conversion, preserving the intended date. For Excel Date objects, use Luxon's date formatting directly rather than going through `toISOString()`.

---

## Phase 1: Fix Primary Shipment Import Bug

### Overview

Fix the immediate bug causing shipment dates to shift by one day when importing from Excel.

### Changes Required:

#### 1. LogShipmentForm.tsx - formatDate function

**File**: `frontend/src/components/HwqaPage/features/shipments/LogShipmentForm.tsx`
**Lines**: 180-191

**Current Code:**
```typescript
const formatDate = (dateStr: string) => {
  if (!dateStr) return "";
  try {
    // Parse the date and format as ISO date (YYYY-MM-DD)
    const dt = DateTime.fromJSDate(new Date(dateStr));
    if (!dt.isValid) return dateStr;
    return dt.toFormat("yyyy-MM-dd");
  } catch (e) {
    console.error("Date parsing error:", e);
    return dateStr;
  }
};
```

**New Code:**
```typescript
const formatDate = (dateStr: string) => {
  if (!dateStr) return "";
  try {
    // Use fromISO to parse date-only strings without timezone conversion
    const dt = DateTime.fromISO(dateStr);
    if (!dt.isValid) return dateStr;
    return dt.toFormat("yyyy-MM-dd");
  } catch (e) {
    console.error("Date parsing error:", e);
    return dateStr;
  }
};
```

#### 2. LogShipmentForm.tsx - Excel cell date extraction

**File**: `frontend/src/components/HwqaPage/features/shipments/LogShipmentForm.tsx`
**Lines**: 139-141

**Current Code:**
```typescript
if (cell.type === ExcelJS.ValueType.Date) {
  const date = cell.value as Date;
  rowData[header] = date.toISOString().split("T")[0];
}
```

**New Code:**
```typescript
if (cell.type === ExcelJS.ValueType.Date) {
  const date = cell.value as Date;
  // Use Luxon to format the date directly, avoiding UTC conversion
  rowData[header] = DateTime.fromJSDate(date).toFormat("yyyy-MM-dd");
}
```

### Success Criteria:

#### Automated Verification:

- [ ] Type checking passes: `make -C frontend typecheck`
- [ ] Linting passes: `make -C frontend lint`
- [ ] Unit tests pass: `cd frontend && npm test -- --testPathPattern=LogShipmentForm`

#### Manual Verification:

- [ ] Upload a shipment CSV with date "2025-01-15"
- [ ] Verify the preview shows "2025-01-15" (not "2025-01-14")
- [ ] Click "Import Data" and verify the table shows "1/15/2025"
- [ ] Query database to confirm `DateShipped = '2025-01-15'`

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation that the shipment import bug is fixed before proceeding.

---

## Phase 2: Fix Dashboard Date Aggregation

### Overview

Fix date handling in dashboard charts and aggregation logic to prevent date shifting.

### Changes Required:

#### 1. dateAggregation.ts - calculateRollingAverage

**File**: `frontend/src/components/HwqaPage/features/dashboard/PassRateOverview/utils/dateAggregation.ts`
**Lines**: 79-84

**Current Code:**
```typescript
const dateStr =
  typeof shipment.date_shipped === "string"
    ? shipment.date_shipped.substring(0, 10)
    : DateTime.fromJSDate(new Date(shipment.date_shipped)).toFormat(
        "yyyy-MM-dd",
      );
```

**New Code:**
```typescript
const dateStr =
  typeof shipment.date_shipped === "string"
    ? shipment.date_shipped.substring(0, 10)
    : DateTime.fromJSDate(shipment.date_shipped as Date).toFormat(
        "yyyy-MM-dd",
      );
```

**Note**: The `typeof === "string"` branch is correct. The fallback should use `DateTime.fromJSDate()` directly on the Date object without wrapping in `new Date()`.

#### 2. dateAggregation.ts - aggregateFromRawMetrics

**File**: `frontend/src/components/HwqaPage/features/dashboard/PassRateOverview/utils/dateAggregation.ts`
**Lines**: 270-275

**Current Code:**
```typescript
const dateStr =
  typeof shipment.date_shipped === "string"
    ? shipment.date_shipped.substring(0, 10)
    : DateTime.fromJSDate(new Date(shipment.date_shipped)).toFormat(
        "yyyy-MM-dd",
      );
```

**New Code:**
```typescript
const dateStr =
  typeof shipment.date_shipped === "string"
    ? shipment.date_shipped.substring(0, 10)
    : DateTime.fromJSDate(shipment.date_shipped as Date).toFormat(
        "yyyy-MM-dd",
      );
```

#### 3. chartDataTransformers.ts - transformMetricsToChartData

**File**: `frontend/src/components/HwqaPage/features/dashboard/PassRateOverview/utils/chartDataTransformers.ts`
**Lines**: 46-51

**Current Code:**
```typescript
} else {
  // Fallback for Date objects - format as YYYY-MM-DD
  dateStr = DateTime.fromJSDate(
    new Date(shipment.date_shipped),
  ).toFormat("yyyy-MM-dd");
}
```

**New Code:**
```typescript
} else {
  // Fallback for Date objects - format as YYYY-MM-DD
  dateStr = DateTime.fromJSDate(
    shipment.date_shipped as Date,
  ).toFormat("yyyy-MM-dd");
}
```

### Success Criteria:

#### Automated Verification:

- [ ] Type checking passes: `make -C frontend typecheck`
- [ ] Linting passes: `make -C frontend lint`
- [ ] Unit tests pass: `cd frontend && npm test -- --testPathPattern="dateAggregation|chartDataTransformers"`

#### Manual Verification:

- [ ] Open HWQA Dashboard with existing shipment data
- [ ] Verify chart dates align with actual shipment dates
- [ ] Toggle between daily and weekly aggregation
- [ ] Confirm no date shifting in chart labels

**Implementation Note**: After completing this phase, pause for manual confirmation that dashboard displays correctly.

---

## Phase 3: Fix Date Filtering in Data Tables

### Overview

Fix the AG Grid date filter comparators that use `new Date()` to parse date-only strings.

### Changes Required:

#### 1. ShipmentList.tsx - Create reusable date comparator

**File**: `frontend/src/components/HwqaPage/features/shipments/ShipmentList.tsx`
**Lines**: Add after line 40, update filter params at lines 71-83, 136-148, 216-228

**Add helper function after formatDateTime:**
```typescript
/**
 * AG Grid date filter comparator that handles ISO date strings correctly.
 * Uses Luxon to parse dates without timezone conversion issues.
 */
const dateFilterComparator = (filterLocalDateAtMidnight: Date, cellValue: string): number => {
  if (!cellValue) return -1;

  // Parse the ISO date string using Luxon (treats date-only as local)
  const cellDateTime = DateTime.fromISO(cellValue);
  if (!cellDateTime.isValid) return -1;

  // Compare just the date portions
  const filterDateTime = DateTime.fromJSDate(filterLocalDateAtMidnight).startOf("day");
  const cellDateOnly = cellDateTime.startOf("day");

  if (cellDateOnly < filterDateTime) return -1;
  if (cellDateOnly > filterDateTime) return 1;
  return 0;
};
```

**Update all three filterParams blocks to use:**
```typescript
filterParams: {
  comparator: dateFilterComparator,
},
```

#### 2. TestList.tsx - Apply same fix

**File**: `frontend/src/components/HwqaPage/features/tests/TestList.tsx`

Apply the same pattern:
- Add the `dateFilterComparator` helper function
- Update all date column filter params (lines 58, 156, 196)

#### 3. RouteBasedSensorList.tsx - Apply same fix

**File**: `frontend/src/components/HwqaPage/features/conversion/SensorConversion/RouteBasedSensorList.tsx`

Apply the same pattern:
- Add the `dateFilterComparator` helper function
- Update date column filter params (lines 104, 126)
- Also fix line 28 fallback: change `DateTime.fromJSDate(new Date(isoString))` to `DateTime.fromISO(isoString)`

### Success Criteria:

#### Automated Verification:

- [ ] Type checking passes: `make -C frontend typecheck`
- [ ] Linting passes: `make -C frontend lint`
- [ ] Unit tests pass: `cd frontend && npm test -- --testPathPattern="ShipmentList|TestList|RouteBasedSensorList"`

#### Manual Verification:

- [ ] Open Shipments list, use date filter to filter by a specific date
- [ ] Verify correct shipments are shown/hidden
- [ ] Open Tests list, use date filter
- [ ] Verify filtering works correctly across timezone boundaries

**Implementation Note**: After completing this phase, pause for manual confirmation that date filtering works correctly.

---

## Phase 4: Create Shared Date Utilities (Optional Refactor)

### Overview

Create a shared date utilities module for HWQA to ensure consistent date handling and prevent future issues.

### Changes Required:

#### 1. Create new utility file

**File**: `frontend/src/components/HwqaPage/utils/dateUtils.ts` (new file)

```typescript
import { DateTime } from "luxon";

/**
 * Parses a date string or Date object into a YYYY-MM-DD format string.
 * Handles date-only strings without timezone conversion.
 *
 * @param value - ISO date string, Date object, or any date-like value
 * @returns YYYY-MM-DD formatted string
 */
export function toDateString(value: string | Date | unknown): string {
  if (!value) return "";

  if (typeof value === "string") {
    // For strings, extract just the date portion (handles both "2025-01-15" and "2025-01-15T00:00:00")
    return value.substring(0, 10);
  }

  if (value instanceof Date) {
    // For Date objects, format directly without UTC conversion
    return DateTime.fromJSDate(value).toFormat("yyyy-MM-dd");
  }

  return "";
}

/**
 * Parses a date-only string to a Luxon DateTime.
 * Treats date-only strings as local dates (no timezone shift).
 *
 * @param dateStr - Date string in YYYY-MM-DD or ISO format
 * @returns Luxon DateTime object
 */
export function parseDate(dateStr: string): DateTime {
  return DateTime.fromISO(dateStr);
}

/**
 * Formats a date for display using locale settings.
 *
 * @param dateStr - ISO date string
 * @param format - Luxon preset or format string (default: DATE_SHORT)
 * @returns Formatted date string
 */
export function formatDateForDisplay(dateStr: string, format: Intl.DateTimeFormatOptions = DateTime.DATE_SHORT): string {
  if (!dateStr) return "";
  const dt = DateTime.fromISO(dateStr);
  if (!dt.isValid) return dateStr;
  return dt.toLocaleString(format);
}

/**
 * AG Grid date filter comparator that handles ISO date strings correctly.
 * Uses Luxon to parse dates without timezone conversion issues.
 */
export function dateFilterComparator(filterLocalDateAtMidnight: Date, cellValue: string): number {
  if (!cellValue) return -1;

  const cellDateTime = DateTime.fromISO(cellValue);
  if (!cellDateTime.isValid) return -1;

  const filterDateTime = DateTime.fromJSDate(filterLocalDateAtMidnight).startOf("day");
  const cellDateOnly = cellDateTime.startOf("day");

  if (cellDateOnly < filterDateTime) return -1;
  if (cellDateOnly > filterDateTime) return 1;
  return 0;
}
```

#### 2. Update components to use shared utilities

Update `ShipmentList.tsx`, `TestList.tsx`, `RouteBasedSensorList.tsx`, `LogShipmentForm.tsx`, `dateAggregation.ts`, and `chartDataTransformers.ts` to import from the shared utilities.

### Success Criteria:

#### Automated Verification:

- [ ] Type checking passes: `make -C frontend typecheck`
- [ ] Linting passes: `make -C frontend lint`
- [ ] All HWQA tests pass: `cd frontend && npm test -- --testPathPattern=HwqaPage`

#### Manual Verification:

- [ ] Re-verify all previous manual tests still pass
- [ ] No regressions in any HWQA functionality

---

## Testing Strategy

### Unit Tests:

- Test `formatDate` function with various date string formats
- Test date comparator with dates across timezone boundaries
- Test Excel date parsing with Date objects from ExcelJS

### Integration Tests:

- End-to-end shipment import flow
- Dashboard data aggregation with known date sets
- Date filtering with boundary cases

### Manual Testing Steps:

1. **Shipment Import Test:**
   - Create CSV with dates: "2025-01-01", "2025-01-15", "2025-01-31"
   - Import and verify all dates stored correctly
   - Test in different browser timezone settings

2. **Dashboard Test:**
   - View dashboard with known shipment dates
   - Verify chart X-axis shows correct dates
   - Test weekly aggregation buckets

3. **Filter Test:**
   - Filter shipments by date range
   - Verify results include/exclude correct dates
   - Test at month/year boundaries

## Performance Considerations

- No performance impact expected (same number of operations)
- Luxon's `fromISO()` is slightly faster than `fromJSDate(new Date())` due to avoided object creation

## Migration Notes

- No database migration required
- No API changes required
- Existing data is not affected (issue was only during import)
- Users may notice previously imported dates were off by one day - this is historical data that would need manual correction if critical

## References

- Original ticket: IWA-14751
- Database schema: `mysql/db/table_change_scripts/V000000234__IWA-9108_CreateHardwareTables.sql`
- Luxon documentation: https://moment.github.io/luxon/
- Related files:
  - `frontend/src/components/HwqaPage/features/shipments/LogShipmentForm.tsx:184`
  - `frontend/src/components/HwqaPage/features/dashboard/PassRateOverview/utils/dateAggregation.ts:82`
  - `frontend/src/components/HwqaPage/features/dashboard/PassRateOverview/utils/chartDataTransformers.ts:48`
