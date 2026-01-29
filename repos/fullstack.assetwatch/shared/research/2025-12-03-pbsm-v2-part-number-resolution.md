---
date: 2025-12-03T12:00:00-06:00
researcher: aw-jwalker
git_commit: ef31b8cdce7acaf3a700091fffc5c74b5181a146
branch: dev
repository: fullstack.assetwatch
topic: "How is the actual part number identified when PBSM V2 is selected on Track Inventory page?"
tags: [research, codebase, track-inventory, pbsm, serial-number, part-number]
status: complete
last_updated: 2025-12-03
last_updated_by: aw-jwalker
---

# Research: PBSM V2 Part Number Resolution on Track Inventory Page

**Date**: 2025-12-03T12:00:00-06:00
**Researcher**: aw-jwalker
**Git Commit**: ef31b8cdce7acaf3a700091fffc5c74b5181a146
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question
On the Track Inventory page, when "PBSM V2" is selected in the Part Number dropdown (which contains options like "PBSM v2" as well as regular part numbers like "100-006"), how is the actual part number of the serial number identified? Is the serial number looked up in the Receiver table to return the PartID?

## Summary

**No, the Receiver table is NOT used to determine the PartID when PBSM V2 is selected.** Instead, the actual part number is derived from the **first character of the serial number** using a hardcoded frontend mapping function. The Receiver table is only used afterward to **validate** that the serial number exists with that derived PartID.

### Key Findings:
1. "PBSM v2" dropdown option has a special `partId` value of `"0"` (not a real Part ID)
2. When `partId === "0"`, serial numbers are grouped by their first character
3. The `getPartNumberFromSerialNumber()` function maps the first digit to a specific part number
4. The derived PartID is then used to validate the serial number exists in the Receiver table

## Detailed Findings

### 1. Part Number Dropdown Configuration

**Location**: `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx:272-287`

```typescript
augmentedPartNumberDropdownList.push({
  label: "Hub v2",
  value: "4",
});
augmentedPartNumberDropdownList.push({
  label: "PBSM v2",
  value: "0",  // Special value - NOT a real PartID
});
augmentedPartNumberDropdownList.push({
  label: "Hub v3",
  value: PartEnum["710-200"].toString(),
});
augmentedPartNumberDropdownList.push({
  label: "Enclosure",
  value: "999", // Another special grouping value
});
```

The "PBSM v2" option uses `value: "0"` which is a special sentinel value indicating that the actual PartID should be derived from the serial numbers entered.

### 2. Serial Number Processing Flow for PBSM V2

**Location**: `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx:907-969`

When `partId === "0"` (PBSM v2 selected), the following flow occurs:

```typescript
} else if (partId === "0") {
  // group SNs by the character in the 0 index (aka charAt(0))
  const snsGroupedByPart = _.groupBy(validSerialNumbers, "[0]");

  // ... validation for multiple part numbers with revision change ...

  _.forIn(snsGroupedByPart, async (snListForPart, firstChar) => {
    const currentPartNumber = getPartNumberFromSerialNumber(firstChar);
    const currentPartID = PartEnum[currentPartNumber];

    // Check that sensors are valid and exist prior to adding
    const checkInventoryResponse = await checkInventorySerialNumbers(
      snListForPart.join(","),
      currentPartID.toString(),
    );
    // ... validation and mutation ...
  });
}
```

### 3. Part Number Derivation from Serial Number

**Location**: `frontend/src/components/Utilities.ts:539-562`

```typescript
export function getPartNumberFromSerialNumber(serialNumber: string) {
  // from Jira https://nikolalabs.atlassian.net/browse/IWA-2467
  // Column Logic:
  // If the user types in Serial Number 0XXXXXX, make the default Part Number 710-001
  // If the user types in Serial Number 1XXXXXX, make the default Part Number 710-001
  // If the user types in Serial Number 2XXXXXX, make the default Part Number 710-001
  // If the user types in Serial Number 3XXXXXX, make the default Part Number 710-003
  // If the user types in Serial Number 4XXXXXX, make the default Part Number 710-004
  // If the user types in Serial Number 5XXXXXX, make the default Part Number 710-001
  // If the user types in Serial Number 6XXXXXX, make the default Part Number 710-006
  // If the user types in Serial Number 7XXXXXX, make the default Part Number 710-007
  // If the user types in Serial Number 8XXXXXX, make the default Part Number 710-001
  // If the user types in Serial Number 9XXXXXX, make the default Part Number 710-001

  switch (serialNumber[0]) {
    case "3": return "710-003";
    case "4": return "710-004";
    case "6": return "710-006";
    case "7": return "710-007";
    case "8": return "710-008";
    default: return "710-001";
  }
}
```

