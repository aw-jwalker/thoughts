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
        FIRE_MONITOR["Sensor Temperature<br/>Readings/Diagnostics"]
        ML["ML Battery<br/>Prediction Model"]
        VOLTAGE["Sensor Voltage<br/>Readings/Diagnostics"]
    end

    FIRE_MONITOR -->|"High temp detected"| TOFR_PROC["HardwareIssue_<br/>ReceiversTempOverFireRisk"]
    TOFR_PROC -->|"Creates"| TOFR_ISSUES["Temp Over Fire Risk<br/>TOFR - Replace<br/>TOFR - Remove"]

    ML -->|"Updates"| SENSORLIFE["SensorLife Table<br/>PredictedBatteryStatus"]
    SENSORLIFE -->|"'Critical'"| REPLACE_FLAG["hasReplaceAction = 1"]

    VOLTAGE -->|"2.5V - 3.2V"| LOW_V["Low Battery Voltage"]

    CSR_UI -->|"Manual entry"| CSR_ISSUES["CSR - Check Placement<br/>CSR - Remove<br/>CSR - Strengthen Network"]
```

---

## Diagram 2: What Triggers "Replace" Action?

The database determines if a sensor needs replacement based on battery status OR hardware issues.

```mermaid
flowchart LR
    subgraph Database["Database Layer"]
        BATTERY["Battery Status<br/>(from ML predictions)"]
        HW_ISSUE["Hardware Issues:<br/>- Low Battery Voltage<br/>- TOFR - Replace"]
    end

    BATTERY -->|"Critical"| REPLACE_ACTION
    HW_ISSUE -->|"Open"| REPLACE_ACTION

    REPLACE_ACTION(["Sensor Needs<br/>Replacement"])
```

---

## Diagram 3: Decision Flowchart

Shows how the Action column value is determined, using terminology visible in the UI.

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

| Priority | Action | When You See... |
|:--------:|--------|-----------------|
| 1 | **Remove** | Hardware Event: "Temp Over Fire Risk", "CSR - Remove", or "TOFR - Remove"<br/>OR Monitoring Point Status: "Blacklist" |
| 2 | **Replace** | Battery Status: Critical (predicted)<br/>OR Hardware Event: "TOFR - Replace"<br/>OR Monitoring Point Status: "Released" |
| 3 | **Check/Add Network Equipment** | Hardware Event: "CSR - Strengthen Network" |
| 4 | **Check Placement** | Hardware Event: "CSR - Check Placement" |
| 5 | **Turn On** | Sensor Status: "Offline" |
| 6 | **Ok** | No issues detected |
