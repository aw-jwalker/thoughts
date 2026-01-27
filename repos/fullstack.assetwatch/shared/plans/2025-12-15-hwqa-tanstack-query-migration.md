# HWQA TanStack Query Migration Implementation Plan

## Overview

Remove the HWQA `AppStateContext` and replace it with TanStack Query hooks to match the established patterns in the fullstack.assetwatch repository. This will provide automatic caching, background refetching, and consistent state management.

## Current State Analysis

### What Exists Now
- **AppStateContext** (`frontend/src/components/HwqaPage/context/AppStateContext.tsx`):
  - Stores all HWQA data in React state (428 lines)
  - 27 functions for fetching and mutations
  - Manual state management with `useState` and `useCallback`
  - No caching - every page load refetches data
  - Manual loading/error state in each component

- **Files Using AppStateContext** (14 files):
  - `pages/Hwqa.tsx` - Provider wrapper
  - `pages/SensorTestsPage.tsx`
  - `pages/SensorShipmentsPage.tsx`
  - `pages/SensorDashboardPage.tsx` (already uses `useMetricsQuery`)
  - `pages/SensorConversionPage.tsx`
  - `pages/HubTestsPage.tsx`
  - `pages/HubShipmentsPage.tsx`
  - `pages/HubDashboardPage.tsx` (already uses `useMetricsQuery`)
  - `pages/GlossaryPage.tsx`
  - `features/dashboard/DashboardFilters/DashboardFilters.tsx`
  - `features/conversion/SensorConversion/SensorConversionForm.tsx`
  - `features/conversion/SensorConversion/RouteBasedSensorList.tsx`

- **Existing Services** (already abstracted API calls):
  - `sensorTestService.ts`, `hubTestService.ts`
  - `sensorShipmentService.ts`, `hubShipmentService.ts`
  - `sensorDashboardService.ts`, `hubDashboardService.ts`
  - `sensorConversionService.ts`
  - `glossaryService.ts`

### Key Discoveries
- Already has `useMetricsQuery` hook (`hooks/useMetricsQuery.ts`) - good pattern to follow
- Services already handle error transformation - hooks can just call services
- Dashboard pages already use TanStack Query for metrics, but context for filter options
- Sensor/Hub patterns are nearly identical - can unify with `deviceType` parameter

## Desired End State

After implementation:
1. All HWQA data fetching uses TanStack Query hooks
2. `AppStateContext` and `AppStateProvider` are removed
3. Automatic caching with appropriate `staleTime` values
4. Mutations invalidate related queries on success
5. Hooks grouped by domain in files matching lambda patterns
6. Unified sensor/hub hooks with `deviceType` parameter

