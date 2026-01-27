# Implementation Plan: HWQA Minimal Migration

**Date**: 2025-12-01
**Author**: Claude Code
**Research Document**: `thoughts/shared/research/2025-12-01-hwqa-native-integration-migration.md`
**Branch**: TBD

## Problem Summary

The HWQA application currently runs as a separate deployment and is embedded in AssetWatch via an iframe. This creates:
- Deployment complexity (separate CI/CD pipelines)
- Authentication handoff issues
- Limited integration with AssetWatch features
- Maintenance overhead of two separate repos

## Goal

Migrate HWQA code into the AssetWatch repository with **minimal changes**, then gradually refactor to match AssetWatch patterns over time. The key principle is: **copy first, refactor later**.

## Migration Strategy: Minimal Changes

### Core Approach
1. **Add react-router-dom** as dependency (hwqa uses it)
2. **Copy code directly** into namespaced directories
3. **Use MemoryRouter** to nest React Router inside TanStack Router (avoids routing conflicts)
4. **Deploy backend as-is** using Mangum (already Lambda-ready)
5. **Make only essential compatibility changes** (1 prop rename for Mantine 7→8)

### Why This Works
- **React 18 → 19**: Largely backwards compatible, React Router DOM works on both
- **Mantine 7 → 8**: Main breaking change is `spacing` → `gap` prop (only 1 occurrence in hwqa)
- **MemoryRouter**: Standard pattern for nesting React Router in other routers
- **Mangum**: hwqa backend already has `handler = Mangum(app)` - zero backend code changes needed

---

## Phase 1: Frontend Migration

### 1.1 Add react-router-dom Dependency

**File**: `frontend/package.json`

```bash
cd frontend && npm install react-router-dom@6.21.3
```

### 1.2 Copy Frontend Code

Copy hwqa frontend code into namespaced `hwqa/` directory:

```bash
# From fullstack.assetwatch root
mkdir -p frontend/src/hwqa

# Copy directories
cp -r ~/repos/hwqa/frontend/src/components frontend/src/hwqa/
cp -r ~/repos/hwqa/frontend/src/pages frontend/src/hwqa/
cp -r ~/repos/hwqa/frontend/src/services frontend/src/hwqa/
cp -r ~/repos/hwqa/frontend/src/contexts frontend/src/hwqa/
cp -r ~/repos/hwqa/frontend/src/hooks frontend/src/hwqa/
cp -r ~/repos/hwqa/frontend/src/styles frontend/src/hwqa/
cp -r ~/repos/hwqa/frontend/src/utils frontend/src/hwqa/
cp -r ~/repos/hwqa/frontend/src/types frontend/src/hwqa/

# Copy router (needed for MemoryRouter setup)
cp ~/repos/hwqa/frontend/src/router.tsx frontend/src/hwqa/
```

**Files to copy**:
| Source | Destination |
|--------|-------------|
| `hwqa/frontend/src/components/` | `assetwatch/frontend/src/hwqa/components/` |
| `hwqa/frontend/src/pages/` | `assetwatch/frontend/src/hwqa/pages/` |
| `hwqa/frontend/src/services/` | `assetwatch/frontend/src/hwqa/services/` |
| `hwqa/frontend/src/contexts/` | `assetwatch/frontend/src/hwqa/contexts/` |
| `hwqa/frontend/src/hooks/` | `assetwatch/frontend/src/hwqa/hooks/` |
| `hwqa/frontend/src/styles/` | `assetwatch/frontend/src/hwqa/styles/` |
| `hwqa/frontend/src/utils/` | `assetwatch/frontend/src/hwqa/utils/` |
| `hwqa/frontend/src/types/` | `assetwatch/frontend/src/hwqa/types/` |
| `hwqa/frontend/src/router.tsx` | `assetwatch/frontend/src/hwqa/router.tsx` |

### 1.3 Create HwqaApp Wrapper with MemoryRouter

**Create file**: `frontend/src/hwqa/HwqaApp.tsx`

```typescript
import { MemoryRouter } from "react-router-dom";
import { AppRoutes } from "./router"; // hwqa's existing router
import { AppStateProvider } from "./contexts/AppStateContext";
// Note: Use AssetWatch's AuthContext, not hwqa's

interface HwqaAppProps {
  initialPath?: string;
}

export function HwqaApp({ initialPath = "/" }: HwqaAppProps) {
  return (
    <MemoryRouter initialEntries={[initialPath]}>
      <AppStateProvider>
        <AppRoutes />
      </AppStateProvider>
    </MemoryRouter>
  );
}
```

