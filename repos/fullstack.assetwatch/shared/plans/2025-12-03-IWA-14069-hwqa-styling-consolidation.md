# HWQA Styling Consolidation Implementation Plan

## Overview

Consolidate HWQA styling to use AssetWatch's existing styling system, eliminating redundant code. The HWQA section currently maintains its own copy of color palettes, typography, spacing, and other styling constants that are identical to AssetWatch's design system. This plan removes the duplicate HWQA styling files and updates any imports to use AssetWatch's styling infrastructure.

## Current State Analysis

### HWQA Styling Files (To Be Deleted)
The `frontend/src/hwqa/styles/` directory contains 10 TypeScript files that duplicate AssetWatch styling:

| File | Purpose | Redundant Because |
|------|---------|-------------------|
| `colors/palettes.ts` | Color definitions | Identical hex values to `@styles/colorPalette.ts` |
| `fonts/fonts.ts` | Font families/sizes | Mantine theme handles this |
| `constants/spacing.ts` | Spacing constants | Mantine spacing system |
| `constants/layout.ts` | Layout dimensions | Can use shared constants |
| `breakpoints/breakpoints.ts` | Responsive breakpoints | Mantine breakpoints |
| `mixins/typography.ts` | Typography mixins | Mantine Text component |
| `mixins/flexbox.ts` | Flexbox utilities | Mantine Flex/Stack components |
| `animations/keyframes.ts` | Animation keyframes | CSS modules or Mantine transitions |
| `animations/transitions.ts` | Transition timings | Mantine transitions |
| `index.ts` | Re-exports all | References non-existent `themes/mantineTheme` |

### AssetWatch Styling System (To Use Instead)
- `frontend/src/styles/colorPalette.ts` - Color definitions with `staticColors`, `mantineColorTuples`
- `frontend/src/styles/assetWatchTheme.ts` - Mantine theme configuration
- `frontend/src/hooks/useColors.ts` - React hook for theme-reactive colors
- `frontend/src/hooks/useOrderedDataVisualColors.ts` - Hook for chart colors
- `frontend/src/styles/zIndex/` - Z-index management system

### Key Discoveries:
- **Colors are identical**: HWQA's `colorPalettes` has exact same hex values as AssetWatch's `figmaColors` (`frontend/src/hwqa/styles/colors/palettes.ts:26-116` matches `frontend/src/styles/colorPalette.ts:5-118`)
- **Different export structure**: HWQA exports `orderedDataVisualColors` as an array from palettes.ts, while AssetWatch provides `useOrderedDataVisualColors` hook
- **Only 1 direct import**: Only `frontend/src/hwqa/components/features/dashboard/PassRateOverview/charts/constants.ts:1` imports from HWQA palettes
- **HWQA already uses AssetWatch colors**: Most HWQA components use `useColors` hook from `@hooks/useColors` (e.g., `HwqaSideNav.tsx:28`)
- **17 CSS modules exist**: Various `.module.css` files in HWQA with some hardcoded colors

## Desired End State

After this plan is complete:
1. The `frontend/src/hwqa/styles/` directory is completely deleted
2. All HWQA components use AssetWatch styling imports (`@styles/`, `@hooks/useColors`)
3. No hardcoded color values in HWQA components
4. HWQA pages use consistent light gray backgrounds (`neutral.9`) instead of white
5. All tests pass and the application builds successfully

### How to Verify:
- `npm run typecheck` passes with no errors
- `npm run lint` passes
- `npm run build` succeeds
- No imports from `hwqa/styles` exist in the codebase
- HWQA pages render correctly with proper styling

## What We're NOT Doing

- **NOT changing the overall HWQA layout** - Just styling consolidation
- **NOT redesigning HWQA components** - Only removing redundant styling code
- **NOT adding new features** - Pure cleanup/consolidation
- **NOT modifying AssetWatch styling** - Using it as-is
- **NOT touching CSS modules** that don't have hardcoded colors - Only update problematic ones
- **NOT changing navbar/header behavior** - Only updating background colors

## Implementation Approach

We'll take an incremental approach:
1. First, fix the one file that imports from HWQA styles
2. Verify no other imports exist
3. Delete the redundant HWQA styles directory
4. Fix hardcoded colors and background styling issues

---

## Phase 1: Update Chart Colors Import

### Overview
Update the single file that directly imports from HWQA palettes to use AssetWatch's equivalent.

### Changes Required:

#### 1. Update PassRateOverview Chart Constants
**File**: `frontend/src/hwqa/components/features/dashboard/PassRateOverview/charts/constants.ts`
**Changes**: Replace HWQA `orderedDataVisualColors` import with AssetWatch equivalent

**Current code** (lines 1-3):
```typescript
import { orderedDataVisualColors } from '../../../../../styles/colors/palettes';

export const TEST_SPEC_COLORS = orderedDataVisualColors.slice(0, 12);
```