### Verification
- All HWQA pages load and function correctly
- Data caches appropriately (navigating away and back doesn't refetch if not stale)
- Mutations properly refresh related data
- No console errors related to context or queries
- TypeScript compiles without errors
- Linting passes

## What We're NOT Doing

- Changing the service layer (services remain as-is)
- Modifying the API contracts
- Adding new features or UI changes
- Changing the routing structure
- Refactoring components beyond removing context usage

## Implementation Approach

We'll create TanStack Query hooks grouped by domain, then update pages incrementally with testing checkpoints between phases. We will make small commits for the changes as we go instead of 1 large commit.

**Hook File Structure:**
```
frontend/src/components/HwqaPage/hooks/
├── useMetricsQuery.ts        (existing - keep as-is)
├── testQueries.ts            (new - test results, phases, specs, failure types)
├── shipmentQueries.ts        (new - shipment fetching and logging)
├── glossaryQueries.ts        (new - glossary data and mutations)
├── filterOptionsQueries.ts   (new - dashboard filter options)
├── conversionQueries.ts      (new - sensor conversion and route-based sensors)
└── index.ts                  (new - re-export all hooks)
```

---

## Phase 1: Create Query Hooks

### Overview
Create all TanStack Query hooks for read and write operations, grouped by domain.

### Changes Required:

#### 1. Test Queries Hook
**File**: `frontend/src/components/HwqaPage/hooks/testQueries.ts`
**Changes**: Create unified hooks for sensor/hub test operations

```typescript
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { sensorTestService } from '@components/HwqaPage/services/sensorTestService';
import { hubTestService } from '@components/HwqaPage/services/hubTestService';
import { TestResult, DropdownOption, TestLogResult } from '@components/HwqaPage/types/api';

type DeviceType = 'sensor' | 'hub';

const getService = (deviceType: DeviceType) =>
  deviceType === 'sensor' ? sensorTestService : hubTestService;

interface UseTestResultsParams {
  deviceType: DeviceType;
  serialNumbers?: string[];
  limit?: number;
  enabled?: boolean;
}

/**
 * Fetches test results for sensors or hubs
 * Caches results by device type, serial numbers, and limit
 */
export function useTestResults({
  deviceType,
  serialNumbers = [],
  limit = 1000,
  enabled = true
}: UseTestResultsParams) {
  const queryKey = ['hwqa', deviceType, 'tests', { serialNumbers, limit }];
  const queryClient = useQueryClient();

  const query = useQuery<TestResult[]>({
    queryKey,
    queryFn: () => getService(deviceType).getTests(serialNumbers, limit),
    enabled,
    staleTime: 2 * 60 * 1000, // 2 minutes
    placeholderData: [],
  });

  const invalidateQuery = () => queryClient.invalidateQueries({ queryKey: ['hwqa', deviceType, 'tests'] });

  return { ...query, queryKey, invalidateQuery };
}

/**
 * Fetches test phases dropdown options
 */
export function useTestPhases(deviceType: DeviceType) {
  const queryKey = ['hwqa', deviceType, 'testPhases'];

  return useQuery<DropdownOption[]>({
    queryKey,
    queryFn: () => getService(deviceType).fetchTestPhases(),
    staleTime: 30 * 60 * 1000, // 30 minutes - rarely changes
    placeholderData: [],
  });
}

/**
 * Fetches test specs dropdown options
 */
export function useTestSpecs(deviceType: DeviceType) {
  const queryKey = ['hwqa', deviceType, 'testSpecs'];

  return useQuery<DropdownOption[]>({
    queryKey,
    queryFn: () => getService(deviceType).fetchTestSpecs(),
    staleTime: 30 * 60 * 1000, // 30 minutes - rarely changes
    placeholderData: [],
  });
}

/**
 * Fetches failure types dropdown options
 */
export function useFailureTypes(deviceType: DeviceType) {
  const queryKey = ['hwqa', deviceType, 'failureTypes'];

  return useQuery<DropdownOption[]>({
    queryKey,
    queryFn: () => getService(deviceType).fetchFailureTypes(),
    staleTime: 30 * 60 * 1000, // 30 minutes - rarely changes
    placeholderData: [],
  });
}

interface LogTestData {
  serialNumbers: string[];
  testPhase: string;
  testSpec: string;
  failureType: string;
}

/**
 * Mutation hook for logging test results
 * Invalidates test results cache on success
 */
export function useLogTest(deviceType: DeviceType) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (data: LogTestData) => {
      const result = await getService(deviceType).logTest(data);

      // Check for errors in results
      const errors = result.results?.filter((r: TestLogResult) => r.status === 'error');
      if (errors?.length > 0) {
        throw new Error(errors.map((e: any) => e.message).join(', '));
      }

      return result;
    },
    onSuccess: () => {
      // Invalidate all test results for this device type
      queryClient.invalidateQueries({ queryKey: ['hwqa', deviceType, 'tests'] });
    },
  });
}
```

#### 2. Shipment Queries Hook
**File**: `frontend/src/components/HwqaPage/hooks/shipmentQueries.ts`
**Changes**: Create unified hooks for sensor/hub shipment operations

```typescript
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { sensorShipmentService } from '@components/HwqaPage/services/sensorShipmentService';
import { hubShipmentService } from '@components/HwqaPage/services/hubShipmentService';
import { ShipmentGroup, ShipmentData, ImportResult } from '@components/HwqaPage/types/api';

type DeviceType = 'sensor' | 'hub';

const getService = (deviceType: DeviceType) =>
  deviceType === 'sensor' ? sensorShipmentService : hubShipmentService;

/**
 * Fetches shipments for sensors or hubs
 */
export function useShipments(deviceType: DeviceType, enabled = true) {
  const queryKey = ['hwqa', deviceType, 'shipments'];
  const queryClient = useQueryClient();

  const query = useQuery<ShipmentGroup[]>({
    queryKey,
    queryFn: () => getService(deviceType).getShipments(),
    enabled,
    staleTime: 2 * 60 * 1000, // 2 minutes
    placeholderData: [],
  });

  const invalidateQuery = () => queryClient.invalidateQueries({ queryKey });

  return { ...query, queryKey, invalidateQuery };
}

/**
 * Mutation hook for logging/importing shipments
 * Invalidates shipments cache on success
 */
export function useLogShipment(deviceType: DeviceType) {
  const queryClient = useQueryClient();

  return useMutation<ImportResult, Error, ShipmentData>({
    mutationFn: (data: ShipmentData) => getService(deviceType).importShipment(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hwqa', deviceType, 'shipments'] });
    },
  });
}
```

#### 3. Glossary Queries Hook
**File**: `frontend/src/components/HwqaPage/hooks/glossaryQueries.ts`
**Changes**: Create hooks for glossary data and mutations

```typescript
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { glossaryService } from '@components/HwqaPage/services/glossaryService';
import {
  GlossaryData,
  NextStep,
  FailureType,
  CreateFailureTypeRequest,
  CreateFailureTypeResponse,
  CreateTestSpecRequest,
  CreateTestSpecResponse
} from '@components/HwqaPage/types/api';

/**
 * Fetches glossary data (test phases, specs, failure types)
 */
export function useGlossary(enabled = true) {
  const queryKey = ['hwqa', 'glossary'];
  const queryClient = useQueryClient();

  const query = useQuery<GlossaryData>({
    queryKey,
    queryFn: () => glossaryService.getGlossary(),
    enabled,
    staleTime: 10 * 60 * 1000, // 10 minutes - reference data
  });

  const invalidateQuery = () => queryClient.invalidateQueries({ queryKey });

  return { ...query, queryKey, invalidateQuery };
}

/**
 * Fetches next steps for failure types
 */
export function useNextSteps(enabled = true) {
  const queryKey = ['hwqa', 'nextSteps'];

  return useQuery<NextStep[]>({
    queryKey,
    queryFn: () => glossaryService.getNextSteps(),
    enabled,
    staleTime: 30 * 60 * 1000, // 30 minutes
    placeholderData: [],
  });
}

/**
 * Fetches failure types, optionally filtered by device type
 */
export function useGlossaryFailureTypes(deviceType?: 'sensor' | 'hub', enabled = true) {
  const queryKey = ['hwqa', 'failureTypes', { deviceType }];

  return useQuery<FailureType[]>({
    queryKey,
    queryFn: () => glossaryService.getFailureTypes(deviceType),
    enabled,
    staleTime: 30 * 60 * 1000, // 30 minutes
    placeholderData: [],
  });
}

/**
 * Mutation hook for creating a new failure type
 * Invalidates glossary cache on success
 */
export function useCreateFailureType() {
  const queryClient = useQueryClient();

  return useMutation<CreateFailureTypeResponse, Error, CreateFailureTypeRequest>({
    mutationFn: (request) => glossaryService.createFailureType(request),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hwqa', 'glossary'] });
      queryClient.invalidateQueries({ queryKey: ['hwqa', 'failureTypes'] });
      // Also invalidate device-specific failure types
      queryClient.invalidateQueries({ queryKey: ['hwqa', 'sensor', 'failureTypes'] });
      queryClient.invalidateQueries({ queryKey: ['hwqa', 'hub', 'failureTypes'] });
    },
  });
}

/**
 * Mutation hook for creating a new test spec
 * Invalidates glossary cache on success
 */
export function useCreateTestSpec() {
  const queryClient = useQueryClient();

  return useMutation<CreateTestSpecResponse, Error, CreateTestSpecRequest>({
    mutationFn: (request) => glossaryService.createTestSpec(request),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hwqa', 'glossary'] });
      queryClient.invalidateQueries({ queryKey: ['hwqa', 'sensor', 'testSpecs'] });
      queryClient.invalidateQueries({ queryKey: ['hwqa', 'hub', 'testSpecs'] });
    },
  });
}
```

#### 4. Filter Options Queries Hook
**File**: `frontend/src/components/HwqaPage/hooks/filterOptionsQueries.ts`
**Changes**: Create hooks for dashboard filter options

```typescript
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { sensorDashboardService } from '@components/HwqaPage/services/sensorDashboardService';
import { hubDashboardService } from '@components/HwqaPage/services/hubDashboardService';
import { FilterOptions } from '@components/HwqaPage/types/api';

type DeviceType = 'sensor' | 'hub';

const getService = (deviceType: DeviceType) =>
  deviceType === 'sensor' ? sensorDashboardService : hubDashboardService;

/**
 * Fetches filter options for dashboard dropdowns
 * Used for test phases, specs, revisions, failure types filters
 */
export function useFilterOptions(deviceType: DeviceType, enabled = true) {
  const queryKey = ['hwqa', deviceType, 'filterOptions'];
  const queryClient = useQueryClient();

  const query = useQuery<FilterOptions>({
    queryKey,
    queryFn: () => getService(deviceType).getFilterOptions(),
    enabled,
    staleTime: 10 * 60 * 1000, // 10 minutes
  });

  const invalidateQuery = () => queryClient.invalidateQueries({ queryKey });

  return { ...query, queryKey, invalidateQuery };
}
```

#### 5. Conversion Queries Hook
**File**: `frontend/src/components/HwqaPage/hooks/conversionQueries.ts`
**Changes**: Create hooks for sensor conversion operations

```typescript
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { sensorConversionService } from '@components/HwqaPage/services/sensorConversionService';
import {
  RouteBasedSensor,
  SensorConversionRequest,
  SensorConversionResponse,
  SensorConversionBatchRequest,
  SensorConversionBatchResponse
} from '@components/HwqaPage/types/api';

/**
 * Fetches list of route-based sensors
 */
export function useRouteBasedSensors(enabled = true) {
  const queryKey = ['hwqa', 'routeBasedSensors'];
  const queryClient = useQueryClient();

  const query = useQuery<RouteBasedSensor[]>({
    queryKey,
    queryFn: () => sensorConversionService.getRouteBasedSensors(),
    enabled,
    staleTime: 2 * 60 * 1000, // 2 minutes
    placeholderData: [],
  });

  const invalidateQuery = () => queryClient.invalidateQueries({ queryKey });

  return { ...query, queryKey, invalidateQuery };
}

/**
 * Mutation hook for converting a single sensor to route-based
 * Invalidates route-based sensors cache on success
 */
export function useConvertSensor() {
  const queryClient = useQueryClient();

  return useMutation<SensorConversionResponse, Error, SensorConversionRequest>({
    mutationFn: (data) => sensorConversionService.convertSensor(data),
    onSuccess: (response) => {
      if (response.success) {
        queryClient.invalidateQueries({ queryKey: ['hwqa', 'routeBasedSensors'] });
      }
    },
  });
}

/**
 * Mutation hook for batch converting sensors to route-based
 * Invalidates route-based sensors cache on success
 */
export function useConvertSensorsBatch() {
  const queryClient = useQueryClient();

  return useMutation<SensorConversionBatchResponse, Error, SensorConversionBatchRequest>({
    mutationFn: (data) => sensorConversionService.convertSensorsBatch(data),
    onSuccess: (response) => {
      if (response.success_count > 0) {
        queryClient.invalidateQueries({ queryKey: ['hwqa', 'routeBasedSensors'] });
      }
    },
  });
}
```

#### 6. Hooks Index File
**File**: `frontend/src/components/HwqaPage/hooks/index.ts`
**Changes**: Re-export all hooks for easy importing

```typescript
// Test queries
export {
  useTestResults,
  useTestPhases,
  useTestSpecs,
  useFailureTypes,
  useLogTest
} from './testQueries';

// Shipment queries
export { useShipments, useLogShipment } from './shipmentQueries';

// Glossary queries
export {
  useGlossary,
  useNextSteps,
  useGlossaryFailureTypes,
  useCreateFailureType,
  useCreateTestSpec
} from './glossaryQueries';

// Filter options queries
export { useFilterOptions } from './filterOptionsQueries';

// Conversion queries
export {
  useRouteBasedSensors,
  useConvertSensor,
  useConvertSensorsBatch
} from './conversionQueries';

// Metrics query (existing)
export { useMetricsQuery } from './useMetricsQuery';
```

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles: `cd frontend && npx tsc --noEmit`
- [x] Linting passes: `cd frontend && npm run lint`
- [x] All new hook files exist and export correctly

#### Manual Verification:
- [ ] Import hooks in a test component to verify exports work
- [ ] No runtime errors when importing hooks

**Implementation Note**: After completing this phase, pause to verify TypeScript compilation before proceeding to Phase 2.

---

## Phase 2: Update Test Pages (Sensor & Hub)

### Overview
Update SensorTestsPage and HubTestsPage to use the new TanStack Query hooks.

### Changes Required:

#### 1. SensorTestsPage
**File**: `frontend/src/components/HwqaPage/pages/SensorTestsPage.tsx`
**Changes**: Replace useAppState with TanStack Query hooks

```typescript
import { Paper, Title, Stack, Text } from '@mantine/core';
import { PageContainer } from '@components/HwqaPage/layout';
import { TestList } from '@components/HwqaPage/features/tests/TestList';
import { LogTestForm } from '@components/HwqaPage/features/tests/LogTestForm';
import { useState } from 'react';
import { useAuthContext } from '@contexts/AuthContext';
import { ProductType } from '@components/HwqaPage/shared/enums/ProductType';
import {
  useTestResults,
  useTestPhases,
  useTestSpecs,
  useFailureTypes,
  useLogTest
} from '@components/HwqaPage/hooks';

export function SensorTestsPage() {
  const { isEngineering, isSupplyChain, isContractManufacturer } = useAuthContext();
  const canLogTests = isEngineering || isSupplyChain || isContractManufacturer;

  const [limit, setLimit] = useState(1000);
  const [searchSerialNumbers, setSearchSerialNumbers] = useState<string[]>([]);

  // Queries
  const {
    data: sensorResults = [],
    isLoading: isLoadingResults,
    refetch: refetchResults
  } = useTestResults({
    deviceType: 'sensor',
    serialNumbers: searchSerialNumbers,
    limit
  });

  const { data: testPhases = [] } = useTestPhases('sensor');
  const { data: testSpecs = [] } = useTestSpecs('sensor');
  const { data: failureTypes = [] } = useFailureTypes('sensor');

  // Mutation
  const logTestMutation = useLogTest('sensor');

  const handleLogTest = async (data: {
    serialNumbers: string[];
    testPhase: string;
    testSpec: string;
    failureType: string;
  }) => {
    await logTestMutation.mutateAsync(data);
    // Update search to show results for logged serial numbers
    setSearchSerialNumbers(data.serialNumbers);
  };

  const handleRefreshTests = (newLimit: number) => {
    setLimit(newLimit);
    setSearchSerialNumbers([]);
    refetchResults();
  };

  const handleFetchTestsAdapter = async (serialNumbers: string[], newLimit: number) => {
    setSearchSerialNumbers(serialNumbers);
    setLimit(newLimit);
  };

  const isLoading = isLoadingResults || logTestMutation.isPending;
  const error = logTestMutation.error?.message;

  return (
    <PageContainer>
      <Stack gap="lg">
        <Title>Test Results</Title>

        {canLogTests && (
          <Paper p="md" withBorder>
            <Title order={3}>Log Test Results</Title>
            <Text c="dimmed" mb="md">
              Log test results for sensors by entering serial numbers and test information.
            </Text>
            <LogTestForm
              testPhases={testPhases}
              testSpecs={testSpecs}
              failureTypes={failureTypes}
              productType={ProductType.SENSOR}
              onLogTest={handleLogTest}
              onFetchTests={handleFetchTestsAdapter}
              isLoading={logTestMutation.isPending}
              error={error}
            />
          </Paper>
        )}

        <TestList
          data={sensorResults}
          isLoading={isLoadingResults}
          onRefresh={handleRefreshTests}
        />
      </Stack>
    </PageContainer>
  );
}
```

#### 2. HubTestsPage
**File**: `frontend/src/components/HwqaPage/pages/HubTestsPage.tsx`
**Changes**: Same pattern as SensorTestsPage but with `deviceType: 'hub'`

(Similar structure to SensorTestsPage, replacing 'sensor' with 'hub' and ProductType.SENSOR with ProductType.HUB)

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles: `cd frontend && npx tsc --noEmit`
- [x] Linting passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] Navigate to Sensor Tests page - loads without errors
- [ ] Test results display correctly
- [ ] Dropdown options (phases, specs, failure types) populate
- [ ] Log a test result - success message appears, list refreshes
- [ ] Refresh button works
- [ ] Navigate to Hub Tests page - same verifications
- [ ] Navigate away and back - data should be cached (no loading spinner if within 2 min)

