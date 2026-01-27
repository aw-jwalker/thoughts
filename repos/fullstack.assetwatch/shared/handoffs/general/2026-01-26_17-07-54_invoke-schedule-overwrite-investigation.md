---
date: 2026-01-26T17:07:54-05:00
researcher: Claude
git_commit: 881ecbe11513e5a273e8706367f4d7af534361d9
branch: dev
repository: fullstack.assetwatch
topic: "Invoke Reading May Be Overwriting Custom Schedules - Investigation"
tags: [investigation, bug-analysis, ReceiverSchedule, invoke, schedule-inheritance]
status: in_progress
last_updated: 2026-01-26
last_updated_by: Claude
type: investigation
---

# Handoff: Invoke Schedule Overwrite Bug Investigation

## Task(s)

**Status: In Progress**

Building on the existing schedule inheritance bug investigation, the user discovered a **potential second bug**: invoking a reading (a one-time manual reading request) may be overwriting the sensor's custom schedule frequency and sampling rate.

### Background
- **Original Bug (documented)**: When a sensor is replaced, the new sensor should inherit the previous sensor's custom schedule but instead gets the default (6400 Hz, 8192 samples)
- **New Hypothesis**: The "invoke" action (requesting a single reading with specified freq/sample rate) may ALSO be overwriting the persistent schedule settings, even though it should only trigger a one-time reading

### What Was Accomplished
1. Read and understood the two research documents on schedule inheritance
2. Started database investigation of sensor 6001379
3. Retrieved full schedule history for the sensor (see findings below)

## Critical References

1. `thoughts/shared/research/2026-01-22-monitoring-point-schedule-copy-functionality.md` - How schedule inheritance is supposed to work
2. `thoughts/shared/research/2026-01-26-schedule-inheritance-bug-impact-analysis.md` - Impact analysis identifying 505 affected MPs

## Recent changes

None - this was a research/investigation session, no code changes made.

## Learnings

### Sensor 6001379 Schedule History (Key Finding)

The sensor is on MonitoringPoint 118037 ("Mill DE"), ReceiverID 131643, active since 2023-05-01.

**Schedule timeline:**
| Date | Frequency | RQID | Notes |
|------|-----------|------|-------|
| 2023-05-01 | 6400 Hz | 1682966526 | Initial default |
| 2024-01-31 | 1600 Hz | 1706716330 | Changed to custom |
| 2025-02-06 | 1600 Hz | 1738862011 | Custom maintained |
| 2025-04-04 | 1600 Hz | multiple | Several schedule updates |
| 2025-07-14 | 3200 Hz | 1752517100 | Changed to different custom |
| **2025-12-30** | **6400 Hz** | **1767112501** | **⚠️ REVERTED TO DEFAULT - KEY EVENT** |
| 2026-01-23 | 6400 Hz | 1769190149 | Still at default |

**The key event to investigate is 2025-12-30 (RQID 1767112501)** - the schedule went from custom 3200 Hz back to default 6400 Hz. User believes this happened during an invoke action.

### User's Observation
When viewing sensor 6001379 history in the frontend, the user saw that the schedule change happened at the EXACT same time as a sensor invoke. The invoke was done with default sampling rate and frequency, and it appears to have also changed the persistent schedule.

## Artifacts

- `thoughts/shared/research/2026-01-22-monitoring-point-schedule-copy-functionality.md` - Existing research on schedule inheritance
- `thoughts/shared/research/2026-01-26-schedule-inheritance-bug-impact-analysis.md` - Existing impact analysis
- This handoff document

## Action Items & Next Steps

1. **Query Request details for RQID 1767112501** to determine if it was an Invoke request type
   ```sql
   SELECT * FROM Request WHERE RQID = 1767112501;
   ```

2. **Query RequestType table** to understand the different request types (Invoke vs Schedule vs others)
   ```sql
   SELECT * FROM RequestType;
   ```

3. **Look at RQMeta** for the problematic request to see what parameters were passed
   ```sql
   SELECT * FROM RQMeta WHERE RQID = 1767112501;
   ```

4. **Find the code path for "invoke" requests** - where does invoke happen and does it call any schedule-related stored procedures?
   - Check `frontend/src/shared/api/RequestServiceV2.ts` for invoke-related functions
   - Check the lambda handlers for invoke request processing
   - Look for stored procedures that handle invoke requests

5. **If invoke bug is confirmed**, search for a broader pattern:
   - Query for all sensors where a schedule change to default happened at the same timestamp as an invoke request

6. **Update the impact analysis** if this is a separate bug vector

## Other Notes

### Database Schema Notes
- `ReceiverSchedule` stores schedules per sensor (ReceiverID), not per MonitoringPoint
- Each schedule has an RQID linking it to the Request that created it
- `ReceiverScheduleStatusID`: 1 = active, 2 = superseded
- The Request table has `ReceiverID` directly (not through a junction table)

### Key Question to Answer
Does the invoke code path (intentionally or unintentionally) call `Receiver_AddReceiverSchedule` or similar procedures that create new schedule records? It should only trigger a one-time reading, not modify the persistent schedule.

### Relevant Code Locations to Investigate
- `frontend/src/shared/api/RequestServiceV2.ts` - Frontend request service
- `lambdas/lf-vero-prod-request/` - Request processing lambda
- `mysql/db/procs/R__PROC_Receiver_AddReceiverSchedule.sql` - Schedule creation procedure
