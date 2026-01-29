# HWQA Dark Mode Implementation Plan

## Overview

Implement a self-contained dark mode system for the HWQA section of AssetWatch. This serves as a proof-of-concept for how dark mode might work when eventually added to the entire application. The implementation is designed to:

1. **Harmonize** with existing AssetWatch styles and brand colors
2. **Be easily removable** when app-wide dark mode is implemented
3. **Scope only to HWQA** without affecting other parts of the application

## Current State Analysis

### Existing Infrastructure
- **41 component files** using Mantine components (488 total usages)
- **15 CSS module files** requiring dark mode updates
- **3 files** using `useColors` hook (HwqaSideNav, PassRateBarChart, PassRateLineChart)
- **9 AG-Grid components** needing theme configuration
- **No existing dark mode infrastructure** in AssetWatch

### Key Files
| File | Purpose |
|------|---------|
| `frontend/src/pages/HwqaPage.tsx` | HWQA entry point - theme provider insertion point |
| `frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.tsx` | Navigation - toggle location |
| `frontend/src/styles/colorPalette.ts` | AssetWatch brand colors from Figma |
| `frontend/src/styles/assetWatchTheme.ts` | Current theme configuration |

### Key Discoveries
- Some CSS modules already use `light-dark()` function (`LogTestForm.module.css:16-17`)
- Several CSS modules reference semantic variables (`--bg-surface`, `--status-success`) that don't exist yet
- HWQA has clear architectural isolation at `HwqaPage.tsx`
- The standalone HWQA repo has a complete dark mode implementation we can adapt

### Existing Color Infrastructure

**Pattern in `colorVariables.css`**: The codebase uses `--mantine-color-{family}{shade}` format derived from the Figma brand palette:
```css
--mantine-color-primary60: var(--mantine-color-primary60-0);  /* #00A388 */
--mantine-color-neutral95: var(--mantine-color-neutral95-0);  /* #F0F0F4 */
```

### Semantic Variables: Establishing a New Convention

**Important**: The semantic variable pattern (`--bg-*`, `--text-*`, `--status-*`, `--border-*`) is **NOT an existing app-wide standard**. It is being **pioneered by HWQA files** that reference these variables without them being defined anywhere. The variables currently resolve to nothing (transparent/default).

**Semantic Variables Already In Use (but NOT defined)**:

| File | Variables Used |
|------|---------------|
| `ShipmentsPage.module.css` | `--bg-input`, `--text-primary`, `--border-input`, `--bg-surface-alt`, `--text-secondary`, `--border-subtle`, `--bg-surface` |
| `DateRangeFilter.module.css` | `--status-error`, `--status-success`, `--status-success-bg`, `--interactive-active`, `--text-on-primary` |
| `PrimaryIssues.module.css` | `--status-warning` |
| `PrimaryIssues.tsx` | `--status-warning` |
| `PhaseMetricsGrid.tsx` | `--border-default` |
| `SequentialConfirmationModal.tsx` | `--bg-elevated`, `--border-default`, `--status-success`, `--bg-surface-alt` |

**Note**: The Bearing Analysis Tool (`CMESandbox/bearingAnalysisScichart/`) uses a different, component-scoped variable pattern (e.g., `--text-color-bearing-css`, `--border-radius-bearing-css-fnck`) that is isolated to that feature and unrelated to our semantic token system.

### Our Approach

We are **establishing** the semantic token convention for HWQA (and potentially the future app-wide standard):

1. **Define semantic variables** via `cssVariablesResolver` that map to existing `--mantine-color-*` variables
2. **No hardcoded hex values** - all mappings reference the Figma brand palette
3. **Light/dark mode support** - same semantic names, different color mappings per scheme
4. **Future-proof** - when app-wide dark mode is added, this pattern can be adopted globally

## Desired End State

After implementation:
1. Users can toggle between light and dark mode within the HWQA section
2. Toggle is located at the bottom of HwqaSideNav
3. Preference persists in localStorage
4. All HWQA components, including AG-Grid tables, respect the theme
5. Colors align with AssetWatch brand palette
6. Implementation is isolated and can be easily removed

### Verification
- Toggle switches theme immediately without page reload
- Theme persists across page refreshes
- AG-Grid tables display correctly in both modes
- Charts and data visualizations are readable in both modes
- No visual regressions in light mode

## What We're NOT Doing

