# HWQA API Layer Refactor Implementation Plan

## Overview

Refactor the HWQA API layer to match AssetWatch patterns by:
1. Creating a new `bulkService.ts` for bulk operations currently inline in `LogTestForm.tsx`
2. Updating all HWQA services to use the shared `@api/amplifyAdapter` instead of the custom `amplifyApi.service.ts`
3. Deleting the custom `amplifyApi.service.ts` adapter

## Current State Analysis

### Custom HWQA Adapter (`frontend/src/hwqa/services/amplifyApi.service.ts`)
- Wraps Amplify v6 API calls with custom interface
- Hardcodes `apiName: 'apiVeroHwqa'`
- Returns responses wrapped in `{ data: json }` format
- Has PUT/DELETE methods that are **never used**
- 146 lines of code that duplicates shared functionality

### Shared Adapter (`frontend/src/shared/api/amplifyAdapter.ts`)
- Uses v5-style interface: `API.get(apiName, path, options)`
- Returns JSON directly (not wrapped)
- Has `get`, `post`, and `aiChatPost` methods
- Used consistently across all other AssetWatch services

### LogTestForm Inline API Calls (`frontend/src/hwqa/components/features/tests/LogTestForm.tsx:141-277`)
- 4 inline API functions: `fetchShipments()`, `fetchBoxes()`, `loadSerialNumbers()`, `checkForExistingTests()`
- Bypass service layer, making code harder to test and maintain
- Should be extracted to a new `bulkService.ts`

### Key Discoveries
- **No PUT/DELETE usage**: The custom adapter defines PUT and DELETE methods, but no HWQA code uses them
- **Response format difference**: Custom adapter returns `{ data: json }`, shared adapter returns `json` directly
- **62 occurrences** of `response.data` across 11 files need updating to `response`

## Desired End State

After implementation:
1. All HWQA services use `import { API } from "@api/amplifyAdapter"`
2. Custom `amplifyApi.service.ts` is deleted
3. `LogTestForm.tsx` uses `bulkService` for all API calls
4. Response handling uses direct JSON format (not wrapped in `{ data: ... }`)
5. All tests pass and functionality works identically

### Verification Commands
```bash
cd frontend && npm run typecheck    # TypeScript compilation
cd frontend && npm run lint         # Linting passes
cd frontend && npm test             # All tests pass
```

## What We're NOT Doing

- Adding PUT or DELETE methods to shared adapter (not needed)
- Modifying shared adapter response format (would affect other apps)
- Changing any API endpoints or backend logic
- Refactoring error handling patterns (keep existing patterns)

## Implementation Approach

**Strategy**: Update services one-by-one, keeping the custom adapter until all services are migrated, then delete it. This allows incremental testing.

**Key transformations**:
1. Import: `import { fetchApi } from './amplifyApi.service'` → `import { API } from "@api/amplifyAdapter"`
2. GET calls: `fetchApi({ method: 'GET', url: path, params })` → `API.get("apiVeroHwqa", path, { queryParams: params })`
3. POST calls: `fetchApi({ method: 'POST', url: path, data })` → `API.post("apiVeroHwqa", path, { body: data })`
4. Response access: `response.data` → `response`

---

## Phase 1: Create bulkService.ts

### Overview
Extract inline API calls from LogTestForm.tsx into a new service file.

### Changes Required:

#### 1. Create new service file
**File**: `frontend/src/hwqa/services/bulkService.ts`
**Action**: Create new file

