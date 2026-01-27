# IWA-14069: Migrate HWQA to AssetWatch Enterprise AG Grid DataTable

## Overview

Replace the custom HWQA DataTable component with the existing AssetWatch DataTable component to fully leverage enterprise AG Grid functionality. This migration standardizes the codebase, enables enterprise features (sidebar, column state persistence, range selection), and removes duplicate code.

## Current State Analysis

### HWQA DataTable (`src/hwqa/components/common/DataTable/DataTable.tsx`)
- Uses `ag-grid-community` imports (not enterprise)
- Uses `ag-theme-alpine` theme
- Custom CSV export via `csvExport.ts` utilities
- Filter state persistence only (no column state)
- Emoji-based status indicators (✅❌⚪)
- Floating filter toggle UI
- 14 props, simpler interface

### AssetWatch DataTable (`src/components/common/DataTable.tsx`)
- Uses `ag-grid-enterprise` imports
- Uses `ag-theme-balham` theme
- Built-in CSV export via `api.exportDataAsCsv()`
- Full column + filter state persistence
- Cell highlighting via `cellClassRules`
- Enterprise sidebar for columns/filters
- 40+ props, comprehensive interface
- `forwardRef` pattern exposing grid API

### Key Discoveries:
- 8 HWQA components consume the DataTable (`src/hwqa/components/common/DataTable/DataTable.tsx:1-216`)
- Enterprise license already configured (`src/index.tsx:15-17`)
- Cell styling classes already exist (`src/styles/css/App.css:68-116`)
- Only `TestList.tsx` uses emoji status indicators (lines 74-79)

## Desired End State

After this plan is complete:
1. All HWQA tables use the AssetWatch `DataTable` component from `src/components/common/DataTable.tsx`
2. Enterprise features available: sidebar filters/columns, column state persistence, range selection
3. Status indicators use `cellClassRules` with `.grid-cell-ok`, `.grid-cell-critical`, `.grid-cell-gray` classes
4. All custom HWQA DataTable infrastructure removed
5. No `ag-grid-community` style imports remain in HWQA code
6. All tables maintain existing functionality (filtering, sorting, CSV export, pagination)

### Verification:
- `npm run build` completes without errors
- `npm run lint` passes
- All 8 DataTable consumers render correctly
- CSV export works on all tables with `enableCSVExport`
- Filter/column state persists across page refreshes
- Sidebar panels (columns/filters) appear on tables

## What We're NOT Doing

- Changing the AssetWatch DataTable component itself
- Modifying the enterprise license configuration
- Adding new features to the DataTable beyond what exists
- Changing data fetching or service layer code
- Modifying the App.css cell styling classes

## Implementation Approach

Migrate each consumer component individually, then remove the old infrastructure. Each component migration follows the same pattern:
1. Update import to use AssetWatch DataTable
2. Convert props to match AssetWatch API
3. Add sidebar configuration
4. Convert any emoji status to `cellClassRules`
5. Ensure `tableId` is provided (required prop)

---

## Phase 1: Migrate TestList Component (Has Emoji Status)

### Overview
Migrate the most complex consumer first - `TestList.tsx` has emoji-based status rendering that needs conversion to `cellClassRules`.

### Changes Required:

#### 1. Update TestList.tsx
**File**: `frontend/src/hwqa/components/features/tests/TestList.tsx`

**Change 1: Update imports** (lines 1-4)
```typescript
// OLD
import { DataTable } from '../../common/DataTable';
import { ColDef, GridOptions } from 'ag-grid-community';

// NEW
import { DataTable } from '../../../../components/common/DataTable';
import { ColDef, GridOptions, SideBarDef } from 'ag-grid-enterprise';
```

**Change 2: Add sidebar configuration** (after line 7)
```typescript
const sideBar: SideBarDef = {
  toolPanels: [
    {
      id: 'columns',
      labelDefault: 'Columns',
      labelKey: 'columns',
      iconKey: 'columns',
      toolPanel: 'agColumnsToolPanel',
    },
    {
      id: 'filters',
      labelDefault: 'Filters',
      labelKey: 'filters',
      iconKey: 'filter',
      toolPanel: 'agFiltersToolPanel',
    },
  ],
};
```

