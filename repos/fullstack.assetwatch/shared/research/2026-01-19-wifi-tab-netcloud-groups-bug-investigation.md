---
date: 2026-01-19T16:05:20-05:00
researcher: aw-jwalker
git_commit: 35bb96c8a286eb1705ca2dd97fea4b5f4c8cc648
branch: dev
repository: fullstack.assetwatch
topic: "WiFi Tab and NetCloud Groups Bug Investigation"
tags: [research, codebase, wifi, netcloud, facility-modal, validation, bug-investigation]
status: complete
last_updated: 2026-01-19
last_updated_by: aw-jwalker
last_updated_note: "Added follow-up research comparing Hub WiFi Setup vs Edit Facility Modal implementations"
---

# Research: WiFi Tab and NetCloud Groups Bug Investigation

**Date**: 2026-01-19T16:05:20-05:00
**Researcher**: aw-jwalker
**Git Commit**: 35bb96c8a286eb1705ca2dd97fea4b5f4c8cc648
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question

A bug was reported with the WiFi tab of the Edit Facility modal:
1. WiFi credentials are not populating in the "Edit Facility" modal on the Facility Layout page
2. Credentials exist in the hub WiFi setup tool (suggesting they were saved correctly)
3. Updating the facility page fails
4. All new customers have unconfigured NetCloud groups
5. In dev branch only: validation shows "password is required when SSID is not null" even when SSID IS null

We need to research:
- How NetCloud groups and WiFi credentials are handled for new customers
- What development occurred in the last 60 days that could have caused these issues

## Summary

This research documents the complete architecture of the WiFi credentials and NetCloud groups functionality in AssetWatch. Key components include:

1. **WiFi Tab Component**: Located in `UpdateFacility.tsx`, renders `WifiPasscodeForm.tsx` for team members only
2. **NetCloud Groups**: Managed via Cradlepoint Lambda, creates pairs of groups (IBR200 + S400) per facility
3. **Data Flow**: Frontend → Lambda → MySQL stored procedures for WiFi; Frontend → Lambda → NetCloud API for groups
4. **Recent Changes**: BrandonD09 made significant changes to NetCloud group handling in Nov-Dec 2025

## Detailed Findings

### 1. WiFi Tab Component Structure

**Main Modal Component:**
`frontend/src/components/CustomerDetailPage/FacilityLayout/Facility/UpdateFacility.tsx`

- **Lines 840-854**: WiFi tab visibility controlled by `isTeamMember` check
- **Lines 175-238**: WiFi credentials loaded via `getWifiCredentials(facility.extfid)` on component mount
- **Lines 697-759**: `manageHotspotGroupCredentials()` function handles NetCloud group creation/updates

**WiFi Form Component:**
`frontend/src/components/CustomerDetailPage/FacilityLayout/Facility/WifiPasscodeForm.tsx`

- **Lines 99-113**: Renders `primarySSID` and `primaryPasscode` form fields
- **Lines 55-74**: "Customer using their own WIFI?" radio group
- **Lines 115-125**: Generate passcode button using `crypto.getRandomValues()`

### 2. WiFi Credentials Data Flow

**Frontend API Layer:**
`frontend/src/shared/api/FacilityServices.ts`

- **Lines 684-694**: `getWifiCredentials()` calls `getFacilityWifiTemp` method
- **Lines 961-975**: `updateWifiCredentials()` calls `updateFacilityWifiTemp` method

**Backend Lambda:**
`lambdas/lf-vero-prod-facilities/main.py`

- **Lines 671-731**: `getFacilityWifiTemp` handler
  - Initializes empty response structure with default values
  - Calls `Facility_GetFacilityWifiSettings` for settings (customerOwnWifi, hasWifiMeshDevices)
  - Calls `Facility_GetWifi` with type 1 (primary) and type 2 (secondary)
  - Decrypts passcodes using KMS

- **Lines 1410-1490**: `updateFacilityWifiTemp` handler
  - Requires `NikolaTeam` usergroup
  - Encrypts passcodes using KMS
  - Calls stored procedures to update database

**Database Layer:**