- Changing the main AssetWatch theme system
- Adding dark mode to non-HWQA parts of the application
- Modifying the root MantineProvider configuration
- Creating new color palettes (using existing AssetWatch brand colors)
- Adding system preference detection (explicit toggle only)

## Implementation Approach

We'll create a nested MantineProvider at the HWQA level with a custom `cssVariablesResolver` that maps semantic tokens to different color values based on the color scheme. This approach:

1. Uses Mantine's built-in color scheme support
2. Leverages CSS variables for automatic theme switching
3. Minimizes changes to existing components
4. Can be removed by simply deleting the wrapper

---

## Phase 1: Theme Infrastructure

### Overview
Create the core theme infrastructure: context, provider, and CSS variables resolver.

### Changes Required:

#### 1. Create HWQA Theme Context
**File**: `frontend/src/hwqa/context/HwqaThemeContext.tsx` (new file)

```typescript
import { createContext, useContext, useState, useEffect, ReactNode } from "react";

type ColorScheme = "light" | "dark";

interface HwqaThemeContextValue {
  colorScheme: ColorScheme;
  setColorScheme: (scheme: ColorScheme) => void;
  toggleColorScheme: () => void;
}

const STORAGE_KEY = "hwqa-color-scheme";

function getInitialColorScheme(): ColorScheme {
  if (typeof window === "undefined") return "light";
  const stored = localStorage.getItem(STORAGE_KEY);
  if (stored === "light" || stored === "dark") return stored;
  return "light";
}

const HwqaThemeContext = createContext<HwqaThemeContextValue | null>(null);

export function HwqaThemeProvider({ children }: { children: ReactNode }) {
  const [colorScheme, setColorScheme] = useState<ColorScheme>(getInitialColorScheme);

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, colorScheme);
  }, [colorScheme]);

  const toggleColorScheme = () => {
    setColorScheme((prev) => (prev === "light" ? "dark" : "light"));
  };

  return (
    <HwqaThemeContext.Provider value={{ colorScheme, setColorScheme, toggleColorScheme }}>
      {children}
    </HwqaThemeContext.Provider>
  );
}

export function useHwqaTheme(): HwqaThemeContextValue {
  const context = useContext(HwqaThemeContext);
  if (!context) {
    throw new Error("useHwqaTheme must be used within HwqaThemeProvider");
  }
  return context;
}
```

#### 2. Create CSS Variables Resolver
**File**: `frontend/src/hwqa/styles/cssVariablesResolver.ts` (new file)

This resolver maps semantic tokens to AssetWatch brand colors for both light and dark modes.

**Design Principles:**
- **No hardcoded hex values** - all colors reference `var(--mantine-color-*)` which maps to the Figma brand palette
- **Semantic naming** - variables describe purpose, not color (e.g., `--bg-surface` not `--bg-white`)
- **Tonal scale mapping** - uses Material Design 3 tonal scale (0=darkest, 100=lightest)
- **Consistent contrast** - light mode uses dark text (10-40) on light backgrounds (95-100); dark mode inverts this

