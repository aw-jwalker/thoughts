---
date: 2025-12-02T00:00:00-05:00
researcher: Claude
git_commit: d6615c9a64695ec087575d2f404c54cfdfa47181
branch: db/IWA-14069
repository: fullstack.assetwatch-hwqa-migration
topic: "HWQA Styling and Navigation Integration Analysis"
tags: [research, codebase, hwqa, styling, navigation, refactoring]
status: complete
last_updated: 2025-12-02
last_updated_by: Claude
---

# Research: HWQA Styling and Navigation Integration Analysis

**Date**: 2025-12-02
**Researcher**: Claude
**Git Commit**: d6615c9a64695ec087575d2f404c54cfdfa47181
**Branch**: db/IWA-14069
**Repository**: fullstack.assetwatch-hwqa-migration

## Research Question

Analyze the HWQA code that was ported from another repo to understand:
1. Why the main AssetWatch navbar/header colors are wrong after HWQA integration
2. Why the main app left navbar disappears when navigating to /hwqa
3. How HWQA styles and components compare to existing AssetWatch patterns (e.g., CustomerDetail/Summary)
4. What needs to change for HWQA to blend seamlessly with the AssetWatch app

## Summary

The HWQA code creates a **completely isolated application within the AssetWatch app**, with its own:
- MantineProvider and theme system
- MemoryRouter for internal navigation
- AppLayout with its own navbar
- Global CSS that overrides main app styles

The primary issues are:
1. **HWQA's AppLayout.css sets global `:root` and `body` styles** that leak into the main app
2. **HWQA's CSS targets `.mantine-AppShell-*` classes with `!important`** which overrides the main app's header/navbar styling
3. **HWQA renders its own AppLayout inside the main AppLayout** creating a "nested layout" situation where the main app navbar is hidden by HWQA's own layout
4. **HWQA re-imports Mantine CSS** potentially causing style loading order conflicts

## Detailed Findings

### 1. HWQA Code Structure

**Location**: `frontend/src/hwqa/` (130+ files)

**Key Files**:
- `HwqaApp.tsx:1-113` - Main entry point with MemoryRouter and nested MantineProvider
- `components/layout/AppLayout/AppLayout.tsx:1-22` - HWQA's own layout component
- `components/layout/AppLayout/AppLayout.css:1-66` - **ROOT CAUSE** of styling conflicts
- `components/layout/AppNavbar/AppNavbar.tsx:1-142` - HWQA's sidebar navigation
- `styles/themes/mantineTheme.ts:1-191` - Separate Mantine theme
- `styles/themes/cssVariablesResolver.ts:1-230` - CSS variables for light/dark mode

**Integration Point**:
- `pages/HwqaPage.tsx:1-13` - Simple wrapper that renders `<HwqaApp />`
- `TanStackRoutes.tsx:353-357` - Route defined as `/hwqa` pointing to HwqaPage

### 2. Root Causes of Styling Issues

#### Issue A: Global CSS Overrides in AppLayout.css

**File**: `frontend/src/hwqa/components/layout/AppLayout/AppLayout.css`

```css
/* Lines 12-18: Sets GLOBAL :root variables */
:root {
  --app-navbar-width: 230px;
  --app-navbar-collapsed-width: 60px;
  --app-header-height: 60px;
  --app-content-max-width: 1200px;
  --app-content-padding: var(--mantine-spacing-md);
}

/* Lines 20-26: Sets GLOBAL body styles */
body {
  margin: 0;
  padding: 0;
  background-color: var(--bg-body);  /* This variable doesn't exist in main app! */
  font-family: var(--mantine-font-family);
  color: var(--text-primary);  /* This variable doesn't exist in main app! */
}

/* Lines 29-43: Targets ALL .mantine-AppShell components with !important */
.mantine-AppShell-main {
  background-color: var(--bg-body);
}

.mantine-AppShell-header {
  background-color: var(--bg-header) !important;  /* OVERRIDES main app header! */
  border-bottom: none;
}

.mantine-AppShell-navbar {
  background-color: var(--bg-navbar) !important;  /* OVERRIDES main app navbar! */
  border-right: 1px solid var(--border-navbar);
}
```

**Impact**: These CSS rules apply globally because:
- They target generic Mantine class names (not scoped to HWQA)
- They use `!important` which overrides the main app's inline styles
- The main app header uses `bg="black"` but HWQA's CSS sets it to `var(--bg-header)`

#### Issue B: Nested Layout Architecture

**Current Flow**:
1. Main app `AppLayout.tsx` renders with header/navbar/main
2. Route `/hwqa` renders `HwqaPage` inside main `AppLayout.Main`
3. `HwqaPage` renders `HwqaApp`
4. `HwqaApp` renders its OWN `AppLayout` with its OWN navbar