| Stored Procedure | File | Purpose |
|------------------|------|---------|
| `Facility_GetWifi` | `mysql/db/procs/R__PROC_Facility_GetWifi.sql` | SELECT SSID, Passcode from Facility_Wifi |
| `Facility_GetFacilityWifiSettings` | `mysql/db/procs/R__PROC_Facility_GetFacilityWifiSettings.sql` | SELECT CustomerOwnWifi, HasWifiMeshDevices from Facility |
| `Facility_UpdateWifiByType` | `mysql/db/procs/R__PROC_Facility_UpdateWifiByType.sql` | UPDATE WiFi credentials by type |

**Database Tables:**

`Facility_Wifi` table (from `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:1365-1377`):
```sql
CREATE TABLE `Facility_Wifi` (
  `FacilityWifiID` int NOT NULL AUTO_INCREMENT,
  `FacilityWifiTypeID` int NOT NULL,  -- 1=Primary, 2=Secondary
  `FacilityID` int NOT NULL,
  `SSID` varchar(45) DEFAULT NULL,
  `Passcode` varchar(255) DEFAULT NULL,  -- KMS encrypted
  PRIMARY KEY (`FacilityWifiID`),
  UNIQUE KEY `FacilityID_WifiTypeID_idx` (`FacilityID`,`FacilityWifiTypeID`)
);
```

### 3. NetCloud Groups Architecture

**Lambda Handler:**
`lambdas/lf-vero-prod-cradlepoint/main.py`

- **Lines 236-275**: `create_netcloud_group()` creates groups in NetCloud API
  - Creates TWO groups per facility: one for IBR200 (ProductID 49), one for S400 (ProductID 105)
  - Naming convention: `{CustomerName} - {FacilityName} (IBR200)` and `{CustomerName} - {FacilityName} (S400)`

- **Lines 190-207**: `generate_netcloud_group_config()` generates WiFi config for groups:
  ```python
  {
    "wlan": {
      "radio": {"0": {"bss": {"0": {"ssid": primary_ssid, "wpapsk": primary_passcode}}}}
    }
  }
  ```

**Frontend Integration:**
`frontend/src/components/CustomerDetailPage/FacilityLayout/Facility/UpdateFacility.tsx:697-759`

The `manageHotspotGroupCredentials()` function:
1. If `createGroups=true`: Creates new NetCloud groups via `createHotspotMutation`
2. If `createGroups=false`: Searches for existing groups, validates exactly 2 groups exist, then updates

**Database Table:**
`CradlepointDevice_Group` (from `mysql/db/table_change_scripts/V20251121_222840__IWA-14010_Add_CradlepointDevice_Group_Table.sql`):
```sql
CREATE TABLE CradlepointDevice_Group (
  CradlepointDeviceGroupID INT PRIMARY KEY AUTO_INCREMENT,
  GroupID INT NOT NULL,  -- NetCloud Group ID
  Name VARCHAR(65) NOT NULL,
  ActiveFlag BIT(1) NOT NULL,
  URL VARCHAR(100) NOT NULL,
  ProductID INT NOT NULL,  -- 49=IBR200, 105=S400
  DateCreated TIMESTAMP(3),
  DateUpdated TIMESTAMP(3)
);
```

### 4. Validation Schema

`frontend/src/components/CustomerDetailPage/FacilityLayout/Facility/validationSchemas.ts`

**SSID/Password Cross-Validation (Lines 252-274):**
```typescript
.superRefine((data, ctx) => {
  const { primarySSID, primaryPasscode } = data || {};
  const hasSSID = primarySSID && primarySSID.trim() !== "";
  const hasPasscode = primaryPasscode && primaryPasscode.trim() !== "";

  if (hasSSID && !hasPasscode) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "Cannot be blank when SSID is provided",
      path: ["primaryPasscode"],
    });
  }

  if (hasPasscode && !hasSSID) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "Cannot be blank when passcode is provided",
      path: ["primarySSID"],
    });
  }
});
```

**Password Length Validation (Lines 212-230):**
- Validates password length is 8-63 characters (only when password is provided)

### 5. Recent Commits (Last 60 Days) Affecting WiFi/NetCloud

#### Critical NetCloud Changes by BrandonD09:

**Commit `4953a7fdb` (Dec 10, 2025)**: "Fix Netcloud group create and update function for facility layout"
- **File changed**: `UpdateFacility.tsx` (+40, -12 lines)
- **Key changes**:
  1. Added `createGroups = false` parameter to `manageHotspotGroupCredentials()`
  2. Added new conditional: if `createGroups=true`, immediately creates groups and returns
  3. Changed group filtering logic to require EXACTLY 2 matching groups
  4. Removed the `else` clause that previously auto-created groups when none were found
  5. Added `Product.CRADLEPOINT` and `Product.HOTSPOT_S400` product ID filtering

**Commit `838258038` (Dec 1, 2025)**: "Remove netcloud test groups from API call. Get groups from the database"
- **File changed**: `useGetHotspotGroups.ts` (+4, -13 lines)
- **Key changes**:
  1. Removed `isTestEnvironment()` check
  2. Removed `testNetCloudGroupList` fallback for QA environments
  3. Now always fetches from database regardless of environment

**Commit `d17576294` (Nov 21, 2025)**: "Add stored procedure to create CradlepointDevice_Group table"
- **File changed**: `V20251121_222840__IWA-14010_Add_CradlepointDevice_Group_Table.sql`
- Created the `CradlepointDevice_Group` table

#### Other WiFi-Related Commits:

| Hash | Date | Author | Description |
|------|------|--------|-------------|
| `f003f6fe5` | Dec 1, 2025 | aw-jwalker | Add handling for S400 netcloud groups to AddHubs |
| `978849c3c` | Dec 1, 2025 | aw-jwalker | Move into update_cradlepoint |
| `56d4012d2` | Jan 7, 2026 | aw-jwalker | Add enclosure cascade to Track Inventory |

### 6. New Customer NetCloud Group Flow

**Customer Creation:**
`lambdas/lf-vero-prod-sensor/main.py:520-535`
- Method: `addCustomer`
- Calls stored procedure `Customer_AddCustomerFromAssetWatch`
- No automatic NetCloud group creation at this stage

**Facility Creation:**
`lambdas/lf-vero-prod-facilities/main.py:1151`
- Method: `updateFacilityFromLayout`
- Calls stored procedure `Facility_AddFacilityFromAssetWatch`
- No automatic NetCloud group creation at this stage

**NetCloud Group Creation (Manual):**
Groups are created when:
1. User opens Edit Facility modal → WiFi tab
2. User enters SSID/Passcode and clicks Save
3. `manageHotspotGroupCredentials()` is called with `createGroups=true` (for new facilities)

## Code References

### Frontend Components
- `frontend/src/components/CustomerDetailPage/FacilityLayout/Facility/UpdateFacility.tsx:697-759` - manageHotspotGroupCredentials function
- `frontend/src/components/CustomerDetailPage/FacilityLayout/Facility/WifiPasscodeForm.tsx:99-113` - WiFi form fields
- `frontend/src/components/CustomerDetailPage/FacilityLayout/Facility/validationSchemas.ts:252-274` - SSID/password validation
- `frontend/src/hooks/services/hotspots/useGetHotspotGroups.ts` - Hotspot groups query hook

### Backend Lambdas
- `lambdas/lf-vero-prod-facilities/main.py:671-731` - getFacilityWifiTemp handler
- `lambdas/lf-vero-prod-facilities/main.py:1410-1490` - updateFacilityWifiTemp handler
- `lambdas/lf-vero-prod-cradlepoint/main.py:236-275` - create_netcloud_group function
- `lambdas/lf-vero-prod-cradlepoint/main.py:190-207` - generate_netcloud_group_config

### Database
- `mysql/db/procs/R__PROC_Facility_GetWifi.sql` - Get WiFi credentials
- `mysql/db/procs/R__PROC_Facility_GetFacilityWifiSettings.sql` - Get WiFi settings
- `mysql/db/procs/R__PROC_Facility_UpdateWifiByType.sql` - Update WiFi credentials
- `mysql/db/table_change_scripts/V20251121_222840__IWA-14010_Add_CradlepointDevice_Group_Table.sql` - CradlepointDevice_Group table