```typescript
import { CSSVariablesResolver } from "@mantine/core";

/**
 * CSS Variables Resolver for HWQA Dark Mode
 *
 * IMPORTANT: No hardcoded hex values! All colors reference the Figma brand palette
 * via --mantine-color-* variables defined in colorVariables.css
 *
 * Tonal Scale Reference (from colorPalette.ts):
 * - 0-30: Very dark (dark mode backgrounds, light mode text)
 * - 40-60: Mid-tones (interactive states, borders)
 * - 70-90: Light (light mode backgrounds, dark mode text)
 * - 95-100: Very light (light mode surfaces)
 *
 * Brand Colors:
 * - primary: #00A388 (60) - Success, primary actions
 * - secondary: #009FB1 (60) - Info, secondary actions
 * - critical: #F26249 (60) - Errors, destructive actions
 * - warning: #AA8F00 (60) - Warnings, cautions
 * - neutral: Grayscale for text, backgrounds, borders
 */
export const hwqaCssVariablesResolver: CSSVariablesResolver = (theme) => ({
  variables: {
    // Static values (same in both modes) - shadows don't change with theme
    "--shadow-sm": "0px 4px 4px 0px rgba(0, 0, 0, 0.10)",
    "--shadow-md": "0px 8px 16px 0px rgba(0, 0, 0, 0.15)",
    "--shadow-lg": "0px 16px 32px 0px rgba(0, 0, 0, 0.20)",
  },
  light: {
    // Backgrounds
    "--bg-body": "var(--mantine-color-neutral99)",
    "--bg-surface": "var(--mantine-color-neutral100)",
    "--bg-surface-alt": "var(--mantine-color-neutral98)",
    "--bg-elevated": "var(--mantine-color-neutral100)",
    "--bg-input": "var(--mantine-color-neutral100)",
    "--bg-header": "var(--mantine-color-neutral100)",
    "--bg-navbar": "var(--mantine-color-neutral100)",
    "--bg-hover": "var(--mantine-color-neutral95)",
    "--bg-active": "var(--mantine-color-neutral90)",

    // Text
    "--text-primary": "var(--mantine-color-neutral10)",
    "--text-secondary": "var(--mantine-color-neutral40)",
    "--text-tertiary": "var(--mantine-color-neutral60)",
    "--text-inverse": "var(--mantine-color-neutral100)",
    "--text-link": "var(--mantine-color-primary60)",
    "--text-on-primary": "var(--mantine-color-neutral100)",

    // Borders
    "--border-default": "var(--mantine-color-neutral90)",
    "--border-subtle": "var(--mantine-color-neutral95)",
    "--border-strong": "var(--mantine-color-neutral70)",
    "--border-input": "var(--mantine-color-neutral80)",
    "--border-focus": "var(--mantine-color-primary60)",

    // Status colors
    "--status-success": "var(--mantine-color-primary60)",
    "--status-success-bg": "var(--mantine-color-primary95)",
    "--status-success-border": "var(--mantine-color-primary80)",
    "--status-warning": "var(--mantine-color-warning60)",
    "--status-warning-bg": "var(--mantine-color-warning95)",
    "--status-warning-border": "var(--mantine-color-warning80)",
    "--status-error": "var(--mantine-color-critical60)",
    "--status-error-bg": "var(--mantine-color-critical95)",
    "--status-error-border": "var(--mantine-color-critical80)",
    "--status-info": "var(--mantine-color-secondary60)",
    "--status-info-bg": "var(--mantine-color-secondary95)",
    "--status-info-border": "var(--mantine-color-secondary80)",

    // Interactive
    "--interactive-hover": "var(--mantine-color-neutral95)",
    "--interactive-active": "var(--mantine-color-neutral90)",
    "--interactive-selected": "var(--mantine-color-primary95)",
    "--interactive-disabled": "var(--mantine-color-neutral90)",

    // Navigation
    "--nav-text": "var(--mantine-color-neutral40)",
    "--nav-text-active": "var(--mantine-color-neutral100)",
    "--nav-bg-hover": "var(--mantine-color-neutral95)",
    "--nav-bg-active": "var(--mantine-color-primary60)",

    // Brand colors for direct use
    "--brand-primary": "var(--mantine-color-primary60)",
    "--brand-secondary": "var(--mantine-color-secondary60)",
  },
  dark: {
    // Backgrounds
    "--bg-body": "var(--mantine-color-neutral10)",
    "--bg-surface": "var(--mantine-color-neutral20)",
    "--bg-surface-alt": "var(--mantine-color-neutral30)",
    "--bg-elevated": "var(--mantine-color-neutral30)",
    "--bg-input": "var(--mantine-color-neutral20)",
    "--bg-header": "var(--mantine-color-neutral20)",
    "--bg-navbar": "var(--mantine-color-neutral20)",
    "--bg-hover": "var(--mantine-color-neutral30)",
    "--bg-active": "var(--mantine-color-neutral40)",

    // Text
    "--text-primary": "var(--mantine-color-neutral95)",
    "--text-secondary": "var(--mantine-color-neutral70)",
    "--text-tertiary": "var(--mantine-color-neutral60)",
    "--text-inverse": "var(--mantine-color-neutral10)",
    "--text-link": "var(--mantine-color-primary80)",
    "--text-on-primary": "var(--mantine-color-neutral10)",

    // Borders
    "--border-default": "var(--mantine-color-neutral40)",
    "--border-subtle": "var(--mantine-color-neutral30)",
    "--border-strong": "var(--mantine-color-neutral60)",
    "--border-input": "var(--mantine-color-neutral40)",
    "--border-focus": "var(--mantine-color-primary70)",

    // Status colors (brighter for dark mode)
    "--status-success": "var(--mantine-color-primary80)",
    "--status-success-bg": "var(--mantine-color-primary20)",
    "--status-success-border": "var(--mantine-color-primary40)",
    "--status-warning": "var(--mantine-color-warning80)",
    "--status-warning-bg": "var(--mantine-color-warning20)",
    "--status-warning-border": "var(--mantine-color-warning40)",
    "--status-error": "var(--mantine-color-critical80)",
    "--status-error-bg": "var(--mantine-color-critical20)",
    "--status-error-border": "var(--mantine-color-critical40)",
    "--status-info": "var(--mantine-color-secondary80)",
    "--status-info-bg": "var(--mantine-color-secondary20)",
    "--status-info-border": "var(--mantine-color-secondary40)",

    // Interactive
    "--interactive-hover": "var(--mantine-color-neutral30)",
    "--interactive-active": "var(--mantine-color-neutral40)",
    "--interactive-selected": "var(--mantine-color-primary30)",
    "--interactive-disabled": "var(--mantine-color-neutral30)",

    // Navigation
    "--nav-text": "var(--mantine-color-neutral70)",
    "--nav-text-active": "var(--mantine-color-neutral10)",
    "--nav-bg-hover": "var(--mantine-color-neutral30)",
    "--nav-bg-active": "var(--mantine-color-primary70)",

    // Brand colors for direct use (brighter in dark mode)
    "--brand-primary": "var(--mantine-color-primary80)",
    "--brand-secondary": "var(--mantine-color-secondary80)",
  },
});
```