**Implementation Note**: After completing this phase and all verification passes, pause here for manual testing before proceeding to Phase 3.

---

## Phase 3: Update Shipment Pages (Sensor & Hub)

### Overview
Update SensorShipmentsPage and HubShipmentsPage to use TanStack Query hooks.

### Changes Required:

#### 1. SensorShipmentsPage
**File**: `frontend/src/components/HwqaPage/pages/SensorShipmentsPage.tsx`
**Changes**: Replace useAppState with TanStack Query hooks

```typescript
import { useState } from 'react';
import { Title, Group, Paper, Stack, Text, Alert, Center, Button } from '@mantine/core';
import { ShipmentList, LogShipmentForm } from '@components/HwqaPage/features/shipments';
import { useAuthContext } from '@contexts/AuthContext';
import { PageContainer } from '@components/HwqaPage/layout';
import { ImportResult, ShipmentData } from '@components/HwqaPage/types/api';
import { faCircleExclamation, faCheck } from '@fortawesome/pro-solid-svg-icons';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { ExpandableSection } from '@components/HwqaPage/common/ExpandableSection';
import { useShipments, useLogShipment } from '@components/HwqaPage/hooks';

export function SensorShipmentsPage() {
  const { isEngineering, isSupplyChain, isContractManufacturer } = useAuthContext();
  const canLogShipments = isEngineering || isSupplyChain || isContractManufacturer;

  const [apiResult, setApiResult] = useState<{ success: boolean; message: string } | null>(null);

  // Query
  const {
    data: shipments = [],
    isLoading: isLoadingShipments,
    error: shipmentsError,
    refetch: refetchShipments
  } = useShipments('sensor');

  // Mutation
  const logShipmentMutation = useLogShipment('sensor');

  const handleLogShipment = async (data: ShipmentData): Promise<ImportResult> => {
    setApiResult(null);
    try {
      const result = await logShipmentMutation.mutateAsync(data);
      setApiResult({
        success: true,
        message: `Successfully imported ${result.new_shipments} new and updated ${result.updated_shipments} shipments`
      });
      return result;
    } catch (err: any) {
      const errorMessage = err.message || 'Failed to log shipment. Please try again.';
      setApiResult({ success: false, message: errorMessage });
      throw err;
    }
  };

  const handleRefresh = async () => {
    setApiResult(null);
    try {
      await refetchShipments();
      setApiResult({ success: true, message: 'Shipment data refreshed successfully' });
    } catch (err: any) {
      setApiResult({ success: false, message: err.message || 'Failed to refresh shipments.' });
    }
  };

  // Show error from initial load
  if (shipmentsError && !apiResult) {
    setApiResult({ success: false, message: shipmentsError.message });
  }

  return (
    <PageContainer>
      <Stack gap="lg">
        <Title>Shipments</Title>

        {apiResult && (
          <Alert
            icon={apiResult.success ? <FontAwesomeIcon icon={faCheck} size="sm" /> : <FontAwesomeIcon icon={faCircleExclamation} size="sm" />}
            title={apiResult.success ? "Success" : "Error"}
            color={apiResult.success ? "primary60" : "error60"}
            withCloseButton
            onClose={() => setApiResult(null)}
          >
            <Text>{apiResult.message}</Text>
          </Alert>
        )}

        {canLogShipments && (
          <ExpandableSection
            title="Log New Shipment"
            defaultOpen={true}
            summary={<Text c="dimmed">Add new shipment records by uploading an Excel file.</Text>}
          >
            <LogShipmentForm
              onSuccess={handleLogShipment}
              onCancel={() => setApiResult(null)}
            />
          </ExpandableSection>
        )}

        <Paper p="md" withBorder>
          <Group justify="apart" mb="md">
            <Title order={3}>Shipment Records</Title>
            <Button
              variant="default"
              size="sm"
              onClick={handleRefresh}
              loading={isLoadingShipments}
              type="button"
            >
              Refresh Data
            </Button>
          </Group>

          {Array.isArray(shipments) && shipments.length > 0 ? (
            <ShipmentList data={shipments} />
          ) : (
            <Center py="xl">
              <Text c="dimmed">
                {shipmentsError ? 'Unable to load shipments.' : 'No shipments found.'}
              </Text>
            </Center>
          )}
        </Paper>
      </Stack>
    </PageContainer>
  );
}
```

