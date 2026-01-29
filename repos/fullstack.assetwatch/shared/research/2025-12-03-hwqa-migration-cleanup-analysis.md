---
date: 2025-12-03T22:23:40-05:00
researcher: Claude Code
git_commit: 29b080008c4f7cf842903ac7c0b486fab1964e98
branch: db/IWA-14069
repository: fullstack.assetwatch-hwqa-migration
topic: "HWQA Migration Cleanup - Identifying Unused Code After AssetWatch Integration"
tags: [research, hwqa, migration, cleanup, dead-code]
status: complete
last_updated: 2025-12-03
last_updated_by: Claude Code
---

# Research: HWQA Migration Cleanup - Identifying Unused Code After AssetWatch Integration

**Date**: 2025-12-03T22:23:40-05:00
**Researcher**: Claude Code
**Git Commit**: 29b080008c4f7cf842903ac7c0b486fab1964e98
**Branch**: db/IWA-14069
**Repository**: fullstack.assetwatch-hwqa-migration

## Research Question
After merging HWQA into fullstack.assetwatch and replacing redundant HWQA architecture with pre-existing AssetWatch infrastructure (navigation, authentication, etc.), identify which HWQA code is no longer needed.

## Summary

The HWQA migration to AssetWatch has left significant dead code that can be safely removed. The analysis identified **~20 files/directories** that are no longer used, primarily:
- The entire standalone authentication system (`components/auth/`)
- The standalone router and navigation components
- Unused hooks and utilities
- Duplicate shared definitions

## Detailed Findings

### 1. Authentication Components - UNUSED (Entire Directory)

**Directory**: `/frontend/src/hwqa/components/auth/`

The entire `auth/` directory is no longer needed. Authentication is now handled by:
- **Main AssetWatch**: `AuthContext` at `/frontend/src/contexts/AuthContext.tsx`
- **HWQA Integration**: `HwqaProtectedRoute` at `/frontend/src/hwqa/components/HwqaProtectedRoute.tsx` (uses main AuthContext)

| File | Status | Reason |
|------|--------|--------|
| `ProtectedRoute.tsx` | **UNUSED** | TanStack Router handles protection; routes use `HwqaProtectedRoute` from main app integration |
| `RoleProtectedRoute.tsx` | **UNUSED** | Imported in `router.tsx` but **never actually used** in any route definition |
| `AuthCallback.tsx` | **UNUSED** | No `/auth/callback` route exists in TanStack Router integration |

**Evidence**:
- No files outside hwqa/auth import from these components
- TanStack Router at `/frontend/src/TanStackRoutes.tsx` handles HWQA routes (lines 362-421)
- `HwqaProtectedRoute` wraps content at `/frontend/src/pages/HwqaPage.tsx:72`

---

### 2. Standalone Router - UNUSED

**File**: `/frontend/src/hwqa/router.tsx`

This entire file is **not imported anywhere**. The standalone React Router DOM configuration has been completely replaced by TanStack Router integration.

