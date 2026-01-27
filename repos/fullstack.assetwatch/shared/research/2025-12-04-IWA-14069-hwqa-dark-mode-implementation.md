---
date: 2025-12-04T00:16:12-05:00
researcher: aw-jwalker
git_commit: eca2718eb1dd201d93de61d6f135469fa5631410
branch: db/IWA-14069
repository: fullstack.assetwatch-hwqa-migration
topic: "HWQA Dark Mode Implementation Research"
tags: [research, codebase, hwqa, dark-mode, theming, mantine]
status: complete
last_updated: 2025-12-04
last_updated_by: aw-jwalker
---

# Research: HWQA Dark Mode Implementation

**Date**: 2025-12-04T00:16:12-05:00
**Researcher**: aw-jwalker
**Git Commit**: eca2718eb1dd201d93de61d6f135469fa5631410
**Branch**: db/IWA-14069
**Repository**: fullstack.assetwatch-hwqa-migration

## Research Question
Research the HWQA codebase (branch IWA-14034) for the implementation of the light/dark theme toggle, then look at the AssetWatch codebase for its light theme, then look specifically at the HWQA portion of the AssetWatch codebase for how we can implement the dark mode toggle specifically to that section of the app.

## Summary

This research documents three theme systems:

1. **HWQA Standalone Repo (IWA-14034)**: A fully-implemented light/dark mode system using Mantine's `cssVariablesResolver` with semantic tokens and virtual colors
2. **AssetWatch Main App**: Light mode only, using Figma design tokens transformed to Mantine color tuples
3. **HWQA Section in AssetWatch**: Inherits the main app's theme with no isolation, but has a clear architectural boundary for scoping a theme provider

The HWQA standalone implementation provides a complete template for bringing dark mode to the HWQA section of AssetWatch.

---

## Detailed Findings

### 1. HWQA Standalone Implementation (~/repos/hwqa branch IWA-14034)

The HWQA standalone application implements a comprehensive light/dark theme system.

#### Core Architecture Files

| File | Purpose |
|------|---------|
| `frontend/src/styles/themes/mantineTheme.ts` | Theme object with component overrides |
| `frontend/src/styles/themes/cssVariablesResolver.ts` | Light/dark CSS variable mappings |
| `frontend/src/styles/colors/palettes.ts` | Color palette definitions (10-shade tuples) |
| `frontend/src/context/ThemeContext.tsx` | React context for theme state |
| `frontend/src/App.tsx` | Provider setup and sync component |

#### CSS Variables Resolver Pattern

The resolver returns three sections:
- **variables**: Static values (shadows) same in both modes
- **light**: Light mode color mappings (100+ variables)
- **dark**: Dark mode color mappings (100+ variables)

**Semantic Variable Categories:**
- Backgrounds: `--bg-body`, `--bg-surface`, `--bg-elevated`, `--bg-input`, `--bg-header`, `--bg-navbar`
- Text: `--text-primary`, `--text-secondary`, `--text-tertiary`, `--text-inverse`, `--text-link`
- Borders: `--border-default`, `--border-subtle`, `--border-strong`, `--border-focus`
- Status: `--status-success`, `--status-warning`, `--status-error`, `--status-info` (with `-bg` and `-border` variants)
- Interactive: `--interactive-hover`, `--interactive-active`, `--interactive-selected`
- Navigation: `--nav-text`, `--nav-bg-hover`, `--nav-bg-active`

#### Color Palette Structure

Seven main color families with 10-shade tuples:
- **primary**: `#00A388` (light mode index 6), `#2DDBB9` (dark mode index 7 - brighter)
- **secondary**: `#009FB1` / `#50D8EC`
- **tertiary**: `#5964DB` / `#A1C9FF`
- **critical**: `#F26249` / `#FFB4A6`
- **warning**: `#AA8F00` / `#E9C400`
- **neutral**: Grayscale `#000000` to `#F0F0F4`
- **neutralVariant**: Alternative grayscale

Plus 12 data visualization palettes (`dv*`).

#### Theme Context Implementation

