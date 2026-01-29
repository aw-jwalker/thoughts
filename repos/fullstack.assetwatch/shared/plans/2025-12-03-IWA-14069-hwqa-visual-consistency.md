# HWQA Visual Consistency Implementation Plan

## Overview

Migrate HWQA components from custom CSS Modules and wrapper components to use AssetWatch's Mantine-based theming system for visual consistency. This involves replacing the custom Button component and migrating form styling to Mantine props.

## Current State Analysis

### HWQA Current Approach
- Custom `Button` component with CSS Modules (18 files depend on it)
- Custom `FormModal` wrapper (2 usages)
- Custom `ConfirmationModal` wrapper (0 usages - unused)
- 19 CSS Module files (~1,450 lines total)

### AssetWatch Modern Approach
- Mantine Button with theme defaults (`color="primary40"`, `radius="xl"`)
- Direct Mantine Modal usage with inline props
- All styling via Mantine component props (no CSS Modules)

### Key Discoveries:
- Both codebases use Mantine UI v8.2.4
- Color systems are already aligned (same Figma design library)
- HWQA inherits `assetWatchTheme` through MantineProvider hierarchy
- Theme defaults: Button gets `color="primary40"` and `radius="xl"` automatically

## Desired End State

After this plan is complete:
1. HWQA uses Mantine Button directly (no custom wrapper)
2. High/medium priority CSS Modules migrated to Mantine props
3. HWQA visually matches AssetWatch styling patterns
4. Reduced code duplication and maintenance burden

### Verification:
- All HWQA pages render correctly with consistent styling
- Buttons have rounded appearance (`radius="xl"`)
- Colors match AssetWatch semantic palette
- No TypeScript/ESLint errors
- All existing functionality preserved

## What We're NOT Doing

- Migrating FormModal/ConfirmationModal wrappers (separate plan)
- Migrating AG-Grid theming (DataTable.module.css) - domain-specific, works well
- Migrating ExcelGrid.module.css - custom grid implementation
- Migrating navigation CSS (AppNavbar, NavbarLinksGroup) - already uses semantic variables
- Changing HWQA-specific business logic
- Adding new features

## Implementation Approach

Migrate in phases, validating each before proceeding:
1. **Phase 1**: Button migration (highest impact, enables other phases)
2. **Phase 2**: Form CSS migration to Mantine props
3. **Phase 3**: Remaining CSS cleanup

---

## Phase 1: Button Migration

### Overview
Replace the custom HWQA Button component with Mantine's themed Button. This affects 18 files and is the foundation for visual consistency.

### Variant Mapping (Based on AssetWatch Patterns)

| HWQA Custom | Mantine Equivalent | Example Usage |
|-------------|-------------------|---------------|
| `variant="primary"` | (no variant - uses theme default) | Submit, Save, Confirm buttons |
| `variant="secondary"` | `variant="default"` | Cancel, secondary actions |
| `variant="danger"` | `color="critical60"` | Delete, destructive actions |

### Changes Required:

#### 1. Update Button Imports in All 18 Files

Each file needs import change and prop updates.

**Files to update:**
1. `frontend/src/hwqa/components/common/ExpandableSection/ExpandableSection.tsx`
2. `frontend/src/hwqa/components/common/Modal/ConfirmationModal.tsx`
3. `frontend/src/hwqa/components/common/Modal/FormModal.tsx`
4. `frontend/src/hwqa/components/features/dashboard/DashboardFilters/DashboardFilters.tsx`
5. `frontend/src/hwqa/components/features/dashboard/PassRateOverview/filters/TestSpecFilter.tsx`
6. `frontend/src/hwqa/components/features/shipments/CreateShipmentForm.tsx`
7. `frontend/src/hwqa/components/features/shipments/LogShipmentForm.tsx`
8. `frontend/src/hwqa/components/features/shipments/PasteShipmentForm.tsx`
9. `frontend/src/hwqa/components/features/tests/LogTestForm.tsx`
10. `frontend/src/hwqa/components/features/tests/TestList.tsx`
11. `frontend/src/hwqa/components/features/tests/sequential-confirmation/SequentialConfirmationModal.tsx`
12. `frontend/src/hwqa/components/features/conversion/SensorConversion/SensorConversionForm.tsx`
13. `frontend/src/hwqa/components/features/conversion/SensorConversion/RouteBasedSensorList.tsx`
14. `frontend/src/hwqa/components/features/dashboard/RCCAReport/SpreadsheetExport/SpreadsheetExport.tsx`
15. `frontend/src/hwqa/pages/HubShipmentsPage.tsx`
16. `frontend/src/hwqa/pages/SensorShipmentsPage.tsx`
17. `frontend/src/hwqa/pages/GlossaryPage.tsx`
18. `frontend/src/hwqa/components/common/CSVExportButton/CSVExportButton.tsx`

