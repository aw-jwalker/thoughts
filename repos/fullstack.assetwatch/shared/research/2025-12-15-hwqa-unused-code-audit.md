---
date: 2025-12-15T12:00:00-06:00
researcher: Claude
git_commit: 8bc02bd474fca15bb303c87c6e1a522aabb4a3b6
branch: db/IWA-14150
repository: fullstack.assetwatch
topic: "HWQA Frontend Unused Code Audit"
tags: [research, codebase, hwqa, cleanup, dead-code, css-consolidation]
status: complete
last_updated: 2025-12-15
last_updated_by: Claude
---

# Research: HWQA Frontend Unused Code Audit

**Date**: 2025-12-15T12:00:00-06:00
**Researcher**: Claude
**Git Commit**: 8bc02bd474fca15bb303c87c6e1a522aabb4a3b6
**Branch**: db/IWA-14150
**Repository**: fullstack.assetwatch

## Research Question
Identify unused or obsolete files and functions in the frontend HWQA module that have been superseded by shared AssetWatch code after the recent port into the fullstack.assetwatch repo.

## Summary

The HWQA module contains **117 files** with significant dead code from the migration. Key findings:

1. **8 files can be immediately deleted** (unused components and orphaned CSS)
2. **1 deprecated context** ready for removal after removing wrapper usage
3. **15 CSS module files** exist - the orphaned `ShipmentsPage.module.css` should be deleted
4. **No utility duplication** - HWQA utilities are domain-specific and not duplicated in shared code
5. **environment.ts was already deleted** and cleaned up successfully

## Detailed Findings

### Files Ready for Deletion (High Confidence)

#### Unused Shipment Components
These components were commented out of the barrel export and are never imported:

| File | Location | Reason |
|------|----------|--------|
| `CreateShipmentForm.tsx` | `features/shipments/` | Commented out in index.ts:5, never imported |
| `CreateShipmentForm.module.css` | `features/shipments/` | CSS for unused component |
| `PasteShipmentForm.tsx` | `features/shipments/` | Commented out in index.ts:2, never imported |
| `PasteShipmentForm.module.css` | `features/shipments/` | CSS for unused component |

#### Unused Glossary Components
These components form an unused component hierarchy:

| File | Location | Reason |
|------|----------|--------|
| `GlossaryList.tsx` | `features/glossary/` | Not exported, not imported anywhere |
| `GlossaryTabs.tsx` | `features/glossary/` | Only imported by unused GlossaryList |
| `GlossaryContent.tsx` | `features/glossary/` | Only imported by unused GlossaryList |

#### Orphaned CSS File (User's Known Issue)
| File | Location | Reason |
|------|----------|--------|
| `ShipmentsPage.module.css` | `pages/` | No corresponding component exists, not imported |

### Deprecated Context (Requires Migration)

#### AppStateContext (`context/AppStateContext.tsx`)
- **Status**: Marked `@deprecated` in comments
- **Description**: Empty context shell kept for backwards compatibility after TanStack Query migration
- **Exports**:
  - `AppStateProvider` - Empty provider with no state
  - `useAppState` - Hook that returns empty object `{}`
- **Current Usage**: Only in `/src/pages/Hwqa.tsx` lines 7 and 66
- **Migration Path**: Remove the wrapper in Hwqa.tsx, then delete context files

### CSS Files Inventory

All 15 CSS files use `.module.css` format (CSS Modules pattern):

```
pages/
└── ShipmentsPage.module.css ❌ (ORPHANED - DELETE)

layout/PageContainer/
└── PageContainer.module.css ✓

common/DateRangeFilter/
└── DateRangeFilter.module.css ✓

features/shipments/
├── CreateShipmentForm.module.css ❌ (UNUSED - DELETE)
├── ExcelGrid.module.css ✓
├── LogShipmentForm.module.css ✓
└── PasteShipmentForm.module.css ❌ (UNUSED - DELETE)

features/tests/
├── LogTestForm.module.css ✓
└── sequential-confirmation/SequentialConfirmationModal.module.css ✓

features/dashboard/DashboardFilters/
└── DashboardFilters.module.css ✓

features/dashboard/RCCAReport/
├── PhaseMetricsGrid/PhaseMetricsGrid.module.css ✓
├── PrimaryIssues/PrimaryIssues.module.css ✓
├── QAGoals/QAGoals.module.css ✓
├── ShipmentDetailsList/ShipmentDetailsList.module.css ✓
└── SpreadsheetExport/SpreadsheetExport.module.css ✓
```

**Consolidation Recommendation**: The CSS files are already well-organized by component. The module CSS pattern is appropriate for component-scoped styles. No consolidation needed beyond deleting the orphaned/unused files.

### Unused Constants

| Constant | File | Line | Reason |
|----------|------|------|--------|
| `DEFAULT_DASHBOARD_FILTERS` | `constants/dashboardDefaults.ts` | 77 | Never imported (but `DEFAULT_PASS_RATE_FILTERS` and `DEFAULT_RCCA_FILTERS` ARE used) |

### Code Cleanup Within Existing Files

| File | Lines | Issue |
|------|-------|-------|
| `MetricsSummary.tsx` | 6, 13-15, 36-40 | Commented-out imports and calculations |
| `features/shipments/index.ts` | 2, 5 | Commented-out exports |