#### 3. Create HWQA Theme Wrapper Component
**File**: `frontend/src/hwqa/components/HwqaThemeWrapper.tsx` (new file)

```typescript
import { MantineProvider } from "@mantine/core";
import { ReactNode } from "react";
import { HwqaThemeProvider, useHwqaTheme } from "../context/HwqaThemeContext";
import { hwqaCssVariablesResolver } from "../styles/cssVariablesResolver";
import { assetWatchTheme } from "@styles/assetWatchTheme";

function HwqaMantineProvider({ children }: { children: ReactNode }) {
  const { colorScheme } = useHwqaTheme();

  return (
    <MantineProvider
      theme={assetWatchTheme}
      cssVariablesResolver={hwqaCssVariablesResolver}
      forceColorScheme={colorScheme}
    >
      {children}
    </MantineProvider>
  );
}

export function HwqaThemeWrapper({ children }: { children: ReactNode }) {
  return (
    <HwqaThemeProvider>
      <HwqaMantineProvider>
        {children}
      </HwqaMantineProvider>
    </HwqaThemeProvider>
  );
}
```

#### 4. Update HwqaPage to Use Theme Wrapper
**File**: `frontend/src/pages/HwqaPage.tsx`
**Changes**: Wrap content with HwqaThemeWrapper

```typescript
// Add import
import { HwqaThemeWrapper } from "@hwqa/components/HwqaThemeWrapper";

// Update HwqaPage function
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
```

#### 5. Export Context from Index
**File**: `frontend/src/hwqa/context/index.ts`
**Changes**: Add export for HwqaThemeContext

```typescript
export * from "./HwqaThemeContext";
```

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles without errors: `npm run typecheck`
- [ ] Linting passes: `npm run lint`
- [ ] Build succeeds: `npm run build`
- [ ] Existing tests pass: `cd frontend && npm test`

#### Manual Verification:
- [ ] HWQA section loads without errors
- [ ] No visual regressions in light mode
- [ ] Theme context is accessible in HWQA components
- [ ] localStorage stores theme preference

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation that HWQA loads correctly.

---

## Phase 2: Theme Toggle UI

### Overview
Add the dark mode toggle to the bottom of HwqaSideNav.

### Changes Required:

#### 1. Create Theme Toggle Component
**File**: `frontend/src/hwqa/components/common/ThemeToggle/ThemeToggle.tsx` (new file)

```typescript
import { ActionIcon, Group, Text, Tooltip, useMantineColorScheme } from "@mantine/core";
import { IconSun, IconMoon } from "@tabler/icons-react";
import { useHwqaTheme } from "@hwqa/context/HwqaThemeContext";

interface ThemeToggleProps {
  collapsed?: boolean;
}

export function ThemeToggle({ collapsed = false }: ThemeToggleProps) {
  const { colorScheme, toggleColorScheme } = useHwqaTheme();
  const isDark = colorScheme === "dark";

  const toggle = (
    <ActionIcon
      variant="subtle"
      size="lg"
      onClick={toggleColorScheme}
      aria-label={isDark ? "Switch to light mode" : "Switch to dark mode"}
      style={{
        color: "var(--nav-text)",
      }}
    >
      {isDark ? <IconSun size={20} /> : <IconMoon size={20} />}
    </ActionIcon>
  );

  if (collapsed) {
    return (
      <Tooltip label={isDark ? "Light mode" : "Dark mode"} position="right">
        {toggle}
      </Tooltip>
    );
  }

  return (
    <Group gap="sm" px="md" py="xs">
      {toggle}
      <Text size="sm" c="var(--nav-text)">
        {isDark ? "Light mode" : "Dark mode"}
      </Text>
    </Group>
  );
}
```

