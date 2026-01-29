# HWQA Integration Refactor Implementation Plan

## Overview

Refactor the HWQA (Hardware Quality Assurance) code that was ported from another repository to integrate seamlessly with the AssetWatch application. The HWQA section currently operates as an isolated application with its own layout, theme, and routing, which causes styling conflicts and navigation issues with the main app.

## Current State Analysis

### Problems Identified:
1. **Global CSS leakage**: `AppLayout.css` sets `:root`, `body`, and `.mantine-AppShell-*` styles with `!important` that override main app styling
2. **Nested layouts**: HWQA renders its own `AppLayout` inside the main app's `AppLayout`, hiding the main navbar
3. **Isolated routing**: Uses `MemoryRouter` instead of TanStack Router, preventing URL-based navigation
4. **Separate theme system**: Has its own `MantineProvider`, `ThemeContext`, and `cssVariablesResolver`
5. **Duplicate imports**: Re-imports Mantine CSS files already loaded by main app

### Key Discoveries:
- HWQA entry: `frontend/src/hwqa/HwqaApp.tsx:1-113`
- Problematic CSS: `frontend/src/hwqa/components/layout/AppLayout/AppLayout.css:12-43`
- Reference pattern: `frontend/src/components/CustomerDetailPage/SideNav.tsx`
- Navigation config: `frontend/src/hooks/useNavLinks.ts:53-76` (Hardware section)
- HWQA permissions: `frontend/src/hwqa/contexts/AuthContext.tsx` with roles: Engineering, SupplyChain, ContractManufacturer

## Desired End State

After implementation:
1. HWQA accessible via `/hwqa/*` routes in browser URL (TanStack Router)
2. HWQA appears under Hardware navigation menu in left navbar
3. Main app header (black) and left navbar (80px icons) remain visible
4. HWQA has its own SideNav (like CustomerDetail) for internal tab navigation
5. No styling conflicts - main app looks correct on all pages
6. Only NikolaTeam users can access HWQA
7. Only SupplyChain, ContractManufacturer, and Engineering roles have write access

### Verification:
- Navigate to any non-HWQA page - header should be black, navbar visible
- Navigate to `/hwqa` - main navbar stays, HWQA SideNav appears in content area
- Browser URL updates when navigating within HWQA (e.g., `/hwqa/sensor/tests`)
- Non-NikolaTeam users cannot access `/hwqa` routes
- Read-only users see data but not forms

## What We're NOT Doing

- Not migrating HWQA common components to main app equivalents yet (Phase 4+ work)
- Not adding dark mode support (will come with main app dark mode later)
- Not changing HWQA backend/API layer
- Not modifying HWQA feature components logic
- Not changing HWQA data tables or charts

## Implementation Approach

Follow the CustomerDetail pattern: remove HWQA's isolated layout/routing, create a SideNav component for internal navigation, and integrate with TanStack Router for URL-based routing.

---

## Phase 1: Fix Immediate Styling Issues

### Overview
Remove global CSS that's breaking the main app styling. This is the critical fix to restore correct header/navbar colors across the entire application.

### Changes Required:

#### 1. Delete Global CSS File
**File**: `frontend/src/hwqa/components/layout/AppLayout/AppLayout.css`
**Action**: Delete this file entirely

This file contains global `:root`, `body`, and `.mantine-AppShell-*` selectors that leak into the main app. All necessary styling will be handled by scoped CSS modules in later phases.

#### 2. Remove CSS Import from HWQA AppLayout
**File**: `frontend/src/hwqa/components/layout/AppLayout/AppLayout.tsx`
**Changes**: Remove the CSS import

Current (line ~1-5):
```tsx
import { AppShell } from "@mantine/core";
import { Outlet } from "react-router-dom";
import { AppNavbar } from "../AppNavbar/AppNavbar";
import "./AppLayout.css";  // REMOVE THIS LINE
```

After:
```tsx
import { AppShell } from "@mantine/core";
import { Outlet } from "react-router-dom";
import { AppNavbar } from "../AppNavbar/AppNavbar";
```

#### 3. Remove Duplicate Mantine CSS Imports
**File**: `frontend/src/hwqa/HwqaApp.tsx`
**Changes**: Remove lines 22-24

Current:
```tsx
// Import hwqa styles
import "@mantine/core/styles.css";
import "@mantine/dates/styles.css";
import "@mantine/notifications/styles.css";
```

