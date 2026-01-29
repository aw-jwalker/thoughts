---
date: 2025-12-03T23:07:03-05:00
researcher: Claude
git_commit: 107a6be3d61ac31240bb48e46fc2059c8019d884
branch: db/IWA-14069
repository: fullstack.assetwatch-hwqa-migration
topic: "Refactoring HWQA API layer to match AssetWatch patterns"
tags: [research, codebase, hwqa, api, refactor, amplify]
status: complete
last_updated: 2025-12-03
last_updated_by: Claude
---

# Research: Refactoring HWQA API Layer to Match AssetWatch Patterns

**Date**: 2025-12-03T23:07:03-05:00
**Researcher**: Claude
**Git Commit**: 107a6be3d61ac31240bb48e46fc2059c8019d884
**Branch**: db/IWA-14069
**Repository**: fullstack.assetwatch-hwqa-migration

## Research Question
How should the HWQA API layer be refactored to match the AssetWatch API patterns, and should the inline API calls in LogTestForm be extracted to a service?

## Summary

The HWQA module currently uses a custom `amplifyApi.service.ts` that duplicates functionality already available in the shared `@api/amplifyAdapter`. To align HWQA with the rest of the AssetWatch codebase, this custom service should be removed and all HWQA services should use the shared adapter pattern. Additionally, `LogTestForm.tsx` contains inline API calls that should be extracted to an existing service file (`sensorTestService.ts` or `hubTestService.ts`).

## Detailed Findings

### Current AssetWatch API Pattern

The main AssetWatch application uses a shared adapter at `frontend/src/shared/api/amplifyAdapter.ts`:

```typescript
import { API } from "@api/amplifyAdapter";

// GET request
await API.get("apiVeroSensor", "/list", { queryParams: params });

// POST request
await API.post("apiVeroSensor", "/list", { body: { meth: "getSensorStatus" } });
```

**Key characteristics:**
- Centralized adapter that wraps Amplify v6 with v5-style interface
- API name passed as first parameter (e.g., `"apiVeroSensor"`, `"apiVeroHwqa"`)
- Path as second parameter
- Options object with `body` or `queryParams` as third parameter

### Current HWQA API Pattern

HWQA uses a custom service at `frontend/src/hwqa/services/amplifyApi.service.ts`:

```typescript
import { fetchApi } from './amplifyApi.service';

// GET request
await fetchApi({ method: 'GET', url: '/sensor/tests/recent', params });

// POST request
await fetchApi({ method: 'POST', url: '/sensor/tests/log', data: transformedData });
```

**Key characteristics:**
- Custom adapter duplicating shared functionality
- Hardcoded `apiName: 'apiVeroHwqa'` inside the service
- Different interface (object with `method`, `url`, `data`, `params`)

### LogTestForm Inline API Calls

`LogTestForm.tsx` (lines 141-277) contains four inline API calls that bypass the service layer:

| Function | Endpoint | Purpose |
|----------|----------|---------|
| `fetchShipments()` | `/bulk/{device}s/shipments` | Load shipment dropdown |
| `fetchBoxes()` | `/bulk/{device}s/boxes` | Load box dropdown |
| `loadSerialNumbers()` | `/bulk/{device}s/serials` | Load serial numbers for selection |
| `checkForExistingTests()` | `/{device}/tests/check` | Check for duplicate tests |

**Why LogTestForm is the only component doing this:**

1. **Historical context**: LogTestForm was likely developed with a "get it working" approach, adding API calls inline rather than through services
2. **Bulk operations**: These endpoints (`/bulk/*`) are specific to the bulk loading feature in the test form and weren't abstracted into services
3. **Component-specific logic**: The calls are tightly coupled to component state (shipment selection, box selection)

