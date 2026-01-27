---
date: 2025-12-03T12:00:00-06:00
researcher: jwalker
git_commit: b2396427e6969877f9450a0ea7675b2c400defb8
branch: db/IWA-14069
repository: fullstack.assetwatch-hwqa-migration
topic: "HWQA Section Styling - Background Colors, Colorful Cards, and Navbar Design"
tags: [research, codebase, hwqa, styling, ui, mantine, colors]
status: complete
last_updated: 2025-12-03
last_updated_by: jwalker
---

# Research: HWQA Section Styling - Background Colors, Colorful Cards, and Navbar Design

**Date**: 2025-12-03T12:00:00-06:00
**Researcher**: jwalker
**Git Commit**: b2396427e6969877f9450a0ea7675b2c400defb8
**Branch**: db/IWA-14069
**Repository**: fullstack.assetwatch-hwqa-migration

## Research Question

Document the current HWQA section styling to understand:
1. Why there is "too much white" in the HWQA section
2. How light gray backgrounds are used elsewhere in the AssetWatch app
3. Examples of colorful cards (CustomerDetail > Facilities black card, Summary tab colored cards)
4. Current left navbar styling and its simplicity

## Summary

The HWQA section currently uses explicit white backgrounds and lacks the visual variety found elsewhere in AssetWatch. The main AssetWatch app uses a Mantine-based color system with `neutral.8` (`#E2E2E5`) and `neutral.9` (`#F0F0F4`) for light gray backgrounds. CustomerDetail demonstrates colorful card patterns using `neutral.1` (`#1A1C1E` - black) and `secondary.3` (`#004F58` - dark teal). The HWQA navbar is minimally styled with white background, simple text labels, and significant unused space.

## Detailed Findings

### 1. HWQA Section Current White Backgrounds

#### Main Page Container (`HwqaPage.tsx:40-56`)
```typescript
<Flex>
  <HwqaSideNav isOpen={isSideNavOpen} toggle={toggle} />
  <Box
    style={{
      marginLeft: isSmallScreen ? 0 : isSideNavOpen ? SIDE_NAV_WIDTH_OPEN : SIDE_NAV_WIDTH_CLOSED,
      flex: 1,
      padding: "16px",
    }}
  >
    <Outlet />
  </Box>
</Flex>
```
- **No background color** - inherits browser default (white)
- Uses only margin and padding for layout

#### Page Container Component (`PageContainer.tsx:10-26`)
```typescript
<Container
  size="xl"
  py="xl"
  className={classes.container}
  style={{
    marginLeft: 0,
    paddingLeft: '1rem',
    alignSelf: 'flex-start'
  }}
>
```
- **No background color** set
- CSS module only sets width properties, no colors

#### Side Navigation (`HwqaSideNav.tsx:151-153`)
```typescript
style={{
  zIndex: Z_INDEX_INTERFACE.APP_HEADER,
  backgroundColor: isOpen ? "white" : "transparent",
}}
```
- **Explicitly white** when open
- Transparent when collapsed

### 2. Light Gray Background Patterns in AssetWatch

#### Color Palette Definition (`palettes.ts:91-102`)
```typescript
neutral: [
  "#000000", // 0
  "#1A1C1E", // 1 - Figma 10 (dark/black)
  "#2F3133", // 2 - Figma 20
  "#45474A", // 3 - Figma 30
  "#5D5E61", // 4 - Figma 40
  "#76777A", // 5 - Figma 50
  "#8F9194", // 6 - Figma 60
  "#C6C6C9", // 7 - Figma 80
  "#E2E2E5", // 8 - Figma 90 (light gray)
  "#F0F0F4", // 9 - Figma 95 (lightest gray)
]
```

#### Usage Patterns Found Elsewhere in AssetWatch

| Pattern | Hex Value | Mantine Index | Usage Example |
|---------|-----------|---------------|---------------|
| `bg="neutral.9"` | `#F0F0F4` | neutral[9] | Page backgrounds, cards |
| `bg="neutral.8"` | `#E2E2E5` | neutral[8] | Papers, panels |
| `bg="neutral.7"` | `#C6C6C9` | neutral[7] | Dividers, borders |
| `.body-background` | `#efeef1` | legacy | Full page containers |

#### SideSheet Component (`SideSheet.tsx:85`)
```tsx
<Stack bg="neutral.9" tt="none" ff="Inter, sans-serif">
```

#### RecentWins Card (`RecentWins.tsx:32-40`)
```tsx
<Card bg="neutral.9" padding="xs" withBorder>
```

#### DarkContainer Legacy Pattern (`DarkContainer.tsx + App.css:337-342`)
```css
.body-background {
  background: #efeef1;
  padding: 10px 20px;
  min-height: 100vh;
  box-shadow: 0 5px 10px rgb(0 0 0 / 60%);
}
```

### 3. Colorful Card Examples from CustomerDetail

#### Facilities Tab - Black Background Card (`FacilitySummaryTile.tsx:78-119`)
```tsx
<Paper
  c="white"                    // White text
  bg="neutral.1"               // BLACK (#1A1C1E)
  p="xl"                       // Extra large padding
  radius="lg"                  // Large border radius
>
```
- **Key styling**: Dark background with contrasting white text
- Includes hover effects via CSS module (transform, box-shadow)
- Contains facility metrics, status bars, icons

