---
date: 2025-12-01T12:00:00-05:00
researcher: Claude Code
git_commit: 293d10135d2eda9585854af57711d9219873512e
branch: IWA-14033
repository: fullstack.assetwatch
topic: "HWQA Native Integration Migration Analysis"
tags: [research, codebase, migration, hwqa, iframe-replacement, frontend-integration, backend-integration]
status: complete
last_updated: 2025-12-01
last_updated_by: Claude Code
---

# Research: HWQA Native Integration Migration Analysis

**Date**: 2025-12-01
**Researcher**: Claude Code
**Git Commit**: 293d10135d2eda9585854af57711d9219873512e
**Branch**: IWA-14033
**Repository**: fullstack.assetwatch

## Research Question

What would it take to move all of the frontend and backend code from the hwqa app into the fullstack.assetwatch repo, and have it rendered natively in the assetwatch app, in place of where the iframe is currently?

## Summary

The hwqa application is a hardware quality assurance system built with React 18 + Mantine 7 + FastAPI that can be migrated to run natively within the AssetWatch platform. The migration is **feasible** because:

1. **Database Schema**: All 24 database tables used by hwqa already exist in the AssetWatch database
2. **Technology Overlap**: Both apps use React, Mantine, AWS Amplify/Cognito, and TanStack Query
3. **Shared Authentication**: Both use the same Cognito user pools and role-based access patterns
4. **Similar Patterns**: Both follow service layer patterns for API calls and context-based state management

**Key Migration Challenges**:
- React version upgrade (18.2 → 19.2)
- Mantine version upgrade (7.17 → 8.2.4)
- Router migration (React Router DOM → TanStack Router)
- Backend refactor (FastAPI → Lambda functions with stored procedures)
- API service pattern adaptation

## Detailed Findings

### Current HWQA Architecture

#### Frontend Stack
| Component | Version | Notes |
|-----------|---------|-------|
| React | 18.2.0 | Needs upgrade to 19.2 |
| Mantine | 7.17.0 | Needs upgrade to 8.2.4 |
| React Router DOM | 6.21.3 | Needs migration to TanStack Router |
| TanStack Query | 5.67.1 | Compatible (AssetWatch uses 5.69.0) |
| AWS Amplify | 6.15.3 | Compatible (AssetWatch uses 6.13.2) |
| TypeScript | 5.3.3 | Compatible (AssetWatch uses 5.8.3) |

**Frontend Structure** (`~/repos/hwqa/frontend/src/`):
- 8 page components in `pages/`
- Feature components in `components/features/` (dashboard, tests, shipments, glossary, conversion)
- 3 context providers (Auth, AppState, Theme)
- Service layer in `services/` with 10+ service files
- CSS variables-based theming system.

#### Backend Stack
| Component | Technology | Notes |
|-----------|------------|-------|
| Framework | FastAPI | Needs conversion to Lambda |
| Runtime | Python 3.11+ | Compatible |
| Lambda Adapter | Mangum | Already supports Lambda |
| Database | MySQL (AWS RDS) | Same database as AssetWatch |
| Auth | PyJWT + Cognito | Same approach as AssetWatch |

**API Endpoints** (`~/repos/hwqa/backend/app/routes/`):
- `/sensor/tests/*` - Sensor test CRUD
- `/hub/tests/*` - Hub test CRUD
- `/sensor/shipments/*` - Sensor shipment operations
- `/hub/shipments/*` - Hub shipment operations
- `/sensor/dashboard/*` - Sensor metrics
- `/hub/dashboard/*` - Hub metrics
- `/glossary/*` - Test specifications and failure types
- `/sensor/conversion/*` - Sensor conversion utilities
- `/bulk/*` - Bulk testing operations

### Current iframe Implementation in AssetWatch

**Location**: The iframe embedding is implemented in three key files:

1. **Route Definition** (`/home/aw-jwalker/repos/fullstack.assetwatch/frontend/src/TanStackRoutes.tsx:200-204`):
```typescript
const hwqaRoute = createRoute({
  getParentRoute: () => protectedRoutes,
  path: "/hwqa",
  component: HwqaPage,
});
```

