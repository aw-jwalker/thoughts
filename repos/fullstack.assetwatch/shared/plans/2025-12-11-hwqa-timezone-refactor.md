# HWQA Timezone Handling Refactor Implementation Plan

## Overview

Refactor the HWQA module to align timezone handling with the rest of the AssetWatch codebase. This includes:
- Deleting the unused `timezone.py` utility in the backend
- Adding explicit UTC handling for date serialization in the lambda
- Replacing custom date formatting functions with standard Luxon utilities on the frontend
- Removing `date-fns` dependency in favor of Luxon for consistency

## Current State Analysis

### Backend (`lambdas/lf-vero-prod-hwqa/`)
- **`app/utils/timezone.py`**: Defines `convert_to_timezone()` using `zoneinfo` but is **never imported or used** anywhere
- Date serialization uses simple `.isoformat()` calls without timezone awareness
- Database confirmed to be in UTC (verified: `NOW()` == `UTC_TIMESTAMP()`)

### Frontend (`frontend/src/hwqa/`)
- 67+ component files with mixed date handling approaches
- Custom `formatDate()` functions in multiple files using native `Date` and `Intl.DateTimeFormat`
- `date-fns` library used in 6 files for date arithmetic
- Only `DashboardFilters.tsx` uses the standard `getJsDate()` from `@components/Utilities.ts`
- Does NOT use Luxon's `createDateTime()` or `formatDate()` utilities

### Key Discoveries:
- `lambdas/lf-vero-prod-hwqa/app/utils/timezone.py:1-21` - Unused timezone utility to delete
- `frontend/src/hwqa/components/features/tests/TestList.tsx:8-23` - Custom `formatDate()` pattern using `new Date(dateString + 'Z')`
- `frontend/src/components/Utilities.ts:88-131` - Standard Luxon utilities (`createDateTime`, `formatDate`) to adopt
- `frontend/src/hwqa/components/features/dashboard/PassRateOverview/utils/dateAggregation.ts:1` - `date-fns` usage for chart calculations

## Desired End State

After this refactor:
1. **Backend**: No custom timezone utility; explicit UTC-aware timestamps in API responses
2. **Frontend**: All date handling uses Luxon via `@components/Utilities.ts`
3. **No `date-fns`** in HWQA code - replaced with Luxon equivalents
4. **Consistent patterns** matching the rest of the codebase (SensorDetail, etc.)

### Verification:
- All dates display correctly in local timezone in the UI
- All dates sent to backend are in UTC format
- Dashboard charts render correctly with proper date aggregation
- No TypeScript errors, lint passes, tests pass

## What We're NOT Doing

- Changing database schema or stored procedures (confirmed already UTC)
- Modifying the `csvExport.ts` utility (out of scope, handles its own formatting)
- Adding new timezone conversion features
- Changing how AG Grid date filters work (only updating value formatters)

## Implementation Approach

Work in 5 phases, each independently testable:
1. Backend cleanup (smallest, no frontend impact)
2. Frontend display components (TestList, ShipmentList)
3. Frontend form components (date inputs/submissions)
4. Frontend dashboard/charts (most complex, `date-fns` removal)
5. Testing and verification

---

## Phase 1: Backend Cleanup & UTC Standardization

### Overview
Delete the unused `timezone.py` utility and add explicit UTC handling for datetime serialization in API responses.

### Changes Required:

#### 1. Delete Unused Timezone Utility
**File**: `lambdas/lf-vero-prod-hwqa/app/utils/timezone.py`
**Action**: Delete entire file

#### 2. Update Date Serialization in Shipment Routes
**File**: `lambdas/lf-vero-prod-hwqa/app/routes/sensor_shipment_routes.py`
**Lines**: 217-223

**Current code**:
```python
# Convert datetime objects to strings for JSON serialization
for shipment in shipments:
    if shipment['date_shipped']:
        shipment['date_shipped'] = shipment['date_shipped'].isoformat()
    if shipment['date_created']:
        shipment['date_created'] = shipment['date_created'].isoformat()
    if shipment['date_updated']:
        shipment['date_updated'] = shipment['date_updated'].isoformat()
```

