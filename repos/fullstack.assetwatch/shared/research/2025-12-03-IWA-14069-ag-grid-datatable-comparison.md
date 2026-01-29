---
date: 2025-12-03T12:00:00-06:00
researcher: Claude
git_commit: b4f14d3fdf8a0bb58b0463d526724638302b3fd5
branch: db/IWA-14069
repository: fullstack.assetwatch-hwqa-migration
topic: "AG Grid and DataTable Usage Comparison: AssetWatch vs HWQA"
tags: [research, ag-grid, datatable, hwqa, assetwatch, refactoring]
status: complete
last_updated: 2025-12-03
last_updated_by: Claude
last_updated_note: "Added decisions and implementation patterns for status cell highlighting, sidebar configuration"
---

# Research: AG Grid and DataTable Usage Comparison - AssetWatch vs HWQA

**Date**: 2025-12-03T12:00:00-06:00
**Researcher**: Claude
**Git Commit**: b4f14d3fdf8a0bb58b0463d526724638302b3fd5
**Branch**: db/IWA-14069
**Repository**: fullstack.assetwatch-hwqa-migration

## Research Question

How is ag-grid and datatable used in the assetwatch repo (non-HWQA) vs how it is used in HWQA specifically? This research will inform a refactoring plan to align HWQA with AssetWatch patterns, enabling HWQA to use the enterprise version of ag-grid.

## Summary

Both AssetWatch and HWQA use AG Grid v32.1.0 wrapped in custom `DataTable` components, but with significant architectural differences:

| Aspect | AssetWatch | HWQA |
|--------|------------|------|
| **Theme** | `ag-theme-balham` | `ag-theme-alpine` |
| **Enterprise Features** | Extensively used (sidebar, master-detail, range selection) | Minimally used (primarily community features) |
| **State Persistence** | Column state + filter state in localStorage | Filter state only in localStorage |
| **Column Management** | Full column state restoration (order, width, visibility, sort) | No column state persistence |
| **Action Bar** | Custom `DataTableActionBar` component with toggles | Inline controls in DataTable header |
| **CSV Export** | Built-in AG Grid export (`exportDataAsCsv`) | Custom utility functions (`csvExport.ts`) |
| **Side Panel** | Enterprise columns/filters panels | Not used |
| **Component Location** | `src/components/common/DataTable.tsx` | `src/hwqa/components/common/DataTable/DataTable.tsx` |

## Detailed Findings

### 1. Package Configuration

Both use the same AG Grid packages from `frontend/package.json:33-35`:
```json
"ag-grid-community": "^32.1.0",
"ag-grid-enterprise": "^32.1.0",
"ag-grid-react": "^32.1.0"
```

**License**: Enterprise license configured in:
- `frontend/src/index.tsx:15-17` - Main app initialization
- `frontend/src/testsGlobal/testsSetup.ts:103-108` - Test setup

The license is for "AssetWatch Single Application Developer License" valid until August 14, 2025.

---

### 2. DataTable Component Architecture

#### AssetWatch DataTable (`src/components/common/DataTable.tsx`)

**Component Structure:**
- Lines 39-497 define a `forwardRef` component
- Uses `useImperativeHandle` to expose grid API (line 162)
- Extensive prop interface (40+ props, lines 41-152)

**Key Props:**
```typescript
tableId: string              // Required - for localStorage keys
data: any[]                  // Row data
columns: ColDef[]            // Column definitions
columnDefs: object           // Default column config
sideBar: SideBarDef          // Enterprise sidebar config
masterDetail: boolean        // Enterprise master-detail
enableRangeSelection: boolean // Enterprise cell selection
paginationPageSize: number   // Default 100
domLayout: DomLayoutType     // Default "autoHeight"
```

**Enterprise Features Used:**
- Side panel with columns/filters tools (lines 409-432)
- Master-detail row expansion (lines 486-489)
- Range selection for copying (line 447)
- Legacy column menu (line 452)

**State Management:**
- Column state saved to `DataTable.{tableId}.columnState` (lines 208-220)
- Filter state saved to `DataTable.{tableId}.filterState` (lines 222-226)
- Validates column changes against defaults (lines 164-206)
- Debounced column move events (lines 347-359)

#### HWQA DataTable (`src/hwqa/components/common/DataTable/DataTable.tsx`)

**Component Structure:**
- Lines 12-216 define a standard functional component
- No ref forwarding to parent
- Simpler prop interface (14 props, lines 12-33)

