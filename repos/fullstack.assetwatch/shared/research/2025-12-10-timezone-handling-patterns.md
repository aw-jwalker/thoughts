---
date: 2025-12-10T15:30:00-05:00
researcher: aw-jwalker
git_commit: f239d91ae10bdd623d4512302a93c0e3023c0bf4
branch: db/IWA-14150
repository: fullstack.assetwatch
topic: "Timezone handling patterns and refactoring timezone.py"
tags: [research, timezone, python, luxon, pytz, zoneinfo, UTC]
status: complete
last_updated: 2025-12-10
last_updated_by: aw-jwalker
---

# Research: Timezone Handling Patterns and Refactoring timezone.py

**Date**: 2025-12-10T15:30:00-05:00
**Researcher**: aw-jwalker
**Git Commit**: f239d91ae10bdd623d4512302a93c0e3023c0bf4
**Branch**: db/IWA-14150
**Repository**: fullstack.assetwatch

## Research Question

Can `/lambdas/lf-vero-prod-hwqa/app/utils/timezone.py` be refactored to handle timezones using the same method as the rest of the AssetWatch repo? What patterns does SensorDetail/SensorFacilityHistory use for timezone handling?

## Summary

The AssetWatch codebase follows a **UTC-everywhere storage with frontend display conversion** pattern. The current `timezone.py` implementation in HWQA lambda diverges from the predominant patterns in two ways:

1. **Library choice**: Uses `zoneinfo` (Python 3.9+) while most other lambdas use `pytz`
2. **Default behavior**: Assumes naive datetimes are in `America/New_York` timezone, rather than assuming UTC

The SensorDetail and SensorFacilityHistory data flow demonstrates the canonical pattern: database stores UTC datetimes, returns them without conversion, and the frontend uses Luxon to convert to local time for display.

## Detailed Findings

### Current timezone.py Implementation

**File**: `/lambdas/lf-vero-prod-hwqa/app/utils/timezone.py:1-21`

```python
from datetime import datetime
from zoneinfo import ZoneInfo
import os

DEFAULT_TIMEZONE = os.environ.get('TIMEZONE', 'America/New_York')

def convert_to_timezone(dt: datetime, target_tz: str = None) -> datetime:
    if not dt.tzinfo:
        # Assumes naive datetime is in America/New_York
        dt = dt.replace(tzinfo=ZoneInfo(DEFAULT_TIMEZONE))
    if target_tz:
        target_timezone = ZoneInfo(target_tz)
        dt = dt.astimezone(target_timezone)
    return dt
```

**Key characteristics**:
- Uses Python 3.9+ `zoneinfo` module
- Environment variable `TIMEZONE` with default `'America/New_York'`
- Naive datetimes assumed to be in the default timezone (not UTC)

---

### Pattern 1: Frontend Timezone Handling (Luxon)

The frontend uses **Luxon v3.2.1** as the primary date/time library.

**Core utilities**: `/frontend/src/components/Utilities.ts:88-131`

```typescript
// createDateTime - marks SQL strings as UTC by appending 'Z'
export function createDateTime(rawDate, noOffset = false): DateTime {
  return typeof rawDate === "string"
    ? DateTime.fromSQL(noOffset ? rawDate : `${rawDate}Z`)  // 'Z' marks as UTC
    : DateTime.fromJSDate(rawDate);
}

// formatDate - converts to UTC for SQL, local for display
export function formatDate(rawDate, options = {}) {
  const date = createDateTime(rawDate, noOffset);
  if (toSql) return date.toUTC().toFormat(formatString || "yyyy-MM-dd TT");
  return date.toLocaleString(DateTime[luxonPreset || DateTimeFormat.DATETIME_SHORT]);
}
```

**Key pattern**:
- Database DATETIME strings have 'Z' appended to mark as UTC
- Luxon automatically converts to browser's local timezone for display
- When sending to backend, `.toUTC()` converts to UTC format

---

### Pattern 2: Backend Lambda Timezone Handling (pytz)

Most lambdas use **pytz v2022.7.1** for timezone operations.

