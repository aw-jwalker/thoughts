# Dark Mode Consolidation Plan

## Overview

Consolidate all dark mode related code from branches `IWA-14149` and `db/IWA-14150` into the dedicated dark mode demo branch `IWA-14170`. After this work:
- `IWA-14149` and `db/IWA-14150` will have NO dark mode code
- HWQA components will use standard AssetWatch colors/styles (via `useColors()` hook and Mantine theme)
- `IWA-14170` will contain all dark mode infrastructure

## Current State Analysis

### Branch Overview
| Branch | Purpose | Dark Mode Content |
|--------|---------|-------------------|
| `dev` | Base branch | Clean (no dark mode) |
| `IWA-14149` | HWQA Phase 1 - Integration | `HwqaPage.tsx` imports `HwqaThemeWrapper` |
| `db/IWA-14150` | HWQA Phase 2 - Full module | Full dark mode infrastructure + CSS variable usage |
| `IWA-14170` | Dark mode demo | App-level theme changes only |
| `db/IWA-14069` | Original dark mode work | Both HWQA + app-level (reference only) |

### Dark Mode Files in db/IWA-14150
**Infrastructure files (to move to IWA-14170):**
- `frontend/src/hwqa/styles/cssVariablesResolver.ts`
- `frontend/src/hwqa/styles/agGridTheme.css`
- `frontend/src/hwqa/components/HwqaThemeWrapper.tsx`
- `frontend/src/hwqa/context/HwqaThemeContext.tsx`
- `frontend/src/hwqa/components/common/ThemeToggle/ThemeToggle.tsx`
- `frontend/src/hwqa/components/common/ThemeToggle/index.ts`

**Files using semantic CSS variables (to revert to standard colors):**
- `frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.tsx`
- `frontend/src/hwqa/components/common/DateRangeFilter/DateRangeFilter.module.css`
- `frontend/src/hwqa/components/features/dashboard/DashboardFilters/DashboardFilters.module.css`
- `frontend/src/hwqa/components/features/dashboard/RCCAReport/PhaseMetricsGrid/PhaseMetricsGrid.module.css`
- `frontend/src/hwqa/components/features/dashboard/RCCAReport/PrimaryIssues/PrimaryIssues.module.css`
- `frontend/src/hwqa/components/features/dashboard/RCCAReport/QAGoals/QAGoals.module.css`
- `frontend/src/hwqa/components/features/dashboard/RCCAReport/ShipmentDetailsList/ShipmentDetailsList.module.css`
- `frontend/src/hwqa/components/features/dashboard/RCCAReport/SpreadsheetExport/SpreadsheetExport.module.css`
- `frontend/src/hwqa/components/features/shipments/CreateShipmentForm.module.css`
- `frontend/src/hwqa/components/features/shipments/ExcelGrid.module.css`
- `frontend/src/hwqa/components/features/shipments/LogShipmentForm.module.css`
- `frontend/src/hwqa/components/features/shipments/PasteShipmentForm.module.css`
- `frontend/src/hwqa/components/features/tests/LogTestForm.module.css`
- `frontend/src/hwqa/components/features/tests/sequential-confirmation/SequentialConfirmationModal.module.css`

## Desired End State

### IWA-14149 Branch
- `HwqaPage.tsx` does NOT import or use `HwqaThemeWrapper`
- No references to `HwqaThemeContext`
- No semantic CSS variables (`--bg-*`, `--text-*`, etc.)

### db/IWA-14150 Branch
- NO dark mode infrastructure files exist
- All components use standard AssetWatch styling:
  - `useColors()` hook for dynamic colors in TSX
  - Direct Mantine color tokens in CSS (e.g., `var(--mantine-color-neutral60-0)`)
  - Standard Mantine component props
- `HwqaSideNav` follows same pattern as `CustomerDetailPage/SideNav.tsx`

### IWA-14170 Branch
- Contains all HWQA dark mode infrastructure
- Can be merged later when app-wide dark mode is ready

## What We're NOT Doing

- NOT changing the app-level theme (`assetWatchTheme.ts`) in 14149/14150
- NOT changing `colorPalette.ts` or `colorVariables.css` in 14149/14150
- NOT implementing app-wide dark mode
- NOT changing any non-HWQA components

---

## Phase 1: Update IWA-14149 - Remove Dark Mode from HwqaPage