**What it contains**:
- `createBrowserRouter` from `react-router-dom`
- Routes for `/auth/callback`, all sensor routes, all hub routes, glossary
- References `AppLayout` component (which doesn't exist)

**Evidence**: Grep for imports of `hwqa/router` returns zero results.

---

### 3. Layout Components - UNUSED (Associated with Standalone Router)

**Directory**: `/frontend/src/hwqa/components/layout/AppNavbar/`

| File | Status | Reason |
|------|--------|--------|
| `AppNavbar.tsx` | **UNUSED** | Uses `react-router-dom`; only used by standalone app (not integrated) |
| `NavbarLinksGroup.tsx` | **UNUSED** | Part of AppNavbar system |
| `NavbarLinksGroup.module.css` | **UNUSED** | Styles for unused component |
| `NavbarLinksGroup.module.css.new` | **UNUSED** | Appears to be a backup file |

**Active Navigation**: HWQA uses `HwqaSideNav` at `/frontend/src/hwqa/components/HwqaSideNav/HwqaSideNav.tsx` which uses `@tanstack/react-router`.

**Evidence**:
- `AppNavbar` uses paths without `/hwqa/` prefix (e.g., `/sensor/dashboard`)
- `HwqaSideNav` uses paths with `/hwqa/` prefix (e.g., `/hwqa/sensor/dashboard`)
- `HwqaPage.tsx` imports and uses `HwqaSideNav`, not `AppNavbar`

---

### 4. Hooks - PARTIALLY UNUSED

**File**: `/frontend/src/hwqa/hooks/useAuthToken.ts`

| Export | Status | Reason |
|--------|--------|--------|
| `useAuthToken()` | **UNUSED** | Zero imports found in codebase |
| `useIsAuthenticated()` | **USED** | Imported by AppStateContext, GlossaryPage, AddFailureTypeModal, AddTestSpecModal |
| `useCurrentUser()` | **UNUSED** | Zero imports found in codebase |

**Recommendation**: Keep file but consider removing unused exports (`useAuthToken`, `useCurrentUser`).

---

### 5. Utilities - UNUSED

**File**: `/frontend/src/hwqa/utils/jwtUtils.ts`
- **Status**: **UNUSED**
- **Contains**: JWT decoding utilities (`decodeJWT`, `getUserDisplayName`, `getUserEmail`, etc.)
- **Evidence**: Zero imports found in codebase

**File**: `/frontend/src/hwqa/utils/dateUtils.ts`
- **Status**: **UNUSED**
- **Contains**: `formatDate()` function
- **Evidence**: Zero imports found in hwqa directory

---

### 6. Shared Directory - PARTIALLY UNUSED

**Directory**: `/frontend/src/hwqa/shared/`

| File | Status | Reason |
|------|--------|--------|
| `enums/UserRole.ts` | **UNUSED** | HWQA code imports from main `@shared/enums/UserRole` instead |
| `enums/ProductType.ts` | **USED** | Imported by 6 files |
| `enums/TestResultStatus.ts` | **USED** | Imported by 2 files |
| `enums/TestAction.ts` | **USED** | Imported by 2 files |
| `enums/TestCheckOutcome.ts` | **USED** | Imported by 1 file |
| `types/ColorTypes.ts` | **UNUSED** | Zero imports found anywhere |

**Evidence for UserRole**: `HwqaProtectedRoute.tsx:3` imports from `@shared/enums/UserRole`, not from local hwqa/shared.

---

## Files Safe to Delete

### High Confidence - Remove Entirely

```
/frontend/src/hwqa/
├── components/
│   ├── auth/                          # ENTIRE DIRECTORY
│   │   ├── AuthCallback.tsx
│   │   ├── ProtectedRoute.tsx
│   │   └── RoleProtectedRoute.tsx
│   └── layout/
│       └── AppNavbar/                 # ENTIRE DIRECTORY
│           ├── AppNavbar.tsx
│           ├── NavbarLinksGroup.tsx
│           ├── NavbarLinksGroup.module.css
│           └── NavbarLinksGroup.module.css.new
├── router.tsx                         # Standalone router
├── utils/
│   ├── jwtUtils.ts
│   └── dateUtils.ts
└── shared/
    ├── enums/
    │   └── UserRole.ts                # Duplicate of main shared
    └── types/
        └── ColorTypes.ts
```

### Medium Confidence - Remove Exports Only

**File**: `/frontend/src/hwqa/hooks/useAuthToken.ts`
- Keep: `useIsAuthenticated()` (actively used)
- Remove: `useAuthToken()`, `useCurrentUser()` (unused exports)

---

## Code References

### Files Still Actively Used (Keep These)

**Components**:
- `HwqaProtectedRoute.tsx` - Main app integration auth wrapper
- `HwqaSideNav/` - TanStack Router navigation
- `features/` - All feature components (dashboard, tests, shipments, etc.)
- `common/` - Shared UI components (Modal, CSVExportButton, etc.)
- `layout/PageContainer/` - Page wrapper component
- `layout/NonProdEnvironmentInfo.tsx` - Environment indicator

**Services** (all used):
- `amplifyApi.service.ts` - Base API layer
- `*DashboardService.ts` - Dashboard metrics
- `*TestService.ts` - Test operations
- `*ShipmentService.ts` - Shipment operations
- `glossaryService.ts` - Glossary data
- `sensorConversionService.ts` - Sensor conversion

**Hooks** (used):
- `useMetricsQuery.ts` - Dashboard metrics hook
- `useIsAuthenticated()` in `useAuthToken.ts` - Auth state check

**Context**:
- `AppStateContext.tsx` - HWQA state management

**Utils** (used):
- `csvExport.ts` - CSV export functionality
- `dashboardTransformers.ts` - Dashboard data transformation
- `environment.ts` - Environment detection
- `textSimilarity.ts` - Fuzzy matching for glossary

**Types/Constants/Enums** (used):
- `types/api.ts` - All API types (heavily used - 44 import locations)
- `constants/dashboardDefaults.ts` - Default filters
- `enums/HwqaTab.ts` - Navigation tab enum
- `shared/enums/ProductType.ts` - Product type enum
- `shared/enums/Test*.ts` - Test-related enums

---

## Architecture Documentation

### Current HWQA Integration Pattern

```
AssetWatch App (TanStack Router)
└── /hwqa route (TanStackRoutes.tsx:362-366)
    └── HwqaPage.tsx
        └── HwqaProtectedRoute (checks NIKOLA_TEAM via main AuthContext)
            └── QueryClientProvider (separate hwqaQueryClient)
                └── AppStateProvider (HWQA state management)
                    └── HwqaSideNav + Outlet (child routes)
                        └── Child pages (SensorDashboard, HubTests, etc.)
```

### What Was Replaced

| Original HWQA | Replaced By |
|---------------|-------------|
| Standalone `router.tsx` | TanStack Router in `TanStackRoutes.tsx` |
| `components/auth/ProtectedRoute` | Main app's protected route + `HwqaProtectedRoute` |
| `components/layout/AppNavbar` | `HwqaSideNav` |
| Direct Amplify OAuth flow | Main app's `AuthContext` authentication |
| `useAuthToken` hook | Main app's auth (session managed by AuthContext) |

---

## Impact Assessment

### Estimated Lines of Code to Remove
- `components/auth/` - ~400 lines
- `components/layout/AppNavbar/` - ~300 lines
- `router.tsx` - ~70 lines
- `utils/jwtUtils.ts` - ~125 lines
- `utils/dateUtils.ts` - ~25 lines
- `shared/enums/UserRole.ts` - ~12 lines
- `shared/types/ColorTypes.ts` - ~72 lines

**Total**: ~1,000+ lines of dead code

### Risk Assessment
- **Low Risk**: All identified files have zero import references
- **Testing**: Run `npm run build` and `npm test` after removal to verify no breakage
- **Rollback**: Git history preserves all removed code if needed

---

## Open Questions

1. **AppLayout Reference**: `router.tsx` imports `AppLayout` from `./components/layout/AppLayout/AppLayout` but this file doesn't exist. Was it already deleted, or was the migration incomplete?

2. **Environment.ts Duplication**: Both HWQA and main AssetWatch have environment detection utilities. Consider whether HWQA should use the main shared version instead.

3. **ColorTypes Migration**: Main AssetWatch's `ColorTypes.ts` has TODO comments about migrating HWQA to AssetWatch's color system. The unused hwqa ColorTypes may be remnant of pre-migration code.

---

## Recommended Next Steps

1. **Verify with build**: Before deleting, run `npm run build` to confirm no hidden dependencies
2. **Delete files**: Remove all files listed in "High Confidence - Remove Entirely" section
3. **Clean up exports**: Remove unused exports from `useAuthToken.ts`
4. **Update imports**: Ensure no dead imports remain after file deletion
5. **Run tests**: Execute full test suite to verify no regressions
