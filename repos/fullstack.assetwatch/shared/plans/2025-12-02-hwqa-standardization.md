# HWQA Standardization Plan

## Overview

Remove HWQA-specific authentication and development infrastructure, standardizing the HWQA module to use the main assetwatch application patterns while preserving the FastAPI backend and HWQA business logic.

## Goals

- Remove duplicate auth infrastructure (HWQA has its own Cognito config, API config)
- Standardize API calls to use main app's Amplify-based adapter
- Keep FastAPI backend structure intact
- Lambda should match assetwatch patterns for user context extraction

## Current State Analysis

### Frontend Files to DELETE (9 files)

| File | Reason |
|------|--------|
| `frontend/src/hwqa/config/api.ts` | Has localhost:3000 fallback, replaced by main amplifyConfig |
| `frontend/src/hwqa/config/auth.ts` | HWQA-specific Cognito config, duplicate of main app |
| `frontend/src/hwqa/config/amplify.ts` | Already deleted - was using wrong auth type |
| `frontend/src/hwqa/services/api.service.ts` | Old service using direct fetch() with Bearer tokens |
| `frontend/src/hwqa/services/auth.service.ts` | HWQA-specific auth service, use main app instead |
| `frontend/src/hwqa/hooks/useAuth.ts` | HWQA-specific auth hook, use main app instead |
| `frontend/src/hwqa/types/auth.types.ts` | HWQA-specific auth types |
| `frontend/src/hwqa/utils/tokenStorage.ts` | Token storage for old auth flow |
| `frontend/src/hwqa/utils/apiHelpers.ts` | Helpers for old API service |

### Service Files to REFACTOR (10+ files)

These files use `apiGet`/`apiPost` from the old api.service.ts and need to use `amplifyApi.service.ts`:

| File | Current Import | New Import |
|------|---------------|------------|
| `services/hub.service.ts` | `api.service.ts` | `amplifyApi.service.ts` |
| `services/sensor.service.ts` | `api.service.ts` | `amplifyApi.service.ts` |
| `services/shipment.service.ts` | `api.service.ts` | `amplifyApi.service.ts` |
| `services/test.service.ts` | `api.service.ts` | `amplifyApi.service.ts` |
| `services/conversion.service.ts` | `api.service.ts` | `amplifyApi.service.ts` |
| `services/user.service.ts` | `api.service.ts` | `amplifyApi.service.ts` |
| Additional services as found | | |

### Lambda Backend Changes

| Change | Details |
|--------|---------|
| Remove `/me` endpoint | `app/routes/auth_routes.py` - duplicates main app functionality |
| Remove dead code | `ALLOWED_COGNITO_GROUPS` constant if unused |
| Update user context | Ensure using `db.get_user_details(event)` pattern from db_resources layer |

### AuthContext Refactoring

Current `frontend/src/hwqa/contexts/AuthContext.tsx`:
- Uses direct `fetch()` with Bearer token for `/me` endpoint
- Has `checkAuthStatus()` that calls localhost:3000/me in dev

New approach:
- Remove `/me` endpoint calls
- Use main app's auth context or adapt to use Amplify's built-in user info
- User info already available from Cognito session

---

## Implementation Phases

### Phase 1: Delete Deprecated Files ✅

**Priority:** High
**Risk:** Low
**Dependencies:** None

Delete the 9 identified files that are no longer needed:

```bash
# Config files
rm frontend/src/hwqa/config/api.ts
rm frontend/src/hwqa/config/auth.ts

# Old services
rm frontend/src/hwqa/services/api.service.ts
rm frontend/src/hwqa/services/auth.service.ts

# Auth-related
rm frontend/src/hwqa/hooks/useAuth.ts
rm frontend/src/hwqa/types/auth.types.ts

# Utils
rm frontend/src/hwqa/utils/tokenStorage.ts
rm frontend/src/hwqa/utils/apiHelpers.ts
```

**Verification:**
- `npm run build` should fail with import errors (expected)
- This identifies all files that need updating

### Phase 2: Update Service Imports ✅

**Priority:** High
**Risk:** Medium
**Dependencies:** Phase 1

For each service file using old `api.service.ts`:

1. Change import from:
   ```typescript
   import { apiGet, apiPost } from './api.service';
   ```
   To:
   ```typescript
   import { apiGet, apiPost } from './amplifyApi.service';
   ```

2. The `amplifyApi.service.ts` already has compatible signatures:
   ```typescript
   export const apiGet = async (path: string, params?: Record<string, any>)
   export const apiPost = async (path: string, body: any)
   ```

