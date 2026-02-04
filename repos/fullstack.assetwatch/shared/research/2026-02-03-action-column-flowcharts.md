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

---

## Diagram 4: CSR-Friendly Decision Flowchart

**For Customer Support Representatives** - Uses terminology visible in the UI.

```mermaid
flowchart TD
    START(["Check Sensor Action"])

    START --> CHECK_TOFR_WORKFLOW{{"Is location in<br/>TOFR Workflow?<br/>(Has MP Status)"}}

    CHECK_TOFR_WORKFLOW -->|Yes| TOFR_WORKFLOW
    CHECK_TOFR_WORKFLOW -->|No| CHECK_FIRE_EVENT

    subgraph TOFR_WORKFLOW["🔥 Temp Over Fire Risk Workflow"]
        CHECK_BLACKLIST{{"MP Status:<br/>Blacklist?"}}
        CHECK_RELEASED{{"MP Status:<br/>Released?"}}

        CHECK_BLACKLIST -->|Yes| REMOVE["REMOVE"]
        CHECK_BLACKLIST -->|No| CHECK_RELEASED
        CHECK_RELEASED -->|Yes| REPLACE["REPLACE"]
        CHECK_RELEASED -->|No| CONTINUE["Continue to<br/>standard checks"]
    end

    CONTINUE --> CHECK_FIRE_EVENT

    CHECK_FIRE_EVENT{{"Hardware Event:<br/>Temp Over Fire Risk,<br/>CSR - Remove, or<br/>TOFR - Remove?"}}
    CHECK_FIRE_EVENT -->|Yes| REMOVE

    CHECK_FIRE_EVENT -->|No| CHECK_BATTERY{{"Battery Status:<br/>Critical?<br/>OR<br/>Hardware Event:<br/>TOFR - Replace?"}}
    CHECK_BATTERY -->|Yes| REPLACE

    CHECK_BATTERY -->|No| CHECK_NETWORK_EVENT{{"Hardware Event:<br/>CSR - Strengthen<br/>Network?"}}
    CHECK_NETWORK_EVENT -->|Yes| NETWORK["CHECK/ADD<br/>NETWORK EQUIPMENT"]

    CHECK_NETWORK_EVENT -->|No| CHECK_PLACEMENT_EVENT{{"Hardware Event:<br/>CSR - Check<br/>Placement?"}}
    CHECK_PLACEMENT_EVENT -->|Yes| PLACEMENT["CHECK PLACEMENT"]

    CHECK_PLACEMENT_EVENT -->|No| CHECK_SENSOR_STATUS{{"Sensor Status:<br/>Offline?"}}
    CHECK_SENSOR_STATUS -->|Yes| TURNON["TURN ON"]

    CHECK_SENSOR_STATUS -->|No| OK["OK"]
```

**Legend:**
- **🔥 TOFR Workflow**: Special safety workflow for high-temperature monitoring points
  - **Blacklist**: Confirmed safety risk - sensor must be removed
  - **Released**: Risk resolved - sensor should be replaced
  - **Pending Review**: Under evaluation (continues to standard checks)
- **Hardware Events**: Visible in the "Hardware Events" column
- **Battery Status**: From ML predictions (not directly visible, but shows in Action)
- **Sensor Status: Offline**: Sensor hasn't sent readings in 24+ hours

---

## Priority Summary

### For Engineers

| Priority | Action | Trigger |
|:--------:|--------|---------|
| 1 | **Remove** | Fire risk, CSR removal, Blacklisted MP |
| 2 | **Replace** | Critical battery, ActionID=1 issue, Released MP |
| 3 | **Check/Add Network** | CSR_STRENGTHEN_NETWORK |
| 4 | **Check Placement** | CSR_CHECK_PLACEMENT |
| 5 | **Turn On** | Sensor OFFLINE |
| 6 | **Ok** | Default (no issues) |

### For CSRs

| Priority | Action | When You See... |
|:--------:|--------|-----------------|
| 1 | **Remove** | Hardware Event: "Temp Over Fire Risk", "CSR - Remove", or "TOFR - Remove"<br/>OR Monitoring Point Status: "Blacklist" |
| 2 | **Replace** | Battery Status: Critical (predicted)<br/>OR Hardware Event: "TOFR - Replace"<br/>OR Monitoring Point Status: "Released" |
| 3 | **Check/Add Network Equipment** | Hardware Event: "CSR - Strengthen Network" |
| 4 | **Check Placement** | Hardware Event: "CSR - Check Placement" |
| 5 | **Turn On** | Sensor Status: "Offline" |
| 6 | **Ok** | No issues detected |