**Result**: HWQA's AppLayout creates a full-page layout that fills the main area, essentially hiding/replacing the visual structure.

#### Issue C: CSS Variable Mismatch

**HWQA CSS Variables** (from `cssVariablesResolver.ts`):
- `--bg-header` - resolves to `theme.colors.neutral[0]` (black)
- `--bg-body` - resolves to `theme.colors.neutral[9]`
- `--text-primary` - resolves to `theme.colors.neutral[0]`
- `--bg-navbar` - resolves to `#FFFFFF`

**Main App CSS Variables** (from `colorVariables.css`):
- Uses `--mantine-color-primary70`, `--mantine-color-neutral20`, etc.
- Does NOT define `--bg-*` or `--text-*` semantic variables

When HWQA's CSS file loads, it references variables that only exist when HWQA's MantineProvider with `cssVariablesResolver` is active. Outside HWQA, these resolve to nothing or default values.

#### Issue D: Multiple Mantine CSS Imports

**HwqaApp.tsx lines 22-24**:
```tsx
import "@mantine/core/styles.css";
import "@mantine/dates/styles.css";
import "@mantine/notifications/styles.css";
```

**Main App** also imports these (via global styles). Double-importing may cause CSS cascade issues.

### 3. AssetWatch Reference Implementation (CustomerDetail/Summary)

**Main Page**: `pages/CustomerDetail.tsx`

**Key Patterns**:
- Uses main app's `AppLayout` (no separate layout)
- Has its own `SideNav` component for tab navigation (`components/CustomerDetailPage/SideNav.tsx`)
- SideNav is a child component within the page, NOT a replacement for main navbar
- Uses margin/padding to accommodate SideNav width
- Tabs and content share the same main content area

**SideNav Integration** (CustomerDetail.tsx lines 430-458):
```tsx
<SideNav isOpen={isSideNavOpen} toggle={toggle} />
<Tabs
  style={{
    marginLeft: isSmallScreen ? 0 : isSideNavOpen ? SIDE_NAV_WIDTH_OPEN : SIDE_NAV_WIDTH_CLOSED,
  }}
>
  {/* Tab content */}
</Tabs>
```

**Constants** (utils/constants.ts):
- `SIDE_NAV_WIDTH_OPEN`: 230px
- `SIDE_NAV_WIDTH_CLOSED`: 20px
- `APP_NAVBAR_WIDTH`: 80px (main app navbar)

**This is the pattern HWQA should follow**:
- Remove separate AppLayout
- Create SideNav component similar to CustomerDetail
- Use margin/offset for content area
- Work within main app's layout instead of replacing it

### 4. Navigation Architecture Comparison

| Aspect | Main App | CustomerDetail | HWQA (Current) |
|--------|----------|----------------|----------------|
| Layout | AppLayout.tsx | AppLayout.tsx + SideNav | Own AppLayout (nested) |
| Router | TanStack Router | TanStack Router | MemoryRouter (isolated) |
| Navbar | AppNavbar.tsx (icons) | SideNav.tsx (collapsible) | AppNavbar.tsx (full sidebar) |
| Header | AppHeader.tsx (black bg) | Same (inherited) | None (height: 0) |
| Theme | assetWatchTheme | Same (inherited) | Separate mantineTheme |
| CSS | Module-scoped | Module-scoped | Global with !important |

### 5. File Inventory

#### HWQA Components That Need Refactoring

**Layout (Remove/Replace)**:
- `hwqa/components/layout/AppLayout/AppLayout.tsx`
- `hwqa/components/layout/AppLayout/AppLayout.css`
- `hwqa/components/layout/AppHeader/AppHeader.tsx`
- `hwqa/components/layout/AppHeader/AppHeader.module.css`

**Navigation (Convert to SideNav pattern)**:
- `hwqa/components/layout/AppNavbar/AppNavbar.tsx`
- `hwqa/components/layout/AppNavbar/AppNavbar.module.css`

**Theme System (Remove/Align)**:
- `hwqa/context/ThemeContext.tsx` - Dark mode toggle not used in main app
- `hwqa/styles/themes/mantineTheme.ts` - Separate theme
- `hwqa/styles/themes/cssVariablesResolver.ts` - Custom variables

**Can Keep (Component logic)**:
- `hwqa/pages/*.tsx` - Page components
- `hwqa/components/features/*` - Feature components
- `hwqa/components/common/*` - May have equivalents in main app
- `hwqa/services/*` - API services
- `hwqa/hooks/*` - Custom hooks

#### Existing AssetWatch Equivalents

| HWQA Component | AssetWatch Equivalent |
|----------------|----------------------|
| AppLayout | `components/layout/AppLayout.tsx` |
| AppHeader | `components/layout/AppHeader.tsx` |
| AppNavbar | `components/CustomerDetailPage/SideNav.tsx` (pattern) |
| Button | `@mantine/core Button` |
| DataTable | `components/common/DataTable/` or AG Grid |
| Modal | `@mantine/core Modal` or `components/common/Modal/` |
| DateRangeFilter | Various date picker implementations |