**Verification:**
- TypeScript compilation passes
- `npm run build` succeeds

### Phase 3: Refactor AuthContext ✅

**Priority:** High
**Risk:** Medium
**Dependencies:** Phase 2

Update `frontend/src/hwqa/contexts/AuthContext.tsx`:

1. Remove the `/me` endpoint call in `checkAuthStatus()`
2. Get user info from Amplify's `getCurrentUser()` or `fetchUserAttributes()`
3. Remove Bearer token handling
4. Simplify to use existing main app auth state

**Option A - Use Main App AuthContext:**
```typescript
// In HWQA components, import from main app
import { useAuth } from '../../contexts/AuthContext';
```

**Option B - Simplify HWQA AuthContext:**
```typescript
import { getCurrentUser, fetchUserAttributes } from 'aws-amplify/auth';

const checkAuthStatus = async () => {
  try {
    const user = await getCurrentUser();
    const attributes = await fetchUserAttributes();
    setUser({
      email: attributes.email,
      // ... map other attributes
    });
    setIsAuthenticated(true);
  } catch {
    setIsAuthenticated(false);
  }
};
```

**Verification:**
- HWQA pages load without errors
- User info displays correctly
- No requests to localhost:3000

### Phase 4: Lambda Backend Cleanup ✅

**Priority:** Medium
**Risk:** Low
**Dependencies:** Phase 3 (frontend no longer calls /me)

1. **Remove `/me` endpoint:**
   ```python
   # Delete or comment out in app/routes/auth_routes.py
   @router.get("/me")
   async def get_current_user(...):
       ...
   ```

2. **Remove dead code:**
   - Search for `ALLOWED_COGNITO_GROUPS` usage
   - Remove if unused

3. **Verify user context extraction:**
   - Ensure all routes use `db.get_user_details(event)` pattern
   - This extracts user from API Gateway's cognitoAuthenticationProvider

**Verification:**
- Lambda deploys successfully
- All HWQA API endpoints still work
- User context properly extracted in routes

---

## Testing Strategy

### Unit Tests
- Verify service functions work with new imports
- Test AuthContext state management

### Integration Tests
- Test full authentication flow
- Verify API calls use SigV4 (check request headers)
- Verify user context in lambda responses

### Manual Testing Checklist
- [ ] Login to application
- [ ] Navigate to HWQA section
- [ ] Verify user info displays
- [ ] Test hub search/create
- [ ] Test sensor search/create
- [ ] Test shipment import
- [ ] Test conversion functionality
- [ ] Verify no console errors
- [ ] Verify no localhost requests in Network tab

---

## Rollback Plan

If issues arise:

1. **Frontend:** Revert git changes to restore deleted files
2. **Lambda:** Previous version still deployed, rollback via Terraform
3. **Database:** No schema changes, no rollback needed

---

## Success Criteria

1. **No duplicate code:** HWQA uses main app auth/API patterns
2. **Clean build:** `npm run build` succeeds with no warnings
3. **Working auth:** Users can access HWQA with existing login
4. **Working API:** All HWQA API calls succeed via Amplify SigV4
5. **No localhost:** No requests to localhost:3000 in any environment
6. **Lambda matches pattern:** Uses `db.get_user_details(event)` like other lambdas

---

## Timeline Estimate

| Phase | Tasks |
|-------|-------|
| Phase 1 | Delete 9 files |
| Phase 2 | Update ~10 service imports |
| Phase 3 | Refactor AuthContext |
| Phase 4 | Lambda cleanup |
| Testing | Manual + automated verification |

---

## Files Reference

### Keep (Core HWQA Business Logic)
- `frontend/src/hwqa/components/*` - UI components
- `frontend/src/hwqa/pages/*` - Page components
- `frontend/src/hwqa/services/amplifyApi.service.ts` - Already using Amplify
- `lambdas/lf-vero-prod-hwqa/app/services/*` - Business logic services
- `lambdas/lf-vero-prod-hwqa/app/routes/*` - API routes (except auth cleanup)
- `lambdas/lf-vero-prod-hwqa/app/schemas/*` - Pydantic schemas

### Delete (Deprecated Infrastructure)
- Config: `api.ts`, `auth.ts`
- Services: `api.service.ts`, `auth.service.ts`
- Hooks: `useAuth.ts`
- Types: `auth.types.ts`
- Utils: `tokenStorage.ts`, `apiHelpers.ts`

### Refactor
- `AuthContext.tsx` - Remove /me calls, use Amplify auth
- All services using old `api.service.ts`
