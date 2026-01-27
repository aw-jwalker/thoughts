---
date: 2026-01-26T14:40:49-05:00
researcher: Claude
git_commit: 881ecbe11513e5a273e8706367f4d7af534361d9
branch: dev
repository: fullstack.assetwatch
topic: "Schedule Inheritance Bug - Impact Analysis and Affected Records Identification"
tags: [research, database, ReceiverSchedule, MonitoringPoint, bug-analysis, data-remediation]
status: complete
last_updated: 2026-01-26
last_updated_by: Claude
---

# Research: Schedule Inheritance Bug - Impact Analysis

**Date**: 2026-01-26T14:40:49-05:00
**Researcher**: Claude
**Git Commit**: 881ecbe11513e5a273e8706367f4d7af534361d9
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question

Identify all monitoring points affected by the schedule inheritance bug where:
- A sensor with a custom schedule was replaced
- The replacement sensor incorrectly received the default schedule instead of inheriting the custom schedule

## Summary

**505 monitoring points currently have incorrect schedules** that need to be fixed. The bug has existed since at least 2022, but the majority of unfixed cases (416) occurred in 2025, with a major spike in October 2025 (269 cases). October 15, 2025 alone had 64 affected replacements.

### Key Findings

| Metric | Count |
|--------|-------|
| Total MPs still needing fix (all time) | **505** |
| From 2025 | 416 |
| From 2024 | 78 |
| From 2023 | 8 |
| From 2022 | 1 |
| From 2026 (Jan) | 2 |

### Frequencies Needing Restoration

| Correct Frequency | Samples | Count |
|-------------------|---------|-------|
| 1600 Hz | 8192 | 183 |
| 3200 Hz | 8192 | 166 |
| 400 Hz | 8192 | 65 |
| 800 Hz | 8192 | 61 |
| Others | Various | 30 |

---

## Background: The Bug

### What Should Happen
When a sensor is replaced on a monitoring point:
1. The system should look up the previous sensor's schedule
2. The new sensor should inherit that schedule (same Frequency and Samples)

### What Actually Happened (The Bug)
When a sensor was replaced:
1. The new sensor received the **default schedule** (6400 Hz, 8192 samples)
2. The previous sensor's custom schedule was **not inherited**

### Why This Matters
- Schedule parameters (Frequency, Samples) are determined by the **machine** the monitoring point is on
- The machine doesn't change when a sensor is replaced
- Therefore, the schedule should always be preserved across sensor replacements

---

## Query Progression: Building the Analysis Step by Step

### Step 1: Understand the Default Schedule Values

**Purpose**: Confirm what "default" means in the system.

```sql
-- Query 1.1: Check the default schedule configuration
SELECT * FROM DefaultMonitoringPointReadingSetting LIMIT 10;
```

**Result**:
- Frequency: **6400**
- Samples: **8192**

This confirms the default values we need to filter against.

---

### Step 2: Understand Schedule Distribution

**Purpose**: See what schedule variations exist in the system.

```sql
-- Query 2.1: All distinct Frequency/Samples combinations
SELECT
    Frequency,
    Samples,
    COUNT(*) as count
FROM ReceiverSchedule
GROUP BY Frequency, Samples
ORDER BY count DESC
LIMIT 20;
```

**Result Summary**:
| Frequency | Samples | Count | Type |
|-----------|---------|-------|------|
| 6400 | 8192 | 3,195,422 | DEFAULT (~91%) |
| 1600 | 8192 | 93,306 | Custom |
| 400 | 8192 | 91,766 | Custom |
| 3200 | 8192 | 67,408 | Custom |
| 800 | 8192 | 49,911 | Custom |

**Insight**: ~91% of schedules are default. Custom schedules are relatively rare but significant.

---

### Step 3: Understand Sensor Replacement Patterns

**Purpose**: Find monitoring points that have had multiple sensors (where replacements occurred).

