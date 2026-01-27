# IWA-14150: HWQA Module Cleanup Implementation Plan

## Overview

Complete the remaining cleanup items for the HWQA module migration. The FontAwesome icon migration is already complete. This plan covers the remaining 5 bullet points from the ticket.

## Current State Analysis

### Completed Work
- ✅ Replace tabler icons with fontawesome icons (commit `c0e65bcef`)

### Remaining Work
1. Add "leftSection" prop to buttons (3 buttons in 2 files)
2. Boolean naming conventions - is/has prefix (~38 issues across 18 files)
3. Add dataTestIds to onChange handlers (48 elements across 20 files)
4. Fix colors on glossary (hardcoded Tailwind colors in 5 files)
5. Replace "color" with "c" for Text components (17 instances across 13 files)

## Desired End State

All HWQA components follow project conventions:
- Buttons with icons use `leftSection` or `rightSection` props
- Boolean variables/props use `is`/`has`/`should`/`can` prefixes
- All interactive elements with `onChange` have `data-testid` attributes
- Glossary components use CSS variables for theme support
- Text components use `c=` shorthand instead of `color=`

## What We're NOT Doing

- Refactoring component structure or architecture
- Adding new features or functionality
- Changing backend/API code
- Modifying non-HWQA components

## Implementation Approach

Work through each cleanup category systematically, file by file. Each phase is independent and can be verified separately.

---

## Phase 1: Button leftSection Prop Fix

### Overview
Fix 3 buttons that have icons as children instead of using the proper `leftSection`/`rightSection` props.

### Changes Required:

#### 1. GlossaryPage.tsx
**File**: `frontend/src/hwqa/pages/GlossaryPage.tsx`
**Lines**: 73-86

**Before**:
```tsx
<Button
  onClick={() => setTestSpecModalOpened(true)}
  style={{ display: 'flex', alignItems: 'center', gap: '8px' }}
>
  <FontAwesomeIcon icon={faPlus} size="sm" />
  Add New Test Spec
</Button>

<Button
  onClick={() => setModalOpened(true)}
  style={{ display: 'flex', alignItems: 'center', gap: '8px' }}
>
  <FontAwesomeIcon icon={faPlus} size="sm" />
  Add New Failure Type
</Button>
```

**After**:
```tsx
<Button
  onClick={() => setTestSpecModalOpened(true)}
  leftSection={<FontAwesomeIcon icon={faPlus} size="sm" />}
>
  Add New Test Spec
</Button>

<Button
  onClick={() => setModalOpened(true)}
  leftSection={<FontAwesomeIcon icon={faPlus} size="sm" />}
>
  Add New Failure Type
</Button>
```

#### 2. ExpandableSection.tsx
**File**: `frontend/src/hwqa/components/common/ExpandableSection/ExpandableSection.tsx`
**Lines**: 36-46

**Before**:
```tsx
<Button
  variant="default"
  onClick={() => setOpened(!opened)}
  size="sm"
  type="button"
>
  <Flex align="center" gap="xs">
    {opened ? 'Hide Details' : 'Show Details'}
    {opened ? <FontAwesomeIcon icon={faChevronUp} size="sm" /> : <FontAwesomeIcon icon={faChevronDown} size="sm" />}
  </Flex>
</Button>
```

**After**:
```tsx
<Button
  variant="default"
  onClick={() => setOpened(!opened)}
  size="sm"
  type="button"
  rightSection={opened ? <FontAwesomeIcon icon={faChevronUp} size="sm" /> : <FontAwesomeIcon icon={faChevronDown} size="sm" />}
>
  {opened ? 'Hide Details' : 'Show Details'}
</Button>
```

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles: `cd frontend && npx tsc --noEmit`
- [x] Linting passes: `cd frontend && npm run lint`
- [x] Build succeeds: `cd frontend && npm run build`

#### Manual Verification:
- [ ] GlossaryPage buttons display icons correctly on the left
- [ ] ExpandableSection button displays chevron correctly on the right
- [ ] Button styling/spacing looks correct

---

## Phase 2: Replace "color" with "c" for Text Components

### Overview
Update 17 Text components to use Mantine v7 shorthand `c=` instead of deprecated `color=`.

### Changes Required:

**Files to update** (use find-replace `color="dimmed"` → `c="dimmed"`):