```typescript
// ThemeContext.tsx
const THEME_STORAGE_KEY = "hwqa-color-scheme";

function getInitialColorScheme(): ColorScheme {
  const stored = localStorage.getItem(THEME_STORAGE_KEY);
  if (stored === "light" || stored === "dark") return stored;
  return "light";
}

export function ThemeProvider({ children }) {
  const [colorScheme, setColorScheme] = useState(getInitialColorScheme);

  useEffect(() => {
    localStorage.setItem(THEME_STORAGE_KEY, colorScheme);
  }, [colorScheme]);

  const toggleColorScheme = () => {
    setColorScheme(prev => prev === "light" ? "dark" : "light");
  };

  return (
    <ThemeContext.Provider value={{ colorScheme, setColorScheme, toggleColorScheme }}>
      {children}
    </ThemeContext.Provider>
  );
}
```

#### MantineProvider Setup

```typescript
// App.tsx
<ThemeProvider>
  <AppContent />
</ThemeProvider>

function AppContent() {
  const { colorScheme } = useTheme();

  return (
    <>
      <ColorSchemeScript defaultColorScheme={colorScheme} />
      <MantineProvider
        theme={theme}
        cssVariablesResolver={cssVariablesResolver}
        defaultColorScheme={colorScheme}
      >
        <MantineColorSchemeSync />
        {/* App content */}
      </MantineProvider>
    </>
  );
}
```

#### Component Consumption Patterns

1. **Mantine Props**: `<Paper bg="var(--bg-surface)" c="var(--text-primary)">`
2. **Inline Styles**: `style={{ color: 'var(--text-primary)' }}`
3. **CSS Modules**: `.element { background-color: var(--bg-surface); }`

---

### 2. AssetWatch Main App Theme System

#### Core Files

| File | Purpose |
|------|---------|
| `frontend/src/styles/assetWatchTheme.ts` | Theme object creation |
| `frontend/src/styles/colorPalette.ts` | Figma design tokens |
| `frontend/src/styles/css/colorVariables.css` | CSS variable mappings |
| `frontend/src/TanStackRoutes.tsx:99` | MantineProvider wrapper |
| `frontend/src/hooks/useColors.ts` | Color access hook |

#### Theme Configuration

```typescript
// assetWatchTheme.ts
export const assetWatchTheme = createTheme({
  colors: mantineColorTuples,
  primaryColor: "primary60",
  shadows: { sm: "0px 4px 4px 0px rgba(0, 0, 0, 0.10)" },
  components: { /* Button, MultiSelect, etc. */ }
});
```

#### Color Palette Structure

Figma colors transformed to flat Mantine tuples:
- Input: `{ primary: { 60: "#00A388" } }`
- Output: `{ primary60: colorsTuple("#00A388") }` (10 identical values)

**Key Difference from HWQA Standalone**: Colors are single-value tuples, not 10-shade gradients.

#### Current State

- **No color scheme switching** - Locked to Mantine's default light mode
- **No `useMantineColorScheme`** - Not implemented
- **No `defaultColorScheme` prop** - Not set on MantineProvider
- **No `cssVariablesResolver`** - Not using semantic tokens

#### Color Access

```typescript
// useColors.ts
export function useColors(): Record<ColorKey, string> {
  const theme = useMantineTheme();
  return Object.fromEntries(
    Object.entries(theme.colors).map(([key, arr]) => [key, arr[0]])
  );
}
```

---

### 3. HWQA Section in AssetWatch

#### Structure

The HWQA section is architecturally isolated:

```
TanStackRoutes (Root)
└── MantineProvider (assetWatchTheme) ← Global Theme
    └── AppLayout
        └── /hwqa route
            └── HwqaPage
                └── HwqaProtectedRoute
                    └── QueryClientProvider (hwqaQueryClient) ← Separate QueryClient
                        └── AppStateProvider ← HWQA-specific state
                            └── HwqaContent
                                └── HwqaSideNav + Outlet
```

#### Key Files

| File | Purpose |
|------|---------|
| `frontend/src/pages/HwqaPage.tsx` | HWQA container with providers |
| `frontend/src/hwqa/components/layout/HwqaSideNav/HwqaSideNav.tsx` | Side navigation |
| `frontend/src/hwqa/context/AppStateContext.tsx` | HWQA state management |
| `frontend/src/TanStackRoutes.tsx:362-421` | HWQA route definitions |

