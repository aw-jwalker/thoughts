# HWQA Notification System Unification Plan

## Overview

Refactor HWQA to use the same `react-toastify` notification system as the rest of AssetWatch, eliminating the duplicate Mantine-based notification system currently in use.

## Current State Analysis

### AssetWatch Main App
- Uses `react-toastify` with `ToastContainer` in `AppLayout.tsx`
- Configuration: `theme="colored"`, `autoClose={2000}`, `position="top-center"`
- Custom colors in `App.css` for each toast type
- Direct usage: `toast.success()`, `toast.error()`, `toast.warning()`, `toast.info()`

### HWQA App (Current)
- Uses `@mantine/notifications` (inconsistently)
- 5 files use direct `notifications.show()` from Mantine
- 1 file uses custom wrapper (`showSuccess`, `showError`)
- Custom wrapper exists at `frontend/src/hwqa/components/common/Notifications/`

### Route Hierarchy (confirms ToastContainer availability)
```
rootRoute (AppLayout with ToastContainer)
  └── protectedRoute
        └── hwqaRoute (HwqaPage)
              └── hwqa child routes
```

**Conclusion**: HWQA pages already render inside `AppLayout`, so `ToastContainer` is available.

## Desired End State

1. All HWQA notification calls use `toast` from `react-toastify`
2. HWQA Notifications wrapper directory is deleted
3. Notification appearance is consistent with rest of AssetWatch
4. Future improvements to AssetWatch notifications automatically apply to HWQA

### Verification
- All HWQA pages show toast notifications in the same style as main app
- No imports from `@mantine/notifications` in `frontend/src/hwqa/`
- No `frontend/src/hwqa/components/common/Notifications/` directory exists

## What We're NOT Doing

- Not changing any notification logic/conditions (only the display mechanism)
- Not adding new notification types or features
- Not modifying the main AssetWatch notification system
- Not changing notification messages (only removing titles where applicable)

## Implementation Approach

> **NOTE**: Skip all automated verification steps (TypeScript, linting) during implementation. The user will run these manually at the end after all phases are complete.

Replace Mantine notification calls with react-toastify equivalents:

| Mantine | react-toastify |
|---------|----------------|
| `notifications.show({ title, message, color: 'green' })` | `toast.success(message)` |
| `notifications.show({ title, message, color: 'red' })` | `toast.error(message)` |
| `notifications.show({ title, message, color: 'yellow' })` | `toast.warning(message)` |
| `notifications.show({ title, message, color: 'blue' })` | `toast.info(message)` |
| `showSuccess(message)` | `toast.success(message)` |
| `showError(message)` | `toast.error(message)` |

---

## Phase 1: Update LogTestForm.tsx

### Overview
This file uses the custom Notifications wrapper. Replace with direct react-toastify usage.

### Changes Required:

**File**: `frontend/src/hwqa/components/features/tests/LogTestForm.tsx`

**Change import** (line 15):
```tsx
// Before
import { showSuccess, showError } from "../../common/Notifications";

// After
import { toast } from "react-toastify";
```

**Replace all calls**:
- Line 104: `showError(initialError)` → `toast.error(initialError)`
- Line 133: `showError(...)` → `toast.error(...)`
- Line 150: `showError(...)` → `toast.error(...)`
- Line 177: `showError("No serial numbers found for the selected criteria")` → `toast.error("No serial numbers found for the selected criteria")`
- Line 180: `showSuccess(...)` → `toast.success(...)`
- Line 184: `showError(...)` → `toast.error(...)`
- Line 210: `showError("Please enter at least one valid serial number")` → `toast.error("Please enter at least one valid serial number")`
- Line 243: `showError(errorMessage)` → `toast.error(errorMessage)`
- Line 268: `showSuccess("No changes were made - no serial numbers provided")` → `toast.success("No changes were made - no serial numbers provided")`
- Line 298: `showSuccess(...)` → `toast.success(...)`
- Line 309: `showError(errorMessage)` → `toast.error(errorMessage)`
- Line 333: `showSuccess("No changes were made - all tests were skipped")` → `toast.success("No changes were made - all tests were skipped")`
- Line 460: `showError("Please enter at least one valid serial number")` → `toast.error("Please enter at least one valid serial number")`