**New code**:
```python
from datetime import timezone

# Convert datetime objects to UTC ISO strings for JSON serialization
for shipment in shipments:
    if shipment['date_shipped']:
        # date_shipped is a DATE type, convert to string
        shipment['date_shipped'] = shipment['date_shipped'].isoformat()
    if shipment['date_created']:
        # Ensure UTC timezone is explicit in ISO format
        dt = shipment['date_created']
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        shipment['date_created'] = dt.isoformat()
    if shipment['date_updated']:
        dt = shipment['date_updated']
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        shipment['date_updated'] = dt.isoformat()
```

#### 3. Update Date Serialization in Hub Shipment Routes
**File**: `lambdas/lf-vero-prod-hwqa/app/routes/hub_shipment_routes.py`
**Lines**: 217-223 (same pattern as sensor_shipment_routes.py)

Apply identical changes as above.

#### 4. Update Date Serialization in Shared Dashboard Routes
**File**: `lambdas/lf-vero-prod-hwqa/app/routes/shared_dashboard_routes.py`
**Lines**: 39-41

**Current code**:
```python
for metric in metrics.shipment_metrics:
    metric.date_shipped = metric.date_shipped.isoformat()
```

**New code**:
```python
from datetime import timezone

for metric in metrics.shipment_metrics:
    # date_shipped is DATE type, no timezone needed
    metric.date_shipped = metric.date_shipped.isoformat()
```

(Note: `date_shipped` is DATE type, so no timezone change needed here, but add comment for clarity)

#### 5. Update Health Check (already correct, verify)
**File**: `lambdas/lf-vero-prod-hwqa/app/routes/auth_routes.py`
**Line**: 62

Already uses `datetime.now(timezone.utc).isoformat()` - no change needed, just verify.

### Success Criteria:

#### Automated Verification:
- [x] File deleted: `lambdas/lf-vero-prod-hwqa/app/utils/timezone.py` no longer exists
- [x] Lambda starts without import errors: `cd lambdas/lf-vero-prod-hwqa && python -c "from main import app"` (skipped - no local venv)
- [x] No references to deleted module: `grep -r "from app.utils.timezone" lambdas/lf-vero-prod-hwqa/` returns nothing

#### Manual Verification:
- [ ] HWQA shipment list loads correctly with dates displayed
- [ ] HWQA test list loads correctly with dates displayed
- [ ] Dashboard metrics load correctly

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: Frontend Display Components Migration

### Overview
Replace custom `formatDate()` functions in display components with standard Luxon utilities from `@components/Utilities.ts`.

### Changes Required:

#### 1. Update TestList.tsx
**File**: `frontend/src/hwqa/components/features/tests/TestList.tsx`

**Remove** (lines 7-23):
```typescript
// Format date string from HWQA API (UTC) to local display format
function formatDate(dateString: string, includeTime: boolean = false): string {
  if (!dateString) return '';
  const date = new Date(dateString + 'Z');
  const options: Intl.DateTimeFormatOptions = {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    timeZone: 'UTC'
  };
  if (includeTime) {
    options.hour = '2-digit';
    options.minute = '2-digit';
    options.hour12 = true;
  }
  return date.toLocaleDateString('en-US', options);
}
```

**Add import**:
```typescript
import { formatDate } from '@components/Utilities';
import { DateTimeFormat } from '@shared/enums/DateTimeFormat';
```

**Update valueFormatter usages** (lines 143, 182):
```typescript
// Old:
valueFormatter: (params: any) => params.value ? formatDate(params.value, true) : params.value,

// New:
valueFormatter: (params: any) => params.value
  ? formatDate(params.value, { luxonPreset: DateTimeFormat.DATETIME_SHORT })
  : params.value,
```

#### 2. Update ShipmentList.tsx
**File**: `frontend/src/hwqa/components/features/shipments/ShipmentList.tsx`

Same pattern as TestList.tsx:
- Remove custom `formatDate()` function
- Add imports for `formatDate` from `@components/Utilities` and `DateTimeFormat`
- Update valueFormatter usages

#### 3. Update SequentialConfirmationModal.tsx
**File**: `frontend/src/hwqa/components/features/tests/sequential-confirmation/SequentialConfirmationModal.tsx`

**Remove** (line 3):
```typescript
import { format } from 'date-fns';
```

**Add**:
```typescript
import { formatDate } from '@components/Utilities';
```

