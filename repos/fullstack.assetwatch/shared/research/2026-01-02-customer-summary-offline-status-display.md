---
date: 2026-01-02T09:00:00-05:00
researcher: Jackson Walker
git_commit: 3f78f75c91c5b85ab2a9af41b30359dc2c41dd5c
branch: dev
repository: fullstack.assetwatch
topic: "Customer Detail Summary Page - Offline Status Display and Permissions"
tags: [research, codebase, customer-detail, offline-status, permissions, hardware]
status: complete
last_updated: 2026-01-02
last_updated_by: Jackson Walker
---

# Research: Customer Detail Summary Page - Offline Status Display and Permissions

**Date**: 2026-01-02T09:00:00-05:00
**Researcher**: Jackson Walker
**Git Commit**: 3f78f75c91c5b85ab2a9af41b30359dc2c41dd5c
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question

How does the display of offline status on the customer detail summary page work? Which user groups and roles are able to see it?

## Summary

The offline status display on the Customer Detail Summary page is part of the **Call To Action** section. It shows two categories when offline hardware exists:
1. **"Hubs Offline"** - displays count of offline hubs
2. **"Hotspots Offline"** - displays count of offline hotspots (Cradlepoint devices)

### Who Can See Offline Status?

The offline status categories are visible only when **both** conditions are met:
1. There is at least one offline hub/hotspot
2. The user has `hasHardwareViewPermission`

**`hasHardwareViewPermission` is granted to:**
- **Engineering role** (`UserRole.ENGINEERING`)
- **NikolaTeam Cognito group** (when not in demo view)
- **CustomerHardwareStatus role** (`UserRole.CUSTOMER_HARDWARE_STATUS`)
- **CustomerHardwareStatusAdvanced role** (`UserRole.CUSTOMER_HARDWARE_STATUS_ADVANCED`)

### User Groups That CANNOT See Offline Status:

- **Regular Customers** (Customer Cognito group without hardware status roles)
- **Partners** (Partner Cognito group without being NikolaTeam)
- **Contract Manufacturers** (ContractManufacturer Cognito group)
- **Any user** when in demo view mode

## Detailed Findings

### Component Architecture

The offline status display flows through this component hierarchy:

```
CustomerDetail.tsx (page)
└── SummaryTab.tsx
    └── CallToAction.tsx
        ├── Category (renders each action item)
        ├── OfflineHubsModal
        └── OfflineHotspotsModal
```

### Data Flow

#### 1. Data Fetching (`useHardwareStatuses.tsx`:33-70)

The `useHardwareStatuses` hook fetches and filters hardware data:

```typescript
// Fetch hub data
const hubListQuery = useGetHubListData({
  params: { asOfDate, customerId, fid: selectedFacilityIds, hid: 0 },
});

// Fetch cradlepoint/hotspot data
const cradlepointStatsQuery = useGetCradlepointStats({
  params: { customerId, facilityIds: selectedFacilityIds },
});
```

#### 2. Offline Filtering Logic (`useHardwareStatuses.tsx`:12-19)

```typescript
// Offline hubs: state is "Offline" AND sensor network is "Active"
const filterOfflineHubs = (hubs: HubList[]) =>
  hubs.filter((hub) => hub.hubstate === "Offline" && hub.tsn === "Active");

// Offline hotspots: state is "Offline" AND status is "Assigned"
const filterOfflineHotspots = (hotspots: Hotspot[]) =>
  hotspots.filter(
    (cradlepoint) =>
      cradlepoint.State === "Offline" && cradlepoint.cpStatus === "Assigned",
  );
```

#### 3. Permission Calculation (`useActionCategories.ts`:135-138)

```typescript
const hasHardwareViewPermission =
  isEngineering ||
  (isTeamMember && !demoView) ||
  isCustomerHardwareStatusRoleUser;
```

#### 4. Category Visibility (`useActionCategories.ts`:181-195)

```typescript
{
  label: "Hubs Offline",
  icon: { name: faHardDrive, color: "neutral10" },
  isVisible: offlineHubs.length > 0 && hasHardwareViewPermission,
  isClickable: true,
  count: offlineHubs.length,
  onClick: () => toggleModal("offlineHubsModal", true),
},
{
  label: "Hotspots Offline",
  icon: { name: faWifiSlash, color: "neutral10" },
  isVisible: offlineHotspots.length > 0 && hasHardwareViewPermission,
  isClickable: true,
  count: offlineHotspots.length,
  onClick: () => toggleModal("offlineHotspotsModal", true),
},
```