```typescript
import { API } from "@api/amplifyAdapter";

export interface ShipmentDate {
  id: number;
  date_shipped: string;
  device_count: number;
}

export interface BoxLabel {
  id: number;
  box_label: string;
  device_count: number;
}

export interface SerialNumber {
  serial_number: string;
}

export interface TestCheckRequest {
  serial_number: string;
  test_phase: string;
  test_spec: string;
  failure_type: string;
  pass_flag: boolean;
}

export interface TestCheckResult {
  status: string;
  serial_number: string;
  message?: string;
}

export const bulkService = {
  async getShipments(deviceType: 'sensor' | 'hub'): Promise<ShipmentDate[]> {
    return API.get("apiVeroHwqa", `/bulk/${deviceType}s/shipments`);
  },

  async getBoxes(deviceType: 'sensor' | 'hub', shipmentId: number): Promise<BoxLabel[]> {
    return API.get("apiVeroHwqa", `/bulk/${deviceType}s/boxes`, {
      queryParams: { shipment_id: shipmentId.toString() }
    });
  },

  async getSerials(
    deviceType: 'sensor' | 'hub',
    params: { shipment_id?: number; box_id?: number }
  ): Promise<SerialNumber[]> {
    const queryParams: Record<string, string> = {};
    if (params.shipment_id) queryParams.shipment_id = params.shipment_id.toString();
    if (params.box_id) queryParams.box_id = params.box_id.toString();

    return API.get("apiVeroHwqa", `/bulk/${deviceType}s/serials`, { queryParams });
  },

  async checkForExistingTests(
    deviceType: 'sensor' | 'hub',
    data: TestCheckRequest
  ): Promise<{ results: TestCheckResult[] }> {
    return API.post("apiVeroHwqa", `/${deviceType}/tests/check`, { body: data });
  }
};
```

#### 2. Update LogTestForm.tsx
**File**: `frontend/src/hwqa/components/features/tests/LogTestForm.tsx`
**Changes**: Replace inline API calls with bulkService

**Import change (line 16):**
```typescript
// Remove this:
import { fetchApi } from '../../../services/amplifyApi.service';

// Add this:
import { bulkService } from '../../../services/bulkService';
```

**Remove local interfaces (lines 39-53):**
Delete the local `ShipmentDate`, `BoxLabel`, and `SerialNumber` interfaces (now in bulkService).

**Replace fetchShipments (lines 141-158):**
```typescript
const fetchShipments = async () => {
  setIsLoadingShipments(true);
  try {
    const deviceType = productType === ProductType.HUB ? 'hub' : 'sensor';
    const shipments = await bulkService.getShipments(deviceType);
    setShipments(shipments);
  } catch (error: any) {
    console.error("Error fetching shipments:", error);
    showError(
      `Error loading shipments: ${error.response?.data?.detail || error.message || "Unknown error"}`,
    );
    setShipments([]);
  } finally {
    setIsLoadingShipments(false);
  }
};
```

**Replace fetchBoxes (lines 161-179):**
```typescript
const fetchBoxes = async (shipmentId: number) => {
  setIsLoadingBoxes(true);
  try {
    const deviceType = productType === ProductType.HUB ? 'hub' : 'sensor';
    const boxes = await bulkService.getBoxes(deviceType, shipmentId);
    setBoxes(boxes);
  } catch (error: any) {
    console.error("Error fetching boxes:", error);
    showError(
      `Error loading boxes: ${error.response?.data?.detail || error.message || "Unknown error"}`,
    );
    setBoxes([]);
  } finally {
    setIsLoadingBoxes(false);
  }
};
```

**Replace loadSerialNumbers (lines 181-216):**
```typescript
const loadSerialNumbers = async () => {
  setIsLoadingSerials(true);
  try {
    const deviceType = productType === ProductType.HUB ? 'hub' : 'sensor';
    const params: { shipment_id?: number; box_id?: number } = {};

    if (selectedBoxId) {
      params.box_id = selectedBoxId;
    } else if (selectedShipmentId) {
      params.shipment_id = selectedShipmentId;
    } else {
      return;
    }

    const serialData = await bulkService.getSerials(deviceType, params);
    const serials = serialData.map(item => item.serial_number).join("\n");

    if (serials.length === 0) {
      showError("No serial numbers found for the selected criteria");
    } else {
      form.setFieldValue("serialNumbers", serials);
      showSuccess(`Successfully loaded ${serialData.length} serial numbers`);
    }
  } catch (error: any) {
    console.error("Error loading serial numbers:", error);
    showError(
      `Error loading serial numbers: ${error.response?.data?.detail || error.message || "Unknown error"}`,
    );
  } finally {
    setIsLoadingSerials(false);
  }
};
```