#### 2. HubShipmentsPage
**File**: `frontend/src/components/HwqaPage/pages/HubShipmentsPage.tsx`
**Changes**: Same pattern as SensorShipmentsPage but with `deviceType: 'hub'`

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npx tsc --noEmit`
- [ ] Linting passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] Navigate to Sensor Shipments page - loads without errors
- [ ] Shipment list displays correctly
- [ ] Upload a shipment Excel file - success message, list refreshes
- [ ] Refresh button works
- [ ] Navigate to Hub Shipments page - same verifications
- [ ] Caching works (navigate away and back)

**Implementation Note**: Pause here for manual testing before proceeding to Phase 4.

---

## Phase 4: Update Glossary Page

### Overview
Update GlossaryPage to use TanStack Query hooks.

### Changes Required:

#### 1. GlossaryPage
**File**: `frontend/src/components/HwqaPage/pages/GlossaryPage.tsx`
**Changes**: Replace useAppState with useGlossary hook

```typescript
import { useState } from 'react';
import { Stack, Loader, Paper, Title, Text, Tabs, SimpleGrid, TextInput, Badge, Group, Button } from '@mantine/core';
import { faBook, faFlask, faMagnifyingGlass, faPlus, faDesktop, faRouter } from '@fortawesome/pro-solid-svg-icons';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { useAuthContext } from '@contexts/AuthContext';
import { PageContainer } from '@components/HwqaPage/layout';
import { AddFailureTypeModal } from '@components/HwqaPage/features/glossary/AddFailureTypeModal';
import { AddTestSpecModal } from '@components/HwqaPage/features/glossary/AddTestSpecModal';
import { GlossaryData } from '@components/HwqaPage/types/api';
import { useGlossary } from '@components/HwqaPage/hooks';

