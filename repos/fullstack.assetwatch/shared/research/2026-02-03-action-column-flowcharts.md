# Sensor Action Column Logic - Flowcharts

**Source**: CustomerDetail > Sensors page
**Last Updated**: 2026-02-03

---

## Legend

- **Yellow boxes** = Hardware Events or checks for Hardware Events
  - Hardware Events are visible in the "Hardware Events" column in the UI
  - Created automatically by system monitoring OR manually by CSR
  - Examples: "Temp Over Fire Risk", "CSR - Remove", "Low Battery Voltage", "TOFR Replace"
- **White boxes** = Status checks (NOT hardware events)
  - "Battery Critical" = ML prediction status
  - "Offline" = Sensor communication status
- **🔥 TOFR Workflow**: Special safety workflow for high-temperature monitoring points
  - **Blacklist**: Confirmed safety risk - sensor must be removed
  - **Released**: Risk resolved - sensor should be replaced
  - **Pending Review**: Under evaluation (continues to standard checks)

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
        ML_BATTERY["ML Battery<br/>Prediction Model"]
        ML_MOVED["ML Sensor Moved<br/>Detection Model"]
        VOLTAGE["Sensor Voltage<br/>Readings/Diagnostics"]
    end

    ML_BATTERY -->|"Updates"| SENSORLIFE["SensorLife Table<br/>PredictedBatteryStatus"]
    SENSORLIFE -->|"Check Status"| BATTERY_CRITICAL["Battery Status = Critical"]

    FIRE_MONITOR -->|"High temp detected"| TOFR_PROC["HardwareIssue_<br/>ReceiversTempOverFireRisk"]
    TOFR_PROC -->|"Creates"| TOFR_ISSUES["Temp Over Fire Risk<br/>TOFR - Replace<br/>TOFR - Remove"]

    ML_MOVED -->|"Detected"| CHECK_PLACEMENT_HWE["CSR - Check Placement"]

    VOLTAGE -->|"2.5V - 3.2V"| LOW_V["Low Battery Voltage"]

    CSR_UI -->|"Manual entry"| CSR_ISSUES["CSR - Remove<br/>CSR - Strengthen Network"]

    LEGEND["Hardware Event"]

    %% Style hardware events with light amber (works in light/dark mode)
    style TOFR_ISSUES fill:#FFF9C4,stroke:#F57F17,color:#000
    style CHECK_PLACEMENT_HWE fill:#FFF9C4,stroke:#F57F17,color:#000
    style LOW_V fill:#FFF9C4,stroke:#F57F17,color:#000
    style CSR_ISSUES fill:#FFF9C4,stroke:#F57F17,color:#000
    style LEGEND fill:#FFF9C4,stroke:#F57F17,color:#000
```

---

## Diagram 2: What Triggers "Replace" Action?

The database determines if a sensor needs replacement based on battery status OR hardware events.

```mermaid
flowchart LR
    subgraph Database["Database Layer"]
        BATTERY["Battery Status<br/>(from ML predictions)"]
        OR_NODE{{"OR"}}
        HW_ISSUE["- Low Battery Voltage<br/>- TOFR - Replace"]
    end

    BATTERY -->|"= Critical"| OR_NODE
    HW_ISSUE -->|"Open"| OR_NODE
    OR_NODE --> REPLACE_ACTION

    REPLACE_ACTION(["hasReplaceAction = 1"])

    LEGEND["Hardware Event"]

    %% Style hardware events with light amber
    style HW_ISSUE fill:#FFF9C4,stroke:#F57F17,color:#000
    style LEGEND fill:#FFF9C4,stroke:#F57F17,color:#000