```sql
-- Query 3.1: MPs with multiple sensors assigned over time
SELECT
    MonitoringPointID,
    COUNT(*) as sensor_count
FROM MonitoringPoint_Receiver
GROUP BY MonitoringPointID
HAVING COUNT(*) > 1
ORDER BY sensor_count DESC
LIMIT 20;
```

**Result**: Many MPs have had 2-20+ sensors over their lifetime. Some test MPs have had 100+ sensors.

---

### Step 4: Find MPs with Custom Schedules AND Replacements

**Purpose**: Narrow down to MPs where the bug COULD have occurred.

```sql
-- Query 4.1: MPs that have had custom schedules AND multiple sensors
SELECT DISTINCT mpr.MonitoringPointID
FROM MonitoringPoint_Receiver mpr
JOIN ReceiverSchedule rs ON mpr.ReceiverID = rs.ReceiverID
WHERE (rs.Frequency != 6400 OR rs.Samples != 8192)
LIMIT 10;
```

**Result**: Found 10 sample MPs with custom schedules to investigate further.

---

### Step 5: Examine a Single MP's Schedule History

**Purpose**: Understand the data structure by looking at one MP in detail.

```sql
-- Query 5.1: Full schedule history for one MP
SELECT
    mpr.MonitoringPointID,
    mpr.ReceiverID,
    r.SerialNumber,
    mpr.StartDate as SensorAssignedDate,
    mpr.EndDate as SensorRemovedDate,
    CASE WHEN mpr.ActiveFlag = 1 THEN 'Active' ELSE 'Inactive' END as SensorStatus,
    rs.ReceiverScheduleID,
    rs.Frequency,
    rs.Samples,
    rs.DateCreated as ScheduleCreated,
    rs.ReceiverScheduleStatusID
FROM MonitoringPoint_Receiver mpr
JOIN Receiver r ON mpr.ReceiverID = r.ReceiverID
LEFT JOIN ReceiverSchedule rs ON mpr.ReceiverID = rs.ReceiverID
WHERE mpr.MonitoringPointID = 3450
ORDER BY mpr.StartDate, rs.DateCreated;
```

**Insight**: This showed how schedules evolve over time. A sensor may have many schedule records as users adjust settings.

---

### Step 6: Identify the Key Data Points

**Purpose**: For each sensor replacement, we need to compare:
1. **Old sensor's LAST schedule** (before removal) - this is the "correct" schedule
2. **New sensor's FIRST schedule** (after assignment) - if this is default, it's the bug

```sql
-- Query 6.1: Get LAST schedule for each sensor on an MP
SELECT
    mpr.MonitoringPointID,
    mpr.ReceiverID,
    rs.ReceiverScheduleID,
    rs.Frequency,
    rs.Samples,
    rs.DateCreated as LastScheduleDate,
    CASE WHEN rs.Frequency = 6400 AND rs.Samples = 8192 THEN 'DEFAULT' ELSE 'CUSTOM' END as ScheduleType
FROM MonitoringPoint_Receiver mpr
JOIN Receiver r ON mpr.ReceiverID = r.ReceiverID
LEFT JOIN ReceiverSchedule rs ON mpr.ReceiverID = rs.ReceiverID
    AND rs.ReceiverScheduleID = (
        SELECT MAX(rs2.ReceiverScheduleID)
        FROM ReceiverSchedule rs2
        WHERE rs2.ReceiverID = mpr.ReceiverID
    )
WHERE mpr.MonitoringPointID = 71284
ORDER BY mpr.StartDate ASC;
```

---

### Step 7: Define the Bug Pattern Query

**Purpose**: Find sensor replacements where old sensor had CUSTOM → new sensor got DEFAULT.

**Key Logic**:
- `mpr_new.StartDate = mpr_old.EndDate` - Direct replacement (new sensor starts when old ends)
- `rs_old` = MAX ReceiverScheduleID where DateCreated <= EndDate (last schedule before removal)
- `rs_new_first` = MIN ReceiverScheduleID where DateCreated >= StartDate (first schedule after assignment)