**Note**: The comment in the code says "8" should map to "710-001", but the actual implementation maps "8" to "710-008". The implementation is correct per the tests.

### 4. Serial Number Prefix to Part Number Mapping

| Serial Number Prefix | Part Number | PartID (from enum) |
|---------------------|-------------|-------------------|
| 0, 1, 2, 5, 9       | 710-001     | 3                 |
| 3                   | 710-003     | 7                 |
| 4                   | 710-004     | 8                 |
| 6                   | 710-006     | 9                 |
| 7                   | 710-007     | 10                |
| 8                   | 710-008     | 38                |

### 5. Validation Against Receiver Table

**Location**: `frontend/src/shared/api/InventoryService.ts:46-64`

After the PartID is derived, the serial numbers are validated:

```typescript
export async function checkInventorySerialNumbers(
  serialNumberList: string,
  partId: string,
): Promise<{ fpn: string; sn: string }[] | "error"> {
  const myInit = {
    body: {
      meth: "checkInventorySerialNumbers",
      serialNumberList,
      partId,
    },
  };
  // ... API call
}
```

**Backend Stored Procedure**: `mysql/db/procs/R__PROC_Inventory_CheckSerialNumbers.sql`

```sql
IF (localProductTypeID=3) THEN -- If Vibration Sensor ProductType
  SELECT fp.FundingProjectName AS fpn, r.SerialNumber AS sn
  FROM Receiver r
    LEFT JOIN FundingProject fp ON r.FundingProjectID=fp.FundingProjectID
    INNER JOIN Part p ON p.PartID = r.PartID
  WHERE FIND_IN_SET(r.SerialNumber, inSerialNumbers)
  AND p.PartID = inPartID;
```

This validates that the serial number exists in the Receiver table **with the derived PartID**. If the serial number doesn't exist or has a different PartID, it will not be returned and will be flagged as invalid.

### 6. Why This Design?

The PBSM V2 grouping exists because there are multiple PBSM sensor part numbers (710-001, 710-003, 710-004, 710-006, 710-007, 710-008) that all belong to the same product family. Rather than forcing users to select the exact part number, the system allows them to select "PBSM v2" and enter serial numbers directly - the system then determines the correct part number from the serial number prefix.

This is useful because:
1. Users may not know the exact part number for a sensor
2. Serial numbers contain an embedded part identifier (first digit)
3. Multiple serial numbers with different part numbers can be processed at once (they're grouped by prefix)

## Code References

| File | Lines | Description |
|------|-------|-------------|
| `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx` | 276-279 | PBSM v2 dropdown option definition |
| `frontend/src/components/TrackInventoryPage/TrackInventoryHeader.tsx` | 907-969 | PBSM v2 processing flow |
| `frontend/src/components/Utilities.ts` | 539-562 | `getPartNumberFromSerialNumber()` mapping |
| `frontend/src/shared/api/InventoryService.ts` | 46-64 | `checkInventorySerialNumbers()` API call |
| `mysql/db/procs/R__PROC_Inventory_CheckSerialNumbers.sql` | 19-24 | Validation query against Receiver table |
| `frontend/src/shared/enums/Part.ts` | - | Part number to PartID enum mapping |

## Architecture Documentation

### Data Flow Diagram

```
User selects "PBSM v2" (partId="0")
            ↓
User enters serial numbers (e.g., "8123456, 3456789")
            ↓
Frontend groups by first character:
  {"8": ["8123456"], "3": ["3456789"]}
            ↓
For each group, derive part number:
  "8" → "710-008" → PartID 38
  "3" → "710-003" → PartID 7
            ↓
Validate each group against Receiver table:
  checkInventorySerialNumbers("8123456", "38")
  checkInventorySerialNumbers("3456789", "7")
            ↓
If valid, add sensors with derived PartID
```

### Key Design Decisions

1. **Frontend-based part derivation**: The part number is determined in the frontend using a hardcoded mapping, not from database lookups
2. **Serial number prefix convention**: The first digit of PBSM serial numbers indicates the part number
3. **Validation, not lookup**: The Receiver table is used to validate existence, not to determine the part number
4. **Support for mixed batches**: Multiple serial numbers with different part prefixes can be entered together

## Open Questions

1. What happens if a serial number's first character doesn't match its actual PartID in the Receiver table?
   - The validation will fail and the serial number will be flagged as invalid

2. Is the serial number prefix convention documented elsewhere or enforced at manufacturing?
   - The Jira ticket IWA-2467 established this convention

3. Are there edge cases where the prefix-to-part mapping might be incorrect?
   - The comment in the code mentions "8" should be 710-001, but implementation uses 710-008. Tests confirm 710-008 is correct.