```

---

## Diagram 3: Decision Flowchart

Shows how the Action column value is determined, using terminology visible in the UI.

```mermaid
flowchart TD
    START(["Check Sensor Action"])

    START --> CHECK_TOFR{{Has Monitoring<br/>Point Status?}}

    CHECK_TOFR -->|No| STANDARD_CHECKS
    CHECK_TOFR -->|Yes| TOFR_EVAL

    subgraph TOFR_EVAL["🔥 TOFR Workflow Evaluation"]
        MP_BLACKLIST{{Blacklist?}}
        MP_RELEASED{{Released?}}

        MP_BLACKLIST -->|Yes| TOFR_REMOVE[REMOVE]
        MP_BLACKLIST -->|No| MP_RELEASED
        MP_RELEASED -->|Yes| TOFR_REPLACE[REPLACE]
        MP_RELEASED -->|No| TO_STANDARD[Continue to<br/>Standard Checks]
    end

    TO_STANDARD --> STANDARD_CHECKS

    subgraph STANDARD_CHECKS["Standard Priority Checks"]
        CHECK1{{"Fire Risk<br/>Issue?"}}
        CHECK2A{{"Battery<br/>Critical?"}}
        CHECK2B{{"TOFR<br/>Replace?"}}
        CHECK3{{"Strengthen<br/>Network?"}}
        CHECK4{{"Check<br/>Placement?"}}
        CHECK5{{"Offline?"}}

        CHECK1 -->|Yes| STD_REMOVE[REMOVE]
        CHECK1 -->|No| CHECK2A
        CHECK2A -->|Yes| STD_REPLACE[REPLACE]
        CHECK2A -->|No| CHECK2B
        CHECK2B -->|Yes| STD_REPLACE
        CHECK2B -->|No| CHECK3
        CHECK3 -->|Yes| NETWORK[CHECK/ADD<br/>NETWORK EQUIPMENT]
        CHECK3 -->|No| CHECK4
        CHECK4 -->|Yes| PLACEMENT[CHECK PLACEMENT]
        CHECK4 -->|No| CHECK5
        CHECK5 -->|Yes| TURNON[TURN ON]
        CHECK5 -->|No| OK[OK]
    end

    LEGEND["Hardware Event check"]

    %% Style hardware event checks with light amber
    style CHECK1 fill:#FFF9C4,stroke:#F57F17,color:#000
    style CHECK2B fill:#FFF9C4,stroke:#F57F17,color:#000
    style CHECK3 fill:#FFF9C4,stroke:#F57F17,color:#000
    style CHECK4 fill:#FFF9C4,stroke:#F57F17,color:#000
    style LEGEND fill:#FFF9C4,stroke:#F57F17,color:#000
```

---

## Diagram 4: "Turn On" Troubleshooting Workflow

Shows what happens when a user sees "Turn On" in the Action column and attempts to resolve it.

```mermaid
flowchart TD
    START(["User sees 'Turn On'<br/>in Action column"])

    START --> ACTION["User attempts to<br/>turn on sensor"]

    ACTION --> CHECK{{"Did sensor<br/>turn on?"}}

    CHECK -->|"Yes"| SUCCESS["Sensor is online<br/>Action becomes 'Ok'"]
    CHECK -->|"No"| FAILED["Sensor did not respond<br/>Action becomes 'Replace'"]

    SUCCESS --> RESOLVED["\u2705 Resolved"]
    FAILED --> NEXT_STEP["Sensor needs<br/>replacement"]
```

**Note**: This diagram shows the user troubleshooting process that occurs AFTER the system has already determined the Action column should display "Turn On" (from Diagram 3).

---

## Priority Summary

| Priority | Action | Trigger Type | When You See... |
|:--------:|--------|:------------:|-----------------|
| 1 | **Remove** | 🟡 HWE or MP Status | **HWE**: "Temp Over Fire Risk", "CSR - Remove", "TOFR - Remove"<br/>**MP Status**: "Blacklist" |
| 2a | **Replace** | Battery Status | **Battery**: Critical (from ML prediction) |
| 2b | **Replace** | 🟡 HWE or MP Status | **HWE**: "TOFR - Replace", "Low Battery Voltage"<br/>**MP Status**: "Released" |
| 3 | **Check/Add Network** | 🟡 HWE | **HWE**: "CSR - Strengthen Network" |
| 4 | **Check Placement** | 🟡 HWE | **HWE**: "CSR - Check Placement" (auto-created by ML) |
| 5 | **Turn On** | Sensor Status | **Sensor Status**: "Offline" |
| 6 | **Ok** | None | No issues detected |