2. **Page Component** (`/home/aw-jwalker/repos/fullstack.assetwatch/frontend/src/pages/HwqaPage.tsx`):
- `getHwqaUrl()` function determines environment-specific URL (lines 9-27)
- Iframe rendered at full viewport height minus header (lines 32-54)
- URLs: `hwqa.assetwatch.com` (prod), `hwqa-qa.qa.assetwatch.com` (qa), `hwqa-dev.dev.assetwatch.com` (dev)

3. **Navigation** (`/home/aw-jwalker/repos/fullstack.assetwatch/frontend/src/pages/HardwareLandingPage.tsx:38-44`):
- `HwqaButton()` component navigates to `/hwqa`
- Available to ContractManufacturer users (line 64) and all users (line 221)

4. **Access Control** (`/home/aw-jwalker/repos/fullstack.assetwatch/frontend/src/components/routes/ProtectedRoute.tsx:28`):
- `/hwqa` is in the allowed paths for ContractManufacturer role

5. **CSP Configuration** (`/home/aw-jwalker/repos/fullstack.assetwatch/terraform/s3-frontend.tf:360`):
- `frame-src` allows all hwqa URLs plus localhost:5174

### Database Table Analysis

**All 24 tables used by hwqa exist in the AssetWatch database**:

#### Core Tables (Already in Use)
- `Receiver`, `Transponder` - Hardware units
- `Part`, `PartRevision`, `Product`, `ProductType` - Part hierarchy
- `Users`, `Users_Roles`, `Roles` - User management
- `HardwareIssue` - Issue tracking
- `MonitoringPoint`, `MonitoringPoint_Receiver` - Monitoring assignments

#### Hardware QA Tables (Created by AssetWatch Migrations)
- `ContractManufacturerShipment` - Shipment records
- `ContractManufacturerShipmentBox` - Boxes within shipments
- `ContractManufacturerShipmentBox_Receiver` - Receivers in boxes
- `ContractManufacturerShipmentBoxReceiverTest` - Receiver test results
- `ContractManufacturerShipmentBox_Transponder` - Transponders in boxes
- `ContractManufacturerShipmentBoxTransponderTest` - Transponder test results
- `HardwareTestPhase` - Test phases (IQA, OQA, etc.)
- `HardwareTestSpecification` - Test specifications
- `HardwareTestFailureTypeReceiver` - Sensor failure types
- `HardwareTestFailureTypeTransponder` - Hub failure types
- `HardwareTestFailureTypeNextStep` - Next step actions

**Key Migrations that created these tables**:
- `V000000234__IWA-9108_CreateHardwareTables.sql`
- `V000000285__IWA_10641_Create_ContractManufacturer_Transponder_Tables.sql`

### Technology Pattern Comparison

#### Authentication Flow (Compatible)
Both applications:
- Use AWS Cognito with OAuth 2.0 PKCE flow
- Extract `cognito_id` from JWT tokens
- Query `Users` table for user details and roles
- Compute role-based permission flags (isEngineering, isContractManufacturer, etc.)

**hwqa AuthContext**: 17 properties
**AssetWatch AuthContext**: 39 properties (superset, includes more role flags)

#### API Service Patterns (Needs Adaptation)

**hwqa Pattern** (REST-style):
```typescript
// services/amplifyApi.service.ts
export const apiGet = async (path: string, params?: Record<string, any>) => {
  const authHeaders = await getAuthHeaders();
  const restOperation = get({ apiName: 'hwqaAPI', path, options: { headers: authHeaders }});
  return { data: await (await restOperation.response).body.json() };
};
```

**AssetWatch Pattern** (Method-based):
```typescript
// shared/api/amplifyAdapter.ts
export const API = {
  post: async (apiName, path, options) => {
    const { body } = await post({ apiName, path, options }).response;
    return await body.json();
  }
};

// Service function
export async function getComponentDetail(componentId: number) {
  return await API.post("apiVeroComponent", "/list", {
    body: { meth: "getComponentDetails", componentId }
  });
}
```