### Overview
Remove the `HwqaThemeWrapper` usage from `HwqaPage.tsx` so it doesn't depend on dark mode infrastructure.

### Changes Required

#### 1. HwqaPage.tsx
**File**: `frontend/src/pages/HwqaPage.tsx`

**Remove import:**
```tsx
// DELETE this line:
import { HwqaThemeWrapper } from "../hwqa/components/HwqaThemeWrapper";
```

**Update HwqaPage component - remove wrapper and semantic variable:**
```tsx
// BEFORE:
export function HwqaPage() {
  return (
    <HwqaProtectedRoute>
      <QueryClientProvider client={hwqaQueryClient}>
        <AppStateProvider>
          <HwqaThemeWrapper>
            <HwqaContent />
          </HwqaThemeWrapper>
        </AppStateProvider>
      </QueryClientProvider>
    </HwqaProtectedRoute>
  );
}

// AFTER:
export function HwqaPage() {
  return (
    <HwqaProtectedRoute>
      <QueryClientProvider client={hwqaQueryClient}>
        <AppStateProvider>
          <HwqaContent />
        </AppStateProvider>
      </QueryClientProvider>
    </HwqaProtectedRoute>
  );
}
```

**Update HwqaContent - remove semantic CSS variable:**
```tsx
// BEFORE:
<Box
  bg="var(--bg-body)"
  style={{
    marginLeft: sideNavWidth,
    ...
  }}
>

// AFTER:
<Box
  style={{
    marginLeft: sideNavWidth,
    ...
  }}
>
```

### Success Criteria

#### Automated Verification:
- [x] TypeScript compiles without errors (HWQA files only):
  ```bash
  cd frontend && npx tsc --noEmit 2>&1 | grep -E "src/hwqa/|src/pages/Hwqa" || echo "No HWQA TypeScript errors"
  ```
- [x] No imports of `HwqaThemeWrapper` in HwqaPage:
  ```bash
  grep -c "HwqaThemeWrapper" frontend/src/pages/HwqaPage.tsx || echo "No HwqaThemeWrapper imports"
  ```
- [x] No semantic CSS variables in HwqaPage:
  ```bash
  grep -E "var\(--bg-|var\(--text-|var\(--border-|var\(--status-|var\(--nav-" frontend/src/pages/HwqaPage.tsx || echo "No semantic variables"
  ```

#### Manual Verification:
- [ ] HWQA page loads correctly (will need Phase 2 complete for full test)

---

## Phase 2: Update db/IWA-14150 - Remove Dark Mode Infrastructure

### Overview
Remove all dark mode infrastructure files and update context exports.

### Changes Required

#### 1. Delete Dark Mode Files
**Files to delete:**
- `frontend/src/hwqa/styles/cssVariablesResolver.ts`
- `frontend/src/hwqa/styles/agGridTheme.css`
- `frontend/src/hwqa/components/HwqaThemeWrapper.tsx`
- `frontend/src/hwqa/context/HwqaThemeContext.tsx`
- `frontend/src/hwqa/components/common/ThemeToggle/ThemeToggle.tsx`
- `frontend/src/hwqa/components/common/ThemeToggle/index.ts`

#### 2. Update Context Index
**File**: `frontend/src/hwqa/context/index.ts`

```tsx
// BEFORE:
export { AppStateProvider, useAppState } from "./AppStateContext";
export { HwqaThemeProvider, useHwqaTheme } from "./HwqaThemeContext";

// AFTER:
export { AppStateProvider, useAppState } from "./AppStateContext";
```

#### 3. Delete ThemeToggle Directory
Remove the entire directory: `frontend/src/hwqa/components/common/ThemeToggle/`

### Success Criteria

#### Automated Verification:
- [x] Dark mode infrastructure files no longer exist:
  ```bash
  ls frontend/src/hwqa/styles/cssVariablesResolver.ts \
     frontend/src/hwqa/styles/agGridTheme.css \
     frontend/src/hwqa/components/HwqaThemeWrapper.tsx \
     frontend/src/hwqa/context/HwqaThemeContext.tsx \
     frontend/src/hwqa/components/common/ThemeToggle/ 2>&1 | grep -c "No such file" || echo "Files still exist!"
  ```