**Replace checkForExistingTests (lines 218-278):**
```typescript
const checkForExistingTests = async (): Promise<TestCheckResult> => {
  const errors: Record<string, string> = {};
  if (!form.values.testPhase) errors.testPhase = "Test phase is required";
  if (!form.values.testSpec) errors.testSpec = "Test spec is required";

  if (Object.keys(errors).length > 0) {
    form.setErrors(errors);
    throw new Error("Validation failed");
  }

  const serials = form.values.serialNumbers
    .split(/[\s,\n]+/)
    .map((s) => s.trim())
    .filter((s) => s.length >= 7)
    .map((s) => s.slice(-7))
    .filter((s, i, arr) => arr.indexOf(s) === i);

  if (serials.length === 0) {
    showError("Please enter at least one valid serial number");
    throw new Error("No valid serial numbers");
  }

  setIsCheckingTests(true);
  try {
    const deviceType = productType === ProductType.HUB ? 'hub' : 'sensor';
    const response = await bulkService.checkForExistingTests(deviceType, {
      serial_number: serials.join(","),
      test_phase: form.values.testPhase,
      test_spec: form.values.testSpec,
      failure_type: form.values.failureType || "None",
      pass_flag: form.values.failureType === "None" || !form.values.failureType,
    });

    const results = response.results;

    if (results.some((result: any) => result.status === TestResultStatus.EXISTS)) {
      setTestResultsToConfirm(results);
      setPendingSerials(serials);
      setIsSequentialModalOpen(true);
      return { outcome: TestCheckOutcome.NEEDS_CONFIRMATION, serials };
    }

    return { outcome: TestCheckOutcome.PROCEED, serials };
  } catch (err: any) {
    console.error("Error checking for existing tests:", err);
    const errorMessage =
      err.message ||
      err.response?.data?.message ||
      err.response?.data?.detail ||
      "Failed to check for existing tests. Please try again.";

    showError(errorMessage);
    throw err;
  } finally {
    setIsCheckingTests(false);
  }
};
```

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npm run typecheck`
- [ ] Linting passes: `cd frontend && npm run lint`
- [ ] Tests pass: `cd frontend && npm test`
- [ ] No imports of `amplifyApi.service` in LogTestForm.tsx

#### Manual Verification:
- [ ] Navigate to HWQA > Log Test
- [ ] Select product type (Sensor/Hub)
- [ ] Shipment dropdown loads correctly
- [ ] Box dropdown loads after selecting shipment
- [ ] "Load Serial Numbers" button populates textarea
- [ ] Test submission checks for existing tests correctly

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: Update HWQA Services to Use Shared Adapter

### Overview
Update all 8 HWQA service files to use the shared `@api/amplifyAdapter`.

### Files to Update:

| File | API Calls | Complexity |
|------|-----------|------------|
| `sensorTestService.ts` | 5 | Medium |
| `hubTestService.ts` | 5 | Medium |
| `sensorShipmentService.ts` | 3 | Medium |
| `hubShipmentService.ts` | 3 | Medium |
| `sensorDashboardService.ts` | 2 | Low |
| `hubDashboardService.ts` | 2 | Low |
| `glossaryService.ts` | 5 | Medium |
| `sensorConversionService.ts` | 3 | Medium |

### Transformation Pattern:

**Import change:**
```typescript
// Before:
import { fetchApi } from './amplifyApi.service';

// After:
import { API } from "@api/amplifyAdapter";
```

**GET request transformation:**
```typescript
// Before:
const response = await fetchApi({
  method: 'GET',
  url: '/sensor/tests/recent',
  params
});
return response.data as TestResult[];

// After:
const response = await API.get<TestResult[]>("apiVeroHwqa", "/sensor/tests/recent", {
  queryParams: params
});
return response;
```

**POST request transformation:**
```typescript
// Before:
const response = await fetchApi({
  method: 'POST',
  url: '/sensor/tests/log',
  data: transformedData
});
return response.data;