**Change 3: Convert pass_flag column from emoji to cellClassRules** (lines 72-89)
```typescript
// OLD
{
  field: 'pass_flag',
  headerName: 'Status',
  width: 120,
  cellRenderer: (params: { value: boolean | null }) => {
    if (params.value === null) return '⚪ Not Tested';
    return params.value ? '✅ Pass' : '❌ Fail';
  },
  filter: 'agSetColumnFilter',
  filterParams: {
    values: [true, false, null],
    cellRenderer: (params: { value: boolean | null }) => {
      if (params.value === null) return 'Not Tested';
      return params.value ? 'Pass' : 'Fail';
    },
  },
}

// NEW
{
  field: 'pass_flag',
  headerName: 'Status',
  width: 120,
  valueFormatter: ({ value }: { value: boolean | null }) => {
    if (value === null) return 'Not Tested';
    return value ? 'Pass' : 'Fail';
  },
  cellClassRules: {
    'grid-cell-ok': ({ value }: { value: boolean | null }) => value === true,
    'grid-cell-critical': ({ value }: { value: boolean | null }) => value === false,
    'grid-cell-gray': ({ value }: { value: boolean | null }) => value === null,
  },
  filter: 'agSetColumnFilter',
  filterParams: {
    values: [true, false, null],
    valueFormatter: (params: { value: boolean | null }) => {
      if (params.value === null) return 'Not Tested';
      return params.value ? 'Pass' : 'Fail';
    },
  },
}
```

**Change 4: Update DataTable usage** (lines 236-247)
```typescript
// OLD
<DataTable
  data={data || []}
  columns={testColumns}
  isLoading={isLoading}
  height={height}
  gridOptions={gridOptions}
  tableId="test-results-table"
  rightControls={limitControl}
  enableCSVExport={true}
  csvFilename="test-results"
  showAdvancedCSVOptions={true}
/>

// NEW
<DataTable
  data={data || []}
  columns={testColumns}
  tableId="test-results-table"
  sideBar={sideBar}
  paginationPageSize={50}
  allowDownloadCSV={true}
  customActionItems={limitControl}
/>
```

### Success Criteria:

#### Automated Verification:
- [ ] Build passes: `cd frontend && npm run build`
- [ ] Lint passes: `cd frontend && npm run lint`
- [ ] TypeScript passes: `cd frontend && npm run typecheck`

#### Manual Verification:
- [ ] TestList table renders with data on SensorTestsPage and HubTestsPage
- [ ] Status column shows colored cells (green=Pass, red=Fail, gray=Not Tested)
- [ ] Sidebar appears with Columns and Filters panels
- [ ] CSV export works via action bar download button
- [ ] Filter state persists after page refresh
- [ ] Column state (order, width, visibility) persists after page refresh

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: Migrate ShipmentList Component

### Overview
Migrate the shipment list table - no emoji conversion needed, straightforward prop mapping.

### Changes Required:

#### 1. Update ShipmentList.tsx
**File**: `frontend/src/hwqa/components/features/shipments/ShipmentList.tsx`

**Change 1: Update imports** (lines 1-4)
```typescript
// OLD
import { DataTable } from '../../common/DataTable/DataTable';
import { ColDef, GridOptions } from 'ag-grid-community';

// NEW
import { DataTable } from '../../../../components/common/DataTable';
import { ColDef, GridOptions, SideBarDef } from 'ag-grid-enterprise';
```

**Change 2: Add sidebar configuration** (after line 4)
```typescript
const sideBar: SideBarDef = {
  toolPanels: [
    {
      id: 'columns',
      labelDefault: 'Columns',
      labelKey: 'columns',
      iconKey: 'columns',
      toolPanel: 'agColumnsToolPanel',
    },
    {
      id: 'filters',
      labelDefault: 'Filters',
      labelKey: 'filters',
      iconKey: 'filter',
      toolPanel: 'agFiltersToolPanel',
    },
  ],
};
```

**Change 3: Update DataTable usage** (lines 194-205)
```typescript
// OLD
<DataTable
  title=""
  data={safeData}
  columns={shipmentColumns}
  isLoading={isLoading}
  height={height}
  gridOptions={gridOptions}
  tableId="shipment-list-table"
  enableCSVExport={true}
  csvFilename="shipment-list"
  showAdvancedCSVOptions={true}
/>

// NEW
<DataTable
  data={safeData}
  columns={shipmentColumns}
  tableId="shipment-list-table"
  sideBar={sideBar}
  paginationPageSize={50}
  allowDownloadCSV={true}
/>
```

### Success Criteria:

#### Automated Verification:
- [ ] Build passes: `cd frontend && npm run build`
- [ ] Lint passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] ShipmentList table renders on SensorShipmentsPage and HubShipmentsPage
- [ ] Sidebar appears with Columns and Filters panels
- [ ] CSV export works
- [ ] Filter/column state persists

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation.

---

## Phase 3: Migrate RouteBasedSensorList Component

### Overview
Migrate the route-based sensor conversion list.

### Changes Required:

#### 1. Update RouteBasedSensorList.tsx
**File**: `frontend/src/hwqa/components/features/conversion/SensorConversion/RouteBasedSensorList.tsx`

**Change 1: Update imports** (lines 2-3)
```typescript
// OLD
import { DataTable } from '../../../common/DataTable/DataTable';
import { ColDef, GridOptions } from 'ag-grid-community';

// NEW
import { DataTable } from '../../../../../components/common/DataTable';
import { ColDef, GridOptions, SideBarDef } from 'ag-grid-enterprise';
```

**Change 2: Add sidebar configuration** (after imports)
```typescript
const sideBar: SideBarDef = {
  toolPanels: [
    {
      id: 'columns',
      labelDefault: 'Columns',
      labelKey: 'columns',
      iconKey: 'columns',
      toolPanel: 'agColumnsToolPanel',
    },
    {
      id: 'filters',
      labelDefault: 'Filters',
      labelKey: 'filters',
      iconKey: 'filter',
      toolPanel: 'agFiltersToolPanel',
    },
  ],
};
```

**Change 3: Update DataTable usage** (lines 189-200)
```typescript
// OLD
<DataTable
  title=""
  data={routeBasedSensors || []}
  columns={routeBasedSensorColumns}
  isLoading={isLoading}
  height={500}
  gridOptions={gridOptions}
  tableId="route-based-sensors-table"
  enableCSVExport={true}
  csvFilename="route-based-sensors"
  showAdvancedCSVOptions={true}
/>

// NEW
<DataTable
  data={routeBasedSensors || []}
  columns={routeBasedSensorColumns}
  tableId="route-based-sensors-table"
  sideBar={sideBar}
  paginationPageSize={50}
  allowDownloadCSV={true}
/>
```

### Success Criteria:

#### Automated Verification:
- [ ] Build passes: `cd frontend && npm run build`
- [ ] Lint passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] RouteBasedSensorList table renders on SensorConversionPage
- [ ] Sidebar and CSV export work correctly

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation.

---

## Phase 4: Migrate PassRateTable Component

### Overview
Migrate the pass rate dashboard table. Note: columns are generated dynamically by parent component.

### Changes Required:

#### 1. Update PassRateTable.tsx
**File**: `frontend/src/hwqa/components/features/dashboard/PassRateOverview/PassRateTable.tsx`

**Change 1: Update import** (line 1)
```typescript
// OLD
import { DataTable } from '../../../common/DataTable/DataTable';

// NEW
import { DataTable } from '../../../../../components/common/DataTable';
```

**Change 2: Update DataTable usage** (lines 13-22)
```typescript
// OLD
<DataTable
  title="Pass Rate Data"
  data={data}
  columns={columns}
  height={height}
  enableCSVExport={true}
  csvFilename="pass-rate-data"
  showAdvancedCSVOptions={true}
/>

// NEW
<DataTable
  data={data}
  columns={columns}
  tableId="pass-rate-data-table"
  paginationPageSize={100}
  allowDownloadCSV={true}
/>
```

#### 2. Update PassRateGraph.tsx (dynamic column generation)
**File**: `frontend/src/hwqa/components/features/dashboard/PassRateOverview/PassRateGraph.tsx`

**Change 1: Update import** (line 4)
```typescript
// OLD
import { ColDef } from 'ag-grid-community';

// NEW
import { ColDef } from 'ag-grid-enterprise';
```

### Success Criteria:

#### Automated Verification:
- [ ] Build passes: `cd frontend && npm run build`
- [ ] Lint passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] PassRateTable renders in dashboard
- [ ] CSV export works

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation.

---

## Phase 5: Migrate ShipmentDetailsList Component

### Overview
Migrate the RCCA report shipment details table. No CSV export needed.

### Changes Required:

#### 1. Update ShipmentDetailsList.tsx
**File**: `frontend/src/hwqa/components/features/dashboard/RCCAReport/ShipmentDetailsList/ShipmentDetailsList.tsx`