**Key Props:**
```typescript
tableId?: string             // Optional - defaults to 'data-table'
data: any[]                  // Row data
columns: ColDef[]            // Column definitions
isLoading?: boolean          // Loading indicator
height?: number              // Default 600px
gridOptions?: GridOptions    // Additional config
enableCSVExport?: boolean    // Custom CSV export
```

**Features:**
- Quick filter text search (line 50, 144-150)
- Toggle floating filters (line 51, 151-159)
- Filter persistence only (lines 88-96)
- Custom CSV export via utility (lines 172-184)
- No sidebar or enterprise features actively used

**State Management:**
- Filter state saved to `${tableId}-filter-state` (line 106)
- No column state persistence
- Local `quickFilterText` state (line 50)
- Local `showFilters` toggle (line 51)

---

### 3. Styling and Theming

#### AssetWatch
- **Theme**: `ag-theme-balham` (line 406)
- **Stylesheets**:
  - `ag-grid-enterprise/styles/ag-grid.css` (line 2)
  - `ag-grid-enterprise/styles/ag-theme-balham.css` (line 3)
- **Font Override**: Inter font family (`src/styles/css/App.css:510-512`)
- **Custom Classes**: Defined in `App.css:68-116`:
  - `.grid-cell-ok` - Green background
  - `.grid-cell-warning` - Yellow background
  - `.grid-cell-critical` - Red background (uses `--mantine-color-critical40`)
  - `.grid-cell-temp-critical` - Temperature alerts
  - `.grid-cell-yellow-orange` - Warning state
  - `.grid-cell-gray` - Neutral state

#### HWQA
- **Theme**: `ag-theme-alpine` (line 198)
- **Stylesheets**:
  - `ag-grid-community/styles/ag-grid.css` (line 6)
  - `ag-grid-community/styles/ag-theme-alpine.css` (line 7)
- **CSS Module**: `DataTable.module.css` with semantic variables (lines 58-76):
  - `--ag-background-color: var(--bg-surface)`
  - `--ag-header-background-color: var(--bg-surface-alt)`
  - `--ag-foreground-color: var(--text-primary)`
  - Custom scrollbar styling (lines 39-55)

---

### 4. Column Definition Patterns

#### AssetWatch Patterns

**Grouped Columns** (`src/components/CustomerDetailPage/ColumnDefs.tsx:117-144`):
```typescript
{
  headerName: "Maintenance Recommended",
  marryChildren: true,
  children: [
    { headerName: "Current", field: "mrc", minWidth: 70, cellClassRules: {...} },
    { headerName: "Not Confirmed", field: "mrcu", minWidth: 85, cellClassRules: {...} }
  ]
}
```

**Custom Cell Renderers** (`src/components/UsersPage/TeamAccountsTable.tsx:45-78`):
- Component-based renderers using React.memo
- Registered via `components` prop on AgGridReact (lines 487-492)
- Access `context` for parent callbacks

**Cell Class Rules** (`src/components/SensorCheckPage/SensorCheckResults.tsx:266-274`):
```typescript
cellClassRules: {
  "grid-cell-critical": ({ data, value }) =>
    data.checkFailures.includes("HARDWARE_ISSUES") && value !== "0"
}
```

**Cell Styles** (`src/components/HubCheckPage/HubCheckColumnDefs.tsx:62-70`):
```typescript
cellStyle: ({ data }) => ({
  backgroundColor: data.pass ? 'var(--mantine-color-primary80)' : 'var(--mantine-color-critical80)'
})
```

#### HWQA Patterns

**Basic Text Filter** (`src/hwqa/components/features/tests/TestList.tsx:32-39`):
```typescript
{
  field: 'box_label',
  headerName: 'Box Label',
  filter: 'agTextColumnFilter',
  filterParams: {
    filterOptions: ['contains', 'startsWith', 'endsWith', 'equals'],
    defaultOption: 'contains'
  }
}
```

**Date Filter with Comparator** (`src/hwqa/components/features/shipments/ShipmentList.tsx:13-27`):
```typescript
{
  field: 'date_shipped',
  filter: 'agDateColumnFilter',
  filterParams: {
    comparator: (filterDate, cellValue) => {
      // Custom date comparison logic
    }
  }
}
```

**Status Cell Renderer with Emoji** (`src/hwqa/components/features/tests/TestList.tsx:74-79`):
```typescript
cellRenderer: (params) => {
  if (params.value === null) return '⚪ Not Tested';
  return params.value ? '✅ Pass' : '❌ Fail';
}
```