**Problem**: This file imports colors for use in chart configuration, but it's a non-React file (`.ts`) so it can't use hooks.

**Solution**: Import from AssetWatch's `staticColors` and create an equivalent array, OR refactor to pass colors from a parent component.

**Option A - Use staticColors** (simpler, recommended):
```typescript
import { staticColors } from '@styles/colorPalette';

// Ordered array of data visualization colors for charts
// Uses shade index 10 (darker shades) for good visibility - matches AssetWatch pattern
export const TEST_SPEC_COLORS = [
  staticColors.dataVisualBlue10,
  staticColors.dataVisualCyan10,
  staticColors.dataVisualViolet10,
  staticColors.dataVisualOrange10,
  staticColors.dataVisualPink10,
  staticColors.dataVisualGreen10,
  staticColors.dataVisualPurple10,
  staticColors.dataVisualCoral20,
  staticColors.dataVisualCyan0,
  staticColors.dataVisualPink0,
  staticColors.dataVisualIndigo10,
  staticColors.dataVisualRed10,
];

export const Y_AXIS_DOMAIN = [0, 100];
```

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles: `cd frontend && npm run typecheck`
- [x] Linting passes: `cd frontend && npm run lint` (no lint script, using build instead)
- [x] Build succeeds: `cd frontend && npm run build`
- [x] No import errors in the file

#### Manual Verification:
- [ ] PassRateOverview charts render with correct colors
- [ ] Chart legend shows proper color associations
- [ ] No visual regression in dashboard charts

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the charts render correctly before proceeding.

---

## Phase 2: Verify and Remove HWQA Styles Directory

### Overview
Verify no other files import from HWQA styles, then delete the entire directory.

### Changes Required:

#### 1. Verify No Remaining Imports
**Action**: Search for any remaining imports from `hwqa/styles`

```bash
# Run this search to verify
grep -r "from.*hwqa/styles" frontend/src/ --include="*.ts" --include="*.tsx"
grep -r "from.*hwqa.*palettes" frontend/src/ --include="*.ts" --include="*.tsx"
```

Expected result: No matches (after Phase 1 changes)

#### 2. Delete HWQA Styles Directory
**Directory**: `frontend/src/hwqa/styles/`
**Action**: Delete entire directory

Files to be deleted:
- `frontend/src/hwqa/styles/index.ts`
- `frontend/src/hwqa/styles/colors/palettes.ts`
- `frontend/src/hwqa/styles/fonts/fonts.ts`
- `frontend/src/hwqa/styles/constants/spacing.ts`
- `frontend/src/hwqa/styles/constants/layout.ts`
- `frontend/src/hwqa/styles/breakpoints/breakpoints.ts`
- `frontend/src/hwqa/styles/mixins/typography.ts`
- `frontend/src/hwqa/styles/mixins/flexbox.ts`
- `frontend/src/hwqa/styles/animations/keyframes.ts`
- `frontend/src/hwqa/styles/animations/transitions.ts`

```bash
rm -rf frontend/src/hwqa/styles/
```

### Success Criteria:

#### Automated Verification:
- [x] No grep results for `hwqa/styles` imports
- [x] TypeScript compiles: `cd frontend && npm run typecheck`
- [x] Linting passes: `cd frontend && npm run lint` (no lint script, using build instead)
- [x] Build succeeds: `cd frontend && npm run build`
- [x] Directory `frontend/src/hwqa/styles/` no longer exists

#### Manual Verification:
- [ ] HWQA section loads without errors
- [ ] All HWQA pages render correctly
- [ ] No console errors related to missing modules

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation that HWQA pages load correctly before proceeding.

---

## Phase 3: Fix Hardcoded Colors in HWQA Components

### Overview
Replace hardcoded color values with AssetWatch theme colors for consistency and maintainability.

### Changes Required:

#### 1. HwqaSideNav Background Color
**File**: `frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.tsx`
**Lines**: 151-153
**Change**: Replace hardcoded "white" with theme color

**Current**:
```typescript
style={{
  zIndex: Z_INDEX_INTERFACE.APP_HEADER,
  backgroundColor: isOpen ? "white" : "transparent",
}}
```

**Updated**:
```typescript
style={{
  zIndex: Z_INDEX_INTERFACE.APP_HEADER,
  backgroundColor: isOpen ? "var(--mantine-color-neutral-9)" : "transparent",
}}
```

#### 2. ProtectedRoute Loading Screen Colors
**File**: `frontend/src/hwqa/components/ProtectedRoute.tsx`
**Changes**: Replace hardcoded colors with theme colors