**Key Differences**:
- hwqa: Path-based routing (`/sensor/tests/recent`)
- AssetWatch: Method-based routing (`{ meth: "getTestResults" }` in body)
- hwqa: Manual auth header injection
- AssetWatch: Amplify handles auth automatically

#### Styling Systems (Needs Migration)

**hwqa**: CSS Variables with light/dark mode
```typescript
// cssVariablesResolver.ts - 230 lines
'--bg-surface': '#FFFFFF',
'--text-primary': theme.colors.neutral[1],
```

**AssetWatch**: Direct theme colors (light mode focused)
```typescript
// assetWatchTheme.ts - 56 lines
primaryColor: "primary60",
shadows: { sm: "0px 4px 4px 0px rgba(0, 0, 0, 0.10)" }
```

### Migration Strategy

#### Phase 1: Frontend Migration

**1.1 Upgrade Dependencies**
- Upgrade React 18 → 19 (review breaking changes)
- Upgrade Mantine 7 → 8 (significant API changes in Mantine 8)
- Review component API changes in Mantine 8

**1.2 Migrate Router**
- Convert React Router DOM routes to TanStack Router
- hwqa routes to integrate under protected routes:
  - `/hwqa` → Index route
  - `/hwqa/sensor/dashboard` → Sensor dashboard
  - `/hwqa/hub/dashboard` → Hub dashboard
  - `/hwqa/sensor/tests` → Sensor tests
  - `/hwqa/hub/tests` → Hub tests
  - `/hwqa/sensor/shipments` → Sensor shipments
  - `/hwqa/hub/shipments` → Hub shipments
  - `/hwqa/glossary` → Glossary
  - `/hwqa/sensor/conversion` → Sensor conversion

**1.3 Migrate Components**
- Move page components to `frontend/src/pages/hwqa/`
- Move feature components to `frontend/src/components/hwqa/`
- Adapt to AssetWatch's component organization pattern

**1.4 Migrate Services**
- Create `frontend/src/shared/api/HwqaService.ts`
- Adapt API calls to AssetWatch's `{ meth: "methodName" }` pattern
- Register hwqa API gateway in Amplify config

**1.5 Adapt Styling**
- Remove hwqa's CSS variables resolver
- Map colors to AssetWatch's theme palette
- May need to maintain some hwqa-specific styles

**1.6 Integrate Contexts**
- Use AssetWatch's AuthContext (superset of hwqa's)
- Create hwqa-specific app state context if needed
- Integrate with AssetWatch's existing providers

#### Phase 2: Backend Migration

**2.1 Create Lambda Functions**

Option A: **Single Lambda** (simpler)
- Create `lambdas/lf-vero-prod-hwqa/main.py`
- Route all hwqa endpoints through one handler
- Follow existing AssetWatch lambda patterns

Option B: **Convert FastAPI to Lambda-compatible** (reuse more code)
- Keep FastAPI structure, use Mangum adapter
- Deploy as single Lambda function
- Less code rewrite, but different from AssetWatch patterns

**Recommended: Option A** - Aligns with AssetWatch architecture

**2.2 Create/Update Stored Procedures**
- Many hwqa queries are inline SQL
- Convert to stored procedures following AssetWatch naming: `HWQA_GetTests`, `HWQA_LogTest`, etc.
- Add stored procedures to `mysql/db/procs/`

**2.3 Create API Gateway Specification**
- Create `api/api-vero-hwqa.yaml` following OpenAPI pattern
- Define `/hwqa/list` and `/hwqa/update` paths
- Configure AWS proxy integration

**2.4 Update Terraform**
- Add Lambda function in `terraform/lambdas.tf`
- Add API Gateway resources in `terraform/api-gateway.tf`
- Add base path mapping for `/hwqa`
- Update RBAC policies for ContractManufacturer access

