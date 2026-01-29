---
date: 2026-01-14T10:30:00-05:00
researcher: Claude Code
git_commit: f43236206b6911a61658cf864300ac6684e0f2da
branch: IWA-14248
repository: fullstack.assetwatch
topic: "IWA-14248 Bug Root Cause - UniqueSensorCountLast7d Column Index Swap"
tags: [bug-analysis, root-cause, hub-statistics, transponder-metrics, timestream]
status: complete
last_updated: 2026-01-14
last_updated_by: Claude Code
---

# Bug Root Cause Analysis: IWA-14248 - Unique Sensors Last 7d Wrong by Factor of 10

**Date**: 2026-01-14T10:30:00-05:00
**Researcher**: Claude Code
**Branch**: IWA-14248
**Repository**: fullstack.assetwatch

## Problem Statement

The "Unique Sensors Last 7d" column on the CustomerDetail > Hubs page displays values that are approximately 10x higher than expected. For example, a hub might show 5,000 unique sensors when the actual count should be ~50.

## Root Cause

**Bug Location**: `assetwatch-jobs/terraform/jobs/jobs_insights/jobs-insights/tx_rx_metrics.py:99-101`

**Issue**: Column indices 2 and 3 are swapped when parsing Timestream query results in the `get_hub_metrics_data()` function.

### The Timestream Query (lines 72-91)

```sql
SELECT metrics7d.hub, metrics7d.readings_last_7d, metrics7d.unique_sensors_last_7d, metrics21d.readings_last_21d
FROM (
    SELECT hub,
           COUNT(temperature) AS readings_last_7d,
           approx_distinct(sensor) AS unique_sensors_last_7d
    FROM "vibration_sensor"."reading"
    WHERE time > ago(7d)
    GROUP BY hub
) metrics7d
INNER JOIN (
    SELECT hub,
           COUNT(temperature) AS readings_last_21d,
           approx_distinct(sensor) AS unique_sensors_last_21d
    FROM "vibration_sensor"."reading"
    WHERE time > ago(21d)
    GROUP BY hub
) metrics21d ON metrics7d.hub = metrics21d.hub
```

**Query returns columns in this order:**
| Index | Column Name |
|-------|-------------|
| [0] | hub |
| [1] | readings_last_7d |
| [2] | unique_sensors_last_7d |
| [3] | readings_last_21d |

### The Buggy Code (lines 97-106)

```python
for item in retVal:
    hub = item["Data"][0]["ScalarValue"]
    readings_7d = int(item["Data"][1]["ScalarValue"])
    readings_21d = int(item["Data"][2]["ScalarValue"])      # BUG: Index [2] is unique_sensors_last_7d!
    unique_sensors_7d = int(item["Data"][3]["ScalarValue"]) # BUG: Index [3] is readings_last_21d!

    hub_metrics[hub] = {
        "readings_last_7d": readings_7d,
        "unique_sensors_last_7d": unique_sensors_7d,  # Contains readings_21d value!
        "readings_last_21d": readings_21d,             # Contains unique_sensors_7d value!
    }
```

### Data Flow Impact

| Variable | Expected Source | Actual Source |
|----------|-----------------|---------------|
| `readings_7d` | `readings_last_7d` [1] | `readings_last_7d` [1] ✓ |
| `readings_21d` | `readings_last_21d` [3] | `unique_sensors_last_7d` [2] ✗ |
| `unique_sensors_7d` | `unique_sensors_last_7d` [2] | `readings_last_21d` [3] ✗ |

### Database Impact

The `TransponderMetric` table receives incorrect values:

| Database Column | Expected Value | Actual Value (Due to Bug) |
|-----------------|----------------|---------------------------|
| `ReadingsLast7d` | ~500-2000 readings | ~500-2000 readings ✓ |
| `UniqueSensorCountLast7d` | ~20-100 unique sensors | ~5000-20000 (readings_21d) ✗ |
| `ReadingsLast21d` | ~5000-20000 readings | ~20-100 (unique_sensors_7d) ✗ |

## Verification Methods

### Method 1: Sanity Check Query

If `UniqueSensorCountLast7d > ReadingsLast7d`, the bug is confirmed (you cannot have more unique sensors than readings):

```sql
SELECT
    t.SerialNumber,
    tm.ReadingsLast7d,
    tm.UniqueSensorCountLast7d,
    tm.ReadingsLast21d,
    CASE WHEN tm.UniqueSensorCountLast7d > tm.ReadingsLast7d THEN 'BUG_CONFIRMED' ELSE 'OK' END as status
FROM TransponderMetric tm
JOIN Transponder t ON t.TransponderID = tm.TransponderID
WHERE tm.ReadingsLast7d > 0
LIMIT 20;
```

### Method 2: Logical Anomaly Check

Readings in 21 days should always be >= readings in 7 days. With the bug, `ReadingsLast21d` (which actually contains unique sensors) will often be less than `ReadingsLast7d`:

```sql
SELECT COUNT(*) as anomaly_count
FROM TransponderMetric
WHERE ReadingsLast21d < ReadingsLast7d
  AND ReadingsLast7d > 0;
```

A high `anomaly_count` confirms the bug.

### Method 3: Direct Timestream Comparison

Run the Timestream query directly and compare the values at indices [2] and [3] with what's stored in the database.

## The Fix

```python
# CORRECT code (fix lines 99-101):
for item in retVal:
    hub = item["Data"][0]["ScalarValue"]
    readings_7d = int(item["Data"][1]["ScalarValue"])
    unique_sensors_7d = int(item["Data"][2]["ScalarValue"])  # Index 2 = unique_sensors
    readings_21d = int(item["Data"][3]["ScalarValue"])       # Index 3 = readings_21d

    hub_metrics[hub] = {
        "readings_last_7d": readings_7d,
        "unique_sensors_last_7d": unique_sensors_7d,
        "readings_last_21d": readings_21d,
    }
```

## Files Affected

### Source of Bug
- `assetwatch-jobs/terraform/jobs/jobs_insights/jobs-insights/tx_rx_metrics.py:99-101`

### Data Path (for reference)
1. **Timestream**: `vibration_sensor.reading` table
2. **Job**: `jobs_insights` Lambda (runs every 3 hours)
3. **Database**: `TransponderMetric` table
4. **Stored Procedure**: `Transponder_GetTransponderList` (line 116)
5. **Lambda**: `lf-vero-prod-hub` → `getHubList` method
6. **Frontend**: `HubListTab.tsx` → `sensorcnt` field

## Additional Notes

- The initial research suggested `approx_distinct()` accuracy might be the issue, but this was a red herring
- The actual error (~10x) is too large for `approx_distinct()` error margins (typically 2-5%)
- After the fix, the `jobs_insights` job will need to run to repopulate correct values