### 6. Immediate Fixes for Styling Issues

**Fix 1: Scope HWQA CSS to prevent global leakage**

Current problem (`AppLayout.css`):
```css
body { ... }
.mantine-AppShell-header { ... !important }
```

Needs to be:
```css
.hwqa-root body { ... }
.hwqa-root .mantine-AppShell-header { ... }
```

Or better: Remove global CSS entirely and use CSS modules.

**Fix 2: Remove HWQA's own AppLayout from the route**

Current (`HwqaApp.tsx:59`):
```tsx
<Routes>
  <Route element={<AppLayout />}>
    <Route index element={<SensorDashboardPage />} />
```

Should be:
```tsx
<Routes>
  <Route index element={<SensorDashboardPage />} />
```

And have HWQA pages use a SideNav pattern like CustomerDetail.

**Fix 3: Remove duplicate Mantine CSS imports**

In `HwqaApp.tsx`, remove lines 22-24:
```tsx
// Remove these - already imported by main app
// import "@mantine/core/styles.css";
// import "@mantine/dates/styles.css";
// import "@mantine/notifications/styles.css";
```

**Fix 4: Use main app's MantineProvider**

Instead of creating a new MantineProvider in HwqaApp, inherit from main app or align themes.

## Architecture Documentation

### Current HWQA Integration (Problematic)

```
TanStackRoutes
└── MantineProvider (assetWatchTheme)
    └── AppLayout (main)
        ├── AppHeader (bg="black")
        ├── AppNavbar (main navbar)
        └── AppShell.Main
            └── Outlet
                └── HwqaPage (/hwqa route)
                    └── HwqaApp
                        └── MantineProvider (hwqa theme) ← NESTED PROVIDER
                            └── MemoryRouter
                                └── AppLayout (hwqa) ← NESTED LAYOUT
                                    └── AppNavbar (hwqa sidebar)
                                    └── Outlet (hwqa pages)
```

### Recommended Architecture

```
TanStackRoutes
└── MantineProvider (assetWatchTheme)
    └── AppLayout (main)
        ├── AppHeader (bg="black")
        ├── AppNavbar (main navbar)
        └── AppShell.Main
            └── Outlet
                └── HwqaPage (/hwqa route)
                    ├── HwqaSideNav (like CustomerDetail SideNav)
                    └── HwqaContent (with margin for SideNav)
                        └── HwqaTabContent (based on selected tab)
```

## Code References

**HWQA Entry Point**:
- `frontend/src/hwqa/HwqaApp.tsx:1-113`
- `frontend/src/pages/HwqaPage.tsx:1-13`

**HWQA Problematic CSS**:
- `frontend/src/hwqa/components/layout/AppLayout/AppLayout.css:12-43`

**Main App Layout**:
- `frontend/src/components/layout/AppLayout.tsx:22-80`
- `frontend/src/components/layout/AppHeader.tsx:59-225`
- `frontend/src/components/layout/AppNavbar.tsx:1-152`

**Reference Implementation (CustomerDetail)**:
- `frontend/src/pages/CustomerDetail.tsx:123-574`
- `frontend/src/components/CustomerDetailPage/SideNav.tsx`

**Theme Systems**:
- `frontend/src/styles/assetWatchTheme.ts` (main app)
- `frontend/src/hwqa/styles/themes/mantineTheme.ts` (hwqa)
- `frontend/src/hwqa/styles/themes/cssVariablesResolver.ts`

## Refactoring Strategy Overview

### Phase 1: Fix Immediate Styling Issues
1. Scope or remove global CSS from HWQA
2. Remove `!important` declarations
3. Remove duplicate Mantine CSS imports

### Phase 2: Integrate with Main Layout
1. Remove HWQA's AppLayout wrapper
2. Create HwqaSideNav following CustomerDetail pattern
3. Remove HWQA's MantineProvider (inherit from main)

### Phase 3: Align Navigation
1. Convert MemoryRouter routes to proper TanStack routes
2. Add HWQA to main navbar if needed
3. Use URL-based navigation instead of memory routing

### Phase 4: Component Standardization
1. Replace HWQA common components with main app equivalents
2. Align styling with main app patterns
3. Remove redundant utility files

## Open Questions

1. Should HWQA have a link in the main app left navbar, or be accessed via direct URL only?
2. Does HWQA need dark mode support? (Main app doesn't have it)
3. Are there HWQA-specific permissions/roles that need to be integrated?
4. Should HWQA routes be visible in browser URL (currently hidden by MemoryRouter)?

## Related Research

None currently - this is the initial research document for HWQA integration.