```sql
-- Query 7.1: Find the bug pattern (with date filter for testing)
SELECT
    mpr_old.MonitoringPointID,
    mpr_old.ReceiverID AS OldReceiverID,
    mpr_old.EndDate AS OldSensorRemovedDate,
    mpr_new.ReceiverID AS NewReceiverID,
    mpr_new.StartDate AS NewSensorAssignedDate,
    rs_old.Frequency AS OldSensorLastFreq,
    rs_old.Samples AS OldSensorLastSamples,
    rs_new.Frequency AS NewSensorFirstFreq,
    rs_new.Samples AS NewSensorFirstSamples

FROM MonitoringPoint_Receiver mpr_old

-- Join to find the replacement sensor
JOIN MonitoringPoint_Receiver mpr_new
    ON mpr_old.MonitoringPointID = mpr_new.MonitoringPointID
    AND mpr_new.StartDate = mpr_old.EndDate  -- Direct replacement
    AND mpr_new.ReceiverID != mpr_old.ReceiverID

-- Get old sensor's LAST schedule before removal
JOIN ReceiverSchedule rs_old ON rs_old.ReceiverID = mpr_old.ReceiverID
    AND rs_old.ReceiverScheduleID = (
        SELECT MAX(rs2.ReceiverScheduleID)
        FROM ReceiverSchedule rs2
        WHERE rs2.ReceiverID = mpr_old.ReceiverID
          AND rs2.DateCreated <= mpr_old.EndDate
    )

-- Get new sensor's FIRST schedule after assignment
JOIN ReceiverSchedule rs_new ON rs_new.ReceiverID = mpr_new.ReceiverID
    AND rs_new.ReceiverScheduleID = (
        SELECT MIN(rs3.ReceiverScheduleID)
        FROM ReceiverSchedule rs3
        WHERE rs3.ReceiverID = mpr_new.ReceiverID
          AND rs3.DateCreated >= mpr_new.StartDate
    )

-- Filter: Old sensor had CUSTOM, New sensor got DEFAULT
WHERE (rs_old.Frequency != 6400 OR rs_old.Samples != 8192)  -- Old was CUSTOM
  AND rs_new.Frequency = 6400 AND rs_new.Samples = 8192     -- New got DEFAULT
  AND mpr_old.EndDate >= '2024-01-01'  -- Date filter for testing

ORDER BY mpr_old.EndDate DESC
LIMIT 50;
```

**Result**: Successfully identified bug instances! This query found the pattern.

---

### Step 8: Add "Still Needs Fixing" Filter

**Purpose**: Filter to only MPs that CURRENTLY still have the wrong schedule.

The key additions:
1. `rs_current` = MAX ReceiverScheduleID (what schedule the sensor has NOW)
2. Filter: `rs_current.Frequency = 6400 AND rs_current.Samples = 8192`
3. Filter: `mpr_new.ActiveFlag = 1` (sensor is still active on this MP)