#### Summary Tab - Cost Savings Card (`CostSavings.tsx:166-174`)
```tsx
<Paper
  radius="md"
  p="lg"
  pb="xl"
  bg="secondary.3"             // DARK TEAL (#004F58)
  ta="center"
>
```
- **Key styling**: Brand color (dark teal) background
- Provides visual contrast in the summary grid
- Contains cost savings metrics

#### Progress Bar Colors in Summary Tab
```typescript
const STATUS_COLORS = {
  "All Good": "primary.7",        // #2DDBB9 (bright teal)
  Watching: "warning.7",          // #E9C400 (yellow)
  "Maintenance Recommended": "critical.4",  // #AD311D (red)
};
```

### 4. Current HWQA Left Navbar Styling

#### Container Styling (`HwqaSideNav.tsx:137-155`)
```typescript
<Box
  pt={25}
  px={isOpen ? 20 : 0}
  h={`calc(100vh - ${APP_HEADER_HEIGHT}px)`}
  w={isOpen ? (isSmallScreen ? "100vw" : SIDE_NAV_WIDTH_OPEN) : SIDE_NAV_WIDTH_CLOSED}
  pos="fixed"
  style={{
    zIndex: Z_INDEX_INTERFACE.APP_HEADER,
    backgroundColor: isOpen ? "white" : "transparent",  // PURE WHITE
  }}
>
```

#### Title (`HwqaSideNav.tsx:187-189`)
```typescript
<Title order={3} c={colors.primary40}>   // #006B59 (teal)
  Hardware QA
</Title>
```

#### Section Headers (`HwqaSideNav.tsx:197-199`)
```typescript
<Text size="xs" c="dimmed" fw={600} mb="xs" tt="uppercase">
  {section.title}
</Text>
```

#### Nav Items (`HwqaSideNav.tsx:203-218`)
```typescript
<NavLink
  label={item.text}
  active={isActive}
  style={{
    borderRadius: 10,
    fontWeight: isActive ? "bolder" : "initial",
    color: isActive ? "white" : colors.primary40,
    backgroundColor: isActive ? colors.primary40 : "",  // Empty = transparent
    boxShadow: isActive ? "0px 4px 8px -4px rgba(76, 78, 100, 0.42)" : "none",
  }}
/>
```

**Current issues with navbar:**
- White background provides no visual weight
- Section headers are very small and "dimmed"
- Inactive items have no background - just text
- No icons for navigation items
- Simple dividers between sections
- Large amounts of empty vertical space

### 5. HWQA Color Palette (Same as Main App)

The HWQA section has access to the full AssetWatch color system via `palettes.ts`:

**Primary (Teal)**
- `primary.4` (#006B59) - Used for navbar title, links
- `primary.6` (#00A388) - Primary brand color
- `primary.7` (#2DDBB9) - Accent highlights

**Secondary (Dark Teal)**
- `secondary.3` (#004F58) - Used in CostSavings card

**Neutral (Grays)**
- `neutral.1` (#1A1C1E) - Black for dark cards
- `neutral.8` (#E2E2E5) - Light gray backgrounds
- `neutral.9` (#F0F0F4) - Lightest gray backgrounds

**Status Colors**
- `critical.4` (#AD311D) - Error/maintenance
- `warning.7` (#E9C400) - Warning/watching
- `primary.7` (#2DDBB9) - Success/all good

## Code References

### HWQA Files
- `frontend/src/pages/HwqaPage.tsx:40-56` - Main page wrapper (no bg color)
- `frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.tsx:151-153` - White navbar background
- `frontend/src/hwqa/components/layout/PageContainer/PageContainer.tsx:10-26` - Page container (no bg)

### AssetWatch Light Gray Examples
- `frontend/src/styles/colorPalette.ts:87-102` - Color system definition
- `frontend/src/hwqa/styles/colors/palettes.ts:91-102` - HWQA color palette
- `frontend/src/components/SideSheet/SideSheet.tsx:85` - `bg="neutral.9"` usage
- `frontend/src/styles/css/App.css:337-342` - Legacy `.body-background` class

### Colorful Card Examples
- `frontend/src/pages/facilities/components/FacilitySummaryTile.tsx:78-119` - Black card (`bg="neutral.1"`)
- `frontend/src/components/CustomerDetailPage/SummaryTab/CostSavings.tsx:166-174` - Teal card (`bg="secondary.3"`)
- `frontend/src/components/CustomerDetailPage/SummaryTab/AlertPercentage.tsx:10-14` - Status colors

## Architecture Documentation

### Mantine Color System
The app uses Mantine's theme system with custom color tuples. Colors are:
1. Defined in `palettes.ts` as 10-shade arrays (index 0-9)
2. Accessed via `useColors()` hook or Mantine `bg`/`c` props
3. Applied using format: `bg="neutral.9"` or `c="primary.4"`

### Styling Patterns
1. **Mantine Props (preferred)**: `<Paper bg="neutral.9" p="xl" />`
2. **CSS Modules**: For complex hover/animation states
3. **Inline styles**: Rarely, for one-off positioning

## Open Questions

1. Should HWQA use `neutral.9` (#F0F0F4) or `neutral.8` (#E2E2E5) for page backgrounds?
2. Should navbar items have icons like in other navigation patterns?
3. Should section cards use the colorful patterns from CustomerDetail?
4. What elements should get accent colors vs. remain neutral?