// After:
const response = await API.post("apiVeroHwqa", "/sensor/tests/log", {
  body: transformedData
});
return response;
```

### Changes Required:

#### 1. sensorTestService.ts
**File**: `frontend/src/hwqa/services/sensorTestService.ts`

```typescript
import { DropdownOption, LogTestData, TestLogResult, TestResult } from '../types/api';
import { API } from "@api/amplifyAdapter";

export const sensorTestService = {
  async getTests(serialNumbers?: string[], limit?: number): Promise<TestResult[]> {
    try {
      const queryParams: Record<string, string> = {};
      if (serialNumbers?.length) {
        queryParams.serial_numbers = serialNumbers.join(',');
      }
      if (limit !== undefined && limit > 0) {
        queryParams.limit = limit.toString();
      }
      const response = await API.get<TestResult[]>("apiVeroHwqa", "/sensor/tests/recent", {
        queryParams: Object.keys(queryParams).length > 0 ? queryParams : undefined
      });

      if (!response || (response as any[]).length === 0) {
        return [];
      }

      return response;
    } catch (error: any) {
      if (error.response?.data?.detail) {
        const detail = error.response.data.detail;
        if (Array.isArray(detail)) {
          const errorMessage = detail.map(err => {
            const serial = err.loc?.[1] || 'Unknown';
            return `Serial ${serial}: ${err.msg}`;
          }).join('\n');
          throw new Error(errorMessage);
        } else if (typeof detail === 'string') {
          throw new Error(detail);
        }
      }

      console.error('Failed to fetch sensor tests:', error);
      throw new Error('Failed to fetch sensor test results. Please try again.');
    }
  },

  async logTest(data: LogTestData): Promise<{ results: TestLogResult[] }> {
    try {
      const transformedData = {
        serial_number: data.serialNumbers.join(','),
        test_phase: data.testPhase,
        test_spec: data.testSpec,
        failure_type: data.failureType,
        pass_flag: data.failureType === 'None'
      };

      return await API.post<{ results: TestLogResult[] }>("apiVeroHwqa", "/sensor/tests/log", {
        body: transformedData
      });
    } catch (error: any) {
      if (error.response?.data?.detail) {
        const detail = error.response.data.detail;
        if (Array.isArray(detail)) {
          throw new Error(detail[0].msg);
        } else {
          throw new Error(detail);
        }
      }
      throw new Error('Failed to log sensor test. Please check the serial number and try again.');
    }
  },

  async fetchTestPhases(): Promise<DropdownOption[]> {
    try {
      return await API.get<DropdownOption[]>("apiVeroHwqa", "/sensor/tests/phases");
    } catch (error) {
      console.error('Failed to fetch sensor test phases:', error);
      throw error;
    }
  },

  async fetchTestSpecs(): Promise<DropdownOption[]> {
    try {
      return await API.get<DropdownOption[]>("apiVeroHwqa", "/sensor/tests/specs");
    } catch (error) {
      console.error('Failed to fetch sensor test specs:', error);
      throw error;
    }
  },

  async fetchFailureTypes(): Promise<DropdownOption[]> {
    try {
      return await API.get<DropdownOption[]>("apiVeroHwqa", "/sensor/tests/failure-types");
    } catch (error) {
      console.error('Failed to fetch sensor failure types:', error);
      throw error;
    }
  }
};
```

#### 2. hubTestService.ts
**File**: `frontend/src/hwqa/services/hubTestService.ts`
**Changes**: Same pattern as sensorTestService, replace `/sensor/` with `/hub/`

#### 3. sensorShipmentService.ts
**File**: `frontend/src/hwqa/services/sensorShipmentService.ts`

```typescript
import { ImportResult, ShipmentData, ShipmentGroup, ValidationResponse } from '../types/api';
import { API } from "@api/amplifyAdapter";