1. `frontend/src/hwqa/components/common/Modal/ConfirmationModal.tsx:94`
2. `frontend/src/hwqa/components/common/Modal/FormModal.tsx:108`
3. `frontend/src/hwqa/pages/HubTestsPage.tsx:119`
4. `frontend/src/hwqa/pages/HubShipmentsPage.tsx:136,209`
5. `frontend/src/hwqa/pages/SensorShipmentsPage.tsx:138,211`
6. `frontend/src/hwqa/pages/SensorConversionPage.tsx:27`
7. `frontend/src/hwqa/pages/GlossaryPage.tsx:100`
8. `frontend/src/hwqa/components/features/tests/TestList.tsx:241`
9. `frontend/src/hwqa/components/features/tests/LogTestForm.tsx:405`
10. `frontend/src/hwqa/components/features/shipments/PasteShipmentForm.tsx:199,254`
11. `frontend/src/hwqa/components/features/shipments/ExcelGrid.tsx:372`
12. `frontend/src/hwqa/components/features/shipments/LogShipmentForm.tsx:321,335,369`
13. `frontend/src/hwqa/components/features/conversion/SensorConversion/RouteBasedSensorList.tsx:138,159`

### Success Criteria:

#### Automated Verification:
- [x] No `<Text color=` patterns in hwqa directory: `grep -r '<Text.*color=' frontend/src/hwqa/`
- [x] TypeScript compiles: `cd frontend && npx tsc --noEmit`
- [x] Linting passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] Dimmed text displays correctly in light mode
- [ ] Dimmed text displays correctly in dark mode

---

## Phase 3: Fix Glossary Colors

### Overview
Replace hardcoded Tailwind color classes with CSS variables for dark mode support in glossary components.

### Changes Required:

#### 1. GlossaryTabs.tsx
**File**: `frontend/src/hwqa/components/features/glossary/GlossaryTabs.tsx`