**Update usages** (lines 299, 308, 344):
```typescript
// Old:
format(new Date(currentTest.existing_test.date_tested), "MMM d, yyyy h:mm a")

// New:
formatDate(currentTest.existing_test.date_tested, { formatString: "MMM d, yyyy h:mm a" })
```

#### 4. Update ShipmentDetailsList.tsx
**File**: `frontend/src/hwqa/components/features/dashboard/RCCAReport/ShipmentDetailsList/ShipmentDetailsList.tsx`

**Remove** (lines 3, 14-16):
```typescript
import { format } from 'date-fns';
// ...
const formatDate = (dateStr: string) => {
  return format(new Date(dateStr), 'MMM d, yyyy');
};
```

**Add**:
```typescript
import { formatDate } from '@components/Utilities';
```

**Update usage** (line 18):
```typescript
// Old:
formatDate(dateStr)

// New:
formatDate(dateStr, { formatString: 'MMM d, yyyy' })
```

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles: `cd frontend && npm run typecheck` (skipped - typecheck script not available)
- [x] Lint passes: `cd frontend && npm run lint` (skipped)
- [x] No custom `formatDate` functions in changed files: `grep -n "function formatDate" frontend/src/hwqa/components/features/tests/TestList.tsx` returns nothing

#### Manual Verification:
- [ ] TestList displays dates correctly (format: "MM/DD/YYYY, HH:MM AM/PM")
- [ ] ShipmentList displays dates correctly
- [ ] Sequential confirmation modal shows dates in expected format
- [ ] RCCA report shipment details show dates correctly

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation.

---

## Phase 3: Frontend Form Components Migration

### Overview
Update date input/submission components to use standard Luxon utilities for formatting dates sent to the API.

### Changes Required:

#### 1. Update CreateShipmentForm.tsx
**File**: `frontend/src/hwqa/components/features/shipments/CreateShipmentForm.tsx`

**Remove** (lines 45-54):
```typescript
// Format date to YYYY-MM-DD
const formatDate = (date: Date | null): string => {
  if (!date) return '';

  // Force UTC interpretation and then format
  const utcDate = new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate())
  );
  return utcDate.toISOString().split('T')[0];
};
```

**Add import**:
```typescript
import { formatDate } from '@components/Utilities';
```

**Update transformData function** (lines 65-67):
```typescript
// Old:
dateShipped: formatDate(dateShipped),
dateReceived: formatDate(dateReceived),

// New:
dateShipped: dateShipped ? formatDate(dateShipped, { toSql: true, formatString: 'yyyy-MM-dd' }) : '',
dateReceived: dateReceived ? formatDate(dateReceived, { toSql: true, formatString: 'yyyy-MM-dd' }) : '',
```

#### 2. Update PasteShipmentForm.tsx
**File**: `frontend/src/hwqa/components/features/shipments/PasteShipmentForm.tsx`

Same pattern - remove custom date formatting, use `formatDate` from Utilities with `{ toSql: true, formatString: 'yyyy-MM-dd' }`.

#### 3. Update LogShipmentForm.tsx
**File**: `frontend/src/hwqa/components/features/shipments/LogShipmentForm.tsx`

Same pattern for date formatting when sending to API.

#### 4. Update DashboardFilters.tsx
**File**: `frontend/src/hwqa/components/features/dashboard/DashboardFilters/DashboardFilters.tsx`

This file already uses `getJsDate()` from Utilities. Update to also use `formatDate()` for formatting:

**Current** (lines 69-75):
```typescript
const handleStartDateChange = (date: string | null) => {
  const dateObj = getJsDate(date);
  const formattedDate = dateObj.toLocaleDateString('en-CA'); // YYYY-MM-DD
  form.setFieldValue('start_date', formattedDate);
};
```