export const sensorShipmentService = {
  async getShipments(): Promise<ShipmentGroup[]> {
    try {
      const response = await API.get<any[]>("apiVeroHwqa", "/sensor/shipments/recent");

      if (!Array.isArray(response)) {
        console.error('Expected array response but got:', typeof response);
        return [];
      }

      const mappedResponse = response.map((group: any) => {
        const shipmentInfo = group.shipmentInfo || {};
        const boxes = Array.isArray(group.boxes) ? group.boxes : [];

        return {
          ...group,
          shipmentInfo: {
            ...shipmentInfo,
            totalUnits: shipmentInfo.totalUnits !== undefined
              ? shipmentInfo.totalUnits
              : (shipmentInfo.totalUnits || 0)
          },
          boxes: boxes.map((box: any) => {
            const safeBox = box || {};
            return {
              ...safeBox,
              unitCount: safeBox.sensorCount !== undefined
                ? safeBox.sensorCount
                : (safeBox.unitCount || 0)
            };
          })
        };
      });

      return mappedResponse;
    } catch (error: any) {
      console.error('Error in getShipments:', error);

      if (error.message === 'Network Error') {
        throw new Error('Unable to connect to the server. Please check your internet connection and try again.');
      }

      if (error.response) {
        if (error.response.status === 404) {
          throw new Error('The shipments endpoint was not found. Please contact support.');
        }

        if (error.response.status === 500) {
          throw new Error('The server encountered an error. Please try again later or contact support.');
        }

        if (error.response?.data?.detail) {
          const detail = error.response.data.detail;
          if (Array.isArray(detail)) {
            throw new Error(detail[0].msg);
          } else {
            throw new Error(detail);
          }
        }
      }

      throw new Error('Failed to fetch sensor shipments. Please try again.');
    }
  },

  async validateShipment(data: ShipmentData): Promise<ValidationResponse> {
    try {
      const response = await API.post<any>("apiVeroHwqa", "/sensor/shipments/validate-shipment", {
        body: data
      });

      const mappedResponse = {
        ...response,
        totalUnits: response.totalSensors !== undefined ? response.totalSensors : (response.totalUnits || 0),
        shipments: response.shipments
          ? response.shipments.map((group: any) => {
            const shipmentInfo = group.shipmentInfo || {};
            const boxes = Array.isArray(group.boxes) ? group.boxes : [];

            return {
              ...group,
              shipmentInfo: {
                ...shipmentInfo,
                totalUnits: shipmentInfo.totalSensors !== undefined
                  ? shipmentInfo.totalSensors
                  : (shipmentInfo.totalUnits || 0)
              },
              boxes: boxes.map((box: any) => {
                const safeBox = box || {};
                return {
                  ...safeBox,
                  unitCount: safeBox.sensorCount !== undefined
                    ? safeBox.sensorCount
                    : (safeBox.unitCount || 0)
                };
              })
            };
          })
          : []
      };

      return mappedResponse;
    } catch (error: any) {
      console.error('Error in validateShipment:', error);

      if (error.response?.data?.detail) {
        const detail = error.response.data.detail;
        if (Array.isArray(detail)) {
          throw new Error(detail[0].msg);
        } else {
          throw new Error(detail);
        }
      }
      throw new Error('Failed to validate sensor shipment data. Please check your input and try again.');
    }
  },

  async importShipment(data: ShipmentData): Promise<ImportResult> {
    try {
      return await API.post<ImportResult>("apiVeroHwqa", "/sensor/shipments/import-shipment", {
        body: data
      });
    } catch (error: any) {
      console.error('Error in sensorShipmentService importShipment:', error);

      if (error.response?.data?.detail) {
        const detail = error.response.data.detail;
        if (typeof detail === 'string' && detail.includes('Serial numbers not found:')) {
          const missingSerials = detail.match(/Serial numbers not found: ([\d, ]+)/g)
            ?.map(match => match.replace('Serial numbers not found: ', ''))
            .join(', ');

          throw new Error(
            `The following serial numbers were not found in the database:\n${missingSerials}\n\n` +
            `Please ensure all receivers exist in the database before importing.`
          );
        }
      }
      throw new Error('Failed to import sensor shipment. Please check your data and try again.');
    }
  }
};
```

#### 4. hubShipmentService.ts
**File**: `frontend/src/hwqa/services/hubShipmentService.ts`
**Changes**: Same pattern as sensorShipmentService, replace `/sensor/` with `/hub/`

#### 5. sensorDashboardService.ts
**File**: `frontend/src/hwqa/services/sensorDashboardService.ts`
**Changes**: Update import and response handling

#### 6. hubDashboardService.ts
**File**: `frontend/src/hwqa/services/hubDashboardService.ts`
**Changes**: Same pattern as sensorDashboardService

#### 7. glossaryService.ts
**File**: `frontend/src/hwqa/services/glossaryService.ts`

```typescript
import { CreateFailureTypeRequest, CreateFailureTypeResponse, FailureType, GlossaryData, NextStep, CreateTestSpecRequest, CreateTestSpecResponse } from '../types/api';
import { API } from "@api/amplifyAdapter";

