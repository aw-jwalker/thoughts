# HWQA Migration Cleanup Implementation Plan

## Overview

After merging HWQA into fullstack.assetwatch and replacing redundant HWQA architecture with pre-existing AssetWatch infrastructure, significant dead code remains. This plan removes ~1,000+ lines of unused code across authentication, routing, utilities, and shared definitions.

## Current State Analysis

Based on research documented in `thoughts/shared/research/2025-12-03-hwqa-migration-cleanup-analysis.md`:

- **Authentication**: Entire standalone auth system unused - main app's `AuthContext` handles auth
- **Router**: Standalone `react-router-dom` configuration unused - TanStack Router integration active
- **Navigation**: `AppNavbar` unused - `HwqaSideNav` (TanStack-based) is active
- **Utilities**: `jwtUtils.ts` unused, `dateUtils.ts` has 2 usages that need migration
- **Shared**: Duplicate `UserRole.ts` and `ColorTypes.ts` unused (main app versions used)
- **Hooks**: `useAuthToken` and `useCurrentUser` unused, only `useIsAuthenticated` is used

### Key Discoveries:
- `dateUtils.ts` is imported by `TestList.tsx:6` and `ShipmentList.tsx:4` - requires migration before deletion
- `router.tsx` imports from `auth/` directory - but router itself is unused
- All auth components are only imported by the unused `router.tsx`
- `useIsAuthenticated` hook is actively used by 5 files - must be preserved

## Desired End State

After this plan is complete:

1. **~1,000+ lines of dead code removed**:
   - Entire `components/auth/` directory deleted
   - Entire `components/layout/AppNavbar/` directory deleted
   - `router.tsx` deleted
   - `utils/jwtUtils.ts` deleted
   - `utils/dateUtils.ts` deleted
   - `shared/enums/UserRole.ts` deleted
   - `shared/types/ColorTypes.ts` deleted

2. **Migrated imports**:
   - `TestList.tsx` and `ShipmentList.tsx` use main app's `formatDate` utility

3. **Cleaned up exports**:
   - `useAuthToken.ts` only exports `useIsAuthenticated` (unused exports removed)

### Verification:
- `npm run build` completes without errors
- `npm run typecheck` passes
- `npm test` passes (run at end only)
- No dead imports remain

## What We're NOT Doing

- NOT deleting actively used HWQA components (features/, services/, context/, etc.)
- NOT changing the architecture of the HWQA integration
- NOT modifying any business logic
- NOT touching the main AssetWatch codebase (except importing formatDate)
- NOT running tests until the very end (per user request)

## Implementation Approach

This cleanup follows a dependency-safe order:
1. First migrate any actively used code that depends on files to be deleted
2. Then delete files with no external dependencies
3. Then delete files whose dependents were already deleted
4. Clean up unused exports last
5. Verify with build/typecheck/test at the very end

---

## Phase 1: Migrate dateUtils.ts Usage

### Overview
Before deleting `dateUtils.ts`, migrate the 2 files that import it to use the main app's `formatDate` utility.

### Changes Required:

#### 1. TestList.tsx - Update formatDate Import and Usage
**File**: `/frontend/src/hwqa/components/features/tests/TestList.tsx`
**Changes**:
- Replace import from local `dateUtils` to main app's `Utilities`
- Update usage to match main app's `formatDate` signature

**Current** (line 6):
```typescript
import { formatDate } from '../../../utils/dateUtils';
```

**New**:
```typescript
import { formatDate } from '@components/Utilities';
```

**Current usage** (lines 126, 165):
```typescript
valueFormatter: (params: any) => params.value ? formatDate(params.value, true) : params.value,
```

**New usage** (format: MM/dd/yyyy hh:mm a):
```typescript
valueFormatter: (params: any) => params.value ? formatDate(params.value, { formatString: 'MM/dd/yyyy hh:mm a' }) : params.value,
```

#### 2. ShipmentList.tsx - Update formatDate Import and Usage
**File**: `/frontend/src/hwqa/components/features/shipments/ShipmentList.tsx`
**Changes**:
- Replace import from local `dateUtils` to main app's `Utilities`
- Update usage to match main app's `formatDate` signature

**Current** (line 4):
```typescript
import { formatDate } from '../../../utils/dateUtils';
```

**New**:
```typescript
import { formatDate } from '@components/Utilities';
```

