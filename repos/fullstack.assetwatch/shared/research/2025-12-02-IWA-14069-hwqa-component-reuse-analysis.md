---
date: 2025-12-02T12:00:00-05:00
researcher: Claude
git_commit: 800c66153
branch: db/IWA-14069
repository: fullstack.assetwatch-hwqa-migration
topic: "HWQA Visual Consistency - Component Reuse Analysis"
tags: [research, codebase, hwqa, mantine, components, styling, design-system]
status: complete
last_updated: 2025-12-02
last_updated_by: Claude
---

# Research: HWQA Visual Consistency - Component Reuse Analysis

**Date**: 2025-12-02T12:00:00-05:00
**Researcher**: Claude
**Git Commit**: 800c66153
**Branch**: db/IWA-14069
**Repository**: fullstack.assetwatch-hwqa-migration

## Research Question
What reusable UI components exist in the AssetWatch codebase, and which can be adopted by HWQA for visual consistency? Focus on modern patterns from CustomerDetail/Summary tab.

## Summary

Both AssetWatch and HWQA use **Mantine UI v8.2.4** as their primary component framework. However, there's a significant **styling approach divergence**:

- **AssetWatch (modern pattern)**: Uses Mantine inline props exclusively (`c="primary40"`, `bg="neutral98"`, etc.) - NO CSS modules
- **HWQA (current pattern)**: Uses Mantine components BUT with CSS Modules (18 `.module.css` files) and custom wrapper components

The path to visual consistency involves:
1. Adopting AssetWatch's semantic color naming convention
2. Replacing custom HWQA Button/Modal wrappers with Mantine's themed components
3. Transitioning from CSS Modules to Mantine inline props
4. Reusing AssetWatch's Card, Table action bar, and layout patterns

---

## Detailed Findings

### AssetWatch Component Library

#### Buttons (20+ components)
| Component | Location | Purpose |
|-----------|----------|---------|
| Themed Mantine Button | via `assetWatchTheme.ts:18-23` | Default: `color="primary40"`, `radius="xl"` |
| `SubmitButton` | `components/common/SubmitButton.tsx` | Form submission |
| `ActionButtons` | `components/common/ActionButtons.tsx` | Action button groups |
| `SaveChartButton` | `components/common/SaveChartButton/` | Chart saving |

**Modern Pattern (CustomerDetail):**
```tsx
// Rounded buttons with semantic colors
<Button color="primary40" radius="xl">Save</Button>
<Anchor c="primary40">View All</Anchor>
```

#### Cards (25+ components)
| Component | Location | Purpose |
|-----------|----------|---------|
| `PieChartCard` | `CustomerDetailPage/SummaryTab/PieChartCard.tsx` | Chart container |
| `CostSavingsCard` | `CustomerDetailPage/SummaryTab/CostSavingsCard.tsx` | Metric display |
| `InsightSummaryCard` | `CustomerDetailPage/Insights/` | Summary cards |
| `AssetCard` | `components/AssetCard.tsx` | Asset display |

**Modern Pattern:**
```tsx
<Card shadow="md" withBorder radius="md" p="lg">
  <Title fz={18} fw={500}>Card Title</Title>
  {content}
</Card>
```

#### Tables (13+ components)
| Component | Location | Purpose |
|-----------|----------|---------|
| `DataTable` | `components/common/DataTable.tsx` | Main AG-Grid wrapper |
| `DataTableActionBar` | `components/common/DataTableActionBar.tsx` | Filter/action toolbar |
| Mantine Table | `@mantine/core` | Simple tables in modals |

**Modern Pattern:**
```tsx
// Simple tables
<Table withTableBorder withColumnBorders>
  <Table.Thead>...</Table.Thead>
  <Table.Tbody>...</Table.Tbody>
</Table>

// Complex data grids use AG-Grid with custom styling
```

#### Modals (50+ components)
| Component | Location | Purpose |
|-----------|----------|---------|
| `SimpleModal` | `components/common/SimpleModal.tsx` | Basic modal wrapper |
| `ConfirmationModal` | `components/common/ConfirmationModal.tsx` | Confirm dialogs |
| Mantine Modal | `@mantine/core` | Direct usage |

**Modern Pattern:**
```tsx
<Modal opened={opened} onClose={close} size="60%" title="Modal Title">
  <Stack gap="md">
    {content}
  </Stack>
</Modal>
```