#### Current Theme Consumption

- **3 files use `useColors` hook**: HwqaSideNav, PassRateBarChart, PassRateLineChart
- **156 color prop usages** across 35 files (e.g., `bg="neutral95"`, `c="dimmed"`)
- **15 CSS module files** with component-specific styles
- **No HWQA-specific color definitions**

#### Theme Provider Insertion Point

The ideal location for scoping a dark theme to HWQA:

```typescript
// HwqaPage.tsx - Current
<HwqaProtectedRoute>
  <QueryClientProvider client={hwqaQueryClient}>
    <AppStateProvider>
      <HwqaContent />
    </AppStateProvider>
  </QueryClientProvider>
</HwqaProtectedRoute>

// HwqaPage.tsx - With Theme Scope
<HwqaProtectedRoute>
  <HwqaThemeProvider>  {/* ← New wrapper */}
    <QueryClientProvider client={hwqaQueryClient}>
      <AppStateProvider>
        <HwqaContent />
      </AppStateProvider>
    </QueryClientProvider>
  </HwqaThemeProvider>
</HwqaProtectedRoute>
```

---

## Code References

### HWQA Standalone (~/repos/hwqa)
- `frontend/src/styles/themes/cssVariablesResolver.ts:17-230` - Full resolver implementation
- `frontend/src/styles/colors/palettes.ts:25-115` - Color family definitions
- `frontend/src/context/ThemeContext.tsx:15-51` - Theme context and hook
- `frontend/src/App.tsx:20-66` - Provider setup
- `frontend/src/components/layout/AppHeader/AppHeader.tsx:52-62` - Theme toggle UI

### AssetWatch Main
- `frontend/src/styles/assetWatchTheme.ts:11-56` - Theme object
- `frontend/src/styles/colorPalette.ts:271-287` - Color transformation
- `frontend/src/TanStackRoutes.tsx:99` - MantineProvider
- `frontend/src/hooks/useColors.ts:22-39` - Color access hook

### HWQA Section in AssetWatch
- `frontend/src/pages/HwqaPage.tsx:70-80` - Entry point (provider insertion)
- `frontend/src/pages/HwqaPage.tsx:22-60` - HwqaContent layout
- `frontend/src/hwqa/components/layout/HwqaSideNav/HwqaSideNav.tsx:110` - useColors usage
- `frontend/src/TanStackRoutes.tsx:362-421` - Route definitions

---

## Architecture Documentation

### Pattern Comparison

| Aspect | HWQA Standalone | AssetWatch | HWQA in AssetWatch |
|--------|-----------------|------------|-------------------|
| Color Scheme | Light/Dark toggle | Light only | Inherits light |
| CSS Variables | Semantic tokens | Flat color variables | Inherits flat |
| Theme Context | Custom ThemeContext | None | None |
| Storage | localStorage | N/A | N/A |
| Provider | Wrapped MantineProvider | Root MantineProvider | Inherits root |

### Implementation Strategy

To bring dark mode to HWQA section:

1. **Port the cssVariablesResolver** from standalone HWQA
2. **Port the ThemeContext** with localStorage persistence
3. **Create HWQA-specific MantineProvider** wrapper at HwqaPage level
4. **Update components** to use semantic variables instead of direct color names
5. **Add theme toggle UI** to HwqaSideNav

---

## Related Research

- `thoughts/shared/research/2025-12-03-IWA-14069-hwqa-styling-research.md` - Previous styling analysis
- `thoughts/shared/research/2025-12-02-hwqa-styling-integration-analysis.md` - Integration patterns

---

## Open Questions

1. **Scope boundary**: Should the theme toggle affect only HWQA or persist globally?
2. **Color palette alignment**: Should HWQA dark mode colors match the standalone implementation or be adjusted for AssetWatch brand?
3. **Migration path**: Update all 156 color prop usages to semantic variables, or create a mapping layer?
4. **AG-Grid theming**: The standalone has AG-Grid CSS variable mappings - needed for data tables