- [x] No TypeScript errors in HWQA from missing exports:
  ```bash
  cd frontend && npx tsc --noEmit 2>&1 | grep -E "src/hwqa/" || echo "No HWQA TypeScript errors"
  ```
- [x] No remaining imports of deleted modules in HWQA:
  ```bash
  grep -r "HwqaThemeWrapper\|HwqaThemeContext\|useHwqaTheme\|ThemeToggle\|cssVariablesResolver\|agGridTheme" frontend/src/hwqa/ --include="*.tsx" --include="*.ts" || echo "No remaining imports"
  ```

---

## Phase 3: Update db/IWA-14150 - Convert HwqaSideNav to Standard Styling

### Overview
Update `HwqaSideNav.tsx` to use standard AssetWatch styling patterns (matching `CustomerDetailPage/SideNav.tsx`).

### Changes Required

#### 1. HwqaSideNav.tsx
**File**: `frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.tsx`

**Add useColors import:**
```tsx
import { useColors } from "@hooks/useColors";
```

**Remove ThemeToggle import:**
```tsx
// DELETE:
import { ThemeToggle } from "../common/ThemeToggle";
```

**Add colors hook in component:**
```tsx
export function HwqaSideNav({ isOpen, toggle }: HwqaSideNavProps) {
  const colors = useColors(); // ADD THIS
  // ... rest of component
}
```

**Replace semantic CSS variables with useColors:**

| Semantic Variable | Replacement |
|-------------------|-------------|
| `var(--bg-navbar)` | `"white"` (when open) or `"transparent"` (when closed) |
| `var(--nav-text)` | `colors.primary40` |
| `var(--nav-text-active)` | `"white"` |
| `var(--nav-bg-active)` | `colors.primary40` |
| `var(--border-default)` | `colors.neutral60` |
| `var(--border-subtle)` | `colors.neutral90` |

**Remove ThemeToggle from JSX:**
Find and delete the `<ThemeToggle />` component usage.

**Example transformation for NavLink styling:**
```tsx
// BEFORE:
style={{
  color: isActive ? "var(--nav-text-active)" : "var(--nav-text)",
  backgroundColor: isActive ? "var(--nav-bg-active)" : "",
}}

// AFTER:
style={{
  borderRadius: 10,
  fontWeight: isActive ? "bolder" : "initial",
  color: isActive ? "white" : colors.primary40,
  backgroundColor: isActive ? colors.primary40 : "",
  boxShadow: isActive ? "0px 4px 8px -4px rgba(76, 78, 100, 0.42)" : "none",
}}
```

### Success Criteria

#### Automated Verification:
- [x] TypeScript compiles without errors in HWQA:
  ```bash
  cd frontend && npx tsc --noEmit 2>&1 | grep -E "src/hwqa/" || echo "No HWQA TypeScript errors"
  ```
- [x] No semantic CSS variables in HwqaSideNav:
  ```bash
  grep -E "var\(--bg-|var\(--text-|var\(--border-|var\(--status-|var\(--nav-|var\(--interactive-" frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.tsx || echo "No semantic variables"
  ```
- [x] No imports from ThemeToggle:
  ```bash
  grep "ThemeToggle" frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.tsx || echo "No ThemeToggle imports"
  ```
- [x] Uses useColors hook:
  ```bash
  grep -c "useColors" frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.tsx && echo "useColors is imported"
  ```

#### Manual Verification:
- [ ] SideNav renders correctly with proper colors
- [ ] Active state styling matches CustomerDetail SideNav

---

## Phase 4: Update db/IWA-14150 - Convert CSS Module Files

### Overview
Update all `.module.css` files to use standard Mantine color variables instead of semantic variables.

### CSS Variable Mapping

| Semantic Variable | Mantine Equivalent |
|-------------------|-------------------|
| `var(--bg-surface)` | `white` or `var(--mantine-color-white)` |
| `var(--bg-surface-alt)` | `var(--mantine-color-neutral98-0)` |
| `var(--bg-elevated)` | `white` |
| `var(--bg-hover)` | `var(--mantine-color-neutral95-0)` |
| `var(--text-primary)` | `var(--mantine-color-neutral10-0)` |
| `var(--text-secondary)` | `var(--mantine-color-neutral40-0)` |
| `var(--text-on-primary)` | `white` |
| `var(--border-default)` | `var(--mantine-color-neutral90-0)` |
| `var(--border-focus)` | `var(--mantine-color-primary60-0)` |
| `var(--status-success)` | `var(--mantine-color-primary60-0)` |
| `var(--status-success-bg)` | `var(--mantine-color-primary95-0)` |
| `var(--status-error)` | `var(--mantine-color-error60-0)` |
| `var(--status-warning)` | `var(--mantine-color-warning60-0)` |
| `var(--interactive-selected)` | `var(--mantine-color-primary95-0)` |
| `var(--interactive-active)` | `var(--mantine-color-neutral90-0)` |