After:
```tsx
// Mantine styles are imported by the main app - no need to import here
```

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npm run typecheck`
- [ ] Linting passes: `cd frontend && npm run lint`
- [ ] Build succeeds: `cd frontend && npm run build`
- [ ] CSS file no longer exists: `ls frontend/src/hwqa/components/layout/AppLayout/AppLayout.css` should fail

#### Manual Verification:
- [ ] Navigate to home page (`/`) - header is black, left navbar visible with icons
- [ ] Navigate to any customer detail page - styling is correct
- [ ] Navigate to `/hwqa` - page still loads (may have different layout, that's expected)
- [ ] No console errors related to missing CSS

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding to Phase 2.

---

## Phase 2: Integrate with Main Layout

### Overview
Remove HWQA's nested layout architecture. Create an `HwqaSideNav` component following the CustomerDetail SideNav pattern. HWQA pages will render inside the main app's layout with their own internal navigation.

### Changes Required:

#### 1. Create HWQA Tab Enum
**File**: `frontend/src/hwqa/enums/HwqaTab.ts` (NEW)
**Action**: Create new file

```typescript
export enum HwqaTab {
  SensorDashboard = "sensor-dashboard",
  SensorTests = "sensor-tests",
  SensorShipments = "sensor-shipments",
  SensorConversion = "sensor-conversion",
  HubDashboard = "hub-dashboard",
  HubTests = "hub-tests",
  HubShipments = "hub-shipments",
  Glossary = "glossary",
}
```

#### 2. Create HWQA Context
**File**: `frontend/src/hwqa/contexts/HwqaContext.tsx` (NEW)
**Action**: Create new file for tab state management

```typescript
import { createContext, useContext, useState, ReactNode } from "react";
import { HwqaTab } from "../enums/HwqaTab";

interface HwqaContextType {
  activeTab: HwqaTab;
  setActiveTab: (tab: HwqaTab) => void;
}

const HwqaContext = createContext<HwqaContextType | undefined>(undefined);

interface HwqaProviderProps {
  children: ReactNode;
  initialTab?: HwqaTab;
}

export function HwqaProvider({ children, initialTab = HwqaTab.SensorDashboard }: HwqaProviderProps) {
  const [activeTab, setActiveTab] = useState<HwqaTab>(initialTab);

  return (
    <HwqaContext.Provider value={{ activeTab, setActiveTab }}>
      {children}
    </HwqaContext.Provider>
  );
}

export function useHwqaContext() {
  const context = useContext(HwqaContext);
  if (!context) {
    throw new Error("useHwqaContext must be used within an HwqaProvider");
  }
  return context;
}
```

#### 3. Create HwqaSideNav Component
**File**: `frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.tsx` (NEW)
**Action**: Create new component following CustomerDetail SideNav pattern

```typescript
import {
  faChevronLeft,
  faChevronRight,
} from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useIsSmallScreen } from "@hooks/useIsSmallScreen";
import {
  ActionIcon,
  Box,
  Flex,
  Kbd,
  NavLink,
  Select,
  Space,
  Text,
  Title,
  Tooltip,
  Divider,
} from "@mantine/core";
import { useHover } from "@mantine/hooks";
import { Z_INDEX_INTERFACE } from "@styles/zIndex";
import { useNavigate } from "@tanstack/react-router";
import {
  APP_HEADER_HEIGHT,
  SIDE_NAV_WIDTH_CLOSED,
  SIDE_NAV_WIDTH_OPEN,
} from "@utils/constants";
import { useColors } from "@hooks/useColors";
import { HwqaTab } from "../../enums/HwqaTab";

interface HwqaSideNavProps {
  isOpen: boolean;
  toggle: () => void;
  activeTab: HwqaTab;
  onTabChange: (tab: HwqaTab) => void;
}

type NavSection = {
  title: string;
  items: NavItem[];
};

type NavItem = {
  text: string;
  eventKey: HwqaTab;
  path: string;
};

