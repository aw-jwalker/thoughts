# Sensor Action Column Logic - Flowcharts

**Source**: CustomerDetail > Sensors page
**Last Updated**: 2026-02-03

---

## Diagram 1: Hardware Issue Origins (Automated vs Manual)

Shows which issues are created by the system vs manually by CSRs.

```mermaid
flowchart TB
    subgraph Manual["Manual (CSR)"]
        CSR_UI["Customer Support<br/>UI Actions"]
    end

    subgraph Automated["Automated (System)"]
        FIRE_MONITOR["External Fire Risk<br/>Monitoring System"]
        ML["ML Battery<br/>Prediction Model"]
        VOLTAGE["Low Voltage<br/>Detection"]
    end

    FIRE_MONITOR -->|"Populates temp table"| TOFR_PROC["HardwareIssue_<br/>ReceiversTempOverFireRisk"]
    TOFR_PROC -->|"Creates"| TOFR_ISSUES["TEMP_OVER_FIRE_RISK (59)<br/>TOFR_REPLACE (66)<br/>TOFR_REMOVE (67)"]

    ML -->|"Updates"| SENSORLIFE["SensorLife Table<br/>PredictedBatteryStatus"]
    SENSORLIFE -->|"'Critical'"| REPLACE_FLAG["hasReplaceAction = 1"]

    VOLTAGE -->|"2.5V - 3.2V"| LOW_V["LOW_BATTERY_VOLTAGE (15)"]

    CSR_UI -->|"Manual entry"| CSR_ISSUES["CSR_CHECK_PLACEMENT (49)<br/>CSR_REMOVE (61)<br/>CSR_STRENGTHEN_NETWORK (64)"]
```

---

## Diagram 2: What Triggers "hasReplaceAction"?

The database calculates this flag based on battery status OR hardware issues.

```mermaid
flowchart LR
    subgraph Database["Database Layer"]
        BATTERY["SensorLife Table<br/>PredictedBatteryStatus"]
        HW_ISSUE["HardwareIssue Table<br/>Open issues with<br/>ActionID = 1"]
    end

    BATTERY -->|"= 'Critical'"| HAS_REPLACE
    HW_ISSUE -->|"COUNT > 0"| HAS_REPLACE

    HAS_REPLACE(["hasReplaceAction = 1"])
```

---

## Diagram 3: Main Decision Flowchart

Shows the priority-based rule evaluation. First matching rule wins.

```mermaid
flowchart TD
    START(["Sensor Data Retrieved"])

    START --> CHECK_REMOVE{"Has Remove Issue?<br/>(TEMP_OVER_FIRE_RISK,<br/>CSR_REMOVE, or<br/>TOFR_REMOVE)"}

    CHECK_REMOVE -->|Yes| CHECK_FLAG1{"Feature Flag<br/>releaseMpTofStatus?"}
    CHECK_FLAG1 -->|No| REMOVE["REMOVE"]
    CHECK_FLAG1 -->|Yes| CHECK_MPSTATUS{"Has MP Status?"}
    CHECK_MPSTATUS -->|No| REMOVE
    CHECK_MPSTATUS -->|Yes| CHECK_BLACKLIST

    CHECK_REMOVE -->|No| CHECK_BLACKLIST{"Is Blacklisted?<br/>(mpStatusId = Blacklist)"}
    CHECK_BLACKLIST -->|Yes + Flag On| REMOVE
    CHECK_BLACKLIST -->|No or Flag Off| CHECK_REPLACE

    CHECK_REPLACE{"Needs Replacement?<br/>(hasReplaceAction=1<br/>OR TOFR_REPLACE issue)"}
    CHECK_REPLACE -->|Yes| REPLACE["REPLACE"]

    CHECK_REPLACE -->|No| CHECK_RELEASED{"MP Status = Released?<br/>(+ Flag On)"}
    CHECK_RELEASED -->|Yes| REPLACE

    CHECK_RELEASED -->|No| CHECK_NETWORK{"Has<br/>CSR_STRENGTHEN_NETWORK<br/>issue?"}
    CHECK_NETWORK -->|Yes| NETWORK["CHECK/ADD<br/>NETWORK EQUIPMENT"]

    CHECK_NETWORK -->|No| CHECK_PLACEMENT{"Has<br/>CSR_CHECK_PLACEMENT<br/>issue?"}
    CHECK_PLACEMENT -->|Yes| PLACEMENT["CHECK PLACEMENT"]

    CHECK_PLACEMENT -->|No| CHECK_OFFLINE{"Sensor Status<br/>= OFFLINE?"}
    CHECK_OFFLINE -->|Yes| TURNON["TURN ON"]

    CHECK_OFFLINE -->|No| OK["OK"]
```

---

## Priority Summary

| Priority | Action | Trigger |
|:--------:|--------|---------|
| 1 | **Remove** | Fire risk, CSR removal, Blacklisted MP |
| 2 | **Replace** | Critical battery, ActionID=1 issue, Released MP |
| 3 | **Check/Add Network** | CSR_STRENGTHEN_NETWORK |
| 4 | **Check Placement** | CSR_CHECK_PLACEMENT |
| 5 | **Turn On** | Sensor OFFLINE |
| 6 | **Ok** | Default (no issues) |