export function GlossaryPage() {
  const { isAuthenticated, isEngineering, isSupplyChain } = useAuthContext();

  const { data: glossaryData, isLoading, error, invalidateQuery } = useGlossary(isAuthenticated);

  const [activeTab, setActiveTab] = useState<string>('phases');
  const [searchQuery, setSearchQuery] = useState('');
  const [modalOpened, setModalOpened] = useState(false);
  const [testSpecModalOpened, setTestSpecModalOpened] = useState(false);

  const handleModalSuccess = () => {
    invalidateQuery();
  };

  // Filter glossary data based on search query
  const filteredData = glossaryData?.failure_types
    ? filterGlossaryData(glossaryData, searchQuery)
    : null;

  if (isLoading) {
    return (
      <PageContainer>
        <Paper p="md" withBorder>
          <Stack align="center" justify="center" py="xl">
            <Loader size="xl" />
            <Text>Loading glossary data...</Text>
          </Stack>
        </Paper>
      </PageContainer>
    );
  }

  return (
    <PageContainer>
      {/* ... rest of component JSX remains the same ... */}
    </PageContainer>
  );
}

// filterGlossaryData helper function remains the same
```

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npx tsc --noEmit`
- [ ] Linting passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] Navigate to Glossary page - loads without errors
- [ ] All tabs display data (phases, specs, sensor failures, hub failures)
- [ ] Search filtering works
- [ ] Add Failure Type modal works, glossary refreshes on success
- [ ] Add Test Spec modal works, glossary refreshes on success