### Files to Update

#### 4.1 DateRangeFilter.module.css
**File**: `frontend/src/hwqa/components/common/DateRangeFilter/DateRangeFilter.module.css`

Search for and replace all semantic variables using the mapping above.

#### 4.2 DashboardFilters.module.css
**File**: `frontend/src/hwqa/components/features/dashboard/DashboardFilters/DashboardFilters.module.css`

#### 4.3 PhaseMetricsGrid.module.css
**File**: `frontend/src/hwqa/components/features/dashboard/RCCAReport/PhaseMetricsGrid/PhaseMetricsGrid.module.css`

#### 4.4 PrimaryIssues.module.css
**File**: `frontend/src/hwqa/components/features/dashboard/RCCAReport/PrimaryIssues/PrimaryIssues.module.css`

#### 4.5 QAGoals.module.css
**File**: `frontend/src/hwqa/components/features/dashboard/RCCAReport/QAGoals/QAGoals.module.css`

#### 4.6 ShipmentDetailsList.module.css
**File**: `frontend/src/hwqa/components/features/dashboard/RCCAReport/ShipmentDetailsList/ShipmentDetailsList.module.css`

#### 4.7 SpreadsheetExport.module.css
**File**: `frontend/src/hwqa/components/features/dashboard/RCCAReport/SpreadsheetExport/SpreadsheetExport.module.css`

#### 4.8 CreateShipmentForm.module.css
**File**: `frontend/src/hwqa/components/features/shipments/CreateShipmentForm.module.css`

#### 4.9 ExcelGrid.module.css
**File**: `frontend/src/hwqa/components/features/shipments/ExcelGrid.module.css`

#### 4.10 LogShipmentForm.module.css
**File**: `frontend/src/hwqa/components/features/shipments/LogShipmentForm.module.css`

#### 4.11 PasteShipmentForm.module.css
**File**: `frontend/src/hwqa/components/features/shipments/PasteShipmentForm.module.css`

#### 4.12 LogTestForm.module.css
**File**: `frontend/src/hwqa/components/features/tests/LogTestForm.module.css`

#### 4.13 SequentialConfirmationModal.module.css
**File**: `frontend/src/hwqa/components/features/tests/sequential-confirmation/SequentialConfirmationModal.module.css`

### Success Criteria

#### Automated Verification:
- [x] No semantic CSS variables remain in HWQA .module.css files:
  ```bash
  find frontend/src/hwqa -name "*.module.css" -exec grep -l "var(--bg-\|var(--text-\|var(--border-\|var(--status-\|var(--nav-\|var(--interactive-\|var(--brand-" {} \; || echo "No semantic variables in CSS modules"
  ```
- [ ] Frontend build succeeds (validates CSS syntax):
  ```bash
  cd frontend && npm run build 2>&1 | grep -E "error|Error" | grep -v "node_modules" || echo "Build succeeded"
  ```

#### Manual Verification:
- [ ] All styled components render with appropriate colors
- [ ] No visual regressions (colors should be similar to light mode)

---

## Phase 5: Update db/IWA-14150 - Convert TSX Inline Styles

### Overview
Update TSX files that use semantic CSS variables in inline styles to use `useColors()` or static values.

### Files to Update

Scan for files using semantic variables in TSX:
```bash
grep -r "var(--bg-\|var(--text-\|var(--border-\|var(--status-" frontend/src/hwqa/**/*.tsx
```

Common patterns to convert:

**Pattern 1: Inline style with semantic variable**
```tsx
// BEFORE:
style={{ backgroundColor: 'var(--bg-surface-alt)' }}

// AFTER:
const colors = useColors();
// ...
style={{ backgroundColor: colors.neutral98 }}
```