```sql
-- Query 8.1: MPs that CURRENTLY still need fixing
SELECT
    mpr_old.MonitoringPointID,
    mp.MonitoringPointName,
    rs_old.Frequency AS CorrectFrequency,
    rs_old.Samples AS CorrectSamples,
    mpr_new.ReceiverID AS CurrentReceiverID,
    r_new.SerialNumber AS CurrentSensorSerial,
    rs_current.Frequency AS CurrentFrequency,
    rs_current.Samples AS CurrentSamples,
    mpr_old.EndDate AS ReplacementDate

FROM MonitoringPoint_Receiver mpr_old
JOIN MonitoringPoint mp ON mpr_old.MonitoringPointID = mp.MonitoringPointID
JOIN MonitoringPoint_Receiver mpr_new
    ON mpr_old.MonitoringPointID = mpr_new.MonitoringPointID
    AND mpr_new.StartDate = mpr_old.EndDate
    AND mpr_new.ReceiverID != mpr_old.ReceiverID
JOIN Receiver r_new ON mpr_new.ReceiverID = r_new.ReceiverID

-- Old sensor's last schedule (the CORRECT schedule)
JOIN ReceiverSchedule rs_old
    ON rs_old.ReceiverID = mpr_old.ReceiverID
    AND rs_old.ReceiverScheduleID = (
        SELECT MAX(rs2.ReceiverScheduleID)
        FROM ReceiverSchedule rs2
        WHERE rs2.ReceiverID = mpr_old.ReceiverID
          AND rs2.DateCreated <= mpr_old.EndDate
    )

-- New sensor's FIRST schedule (was default - the bug)
JOIN ReceiverSchedule rs_new_first
    ON rs_new_first.ReceiverID = mpr_new.ReceiverID
    AND rs_new_first.ReceiverScheduleID = (
        SELECT MIN(rs3.ReceiverScheduleID)
        FROM ReceiverSchedule rs3
        WHERE rs3.ReceiverID = mpr_new.ReceiverID
          AND rs3.DateCreated >= mpr_new.StartDate
    )

-- Current sensor's LATEST schedule (what it has NOW)
JOIN ReceiverSchedule rs_current
    ON rs_current.ReceiverID = mpr_new.ReceiverID
    AND rs_current.ReceiverScheduleID = (
        SELECT MAX(rs4.ReceiverScheduleID)
        FROM ReceiverSchedule rs4
        WHERE rs4.ReceiverID = mpr_new.ReceiverID
    )

WHERE
    (rs_old.Frequency != 6400 OR rs_old.Samples != 8192)  -- Old was CUSTOM
    AND rs_new_first.Frequency = 6400
    AND rs_new_first.Samples = 8192                       -- New got DEFAULT (the bug)
    AND rs_current.Frequency = 6400
    AND rs_current.Samples = 8192                         -- STILL has wrong schedule
    AND mpr_new.ActiveFlag = 1                            -- Sensor still active

ORDER BY rs_old.Frequency, mpr_old.EndDate DESC;
```

---

## Final Queries

### Query A: Count All MPs Still Needing Fix

```sql
SELECT COUNT(*) AS total_mps_still_needing_fix
FROM MonitoringPoint_Receiver mpr_old
JOIN MonitoringPoint mp ON mpr_old.MonitoringPointID = mp.MonitoringPointID
JOIN MonitoringPoint_Receiver mpr_new
    ON mpr_old.MonitoringPointID = mpr_new.MonitoringPointID
    AND mpr_new.StartDate = mpr_old.EndDate
    AND mpr_new.ReceiverID != mpr_old.ReceiverID
JOIN ReceiverSchedule rs_old
    ON rs_old.ReceiverID = mpr_old.ReceiverID
    AND rs_old.ReceiverScheduleID = (
        SELECT MAX(rs2.ReceiverScheduleID)
        FROM ReceiverSchedule rs2
        WHERE rs2.ReceiverID = mpr_old.ReceiverID
          AND rs2.DateCreated <= mpr_old.EndDate
    )
JOIN ReceiverSchedule rs_new_first
    ON rs_new_first.ReceiverID = mpr_new.ReceiverID
    AND rs_new_first.ReceiverScheduleID = (
        SELECT MIN(rs3.ReceiverScheduleID)
        FROM ReceiverSchedule rs3
        WHERE rs3.ReceiverID = mpr_new.ReceiverID
          AND rs3.DateCreated >= mpr_new.StartDate
    )
JOIN ReceiverSchedule rs_current
    ON rs_current.ReceiverID = mpr_new.ReceiverID
    AND rs_current.ReceiverScheduleID = (
        SELECT MAX(rs4.ReceiverScheduleID)
        FROM ReceiverSchedule rs4
        WHERE rs4.ReceiverID = mpr_new.ReceiverID
    )
WHERE
    (rs_old.Frequency != 6400 OR rs_old.Samples != 8192)
    AND rs_new_first.Frequency = 6400
    AND rs_new_first.Samples = 8192
    AND rs_current.Frequency = 6400
    AND rs_current.Samples = 8192
    AND mpr_new.ActiveFlag = 1;
```