**Implementation Note**: Pause here for manual testing before proceeding to Phase 5.

---

## Phase 5: Update Dashboard Pages

### Overview
Update DashboardFilters component to use TanStack Query for filter options, while dashboard pages already use useMetricsQuery.

### Changes Required:

#### 1. DashboardFilters Component
**File**: `frontend/src/components/HwqaPage/features/dashboard/DashboardFilters/DashboardFilters.tsx`
**Changes**: Replace useAppState filter options with useFilterOptions hook

The component currently uses:
```typescript
const { sensorFilterOptions, hubFilterOptions } = useAppState();
```

Replace with:
```typescript
import { useFilterOptions } from '@components/HwqaPage/hooks';

// Inside component:
const { data: filterOptions } = useFilterOptions(isHub ? 'hub' : 'sensor');
```

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npx tsc --noEmit`
- [ ] Linting passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] Sensor Dashboard page loads - filter dropdowns populate
- [ ] Hub Dashboard page loads - filter dropdowns populate
- [ ] Applying filters works and refreshes metrics
- [ ] RCCA Report tab works
- [ ] Pass Rate Overview tab works

**Implementation Note**: Pause here for manual testing before proceeding to Phase 6.

---

## Phase 6: Update Conversion Page

### Overview
Update SensorConversionPage and related components to use TanStack Query hooks.

### Changes Required:

#### 1. SensorConversionPage
**File**: `frontend/src/components/HwqaPage/pages/SensorConversionPage.tsx`
**Changes**: Remove useAppState, conversion now handled by child components

```typescript
import { Title, Text, Stack, Paper } from '@mantine/core';
import { SensorConversionForm, RouteBasedSensorList } from '@components/HwqaPage/features/conversion/SensorConversion';
import { useAuthContext } from '@contexts/AuthContext';
import { PageContainer } from '@components/HwqaPage/layout';