const navSections: NavSection[] = [
  {
    title: "Sensors",
    items: [
      { text: "Dashboard", eventKey: HwqaTab.SensorDashboard, path: "/hwqa/sensor/dashboard" },
      { text: "Tests", eventKey: HwqaTab.SensorTests, path: "/hwqa/sensor/tests" },
      { text: "Shipments", eventKey: HwqaTab.SensorShipments, path: "/hwqa/sensor/shipments" },
      { text: "Conversion", eventKey: HwqaTab.SensorConversion, path: "/hwqa/sensor/conversion" },
    ],
  },
  {
    title: "Hubs",
    items: [
      { text: "Dashboard", eventKey: HwqaTab.HubDashboard, path: "/hwqa/hub/dashboard" },
      { text: "Tests", eventKey: HwqaTab.HubTests, path: "/hwqa/hub/tests" },
      { text: "Shipments", eventKey: HwqaTab.HubShipments, path: "/hwqa/hub/shipments" },
    ],
  },
  {
    title: "Other",
    items: [
      { text: "Glossary", eventKey: HwqaTab.Glossary, path: "/hwqa/glossary" },
    ],
  },
];

export function HwqaSideNav({ isOpen, toggle, activeTab, onTabChange }: HwqaSideNavProps) {
  const colors = useColors();
  const { hovered, ref } = useHover();
  const isSmallScreen = useIsSmallScreen();
  const navigate = useNavigate();

  const handleNavClick = (item: NavItem) => {
    onTabChange(item.eventKey);
    navigate({ to: item.path });
  };

  const allItems = navSections.flatMap((section) => section.items);

  const tooltipContent = (
    <Flex align="center">
      <Text>{isOpen ? "Collapse" : "Expand"}</Text>
      <Space w="xs" />
      <Kbd size="xs">[</Kbd>
    </Flex>
  );

  const isCollapseButtonVisible = (isOpen && hovered) || !isOpen || isSmallScreen;

  return (
    <Box
      pt={25}
      px={isOpen ? 20 : 0}
      h={`calc(100vh - ${APP_HEADER_HEIGHT}px)`}
      w={isOpen ? (isSmallScreen ? "100vw" : SIDE_NAV_WIDTH_OPEN) : SIDE_NAV_WIDTH_CLOSED}
      top={APP_HEADER_HEIGHT}
      pos="fixed"
      ref={ref}
      style={{
        zIndex: Z_INDEX_INTERFACE.APP_HEADER,
        backgroundColor: isOpen ? "white" : "transparent",
      }}
    >
      {isCollapseButtonVisible && (
        <Box pos="relative">
          <Tooltip position="right" label={tooltipContent}>
            <ActionIcon
              data-testid="hwqa-sidenav-toggle"
              pos="absolute"
              top={isSmallScreen ? 5 : 10}
              right={-15}
              display="flex"
              onClick={toggle}
              variant="white"
              color="neutral60"
              style={{
                zIndex: 1,
                border: `1px solid ${colors.neutral60}`,
                borderRadius: 100,
              }}
            >
              <FontAwesomeIcon
                size="xs"
                icon={isOpen ? faChevronLeft : faChevronRight}
              />
            </ActionIcon>
          </Tooltip>
        </Box>
      )}

      {isOpen && (
        <Flex direction="column" h={isSmallScreen ? "auto" : "100%"}>
          <Box>
            <Space h="xl" />
            <Title order={3} c={colors.primary40}>Hardware QA</Title>
            <Space h="lg" />
          </Box>

          {!isSmallScreen && (
            <Box style={{ flex: 1, overflowY: "auto" }} pb="xl">
              {navSections.map((section, sectionIdx) => (
                <Box key={section.title} mb="md">
                  <Text size="xs" c="dimmed" fw={600} mb="xs" tt="uppercase">
                    {section.title}
                  </Text>
                  {section.items.map((item) => {
                    const isActive = activeTab === item.eventKey;
                    return (
                      <NavLink
                        data-testid={`hwqa-sidenav-${item.eventKey}`}
                        key={item.eventKey}
                        label={item.text}
                        active={isActive}
                        onClick={() => handleNavClick(item)}
                        style={{
                          borderRadius: 10,
                          fontWeight: isActive ? "bolder" : "initial",
                          color: isActive ? "white" : colors.primary40,
                          backgroundColor: isActive ? colors.primary40 : "",
                          boxShadow: isActive
                            ? "0px 4px 8px -4px rgba(76, 78, 100, 0.42)"
                            : "none",
                        }}
                      />
                    );
                  })}
                  {sectionIdx < navSections.length - 1 && <Divider my="sm" />}
                </Box>
              ))}
            </Box>
          )}
        </Flex>
      )}

      {isSmallScreen && isOpen && (
        <Select
          data-testid="hwqa-sidenav-select"
          label="Section:"
          value={activeTab}
          data={allItems.map((item) => ({
            value: item.eventKey,
            label: item.text,
          }))}
          onChange={(value) => {
            const item = allItems.find((i) => i.eventKey === value);
            if (item) handleNavClick(item);
          }}
        />
      )}
    </Box>
  );
}
```

#### 4. Create HwqaSideNav CSS Module
**File**: `frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.module.css` (NEW)

```css
/* Minimal styling - using Mantine components and useColors hook for consistency */
```

#### 5. Create HwqaSideNav Index
**File**: `frontend/src/hwqa/components/HwqaSideNav/index.ts` (NEW)

```typescript
export { HwqaSideNav } from "./HwqaSideNav";
```

#### 6. Refactor HwqaPage to Use New Layout Pattern
**File**: `frontend/src/pages/HwqaPage.tsx`
**Action**: Complete rewrite to follow CustomerDetail pattern

```typescript
import { useDisclosure } from "@mantine/hooks";
import { useIsSmallScreen } from "@hooks/useIsSmallScreen";
import { useRegisterHotkey } from "@hooks/useRegisterHotkey";
import { useAuthContext } from "@contexts/AuthContext";
import { Box, Flex } from "@mantine/core";
import { SIDE_NAV_WIDTH_CLOSED, SIDE_NAV_WIDTH_OPEN } from "@utils/constants";
import { Outlet, useMatch } from "@tanstack/react-router";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { HwqaSideNav } from "../hwqa/components/HwqaSideNav";
import { HwqaProvider, useHwqaContext } from "../hwqa/contexts/HwqaContext";
import { HwqaTab } from "../hwqa/enums/HwqaTab";
import { AuthContextProvider as HwqaAuthContextProvider } from "../hwqa/contexts/AuthContext";
import { AppStateProvider } from "../hwqa/context/AppStateContext";

// Separate QueryClient for HWQA to avoid conflicts
const hwqaQueryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false,
    },
  },
});