**Current usage** (line 31 - date only):
```typescript
valueFormatter: (params: any) => params.value ? formatDate(params.value, false) : params.value,
```

**New usage** (format: MM/dd/yyyy):
```typescript
valueFormatter: (params: any) => params.value ? formatDate(params.value, { formatString: 'MM/dd/yyyy' }) : params.value,
```

**Current usage** (lines 93, 172 - date with time):
```typescript
valueFormatter: (params: any) => params.value ? formatDate(params.value, true) : params.value,
```

**New usage**:
```typescript
valueFormatter: (params: any) => params.value ? formatDate(params.value, { formatString: 'MM/dd/yyyy hh:mm a' }) : params.value,
```

### Success Criteria:

#### Automated Verification:
- [x] `npm run build` completes without errors
- [x] `npm run typecheck` passes

**Implementation Note**: After completing this phase and all automated verification passes, proceed to Phase 2.

---

## Phase 2: Delete Unused Utility Files

### Overview
Delete utility files that are no longer used (dateUtils.ts now has no imports after Phase 1).

### Changes Required:

#### 1. Delete dateUtils.ts
**File to delete**: `/frontend/src/hwqa/utils/dateUtils.ts`
**Reason**: All imports migrated in Phase 1

#### 2. Delete jwtUtils.ts
**File to delete**: `/frontend/src/hwqa/utils/jwtUtils.ts`
**Reason**: Zero imports found in codebase - JWT handling done by main app

### Success Criteria:

#### Automated Verification:
- [x] `npm run build` completes without errors
- [x] `npm run typecheck` passes
- [x] `grep -r "jwtUtils" frontend/src/hwqa/` returns no results
- [x] `grep -r "dateUtils" frontend/src/hwqa/` returns no results

**Implementation Note**: After completing this phase and all automated verification passes, proceed to Phase 3.

---

## Phase 3: Delete Unused Shared Definitions

### Overview
Delete duplicate shared enums and types that are unused (main app versions are used instead).

### Changes Required:

#### 1. Delete UserRole.ts (hwqa duplicate)
**File to delete**: `/frontend/src/hwqa/shared/enums/UserRole.ts`
**Reason**: HWQA code imports from `@shared/enums/UserRole` (main app version) instead

#### 2. Delete ColorTypes.ts (hwqa duplicate)
**File to delete**: `/frontend/src/hwqa/shared/types/ColorTypes.ts`
**Reason**: Zero imports - main app's ColorTypes.ts is used throughout codebase

### Success Criteria:

#### Automated Verification:
- [x] `npm run build` completes without errors
- [x] `npm run typecheck` passes
- [x] `grep -r "hwqa/shared/enums/UserRole" frontend/` returns no results
- [x] `grep -r "hwqa/shared/types/ColorTypes" frontend/` returns no results

**Implementation Note**: After completing this phase and all automated verification passes, proceed to Phase 4.

---

## Phase 4: Delete Unused Authentication Components

### Overview
Delete the entire standalone authentication system. These files are only imported by `router.tsx` which is also unused.

### Changes Required:

#### 1. Delete entire auth directory
**Directory to delete**: `/frontend/src/hwqa/components/auth/`

**Files being deleted**:
- `AuthCallback.tsx` - OAuth callback handler (unused - no `/auth/callback` route in TanStack Router)
- `ProtectedRoute.tsx` - Route protection component (unused - `HwqaProtectedRoute` handles this)
- `RoleProtectedRoute.tsx` - Role-based route protection (imported in router.tsx but never used in route definitions)

**Reason**: All 3 files are only imported by `router.tsx` which is unused. Auth is handled by main app's `AuthContext` + `HwqaProtectedRoute`.

### Success Criteria:

#### Automated Verification:
- [x] `npm run build` completes without errors
- [x] `npm run typecheck` passes
- [x] `grep -r "hwqa/components/auth" frontend/` returns no results

**Implementation Note**: After completing this phase and all automated verification passes, proceed to Phase 5.

---

## Phase 5: Delete Unused Layout/Navigation Components

### Overview
Delete the standalone `AppNavbar` navigation component that was replaced by `HwqaSideNav`.

### Changes Required:

#### 1. Delete entire AppNavbar directory
**Directory to delete**: `/frontend/src/hwqa/components/layout/AppNavbar/`