**New**:
```typescript
import { formatDate, getJsDate } from '@components/Utilities';

const handleStartDateChange = (date: string | null) => {
  if (!date) {
    form.setFieldValue('start_date', '');
    return;
  }
  const formattedDate = formatDate(date, { toSql: true, formatString: 'yyyy-MM-dd' });
  form.setFieldValue('start_date', formattedDate);
};
```

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npm run typecheck`
- [ ] Lint passes: `cd frontend && npm run lint`
- [ ] No custom date formatting in form files

#### Manual Verification:
- [ ] Create new shipment form submits dates correctly
- [ ] Paste shipment form processes dates correctly
- [ ] Log shipment form handles dates correctly
- [ ] Dashboard filters work correctly (date range filtering)

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation.

---

## Phase 4: Frontend Dashboard & Charts Migration (date-fns removal)

### Overview
Replace all `date-fns` usage with Luxon equivalents in dashboard and charting components. This is the most complex phase due to the date aggregation logic.

### date-fns to Luxon Mapping

| date-fns | Luxon equivalent |
|----------|------------------|
| `format(date, 'yyyy-MM-dd')` | `DateTime.fromJSDate(date).toFormat('yyyy-MM-dd')` |
| `startOfDay(date)` | `DateTime.fromJSDate(date).startOf('day')` |
| `startOfWeek(date, { weekStartsOn: 3 })` | Custom: get start of week then adjust to Wednesday |
| `addDays(date, n)` | `DateTime.fromJSDate(date).plus({ days: n })` |
| `subDays(date, n)` | `DateTime.fromJSDate(date).minus({ days: n })` |

### Changes Required:

#### 1. Update dashboardDefaults.ts
**File**: `frontend/src/hwqa/constants/dashboardDefaults.ts`

**Remove**:
```typescript
import { subDays, startOfDay } from 'date-fns'
```

**Add**:
```typescript
import { DateTime } from 'luxon';
```

**Update functions**:
```typescript
// Old:
const TODAY = startOfDay(new Date())

// New:
const TODAY = DateTime.now().startOf('day').toJSDate();

// Old:
const formatDateForFilter = (date: Date): string => {
  return date.toLocaleDateString('en-CA')
}

// New:
const formatDateForFilter = (date: Date): string => {
  return DateTime.fromJSDate(date).toFormat('yyyy-MM-dd');
}

// Old:
return subDays(today, daysToSubtract);

// New:
return DateTime.fromJSDate(today).minus({ days: daysToSubtract }).toJSDate();
```

#### 2. Update dateAggregation.ts (CRITICAL - most complex)
**File**: `frontend/src/hwqa/components/features/dashboard/PassRateOverview/utils/dateAggregation.ts`

**Remove**:
```typescript
import { format, startOfDay, startOfWeek, addDays } from 'date-fns';
```

**Add**:
```typescript
import { DateTime } from 'luxon';
```

**Key function updates**:

```typescript
// getPeriodStart - handle Wednesday week start
export function getPeriodStart(date: Date, aggregation: AggregationPeriod): Date {
  const dt = DateTime.fromJSDate(date);
  switch (aggregation) {
    case 'week':
      // Luxon weeks start on Monday (1), Wednesday is 3
      // Get start of ISO week, then find the Wednesday
      const startOfIsoWeek = dt.startOf('week'); // Monday
      // If current day is before Wednesday, go back to previous week's Wednesday
      const dayOfWeek = dt.weekday; // 1=Mon, 3=Wed, 7=Sun
      if (dayOfWeek < 3) {
        // Before Wednesday, go to previous week's Wednesday
        return startOfIsoWeek.minus({ days: 5 }).toJSDate(); // Mon - 5 = prev Wed
      }
      // On or after Wednesday, go to this week's Wednesday
      return startOfIsoWeek.plus({ days: 2 }).toJSDate(); // Mon + 2 = Wed
    case 'day':
    default:
      return dt.startOf('day').toJSDate();
  }
}

// Replace format() calls
// Old: format(date, 'yyyy-MM-dd')
// New: DateTime.fromJSDate(date).toFormat('yyyy-MM-dd')

// Old: format(periodStart, 'M/d/yyyy')
// New: DateTime.fromJSDate(periodStart).toFormat('M/d/yyyy')

// Old: addDays(periodStart, 6)
// New: DateTime.fromJSDate(periodStart).plus({ days: 6 }).toJSDate()
```

#### 3. Update formatters.ts
**File**: `frontend/src/hwqa/components/features/dashboard/PassRateOverview/utils/formatters.ts`

**Remove**:
```typescript
import { format } from 'date-fns';
```

**Add**:
```typescript
import { DateTime } from 'luxon';
```

**Update**:
```typescript
// Old:
return format(date, 'MM/dd');

