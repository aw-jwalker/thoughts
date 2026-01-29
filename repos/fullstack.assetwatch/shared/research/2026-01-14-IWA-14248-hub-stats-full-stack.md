---
date: 2026-01-14T08:46:10-05:00
researcher: Claude Code
git_commit: f43236206b6911a61658cf864300ac6684e0f2da
branch: IWA-14248
repository: fullstack.assetwatch
topic: "CustomerDetail Hubs Data Table - Full Stack Data Flow for Hub Statistics"
tags: [research, codebase, hub-statistics, transponder-metrics, timestream, mqtt, customer-detail]
status: complete
last_updated: 2026-01-14
last_updated_by: Claude Code
---

# Research: CustomerDetail Hubs Data Table - Full Stack Data Flow

**Date**: 2026-01-14T08:46:10-05:00
**Researcher**: Claude Code
**Git Commit**: f43236206b6911a61658cf864300ac6684e0f2da
**Branch**: IWA-14248
**Repository**: fullstack.assetwatch

## Research Question

Where do the fields on the CustomerDetail > Hubs data table come from? Specifically:
- Readings Last 7D
- Unique Sensors Last 7D
- Last Sensor Read by Hub
- Hub Last Online
- And similar hub statistics fields

We need to understand the full stack from frontend to data source, including background jobs and MQTT message handling.

## Summary

The hub statistics displayed in the CustomerDetail > Hubs table follow a multi-stage data pipeline:

1. **Data Source**: Sensor readings arrive via MQTT and are stored in AWS Timestream (`vibration_sensor.reading`)
2. **Background Job**: The `jobs_insights` Lambda (in `assetwatch-jobs`) runs every 3 hours and queries Timestream to calculate aggregate statistics, storing results in the `TransponderMetric` table
3. **API Layer**: The `lf-vero-prod-hub` Lambda handles the `getHubList` method, calling `Transponder_GetTransponderList` stored procedure
4. **Database**: The stored procedure JOINs `Transponder` with `TransponderMetric` to return statistics
5. **Frontend**: The `HubListTab` component fetches data via `HubService.getHubListData()` and displays it in an AG-Grid table

**Key Finding for IWA-14248**: The `UniqueSensorCountLast7d` field is populated by the `jobs_insights` job which uses `approx_distinct(sensor)` in Timestream - an approximate count function that may have accuracy issues.

## Detailed Findings

### 1. Frontend Layer

#### HubListTab Component
- **File**: `frontend/src/components/CustomerDetailPage/Hubs/HubListTab.tsx:54-643`
- **Purpose**: Main component rendering the Hubs tab in CustomerDetail page
- **Data Display**: Uses AG-Grid Enterprise (ag-grid-react) DataTable component

#### Column Definitions
- **File**: `frontend/src/components/CustomerDetailPage/Hubs/ColumnDefs.tsx:28-402`
- **Key Statistics Columns**:

| Column Header | Field Name | Line | Source |
|---------------|------------|------|--------|
| Readings Last 7d | `readcnt` | 302-306 | `TransponderMetric.ReadingsLast7d` |
| Unique Sensors Last 7d | `sensorcnt` | 329-333 | `TransponderMetric.UniqueSensorCountLast7d` |
| Last Sensor Read by Hub | `ldte` | 193-224 | `Transponder.LastReadingDate` |
| Hub Last Online | `llte` | 226-256 | `IoTCoreEvent` or `TransponderLastLogDate` |
| Hub Online Status | `hubstate` | 147-159 | `IoTCoreEvent.IoTCoreEventTypeID` |
| Hub CPU Temp | `htemp` | 341-353 | `HubDiagnostic.cputemp` |

#### Data Fetching Hook
- **File**: `frontend/src/components/CustomerDetailPage/Hubs/hooks/useGetHubListData.ts:10-70`
- **Query Key**: `["hubList", selectedFacilityIds, selectedFilter]`
- **Date Parameter**: Requests data with 7-day lookback (`minus({ weeks: 1 })`)

#### API Service
- **File**: `frontend/src/shared/api/HubService.ts:124-141`
- **Function**: `getHubListData()`
- **Method**: POST to `apiVeroHub` at `/list` endpoint
- **Payload**:
  ```json
  {
    "meth": "getHubList",
    "hid": 0,
    "dte": "<1-week-ago-date>",
    "extcid": "<external-customer-id>",
    "fid": "<facility-ids>"
  }
  ```