**Key points**:
- `MemoryRouter` keeps hwqa routing isolated (no URL bar conflicts with TanStack)
- `initialPath` allows deep-linking from TanStack routes
- Uses hwqa's existing `AppStateProvider` for hwqa-specific state
- Will use AssetWatch's `AuthContext` (superset of hwqa's)

### 1.4 Update Import Paths in Copied Code

After copying, update import paths from `@/` to relative paths or update the hwqa code to use consistent imports:

**Option A**: Find and replace `@/` imports
```bash
# In frontend/src/hwqa/
find . -type f -name "*.tsx" -o -name "*.ts" | xargs sed -i 's|from "@/|from "./|g'
```

**Option B**: Add path alias in tsconfig.json
```json
{
  "compilerOptions": {
    "paths": {
      "@hwqa/*": ["./src/hwqa/*"]
    }
  }
}
```

### 1.5 Single Required Code Change: Mantine spacing → gap

**File**: `frontend/src/hwqa/components/common/navbar/NavbarLinksGroup.tsx` (line ~41)

```typescript
// Before (Mantine 7)
<Stack spacing="xs">

// After (Mantine 8)
<Stack gap="xs">
```

This is the **only** known breaking change required.

### 1.6 Update TanStack Route to Render HwqaApp

**File**: `frontend/src/TanStackRoutes.tsx`

Replace iframe route with native rendering:

```typescript
// Add import
import { HwqaApp } from "./hwqa/HwqaApp";

// Update route (around line 200-204)
const hwqaRoute = createRoute({
  getParentRoute: () => protectedRoutes,
  path: "/hwqa",
  component: () => <HwqaApp initialPath="/" />,
});

// Add catch-all for hwqa sub-routes
const hwqaSubRoute = createRoute({
  getParentRoute: () => hwqaRoute,
  path: "$",  // Catch all sub-paths
  component: () => {
    const { "*": splat } = useParams({ from: "/hwqa/$" });
    return <HwqaApp initialPath={`/${splat}`} />;
  },
});
```

### 1.7 Update HwqaPage.tsx (Remove iframe)

**File**: `frontend/src/pages/HwqaPage.tsx`

Replace entire file content:

```typescript
import { HwqaApp } from "../hwqa/HwqaApp";

export function HwqaPage() {
  return <HwqaApp />;
}
```

### 1.8 Configure API Gateway for hwqa

**File**: `frontend/src/config.ts`

Add hwqa API gateway configuration:

```typescript
export const apiGatewayIds: Record<string, Record<string, string>> = {
  // ... existing entries
  apiVeroHwqa: {
    dev: "xxxxxxxxxx",   // To be created in Phase 2
    qa: "xxxxxxxxxx",    // To be created in Phase 2
    prod: "xxxxxxxxxx",  // To be created in Phase 2
  },
};
```

### 1.9 Update hwqa API Service

**File**: `frontend/src/hwqa/services/amplifyApi.service.ts`

Update API name to match AssetWatch config:

```typescript
// Before
const restOperation = get({ apiName: 'hwqaAPI', path, options: ... });

// After
const restOperation = get({ apiName: 'apiVeroHwqa', path, options: ... });
```

---

## Phase 2: Backend Migration

### 2.1 Copy Backend Code

Copy hwqa backend directly into a new Lambda directory:

```bash
# From fullstack.assetwatch root
mkdir -p lambdas/lf-vero-prod-hwqa

# Copy entire app directory
cp -r ~/repos/hwqa/backend/app lambdas/lf-vero-prod-hwqa/

# Copy requirements
cp ~/repos/hwqa/backend/requirements.txt lambdas/lf-vero-prod-hwqa/
```

**Directory structure after copy**:
```
lambdas/lf-vero-prod-hwqa/
├── app/
│   ├── main.py           # FastAPI app with Mangum handler
│   ├── routes/           # All API routes
│   ├── services/         # Business logic
│   ├── schemas/          # Pydantic models
│   └── utils/            # Utilities
└── requirements.txt
```

### 2.2 Verify Mangum Handler (No Changes Needed)