**Result**: **505** monitoring points

---

### Query B: Breakdown by Month

```sql
SELECT
    DATE_FORMAT(mpr_old.EndDate, '%Y-%m') AS BugMonth,
    COUNT(*) AS CountStillNeedingFix
FROM MonitoringPoint_Receiver mpr_old
JOIN MonitoringPoint_Receiver mpr_new
    ON mpr_old.MonitoringPointID = mpr_new.MonitoringPointID
    AND mpr_new.StartDate = mpr_old.EndDate
    AND mpr_new.ReceiverID != mpr_old.ReceiverID
JOIN ReceiverSchedule rs_old
    ON rs_old.ReceiverID = mpr_old.ReceiverID
    AND rs_old.ReceiverScheduleID = (
        SELECT MAX(rs2.ReceiverScheduleID)
        FROM ReceiverSchedule rs2
        WHERE rs2.ReceiverID = mpr_old.ReceiverID
          AND rs2.DateCreated <= mpr_old.EndDate
    )
JOIN ReceiverSchedule rs_new_first
    ON rs_new_first.ReceiverID = mpr_new.ReceiverID
    AND rs_new_first.ReceiverScheduleID = (
        SELECT MIN(rs3.ReceiverScheduleID)
        FROM ReceiverSchedule rs3
        WHERE rs3.ReceiverID = mpr_new.ReceiverID
          AND rs3.DateCreated >= mpr_new.StartDate
    )
JOIN ReceiverSchedule rs_current
    ON rs_current.ReceiverID = mpr_new.ReceiverID
    AND rs_current.ReceiverScheduleID = (
        SELECT MAX(rs4.ReceiverScheduleID)
        FROM ReceiverSchedule rs4
        WHERE rs4.ReceiverID = mpr_new.ReceiverID
    )
WHERE
    (rs_old.Frequency != 6400 OR rs_old.Samples != 8192)
    AND rs_new_first.Frequency = 6400
    AND rs_new_first.Samples = 8192
    AND rs_current.Frequency = 6400
    AND rs_current.Samples = 8192
    AND mpr_new.ActiveFlag = 1
GROUP BY DATE_FORMAT(mpr_old.EndDate, '%Y-%m')
ORDER BY BugMonth DESC;
```

**Result**:
| Month | Count |
|-------|-------|
| 2026-01 | 2 |
| 2025-12 | 1 |
| 2025-11 | 12 |
| **2025-10** | **269** |
| 2025-07 | 20 |
| 2025-06 | 43 |
| 2025-05 | 37 |
| ... | ... |

---

### Query C: Breakdown by Correct Frequency