**Graph Lambda**: `/lambdas/lf-vero-prod-graph/query_timestream.py:35-63`

```python
import pytz

def toUTC(d):
    tz = pytz.timezone("US/Eastern")
    d_tz = tz.normalize(tz.localize(d))
    utc = pytz.timezone("UTC")
    return d_tz.astimezone(utc)

def epoch_to_localtime(epoch_timestamp, timezone):
    tz = pytz.timezone(timezone)
    dt = datetime.datetime.fromtimestamp(epoch_timestamp, tz)
    return dt.strftime("%Y-%m-%dT%H:%M:%S")
```

**Notification Lambda**: `/lambdas/lf-vero-prod-notification/generate_html.py:509-519`

```python
# UTC timestamp → America/New_York for display
utc_dt = datetime.datetime.utcfromtimestamp(timestamp).replace(tzinfo=pytz.utc)
tz = pytz.timezone("America/New_York")
dt = utc_dt.astimezone(tz)
formatted_date = dt.strftime("%Y-%m-%d %H:%M:%S %Z%z")
```

**Facilities Lambda**: `/lambdas/lf-vero-prod-facilities/facility_hardware_utils.py:80-90`

```python
from datetime import datetime, timezone, timedelta

# All calculations done in UTC
now = datetime.now(timezone.utc)
query_start_time_ms = int(query_start_time.timestamp() * 1000)
```

---

### Pattern 3: Database Timezone Handling (MySQL)

**UTC Storage**: All datetime columns store UTC after migration `V000000004__IWA-4809_UpdateTablesToUTC.sql`

**Current time recording**: Uses `UTC_TIMESTAMP()` directly

```sql
-- R__PROC_Reading_Update.sql:56
UPDATE HardwareIssue
SET DateResolved = UTC_TIMESTAMP()
```

**Timezone conversions in procedures**: Uses `CONVERT_TZ()` with hardcoded 'America/New_York'

```sql
-- R__PROC_Reading_Update.sql:36
SET inDateCreated = CONVERT_TZ(inDateCreatedUTC, 'UTC', 'America/New_York');

-- R__PROC_Reading_Update.sql:70-72
UPDATE Receiver SET LastReadingDate=CONVERT_TZ(inDateCreated, 'America/New_York', 'GMT')
```

**User/Facility timezone preferences**: Stored as strings

```sql
-- Users.TimeZone VARCHAR(100) DEFAULT 'America/New_York'
-- Facility.TimezoneName VARCHAR(100)
```

---

### SensorDetail/SensorFacilityHistory Pattern

This is the **cleanest UTC pattern** in the codebase:

**Database**: `/mysql/db/procs/R__PROC_Receiver_GetSensorDetail.sql:17`

```sql
SET @CurrentTime = (SELECT UTC_TIMESTAMP());
-- Returns datetimes as-is (stored in UTC), no CONVERT_TZ calls
```

**Lambda**: `/lambdas/lf-vero-prod-sensor/main.py:122-171`

- TimeStream timestamps returned as-is (ISO 8601 UTC)
- No timezone conversions in Python code
- Epoch timestamps passed through to frontend

**Frontend**: `/frontend/src/pages/ReceiverDetail.tsx:100-102`

```typescript
const asOfDate = formatDate(DateTime.now().minus({ days: 21 }), { toSql: true });
```

**Data Flow**:
```
MySQL DATETIME (UTC) → Lambda returns as-is → Frontend createDateTime() + 'Z' → Luxon .toLocal() → Display
```

---

## Timezone Library Comparison

| Library | Used In | Pros | Cons |
|---------|---------|------|------|
| `zoneinfo` (Python 3.9+) | HWQA lambda | Built-in, modern, no dependency | Different from other lambdas |
| `pytz` | Graph, Notification, iAlert lambdas | Well-established, most lambdas use it | Requires dependency, deprecated in favor of zoneinfo |
| `datetime.timezone.utc` | Facilities, HWQA auth | Built-in, simple UTC handling | UTC only, no named timezones |

---

## Code References

### timezone.py (current)
- `/lambdas/lf-vero-prod-hwqa/app/utils/timezone.py:1-21` - Current implementation