### Shared Code Migration Status

HWQA has already migrated to use these shared AssetWatch patterns:

| Shared Import | HWQA Usage Count | Description |
|--------------|------------------|-------------|
| `@api/amplifyAdapter` | 9 files | All service layer files |
| `@contexts/AuthContext` | 9 files | Role-based access control |
| `@hooks/useColors` | 3 files | Theme-aware colors |
| `@hooks/useOrderedDataVisualColors` | 2 files | Chart data colors |
| `@hooks/useIsSmallScreen` | 1 file | Responsive design |
| `@shared/types/ColorTypes` | 5 files | Type-safe colors |
| `@styles/zIndex` | 2 files | Z-index constants |
| `@components/Utilities` | 3 files | `getJsDate` utility |
| `@utils/constants` | 1 file | Layout constants |

### Utility Files Analysis

The three HWQA utility files are **domain-specific** and not duplicated:

| Utility | Purpose | Duplication Risk |
|---------|---------|------------------|
| `dashboardTransformers.ts` | QA metrics transformation | None - HWQA-specific types |
| `textSimilarity.ts` | Glossary duplicate detection | None - unique functionality |
| `csvExport.ts` | AG Grid CSV export | None - shared `fileUtils.ts` handles uploads, not exports |

### Successfully Deleted Files

| File | Status |
|------|--------|
| `utils/environment.ts` | Deleted in current branch, no orphaned imports |

## Code References

### Files to Delete
- `frontend/src/components/HwqaPage/features/shipments/CreateShipmentForm.tsx`
- `frontend/src/components/HwqaPage/features/shipments/CreateShipmentForm.module.css`
- `frontend/src/components/HwqaPage/features/shipments/PasteShipmentForm.tsx`
- `frontend/src/components/HwqaPage/features/shipments/PasteShipmentForm.module.css`
- `frontend/src/components/HwqaPage/features/glossary/GlossaryList.tsx`
- `frontend/src/components/HwqaPage/features/glossary/GlossaryTabs.tsx`
- `frontend/src/components/HwqaPage/features/glossary/GlossaryContent.tsx`
- `frontend/src/components/HwqaPage/pages/ShipmentsPage.module.css`

### Files to Clean Up
- `frontend/src/components/HwqaPage/features/dashboard/RCCAReport/MetricsSummary/MetricsSummary.tsx:6,13-15,36-40` - Remove commented code
- `frontend/src/components/HwqaPage/features/shipments/index.ts:2,5` - Remove commented exports
- `frontend/src/components/HwqaPage/constants/dashboardDefaults.ts:77` - Remove unused `DEFAULT_DASHBOARD_FILTERS`

### Context Migration
- `frontend/src/pages/Hwqa.tsx:7,66` - Remove AppStateProvider wrapper
- `frontend/src/components/HwqaPage/context/AppStateContext.tsx` - Delete after migration
- `frontend/src/components/HwqaPage/context/index.ts` - Delete after migration
- `frontend/src/components/HwqaPage/index.ts:5` - Remove context exports

## Architecture Insights

### HWQA Module Structure (117 files)
```
HwqaPage/
├── pages/          (9 files) - Top-level page components
├── features/       (75 files) - Feature-specific components
│   ├── dashboard/  - PassRateOverview, RCCAReport, DashboardFilters
│   ├── shipments/  - Shipment logging and management
│   ├── tests/      - Test logging and management
│   ├── glossary/   - Failure types and test specs management
│   └── conversion/ - Sensor conversion tools
├── common/         (9 files) - Reusable components
├── hooks/          (7 files) - TanStack Query hooks (recently migrated)
├── services/       (9 files) - API service layer
├── utils/          (3 files) - Domain-specific utilities
├── context/        (2 files) - DEPRECATED, to be removed
├── types/          (1 file) - TypeScript interfaces
├── enums/          (1 file) - Tab enum
├── shared/enums/   (4 files) - ProductType, TestAction, etc.
├── constants/      (1 file) - Dashboard defaults
└── layout/         (3 files) - PageContainer
```

### Recent Migration Pattern
Based on recent commits, HWQA has been migrating from local state management (AppStateContext) to TanStack Query hooks:
- `8bc02bd47` - refactor(hwqa): slim down AppStateContext after TanStack Query migration
- `d35600ef1` - feat(hwqa): migrate conversion components to TanStack Query hooks
- `e63a43dee` - feat(hwqa): migrate dashboard filters to TanStack Query hooks
- `bbd606a70` - feat(hwqa): migrate glossary page to TanStack Query hooks
- `b6cbd0589` - feat(hwqa): migrate shipment pages to TanStack Query hooks

## Open Questions

1. **Should the README.md in features/shipments/ be updated or deleted?** It references CreateShipmentForm and PasteShipmentForm which are unused.

2. **Feature flags**: `SHOW_DEV_FEATURES` constants in HubShipmentsPage.tsx and SensorShipmentsPage.tsx appear to control the visibility of these unused shipment components. Should they remain as toggles for future features?

3. **Date formatting consolidation**: Multiple date formatting approaches exist (Luxon in csvExport.ts, custom formatters in PassRateOverview). Consider consolidating to a shared date formatting utility.