function HwqaContent() {
  const { isTeamMember } = useAuthContext();
  const { activeTab, setActiveTab } = useHwqaContext();
  const isSmallScreen = useIsSmallScreen();

  const [isSideNavOpen, { toggle }] = useDisclosure(true);

  useRegisterHotkey({
    keys: "[",
    callback: () => {
      if (isTeamMember) toggle();
    },
    description: "Open/close HWQA navigation",
    components: [],
    isAvailable: isTeamMember,
  });

  return (
    <Flex>
      <HwqaSideNav
        isOpen={isSideNavOpen}
        toggle={toggle}
        activeTab={activeTab}
        onTabChange={setActiveTab}
      />
      <Box
        style={{
          marginLeft: isSmallScreen
            ? 0
            : isSideNavOpen
              ? SIDE_NAV_WIDTH_OPEN
              : SIDE_NAV_WIDTH_CLOSED,
          flex: 1,
          padding: "16px",
        }}
      >
        <Outlet />
      </Box>
    </Flex>
  );
}

export function HwqaPage() {
  return (
    <QueryClientProvider client={hwqaQueryClient}>
      <HwqaAuthContextProvider>
        <AppStateProvider>
          <HwqaProvider>
            <HwqaContent />
          </HwqaProvider>
        </AppStateProvider>
      </HwqaAuthContextProvider>
    </QueryClientProvider>
  );
}
```

#### 7. Delete Obsolete HWQA Layout Files
**Files to Delete**:
- `frontend/src/hwqa/components/layout/AppLayout/AppLayout.tsx`
- `frontend/src/hwqa/components/layout/AppHeader/AppHeader.tsx`
- `frontend/src/hwqa/components/layout/AppHeader/AppHeader.module.css`
- `frontend/src/hwqa/components/layout/UserMenu/UserMenu.tsx`
- `frontend/src/hwqa/context/ThemeContext.tsx`
- `frontend/src/hwqa/styles/themes/cssVariablesResolver.ts`
- `frontend/src/hwqa/styles/themes/mantineTheme.ts`

#### 8. Update HWQA Layout Index
**File**: `frontend/src/hwqa/components/layout/index.ts`
**Action**: Remove exports for deleted components

Current exports to remove:
```typescript
// Remove these exports
export { default as AppLayout } from "./AppLayout/AppLayout";
export { AppHeader } from "./AppHeader/AppHeader";
export { UserMenu } from "./UserMenu/UserMenu";
```

Keep:
```typescript
export { PageContainer } from "./PageContainer/PageContainer";
export { NonProdEnvironmentInfo } from "./NonProdEnvironmentInfo";
```

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npm run typecheck`
- [ ] Linting passes: `cd frontend && npm run lint`
- [ ] Build succeeds: `cd frontend && npm run build`
- [ ] New files exist: `ls frontend/src/hwqa/components/HwqaSideNav/`
- [ ] Deleted files removed: Layout files no longer exist