**2.5 Configure Amplify**
- Add `apiVeroHwqa` to `frontend/src/config.ts` gateway map
- Register in Amplify configuration in `index.tsx`

#### Phase 3: Integration & Testing

**3.1 Authentication Integration**
- Ensure ContractManufacturer role can access hwqa routes
- Update `ProtectedRoute.tsx` to handle new route structure
- Verify role-based access on all endpoints

**3.2 Navigation Updates**
- Update `HwqaButton()` to navigate to `/hwqa` (no change if keeping route)
- Update route tree in `TanStackRoutes.tsx`

**3.3 Remove iframe Implementation**
- Replace `HwqaPage.tsx` iframe with native route rendering
- Update/remove CSP frame-src rules
- Clean up environment URL configuration

**3.4 Testing**
- Unit tests for migrated components
- Integration tests for API endpoints
- E2E tests for critical flows

### Effort Estimation

| Phase | Component | Effort | Notes |
|-------|-----------|--------|-------|
| 1.1 | Dependency upgrades | Medium | React/Mantine breaking changes |
| 1.2 | Router migration | Medium | 8 routes to convert |
| 1.3 | Component migration | High | 50+ components |
| 1.4 | Service migration | Medium | 10 service files |
| 1.5 | Styling adaptation | Medium | CSS variables to theme |
| 1.6 | Context integration | Low | Auth already compatible |
| 2.1 | Lambda creation | Medium | New lambda function |
| 2.2 | Stored procedures | High | Convert inline SQL |
| 2.3 | API Gateway | Low | YAML configuration |
| 2.4 | Terraform updates | Low | Infrastructure as code |
| 2.5 | Amplify config | Low | Config file updates |
| 3.x | Testing | Medium | E2E and integration |

**Total Estimated Effort**: 4-6 weeks for a small team

### Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Mantine 7→8 breaking changes | High | Thorough component testing |
| React 18→19 deprecations | Medium | Review migration guide |
| TanStack Router learning curve | Low | Good documentation available |
| Backend pattern mismatch | Medium | Follow existing lambda patterns |
| CSS variables removal | Medium | Create mapping document |
| Performance regression | Medium | Profile before/after |

### Alternatives Considered

1. **Keep iframe, improve integration**: Lower effort but maintains separate deployments
2. **Micro-frontend approach**: Higher complexity, better isolation
3. **Full rewrite in AssetWatch patterns**: Highest effort, cleanest result

**Recommendation**: Direct migration (documented above) balances effort and maintainability.

## Code References

### hwqa Frontend
- Entry point: `/home/aw-jwalker/repos/hwqa/frontend/src/main.tsx`
- Router: `/home/aw-jwalker/repos/hwqa/frontend/src/router.tsx`
- Auth context: `/home/aw-jwalker/repos/hwqa/frontend/src/contexts/AuthContext.tsx`
- API service: `/home/aw-jwalker/repos/hwqa/frontend/src/services/amplifyApi.service.ts`
- Theme: `/home/aw-jwalker/repos/hwqa/frontend/src/styles/themes/mantineTheme.ts`

### hwqa Backend
- Entry point: `/home/aw-jwalker/repos/hwqa/backend/app/main.py`
- Routes: `/home/aw-jwalker/repos/hwqa/backend/app/routes/`
- Services: `/home/aw-jwalker/repos/hwqa/backend/app/services/`
- Schemas: `/home/aw-jwalker/repos/hwqa/backend/app/schemas/`

### AssetWatch Frontend
- Entry point: `/home/aw-jwalker/repos/fullstack.assetwatch/frontend/src/index.tsx`
- Router: `/home/aw-jwalker/repos/fullstack.assetwatch/frontend/src/TanStackRoutes.tsx`
- Auth context: `/home/aw-jwalker/repos/fullstack.assetwatch/frontend/src/contexts/AuthContext.tsx`
- API adapter: `/home/aw-jwalker/repos/fullstack.assetwatch/frontend/src/shared/api/amplifyAdapter.ts`
- Theme: `/home/aw-jwalker/repos/fullstack.assetwatch/frontend/src/styles/assetWatchTheme.ts`