### Type Definitions
- `frontend/src/shared/types/facility/FacilityWifiCredentials.ts` - WiFi credentials type
- `frontend/src/shared/types/facility/FacilityFormValues.ts:34-39` - Form values including WiFi fields
- `frontend/src/shared/types/hotspots/HotspotGroup.ts` - HotspotGroup type

## Architecture Documentation

### Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     WIFI CREDENTIALS FLOW                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  UpdateFacility.tsx                                             │
│       │                                                          │
│       ├── useEffect (line 175-238)                              │
│       │       │                                                  │
│       │       └── getWifiCredentials(extfid)                    │
│       │               │                                          │
│       │               ▼                                          │
│       │       FacilityServices.ts:684-694                       │
│       │               │                                          │
│       │               └── POST apiVeroFacility                   │
│       │                       meth: "getFacilityWifiTemp"        │
│       │                       │                                  │
│       │                       ▼                                  │
│       │               lf-vero-prod-facilities/main.py:671-731   │
│       │                       │                                  │
│       │                       ├── Facility_GetFacilityWifiSettings │
│       │                       ├── Facility_GetWifi (type=1)     │
│       │                       ├── Facility_GetWifi (type=2)     │
│       │                       └── decrypt_passcode (KMS)        │
│       │                               │                          │
│       │                               ▼                          │
│       │                       Response: {                        │
│       │                         primarySSID,                     │
│       │                         primaryPasscode,                 │
│       │                         secondarySSID,                   │
│       │                         secondaryPasscode,               │
│       │                         customerOwnWifi,                 │
│       │                         hasWifiMeshDevices               │
│       │                       }                                  │
│       │                                                          │
│       └── handleFormSubmit (line 395-690)                       │
│               │                                                  │
│               ├── updateWifiCredentials() → Database            │
│               │                                                  │
│               └── manageHotspotGroupCredentials() → NetCloud    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    NETCLOUD GROUPS FLOW                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  manageHotspotGroupCredentials(customerName, facilityName,      │
│                                 primarySSID, primaryPasscode,    │
│                                 createGroups)                    │
│       │                                                          │
│       ├── IF createGroups=true:                                 │
│       │       └── createHotspotMutation.mutateAsync()           │
│       │               │                                          │
│       │               └── POST apiVeroCradlepoint               │
│       │                       meth: "createHotspotGroups"        │
│       │                       │                                  │
│       │                       ▼                                  │
│       │               lf-vero-prod-cradlepoint:                 │
│       │               create_netcloud_group() x2                │
│       │               (IBR200 + S400)                           │
│       │                                                          │
│       └── ELSE:                                                 │
│               └── getHotspotGroups(hotspotGroupName)            │
│                       │                                          │
│                       ▼                                          │
│               Filter to exactly 2 matching groups               │
│               (one IBR200, one S400)                            │
│                       │                                          │
│                       ├── IF 2 groups found:                    │
│                       │       └── updateHotspotMutation()       │
│                       │                                          │
│                       └── IF >2 groups: Show error toast        │
│                           IF <2 groups: Do nothing (silent)     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Architectural Points

1. **WiFi credentials are stored in MySQL** (`Facility_Wifi` table), encrypted with KMS
2. **NetCloud groups are external** (Cradlepoint API), with local references in `CradlepointDevice_Group`
3. **Two separate data stores**: Database WiFi credentials ≠ NetCloud group WiFi config
4. **Role-based access**: Only `NikolaTeam` usergroup can see/edit WiFi tab
5. **Validation is client-side**: Zod schema validates SSID/password pairing

## Historical Context (from thoughts/)

- `thoughts/shared/research/2026-01-08-netcloud-groups-management.md` - Comprehensive research on NetCloud group management architecture
- `thoughts/shared/research/2026-01-08-hardware-whitelist-system.md` - Hardware whitelist system documentation including 6 whitelisted hotspot MACs for QA
- `thoughts/shared/plans/2025-12-01-iwa-13437-addhubs-hotspot-bug-fix.md` - Bug fix plan for AddHubs hotspot movement

## Related Research

- `thoughts/shared/research/2026-01-08-netcloud-groups-management.md`
- `thoughts/shared/research/2026-01-08-hardware-whitelist-system.md`

