# HWQA Tabler to FontAwesome Icon Migration Plan

## Overview

Migrate 39 Tabler icons to FontAwesome equivalents across 22 files in the HWQA module to maintain consistency with the AssetWatch codebase. AssetWatch uses FontAwesome Pro packages exclusively (513 occurrences across 245 files).

## Current State Analysis

### Tabler Usage Pattern
```typescript
import { IconCheck, IconAlertCircle } from "@tabler/icons-react";

<IconCheck size={16} />
<IconFilter size={20} stroke={1.5} />
```

### FontAwesome Usage Pattern (target)
```typescript
import { faCheck, faCircleExclamation } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";

<FontAwesomeIcon icon={faCheck} size="sm" />
<FontAwesomeIcon icon={faFilter} size="lg" />
```

### Key Discoveries
- Tabler uses numeric `size` prop (14, 16, 18, 20, 22 pixels)
- FontAwesome uses string `size` prop ("xs", "sm", "lg", "xl", "1x", "2x")
- Tabler `stroke={1.5}` maps to FontAwesome light variants
- AssetWatch predominantly uses `@fortawesome/pro-solid-svg-icons`

## Size Mapping

| Tabler Size | FontAwesome Size | Notes |
|-------------|------------------|-------|
| 14 | "xs" | Small badges |
| 16 | "sm" | Standard icons |
| 18 | "lg" | Medium emphasis |
| 20 | "lg" | Header icons |
| 22 | "xl" | Large headers |

## Icon Mapping Table

| Tabler Icon | FontAwesome Icon | Package | Files Using |
|-------------|------------------|---------|-------------|
| IconAlertCircle | faCircleExclamation | pro-solid | 5 |
| IconAlertTriangle | faTriangleExclamation | pro-solid | 1 |
| IconArrowRight | faArrowRight | pro-solid | 1 |
| IconArrowUpRight | faArrowUpRight | pro-solid | 1 |
| IconBook | faBook | pro-solid | 1 |
| IconBug | faBug | pro-solid | 1 |
| IconCalendar | faCalendarDay | pro-solid | 2 |
| IconCalendarStats | faCalendarRange | pro-solid | 1 |
| IconChartBar | faChartBar | pro-solid | 1 |
| IconChartLine | faChartLine | pro-solid | 2 |
| IconCheck | faCheck | pro-solid | 7 |
| IconChevronDown | faChevronDown | pro-solid | 2 |
| IconChevronRight | faChevronRight | pro-solid | 1 |
| IconChevronUp | faChevronUp | pro-solid | 1 |
| IconCopy | faCopy | pro-regular | 1 |
| IconDeviceAnalytics | faChartMixed | pro-solid | 2 |
| IconDeviceDesktop | faDesktop | pro-solid | 1 |
| IconDeviceWatch | faWatch | pro-solid | 1 |
| IconDownload | faDownload | pro-solid | 1 |
| IconFileExport | faFileExport | pro-solid | 1 |
| IconFileReport | faFileChartColumn | pro-solid | 1 |
| IconFileText | faFileLines | pro-solid | 1 |
| IconFilter | faFilter | pro-solid | 1 |
| IconFilterOff | faFilterSlash | pro-solid | 1 |
| IconInfoCircle | faCircleInfo | pro-solid | 1 |
| IconMoon | faMoon | pro-solid | 1 |
| IconPlus | faPlus | pro-solid | 2 |
| IconReportAnalytics | faChartColumn | pro-solid | 2 |
| IconRouter | faRouter | pro-solid | 2 |
| IconSearch | faMagnifyingGlass | pro-solid | 1 |
| IconSettings | faGear | pro-solid | 1 |
| IconSun | faSun | pro-solid | 1 |
| IconTable | faTable | pro-solid | 1 |
| IconTestPipe | faFlask | pro-solid | 2 |
| IconTools | faWrench | pro-solid | 1 |
| IconTrash | faTrash | pro-solid | 1 |
| IconUpload | faUpload | pro-solid | 1 |
| IconUser | faUser | pro-solid | 1 |
| IconX | faXmark | pro-solid | 1 |

## What We're NOT Doing

- Not changing any component logic or behavior
- Not modifying non-icon related code
- Not adding new icons beyond replacing existing ones
- Not changing the visual appearance significantly (just library swap)

## Implementation Approach

Process each file individually:
1. Update imports (remove Tabler, add FontAwesome)
2. Replace icon components with FontAwesomeIcon
3. Convert size props from numeric to string
4. Test that icons render correctly

## Phase 1: Common Components (6 files)

These components are reused throughout HWQA, so fixing them first ensures consistency.

### Files to Update:

#### 1. `frontend/src/hwqa/components/common/Modal/FormModal.tsx`
**Icons**: IconAlertCircle
```typescript
// Before
import { IconAlertCircle } from "@tabler/icons-react";
<Alert icon={<IconAlertCircle size={16} />} color="red">

// After
import { faCircleExclamation } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
<Alert icon={<FontAwesomeIcon icon={faCircleExclamation} size="sm" />} color="red">
```

#### 2. `frontend/src/hwqa/components/common/ExpandableSection/ExpandableSection.tsx`
**Icons**: IconChevronDown, IconChevronUp
```typescript
// Before
import { IconChevronDown, IconChevronUp } from "@tabler/icons-react";
{opened ? <IconChevronUp size={16} /> : <IconChevronDown size={16} />}

// After
import { faChevronDown, faChevronUp } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
{opened ? <FontAwesomeIcon icon={faChevronUp} size="sm" /> : <FontAwesomeIcon icon={faChevronDown} size="sm" />}
```

#### 3. `frontend/src/hwqa/components/common/DateRangeFilter/DateRangeFilter.tsx`
**Icons**: IconCalendar
```typescript
// Before
import { IconCalendar } from "@tabler/icons-react";
leftSection={<IconCalendar size={18} stroke={1.5} />}

// After
import { faCalendarDay } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
leftSection={<FontAwesomeIcon icon={faCalendarDay} size="lg" />}
```

#### 4. `frontend/src/hwqa/components/common/ThemeToggle/ThemeToggle.tsx`
**Icons**: IconSun, IconMoon
```typescript
// Before
import { IconSun, IconMoon } from "@tabler/icons-react";
{isDark ? <IconSun size={20} /> : <IconMoon size={20} />}

// After
import { faSun, faMoon } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
{isDark ? <FontAwesomeIcon icon={faSun} size="lg" /> : <FontAwesomeIcon icon={faMoon} size="lg" />}
```

#### 5. `frontend/src/hwqa/components/common/CSVExportButton/CSVExportButton.tsx`
**Icons**: IconDownload, IconFileExport, IconSettings
```typescript
// Before
import { IconDownload, IconFileExport, IconSettings } from "@tabler/icons-react";

// After
import { faDownload, faFileExport, faGear } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 6. `frontend/src/hwqa/components/features/glossary/DuplicateCheckAlert.tsx`
**Icons**: IconAlertTriangle, IconInfoCircle, IconCheck
```typescript
// Before
import { IconAlertTriangle, IconInfoCircle, IconCheck } from "@tabler/icons-react";

// After
import { faTriangleExclamation, faCircleInfo, faCheck } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

### Success Criteria (Phase 1):

#### Automated Verification:
- [x] No Tabler imports in common components: `grep -r "@tabler" frontend/src/hwqa/components/common`

#### Manual Verification:
- [ ] Icons render correctly in the UI
- [ ] Theme toggle works (sun/moon)
- [ ] Expandable sections expand/collapse
- [ ] CSV export menu displays correctly

---

## Phase 2: Page Components (5 files)

### Files to Update:

#### 1. `frontend/src/hwqa/pages/SensorDashboardPage.tsx`
**Icons**: IconReportAnalytics, IconChartLine
```typescript
// After
import { faChartColumn, faChartLine } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 2. `frontend/src/hwqa/pages/HubDashboardPage.tsx`
**Icons**: IconReportAnalytics, IconChartLine
```typescript
// After
import { faChartColumn, faChartLine } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 3. `frontend/src/hwqa/pages/SensorShipmentsPage.tsx`
**Icons**: IconCheck, IconAlertCircle
```typescript
// After
import { faCheck, faCircleExclamation } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 4. `frontend/src/hwqa/pages/HubShipmentsPage.tsx`
**Icons**: IconCheck, IconAlertCircle
```typescript
// After
import { faCheck, faCircleExclamation } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 5. `frontend/src/hwqa/pages/GlossaryPage.tsx`
**Icons**: IconBook, IconTestPipe, IconSearch, IconPlus, IconDeviceDesktop, IconRouter
```typescript
// After
import { faBook, faFlask, faMagnifyingGlass, faPlus, faDesktop, faRouter } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

### Success Criteria (Phase 2):

#### Automated Verification:
- [x] No Tabler imports in pages: `grep -r "@tabler" frontend/src/hwqa/pages`

#### Manual Verification:
- [ ] Dashboard tabs display icons correctly
- [ ] Shipment pages show success/error icons
- [ ] Glossary page tabs and buttons have correct icons

---

## Phase 3: Dashboard Feature Components (6 files)

### Files to Update:

#### 1. `frontend/src/hwqa/components/features/dashboard/DashboardFilters/DashboardFilters.tsx`
**Icons**: IconFilter, IconFilterOff, IconDeviceAnalytics, IconTestPipe, IconBug, IconRouter, IconUser, IconCalendar
```typescript
// After
import {
  faFilter, faFilterSlash, faChartMixed, faFlask,
  faBug, faRouter, faUser, faCalendarDay
} from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 2. `frontend/src/hwqa/components/features/dashboard/PassRateOverview/PassRateGraph.tsx`
**Icons**: IconChartBar
```typescript
// After
import { faChartBar } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 3. `frontend/src/hwqa/components/features/dashboard/RCCAReport/QAGoals/QAGoals.tsx`
**Icons**: IconCheck, IconTools, IconArrowUpRight
```typescript
// After
import { faCheck, faWrench, faArrowUpRight } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 4. `frontend/src/hwqa/components/features/dashboard/RCCAReport/SpreadsheetExport/SpreadsheetExport.tsx`
**Icons**: IconCheck, IconCopy, IconFileReport, IconFileText, IconTable
```typescript
// After
import { faCheck, faFileChartColumn, faFileLines, faTable } from "@fortawesome/pro-solid-svg-icons";
import { faCopy } from "@fortawesome/pro-regular-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 5. `frontend/src/hwqa/components/features/dashboard/RCCAReport/MetricsSummary/MetricsSummary.tsx`
**Icons**: IconDeviceAnalytics, IconCalendarStats, IconDeviceWatch
```typescript
// After
import { faChartMixed, faCalendarRange, faWatch } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 6. `frontend/src/hwqa/components/features/dashboard/RCCAReport/PhaseMetricsGrid/PhaseMetricsGrid.tsx`
**Icons**: IconChevronDown, IconChevronRight
```typescript
// After
import { faChevronDown, faChevronRight } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

### Success Criteria (Phase 3):

#### Automated Verification:
- [x] No Tabler imports in dashboard: `grep -r "@tabler" frontend/src/hwqa/components/features/dashboard`

#### Manual Verification:
- [ ] Dashboard filters display correctly
- [ ] RCCA report sections show icons
- [ ] Pass rate graph header icon visible

---

## Phase 4: Other Feature Components (5 files)

### Files to Update:

#### 1. `frontend/src/hwqa/components/features/tests/LogTestForm.tsx`
**Icons**: IconUpload
```typescript
// After
import { faUpload } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 2. `frontend/src/hwqa/components/features/tests/sequential-confirmation/SequentialConfirmationModal.tsx`
**Icons**: IconCheck, IconX, IconArrowRight
```typescript
// After
import { faCheck, faXmark, faArrowRight } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 3. `frontend/src/hwqa/components/features/shipments/ExcelGrid.tsx`
**Icons**: IconTrash, IconPlus
```typescript
// After
import { faTrash, faPlus } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 4. `frontend/src/hwqa/components/features/conversion/SensorConversion/RouteBasedSensorList.tsx`
**Icons**: IconAlertCircle
```typescript
// After
import { faCircleExclamation } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

#### 5. `frontend/src/hwqa/components/features/conversion/SensorConversion/SensorConversionForm.tsx`
**Icons**: IconAlertCircle, IconCheck
```typescript
// After
import { faCircleExclamation, faCheck } from "@fortawesome/pro-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
```

### Success Criteria (Phase 4):

#### Automated Verification:
- [x] No Tabler imports remain: `grep -r "@tabler" frontend/src/hwqa`

#### Manual Verification:
- [ ] Test forms show upload icon
- [ ] Sequential confirmation modal shows pass/fail icons
- [ ] Excel grid shows add/delete row icons
- [ ] Sensor conversion shows success/error alerts

---

## Phase 5: Cleanup

### Tasks:
1. Remove `@tabler/icons-react` from `frontend/package.json`
2. Run `npm install` to update lockfile
3. Verify no remaining Tabler imports

### Success Criteria (Phase 5):

#### Automated Verification:
- [x] No Tabler in package.json: `grep "@tabler" frontend/package.json`

#### Manual Verification:
- [ ] Application loads correctly
- [ ] All HWQA pages functional
- [ ] No console errors related to icons

---

## Testing Strategy

### Manual Testing Steps:
1. Navigate to HWQA module
2. Check each page:
   - Sensor Dashboard (tabs, filters)
   - Hub Dashboard (tabs, filters)
   - Sensor Shipments (alerts)
   - Hub Shipments (alerts)
   - Glossary (tabs, search, add buttons)
3. Test interactive elements:
   - Theme toggle (sun/moon icons)
   - Expandable sections (chevrons)
   - CSV export menu
   - Filter toggles
4. Test forms:
   - Log test form (upload button)
   - Sequential confirmation modal
   - Excel grid (add/delete rows)

## References

- Handoff: `docs/handoffs/2025-12-09_16-16-09_hwqa-phase2-icon-migration.md`
- Jira: IWA-14152 (Move HWQA code into Fullstack.AssetWatch repo)
- Branch: `db/IWA-14150`