**Pattern 2: Mantine component prop**
```tsx
// BEFORE:
<Text c="var(--text-secondary)">

// AFTER:
<Text c="neutral40">
```

### Success Criteria

#### Automated Verification:
- [x] No semantic CSS variables in HWQA TSX files:
  ```bash
  find frontend/src/hwqa -name "*.tsx" -exec grep -l "var(--bg-\|var(--text-\|var(--border-\|var(--status-\|var(--nav-\|var(--interactive-\|var(--brand-" {} \; || echo "No semantic variables in TSX files"
  ```
- [x] TypeScript compiles without errors in HWQA:
  ```bash
  cd frontend && npx tsc --noEmit 2>&1 | grep -E "src/hwqa/" || echo "No HWQA TypeScript errors"
  ```

#### Manual Verification:
- [ ] All components render correctly
- [ ] Colors match expected light mode appearance

---

## Phase 6: Move Dark Mode Code to IWA-14170

### Overview
Cherry-pick or copy the dark mode infrastructure to IWA-14170.

### Changes Required

#### 1. Copy Files to IWA-14170
From `db/IWA-14150` (before Phase 2 deletions), copy to IWA-14170:
- `frontend/src/hwqa/styles/cssVariablesResolver.ts`
- `frontend/src/hwqa/styles/agGridTheme.css`
- `frontend/src/hwqa/components/HwqaThemeWrapper.tsx`
- `frontend/src/hwqa/context/HwqaThemeContext.tsx`
- `frontend/src/hwqa/components/common/ThemeToggle/ThemeToggle.tsx`
- `frontend/src/hwqa/components/common/ThemeToggle/index.ts`

#### 2. Update Context Index on IWA-14170
**File**: `frontend/src/hwqa/context/index.ts`

Add the HwqaThemeContext export.

#### 3. Update HwqaPage on IWA-14170
Ensure `HwqaPage.tsx` uses `HwqaThemeWrapper`.

### Success Criteria

#### Automated Verification:
- [x] All dark mode files exist in IWA-14170:
  ```bash
  git checkout IWA-14170 && \
  ls frontend/src/hwqa/styles/cssVariablesResolver.ts \
     frontend/src/hwqa/styles/agGridTheme.css \
     frontend/src/hwqa/components/HwqaThemeWrapper.tsx \
     frontend/src/hwqa/context/HwqaThemeContext.tsx \
     frontend/src/hwqa/components/common/ThemeToggle/ThemeToggle.tsx \
     frontend/src/hwqa/components/common/ThemeToggle/index.ts && echo "All dark mode files present"
  ```
- [ ] TypeScript compiles on IWA-14170 (HWQA files):
  ```bash
  cd frontend && npx tsc --noEmit 2>&1 | grep -E "src/hwqa/" || echo "No HWQA TypeScript errors"
  ```
- [ ] HwqaPage uses HwqaThemeWrapper:
  ```bash
  grep -c "HwqaThemeWrapper" frontend/src/pages/HwqaPage.tsx && echo "HwqaThemeWrapper is used"
  ```

#### Manual Verification:
- [ ] Dark mode toggle works in IWA-14170
- [ ] Theme switching functions correctly

---

## Testing Strategy

### Unit Tests
- Existing component tests should pass after color updates
- No new tests required for color changes

### Integration Tests
- HWQA routing works correctly
- All pages load without errors

### Manual Testing Steps
1. Navigate to `/hwqa` route
2. Verify SideNav displays correctly with proper colors
3. Test all sub-pages (Dashboard, Tests, Shipments, Glossary, Conversion)
4. Verify forms and modals have correct styling
5. Check AG-Grid tables render properly

## Execution Order

1. **Phase 6 FIRST** - Copy dark mode files to IWA-14170 (preserve them before deletion)
2. Phase 1 - Update IWA-14149
3. Phase 2 - Delete dark mode infrastructure from db/IWA-14150
4. Phase 3 - Convert HwqaSideNav
5. Phase 4 - Convert CSS modules
6. Phase 5 - Convert TSX inline styles

## References

- Standard SideNav pattern: `frontend/src/components/CustomerDetailPage/SideNav.tsx`
- Color hook: `frontend/src/hooks/useColors.ts`
- Base theme: `frontend/src/styles/assetWatchTheme.ts`
- Color palette: `frontend/src/styles/colorPalette.ts`