**File**: `lambdas/lf-vero-prod-hwqa/app/main.py` (line ~101)

The handler is already defined:
```python
handler = Mangum(app)
```

**No code changes required** - hwqa backend is already Lambda-ready.

### 2.3 Create Terraform for Lambda Function

**File**: `terraform/lambdas.tf`

Add hwqa Lambda definition:

```hcl
# HWQA Lambda Function
resource "aws_lambda_function" "lf_vero_prod_hwqa" {
  function_name = "lf-vero-${var.environment}-hwqa"
  role          = aws_iam_role.lambda_role.arn
  handler       = "app.main.handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.hwqa_lambda_zip.output_path
  source_code_hash = data.archive_file.hwqa_lambda_zip.output_base64sha256

  environment {
    variables = {
      DB_HOST     = var.db_host
      DB_NAME     = var.db_name
      DB_USER     = var.db_user
      DB_PASSWORD = var.db_password
      ENVIRONMENT = var.environment
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  layers = [
    aws_lambda_layer_version.db_resources_311.arn
  ]

  tags = {
    Application = "AssetWatch"
    Component   = "HWQA"
    Environment = var.environment
  }
}

data "archive_file" "hwqa_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/lf-vero-prod-hwqa"
  output_path = "${path.module}/../lambdas/lf-vero-prod-hwqa.zip"
}
```

### 2.4 Create API Gateway Configuration

**File**: `terraform/api-gateway.tf`

Add hwqa API Gateway:

```hcl
# HWQA API Gateway
resource "aws_apigatewayv2_api" "hwqa_api" {
  name          = "api-vero-${var.environment}-hwqa"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.allowed_origins
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "hwqa_lambda" {
  api_id             = aws_apigatewayv2_api.hwqa_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.lf_vero_prod_hwqa.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "hwqa_proxy" {
  api_id    = aws_apigatewayv2_api.hwqa_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.hwqa_lambda.id}"
}

resource "aws_apigatewayv2_stage" "hwqa_default" {
  api_id      = aws_apigatewayv2_api.hwqa_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "hwqa_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lf_vero_prod_hwqa.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.hwqa_api.execution_arn}/*/*"
}

output "hwqa_api_gateway_id" {
  value = aws_apigatewayv2_api.hwqa_api.id
}
```

### 2.5 Add Lambda Dependencies Layer (if needed)

If hwqa has unique dependencies not in existing layers, create a layer:

**File**: `terraform/lambda-layers.tf`

```hcl
resource "aws_lambda_layer_version" "hwqa_dependencies" {
  layer_name          = "hwqa-dependencies-${var.environment}"
  compatible_runtimes = ["python3.11"]
  filename            = data.archive_file.hwqa_layer_zip.output_path
  source_code_hash    = data.archive_file.hwqa_layer_zip.output_base64sha256
}
```

---

## Phase 3: Integration and Cleanup

### 3.1 Wire Up Authentication

hwqa's AuthContext can be **removed** - use AssetWatch's AuthContext instead. AssetWatch's AuthContext is a superset that includes all hwqa's auth properties.

**File**: `frontend/src/hwqa/HwqaApp.tsx`

Update to use AssetWatch's auth:

```typescript
import { useAuth } from "../contexts/AuthContext"; // AssetWatch's context
// Remove: import { AuthProvider } from "./contexts/AuthContext";

export function HwqaApp({ initialPath = "/" }: HwqaAppProps) {
  const auth = useAuth(); // Get auth from AssetWatch

  return (
    <MemoryRouter initialEntries={[initialPath]}>
      <AppStateProvider>
        {/* Pass auth down to hwqa components via props or context */}
        <AppRoutes />
      </AppStateProvider>
    </MemoryRouter>
  );
}
```

### 3.2 Update API Gateway IDs in Config

After Terraform deployment, update:

**File**: `frontend/src/config.ts`

```typescript
apiVeroHwqa: {
  dev: "actual-dev-api-id",
  qa: "actual-qa-api-id",
  prod: "actual-prod-api-id",
},
```

### 3.3 Remove iframe CSP Rules

**File**: `terraform/s3-frontend.tf` (around line 360)

Remove hwqa URLs from `frame-src`:

```hcl
# Before
frame-src 'self' https://hwqa.assetwatch.com https://hwqa-qa.qa.assetwatch.com ...

# After
frame-src 'self' ...  # Remove hwqa URLs
```