export function SensorConversionPage() {
  const { isEngineering, isSupplyChain, isContractManufacturer } = useAuthContext();
  const canLogTests = isEngineering || isSupplyChain || isContractManufacturer;

  return (
    <PageContainer>
      <Stack gap="lg">
        <Title>Sensor Conversion Tool</Title>

        {canLogTests && (
          <Paper p="md" withBorder>
            <Title order={3}>Convert Sensor</Title>
            <Text c="dimmed">
              This tool allows you to convert a sensor to a route-based sensor by updating the database.
            </Text>
            <SensorConversionForm />
          </Paper>
        )}

        <RouteBasedSensorList />
      </Stack>
    </PageContainer>
  );
}
```

#### 2. SensorConversionForm
**File**: `frontend/src/components/HwqaPage/features/conversion/SensorConversion/SensorConversionForm.tsx`
**Changes**: Use useConvertSensor and useConvertSensorsBatch hooks

```typescript
import { useConvertSensor, useConvertSensorsBatch } from '@components/HwqaPage/hooks';

// Inside component:
const convertSensorMutation = useConvertSensor();
const convertBatchMutation = useConvertSensorsBatch();

// Replace direct calls with mutations
const handleConvert = async (data: SensorConversionRequest) => {
  await convertSensorMutation.mutateAsync(data);
};
```

#### 3. RouteBasedSensorList
**File**: `frontend/src/components/HwqaPage/features/conversion/SensorConversion/RouteBasedSensorList.tsx`
**Changes**: Use useRouteBasedSensors hook

```typescript
import { useRouteBasedSensors } from '@components/HwqaPage/hooks';