### AssetWatch Backend
- Lambda example: `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/lf-vero-prod-asset/main.py`
- DB layer: `/home/aw-jwalker/repos/fullstack.assetwatch/lambdas/layers/db_resources_311/python/db_resources.py`
- API spec example: `/home/aw-jwalker/repos/fullstack.assetwatch/api/api-vero-asset.yaml`

### iframe Implementation
- Route: `/home/aw-jwalker/repos/fullstack.assetwatch/frontend/src/TanStackRoutes.tsx:200-204`
- Page: `/home/aw-jwalker/repos/fullstack.assetwatch/frontend/src/pages/HwqaPage.tsx`
- Navigation: `/home/aw-jwalker/repos/fullstack.assetwatch/frontend/src/pages/HardwareLandingPage.tsx:38-44`
- Access control: `/home/aw-jwalker/repos/fullstack.assetwatch/frontend/src/components/routes/ProtectedRoute.tsx:28`

## Architecture Documentation

### Current State (iframe)
```
AssetWatch App                    HWQA App (Separate)
┌──────────────────┐             ┌──────────────────┐
│  TanStackRouter  │             │  ReactRouterDOM  │
│       ↓          │             │       ↓          │
│   /hwqa route    │───iframe───▶│   / (index)      │
│   HwqaPage.tsx   │             │   AppLayout      │
│   (iframe only)  │             │   Pages/Features │
└──────────────────┘             └──────────────────┘
         │                                │
         │ Cognito Auth                   │ Cognito Auth
         ↓                                ↓
┌──────────────────┐             ┌──────────────────┐
│  AssetWatch APIs │             │   FastAPI/Mangum │
│  (30+ Lambdas)   │             │   (Single Lambda)│
└──────────────────┘             └──────────────────┘
         │                                │
         └────────────┬───────────────────┘
                      ↓
              ┌──────────────────┐
              │  Shared Database │
              │   (Aurora MySQL) │
              └──────────────────┘
```

### Target State (Native Integration)
```
AssetWatch App (Unified)
┌────────────────────────────────────────┐
│            TanStackRouter              │
│                  ↓                     │
│  ┌────────────┬────────────────────┐   │
│  │ /customers │ /hwqa/*            │   │
│  │ /assets    │ /hwqa/sensor/tests │   │
│  │ /hardware  │ /hwqa/hub/tests    │   │
│  │ ...        │ /hwqa/glossary     │   │
│  └────────────┴────────────────────┘   │
│                  ↓                     │
│  ┌─────────────────────────────────┐   │
│  │   Shared Components & Context   │   │
│  │   (AuthContext, MantineProvider)│   │
│  └─────────────────────────────────┘   │
└────────────────────────────────────────┘
                   │
                   │ Cognito Auth + AWS SigV4
                   ↓
┌────────────────────────────────────────┐
│         AssetWatch APIs                │
│  ┌──────────┬───────────────────────┐  │
│  │ Existing │ lf-vero-prod-hwqa     │  │
│  │ Lambdas  │ (New Lambda)          │  │
│  │ (30+)    │                       │  │
│  └──────────┴───────────────────────┘  │
└────────────────────────────────────────┘
                   │
                   ↓
         ┌──────────────────┐
         │  Shared Database │
         │   (Aurora MySQL) │
         │ (No schema changes)│
         └──────────────────┘
```

## Open Questions

1. **Feature Flag Strategy**: Should the migration be behind a LaunchDarkly flag for gradual rollout?
2. **URL Structure**: Keep `/hwqa/*` routes or integrate into existing `/hardware/*` structure?
3. **Dark Mode**: Should hwqa's dark mode support be maintained in AssetWatch?
4. **Backend Approach**: Single hwqa Lambda or integrate into existing Lambdas by domain?
5. **Deployment Strategy**: Big bang migration or incremental route-by-route?