### 3.4 Update CI/CD Pipeline

Ensure CI/CD builds and deploys the hwqa Lambda:

1. Add `lambdas/lf-vero-prod-hwqa/` to build process
2. Include pip install for hwqa requirements
3. Deploy to all environments (dev, qa, prod)

### 3.5 Delete Old iframe Implementation

After verification, remove:

```bash
# These files can be simplified or deleted
# frontend/src/pages/HwqaPage.tsx (simplified in Phase 1)
```

---

## Files Modified Summary

### Frontend (Phase 1)
| File | Change |
|------|--------|
| `package.json` | Add `react-router-dom@6.21.3` |
| `src/hwqa/*` | NEW - copied from hwqa repo |
| `src/hwqa/HwqaApp.tsx` | NEW - wrapper with MemoryRouter |
| `src/hwqa/components/common/navbar/NavbarLinksGroup.tsx` | `spacing` → `gap` |
| `src/hwqa/services/amplifyApi.service.ts` | Update API name |
| `src/TanStackRoutes.tsx` | Update route to render HwqaApp |
| `src/pages/HwqaPage.tsx` | Replace iframe with HwqaApp |
| `src/config.ts` | Add apiVeroHwqa gateway |

### Backend (Phase 2)
| File | Change |
|------|--------|
| `lambdas/lf-vero-prod-hwqa/*` | NEW - copied from hwqa repo |
| `terraform/lambdas.tf` | Add hwqa Lambda definition |
| `terraform/api-gateway.tf` | Add hwqa API Gateway |

### Integration (Phase 3)
| File | Change |
|------|--------|
| `terraform/s3-frontend.tf` | Remove iframe CSP rules |

---

## Testing Plan

### Phase 1 Tests (Frontend)
1. **Build succeeds**: `npm run build` completes without errors
2. **TypeScript**: `npm run typecheck` passes
3. **Navigation**: Can navigate to `/hwqa` route
4. **Rendering**: hwqa dashboard renders correctly
5. **Sub-navigation**: Internal hwqa navigation works (sensor/hub tabs, etc.)

### Phase 2 Tests (Backend)
1. **Lambda deploys**: Terraform apply succeeds
2. **API reachable**: Curl test to API Gateway endpoint
3. **Auth works**: Authenticated request returns data
4. **Database**: Queries return correct data from shared database

### Phase 3 Tests (Integration)
1. **End-to-end**: Full user flow from AssetWatch login → hwqa features
2. **All hwqa pages**: Dashboard, tests, shipments, glossary, conversion
3. **CRUD operations**: Create test, update shipment, etc.
4. **Existing features**: AssetWatch features still work correctly

---

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Import path issues after copy | Medium | High | Systematic find/replace, TypeScript will catch errors |
| Mantine 7→8 undiscovered breaks | Medium | Low | Only 1 known issue, TypeScript will flag others |
| API authentication mismatch | High | Low | Both use same Cognito, hwqa's pattern is compatible |
| Performance regression | Low | Low | hwqa is lightweight, native rendering is faster than iframe |

---

## Rollback Plan

If issues occur:
1. **Frontend**: Revert HwqaPage.tsx to iframe implementation
2. **Backend**: Keep hwqa Lambda deployed (doesn't affect iframe)
3. **Full rollback**: Remove hwqa directory, revert package.json

The iframe implementation remains functional until explicitly removed in Phase 3.

---

## Future Refactoring (Out of Scope)

After this minimal migration is stable, consider:
1. Convert React Router routes to TanStack Router (remove MemoryRouter)
2. Migrate hwqa API calls to AssetWatch's `{ meth: "methodName" }` pattern
3. Convert FastAPI backend to Lambda + stored procedures pattern
4. Remove hwqa-specific contexts, use AssetWatch contexts
5. Unify CSS theming (remove hwqa CSS variables)
6. Move hwqa components into main component directories

These are **future improvements**, not part of this migration.

---

## Success Criteria

- [ ] hwqa renders natively in AssetWatch (no iframe)
- [ ] All hwqa features work: dashboard, tests, shipments, glossary, conversion
- [ ] Authentication flows correctly through AssetWatch
- [ ] Backend API calls work with new Lambda
- [ ] No regressions in existing AssetWatch features
- [ ] Build and typecheck pass