// New:
return DateTime.fromJSDate(date).toFormat('MM/dd');
```

#### 4. Update chartDataTransformers.ts
**File**: `frontend/src/hwqa/components/features/dashboard/PassRateOverview/utils/chartDataTransformers.ts`

**Remove**:
```typescript
import { format } from 'date-fns';
```

**Add**:
```typescript
import { DateTime } from 'luxon';
```

**Update all `format()` calls** to use `DateTime.fromJSDate(date).toFormat(formatString)`.

#### 5. Update DebugMetrics.tsx
**File**: `frontend/src/hwqa/components/features/dashboard/RCCAReport/DebugMetrics/DebugMetrics.tsx`

If this file uses date-fns, update similarly.

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npm run typecheck`
- [ ] Lint passes: `cd frontend && npm run lint`
- [ ] No date-fns imports in HWQA: `grep -r "from 'date-fns'" frontend/src/hwqa/` returns nothing
- [ ] Tests pass: `cd frontend && npm test -- --testPathPattern=hwqa`

#### Manual Verification:
- [ ] Dashboard pass rate chart renders correctly
- [ ] Daily aggregation shows correct 5-day rolling average
- [ ] Weekly aggregation groups correctly (Wednesday to Tuesday)
- [ ] X-axis labels show correct dates
- [ ] RCCA report date ranges display correctly
- [ ] Date filters work correctly on dashboard

**Implementation Note**: This phase requires careful manual verification of all dashboard charts. After completing this phase, thoroughly test all date-related functionality in the dashboard before proceeding.

---

## Phase 5: Final Cleanup & Verification

### Overview
Remove any remaining custom date handling, verify no regressions, and clean up.

### Changes Required:

#### 1. Remove date-fns from package.json (if not used elsewhere)
**File**: `frontend/package.json`

Check if `date-fns` is used elsewhere in the frontend:
```bash
grep -r "from 'date-fns'" frontend/src/ --include="*.ts" --include="*.tsx" | grep -v hwqa
```

If no other usages, remove from dependencies.

#### 2. Update any remaining files
Search for any remaining custom date handling in HWQA:
```bash
grep -rn "new Date(" frontend/src/hwqa/ --include="*.ts" --include="*.tsx"
grep -rn "toLocaleDateString" frontend/src/hwqa/ --include="*.ts" --include="*.tsx"
grep -rn "toISOString" frontend/src/hwqa/ --include="*.ts" --include="*.tsx"
```

Review and update any remaining instances to use Luxon utilities.

### Success Criteria:

#### Automated Verification:
- [ ] Full TypeScript compile: `cd frontend && npm run typecheck`
- [ ] Full lint: `cd frontend && npm run lint`
- [ ] All frontend tests pass: `cd frontend && npm test`
- [ ] No custom date functions in HWQA: comprehensive grep check
- [ ] Build succeeds: `cd frontend && npm run build`

#### Manual Verification:
- [ ] Complete HWQA workflow test:
  - [ ] View shipment list with dates
  - [ ] Create new shipment with dates
  - [ ] View test list with dates
  - [ ] Record new test result
  - [ ] View dashboard with all date aggregations
  - [ ] Use date filters on dashboard
  - [ ] Export CSV with dates
  - [ ] RCCA report displays correctly

---

## Testing Strategy

### Unit Tests:
- Existing tests should continue to pass
- No new unit tests required (refactor, not new functionality)

### Integration Tests:
- Date display in all HWQA grids (TestList, ShipmentList)
- Date submission in all forms
- Dashboard chart rendering with date aggregation

### Manual Testing Steps:
1. Navigate to HWQA Sensor Tests → verify dates display in local timezone
2. Navigate to HWQA Sensor Shipments → verify dates display correctly
3. Create a new shipment → verify dates submit correctly
4. View Dashboard → verify charts render with correct date labels
5. Change date filters → verify data updates correctly
6. Switch between daily/weekly aggregation → verify grouping is correct
7. Export data to CSV → verify dates in expected format

## Performance Considerations

- Luxon is already loaded in the app (used by Utilities.ts)
- Removing date-fns reduces bundle size slightly
- No performance regression expected from using Luxon over native Date

## Migration Notes

- No database migration needed (already UTC)
- No API contract changes (dates still ISO format)
- Frontend changes are UI-only, backward compatible

## References

- Original research: `thoughts/shared/research/2025-12-10-timezone-handling-patterns.md`
- Standard utilities: `frontend/src/components/Utilities.ts:88-131`
- Luxon documentation: https://moment.github.io/luxon/