**Set Filter** (`src/hwqa/components/features/tests/TestList.tsx:80-89`):
```typescript
filter: 'agSetColumnFilter',
filterParams: {
  values: [true, false, null],
  cellRenderer: (params) => {
    if (params.value === null) return 'Not Tested';
    return params.value ? 'Pass' : 'Fail';
  }
}
```

---

### 5. Enterprise Features Comparison

| Feature | AssetWatch | HWQA |
|---------|------------|------|
| **Side Panel** | Full implementation with columns/filters panels | Not used |
| **Master-Detail** | Used in `HardwareSummaryTable.tsx:393-395` | Not used |
| **Range Selection** | `enableRangeSelection` prop (line 447) | Not used |
| **Column State Persistence** | Full save/restore (lines 277-335) | Not implemented |
| **Row Grouping** | Available but not commonly used | Not used |
| **Excel Export** | Custom CSV via `exportDataAsCsv` | Custom `csvExport.ts` utility |
| **Context Menu** | Toggleable via action bar | Not configurable |

---

### 6. CSV Export Implementation

#### AssetWatch
- Uses AG Grid's built-in `api.exportDataAsCsv()` method
- Triggered from `DataTableActionBar` download button
- Location: `DataTable.tsx:376-378`

#### HWQA
- Custom implementation in `src/hwqa/utils/csvExport.ts:1-316`
- Functions:
  - `convertToCSV()` - Converts data array to CSV string
  - `exportGridToCSV()` - Exports ag-grid data with filtering
  - `downloadCSV()` - Triggers browser download with BOM for Excel
  - `getExportStats()` - Returns export statistics
- Features:
  - Custom date formatting (lines 60-143)
  - Filtered data export option
  - Advanced options menu via `CSVExportButton` component

---

### 7. Action Bar / Controls

#### AssetWatch (`DataTableActionBar.tsx`)
**Props:**
- `allowDownloadCSV` - Show CSV download button
- `showDisableMenuToggle` - Show context menu toggle
- `showScrollIndicators` - Show horizontal scroll indicators
- `customActionItems` - Custom toolbar items

**Features:**
- Download as CSV button
- Toggle context menu button
- Scroll indicator dots
- Custom action items slot

#### HWQA (`DataTable.tsx:140-194`)
**Inline Controls:**
- Quick filter text input with search icon
- Toggle floating filters button
- Clear filters button (shows when filters active)
- Row count display ("X of Y records")
- CSV export button (optional)

---

### 8. Grid Options Comparison

#### AssetWatch Default Grid Options
```typescript
{
  pagination: true,
  paginationPageSize: 100,  // Default
  domLayout: "autoHeight",
  columnMenu: "legacy",
  animateRows: false,       // Implied
  rowSelection: "single" | "multiple",
  enableCellTextSelection: true,  // Optional
  cellSelection: true,      // Enterprise range selection
}
```

#### HWQA Default Grid Options
```typescript
{
  animateRows: true,
  pagination: true,
  paginationPageSize: 100,
  paginationPageSizeSelector: [20, 50, 100, 200, 500],
}
```

**Default Column Definitions:**

| Property | AssetWatch | HWQA |
|----------|------------|------|
| `sortable` | Per column | `true` (default) |
| `resizable` | Per column | `true` (default) |
| `filter` | Per column | `true` (default) |
| `floatingFilter` | Via sidebar | Toggleable |
| `flex` | Disabled when stored state | `1` (default) |
| `minWidth` | Not default | `100` (default) |
| `valueFormatter` | Per column | Global null handler |

---

### 9. State Persistence Comparison

#### AssetWatch
**Column State** (`DataTable.{tableId}.columnState`):
- Column order
- Column width (flex set to null to preserve)
- Column visibility (hide property)
- Sort state (sort property)
- Validates changes against defaults before saving

**Filter State** (`DataTable.{tableId}.filterState`):
- Full filter model saved
- Restored on grid ready via `setFilterModel()`

**Restoration Flow:**
1. `onGridReady` callback fires
2. `queueMicrotask()` defers state application
3. `applyColumnState()` with `applyOrder: true`
4. `setFilterModel()` for filters

#### HWQA
**Filter State Only** (`${tableId}-filter-state`):
- Filter model saved on filter change
- Restored on grid ready
- No column state persistence

---

### 10. Data Flow Patterns

#### AssetWatch
1. Parent fetches data via API/React Query
2. Data stored in component state or context
3. Data passed to DataTable via `data` prop
4. Grid renders with configured columns
5. User interactions trigger callbacks
6. Grid state changes auto-saved to localStorage