## Follow-up Research: Frontend Display Issue (2026-01-19)

### Developer Feedback

Brandon Drakeford confirmed: **"The data is there, but we are not displaying it."** The Hub WiFi Setup tool successfully shows the credentials, indicating this is a frontend display issue in the Edit Facility modal, not a backend/database issue.

### Confirmed Facts

1. **Both tools use the same API**: `getWifiCredentials()` from `@api/FacilityServices.ts:684-694`
2. **Hub WiFi Setup works** - displays credentials correctly
3. **Edit Facility Modal doesn't work** - fields appear empty
4. **Backend always returns an object** (never `null`) - see `main.py:674-681`:
   ```python
   retVal = {
       "primarySSID": "",        # Empty string default, populated from DB if found
       "primaryPasscode": "",
       "secondarySSID": "",
       "secondaryPasscode": "",
       "customerOwnWifi": False,
       "hasWifiMeshDevices": False,
   }
   ```

### Key Implementation Difference

| Aspect | Hub WiFi Setup (Works) | Edit Facility Modal (Broken) |
|--------|------------------------|------------------------------|
| **File** | `pages/WifiSetup/WifiSetupTab.tsx` | `components/.../UpdateFacility.tsx` |
| **Input Pattern** | Controlled: `value={ssid}` | Uncontrolled: `{...registerFormField()}` |
| **State Management** | `useState` + `useEffect` to sync | React-Hook-Form `reset()` |
| **Data Binding** | Direct: `setSsid(data.primarySSID)` | Spread: `reset({...credentials})` |

**Hub WiFi Setup** (lines 62-70):
```typescript
const { mutate: getWifiCredentials, data: facilityWifiCredentials } = useGetWifiCredentials();

useEffect(() => {
  if (!facility || !facilityWifiCredentials) return;
  setSsid(facilityWifiCredentials.primarySSID);      // Direct state set
  setPassword(facilityWifiCredentials.primaryPasscode);
}, [facility, facilityWifiCredentials]);
```

**Edit Facility Modal** (lines 177-234):
```typescript
let credentials;
if (isTeamMember) {
  credentials = await getWifiCredentials(facility.extfid);
  if (credentials === null) {  // ⚠️ This check never triggers - API returns object, not null
    credentials = defaultWifiCredentials;
  }
}
reset({ ...otherFields, ...credentials });  // Spread into form
```

### Potential Issues (Speculation)

1. **Null check is ineffective** - The check `credentials === null` at line 182 will never be true because the backend returns an object with empty strings, not `null`. If DB has no data, form gets empty strings instead of triggering the default fallback.

2. **Credentials undefined when not team member** - If `isTeamMember` is false, `credentials` stays `undefined`. Spreading `undefined` adds nothing to the reset object.

3. **Possible race condition** - A second `useEffect` at lines 240-246 resets the form for partner scenarios. If triggered after the credentials useEffect, it could overwrite WiFi values with defaults.

4. **Uncontrolled input timing** - React-Hook-Form's `register()` creates uncontrolled inputs. If `reset()` timing is off relative to component mount, fields may not update.

### Recommended Debugging Steps

Add console logging at `UpdateFacility.tsx:180`:
```typescript
credentials = await getWifiCredentials(facility.extfid);
console.log("API returned credentials:", credentials);
console.log("isTeamMember:", isTeamMember);
```

Check browser DevTools Network tab for the `getFacilityWifiTemp` API response to verify data is returned.

---

## Open Questions

1. **Why does the null check exist?** - The backend never returns `null`. Was this a previous behavior that changed?

2. **Is `isTeamMember` correctly evaluated?** - If false, WiFi credentials are never fetched.

3. **Unconfigured NetCloud groups for new customers**: Commit `4953a7fdb` (Dec 10) removed auto-creation of groups when none exist. Groups now only created when `createGroups=true` is explicitly passed.

4. **Validation showing error when SSID is null (dev only)**: The validation logic appears correct. May be related to form initialization timing or how empty strings vs undefined are handled.

5. **Dec 1 commit impact** (`838258038`): Removed QA test environment fallback. If `CradlepointDevice_Group` table is not populated, no groups returned.