### Permission System Details

#### Cognito User Groups (`CognitoUserGroup.ts`)

Four broad organizational groups:
- `CONTRACT_MANUFACTURER` - Contract manufacturer organizations
- `CUSTOMER` - Customer organizations
- `NIKOLA_TEAM` - Internal AssetWatch team
- `PARTNER` - Partner organizations

#### Relevant Roles (`UserRole.ts`)

- `ENGINEERING` - Full engineering access (internal)
- `CUSTOMER_HARDWARE_STATUS` - Customer-specific hardware status view
- `CUSTOMER_HARDWARE_STATUS_ADVANCED` - Advanced hardware status view

#### Role Derivation (`AuthContext.tsx`:282-292)

```typescript
const isCustomerHardwareStatusAdvanced = userRole.includes(
  UserRole.CUSTOMER_HARDWARE_STATUS_ADVANCED,
);
const isCustomerHardwareStatus =
  userRole.includes(UserRole.CUSTOMER_HARDWARE_STATUS) ||
  isCustomerHardwareStatusAdvanced;

const isCustomerHardwareStatusRoleUser =
  isCustomerHardwareStatusAdvanced || isCustomerHardwareStatus;
```

### UI Interaction

When a user clicks on the offline status category:
1. A modal opens (`OfflineHubsModal` or `OfflineHotspotsModal`)
2. Modal displays a table with:
   - Hub/Hotspot location (Facility, Location Notes)
   - Device identification (Serial Number/MAC Address)
   - Photos (with lightbox viewer)
3. Modal includes troubleshooting instructions
4. Contact information varies based on user role (Partner/Customer vs Support)

### Related Hardware Tab Access

The hardware tabs (Sensors, Hubs, Hotspots) in the side navigation use a similar but slightly different permission check (`SideNav.tsx`:115-119):

```typescript
const canViewHardwareTabs =
  (!cognitoUserGroup.includes("Customer") &&
    !(cognitoUserGroup.includes("Partner") && !userRole.includes("FST")) &&
    !isDemoView) ||
  isCustomerHardwareStatusRoleUser;
```

This allows:
- Internal team members (NikolaTeam) when not in demo view
- Partners with FST (Field Service Technician) role when not in demo view
- Customers with hardware status roles

## Code References

| File | Lines | Description |
|------|-------|-------------|
| `frontend/src/components/CustomerDetailPage/SummaryTab/hooks/useActionCategories.ts` | 135-138 | Permission calculation |
| `frontend/src/components/CustomerDetailPage/SummaryTab/hooks/useActionCategories.ts` | 181-195 | Offline category definitions |
| `frontend/src/components/CustomerDetailPage/SummaryTab/useHardwareStatuses.tsx` | 12-19 | Offline filtering logic |
| `frontend/src/components/CustomerDetailPage/SummaryTab/CallToAction.tsx` | 30-52 | Category rendering |
| `frontend/src/components/CustomerDetailPage/SummaryTab/OfflineHubsModal.tsx` | - | Hub offline modal |
| `frontend/src/components/CustomerDetailPage/SummaryTab/OfflineHotspotsModal.tsx` | - | Hotspot offline modal |
| `frontend/src/contexts/AuthContext.tsx` | 282-292 | Role derivation |
| `frontend/src/components/CustomerDetailPage/SideNav.tsx` | 115-119 | Hardware tab permissions |
| `frontend/src/shared/enums/UserRole.ts` | 22-23 | Hardware status roles |
| `frontend/src/shared/enums/CognitoUserGroup.ts` | 1-6 | Cognito group definitions |

## Architecture Documentation

### Permission Hierarchy (Offline Status Visibility)

```
Can View Offline Status?
│
├── isEngineering? ────────────────────────> YES
│
├── isTeamMember (NikolaTeam)?
│   └── AND NOT demoView? ─────────────────> YES
│
└── isCustomerHardwareStatusRoleUser?
    ├── CUSTOMER_HARDWARE_STATUS role? ────> YES
    └── CUSTOMER_HARDWARE_STATUS_ADVANCED? ─> YES

All other cases ───────────────────────────> NO
```

### Data Requirements for Visibility

```
Offline Category Visible?
│
├── hasHardwareViewPermission = true
│
└── offlineHubs.length > 0  OR  offlineHotspots.length > 0
```

## Open Questions

None - the research question has been fully answered.