export const glossaryService = {
  async getGlossary(): Promise<GlossaryData> {
    try {
      return await API.get<GlossaryData>("apiVeroHwqa", "/glossary/terms");
    } catch (error: any) {
      if (error.response?.data?.detail) {
        const detail = error.response.data.detail;
        if (Array.isArray(detail)) {
          throw new Error(detail[0].msg);
        } else {
          throw new Error(detail);
        }
      }
      throw new Error('Failed to fetch glossary data. Please try again.');
    }
  },

  async getNextSteps(): Promise<NextStep[]> {
    try {
      return await API.get<NextStep[]>("apiVeroHwqa", "/glossary/next-steps");
    } catch (error: any) {
      if (error.response?.data?.detail) {
        const detail = error.response.data.detail;
        if (Array.isArray(detail)) {
          throw new Error(detail[0].msg);
        } else {
          throw new Error(detail);
        }
      }
      throw new Error('Failed to fetch next steps. Please try again.');
    }
  },

  async getFailureTypes(deviceType?: 'sensor' | 'hub'): Promise<FailureType[]> {
    try {
      const queryParams = deviceType ? { device_type: deviceType } : undefined;
      return await API.get<FailureType[]>("apiVeroHwqa", "/glossary/failure-types", {
        queryParams
      });
    } catch (error: any) {
      if (error.response?.data?.detail) {
        const detail = error.response.data.detail;
        if (Array.isArray(detail)) {
          throw new Error(detail[0].msg);
        } else {
          throw new Error(detail);
        }
      }
      throw new Error('Failed to fetch failure types. Please try again.');
    }
  },

  async createFailureType(request: CreateFailureTypeRequest): Promise<CreateFailureTypeResponse> {
    try {
      return await API.post<CreateFailureTypeResponse>("apiVeroHwqa", "/glossary/failure-types", {
        body: request
      });
    } catch (error: any) {
      if (error.response?.data?.detail) {
        const detail = error.response.data.detail;
        if (Array.isArray(detail)) {
          throw new Error(detail[0].msg);
        } else {
          throw new Error(detail);
        }
      }
      throw new Error('Failed to create failure type. Please try again.');
    }
  },

  async createTestSpec(request: CreateTestSpecRequest): Promise<CreateTestSpecResponse> {
    try {
      return await API.post<CreateTestSpecResponse>("apiVeroHwqa", "/glossary/test-specs", {
        body: request
      });
    } catch (error: any) {
      if (!error.response?.data?.detail) {
        throw new Error('Failed to create test spec. Please try again.');
      }

      const detail = error.response.data.detail;
      if (Array.isArray(detail)) {
        throw new Error(detail[0].msg);
      }

      throw new Error(detail);
    }
  }
};
```

#### 8. sensorConversionService.ts
**File**: `frontend/src/hwqa/services/sensorConversionService.ts`
**Changes**: Update import and response handling

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npm run typecheck`
- [ ] Linting passes: `cd frontend && npm run lint`
- [ ] Tests pass: `cd frontend && npm test`
- [ ] No service files import from `amplifyApi.service`