#### Manual Verification:
- [ ] Navigate to `/hwqa` - main app header/navbar visible, HWQA SideNav appears
- [ ] Clicking SideNav items shows corresponding content
- [ ] SideNav collapse/expand works with `[` hotkey
- [ ] Mobile responsive layout works correctly
- [ ] No console errors

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding to Phase 3.

---

## Phase 3: Convert to TanStack Router

### Overview
Replace the MemoryRouter with TanStack Router routes. This enables URL-based navigation within HWQA, allowing users to bookmark and share specific pages. Also adds HWQA to the Hardware navigation menu.

### Changes Required:

#### 1. Add HWQA Routes to TanStack Router
**File**: `frontend/src/TanStackRoutes.tsx`
**Changes**: Add child routes for HWQA

Add imports at top of file:
```typescript
import { SensorDashboardPage } from "@pages/hwqa/pages/SensorDashboardPage";
import { SensorTestsPage } from "@pages/hwqa/pages/SensorTestsPage";
import { SensorShipmentsPage } from "@pages/hwqa/pages/SensorShipmentsPage";
import { SensorConversionPage } from "@pages/hwqa/pages/SensorConversionPage";
import { HubDashboardPage } from "@pages/hwqa/pages/HubDashboardPage";
import { HubTestsPage } from "@pages/hwqa/pages/HubTestsPage";
import { HubShipmentsPage } from "@pages/hwqa/pages/HubShipmentsPage";
import { GlossaryPage as HwqaGlossaryPage } from "@pages/hwqa/pages/GlossaryPage";
```

Replace the existing `hwqaRoute` definition (around line 353-357) with:
```typescript
// HWQA parent route - renders HwqaPage with SideNav
const hwqaRoute = createRoute({
  getParentRoute: () => protectedRoute,
  path: "/hwqa",
  component: HwqaPage,
});

// HWQA child routes - render inside HwqaPage's Outlet
const hwqaSensorDashboardRoute = createRoute({
  getParentRoute: () => hwqaRoute,
  path: "/sensor/dashboard",
  component: SensorDashboardPage,
});

const hwqaSensorTestsRoute = createRoute({
  getParentRoute: () => hwqaRoute,
  path: "/sensor/tests",
  component: SensorTestsPage,
});

const hwqaSensorShipmentsRoute = createRoute({
  getParentRoute: () => hwqaRoute,
  path: "/sensor/shipments",
  component: SensorShipmentsPage,
});

const hwqaSensorConversionRoute = createRoute({
  getParentRoute: () => hwqaRoute,
  path: "/sensor/conversion",
  component: SensorConversionPage,
});

const hwqaHubDashboardRoute = createRoute({
  getParentRoute: () => hwqaRoute,
  path: "/hub/dashboard",
  component: HubDashboardPage,
});

const hwqaHubTestsRoute = createRoute({
  getParentRoute: () => hwqaRoute,
  path: "/hub/tests",
  component: HubTestsPage,
});

const hwqaHubShipmentsRoute = createRoute({
  getParentRoute: () => hwqaRoute,
  path: "/hub/shipments",
  component: HubShipmentsPage,
});

const hwqaGlossaryRoute = createRoute({
  getParentRoute: () => hwqaRoute,
  path: "/glossary",
  component: HwqaGlossaryPage,
});

// Index route - redirects to sensor dashboard
const hwqaIndexRoute = createRoute({
  getParentRoute: () => hwqaRoute,
  path: "/",
  component: SensorDashboardPage,
});
```