#### 2. Create Index Export
**File**: `frontend/src/hwqa/components/common/ThemeToggle/index.ts` (new file)

```typescript
export { ThemeToggle } from "./ThemeToggle";
```

#### 3. Update HwqaSideNav
**File**: `frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.tsx`
**Changes**: Add ThemeToggle at the bottom of the navigation

Add import:
```typescript
import { ThemeToggle } from "@hwqa/components/common/ThemeToggle";
```

Add ThemeToggle at the bottom of the sidebar content, before the closing `</Box>` of the main container (around line 225):

```typescript
{/* Theme Toggle at bottom */}
<Box
  style={{
    marginTop: "auto",
    borderTop: "1px solid var(--border-subtle)",
    paddingTop: 8,
    paddingBottom: 8,
  }}
>
  <ThemeToggle collapsed={!isOpen} />
</Box>
```

Also update the main container Box to use flexbox for proper spacing:
```typescript
<Box
  // ... existing props
  style={{
    // ... existing styles
    display: "flex",
    flexDirection: "column",
  }}
>
```

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles without errors: `npm run typecheck`
- [ ] Linting passes: `npm run lint`
- [ ] Build succeeds: `npm run build`

#### Manual Verification:
- [ ] Toggle appears at bottom of HwqaSideNav
- [ ] Toggle shows correct icon (sun/moon) based on current theme
- [ ] Clicking toggle switches theme immediately
- [ ] Toggle label shows when sidebar is expanded
- [ ] Tooltip shows when sidebar is collapsed
- [ ] Theme preference persists after page refresh

**Implementation Note**: After completing this phase, pause for manual testing of the toggle functionality.

---

## Phase 3: Update HwqaSideNav Styling

### Overview
Update HwqaSideNav to use semantic CSS variables for proper dark mode support.

### Changes Required:

#### 1. Update HwqaSideNav Styles
**File**: `frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.tsx`

Replace hardcoded colors with CSS variables:

**Line ~152** (container background):
```typescript
// Before
backgroundColor: isOpen ? "white" : "transparent"
// After
backgroundColor: isOpen ? "var(--bg-navbar)" : "transparent"
```

**Line ~169** (toggle button border):
```typescript
// Before
border: `1px solid ${colors.neutral60}`
// After
border: "1px solid var(--border-default)"
```

**Line ~214-215** (nav item active state):
```typescript
// Before
color: isActive ? "white" : colors.primary40
backgroundColor: isActive ? colors.primary40 : ""
// After
color: isActive ? "var(--nav-text-active)" : "var(--nav-text)"
backgroundColor: isActive ? "var(--nav-bg-active)" : ""
```

**Box shadow** (active item):
```typescript
// Before
boxShadow: isActive ? "0 2px 4px rgba(0,0,0,0.2)" : "none"
// After
boxShadow: isActive ? "var(--shadow-sm)" : "none"
```

#### 2. Remove useColors Import (if no longer needed)
If `useColors` is no longer used after these changes, remove the import and hook call.

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles without errors: `npm run typecheck`
- [ ] Linting passes: `npm run lint`

#### Manual Verification:
- [ ] SideNav looks correct in light mode
- [ ] SideNav looks correct in dark mode
- [ ] Active navigation item is clearly visible in both modes
- [ ] Toggle button is visible in both modes
- [ ] Hover states work correctly

**Implementation Note**: After completing this phase, test the sidebar in both themes.

---

## Phase 4: Update HwqaContent Layout

### Overview
Update the main HWQA content area to use semantic CSS variables.

### Changes Required:

#### 1. Update HwqaContent Background
**File**: `frontend/src/pages/HwqaPage.tsx`

In the HwqaContent component, update the Box background:

```typescript
// Before
bg="neutral95"
// After
bg="var(--bg-body)"
```

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles without errors: `npm run typecheck`