**Example** (`src/pages/Customers.tsx:56-84`):
```typescript
const response = await API.post("/admin/customers/list", {});
setCustomers((prevState) => ({ ...prevState, customers: response }));
```

#### HWQA
1. Page component calls context fetch function
2. Service layer fetches from API
3. Context updates state (e.g., `sensorResults`)
4. Component receives data via context
5. Data passed to list component, then to DataTable
6. Filter state persisted to localStorage

**Example** (`AppStateContext.tsx:154-163`):
```typescript
const fetchSensorTestResults = async () => {
  const results = await sensorTestService.getTests();
  setSensorResults(results);
};
```

---

## Code References

### AssetWatch DataTable
- `frontend/src/components/common/DataTable.tsx:39-497` - Main component
- `frontend/src/components/common/DataTableActionBar.tsx` - Action bar
- `frontend/src/components/common/index.ts:10` - Export
- `frontend/src/styles/css/App.css:68-116` - Cell styling classes
- `frontend/src/styles/css/App.css:510-512` - Font override

### HWQA DataTable
- `frontend/src/hwqa/components/common/DataTable/DataTable.tsx:1-216` - Main component
- `frontend/src/hwqa/components/common/DataTable/DataTable.module.css` - Styles
- `frontend/src/hwqa/components/common/CSVExportButton/CSVExportButton.tsx` - Export button
- `frontend/src/hwqa/utils/csvExport.ts` - Export utilities

### Column Definitions
- `frontend/src/components/CustomerDetailPage/ColumnDefs.tsx` - AssetWatch columns
- `frontend/src/hwqa/components/features/shipments/ShipmentList.tsx:6-170` - HWQA columns
- `frontend/src/hwqa/components/features/tests/TestList.tsx:9-161` - HWQA test columns

---

## Key Differences for Refactoring

### Theme Migration
- Change from `ag-theme-alpine` to `ag-theme-balham`
- Update stylesheet imports from community to enterprise
- Adopt AssetWatch cell class naming (`.grid-cell-critical`, etc.)

### Component API Alignment
- Add `forwardRef` pattern to expose grid API
- Implement column state persistence
- Add `DataTableActionBar` component or integrate its features
- Remove custom CSV export in favor of AG Grid's built-in method

### Feature Enablement
- Implement sidebar panels (columns/filters)
- Enable range selection where appropriate
- Add master-detail capability for expandable rows
- Use `tableId` as required prop (not optional)

### Styling Standardization
- Move from CSS modules to global CSS classes
- Adopt Mantine color variables for cell styling
- Use consistent cell class rules pattern

### State Management
- Implement full column state persistence
- Add column state validation against defaults
- Use consistent localStorage key patterns

---

## Decisions Made

The following decisions have been made for the HWQA refactoring:

1. **Theme**: HWQA will adopt `ag-theme-balham` to match AssetWatch
2. **CSV Export**: Migrate to AG Grid's built-in `exportDataAsCsv()` method
3. **Status Indicators**: Replace emoji (✅❌⚪) with cell highlighting using `cellClassRules`
4. **Filtering**: Use sidebar filters (enterprise feature) instead of floating filters
5. **Full Alignment**: Adopt AssetWatch implementation patterns in every way possible

---

## Status Cell Highlighting Pattern (Replacing Emoji)

HWQA currently uses emoji for status indicators. This will be replaced with cell highlighting using the AssetWatch pattern.

### CSS Classes Available (`src/styles/css/App.css:68-116`)

```css
/* Green - Success/Pass/OK states */
.grid-cell-ok {
  background-color: #23b598;
  color: #fff;
}

/* Yellow - Warning states */
.grid-cell-warning {
  background-color: #ebc604;
  color: #fff;
}

/* Red - Critical/Fail states */
.grid-cell-critical {
  background-color: var(--mantine-color-critical40);
  color: #fff;
}

/* Red variant - with hover state */
.grid-cell-temp-critical {
  background-color: var(--mantine-color-critical40);
  color: #fff;
}

/* Light yellow-orange - mild warning */
.grid-cell-yellow-orange {
  background-color: #fff0c3;
  color: #000;
}

/* Gray - neutral/inactive */
.grid-cell-gray {
  background-color: #8a929a;
  color: #fff;
}
```

### cellClassRules Pattern Examples

**Simple Expression (using `x` as value):**
```typescript
// src/components/CustomerDetailPage/Sensors/ColumnDefs.tsx:433
cellClassRules: { "grid-cell-critical": "x < 3.2" }
```