### 2. API/Lambda Layer

#### Hub Lambda Handler
- **File**: `lambdas/lf-vero-prod-hub/main.py:436-451`
- **Method**: `getHubList`
- **Action**: Calls stored procedure `Transponder_GetTransponderList`

```python
if meth == "getHubList":
    externalCustomerID = jsonBody["extcid"]
    sql = (
        "CALL Transponder_GetTransponderList("
        + str(jsonBody["hid"])
        + ",'"
        + str(jsonBody["dte"])
        + "','"
        + externalCustomerID
        + "','"
        + str(jsonBody["fid"])
        + "')"
    )
    retVal = db.mysql_read(sql, requestId, meth, cognito_id)
```

### 3. Database Layer

#### Main Stored Procedure
- **File**: `mysql/db/procs/R__PROC_Transponder_GetTransponderList.sql:1-285`
- **Key JOINs for Statistics**:

```sql
-- Line 167/251: Join to TransponderMetric for 7d stats
LEFT JOIN TransponderMetric tm ON tx.TransponderID = tm.TransponderID

-- Lines 113-116, 194-197: Select statistics fields
IFNULL(tm.ReadingsLast7d, 0) AS readcnt,
IFNULL(tm.UniqueSensorCountLast7d, 0) AS sensorcnt,
tx.LastReadingDate AS ldte,
```

#### Hub Last Online Logic
- **Lines 120-123, 201-204**: Different source based on product type
```sql
IF(pr.ProductID = 18,
    FROM_UNIXTIME(iot.lastOnline),  -- IoTCoreEvent for Gen3 hubs
    tlld.LastLogDate                 -- TransponderLastLogDate for others
) AS llte,
```

#### TransponderMetric Table
- **Schema** (inferred from upsert procedure):
  - `TransponderID` (PK)
  - `ReadingsLast7d` (INT)
  - `UniqueSensorCountLast7d` (INT)
  - `ReadingsLast21d` (INT)

#### Upsert Procedure
- **File**: `mysql/db/procs/R__PROC_TransponderMetric_UpsertTransponderMetric.sql:1-21`
- **Action**: INSERT ... ON DUPLICATE KEY UPDATE

### 4. Background Jobs Layer (assetwatch-jobs)

#### Primary Job: jobs_insights
- **Location**: `/home/aw-jwalker/repos/assetwatch-jobs/terraform/jobs/jobs_insights/`
- **Schedule**: Every 3 hours at :35 past the hour (`cron(35 0/3 * * ? *)`)
- **Handler**: `main.lambda_handler()` with `meth: "loadTxRxMetrics"`

#### TX/RX Metrics Calculator
- **File**: `/home/aw-jwalker/repos/assetwatch-jobs/terraform/jobs/jobs_insights/jobs-insights/tx_rx_metrics.py`

