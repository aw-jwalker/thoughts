---
date: 2026-02-05T12:00:00-05:00
researcher: Claude
git_commit: ebf75263138cb1582e583340f9734a3291e50a21
branch: dev
repository: fullstack.assetwatch
topic: "Customer Detail Page - Facility Selection Dropdown & Role-Based Visibility Rules for Facility Statuses"
tags: [research, codebase, customer-detail, facility-status, role-based-access, facility-selection, facility-layout]
status: complete
last_updated: 2026-02-05
last_updated_by: Claude
---

# Research: Customer Detail Page - Facility Selection & Role-Based Visibility Rules for Facility Statuses

**Date**: 2026-02-05
**Researcher**: Claude
**Git Commit**: ebf75263138cb1582e583340f9734a3291e50a21
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question

Search the code for the CustomerDetail page, find the facility selection dropdown (also the facility layout tab of customer detail), and determine if there are any user role-based visibility rules involving facility statuses.

## Summary

**There are no explicit role-based visibility rules that filter which facility statuses a user can see in the facility selection dropdown.** The facility dropdown shows all facilities returned from the backend API, which already excludes `DELETED` (status 4) facilities at the database level. The primary access control model is **entity-based** (which facilities a user has been assigned to) rather than **status-based** (hiding certain statuses from certain roles).

However, there are several adjacent visibility rules:

1. **Demo/Customer View mode** filters out `CHURNED` and `DID_NOT_SUBSCRIBE` facilities from the dropdown
2. **Past-due billing** filters out facilities past their suspension date for customer users
3. **Partners** only see facilities explicitly assigned to them (entity-level filtering)
4. **The Facility Layout tab itself** is hidden from Customers and non-FST Partners
5. **Facility status label** (`STATUS: <name>`) is only displayed to team members and partners in the Facility Layout header
6. **`PENDING_INSTALL` status** hides the "View Facility Hardware" action icon in the Facility Layout tab

## Detailed Findings

### 1. Facility Selection Dropdown

**File**: `apps/frontend/src/components/CustomerDetailPage/FacilitySelection.tsx`

The `FacilitySelection` component is a Mantine `MultiSelect` rendered inside the `SideNav` component. It consumes its data from `CustomerDetailContext.facilityList`.

Key behavior:
- It renders **all** facilities present in `facilityList` — no status-based filtering occurs within the component itself
- It uses `removeDuplicateOptions(facilityList, "fid", "fn")` to create options from facility ID and name
- The dropdown is **disabled** when the active tab is `FacilityOverview`
- If there is only one facility, the dropdown is hidden entirely (returns empty fragment)
- "Select All" and "Deselect All" buttons are provided

**No role-based or status-based filtering exists within this component.** All filtering happens upstream.

### 2. How `facilityList` Gets Populated (Upstream Filtering)

**File**: `apps/frontend/src/pages/CustomerDetail.tsx`

The facility list is fetched and filtered through several paths depending on user role:

#### Path A: Regular Users (non-Partner)
- Calls `getCustomerFacilityList(id)` → stored procedure `Facility_GetCustomerFacilityList`
- The stored procedure filters `FacilityStatusID NOT IN(4)` (excludes DELETED)
- The stored procedure also joins on `Facility_User` table, so users only see facilities they're assigned to
- For **customers with >1 facility**, `filterPastDueAccounts()` additionally removes facilities past their `suspensionDate`

#### Path B: Partner Users
- Calls `checkPartnerFacility(id)` to get only facilities assigned to the partner
- Same past-due filtering applies if the partner has >1 facility

#### Path C: Demo/Customer View Mode
- Applies `shouldShowFacilityInDemo()` which removes `CHURNED` (2) and `DID_NOT_SUBSCRIBE` (7)
- Anonymizes facility names with random city names in demo view

**File**: `apps/frontend/src/contexts/CustomerDetailContext.tsx` (lines 157-168)

```typescript
const maybeAnonymizedFacilityList =
  dv || customerView
    ? facilityList
        .filter(shouldShowFacilityInDemo)
        .map((facility, idx) => ({
          ...facility,
          fn: dv ? randomCityGenerator(idx) : facility.fn,
          cn: dv ? DEMO_CUSTOMER_NAME : facility.cn,
        }))
    : facilityList;
```

The context exposes `maybeAnonymizedFacilityList` as the `facilityList` value, so the FacilitySelection dropdown already receives the filtered/anonymized list.

### 3. Backend Filtering (Stored Procedure)

**File**: `mysql/db/procs/R__PROC_Facility_GetCustomerFacilityList.sql`

```sql
WHERE c.ExternalCustomerID = inExternalCustomerID
    AND f.FacilityStatusID NOT IN(4)
    AND u.CognitoID=inCognitoID
```

- Only excludes `DELETED` (4) — all other statuses (CHURNED, INTERNAL_TESTING, BETA_TESTING, INVENTORY, PENDING_INSTALL, etc.) are returned
- The `Facility_User` join means the user must be explicitly assigned to a facility to see it
- No role-based status filtering at the database level

### 4. Facility Layout Tab - Tab Visibility

**File**: `apps/frontend/src/components/CustomerDetailPage/SideNav.tsx` (lines 108-111)

```typescript
const canViewFacilityLayoutTab =
  !cognitoUserGroup.includes("Customer") &&
  !(cognitoUserGroup.includes("Partner") && !userRole.includes("FST")) &&
  !isDemoView;
```