### Success Criteria:
- [ ] Log test form shows success/error toasts correctly

---

## Phase 2: Update CSVExportButton.tsx

### Overview
Replace Mantine notifications with react-toastify.

### Changes Required:

**File**: `frontend/src/hwqa/components/common/CSVExportButton/CSVExportButton.tsx`

**Change import** (line 6):
```tsx
// Before
import { notifications } from '@mantine/notifications';

// After
import { toast } from "react-toastify";
```

**Remove unused import** (line 3): Remove `IconCheck` from tabler icons (no longer needed for notification icon)

**Replace all calls**:
- Lines 41-45:
```tsx
// Before
notifications.show({
  title: 'Export Error',
  message: 'Grid is not ready for export',
  color: 'red'
});

// After
toast.error('Grid is not ready for export');
```

- Lines 65-70:
```tsx
// Before
notifications.show({
  title: 'Export Successful',
  message: `Exported ${stats.exportedRows} ${dataType} records to CSV`,
  color: 'green',
  icon: <IconCheck size={16} />
});

// After
toast.success(`Exported ${stats.exportedRows} ${dataType} records to CSV`);
```

- Lines 75-79:
```tsx
// Before
notifications.show({
  title: 'Export Failed',
  message: 'Failed to export data. Please try again.',
  color: 'red'
});

// After
toast.error('Failed to export data. Please try again.');
```

### Success Criteria:
- [ ] CSV export shows success/error toasts correctly

---

## Phase 3: Update LogShipmentForm.tsx

### Overview
Replace Mantine notifications with react-toastify.

### Changes Required:

**File**: `frontend/src/hwqa/components/features/shipments/LogShipmentForm.tsx`

**Change import** (line 4):
```tsx
// Before
import { notifications } from '@mantine/notifications';

// After
import { toast } from "react-toastify";
```

**Replace all calls**:
- Lines 101-105:
```tsx
// Before
notifications.show({
  title: 'Warning',
  message: 'Duplicate column headers detected in your Excel file. Numbers have been appended to make them unique.',
  color: 'yellow'
});

// After
toast.warning('Duplicate column headers detected in your Excel file. Numbers have been appended to make them unique.');
```

- Lines 149-153:
```tsx
// Before
notifications.show({
  title: 'Error',
  message: 'Failed to process file. Please ensure it\'s a valid Excel file.',
  color: 'red'
});

// After
toast.error("Failed to process file. Please ensure it's a valid Excel file.");
```

- Lines 238-244:
```tsx
// Before
notifications.show({
  title: 'Success',
  message: result && typeof result === 'object'
    ? `Imported ${result.new_shipments} new and updated ${result.updated_shipments} shipments`
    : 'Shipment data processed successfully',
  color: 'green'
});

// After
toast.success(result && typeof result === 'object'
  ? `Imported ${result.new_shipments} new and updated ${result.updated_shipments} shipments`
  : 'Shipment data processed successfully');
```

- Lines 248-252:
```tsx
// Before
notifications.show({
  title: 'Error',
  message: error instanceof Error ? error.message : 'Import failed',
  color: 'red'
});

// After
toast.error(error instanceof Error ? error.message : 'Import failed');
```

### Success Criteria:
- [ ] Log shipment form shows success/warning/error toasts correctly

---

## Phase 4: Update CreateShipmentForm.tsx

### Overview
Replace Mantine notifications with react-toastify.

### Changes Required:

**File**: `frontend/src/hwqa/components/features/shipments/CreateShipmentForm.tsx`

**Change import** (line 4):
```tsx
// Before
import { notifications } from '@mantine/notifications';

// After
import { toast } from "react-toastify";
```

**Replace all calls**:
- Lines 161-166:
```tsx
// Before
notifications.show({
  title: 'Success',
  message: `Imported ${result.new_shipments} new and updated ${result.updated_shipments} shipments`,
  color: 'green'
});

// After
toast.success(`Imported ${result.new_shipments} new and updated ${result.updated_shipments} shipments`);
```