### Frontend timezone utilities
- `/frontend/src/components/Utilities.ts:88-97` - `createDateTime()` function
- `/frontend/src/components/Utilities.ts:118-131` - `formatDate()` function
- `/frontend/src/components/common/SelectTimezone.tsx:8-24` - Timezone list component

### Backend timezone patterns
- `/lambdas/lf-vero-prod-graph/query_timestream.py:35-63` - pytz usage
- `/lambdas/lf-vero-prod-notification/generate_html.py:509-519` - UTC to Eastern conversion
- `/lambdas/lf-vero-prod-facilities/facility_hardware_utils.py:80-90` - timezone.utc usage

### Database timezone handling
- `/mysql/db/table_change_scripts/V000000004__IWA-4809_UpdateTablesToUTC.sql` - UTC migration
- `/mysql/db/procs/R__PROC_Reading_Update.sql:36,70-72` - CONVERT_TZ usage
- `/mysql/db/procs/R__PROC_Receiver_GetSensorDetail.sql:17` - UTC_TIMESTAMP usage

### SensorDetail data flow
- `/mysql/db/procs/R__PROC_Receiver_GetSensorDetail.sql` - Database query
- `/lambdas/lf-vero-prod-sensor/main.py:122-171` - Lambda handler
- `/frontend/src/pages/ReceiverDetail.tsx:100-102` - Frontend usage

---

## Architecture Documentation

### Predominant Pattern: UTC-Everywhere

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Frontend  │ → │   Lambda    │ → │   MySQL     │ → │  TimeStream │
│   (Luxon)   │    │   (pytz)    │    │   (UTC)     │    │   (UTC)     │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
       │                   │                │                   │
       ▼                   ▼                ▼                   ▼
  .toUTC() for       Pass-through      UTC_TIMESTAMP()    Timestamps
   submissions       or pytz conv.      DATETIME(UTC)      in UTC
       │                   │                │                   │
       ▼                   ▼                ▼                   ▼
  .toLocal() for     Return as-is     No CONVERT_TZ       ISO 8601
    display          (or formatted)    (for clean path)     format
```

### Exception Pattern: Legacy America/New_York Processing

Some stored procedures still convert to America/New_York for internal processing, then back to GMT/UTC for storage. This is legacy behavior found in:
- `R__PROC_Reading_Update.sql`
- `R__PROC_MonitoringPointMetric_*.sql` procedures
- `R__PROC_Hub_GetLastDiagnostic.sql` (for display)

---

## Refactoring Considerations

### Option A: Align with pytz pattern (consistency)

```python
import pytz
from datetime import datetime

DEFAULT_TIMEZONE = 'UTC'  # Assume UTC, not America/New_York

def convert_to_timezone(dt: datetime, target_tz: str = None) -> datetime:
    if not dt.tzinfo:
        # Assume naive datetime is UTC (matches database storage)
        dt = pytz.utc.localize(dt)
    if target_tz:
        target_timezone = pytz.timezone(target_tz)
        dt = dt.astimezone(target_timezone)
    return dt
```

### Option B: Keep zoneinfo but align behavior

```python
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

def convert_to_timezone(dt: datetime, target_tz: str = None) -> datetime:
    if not dt.tzinfo:
        # Assume naive datetime is UTC (matches database storage)
        dt = dt.replace(tzinfo=timezone.utc)
    if target_tz:
        dt = dt.astimezone(ZoneInfo(target_tz))
    return dt
```

### Key Change: Default to UTC, not America/New_York

The SensorDetail pattern shows the cleanest approach:
1. Database stores UTC
2. Lambda returns timestamps without conversion
3. Frontend handles all display conversion

---

## Open Questions

1. **What is the HWQA lambda's specific use case for timezone conversion?** Need to understand if it's for display or processing to determine the right refactoring approach.

2. **Is the `TIMEZONE` environment variable actually set in production?** If not, the default America/New_York may be causing issues.

3. **Does HWQA lambda interact with the same database tables?** If so, it should follow the UTC storage pattern.