Update the route tree to include child routes:
```typescript
const hwqaRouteWithChildren = hwqaRoute.addChildren([
  hwqaIndexRoute,
  hwqaSensorDashboardRoute,
  hwqaSensorTestsRoute,
  hwqaSensorShipmentsRoute,
  hwqaSensorConversionRoute,
  hwqaHubDashboardRoute,
  hwqaHubTestsRoute,
  hwqaHubShipmentsRoute,
  hwqaGlossaryRoute,
]);
```

Update the route tree reference (replace `hwqaRoute` with `hwqaRouteWithChildren` in the tree).

#### 2. Update Navigation Links
**File**: `frontend/src/hooks/useNavLinks.ts`
**Changes**: Add `/hwqa` to Hardware containedRoutes

```typescript
{
  icon: faHdd,
  label: "Hardware",
  href: "/hardware",
  hasPermission: isInternalUser,
  containedRoutes: [
    "/facilityhardware",
    "/firmwarerollout",
    "/firmwareupload",
    "/hardware-events",
    "/hwqa",  // ADD THIS LINE
    "/inventory",
    "/receiverschanged",
    "/receiversunassigned",
    "/requests",
    "/sensorcheck",
    "/trackinventory",
    "/wifi-diagnostics",
    "/wifi-setup",
    "/enclosures",
    "/part-revisions",
    "/part-number-stats",
    "/hardware-ratios",
  ],
},
```

#### 3. Delete HwqaApp.tsx
**File**: `frontend/src/hwqa/HwqaApp.tsx`
**Action**: Delete - no longer needed

The MemoryRouter and nested providers are replaced by TanStack routes and the refactored HwqaPage.

#### 4. Update HWQA Page Components to Remove react-router-dom
**Files**: All files in `frontend/src/hwqa/pages/*.tsx`
**Changes**: Replace `useNavigate` from react-router-dom with TanStack Router

Example for each page file, replace:
```typescript
import { useNavigate } from "react-router-dom";
```

With:
```typescript
import { useNavigate } from "@tanstack/react-router";
```

The `navigate()` calls should work the same way with TanStack Router.

#### 5. Update HwqaSideNav to Sync with URL
**File**: `frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.tsx`
**Changes**: Determine active tab from current route

Add to imports:
```typescript
import { useLocation } from "@tanstack/react-router";
```

Update component to derive active tab from URL:
```typescript
export function HwqaSideNav({ isOpen, toggle }: Omit<HwqaSideNavProps, 'activeTab' | 'onTabChange'>) {
  const location = useLocation();
  const navigate = useNavigate();

  // Derive active tab from URL path
  const getActiveTab = (): HwqaTab => {
    const path = location.pathname;
    if (path.includes("/sensor/dashboard")) return HwqaTab.SensorDashboard;
    if (path.includes("/sensor/tests")) return HwqaTab.SensorTests;
    if (path.includes("/sensor/shipments")) return HwqaTab.SensorShipments;
    if (path.includes("/sensor/conversion")) return HwqaTab.SensorConversion;
    if (path.includes("/hub/dashboard")) return HwqaTab.HubDashboard;
    if (path.includes("/hub/tests")) return HwqaTab.HubTests;
    if (path.includes("/hub/shipments")) return HwqaTab.HubShipments;
    if (path.includes("/glossary")) return HwqaTab.Glossary;
    return HwqaTab.SensorDashboard;
  };

  const activeTab = getActiveTab();

  const handleNavClick = (item: NavItem) => {
    navigate({ to: item.path });
  };
  // ... rest of component
}
```

#### 6. Simplify HwqaPage (Remove Context)
**File**: `frontend/src/pages/HwqaPage.tsx`
**Changes**: Remove HwqaContext since tab state is now in URL