#### Manual Verification:
- [ ] Main content area has correct background in light mode
- [ ] Main content area has correct background in dark mode
- [ ] Contrast is appropriate for readability

---

## Phase 5: Update CSS Modules - Core Components

### Overview
Update CSS modules to use semantic variables for dark mode support. Focus on high-impact files first.

### Changes Required:

#### 1. ShipmentsPage.module.css
**File**: `frontend/src/hwqa/pages/ShipmentsPage.module.css`

These variables are already referenced but need to be defined. With our cssVariablesResolver, they will now work:
- `--bg-input`, `--text-primary`, `--border-input` (lines 8-13)
- `--bg-surface-alt`, `--text-secondary`, `--border-subtle` (lines 19-23)
- `--bg-surface` (line 50)

No changes needed - the variables are now defined by our resolver.

#### 2. DateRangeFilter.module.css
**File**: `frontend/src/hwqa/components/common/DateRangeFilter/DateRangeFilter.module.css`

These variables are already used:
- `--status-error` (line 23)
- `--status-success`, `--status-success-bg` (lines 36, 47, 48, 62)
- `--interactive-active` (line 52)
- `--text-on-primary` (line 63)

No changes needed - the variables are now defined by our resolver.

#### 3. LogTestForm.module.css
**File**: `frontend/src/hwqa/components/features/tests/LogTestForm.module.css`

This file already uses `light-dark()` function. Update to use our semantic variables:

```css
/* Line 16-17 - Update the light-dark reference */
background-color: var(--bg-surface);

/* Lines using var(--mantine-color-dark-*) should use semantic variables */
/* Replace dark-4, dark-6, etc. with appropriate semantic variables */
```

#### 4. ExcelGrid.module.css
**File**: `frontend/src/hwqa/components/features/shipments/ExcelGrid.module.css`

This is the most complex CSS module. Update Mantine dark color references:

```css
/* Replace var(--mantine-color-dark-8) with var(--bg-surface) */
/* Replace var(--mantine-color-dark-6) with var(--bg-elevated) */
/* Replace var(--mantine-color-dark-4) with var(--border-default) */
/* Replace var(--mantine-color-white) with var(--text-primary) for text */
/* Replace var(--mantine-color-blue-7) with var(--border-focus) */
```

#### 5. PrimaryIssues.module.css
**File**: `frontend/src/hwqa/components/features/dashboard/RCCAReport/PrimaryIssues/PrimaryIssues.module.css`

Already uses `--status-warning`. No changes needed.

### Success Criteria:

#### Automated Verification:
- [ ] CSS syntax is valid (no build errors)
- [ ] Build succeeds: `npm run build`

#### Manual Verification:
- [ ] Shipments page displays correctly in both themes
- [ ] Date range filter displays correctly in both themes
- [ ] Test logging form displays correctly in both themes
- [ ] Excel grid displays correctly in both themes
- [ ] Dashboard components display correctly in both themes

**Implementation Note**: Test each page after updating its CSS module.

---

## Phase 6: AG-Grid Dark Mode

### Overview
Configure AG-Grid to support dark mode theming.

### Changes Required:

#### 1. Create AG-Grid Theme CSS
**File**: `frontend/src/hwqa/styles/agGridTheme.css` (new file)

```css
/* AG-Grid HWQA Dark Mode Theme */

/* Light mode (default) */
.hwqa-ag-grid {
  --ag-background-color: var(--bg-surface);
  --ag-header-background-color: var(--bg-surface-alt);
  --ag-odd-row-background-color: var(--bg-surface);
  --ag-row-hover-color: var(--bg-hover);
  --ag-selected-row-background-color: var(--interactive-selected);
  --ag-border-color: var(--border-default);
  --ag-header-foreground-color: var(--text-primary);
  --ag-foreground-color: var(--text-primary);
  --ag-secondary-foreground-color: var(--text-secondary);
  --ag-input-focus-border-color: var(--border-focus);
}

/* Selection colors */
.hwqa-ag-grid .ag-cell-range-selected:not(.ag-cell-focus) {
  background-color: var(--interactive-selected) !important;
}

.hwqa-ag-grid .ag-row-selected {
  background-color: var(--interactive-selected) !important;
}
```

#### 2. Import AG-Grid Theme CSS
**File**: `frontend/src/hwqa/components/HwqaThemeWrapper.tsx`