**Problems with current approach:**
- Violates separation of concerns
- Duplicates API configuration logic
- Makes testing harder (can't easily mock service layer)
- Inconsistent with both HWQA services and AssetWatch patterns

## Code References

- `frontend/src/shared/api/amplifyAdapter.ts:18-42` - Shared AssetWatch API adapter
- `frontend/src/hwqa/services/amplifyApi.service.ts:1-146` - Custom HWQA adapter (to be deleted)
- `frontend/src/hwqa/components/features/tests/LogTestForm.tsx:141-277` - Inline API calls
- `frontend/src/hwqa/services/sensorTestService.ts` - Existing sensor test service
- `frontend/src/hwqa/services/hubTestService.ts` - Existing hub test service
- `frontend/src/config.ts:201-204` - HWQA API configuration (`apiVeroHwqa`)

## Recommended Refactor

### Phase 1: Extract LogTestForm API Calls to Services

Create a new bulk service or extend existing services:

**Option A: Create `bulkService.ts`** (Recommended)
```typescript
// frontend/src/hwqa/services/bulkService.ts
import { API } from "@api/amplifyAdapter";

export const bulkService = {
  async getShipments(deviceType: 'sensor' | 'hub') {
    return API.get("apiVeroHwqa", `/bulk/${deviceType}s/shipments`);
  },

  async getBoxes(deviceType: 'sensor' | 'hub', shipmentId: number) {
    return API.get("apiVeroHwqa", `/bulk/${deviceType}s/boxes`, {
      queryParams: { shipment_id: shipmentId.toString() }
    });
  },

  async getSerials(deviceType: 'sensor' | 'hub', params: { shipment_id?: number; box_id?: number }) {
    return API.get("apiVeroHwqa", `/bulk/${deviceType}s/serials`, { queryParams: params });
  }
};
```

**Option B: Extend existing test services**
Add bulk methods to `sensorTestService.ts` and `hubTestService.ts`.

### Phase 2: Update All HWQA Services

Convert each service from custom adapter to shared adapter:

**Before:**
```typescript
import { fetchApi } from './amplifyApi.service';

async getTests(): Promise<TestResult[]> {
  const response = await fetchApi({
    method: 'GET',
    url: '/sensor/tests/recent',
    params
  });
  return response.data as TestResult[];
}
```

**After:**
```typescript
import { API } from "@api/amplifyAdapter";

async getTests(): Promise<TestResult[]> {
  return API.get("apiVeroHwqa", "/sensor/tests/recent", { queryParams: params });
}
```

### Phase 3: Delete Custom Adapter

Remove `frontend/src/hwqa/services/amplifyApi.service.ts` after all services are updated.

## Files to Modify

| File | Action |
|------|--------|
| `frontend/src/hwqa/services/amplifyApi.service.ts` | Delete |
| `frontend/src/hwqa/services/sensorTestService.ts` | Update imports and calls |
| `frontend/src/hwqa/services/hubTestService.ts` | Update imports and calls |
| `frontend/src/hwqa/services/sensorShipmentService.ts` | Update imports and calls |
| `frontend/src/hwqa/services/hubShipmentService.ts` | Update imports and calls |
| `frontend/src/hwqa/services/sensorDashboardService.ts` | Update imports and calls |
| `frontend/src/hwqa/services/hubDashboardService.ts` | Update imports and calls |
| `frontend/src/hwqa/services/glossaryService.ts` | Update imports and calls |
| `frontend/src/hwqa/services/sensorConversionService.ts` | Update imports and calls |
| `frontend/src/hwqa/services/bulkService.ts` | Create new |
| `frontend/src/hwqa/components/features/tests/LogTestForm.tsx` | Use bulkService |

## Architecture Insights

1. **API Gateway Architecture**: HWQA does NOT have its own API Gateway. It uses the same shared API Gateway as the rest of AssetWatch, just with a different path prefix (`/hwqa`). All services route through `https://api.{branch}.{env}.assetwatch.com/{service-path}`.

2. **Authentication**: Both patterns use the same Cognito Identity Pool for SigV4 signing. The authentication mechanism is identical.

3. **Why the custom adapter exists**: HWQA was originally a standalone application that was migrated into the AssetWatch monorepo. The custom adapter was likely preserved during migration to minimize changes.

## Bug Fixed During Investigation

During this research, a bug was discovered and fixed in `LogTestForm.tsx` where API endpoints were missing leading slashes:

```typescript
// Before (broken):
const endpoint = `bulk/${apiString}s/shipments`;  // → hwqabulk/sensors/shipments

// After (fixed):
const endpoint = `/bulk/${apiString}s/shipments`; // → hwqa/bulk/sensors/shipments
```

This was causing 403 errors because the path concatenated incorrectly with the base URL.

## Open Questions

1. Should the `checkForExistingTests()` functionality be added to the test services, or does it belong in a separate validation service?
2. Are there any other components with inline API calls that should be audited?
3. Should we add PUT and DELETE methods to the shared amplifyAdapter.ts if HWQA needs them?

## Implementation Estimate

- **Phase 1** (Extract LogTestForm calls): ~1 hour
- **Phase 2** (Update all services): ~2 hours
- **Phase 3** (Delete and test): ~30 minutes
- **Total**: ~3.5 hours
