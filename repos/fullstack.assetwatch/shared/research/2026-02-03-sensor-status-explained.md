# Sensor Status Explained

**Purpose**: Detailed explanation of how Sensor Status is determined and what it means

**Date**: 2026-02-03

---

## What is "Sensor Status"?

**Sensor Status** (stored as `ReceiverStatusID` in the database) indicates the current operational state of a sensor. This is **automatically calculated** by a Lambda function that runs periodically.

---

## Status Values in Use

Based on current database data (404,277 total sensors):

| Status ID | Status Name | Count | % | What It Means |
|-----------|-------------|-------|---|---------------|
| 4 | **Offline** | 263,738 | 65% | Sensor hasn't sent readings in 24+ hours |
| 5 | **Ok** | 139,989 | 35% | Sensor is communicating normally |
| 1 | Replace Sensor | 529 | <1% | Sensor needs replacement (set manually) |
| 7 | Provisioned | 21 | <1% | Sensor is newly provisioned but not yet installed |
| 2 | Reclamation | 0 | 0% | (Not currently used) |
| 3 | Missed Readings | 0 | 0% | (Not currently used) |
| 6 | Recharge Battery | 0 | 0% | (Not currently used) |

---

## How "Offline" Status is Determined

**Source**: `lambdas/lf-vero-prod-global/UpdateReceivers.js` - `getSensorStatusGenTwo()` function

### Automated Logic

The system checks `data.lr` (hours since last reading):

```
If sensor hasn't sent readings in 24+ hours:
  → Status = Offline (4)

  If 24-25 hours (or 24-56 on Mondays):
    → Alert Type = Warning (2)
    → Recently went offline

  If >25 hours (or >56 on Mondays):
    → Alert Type = Critical (1)
    → Been offline for extended period

Otherwise:
  → Status = Ok (5)
  → Alert Type = Ok (3)
```

### Special Monday Logic

**Why**: Account for weekend downtime

- **Monday threshold**: 56 hours (from 5pm Friday to 9am Monday)
- **Other days**: 25 hours

This prevents sensors from being marked as long-term offline just because of normal weekend gaps.

---

## How Status Gets Updated

### Automatic Updates (Most Common)

**Lambda Function**: `UpdateReceivers.js` runs periodically

1. Queries all sensors
2. Calculates hours since last reading (`lr`)
3. Determines status based on thresholds
4. Batch updates `Receiver.ReceiverStatusID` in database

### When Readings Come In

**Stored Procedure**: `Reading_Update.sql` (lines 48-51)

When a sensor sends a reading:
```sql
IF (ReceiverStatusID = 4 OR ReceiverStatusID = 7) THEN
    -- Set status to Ok
    SET ReceiverStatusID = 5

    -- Auto-resolve "CSR - Turn Back On" hardware event (ID 50)
    UPDATE HardwareIssue
    SET HardwareIssueStatusID = 2 -- Resolved
    WHERE ReceiverID = localReceiverID
      AND HardwareIssueTypeID = 50
      AND HardwareIssueStatusID = 1
END IF
```

**Result**:
- Offline (4) → Ok (5)
- Provisioned (7) → Ok (5)
- Auto-resolves any open "CSR - Turn Back On" hardware events

---

## What CSRs See

### In the UI

**Status Column**: Shows one of the status names
- "Offline"
- "Ok"
- "Replace Sensor"
- "Provisioned"

### Triggers Action Column

**When Status = "Offline"**:
- Action column shows: **"Turn On"**
- Priority: 5 (checked after Replace, Check Network, Check Placement)
- Meaning: Sensor needs to be powered back on or is having connectivity issues

---

## For CSRs: What "Offline" Really Means

### Short-Term Offline (24-25 hours / 24-56 on Mondays)

**Warning Level** - Recently went offline

**Possible Causes**:
- Sensor was temporarily powered off
- Brief network connectivity issue
- Sensor is in the process of being replaced
- Weekend downtime (normal for some sensors)

**Action**: Monitor to see if it comes back online automatically

### Long-Term Offline (>25 hours / >56 on Mondays)

**Critical Level** - Been offline extended period

**Possible Causes**:
- Sensor needs to be turned back on
- Power supply issue
- Sensor was removed but not properly decommissioned
- Network equipment failure
- Physical damage or failure

**Action**: "Turn On" action - investigate and restore connectivity

---

## Status vs Action Column

| Sensor Status | Action Column | What It Means |
|---------------|---------------|---------------|
| Offline | Turn On | Sensor hasn't communicated in 24+ hours, needs attention |
| Ok | (depends on other factors) | Sensor is communicating normally |
| Replace Sensor | (depends on other factors) | Manually flagged for replacement |
| Provisioned | (depends on other factors) | Newly setup, not yet installed |

**Key Point**: "Sensor Status" is just ONE factor in determining the Action column. The Action column also considers:
- Hardware events
- Battery status
- Monitoring point status (TOFR workflow)
- Other conditions

---

## Technical Details

### Database Field

- **Table**: `Receiver`
- **Column**: `ReceiverStatusID` (INT)
- **Foreign Key**: → `ReceiverStatus.ReceiverStatusID`

### Related Fields

- `LastReadingDate`: Timestamp of last reading
- `MinutesSinceLastReading`: Calculated field
- `AlertTypeID`: 1=Critical, 2=Warning, 3=Ok

### Lambda Schedule

The `UpdateReceivers` Lambda runs on a schedule (likely every few hours or daily) to keep sensor statuses up-to-date.

---

## Summary for CSRs

**"Sensor Status"** tells you if the sensor is communicating with the system:

- **Ok**: ✅ Sensor is working and sending data
- **Offline**: ⚠️ Sensor hasn't sent data in 24+ hours - shows "Turn On" action
- **Provisioned**: 🆕 Sensor is new and not yet installed
- **Replace Sensor**: 🔄 Manually flagged for replacement

The status is **automatically calculated** based on when the sensor last sent a reading. It updates automatically when readings come in or when the system runs its periodic check.