##### Hub Metrics Query (lines 72-91)
```sql
SELECT metrics7d.hub, metrics7d.readings_last_7d,
       metrics7d.unique_sensors_last_7d, metrics21d.readings_last_21d
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

**CRITICAL NOTE**: `approx_distinct(sensor)` is Timestream's approximate count distinct function. This may explain accuracy issues with unique sensor counts as it trades precision for performance.

##### Data Flow in tx_rx_metrics.py
1. **Line 60-128**: `get_hub_metrics_data()` - Queries Timestream for hub stats
2. **Line 93**: Executes query via `common_resources.query_ts()`
3. **Lines 96-107**: Processes results into dictionary
4. **Lines 110-124**: Converts to tuple format for database insert
5. **Lines 339-346**: Calls `TransponderMetric_UpsertTransponderMetric` stored procedure

### 5. Data Ingestion Layer (MQTT/SQS)

#### Reading Flow
1. Sensors transmit via MQTT to AWS IoT Core
2. IoT Rules route messages to SQS queues
3. Lambda processors handle SQS messages
4. Stored procedures insert/update data

#### Key Stored Procedures for Reading Counts
- **Temperature**: `Temperature_AddTemperatureFromSQS` - Updates `Receiver.Readings` counter
- **Vibration**: `Vibration_AddVibrationFromSQS` - Updates counters and risk records
- **Voltage**: `Voltage_AddVoltageFromSQS` - Updates `Receiver.Readings` counter

#### Data Storage
- **Real-time readings**: AWS Timestream (`vibration_sensor.reading` table)
- **Transponder metadata**: MySQL `Transponder` table
- **Aggregated statistics**: MySQL `TransponderMetric` table (updated every 3 hours)

### 6. Related Tables and Data Sources

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `Transponder` | Hub master data | `LastReadingDate`, `SerialNumber`, `FirmwareVersion` |
| `TransponderMetric` | Aggregated hub stats | `ReadingsLast7d`, `UniqueSensorCountLast7d`, `ReadingsLast21d` |
| `IoTCoreEvent` | Hub online/offline events | `IoTCoreEventTypeID`, `IoTTimestamp` |
| `TransponderLastLogDate` | Hub last log timestamp | `LastLogDate` |
| `HubDiagnostic` | Hub hardware diagnostics | `cputemp`, `misc` |
| `Facility_Transponder` | Hub-facility assignment | `LocationNotes`, `StartDate` |
| `HardwareIssue` | Hardware problems | `HardwareIssueTypeID`, count aggregations |

## Code References

### Frontend
- `frontend/src/components/CustomerDetailPage/Hubs/HubListTab.tsx:486-591` - DataTable rendering
- `frontend/src/components/CustomerDetailPage/Hubs/ColumnDefs.tsx:302-333` - Statistics column definitions
- `frontend/src/components/CustomerDetailPage/Hubs/hooks/useGetHubListData.ts:17-20` - Query configuration
- `frontend/src/shared/api/HubService.ts:124-141` - API call implementation
- `frontend/src/shared/types/hubs/HubList.ts:19-28` - Type definitions for `readcnt`, `sensorcnt`

### Backend
- `lambdas/lf-vero-prod-hub/main.py:436-451` - getHubList handler
- `mysql/db/procs/R__PROC_Transponder_GetTransponderList.sql:113-116` - Statistics field selection
- `mysql/db/procs/R__PROC_TransponderMetric_UpsertTransponderMetric.sql:13-18` - Metric upsert logic

### Jobs (assetwatch-jobs repository)
- `/home/aw-jwalker/repos/assetwatch-jobs/terraform/jobs/jobs_insights/jobs-insights/tx_rx_metrics.py:72-91` - Timestream query
- `/home/aw-jwalker/repos/assetwatch-jobs/terraform/jobs/jobs_insights/jobs-insights/tx_rx_metrics.py:60-128` - Hub metrics calculation
- `/home/aw-jwalker/repos/assetwatch-jobs/terraform/jobs/jobs_insights/eventbridge.tf:57-88` - Schedule configuration

## Architecture Documentation

### Data Flow Diagram

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   IoT Sensors   │────▶│  AWS IoT Core   │────▶│   SQS Queue     │
│   (MQTT)        │     │  (MQTT Broker)  │     │                 │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                                                         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Timestream    │◀────│  Data Ingestion │◀────│  Lambda         │
│   (readings)    │     │  Lambda         │     │  (SQS trigger)  │
└────────┬────────┘     └─────────────────┘     └─────────────────┘
         │
         │ Query every 3 hours
         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  jobs_insights  │────▶│ MySQL/RDS       │◀────│ lf-vero-prod-hub│
│  Lambda         │     │ TransponderMetric│    │ Lambda          │
└─────────────────┘     └────────┬────────┘     └────────▲────────┘
                                 │                        │
                                 │                        │ API call
                                 ▼                        │
                        ┌─────────────────┐     ┌─────────────────┐
                        │ Stored Procedure │◀───│   Frontend      │
                        │ GetTransponderList│   │   HubListTab    │
                        └─────────────────┘     └─────────────────┘
```

### Schedule

| Job | Schedule | Purpose |
|-----|----------|---------|
| `jobs_insights.loadTxRxMetrics` | Every 3 hours at :35 | Update TransponderMetric with Timestream aggregates |

## Open Questions

1. **Accuracy of approx_distinct**: The `approx_distinct(sensor)` function in Timestream is an approximate algorithm. What is its error margin and could this explain inaccuracies in "Unique Sensors Last 7D"?

2. **Stale Data Window**: Since the job runs every 3 hours, statistics can be up to 3 hours stale. Is this acceptable for the use case?

3. **LastReadingDate Source**: The `ldte` field comes from `Transponder.LastReadingDate` which is updated by reading ingestion. Is this updated consistently for all reading types?

4. **Hub-Sensor Association**: The Timestream query groups by `hub` field. How is the hub identifier populated in the reading table and is it always accurate?