**Change 1: Update imports** (lines 4-5)
```typescript
// OLD
import { DataTable } from '../../../../common/DataTable/DataTable';
import { ColDef } from 'ag-grid-community';

// NEW
import { DataTable } from '../../../../../../components/common/DataTable';
import { ColDef } from 'ag-grid-enterprise';
```

**Change 2: Update DataTable usage** (lines 76-81)
```typescript
// OLD
<DataTable
  title="Shipment Details"
  data={metrics.shipment_metrics}
  columns={shipmentColumns}
  height={400}
/>

// NEW
<DataTable
  data={metrics.shipment_metrics}
  columns={shipmentColumns}
  tableId="rcca-shipment-details-table"
  paginationPageSize={100}
/>
```

### Success Criteria:

#### Automated Verification:
- [ ] Build passes: `cd frontend && npm run build`
- [ ] Lint passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] ShipmentDetailsList renders in RCCA report

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation.

---

## Phase 6: Migrate SpreadsheetExport Component

### Overview
Migrate the RCCA spreadsheet export table. Uses custom copy-to-clipboard, not CSV export.

### Changes Required:

#### 1. Update SpreadsheetExport.tsx
**File**: `frontend/src/hwqa/components/features/dashboard/RCCAReport/SpreadsheetExport/SpreadsheetExport.tsx`

**Change 1: Update imports** (lines 3, 7)
```typescript
// OLD
import { ColDef } from 'ag-grid-community';
import { DataTable } from '../../../../common/DataTable/DataTable';

// NEW
import { ColDef } from 'ag-grid-enterprise';
import { DataTable } from '../../../../../../components/common/DataTable';
```

**Change 2: Update DataTable usage** (lines 506-511)
```typescript
// OLD
<DataTable
  title=""
  data={spreadsheetRows}
  columns={rccaColumns}
  height={400}
/>

// NEW
<DataTable
  data={spreadsheetRows}
  columns={rccaColumns}
  tableId="rcca-spreadsheet-export-table"
  paginationPageSize={100}
/>
```

### Success Criteria:

#### Automated Verification:
- [ ] Build passes: `cd frontend && npm run build`
- [ ] Lint passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] SpreadsheetExport table renders in RCCA report
- [ ] Copy-to-clipboard functionality still works

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation.

---

## Phase 7: Migrate LogShipmentForm Component

### Overview
Migrate the Excel import preview table in the log shipment form.

### Changes Required:

#### 1. Update LogShipmentForm.tsx
**File**: `frontend/src/hwqa/components/features/shipments/LogShipmentForm.tsx`

**Change 1: Update imports** (lines 7-8)
```typescript
// OLD
import { DataTable } from '../../common/DataTable/DataTable';
import { ColDef } from 'ag-grid-community';

// NEW
import { DataTable } from '../../../../components/common/DataTable';
import { ColDef } from 'ag-grid-enterprise';
```

**Change 2: Update DataTable usage** (around line 390)
```typescript
// OLD
<DataTable
  title=""
  data={previewData}
  columns={previewColumns}
  height={300}
/>

// NEW
<DataTable
  data={previewData}
  columns={previewColumns}
  tableId="shipment-import-preview-table"
  paginationPageSize={100}
/>
```

### Success Criteria:

#### Automated Verification:
- [ ] Build passes: `cd frontend && npm run build`
- [ ] Lint passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] LogShipmentForm preview table renders when Excel file is uploaded
- [ ] Import functionality still works

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation.

---

## Phase 8: Remove HWQA DataTable Infrastructure

### Overview
Remove all HWQA-specific DataTable files now that all consumers have been migrated.

### Changes Required:

#### 1. Delete HWQA DataTable Component
**File to delete**: `frontend/src/hwqa/components/common/DataTable/DataTable.tsx`

#### 2. Delete HWQA DataTable Styles
**File to delete**: `frontend/src/hwqa/components/common/DataTable/DataTable.module.css`

#### 3. Delete HWQA DataTable Index (if exists)
**File to delete**: `frontend/src/hwqa/components/common/DataTable/index.ts` (if exists)

#### 4. Delete CSVExportButton Component
**Files to delete**:
- `frontend/src/hwqa/components/common/CSVExportButton/CSVExportButton.tsx`
- `frontend/src/hwqa/components/common/CSVExportButton/CSVExportButton.module.css` (if exists)
- `frontend/src/hwqa/components/common/CSVExportButton/index.ts` (if exists)

#### 5. Delete CSV Export Utilities
**File to delete**: `frontend/src/hwqa/utils/csvExport.ts`