**Import Change Pattern:**
```tsx
// Before
import { Button } from '../components/common/Button/Button';
// or
import { Button } from '../../common/Button/Button';

// After
import { Button } from '@mantine/core';
```

**Prop Change Patterns:**

```tsx
// Primary button (submit/confirm actions)
// Before
<Button variant="primary" onClick={handleSubmit} loading={isLoading}>
  Submit
</Button>

// After (inherits theme defaults: color="primary40", radius="xl")
<Button onClick={handleSubmit} loading={isLoading}>
  Submit
</Button>
```

```tsx
// Secondary button (cancel/secondary actions)
// Before
<Button variant="secondary" onClick={handleCancel}>
  Cancel
</Button>

// After
<Button variant="default" onClick={handleCancel}>
  Cancel
</Button>
```

```tsx
// Danger button (destructive actions)
// Before
<Button variant="danger" onClick={handleDelete}>
  Delete
</Button>

// After
<Button color="critical60" onClick={handleDelete}>
  Delete
</Button>
```

**Size Mapping (direct equivalents):**
- `size="sm"` → `size="sm"`
- `size="md"` → `size="md"` (or omit - it's the default)
- `size="lg"` → `size="lg"`

**Other Props (direct equivalents):**
- `fullWidth` → `fullWidth`
- `loading` → `loading`
- `disabled` → `disabled`
- `onClick` → `onClick`
- `type` → `type`

#### 2. Delete Custom Button Component

After all imports are updated, delete:
- `frontend/src/hwqa/components/common/Button/Button.tsx`
- `frontend/src/hwqa/components/common/Button/Button.module.css`
- `frontend/src/hwqa/components/common/Button/index.ts` (if exists)

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compilation passes: `cd frontend && npx tsc --noEmit`
- [ ] ESLint passes: `cd frontend && npm run lint`
- [ ] No references to custom Button: `grep -r "from.*Button/Button" frontend/src/hwqa/`
- [ ] Build succeeds: `cd frontend && npm run build`

#### Manual Verification:
- [ ] All HWQA pages load without errors
- [ ] Buttons appear with rounded corners (pill shape)
- [ ] Primary buttons show teal color (#006B59)
- [ ] Secondary buttons have default/outline appearance
- [ ] Danger buttons show red/critical color
- [ ] Loading states work correctly (spinner appears)
- [ ] Disabled states work correctly (grayed out, not clickable)

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to Phase 2.

---

## Phase 2: Form CSS Migration

### Overview
Migrate medium-priority CSS Modules to Mantine inline props. Focus on form components where CSS Modules define layout and spacing.

### Files to Migrate (10 files, ~590 lines):

#### Priority Order:
1. `DashboardFilters.module.css` (35 lines) - Simple grid layout
2. `SpreadsheetExport.module.css` (14 lines) - Minimal styling
3. `PhaseMetricsGrid.module.css` (19 lines) - Progress styling
4. `ShipmentDetailsList.module.css` (9 lines) - Simple layout
5. `PrimaryIssues.module.css` (12 lines) - Badge styling
6. `CreateShipmentForm.module.css` (38 lines) - Form container
7. `PasteShipmentForm.module.css` (41 lines) - Grid paste area
8. `LogShipmentForm.module.css` (46 lines) - Upload form
9. `LogTestForm.module.css` (92 lines) - Complex form
10. `DateRangeFilter.module.css` (79 lines) - Date picker customization

### Migration Pattern

**Before (CSS Module):**
```tsx
import styles from './Component.module.css';

<div className={styles.container}>
  <div className={styles.filterGrid}>
    {/* content */}
  </div>
</div>
```

**After (Mantine Props):**
```tsx
import { Box, SimpleGrid, Paper } from '@mantine/core';

<Box>
  <SimpleGrid cols={3} spacing="md">
    {/* content */}
  </SimpleGrid>
</Box>
```

### Changes Required:

#### 1. DashboardFilters Migration

**File**: `frontend/src/hwqa/components/features/dashboard/DashboardFilters/DashboardFilters.tsx`

Replace CSS classes with Mantine layout components:
- `.filterGrid` → `<SimpleGrid cols={3} spacing="md">`
- `.filterItem` → `<Box>` or remove (use Stack/Group)
- Accordion overrides → Use Mantine Accordion `styles` prop

#### 2. SpreadsheetExport Migration

**File**: `frontend/src/hwqa/components/features/dashboard/RCCAReport/SpreadsheetExport/SpreadsheetExport.tsx`

Replace:
- `.root` → `<Stack gap="md">`
- `.textarea` → `<Textarea styles={{...}}>` or Mantine props
- `.buttonGroup` → `<Group>`

#### 3. Form Components Migration

For each form component (CreateShipmentForm, LogShipmentForm, LogTestForm, PasteShipmentForm):

Replace CSS classes with Mantine equivalents:
- Container classes → `<Paper>`, `<Box>`, `<Stack>`
- Grid layouts → `<SimpleGrid>`, `<Grid>`
- Spacing → `gap`, `p`, `m` props
- Focus states → Mantine handles automatically

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compilation passes
- [ ] ESLint passes
- [ ] Build succeeds
- [ ] Deleted CSS module files have no remaining imports

#### Manual Verification:
- [ ] Dashboard filters display correctly in grid layout
- [ ] Accordion expand/collapse works
- [ ] Spreadsheet export textarea and buttons align correctly
- [ ] All form layouts render correctly
- [ ] Form inputs have proper spacing
- [ ] Date range filter calendar displays correctly

**Implementation Note**: This phase can be done incrementally - migrate one file, test, then proceed to the next. Pause for manual confirmation before proceeding to Phase 3.

---

## Phase 3: Cleanup

### Overview
Address remaining CSS modules and global overrides. Most of these should be kept but may need minor cleanup.

### Files to Review:

#### Keep As-Is (Domain-Specific):
- `DataTable.module.css` - AG-Grid theming (107 lines)
- `ExcelGrid.module.css` - Custom grid implementation (129 lines)
- `PageContainer.module.css` - Simple layout utility (7 lines)
- `AppNavbar.module.css` - Navigation styling (45 lines)
- `NavbarLinksGroup.module.css` - Navigation links (59 lines)
- `QAGoals.module.css` - Minimal padding (3 lines)

#### Review for Cleanup:
- `ShipmentsPage.module.css` (52 lines) - Has global button overrides that may conflict with themed buttons

#### SequentialConfirmationModal:
- `SequentialConfirmationModal.module.css` (113 lines) - Complex modal styling
- Consider migrating to Mantine props if time permits

### Success Criteria:

#### Automated Verification:
- [ ] No console warnings about CSS conflicts
- [ ] Build succeeds

#### Manual Verification:
- [ ] All pages render correctly
- [ ] No visual regressions

---

## Testing Strategy

### Unit Tests:
- Existing tests should continue to pass
- Button click handlers still work
- Form submissions work correctly

### Integration Tests:
- HWQA routing works
- All 8 pages accessible and functional
- Data loading and display works

### Manual Testing Steps:
1. Navigate to each HWQA page and verify:
   - Page loads without errors
   - Buttons appear correctly (rounded, proper colors)
   - Forms submit correctly
2. Test all button variants:
   - Submit buttons (primary)
   - Cancel buttons (secondary/default)
   - Delete buttons (danger/critical)
3. Test loading states on all buttons
4. Test form validation and error display
5. Verify responsive behavior

---

## Performance Considerations

- Removing CSS Modules reduces bundle size slightly
- Mantine's CSS-in-JS has minimal runtime overhead
- No performance regressions expected

---

## Migration Notes

### Import Path Changes:
All Button imports change from relative paths to `@mantine/core`

### Breaking Changes:
None - all functionality preserved, only visual implementation changes

### Rollback Plan:
Git revert if issues discovered - each phase is a separate commit

---

## References

- Research document: `thoughts/shared/research/2025-12-02-IWA-14069-hwqa-component-reuse-analysis.md`
- AssetWatch theme: `frontend/src/styles/assetWatchTheme.ts:11-56`
- AssetWatch color palette: `frontend/src/styles/colorPalette.ts`
- CustomerDetail example patterns: `frontend/src/components/CustomerDetailPage/SummaryTab/`
- Mantine Button docs: https://mantine.dev/core/button/