The Facility Layout tab is **hidden** from:
- All **Customer** users
- **Partner** users who do NOT have the `FST` (Field Service Technician) role
- Users in **Demo View** or **Customer View** mode

It is **visible** to:
- All **NikolaTeam** (internal) users
- **Partner** users who have the `FST` role
- **CME** users (they are not Customers or Partners)

### 5. Facility Status Display in Facility Layout

**File**: `apps/frontend/src/components/CustomerDetailPage/FacilityLayout/HeaderActions.tsx` (line 111)

```typescript
{(isTeamMember || isPartner) && <h6>{`STATUS: ${facility.fsnme}`}</h6>}
```

The facility status name label is only shown to **team members** and **partners**. Other roles (if they could somehow access this tab) would not see the status label.

### 6. Status-Based Feature Restrictions in Facility Layout

**File**: `apps/frontend/src/components/CustomerDetailPage/FacilityLayout/HeaderActions.tsx` (lines 59-71)

```typescript
{facility.fsid !== FacilityStatus.PENDING_INSTALL && (
  <Tooltip label="View Facility Hardware For This Facility">
    <ActionIcon ... component={Link} to={`/facilityhardware?fid=${facility.fid}`} />
  </Tooltip>
)}
```

When a facility has `PENDING_INSTALL` (9) status, the "View Facility Hardware" navigation link is hidden. This is the only status-based UI conditional in the Facility Layout tab's header actions.

### 7. Other Role-Based Controls in Facility Layout

**File**: `apps/frontend/src/components/CustomerDetailPage/FacilityLayout/HeaderActions.tsx`

- **Optimize Sensor Schedule** button: Only visible to `isTeamMember` (line 84)
- **Heartbeat Settings**: Only fetched and displayed for `isEngineering` users (lines 39, 113)

**File**: `apps/frontend/src/components/CustomerDetailPage/FacilityLayout/FacilityLayoutTab.tsx`

- **Sensor Product Filter**: Only visible to `isTeamMember` (line 774)

### 8. Access Revocation Logic

**File**: `apps/frontend/src/pages/CustomerDetail.tsx` (lines 145-166)

Access is fully revoked (`isAccessRevoked = true`) when:
1. A customer has exactly one facility selected AND that facility is past its suspension date
2. A customer has zero facilities in the list but past-due facilities exist (all past due)
3. No facilities are selected at all

When `isAccessRevoked` is true, ALL tab panels (including Facility Layout) return `null`.

### 9. Facility Status Enum

**File**: `apps/frontend/src/shared/enums/FacilityStatus.ts`

24 statuses defined. The statuses relevant to visibility rules:
- `DELETED (4)`: Filtered out at DB level — never shown to anyone
- `CHURNED (2)` and `DID_NOT_SUBSCRIBE (7)`: Filtered out in demo/customer view mode
- `PENDING_INSTALL (9)`: Hides the "View Facility Hardware" link
- All others: No role-based visibility restrictions

## Code References

- `apps/frontend/src/components/CustomerDetailPage/FacilitySelection.tsx` - Facility multi-select dropdown
- `apps/frontend/src/components/CustomerDetailPage/SideNav.tsx:108-111` - Tab visibility rules including `canViewFacilityLayoutTab`
- `apps/frontend/src/pages/CustomerDetail.tsx:145-166` - Access revocation logic
- `apps/frontend/src/pages/CustomerDetail.tsx:304-331` - Past-due facility filtering
- `apps/frontend/src/contexts/CustomerDetailContext.tsx:157-168` - Demo view facility filtering
- `apps/frontend/src/utils/shouldShowInFacilityDemo.ts` - Demo filter (CHURNED, DID_NOT_SUBSCRIBE)
- `apps/frontend/src/components/CustomerDetailPage/FacilityLayout/HeaderActions.tsx:59` - PENDING_INSTALL check
- `apps/frontend/src/components/CustomerDetailPage/FacilityLayout/HeaderActions.tsx:111` - Status label role visibility
- `apps/frontend/src/shared/enums/FacilityStatus.ts` - All 24 facility statuses
- `mysql/db/procs/R__PROC_Facility_GetCustomerFacilityList.sql:33` - DB-level DELETED exclusion

## Architecture Documentation

### Access Control Model

The system uses a layered access control approach:

1. **Database Layer**: `Facility_User` join ensures users only see assigned facilities; `DELETED` always excluded
2. **API Layer**: `checkPartnerFacility` limits partners to their assigned facilities
3. **Frontend - Data Layer**: `filterPastDueAccounts` removes suspended facilities for customers; `shouldShowFacilityInDemo` filters demo view
4. **Frontend - Tab Layer**: `canViewFacilityLayoutTab` hides entire tab based on user group/role
5. **Frontend - Feature Layer**: Individual UI elements hidden by status (PENDING_INSTALL) or role (isTeamMember, isEngineering)

### Key Pattern

The system does NOT use a pattern like "Role X cannot see Status Y facilities." Instead:
- **Entity assignment** controls which facilities appear (Facility_User table)
- **Billing status** (suspension date) controls customer access
- **Tab-level role checks** control which features/views are accessible
- **Individual feature flags** control specific UI elements within tabs

## Open Questions

1. Are there any LaunchDarkly feature flags that conditionally filter facilities by status? (The `ux30FacilitiesEpic` flag controls the new Facilities tab visibility but does not appear related to status filtering)
2. The `checkPartnerFacility` API — does it perform any status-based filtering on the backend? The stored procedure was not examined in this research.