#### 6. Update Common Index Exports (if applicable)
**File**: `frontend/src/hwqa/components/common/index.ts` (if exists)

Remove any exports for DataTable or CSVExportButton.

### Success Criteria:

#### Automated Verification:
- [ ] Build passes: `cd frontend && npm run build`
- [ ] Lint passes: `cd frontend && npm run lint`
- [ ] No import errors for deleted files

#### Manual Verification:
- [ ] All 8 DataTable consumers still render correctly
- [ ] No console errors related to missing modules

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation.

---

## Phase 9: Final Cleanup and Verification

### Overview
Remove any remaining ag-grid-community references from HWQA code and verify the migration is complete.

### Changes Required:

#### 1. Search for remaining ag-grid-community imports
Run: `grep -r "ag-grid-community" frontend/src/hwqa/`

Any remaining imports should be changed to `ag-grid-enterprise`.

#### 2. Verify no HWQA-specific AG Grid CSS imports remain
Ensure no files import:
- `ag-grid-community/styles/ag-grid.css`
- `ag-grid-community/styles/ag-theme-alpine.css`

These should be removed since AssetWatch's DataTable handles the enterprise imports.

#### 3. Verify enterprise features work
Test that these enterprise features function on HWQA tables:
- Sidebar panels (columns/filters)
- Column state persistence
- Filter state persistence
- CSV export via action bar

### Success Criteria:

#### Automated Verification:
- [ ] Build passes: `cd frontend && npm run build`
- [ ] Lint passes: `cd frontend && npm run lint`
- [ ] TypeScript passes: `cd frontend && npm run typecheck`
- [ ] No `ag-grid-community` imports in `src/hwqa/`: `grep -r "ag-grid-community" frontend/src/hwqa/` returns empty
- [ ] Tests pass: `cd frontend && npm test -- --watchAll=false`

#### Manual Verification:
- [ ] All 8 tables render with data
- [ ] Sidebar panels appear on tables with sideBar prop
- [ ] Column state persists (reorder columns, refresh, verify order retained)
- [ ] Filter state persists (apply filter, refresh, verify filter retained)
- [ ] CSV export downloads file with correct data
- [ ] Cell highlighting shows on TestList status column (green/red/gray)
- [ ] No visual regressions (tables look consistent with AssetWatch style)

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation that the migration is fully complete.

---

## Testing Strategy

### Unit Tests:
- Verify column definitions compile correctly with enterprise types
- Verify cellClassRules functions return correct boolean values

### Integration Tests:
- Each page loads without errors
- DataTable components receive data from context
- Pagination, filtering, sorting work as expected

### Manual Testing Steps:
1. Navigate to SensorTestsPage, verify TestList renders with colored status cells
2. Navigate to HubTestsPage, verify TestList renders
3. Navigate to SensorShipmentsPage, verify ShipmentList renders
4. Navigate to HubShipmentsPage, verify ShipmentList renders
5. Navigate to SensorConversionPage, verify RouteBasedSensorList renders
6. Navigate to Dashboard, verify PassRateTable renders
7. Navigate to RCCA Report, verify ShipmentDetailsList and SpreadsheetExport render
8. Open Log Shipment modal, upload Excel file, verify preview table renders
9. On any table: open sidebar, toggle column visibility, verify it works
10. On any table: apply filter, refresh page, verify filter persists
11. On any table: reorder columns, refresh page, verify order persists
12. On tables with CSV export: click download, verify file downloads

## Performance Considerations

- Enterprise sidebar adds minimal overhead
- Column state persistence uses localStorage (same as before)
- No significant performance impact expected

## Migration Notes

- LocalStorage keys will change format from `${tableId}-filter-state` to `DataTable.${tableId}.filterState`
- Users may need to clear localStorage if they have existing saved filter states
- Column state is new - users will get fresh column layouts initially

## Rollback Strategy

If issues are discovered:
1. Revert the consumer component changes
2. Restore deleted files from git
3. The HWQA DataTable is self-contained and can be restored independently

## References

- Research document: `thoughts/shared/research/2025-12-03-IWA-14069-ag-grid-datatable-comparison.md`
- AssetWatch DataTable: `frontend/src/components/common/DataTable.tsx:39-497`
- HWQA DataTable (to be removed): `frontend/src/hwqa/components/common/DataTable/DataTable.tsx:1-216`
- Cell styling classes: `frontend/src/styles/css/App.css:68-116`