Add import at the top:
```typescript
import "../styles/agGridTheme.css";
```

#### 3. Update AG-Grid Components to Use Theme Class
For each AG-Grid component, add the `hwqa-ag-grid` class to the container:

**Files to update:**
- `frontend/src/hwqa/components/features/shipments/LogShipmentForm.tsx`
- `frontend/src/hwqa/components/features/shipments/ShipmentList.tsx`
- `frontend/src/hwqa/components/features/tests/TestList.tsx`
- `frontend/src/hwqa/components/features/conversion/SensorConversion/RouteBasedSensorList.tsx`
- `frontend/src/hwqa/components/features/dashboard/PassRateOverview/PassRateTable.tsx`

Example change:
```typescript
// Before
<div className="ag-theme-quartz" style={{ height: 400 }}>
  <AgGridReact ... />
</div>

// After
<div className="ag-theme-quartz hwqa-ag-grid" style={{ height: 400 }}>
  <AgGridReact ... />
</div>
```

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles without errors: `npm run typecheck`
- [ ] Build succeeds: `npm run build`

#### Manual Verification:
- [ ] AG-Grid tables display correctly in light mode
- [ ] AG-Grid tables display correctly in dark mode
- [ ] Row selection highlighting works in both modes
- [ ] Header styling is consistent with theme
- [ ] Scrollbars are visible in both modes

**Implementation Note**: Test each AG-Grid component in both themes.

---

## Phase 7: Charts and Data Visualization

### Overview
Ensure Mantine Charts and data visualizations work correctly in dark mode.

### Changes Required:

#### 1. Update Chart Components
**Files:**
- `frontend/src/hwqa/components/features/dashboard/PassRateOverview/charts/PassRateBarChart.tsx`
- `frontend/src/hwqa/components/features/dashboard/PassRateOverview/charts/PassRateLineChart.tsx`
- `frontend/src/hwqa/components/features/dashboard/PassRateOverview/charts/HorizontalLegend.tsx`
- `frontend/src/hwqa/components/features/dashboard/PassRateOverview/charts/ChartTooltip.tsx`

Charts using Mantine Charts should automatically inherit theme colors. Verify and update any hardcoded colors.

#### 2. Update HorizontalLegend Background
**File**: `frontend/src/hwqa/components/features/dashboard/PassRateOverview/charts/HorizontalLegend.tsx`

```typescript
// Before (line 15)
bg="neutral95"
// After
bg="var(--bg-surface-alt)"
```

#### 3. Update ChartTooltip
**File**: `frontend/src/hwqa/components/features/dashboard/PassRateOverview/charts/ChartTooltip.tsx`

Ensure Paper component uses semantic colors or inherits from theme.

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles without errors: `npm run typecheck`

#### Manual Verification:
- [ ] Bar charts display correctly in both themes
- [ ] Line charts display correctly in both themes
- [ ] Chart legends are readable in both themes
- [ ] Tooltips are visible and readable in both themes
- [ ] Data visualization colors maintain contrast in dark mode

---

## Phase 8: Remaining Component Updates

### Overview
Update remaining components that use hardcoded colors or need semantic variable updates.

### Changes Required:

#### 1. Update SpreadsheetExport Fallback Colors
**File**: `frontend/src/hwqa/components/features/dashboard/RCCAReport/SpreadsheetExport/SpreadsheetExport.tsx`

Lines 85-86 have hardcoded fallback colors. These are for HTML export where CSS variables don't work, so they can remain as-is. Add a comment explaining this:

```typescript
// Fallback colors for HTML export (CSS variables don't work in copied content)
const successColor = theme.colors.primary60?.[0] || '#00A388';
const errorColor = theme.colors.critical60?.[0] || '#F26249';
```

#### 2. Update Sequential Confirmation Modal
**File**: `frontend/src/hwqa/components/features/tests/sequential-confirmation/SequentialConfirmationModal.tsx`

Update bg props to use semantic variables:
```typescript
// Lines using bg="neutral.9" or similar
bg="var(--bg-surface)"
bg="var(--bg-elevated)"
bg="var(--bg-surface-alt)"
```

#### 3. Update Form Components
**Files:**
- `frontend/src/hwqa/components/features/shipments/CreateShipmentForm.tsx`
- `frontend/src/hwqa/components/features/shipments/PasteShipmentForm.tsx`
- `frontend/src/hwqa/components/features/tests/LogTestForm.tsx`

Review and update any inline styles or color props to use semantic variables.