#### Manual Verification:
- [ ] Sensor test logging works
- [ ] Hub test logging works
- [ ] Sensor shipment import works
- [ ] Hub shipment import works
- [ ] Dashboard loads for sensors
- [ ] Dashboard loads for hubs
- [ ] Glossary management works
- [ ] Sensor conversion works

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 3: Update Component Files Using fetchApi Directly

### Overview
Update remaining component files that import directly from `amplifyApi.service.ts`.

### Files to Update:

| File | Occurrences |
|------|-------------|
| `CreateShipmentForm.tsx` | 2 |
| `PasteShipmentForm.tsx` | 2 |

### Changes Required:

#### 1. CreateShipmentForm.tsx
**File**: `frontend/src/hwqa/components/features/shipments/CreateShipmentForm.tsx`
**Changes**: Remove direct fetchApi usage, use appropriate service instead

#### 2. PasteShipmentForm.tsx
**File**: `frontend/src/hwqa/components/features/shipments/PasteShipmentForm.tsx`
**Changes**: Remove direct fetchApi usage, use appropriate service instead

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npm run typecheck`
- [ ] Linting passes: `cd frontend && npm run lint`
- [ ] Tests pass: `cd frontend && npm test`
- [ ] No component files import from `amplifyApi.service`

#### Manual Verification:
- [ ] Create shipment form works
- [ ] Paste shipment form works

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 4: Delete Custom Adapter

### Overview
Remove the custom `amplifyApi.service.ts` file after all migrations are complete.

### Changes Required:

#### 1. Delete the custom adapter
**File**: `frontend/src/hwqa/services/amplifyApi.service.ts`
**Action**: Delete file

#### 2. Verify no remaining imports
```bash
# Should return no matches
grep -r "amplifyApi.service" frontend/src/hwqa/
```

### Success Criteria:

#### Automated Verification:
- [ ] `amplifyApi.service.ts` file no longer exists
- [ ] No grep results for `amplifyApi.service` in hwqa directory
- [ ] TypeScript compiles: `cd frontend && npm run typecheck`
- [ ] Linting passes: `cd frontend && npm run lint`
- [ ] Tests pass: `cd frontend && npm test`

#### Manual Verification:
- [ ] Full regression test of all HWQA features
- [ ] Sensor test logging
- [ ] Hub test logging
- [ ] Sensor shipment management
- [ ] Hub shipment management
- [ ] Sensor dashboard
- [ ] Hub dashboard
- [ ] Glossary management
- [ ] Bulk operations (shipments, boxes, serials)

**Implementation Note**: This is the final phase. All HWQA functionality should be verified before considering the task complete.

---

## Testing Strategy

### Unit Tests:
- All existing tests should continue to pass
- No new unit tests required (same functionality, different adapter)

### Integration Tests:
- Verify API calls work end-to-end with the shared adapter
- Test authentication flow with SigV4 signing

### Manual Testing Steps:
1. Navigate to HWQA section
2. Test sensor test logging (Log Test page)
3. Test hub test logging (Log Test page)
4. Test sensor shipment import (Shipments page)
5. Test hub shipment import (Shipments page)
6. Test bulk serial number loading
7. Test existing test check functionality
8. Verify error handling displays correctly

## Performance Considerations

- No performance impact expected - same underlying Amplify API calls
- Slightly reduced bundle size from removing duplicate adapter code

## Migration Notes

- No database migrations required
- No backend changes required
- No API contract changes
- Pure frontend refactoring

## References

- Original ticket: `thoughts/shared/research/2025-12-03-IWA-14069-hwqa-api-refactor.md`
- Shared adapter: `frontend/src/shared/api/amplifyAdapter.ts:18-42`
- Custom adapter: `frontend/src/hwqa/services/amplifyApi.service.ts` (to be deleted)
- LogTestForm: `frontend/src/hwqa/components/features/tests/LogTestForm.tsx:141-277`