```sql
SELECT
    rs_old.Frequency AS CorrectFrequency,
    rs_old.Samples AS CorrectSamples,
    COUNT(*) AS CountStillNeedingFix
FROM MonitoringPoint_Receiver mpr_old
JOIN MonitoringPoint_Receiver mpr_new
    ON mpr_old.MonitoringPointID = mpr_new.MonitoringPointID
    AND mpr_new.StartDate = mpr_old.EndDate
    AND mpr_new.ReceiverID != mpr_old.ReceiverID
JOIN ReceiverSchedule rs_old
    ON rs_old.ReceiverID = mpr_old.ReceiverID
    AND rs_old.ReceiverScheduleID = (
        SELECT MAX(rs2.ReceiverScheduleID)
        FROM ReceiverSchedule rs2
        WHERE rs2.ReceiverID = mpr_old.ReceiverID
          AND rs2.DateCreated <= mpr_old.EndDate
    )
JOIN ReceiverSchedule rs_new_first
    ON rs_new_first.ReceiverID = mpr_new.ReceiverID
    AND rs_new_first.ReceiverScheduleID = (
        SELECT MIN(rs3.ReceiverScheduleID)
        FROM ReceiverSchedule rs3
        WHERE rs3.ReceiverID = mpr_new.ReceiverID
          AND rs3.DateCreated >= mpr_new.StartDate
    )
JOIN ReceiverSchedule rs_current
    ON rs_current.ReceiverID = mpr_new.ReceiverID
    AND rs_current.ReceiverScheduleID = (
        SELECT MAX(rs4.ReceiverScheduleID)
        FROM ReceiverSchedule rs4
        WHERE rs4.ReceiverID = mpr_new.ReceiverID
    )
WHERE
    (rs_old.Frequency != 6400 OR rs_old.Samples != 8192)
    AND rs_new_first.Frequency = 6400
    AND rs_new_first.Samples = 8192
    AND rs_current.Frequency = 6400
    AND rs_current.Samples = 8192
    AND mpr_new.ActiveFlag = 1
GROUP BY rs_old.Frequency, rs_old.Samples
ORDER BY CountStillNeedingFix DESC;
```

---

### Query D: Full List of MPs Needing Fix (Final Query)

```sql
-- =====================================================================
-- ALL MONITORING POINTS THAT CURRENTLY NEED SCHEDULE FIX
-- Total: 505 records (as of 2026-01-26)
-- =====================================================================

SELECT
    mpr_old.MonitoringPointID,
    mp.MonitoringPointName,

    -- What the schedule SHOULD be (from old sensor)
    rs_old.Frequency AS CorrectFrequency,
    rs_old.Samples AS CorrectSamples,

    -- Current sensor info
    mpr_new.ReceiverID AS CurrentReceiverID,
    r_new.SerialNumber AS CurrentSensorSerial,

    -- Current sensor's schedule (what it wrongly has now)
    rs_current.Frequency AS CurrentFrequency,
    rs_current.Samples AS CurrentSamples,

    -- When the bug occurred
    mpr_old.EndDate AS ReplacementDate

FROM MonitoringPoint_Receiver mpr_old

JOIN MonitoringPoint mp ON mpr_old.MonitoringPointID = mp.MonitoringPointID

JOIN MonitoringPoint_Receiver mpr_new
    ON mpr_old.MonitoringPointID = mpr_new.MonitoringPointID
    AND mpr_new.StartDate = mpr_old.EndDate
    AND mpr_new.ReceiverID != mpr_old.ReceiverID

JOIN Receiver r_new ON mpr_new.ReceiverID = r_new.ReceiverID

-- Old sensor's last schedule (the CORRECT schedule)
JOIN ReceiverSchedule rs_old
    ON rs_old.ReceiverID = mpr_old.ReceiverID
    AND rs_old.ReceiverScheduleID = (
        SELECT MAX(rs2.ReceiverScheduleID)
        FROM ReceiverSchedule rs2
        WHERE rs2.ReceiverID = mpr_old.ReceiverID
          AND rs2.DateCreated <= mpr_old.EndDate
    )

-- New sensor's FIRST schedule (was default - the bug)
JOIN ReceiverSchedule rs_new_first
    ON rs_new_first.ReceiverID = mpr_new.ReceiverID
    AND rs_new_first.ReceiverScheduleID = (
        SELECT MIN(rs3.ReceiverScheduleID)
        FROM ReceiverSchedule rs3
        WHERE rs3.ReceiverID = mpr_new.ReceiverID
          AND rs3.DateCreated >= mpr_new.StartDate
    )

-- Current sensor's LATEST schedule (what it has NOW)
JOIN ReceiverSchedule rs_current
    ON rs_current.ReceiverID = mpr_new.ReceiverID
    AND rs_current.ReceiverScheduleID = (
        SELECT MAX(rs4.ReceiverScheduleID)
        FROM ReceiverSchedule rs4
        WHERE rs4.ReceiverID = mpr_new.ReceiverID
    )

WHERE
    -- Old sensor had CUSTOM schedule
    (rs_old.Frequency != 6400 OR rs_old.Samples != 8192)
    -- New sensor got DEFAULT (the bug)
    AND rs_new_first.Frequency = 6400
    AND rs_new_first.Samples = 8192
    -- STILL has wrong schedule
    AND rs_current.Frequency = 6400
    AND rs_current.Samples = 8192
    -- Current sensor is still active
    AND mpr_new.ActiveFlag = 1

ORDER BY rs_old.Frequency, mpr_old.EndDate DESC;
```