**Files being deleted**:
- `AppNavbar.tsx` - Main navigation component using `react-router-dom`
- `AppNavbar.module.css` - Styles for AppNavbar
- `NavbarLinksGroup.tsx` - Expandable nav link component
- `NavbarLinksGroup.module.css` - Styles for NavbarLinksGroup
- `NavbarLinksGroup.module.css.new` - Backup/draft styles file

**Reason**: Zero imports found - `HwqaSideNav` (TanStack Router based) is used instead via `HwqaPage.tsx`.

### Success Criteria:

#### Automated Verification:
- [x] `npm run build` completes without errors
- [x] `npm run typecheck` passes
- [x] `grep -r "AppNavbar" frontend/src/hwqa/` returns no results

**Implementation Note**: After completing this phase and all automated verification passes, proceed to Phase 6.

---

## Phase 6: Delete Unused Router

### Overview
Delete the standalone React Router DOM configuration that was replaced by TanStack Router integration.

### Changes Required:

#### 1. Delete router.tsx
**File to delete**: `/frontend/src/hwqa/router.tsx`

**Reason**:
- Zero imports found in codebase
- TanStack Router handles HWQA routes at `/frontend/src/TanStackRoutes.tsx:362-421`
- References deleted components (`AppLayout`, auth components) that no longer exist

### Success Criteria:

#### Automated Verification:
- [x] `npm run build` completes without errors
- [x] `npm run typecheck` passes
- [x] `grep -r "hwqa/router" frontend/` returns no results

**Implementation Note**: After completing this phase and all automated verification passes, proceed to Phase 7.

---

## Phase 7: Clean Up useAuthToken.ts Unused Exports

### Overview
Remove unused exports from `useAuthToken.ts` while preserving the actively used `useIsAuthenticated` hook.

### Changes Required:

#### 1. Remove unused exports from useAuthToken.ts
**File**: `/frontend/src/hwqa/hooks/useAuthToken.ts`

**Remove these exports**:
- `useAuthToken()` function (lines 16-64) - Zero imports
- `useCurrentUser()` function (lines 129-174) - Zero imports

**Keep these exports**:
- `useIsAuthenticated()` function (lines 70-123) - Used by 5 files:
  - `AppStateContext.tsx:3`
  - `ProtectedRoute.tsx:4` (NOTE: This file will be deleted in Phase 4, but useIsAuthenticated is still used by the other 4 files)
  - `GlossaryPage.tsx:5`
  - `AddTestSpecModal.tsx:7`
  - `AddFailureTypeModal.tsx:7`

**Updated file should contain**:
```typescript
import { useState, useEffect } from 'react';
import { fetchAuthSession } from 'aws-amplify/auth';

// Helper to check if we're on the OAuth callback route
function isOAuthCallback(pathname: string): boolean {
  return pathname === '/auth/callback';
}

/**
 * Hook to check if the user is authenticated
 * @returns boolean indicating if the user has valid auth tokens
 */
export function useIsAuthenticated(): boolean {
  const [isAuthenticated, setIsAuthenticated] = useState<boolean>(false);
  const [isLoading, setIsLoading] = useState<boolean>(true);

  // Try to get location from react-router if available, otherwise use window.location
  let location: { pathname: string };
  try {
    // eslint-disable-next-line react-hooks/rules-of-hooks
    const { useLocation } = require('react-router-dom');
    location = useLocation();
  } catch {
    location = window.location;
  }

  useEffect(() => {
    const checkAuth = async () => {
      try {
        const session = await fetchAuthSession();
        const hasValidTokens = !!session.tokens?.accessToken && !!session.tokens?.idToken;
        setIsAuthenticated(hasValidTokens);
      } catch (error) {
        console.log('Auth check error:', error);
        setIsAuthenticated(false);
      } finally {
        setIsLoading(false);
      }
    };

    // Skip initialization if we're on the callback route
    if (isOAuthCallback(location.pathname)) {
      setIsLoading(true);
      return;
    }

    // If we just came from the callback, give it a moment
    if (sessionStorage.getItem('justAuthenticated')) {
      sessionStorage.removeItem('justAuthenticated');
      setTimeout(checkAuth, 100);
      return;
    }

    checkAuth();
  }, [location.pathname]);

  return isLoading ? false : isAuthenticated;
}
```