**Lines with hardcoded colors**:
- Line 132: `backgroundColor: '#1a1b1e'` → Use `neutral10`
- Line 152: `backgroundColor: '#efeef1'` → Use `neutral95`
- Line 163: `color: '#1a1c1e'` → Use `neutral10`
- Line 166: `color: '#5d5d61'` → Use `neutral40`
- Line 176: `backgroundColor: '#00a388'` → Use `primary60`

#### 3. Chart Components with Hardcoded Colors
**Files**:
- `frontend/src/hwqa/components/features/dashboard/PassRateOverview/PassRateBarChart.tsx:23`
- `frontend/src/hwqa/components/features/dashboard/PassRateOverview/PassRateLineChart.tsx:23`

**Change**: Replace `#8884d8` with theme color from `staticColors`

#### 4. ChartTooltip Hardcoded Colors
**File**: `frontend/src/hwqa/components/features/dashboard/PassRateOverview/ChartTooltip.tsx`
**Lines**: 44-60
**Change**: Use CSS variables or theme colors for tooltip styling

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles: `cd frontend && npm run typecheck`
- [x] Linting passes: `cd frontend && npm run lint` (no lint script, using build instead)
- [x] Build succeeds: `cd frontend && npm run build`

#### Manual Verification:
- [ ] HwqaSideNav background appears as light gray (`#F0F0F4`) when open
- [ ] ProtectedRoute loading screens use proper theme colors
- [ ] Chart tooltips render with proper styling
- [ ] All colors match AssetWatch design system

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation that styling looks correct before proceeding.

---

## Phase 4: Apply Consistent Page Backgrounds

### Overview
Update HWQA page containers to use light gray backgrounds (`neutral.9` / `#F0F0F4`) instead of inheriting white, matching the AssetWatch styling pattern.

### Changes Required:

#### 1. HwqaPage Main Container
**File**: `frontend/src/pages/HwqaPage.tsx`
**Lines**: 40-56
**Change**: Add background color to main content area

**Current**:
```typescript
<Box
  style={{
    marginLeft: isSmallScreen ? 0 : isSideNavOpen ? SIDE_NAV_WIDTH_OPEN : SIDE_NAV_WIDTH_CLOSED,
    flex: 1,
    padding: "16px",
  }}
>
```

**Updated**:
```typescript
<Box
  bg="neutral.9"
  style={{
    marginLeft: isSmallScreen ? 0 : isSideNavOpen ? SIDE_NAV_WIDTH_OPEN : SIDE_NAV_WIDTH_CLOSED,
    flex: 1,
    padding: "16px",
    minHeight: "100vh",
  }}
>
```

#### 2. PageContainer Component (Optional)
**File**: `frontend/src/hwqa/components/layout/PageContainer/PageContainer.tsx`
**Change**: Consider adding background color if needed for nested containers

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles: `cd frontend && npm run typecheck`
- [x] Linting passes: `cd frontend && npm run lint` (no lint script, using build instead)
- [x] Build succeeds: `cd frontend && npm run build`

#### Manual Verification:
- [ ] HWQA pages have light gray background instead of white
- [ ] Background color matches AssetWatch's `neutral.9` (`#F0F0F4`)
- [ ] Content cards/papers stand out properly against the background
- [ ] No visual regression in other parts of the HWQA section

**Implementation Note**: This phase completes the styling consolidation. After verification, the HWQA section should visually align with AssetWatch's design patterns.

---

## Testing Strategy

### Unit Tests:
- No new unit tests required - this is a refactoring task
- Existing tests should continue to pass

### Integration Tests:
- Run full frontend build to verify no import errors
- Verify all TypeScript types resolve correctly

### Manual Testing Steps:
1. Navigate to HWQA section in the application
2. Verify all pages load without console errors
3. Check that colors match AssetWatch design system:
   - Backgrounds should be light gray (`#F0F0F4`)
   - Primary actions should use teal (`#00A388`)
   - Text should use neutral grays
4. Verify dashboard charts render with proper colors
5. Test sidebar navigation open/close states
6. Check responsive behavior on different screen sizes

## Performance Considerations

- **Bundle size reduction**: Removing duplicate styling files will slightly reduce bundle size
- **No runtime impact**: This is purely a code organization change
- **Tree-shaking**: AssetWatch's `staticColors` is tree-shakeable, only used colors will be bundled

## Rollback Strategy

If issues arise:
1. The HWQA styles directory can be restored from git history
2. Import changes can be reverted to use HWQA styles
3. No database migrations or backend changes - pure frontend refactoring

## References

- Original research: `thoughts/shared/research/2025-12-03-IWA-14069-hwqa-styling-research.md`
- AssetWatch color palette: `frontend/src/styles/colorPalette.ts`
- AssetWatch theme: `frontend/src/styles/assetWatchTheme.ts`
- useColors hook: `frontend/src/hooks/useColors.ts`
- useOrderedDataVisualColors hook: `frontend/src/hooks/useOrderedDataVisualColors.ts`