---

## Validation Considerations

### Potential False Positives

1. **Intentional schedule changes**: An engineer may have intentionally changed a schedule to default after a sensor replacement. However, per the user, this should be rare since the schedule is determined by the machine, not the sensor.

2. **MPs where machine was replaced**: If the underlying machine was replaced (not just the sensor), the schedule requirements might legitimately change. This would need to be verified case-by-case.

### Potential Missed Records

1. **Non-direct replacements**: The query uses `mpr_new.StartDate = mpr_old.EndDate` which catches direct replacements. If there was a gap between sensors, this would miss those cases.

2. **Multiple replacements**: If an MP had Sensor A (custom) → Sensor B (default) → Sensor C (still default), only the A→B transition is caught. However, Sensor C would still show as needing fix since it has default schedule.

3. **Schedule created before sensor assignment**: The query uses `rs.DateCreated >= mpr_new.StartDate` for the new sensor's first schedule. If a sensor had a schedule created before being assigned to this MP, it wouldn't be caught. This is actually correct behavior since we want the schedule created for THIS assignment.

### Verification Query for Edge Cases

```sql
-- Check for MPs with gaps between sensors (potential missed records)
SELECT
    mpr1.MonitoringPointID,
    mpr1.ReceiverID as OldReceiver,
    mpr1.EndDate as OldEnd,
    mpr2.ReceiverID as NewReceiver,
    mpr2.StartDate as NewStart,
    TIMESTAMPDIFF(SECOND, mpr1.EndDate, mpr2.StartDate) as GapSeconds
FROM MonitoringPoint_Receiver mpr1
JOIN MonitoringPoint_Receiver mpr2
    ON mpr1.MonitoringPointID = mpr2.MonitoringPointID
    AND mpr2.StartDate > mpr1.EndDate
    AND mpr2.ReceiverID != mpr1.ReceiverID
WHERE mpr1.EndDate IS NOT NULL
  AND TIMESTAMPDIFF(SECOND, mpr1.EndDate, mpr2.StartDate) BETWEEN 1 AND 86400
ORDER BY GapSeconds DESC
LIMIT 20;
```

---

## Related Research Documents

- `thoughts/shared/research/2026-01-22-monitoring-point-schedule-copy-functionality.md` - How schedule inheritance is supposed to work
- `thoughts/shared/research/2026-01-12-sensor-schedule-system-comprehensive.md` - Complete schedule system architecture
- `thoughts/shared/research/2025-12-16-receiver-schedule-to-monitoring-point-schedule-impact.md` - Migration impact analysis

## SQL Scripts

- `~/repos/notes/schedule-bugs/cme_custom_schedule_overwritten.sql` - Find active MPs where a CME set a custom schedule and a non-CME (usually the system bot) overwrote it with default. Filters for overwrites after Oct 10, 2025.

---

## Next Steps

1. **Validate the 505 records** by spot-checking a sample
2. **Determine remediation approach**:
   - Manual fix via frontend (if count is manageable)
   - Bulk database update (if count is high)
   - Script to send schedule requests via API
3. **Prioritize by customer/facility impact**
4. **Communicate with affected customers if necessary**

---

## Open Questions

1. What caused the spike on October 15, 2025? (64 cases in one day)
2. Was there a code change around early October 2025 that worsened the bug?
3. Are there any MPs in the list that should legitimately have default schedules?
