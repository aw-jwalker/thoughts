---
date: 2025-01-28T12:00:00-06:00
researcher: Claude
git_commit: 73664cd4c4129c65ce2eb1ee71eb4f906b580b87
branch: dev
repository: fullstack.assetwatch
topic: "DefaultMonitoringPointReadingSetting Table Usage Analysis"
tags: [research, codebase, database, monitoring-point, reading-settings]
status: complete
last_updated: 2025-01-28
last_updated_by: Claude
---

# Research: DefaultMonitoringPointReadingSetting Table Usage Analysis

**Date**: 2025-01-28T12:00:00-06:00
**Researcher**: Claude
**Git Commit**: 73664cd4c4129c65ce2eb1ee71eb4f906b580b87
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question

Is the `DefaultMonitoringPointReadingSetting` database table properly being used by the backend/frontend?

## Summary

**The `DefaultMonitoringPointReadingSetting` table is NOT actively used by the backend or frontend.** The table exists in the database with seeded default values (Frequency: 6400, Samples: 8192), but no stored procedures query it, and the frontend hardcodes identical default values in `constants.ts` rather than fetching them from the database.

## Detailed Findings

### Database Table Definition

**Location**: `mysql/db/table_change_scripts/V000000129__AddMPReadingSettingTable.sql:40-47`

The migration creates the `DefaultMonitoringPointReadingSetting` table with:
- `DefaultMonitoringPointReadingSettingID` (INT, AUTO_INCREMENT, PRIMARY KEY)
- `Frequency` (INT, DEFAULT NULL)
- `Samples` (INT, DEFAULT NULL)

Initial seed data:
```sql
INSERT INTO `DefaultMonitoringPointReadingSetting` (`Frequency`, `Samples`) VALUES ('6400', '8192');
```

### Stored Procedures - No Usage

A grep search across all stored procedures in `mysql/db/procs/` for `DefaultMonitoringPointReadingSetting` returns **zero matches**.

The related stored procedures only interact with `MonitoringPointReadingSetting` (the per-monitoring-point table):

1. **`MonitoringPoint_GetReadingSettings`** (`mysql/db/procs/R__PROC_MonitoringPoint_GetReadingSettings.sql:5-16`)
   - Queries `MonitoringPointReadingSetting` joined with `MonitoringPoint`
   - Does NOT fall back to `DefaultMonitoringPointReadingSetting` when no per-MP settings exist
   - Returns NULL values for Samples/SampleRate if no record exists

2. **`MonitoringPoint_UpdateReadingSettings`** (`mysql/db/procs/R__PROC_MonitoringPoint_UpdateReadingSettings.sql:5-34`)
   - Inserts/updates `MonitoringPointReadingSetting` for a specific monitoring point
   - Does NOT reference `DefaultMonitoringPointReadingSetting`

3. **`MonitoringPoint_UpdateReadingSettingsMobile`** (`mysql/db/procs/R__PROC_MonitoringPoint_UpdateReadingSettingsMobile.sql`)
   - Mobile-specific version with optimistic locking
   - Also does NOT reference `DefaultMonitoringPointReadingSetting`

### Frontend Implementation

**Location**: `frontend/src/components/AssetDetailPage/MonitoringPointReadingSettings.tsx`

The frontend handles defaults in the query function at lines 59-78:

```typescript
const readingSettingsQuery = useQuery({
  queryKey: ["monitoringPoint-reading-settings", monitoringPointId],
  queryFn: async () => {
    const response = await getMonitoringPointReadingSettings(monitoringPointId);

    if (response[0].Samples) {
      return {
        Samples: response[0].Samples,
        SampleRate: response[0].SampleRate,
      };
    }
    return DEFAULT_COLLECT_PARAMS;  // Hardcoded fallback
  },
});
```

When the database returns null/empty values, the frontend falls back to `DEFAULT_COLLECT_PARAMS`.

**Location**: `frontend/src/utils/constants.ts:17-20`

```typescript
export const DEFAULT_COLLECT_PARAMS = {
  Samples: 8192,
  SampleRate: 6400,
};
```

These values are **identical** to what's stored in `DefaultMonitoringPointReadingSetting`, but they are hardcoded rather than fetched from the database.

### Backend Lambda

**Location**: `lambdas/lf-vero-prod-monitoringpoint/main.py`

The Lambda handlers at lines 966-972 and 1225-1237 call the stored procedures but don't directly interact with `DefaultMonitoringPointReadingSetting`.

### Test Infrastructure

The table IS referenced in test infrastructure:

1. **`lambdas/tests/db/tables/DefaultMonitoringPointReadingSetting.ts`** - Test data management class
2. **`lambdas/tests/db/dockerDB/init_scripts/enum_tables.txt:17`** - Listed for Docker test initialization
3. **`lambdas/tests/db/dockerDB/init_scripts/init_enum_tables.sql:207-214`** - Table creation and seed data for tests

## Architecture Documentation

### Current Data Flow

```
Frontend Form (MonitoringPointReadingSettings.tsx)
    ↓ calls
API Service (MonitoringPointService.ts)
    ↓ POST
Lambda (lf-vero-prod-monitoringpoint/main.py)
    ↓ calls
Stored Proc (MonitoringPoint_GetReadingSettings)
    ↓ queries
MonitoringPointReadingSetting table (per-MP settings only)
    ↓ returns NULL if no record
Frontend applies hardcoded DEFAULT_COLLECT_PARAMS
```

### Table Relationships

```
DefaultMonitoringPointReadingSetting (UNUSED)
    - Contains system-wide default values
    - ID: 1, Frequency: 6400, Samples: 8192
    - No foreign keys
    - No procedures reference it

MonitoringPointReadingSetting (USED)
    - Per-monitoring-point overrides
    - FK to MonitoringPoint.MonitoringPointID
    - Queried by MonitoringPoint_GetReadingSettings
    - Updated by MonitoringPoint_UpdateReadingSettings
```

## Code References

- `mysql/db/table_change_scripts/V000000129__AddMPReadingSettingTable.sql:40-47` - Table creation
- `mysql/db/procs/R__PROC_MonitoringPoint_GetReadingSettings.sql:9-15` - Get proc (doesn't use defaults table)
- `mysql/db/procs/R__PROC_MonitoringPoint_UpdateReadingSettings.sql:23-31` - Update proc
- `frontend/src/utils/constants.ts:17-20` - Hardcoded defaults
- `frontend/src/components/AssetDetailPage/MonitoringPointReadingSettings.tsx:71-77` - Fallback logic
- `lambdas/tests/db/tables/DefaultMonitoringPointReadingSetting.ts` - Test helper class

## Historical Context

The table appears to have been created with the intention of providing configurable system-wide defaults, but the implementation was completed using hardcoded frontend constants instead. The database table exists and is seeded but serves no functional purpose in the current system.

## Open Questions

1. Was there an intended feature to allow admins to modify default reading settings that was never completed?
2. Should the stored procedure `MonitoringPoint_GetReadingSettings` be modified to fall back to `DefaultMonitoringPointReadingSetting` when no per-MP settings exist?
3. Should the frontend fetch defaults from the database instead of using hardcoded constants?
4. Is this table safe to remove, or are there plans to use it in the future?