```typescript
import { useDisclosure } from "@mantine/hooks";
import { useIsSmallScreen } from "@hooks/useIsSmallScreen";
import { useRegisterHotkey } from "@hooks/useRegisterHotkey";
import { useAuthContext } from "@contexts/AuthContext";
import { Box, Flex } from "@mantine/core";
import { SIDE_NAV_WIDTH_CLOSED, SIDE_NAV_WIDTH_OPEN } from "@utils/constants";
import { Outlet } from "@tanstack/react-router";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { HwqaSideNav } from "../hwqa/components/HwqaSideNav";
import { AuthContextProvider as HwqaAuthContextProvider } from "../hwqa/contexts/AuthContext";
import { AppStateProvider } from "../hwqa/context/AppStateContext";

const hwqaQueryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false,
    },
  },
});

function HwqaContent() {
  const { isTeamMember } = useAuthContext();
  const isSmallScreen = useIsSmallScreen();

  const [isSideNavOpen, { toggle }] = useDisclosure(true);

  useRegisterHotkey({
    keys: "[",
    callback: () => {
      if (isTeamMember) toggle();
    },
    description: "Open/close HWQA navigation",
    components: [],
    isAvailable: isTeamMember,
  });

  return (
    <Flex>
      <HwqaSideNav isOpen={isSideNavOpen} toggle={toggle} />
      <Box
        style={{
          marginLeft: isSmallScreen
            ? 0
            : isSideNavOpen
              ? SIDE_NAV_WIDTH_OPEN
              : SIDE_NAV_WIDTH_CLOSED,
          flex: 1,
          padding: "16px",
        }}
      >
        <Outlet />
      </Box>
    </Flex>
  );
}

export function HwqaPage() {
  return (
    <QueryClientProvider client={hwqaQueryClient}>
      <HwqaAuthContextProvider>
        <AppStateProvider>
          <HwqaContent />
        </AppStateProvider>
      </HwqaAuthContextProvider>
    </QueryClientProvider>
  );
}
```