#### Dropdowns/Selects (45+ components)
| Component | Location | Purpose |
|-----------|----------|---------|
| `MultiSelectFilter` | `components/common/MultiSelectFilter.tsx` | Multi-select with filter |
| `CreatableSelect` | `components/common/CreatableSelect.tsx` | Add new options |
| `FacilitySelect` | `components/FacilitySelect.tsx` | Facility picker |
| `CustomerSelect` | `components/CustomerSelect.tsx` | Customer picker |

**Modern Pattern:**
```tsx
<Select
  data={options}
  placeholder="Select..."
  checkIconPosition="left"  // Theme default
/>
```

#### Forms (45+ components)
| Component | Location | Purpose |
|-----------|----------|---------|
| `SerialNumberInput` | `components/common/forms/SerialNumberInput.tsx` | SN input |
| `FormErrorText` | `components/common/forms/FormErrorText.tsx` | Error display |
| Input sections | `ComponentModal/tabs/detail/sections/` | Form layouts |

---

### HWQA Current Component State

#### Custom Components (Replace/Update These)

| HWQA Component | Location | Recommendation |
|----------------|----------|----------------|
| `Button` | `hwqa/components/common/Button/` | **Replace** with themed Mantine Button |
| `FormModal` | `hwqa/components/common/Modal/FormModal.tsx` | **Align** with AssetWatch modal patterns |
| `ConfirmationModal` | `hwqa/components/common/Modal/ConfirmationModal.tsx` | **Use** Mantine modals directly |
| `DataTable` | `hwqa/components/common/DataTable/` | **Keep** - well-customized for HWQA |
| `DateRangeFilter` | `hwqa/components/common/DateRangeFilter/` | **Keep** - domain-specific |

#### CSS Modules to Migrate (18 files)

| File | Lines | Priority |
|------|-------|----------|
| `Button.module.css` | 77 | **High** - Replace with themed Button |
| `DataTable.module.css` | 107 | Low - AG-Grid specific theming |
| `DashboardFilters.module.css` | 35 | Medium |
| `LogTestForm.module.css` | — | Medium |
| `CreateShipmentForm.module.css` | — | Medium |
| `PageContainer.module.css` | — | Medium |
| `AppNavbar.module.css` | — | Medium |
| `HwqaSideNav.module.css` | — | Medium |

---

### Color System Comparison

**Both systems are aligned** - they reference the same Figma design library.

#### AssetWatch Colors (`styles/colorPalette.ts`)
```typescript
// Semantic color naming: colorName + shade (0-100)
primary40, primary60, primary80
secondary30, secondary60
critical40, critical50
warning80
neutral60, neutral80, neutral98
```

#### HWQA Colors (`hwqa/styles/colors/palettes.ts`)
```typescript
// Same Mantine 0-9 index system
// Same color families: primary, secondary, tertiary, critical, warning, neutral
// Data visualization colors: coral, lime, violet, etc.
```

**Key Finding**: Color systems are already compatible. HWQA just needs to adopt the semantic naming convention in component props.

---

### Styling Pattern Comparison

#### AssetWatch Modern Pattern (CustomerDetail)
```tsx
// All styling via Mantine props - NO CSS files
<Container size="xl">
  <Title ta="center" fz={28} fw={500} tt="none" ff="Montserrat" my="xl">
    Welcome
  </Title>
  <Flex wrap="wrap" gap={50}>
    <Stack w={360}>
      <Card shadow="md" withBorder radius="md">
        <Text c="primary40" fw={500}>Content</Text>
      </Card>
    </Stack>
  </Flex>
</Container>
```

#### HWQA Current Pattern
```tsx
// Mantine components + CSS Modules
import styles from './Component.module.css';

<div className={styles.container}>
  <Button variant="primary" size="md">Submit</Button>
</div>
```

---

### HWQA Pages Requiring Updates

| Page | Current State | Recommendation |
|------|---------------|----------------|
| `SensorTestsPage` | Paper, Stack, Loader | Minor - already uses Mantine |
| `HubTestsPage` | Same as Sensor | Minor |
| `SensorShipmentsPage` | Forms with CSS Modules | Medium - migrate form styling |
| `HubShipmentsPage` | Same as Sensor | Medium |
| `SensorDashboardPage` | Charts, filters | Medium - filter components |
| `HubDashboardPage` | Same as Sensor | Medium |
| `GlossaryPage` | Tabs, SimpleGrid, Search | Minor - clean Mantine usage |
| `SensorConversionPage` | Forms | Medium |