#### 4. Update Badge and ThemeIcon Colors
**Files:**
- `frontend/src/hwqa/pages/GlossaryPage.tsx`
- `frontend/src/hwqa/components/features/dashboard/RCCAReport/QAGoals/QAGoals.tsx`
- `frontend/src/hwqa/components/features/dashboard/RCCAReport/PrimaryIssues/PrimaryIssues.tsx`

Review Badge and ThemeIcon color props. Mantine handles these automatically with color scheme, but verify contrast is acceptable.

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles without errors: `npm run typecheck`
- [ ] Linting passes: `npm run lint`
- [ ] Build succeeds: `npm run build`

#### Manual Verification:
- [ ] All modal dialogs display correctly in both themes
- [ ] All forms are usable in both themes
- [ ] Badge colors maintain readability in both themes
- [ ] No visual regressions across the application

---

## Phase 9: Final Polish and Testing

### Overview
Comprehensive testing and final adjustments.

### Changes Required:

#### 1. Create HWQA Styles Index
**File**: `frontend/src/hwqa/styles/index.ts` (new file)

```typescript
// Export all HWQA-specific styles
export { hwqaCssVariablesResolver } from "./cssVariablesResolver";
```

#### 2. Update Exports
**File**: `frontend/src/hwqa/components/common/index.ts`

Add export for ThemeToggle if not already done:
```typescript
export * from "./ThemeToggle";
```

#### 3. Document the Implementation
Add inline comments in key files explaining:
- How to remove HWQA dark mode when app-wide dark mode is added
- Where semantic variables are defined
- How to add new semantic variables

### Success Criteria:

#### Automated Verification:
- [ ] All TypeScript compiles without errors: `npm run typecheck`
- [ ] All linting passes: `npm run lint`
- [ ] Build succeeds: `npm run build`
- [ ] All existing tests pass: `cd frontend && npm test`

#### Manual Verification:
- [ ] Complete walkthrough of all HWQA pages in light mode
- [ ] Complete walkthrough of all HWQA pages in dark mode
- [ ] Theme toggle works from any HWQA page
- [ ] Theme preference persists across sessions
- [ ] No console errors or warnings
- [ ] Performance is acceptable (no noticeable lag on toggle)
- [ ] Accessibility: sufficient contrast ratios in both themes

---

## Testing Strategy

### Unit Tests:
- Test HwqaThemeContext: initial state, toggle, persistence
- Test ThemeToggle component: renders correctly, handles click

### Integration Tests:
- Test HwqaThemeWrapper: provides theme to children
- Test theme changes propagate to nested components

### Manual Testing Steps:
1. Navigate to HWQA section
2. Verify default theme is light
3. Click theme toggle
4. Verify all visible elements update to dark theme
5. Refresh page
6. Verify theme preference persisted
7. Navigate through all HWQA pages
8. Verify each page displays correctly in dark mode
9. Test AG-Grid interactions in dark mode
10. Test form submissions in dark mode
11. Toggle back to light mode
12. Verify no visual regressions

---

## Performance Considerations

- CSS variables are resolved at paint time, minimal performance impact
- Theme toggle is instant (no network requests)
- localStorage access is synchronous but fast
- No additional bundle size for color definitions (reusing existing palette)

---

## Migration Notes

### Removing HWQA Dark Mode (When App-Wide Dark Mode is Added)

1. Remove `HwqaThemeWrapper` from `HwqaPage.tsx`
2. Delete `frontend/src/hwqa/context/HwqaThemeContext.tsx`
3. Delete `frontend/src/hwqa/styles/cssVariablesResolver.ts`
4. Delete `frontend/src/hwqa/components/HwqaThemeWrapper.tsx`
5. Delete `frontend/src/hwqa/components/common/ThemeToggle/`
6. Remove ThemeToggle from `HwqaSideNav.tsx`
7. Keep CSS modules using semantic variables (they'll work with app-wide theme)
8. Move `agGridTheme.css` to app-level styles if needed

The semantic CSS variable names are designed to be compatible with a future app-wide implementation.

---

## References

- Research document: `thoughts/shared/research/2025-12-04-IWA-14069-hwqa-dark-mode-implementation.md`
- AssetWatch color palette: `frontend/src/styles/colorPalette.ts`
- Standalone HWQA dark mode: `~/repos/hwqa` branch `IWA-14034`
- Mantine theming docs: https://mantine.dev/theming/css-variables/