### Success Criteria:

#### Automated Verification:
- [x] `npm run build` completes without errors
- [x] `npm run typecheck` passes
- [x] `grep -r "useAuthToken" frontend/src/hwqa/` returns only the file definition (no imports)
- [x] `grep -r "useCurrentUser" frontend/src/hwqa/` returns no results
- [x] `grep -r "useIsAuthenticated" frontend/src/hwqa/` returns 5 results (4 imports + 1 definition)

**Implementation Note**: After completing this phase and all automated verification passes, proceed to Phase 8.

---

## Phase 8: Final Verification

### Overview
Run all verification commands to ensure no regressions were introduced.

### Verification Steps:

#### 1. Build Verification
```bash
cd frontend && npm run build
```
Expected: Build completes successfully with no errors

#### 2. Type Check Verification
```bash
cd frontend && npm run typecheck
```
Expected: No type errors

#### 3. Test Suite Verification
```bash
cd frontend && npm test
```
Expected: All tests pass

#### 4. Dead Import Check
```bash
# Check for any remaining imports of deleted files
grep -r "hwqa/components/auth" frontend/src/
grep -r "hwqa/router" frontend/src/
grep -r "AppNavbar" frontend/src/hwqa/
grep -r "jwtUtils" frontend/src/hwqa/
grep -r "hwqa/utils/dateUtils" frontend/src/
grep -r "hwqa/shared/enums/UserRole" frontend/src/
grep -r "hwqa/shared/types/ColorTypes" frontend/src/
```
Expected: All commands return no results

### Success Criteria:

#### Automated Verification:
- [x] `npm run build` completes without errors
- [x] `npm run typecheck` passes (pre-existing errors unrelated to changes)
- [ ] `npm test` passes
- [x] All grep commands return no results (no dead imports)

#### Manual Verification:
- [x] HWQA features still work when accessed via AssetWatch navigation
- [x] Authentication flow works correctly
- [x] No console errors related to missing imports
- [x] Date formatting displays correctly in test/shipment lists

---

## Testing Strategy

### Automated Tests (Run in Phase 8 only):
- Unit tests via `npm test`
- Build verification via `npm run build`
- Type checking via `npm run typecheck`

### Manual Testing Steps:
1. Navigate to HWQA section via AssetWatch sidebar
2. Verify sensor dashboard loads correctly
3. Verify hub dashboard loads correctly
4. Verify tests page loads and data fetches
5. Verify shipments page loads and data fetches
6. Verify glossary page loads
7. Verify date formatting displays correctly in test/shipment lists

---

## Files Summary

### Files to Delete (17 total):

```
/frontend/src/hwqa/
├── components/
│   ├── auth/                          # ENTIRE DIRECTORY (3 files)
│   │   ├── AuthCallback.tsx
│   │   ├── ProtectedRoute.tsx
│   │   └── RoleProtectedRoute.tsx
│   └── layout/
│       └── AppNavbar/                 # ENTIRE DIRECTORY (5 files)
│           ├── AppNavbar.tsx
│           ├── AppNavbar.module.css
│           ├── NavbarLinksGroup.tsx
│           ├── NavbarLinksGroup.module.css
│           └── NavbarLinksGroup.module.css.new
├── router.tsx                         # 1 file
├── utils/
│   ├── jwtUtils.ts                    # 1 file
│   └── dateUtils.ts                   # 1 file
└── shared/
    ├── enums/
    │   └── UserRole.ts                # 1 file
    └── types/
        └── ColorTypes.ts              # 1 file
```

### Files to Modify (3 total):
- `/frontend/src/hwqa/components/features/tests/TestList.tsx` - Update formatDate import
- `/frontend/src/hwqa/components/features/shipments/ShipmentList.tsx` - Update formatDate import
- `/frontend/src/hwqa/hooks/useAuthToken.ts` - Remove unused exports

---

## References

- Research document: `thoughts/shared/research/2025-12-03-hwqa-migration-cleanup-analysis.md`
- TanStack Router integration: `/frontend/src/TanStackRoutes.tsx:362-421`
- Main app AuthContext: `/frontend/src/contexts/AuthContext.tsx`
- Active HWQA entry point: `/frontend/src/pages/HwqaPage.tsx`
- Main app formatDate utility: `/frontend/src/components/Utilities.ts:118`