**Function with value:**
```typescript
// src/components/CustomerDetailPage/Sensors/ColumnDefs.tsx:291-293
cellClassRules: {
  "grid-cell-critical": ({ value }: { value: number }) => value < 50,
  "grid-cell-warning": ({ value }: { value: number }) => value < 75,
}
```

**Function with data object:**
```typescript
// src/components/CustomerDetailPage/Sensors/ColumnDefs.tsx:205-208
cellClassRules: {
  "grid-cell-critical": ({ data }: { data: Sensor }) =>
    data.rstid !== SensorStatus.OK && data.rstid !== SensorStatus.PROVISIONED,
}
```

**Multiple conditions with different classes:**
```typescript
// src/components/CustomerDetailPage/Sensors/ColumnDefs.tsx:216-228
cellClassRules: {
  "grid-cell-temp-critical": ({ value }: { value: Date }) => {
    const timeElapsed = calculateHoursElapsed(value);
    return timeElapsed > 56;
  },
  "grid-cell-warning": ({ value }: { value: Date }) => {
    const timeElapsed = calculateHoursElapsed(value);
    return timeElapsed > 24 && timeElapsed <= 56;
  },
}
```

### HWQA Status Column Migration Example

**Current HWQA Implementation (to be replaced):**
```typescript
// src/hwqa/components/features/tests/TestList.tsx:74-79
{
  field: 'pass_flag',
  headerName: 'Status',
  cellRenderer: (params) => {
    if (params.value === null) return '⚪ Not Tested';
    return params.value ? '✅ Pass' : '❌ Fail';
  }
}
```

**New Implementation (AssetWatch pattern):**
```typescript
{
  field: 'pass_flag',
  headerName: 'Status',
  valueFormatter: ({ value }) => {
    if (value === null) return 'Not Tested';
    return value ? 'Pass' : 'Fail';
  },
  cellClassRules: {
    "grid-cell-ok": ({ value }) => value === true,
    "grid-cell-critical": ({ value }) => value === false,
    "grid-cell-gray": ({ value }) => value === null,
  }
}
```

---

## Sidebar Configuration Pattern

HWQA will adopt the AssetWatch sidebar pattern for filtering instead of floating filters.

### Standard Sidebar Configuration
```typescript
// src/components/SensorCheckPage/SensorCheckResults.tsx:72-95
const sideBar: SideBarDef = {
  toolPanels: [
    {
      id: "columns",
      labelDefault: "Columns",
      labelKey: "columns",
      iconKey: "columns",
      toolPanel: "agColumnsToolPanel",
    },
    {
      id: "filters",
      labelDefault: "Filters",
      labelKey: "filters",
      iconKey: "filter",
      toolPanel: "agFiltersToolPanel",
    },
  ],
};
```

### Usage in DataTable
```typescript
<DataTable
  tableId="sensor-test-results"
  data={results}
  columns={columns}
  sideBar={sideBar}
  // ... other props
/>
```

---

## Files to Remove After Migration

The following HWQA-specific files can be removed after migration:

1. `src/hwqa/components/common/DataTable/DataTable.tsx` - Replace with AssetWatch DataTable
2. `src/hwqa/components/common/DataTable/DataTable.module.css` - Use global App.css classes
3. `src/hwqa/components/common/CSVExportButton/CSVExportButton.tsx` - Use built-in AG Grid export
4. `src/hwqa/utils/csvExport.ts` - No longer needed

---

## Open Questions (Resolved)

~~1. **Theme Preference**: Should HWQA migrate to `ag-theme-balham` or should AssetWatch also support `ag-theme-alpine`?~~
**Decision**: HWQA will adopt `ag-theme-balham`

~~2. **CSV Export**: Should HWQA's custom CSV export utilities be preserved for their advanced features, or fully migrate to AG Grid's built-in export?~~
**Decision**: Migrate to AG Grid's built-in export

~~3. **Emoji Usage**: HWQA uses emoji in status cells (✅❌⚪). Should this pattern be preserved or replaced with icon components/CSS styling?~~
**Decision**: Replace with cell highlighting using `cellClassRules` (like CustomerDetail>Sensors)

~~4. **Floating Filters**: HWQA has a toggle for floating filters. AssetWatch uses sidebar filters. Which pattern should be standardized?~~
**Decision**: Use sidebar filters

~~5. **Page Size Options**: HWQA uses `[20, 50, 100, 200, 500]`. AssetWatch uses configurable `paginationPageSize` without selector. Should page size selector be added to AssetWatch pattern?~~
**Decision**: Follow AssetWatch pattern (can be addressed in a future enhancement if needed)