#### 7. Delete HwqaContext (No Longer Needed)
**File**: `frontend/src/hwqa/contexts/HwqaContext.tsx`
**Action**: Delete - tab state now lives in URL

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npm run typecheck`
- [ ] Linting passes: `cd frontend && npm run lint`
- [ ] Build succeeds: `cd frontend && npm run build`
- [ ] HwqaApp.tsx deleted: File no longer exists

#### Manual Verification:
- [ ] Navigate to `/hwqa` - redirects to `/hwqa/sensor/dashboard`
- [ ] Browser URL updates when clicking SideNav items
- [ ] Direct URL navigation works (e.g., type `/hwqa/hub/tests` in browser)
- [ ] Hardware nav icon stays highlighted when on any `/hwqa/*` route
- [ ] Back/forward browser buttons work correctly
- [ ] Refreshing page on any HWQA route works

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding to Phase 4.

---

## Phase 4: Add Access Control

### Overview
Restrict HWQA access to NikolaTeam users only. Ensure write permissions (logging tests/shipments) are limited to SupplyChain, ContractManufacturer, and Engineering roles. The permission patterns already exist in HWQA code.

### Changes Required:

#### 1. Create HWQA Protected Route
**File**: `frontend/src/hwqa/components/HwqaProtectedRoute.tsx` (NEW)

```typescript
import { Navigate } from "@tanstack/react-router";
import { useAuthContext } from "@contexts/AuthContext";
import { UserRole } from "@shared/enums/UserRole";

interface HwqaProtectedRouteProps {
  children: React.ReactNode;
}

export function HwqaProtectedRoute({ children }: HwqaProtectedRouteProps) {
  const { cognitoUserGroup, isAuthenticating } = useAuthContext();

  if (isAuthenticating) {
    return <div>Loading...</div>;
  }

  // Only NikolaTeam can access HWQA
  const isNikolaTeam = cognitoUserGroup.includes(UserRole.NIKOLA_TEAM);

  if (!isNikolaTeam) {
    return <Navigate to="/" />;
  }

  return <>{children}</>;
}
```

#### 2. Wrap HwqaPage with Access Control
**File**: `frontend/src/pages/HwqaPage.tsx`
**Changes**: Add HwqaProtectedRoute wrapper

```typescript
import { HwqaProtectedRoute } from "../hwqa/components/HwqaProtectedRoute";

// ... existing code ...

export function HwqaPage() {
  return (
    <HwqaProtectedRoute>
      <QueryClientProvider client={hwqaQueryClient}>
        <HwqaAuthContextProvider>
          <AppStateProvider>
            <HwqaContent />
          </AppStateProvider>
        </HwqaAuthContextProvider>
      </QueryClientProvider>
    </HwqaProtectedRoute>
  );
}
```

#### 3. Verify Write Permission Checks
**Files**: HWQA page components that render forms
**Action**: Verify existing `canLogTests` and `canLogShipments` checks are working

The HWQA AuthContext already computes these permissions at `frontend/src/hwqa/contexts/AuthContext.tsx:174-178`:
```typescript
const isEngineering = userRole.includes(UserRole.ENGINEERING);
const isSupplyChain = userRole.includes(UserRole.SUPPLY_CHAIN);
const isContractManufacturer = userRole.includes(UserRole.CONTRACT_MANUFACTURER);
const canLogTests = isEngineering || isSupplyChain || isContractManufacturer;
const canLogShipments = isEngineering || isSupplyChain || isContractManufacturer;
```

These are already used in:
- `SensorTestsPage.tsx:111-128` - Conditionally renders LogTestForm
- `SensorShipmentsPage.tsx:132-149` - Conditionally renders LogShipmentForm
- `HubTestsPage.tsx` - Similar pattern
- `HubShipmentsPage.tsx` - Similar pattern
- `GlossaryPage.tsx:73-90` - Conditionally renders Add buttons

No changes needed if patterns are already in place.

#### 4. Connect HWQA AuthContext to Main App User Info
**File**: `frontend/src/hwqa/contexts/AuthContext.tsx`
**Changes**: Use main app's auth info instead of separate API call

The HWQA AuthContext currently fetches user info from `/me` endpoint. We need to ensure it uses the same user session as the main app, or receives user info from the main app.

Option A (Recommended): Pass user info from main app to HWQA context:

Update `HwqaPage.tsx`:
```typescript
import { useAuthContext as useMainAuthContext } from "@contexts/AuthContext";

function HwqaContent() {
  const { userRole, cognitoUserGroup } = useMainAuthContext();
  // ... rest of component
}
```

Update HWQA AuthContext to accept initial values or integrate with main app context.

Option B: Keep separate context but ensure it uses same session token (current behavior should work if Cognito session is shared).

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npm run typecheck`
- [ ] Linting passes: `cd frontend && npm run lint`
- [ ] Build succeeds: `cd frontend && npm run build`

#### Manual Verification:
- [ ] Non-NikolaTeam user is redirected away from `/hwqa`
- [ ] NikolaTeam user without write roles can view HWQA pages
- [ ] NikolaTeam user without write roles does NOT see test/shipment forms
- [ ] NikolaTeam user with SupplyChain role can log tests and shipments
- [ ] NikolaTeam user with Engineering role can log tests and shipments
- [ ] NikolaTeam user with ContractManufacturer role can log tests and shipments

**Implementation Note**: After completing this phase, the core integration is complete. Phase 4+ work (component standardization) is out of scope for this plan.

---

## Testing Strategy

### Unit Tests:
- HwqaSideNav renders correct navigation items
- HwqaSideNav highlights active tab based on route
- HwqaProtectedRoute redirects non-NikolaTeam users
- Permission checks correctly hide/show form components

### Integration Tests:
- Full HWQA navigation flow from Hardware landing page
- URL changes correctly when navigating within HWQA
- Back/forward browser navigation works
- Deep linking to specific HWQA pages works

### Manual Testing Steps:
1. As NikolaTeam + Engineering user: Verify full access to all HWQA features
2. As NikolaTeam without write role: Verify read-only access (no forms visible)
3. As non-NikolaTeam user: Verify redirect away from HWQA
4. Test all HWQA SideNav links navigate correctly
5. Test browser back/forward buttons
6. Test refreshing page on various HWQA routes
7. Test mobile responsive layout
8. Verify main app styling is not affected on non-HWQA pages

## Performance Considerations

- HWQA QueryClient is separate to avoid cache conflicts with main app
- SideNav uses position:fixed to avoid re-renders on scroll
- Route-based code splitting should be maintained for HWQA pages

## Migration Notes

- No database migrations required
- No API changes required
- Feature flag not needed - access controlled by user roles
- Rollback: Revert git commits to restore previous HWQA implementation

## References

- Research document: `thoughts/shared/research/2025-12-02-hwqa-styling-integration-analysis.md`
- CustomerDetail SideNav pattern: `frontend/src/components/CustomerDetailPage/SideNav.tsx`
- HWQA permissions: `frontend/src/hwqa/contexts/AuthContext.tsx:174-178`
- Navigation config: `frontend/src/hooks/useNavLinks.ts:53-76`