---

## Reusable AssetWatch Components for HWQA

### High-Value Reuse Opportunities

1. **Card Pattern**
   - Use `shadow="md"`, `withBorder`, `radius="md"` consistently
   - Adopt `Paper` with `bg="secondary30"` for highlighted sections

2. **Button Theme**
   - Remove custom Button component
   - Use Mantine Button with `assetWatchTheme` defaults
   - Colors: `primary40`, `critical50`, etc.

3. **Modal Pattern**
   - Use Mantine Modal directly
   - Standard props: `size`, `title`, `opened`, `onClose`

4. **Loading States**
   - `<Skeleton visible={isLoading} radius="md">`

5. **Layout Components**
   - `Container size="xl"`
   - `Stack`, `Group`, `Flex` for layouts
   - `SimpleGrid` for grids

### Components HWQA Should Keep

1. **DataTable** - AG-Grid integration is domain-specific
2. **DateRangeFilter** - HWQA-specific date filtering
3. **CSVExportButton** - Specific to HWQA export needs
4. **Dashboard filters** - Complex filtering specific to QA metrics

---

## Code References

### AssetWatch Theme Configuration
- `frontend/src/styles/assetWatchTheme.ts:11-56` - Mantine theme with Button defaults
- `frontend/src/styles/colorPalette.ts:1-327` - Full color palette
- `frontend/src/hooks/useColors.ts:22-39` - Color access hook

### CustomerDetail Modern Patterns
- `frontend/src/components/CustomerDetailPage/SummaryTab/SummaryTab.tsx:15-46` - Layout example
- `frontend/src/components/CustomerDetailPage/SummaryTab/PieChartCard.tsx:24-37` - Card + Chart
- `frontend/src/components/CustomerDetailPage/SummaryTab/CostSavings.tsx:162-226` - Skeleton loading

### HWQA Current Implementation
- `frontend/src/hwqa/components/common/Button/Button.tsx:12-35` - Custom button (to replace)
- `frontend/src/hwqa/components/common/Modal/FormModal.tsx:79-136` - Modal wrapper
- `frontend/src/hwqa/styles/colors/palettes.ts:26-361` - Color system (compatible)

### Shared Infrastructure
- `frontend/src/TanStackRoutes.tsx:96-100` - MantineProvider setup
- `frontend/src/styles/css/colorVariables.css` - CSS variables
- `frontend/src/styles/css/globalOverrides.css` - Global overrides

---

## Architecture Insights

### Mantine Provider Hierarchy
```
QueryClientProvider
  → PendoProvider
    → LaunchDarklyProvider
      → MantineProvider (assetWatchTheme)
        → DatesProvider
          → ModalsProvider
            → App
```

HWQA inherits theme automatically through this hierarchy when accessed via `/hwqa` route.

### Styling Best Practices (from CustomerDetail)
1. **No CSS Modules** for component styling
2. **All styling via props**: `c`, `bg`, `fz`, `fw`, `m`, `p`, `gap`, etc.
3. **Semantic colors**: `primary40`, not raw hex values
4. **Consistent spacing**: Use Mantine spacing scale (`xs`, `sm`, `md`, `lg`, `xl`)
5. **Typography**: `fz` for size, `fw` for weight, `ff` for family

---

## Open Questions

1. Should HWQA's CSS Modules be migrated all at once or incrementally?
2. Should the custom Button component be deprecated or wrapped around Mantine Button?
3. What's the timeline expectation for visual consistency?
4. Are there any HWQA-specific styling requirements that differ from AssetWatch?

---

## Recommended Next Steps

### Phase 1: Quick Wins (Low effort, high impact)
1. Replace custom `Button` with Mantine Button
2. Add `radius="md"` and `shadow="md"` to existing Cards
3. Use semantic color props (`c="primary40"`) instead of CSS variables

### Phase 2: Form Consistency
1. Migrate form components to Mantine prop styling
2. Standardize modal patterns
3. Update page layouts to match CustomerDetail

### Phase 3: Full Migration
1. Remove CSS Modules progressively
2. Create shared component variants if needed
3. Document HWQA-specific patterns