- Lines 189-194:
```tsx
// Before
notifications.show({
  title: 'Error',
  message: error instanceof Error ? error.message : 'Import failed',
  color: 'red',
  autoClose: false
});

// After
toast.error(error instanceof Error ? error.message : 'Import failed', { autoClose: false });
```

### Success Criteria:
- [ ] Create shipment form shows success/error toasts correctly

---

## Phase 5: Update PasteShipmentForm.tsx

### Overview
Replace Mantine notifications with react-toastify.

### Changes Required:

**File**: `frontend/src/hwqa/components/features/shipments/PasteShipmentForm.tsx`

**Change import** (line 3):
```tsx
// Before
import { notifications } from '@mantine/notifications';

// After
import { toast } from "react-toastify";
```

**Replace all calls**:
- Lines 59-63:
```tsx
// Before
notifications.show({
  title: 'Data Parsed',
  message: `${rows.length} rows of data ready to edit or import`,
  color: 'blue'
});

// After
toast.info(`${rows.length} rows of data ready to edit or import`);
```

- Lines 149-154:
```tsx
// Before
notifications.show({
  title: 'Success',
  message: `Imported ${result.new_shipments} new and updated ${result.updated_shipments} shipments`,
  color: 'green'
});

// After
toast.success(`Imported ${result.new_shipments} new and updated ${result.updated_shipments} shipments`);
```

- Lines 177-182:
```tsx
// Before
notifications.show({
  title: 'Error',
  message: error instanceof Error ? error.message : 'Import failed',
  color: 'red',
  autoClose: false
});

// After
toast.error(error instanceof Error ? error.message : 'Import failed', { autoClose: false });
```

- Lines 233-237:
```tsx
// Before
notifications.show({
  title: 'Success',
  message: 'Sample data copied to clipboard',
  color: 'green'
});

// After
toast.success('Sample data copied to clipboard');
```

- Lines 240-244:
```tsx
// Before
notifications.show({
  title: 'Error',
  message: 'Failed to copy sample data',
  color: 'red'
});

// After
toast.error('Failed to copy sample data');
```

### Success Criteria:
- [ ] Paste shipment form shows success/info/error toasts correctly

---

## Phase 6: Delete HWQA Notifications Directory

### Overview
Remove the now-unused custom Notifications wrapper.

### Changes Required:

**Delete directory**: `frontend/src/hwqa/components/common/Notifications/`

This removes:
- `frontend/src/hwqa/components/common/Notifications/notifications.tsx`
- `frontend/src/hwqa/components/common/Notifications/index.ts`

### Success Criteria:
- [ ] Directory `frontend/src/hwqa/components/common/Notifications/` does not exist
- [ ] All HWQA pages with notifications still work correctly

---

## Testing Strategy

> **NOTE**: Automated verification is to be run by the user after all phases are complete, not during implementation.

### Automated Tests (Run by user at end)
- TypeScript compilation: `cd frontend && npx tsc --noEmit`
- Linting: `cd frontend && npm run lint`
- Grep verification: `grep -r "@mantine/notifications" frontend/src/hwqa/` should return no results

### Manual Testing Steps
1. Navigate to HWQA Sensor Tests page → Log a test → Verify success/error toasts appear
2. Navigate to HWQA Sensor Shipments → Create shipment → Verify success toast
3. Navigate to HWQA Sensor Shipments → Paste shipment data → Verify info/success toasts
4. Navigate to HWQA Sensor Shipments → Upload Excel file → Verify warning/error/success toasts
5. Export any grid to CSV → Verify success toast appears
6. Trigger error conditions → Verify error toasts appear correctly

## References

- AssetWatch ToastContainer config: `frontend/src/components/layout/AppLayout.tsx:72-77`
- AssetWatch toast CSS: `frontend/src/styles/css/App.css:34-45`
- react-toastify docs: https://fkhadra.github.io/react-toastify/