// Inside component:
const { data: routeBasedSensors = [], isLoading, refetch } = useRouteBasedSensors();
```

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npx tsc --noEmit`
- [ ] Linting passes: `cd frontend && npm run lint`

#### Manual Verification:
- [ ] Sensor Conversion page loads
- [ ] Route-based sensors list displays
- [ ] Convert single sensor works, list refreshes
- [ ] Batch convert works, list refreshes

**Implementation Note**: Pause here for manual testing before proceeding to Phase 7.

---

## Phase 7: Clean Up - Remove AppStateContext

### Overview
Remove the AppStateContext now that all pages use TanStack Query hooks.

### Changes Required:

#### 1. Remove AppStateProvider from Hwqa.tsx
**File**: `frontend/src/pages/Hwqa.tsx`
**Changes**: Remove AppStateProvider wrapper, keep QueryClientProvider

```typescript
import { useAuthContext } from "@contexts/AuthContext";
import { useSideNavContext } from "@contexts/SideNavContext";
import { useRegisterHotkey } from "@hooks/useRegisterHotkey";
import { Box, Flex } from "@mantine/core";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Outlet } from "@tanstack/react-router";
import { HwqaSideNav } from "../components/HwqaPage";

// Separate QueryClient for HWQA to avoid conflicts
const hwqaQueryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false,
    },
  },
});

function HwqaContent() {
  // ... same as before
}

export function Hwqa() {
  return (
    <QueryClientProvider client={hwqaQueryClient}>
      <HwqaContent />
    </QueryClientProvider>
  );
}

export { Hwqa as HwqaPage };
```

#### 2. Delete AppStateContext File
**File**: `frontend/src/components/HwqaPage/context/AppStateContext.tsx`
**Action**: Delete file

#### 3. Update Context Index
**File**: `frontend/src/components/HwqaPage/context/index.ts`
**Changes**: Remove AppStateContext exports (may delete file if empty)

#### 4. Update HwqaPage Index
**File**: `frontend/src/components/HwqaPage/index.ts`
**Changes**: Remove AppStateProvider and useAppState exports

#### 5. Verify No Remaining Imports
Search for any remaining imports of `useAppState` or `AppStateProvider` and remove them.

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npx tsc --noEmit`
- [ ] Linting passes: `cd frontend && npm run lint`
- [ ] No imports of `useAppState` or `AppStateProvider` remain: `grep -r "useAppState\|AppStateProvider" frontend/src/components/HwqaPage`

#### Manual Verification:
- [ ] Full smoke test of all HWQA pages:
  - [ ] Sensor Tests - load, log test, refresh
  - [ ] Sensor Shipments - load, upload, refresh
  - [ ] Sensor Dashboard - load, apply filters, both tabs
  - [ ] Hub Tests - load, log test, refresh
  - [ ] Hub Shipments - load, upload, refresh
  - [ ] Hub Dashboard - load, apply filters, both tabs
  - [ ] Glossary - load, search, add failure type, add test spec
  - [ ] Sensor Conversion - load, convert sensor
- [ ] Verify caching works (navigate between pages, data doesn't re-fetch if fresh)
- [ ] No console errors

---

## Testing Strategy

### Unit Tests
After migration, consider adding tests for the new hooks:
- Mock service calls
- Verify query keys are correct
- Verify mutations trigger correct invalidations

### Integration Tests
- Verify pages render with mocked query responses
- Verify mutations call correct services

### Manual Testing Steps
1. Navigate to each HWQA page
2. Verify data loads correctly
3. Perform CRUD operations where applicable
4. Verify data refreshes after mutations
5. Navigate away and back - verify caching works
6. Check browser Network tab - verify no duplicate requests

## Performance Considerations

- **Stale Time Settings**: Chosen based on data volatility:
  - Test results, shipments: 2 minutes (changes frequently during testing)
  - Filter options, glossary: 10-30 minutes (reference data, changes rarely)

- **Placeholder Data**: Empty arrays prevent undefined state, smoother UX

- **Query Key Structure**: Hierarchical `['hwqa', deviceType, entity]` allows targeted invalidation

## Migration Notes

This is a non-breaking change - all existing functionality is preserved. The primary difference is:
- Data is now cached automatically
- Loading/error states come from TanStack Query instead of manual useState
- Mutations automatically invalidate related queries

## References

- Current AppStateContext: `frontend/src/components/HwqaPage/context/AppStateContext.tsx`
- Existing useMetricsQuery: `frontend/src/components/HwqaPage/hooks/useMetricsQuery.ts`
- TanStack Query patterns: `frontend/src/hooks/services/*.ts`
- Service files: `frontend/src/components/HwqaPage/services/*.ts`