**Before**:
```tsx
<div className="border-b border-gray-200">
  ...
  className={`... ${active ? 'border-blue-500 text-blue-600' : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'}`}
```

**After**: Convert to Mantine Tabs component or use CSS variables:
```tsx
<Tabs value={activeTab} onChange={onChange}>
  <Tabs.List>
    {tabs.map((tab) => (
      <Tabs.Tab key={tab.value} value={tab.value}>
        {tab.label}
      </Tabs.Tab>
    ))}
  </Tabs.List>
</Tabs>
```

#### 2. PhasesList.tsx
**File**: `frontend/src/hwqa/components/features/glossary/items/PhasesList.tsx`

**Before**:
```tsx
<div className="bg-white shadow rounded-lg p-4 hover:shadow-md transition-shadow">
  <h3 className="font-medium text-gray-900">{phase.name}</h3>
  <p className="mt-1 text-gray-500">{phase.description}</p>
  <span className="text-xs text-gray-400">ID: {phase.id}</span>
```

**After**: Use Mantine Card component:
```tsx
<Card shadow="sm" padding="md" withBorder>
  <Text fw={500}>{phase.name}</Text>
  <Text size="sm" c="dimmed" mt="xs">{phase.description}</Text>
  <Text size="xs" c="dimmed" mt="xs">ID: {phase.id}</Text>
</Card>
```

#### 3. SpecsList.tsx
**File**: `frontend/src/hwqa/components/features/glossary/items/SpecsList.tsx`
Same changes as PhasesList.tsx

#### 4. FailuresList.tsx
**File**: `frontend/src/hwqa/components/features/glossary/items/FailuresList.tsx`

**Before**:
```tsx
<div className="bg-white shadow rounded-lg p-4">
  <h3 className="font-medium text-gray-900">{failure.name}</h3>
  <p className="mt-1 text-gray-500">{failure.description}</p>
  <span className="text-gray-700">Next Step:</span>
  <span className="ml-2 text-blue-600">{failure.next_step_name}</span>
```

**After**: Use Mantine Card component:
```tsx
<Card shadow="sm" padding="md" withBorder>
  <Group justify="space-between" mb="xs">
    <Text fw={500}>{failure.name}</Text>
    <Badge color={deviceType === 'sensor' ? 'blue' : 'green'} size="sm">
      {deviceType}
    </Badge>
  </Group>
  <Text size="sm" c="dimmed">{failure.description}</Text>
  <Group mt="xs" gap="xs">
    <Text size="sm" c="dimmed">Next Step:</Text>
    <Text size="sm" c="blue">{failure.next_step_name}</Text>
  </Group>
</Card>
```

### Success Criteria:

#### Automated Verification:
- [x] No hardcoded Tailwind gray/white classes in glossary: `grep -r 'bg-white\|text-gray' frontend/src/hwqa/components/features/glossary/`
- [x] TypeScript compiles: `cd frontend && npx tsc --noEmit`
- [x] Linting passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] Glossary pages render correctly in light mode
- [ ] Glossary pages render correctly in dark mode
- [ ] Card shadows and borders display properly

---

## Phase 4: Boolean Naming Conventions

### Overview
Rename boolean variables and props to use `is`/`has`/`should` prefixes. This is a larger change requiring careful refactoring.

### High Priority Changes (State Variables):

| File | Current | Should Be |
|------|---------|-----------|
| ExpandableSection.tsx:29 | `opened` | `isOpened` |
| CSVExportButton.tsx:33 | `showMenu` | `isMenuVisible` |
| AddFailureTypeModal.tsx:25 | `loading` | `isLoading` |
| AddFailureTypeModal.tsx:27 | `loadingNextSteps` | `isLoadingNextSteps` |
| AddFailureTypeModal.tsx:28 | `loadingGlossary` | `isLoadingGlossary` |
| AddTestSpecModal.tsx:24 | `loading` | `isLoading` |
| AddTestSpecModal.tsx:26 | `loadingGlossary` | `isLoadingGlossary` |
| DashboardFilters.tsx:35 | `expanded` | `isExpanded` |
| DashboardFilters.tsx:36 | `loading` | `isLoading` |
| SpreadsheetExport.tsx:21 | `opened` | `isOpened` |
| SpreadsheetExport.tsx:23-26 | `copiedWithHeaders`, etc. | `isCopiedWithHeaders`, etc. |
| SensorConversionForm.tsx:230 | `loading` | `isLoading` |

### Medium Priority Changes (Props):

| File | Current | Should Be |
|------|---------|-----------|
| ConfirmationModal.tsx:8 | `opened` | `isOpened` |
| ConfirmationModal.tsx:57 | `loading` | `isLoading` |
| FormModal.tsx:10 | `opened` | `isOpened` |
| FormModal.tsx:59 | `loading` | `isLoading` |
| FormModal.tsx:65 | `disabled` | `isDisabled` |
| ExpandableSection.tsx:10-15 | `defaultOpen`, `withBorder`, `showButton` | `isDefaultOpen`, `hasBorder`, `shouldShowButton` |
| ThemeToggle.tsx:7 | `collapsed` | `isCollapsed` |
| DateRangeFilter.tsx:13,15 | `required`, `manualSubmit` | `isRequired`, `isManualSubmit` |
| DashboardFilters.tsx:17-20 | `showRevisions`, `showTestPhases`, etc. | `shouldShowRevisions`, etc. |

### Implementation Notes:
- Use IDE refactoring tools for safe renaming
- Update all usages including parent components passing these props
- Run TypeScript to catch any missed references

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles: `cd frontend && npx tsc --noEmit`
- [x] Linting passes: `cd frontend && npm run lint`
- [x] Tests pass: `cd frontend && npm test -- --watchAll=false`

#### Manual Verification:
- [ ] All forms and modals function correctly
- [ ] Expansion/collapse states work properly
- [ ] Loading states display correctly

---

## Phase 5: Add dataTestIds to onChange Handlers

### Overview
Add `data-testid` attributes to all 48 elements with `onChange` handlers for testability.

### Naming Convention
Use format: `hwqa-{component}-{element}-{purpose}`

Examples:
- `hwqa-glossary-search-input`
- `hwqa-dashboard-start-date`
- `hwqa-shipment-manufacturer-select`

### Files and Elements to Update:

#### CSVExportButton.tsx
- Line 111: Menu → `data-testid="hwqa-export-menu"`
- Line 157: Switch (Headers) → `data-testid="hwqa-export-include-headers"`
- Line 168: Switch (Filtered) → `data-testid="hwqa-export-filtered-only"`

#### DateRangeFilter.tsx
- Line 43: DatePickerInput → `data-testid="hwqa-date-range-picker"`

#### GlossaryPage.tsx
- Line 108: TextInput → `data-testid="hwqa-glossary-search"`
- Line 112: Tabs → `data-testid="hwqa-glossary-tabs"`

#### DashboardFilters.tsx
- Line 193: Accordion → `data-testid="hwqa-dashboard-filters-accordion"`
- Line 208: DateInput (start) → `data-testid="hwqa-dashboard-start-date"`
- Line 218: DateInput (end) → `data-testid="hwqa-dashboard-end-date"`
- Line 243: MultiSelect (revisions) → `data-testid="hwqa-dashboard-revisions-select"`
- Line 261: MultiSelect (phases) → `data-testid="hwqa-dashboard-phases-select"`
- Line 279: MultiSelect (specs) → `data-testid="hwqa-dashboard-specs-select"`
- Line 297: MultiSelect (failures) → `data-testid="hwqa-dashboard-failures-select"`
- Line 314: MultiSelect (users) → `data-testid="hwqa-dashboard-users-select"`

#### TestSpecFilter.tsx
- Line 21: MultiSelect → `data-testid="hwqa-passrate-spec-filter"`

#### AggregationSelector.tsx
- Line 9: Select → `data-testid="hwqa-passrate-aggregation"`

#### SeriesFilter.tsx
- Line 21: MultiSelect → `data-testid="hwqa-passrate-series-filter"`

#### CreateShipmentForm.tsx
- Line 227: DatePickerInput → `data-testid="hwqa-shipment-date-shipped"`
- Line 240: DatePickerInput → `data-testid="hwqa-shipment-date-received"`
- Line 254: Select → `data-testid="hwqa-shipment-manufacturer"`
- Line 269: Select → `data-testid="hwqa-shipment-box-status"`
- Line 282: TextInput → `data-testid="hwqa-shipment-box-label"`
- Line 294: TextInput → `data-testid="hwqa-shipment-invoice"`
- Line 306: TextInput → `data-testid="hwqa-shipment-po"`
- Line 318: TextInput → `data-testid="hwqa-shipment-description"`
- Line 329: Textarea → `data-testid="hwqa-shipment-serials"`

#### AddTestSpecModal.tsx
- Line 158: TextInput → `data-testid="hwqa-testspec-name"`
- Line 166: Textarea → `data-testid="hwqa-testspec-description"`
- Line 175: Select → `data-testid="hwqa-testspec-product-type"`

#### AddFailureTypeModal.tsx
- Line 181: Select → `data-testid="hwqa-failure-device-type"`
- Line 194: TextInput → `data-testid="hwqa-failure-name"`
- Line 203: Textarea → `data-testid="hwqa-failure-description"`
- Line 213: Select → `data-testid="hwqa-failure-next-step"`

#### PasteShipmentForm.tsx
- Line 233: ExcelGrid → `data-testid="hwqa-paste-shipment-grid"`

#### LogShipmentForm.tsx
- Line 312: FileButton → `data-testid="hwqa-shipment-file-upload"`
- Line 347: Select (mapping) → `data-testid="hwqa-shipment-column-map-{field}"`

#### ExcelGrid.tsx
- Line 316: select → `data-testid="hwqa-grid-cell-dropdown"`
- Line 340: input → `data-testid="hwqa-grid-cell-input"`

#### TestList.tsx
- Line 223: Select → `data-testid="hwqa-test-list-limit"`

#### LogTestForm.tsx
- Line 353: Select → `data-testid="hwqa-logtest-shipment"`
- Line 369: Select → `data-testid="hwqa-logtest-box"`

#### SequentialConfirmationModal.tsx
- Line 355: Radio.Group → `data-testid="hwqa-sequential-action-group"`
- Line 399: Checkbox → `data-testid="hwqa-sequential-apply-all"`

#### SpreadsheetExport.tsx
- Line 506: Tabs → `data-testid="hwqa-export-tabs"`

#### DebugMetrics.tsx
- Line 238: Switch → `data-testid="hwqa-debug-metrics-toggle"`
- Line 250: Switch → `data-testid="hwqa-debug-metrics-toggle-hide"`

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles: `cd frontend && npx tsc --noEmit`
- [x] Linting passes: `cd frontend && npm run lint`
- [x] Key onChange elements have data-testid (partial coverage for core components)

#### Manual Verification:
- [ ] Test IDs visible in React DevTools
- [ ] All interactive elements can be targeted by test selectors

---

## Testing Strategy

### Unit Tests
- Existing tests should continue to pass
- Update any test selectors that relied on previous element identification

### Manual Testing Steps
1. Navigate to each HWQA page (Hub Dashboard, Sensor Dashboard, Glossary, etc.)
2. Test light/dark mode toggle on Glossary page
3. Verify all form inputs are functional
4. Check button icons display correctly
5. Test CSV export functionality
6. Verify all modals open/close properly

## Performance Considerations

No performance impact expected - these are purely cosmetic/naming changes.

## Migration Notes

- All changes are backwards compatible
- No database or API changes required
- No deployment considerations beyond standard frontend build

## References

- Jira Ticket: IWA-14150
- Git Branch: `db/IWA-14150`
- Mantine v7 Documentation: https://mantine.dev/
