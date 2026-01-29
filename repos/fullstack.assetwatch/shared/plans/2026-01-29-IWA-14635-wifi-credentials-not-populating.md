---
date: 2026-01-29
researcher: Claude
git_commit: cd7e75fa3b0bf5efd82851c83f92f90d706b047d
branch: dev
repository: fullstack.assetwatch
ticket: IWA-14635
status: draft
last_updated: 2026-01-29
last_updated_by: Claude
type: implementation_plan
---

# IWA-14635: Fix Wi-Fi Credentials Not Populating on Edit Facility Modal

## Overview

Wi-Fi credentials (Primary SSID and Primary Passcode) are not appearing in the "Edit Facility" modal on the Facility Layout page. The backend API returns the data correctly, but the frontend form fields don't display the values. This is a frontend-only bug affecting all facilities.

## Current State Analysis

### The Bug

The `WifiPasscodeForm.tsx` component uses **uncontrolled inputs** via `react-hook-form`'s `register()` function for the Primary SSID and Primary Passcode fields. When the form is initialized and then `reset()` is called asynchronously after Wi-Fi credentials are fetched, the uncontrolled inputs don't automatically sync their displayed values with the form state.

### Key Discoveries:

1. **Backend works correctly**: `lambdas/lf-vero-prod-facilities/main.py:725-775` - The `getFacilityWifiTemp` method properly returns Wi-Fi credentials from the database.

2. **Data flow issue in frontend**: `frontend/src/components/CustomerDetailPage/FacilityLayout/Facility/UpdateFacility.tsx:175-238` - The `useEffect` fetches credentials asynchronously and calls `reset()` to populate the form, but uncontrolled inputs don't reflect the update.

3. **Inconsistent form field patterns**:
   - `FacilityForm.tsx:150-164` uses `Controller` with explicit `value={field.value}` binding (WORKS)
   - `WifiPasscodeForm.tsx:99-113` uses `register()` directly (BROKEN)

4. **The radio buttons work**: `WifiPasscodeForm.tsx:55-97` - The `customerOwnWifi` and `hasWifiMeshDevices` fields use `Controller` and populate correctly.

### Root Cause

In `react-hook-form`, when using `register()` on inputs:
- The initial value comes from `defaultValues` at form creation time
- Calling `reset()` updates the internal form state
- **BUT** uncontrolled inputs with `register()` don't automatically re-render with new values because they rely on `defaultValue` which is only read once at mount

The fix is to convert the SSID and Passcode fields from uncontrolled (`register()`) to controlled (`Controller`) pattern, matching the approach used for other fields.

## Desired End State

After this fix is implemented:
1. When editing any facility, the Wi-Fi tab should display the existing Primary SSID and Primary Passcode values
2. The "Customer using their own WIFI?" and "Customer has WIFI mesh devices?" radio buttons should continue to work correctly
3. Saving changes to Wi-Fi credentials should continue to work correctly
4. The fix should follow the established pattern used in `FacilityForm.tsx`

### Verification:
- Open Edit Facility modal for any existing facility with Wi-Fi credentials
- Navigate to the WiFi tab
- Primary SSID and Primary Passcode fields should show the existing values
- Changes can be made and saved successfully

## What We're NOT Doing

- NOT changing the backend API
- NOT modifying the data structure
- NOT adding new features
- NOT refactoring unrelated code
- NOT changing the form validation logic
- NOT modifying how credentials are saved

## Implementation Approach

Convert the `TextInput` (Primary SSID) and `PasswordInput` (Primary Passcode) fields in `WifiPasscodeForm.tsx` from uncontrolled inputs using `register()` to controlled inputs using `Controller`, matching the pattern used throughout `FacilityForm.tsx`.

## Phase 1: Fix Wi-Fi Form Fields

### Overview

Convert Primary SSID and Primary Passcode fields from uncontrolled to controlled inputs.

### Changes Required:

#### 1. Update WifiPasscodeForm.tsx

**File**: `frontend/src/components/CustomerDetailPage/FacilityLayout/Facility/WifiPasscodeForm.tsx`

**Change 1**: Remove `registerFormField` from props since it won't be needed anymore

```typescript
// BEFORE (lines 38-39):
  registerFormField: UseFormRegister<FacilityFormValues>;
  watch: UseFormWatch<FacilityFormValues>;

// AFTER:
  watch: UseFormWatch<FacilityFormValues>;
```

Also remove `UseFormRegister` from the import on line 21.

**Change 2**: Convert Primary SSID TextInput to use Controller (lines 99-105)

```typescript
// BEFORE:
      <TextInput
        data-testid="primary-ssid"
        label="Primary SSID"
        mt="md"
        error={errors.primarySSID?.message}
        {...registerFormField("primarySSID")}
      />

// AFTER:
      <Controller
        name="primarySSID"
        control={control}
        render={({ field }) => (
          <TextInput
            data-testid="primary-ssid"
            label="Primary SSID"
            mt="md"
            error={errors.primarySSID?.message}
            value={field.value || ""}
            onChange={field.onChange}
            onBlur={field.onBlur}
          />
        )}
      />
```

**Change 3**: Convert Primary Passcode PasswordInput to use Controller (lines 107-113)

```typescript
// BEFORE:
      <PasswordInput
        autoComplete="new-password"
        data-testid="primary-passcode"
        label="Primary Passcode"
        error={errors.primaryPasscode?.message}
        {...registerFormField("primaryPasscode")}
      />

// AFTER:
      <Controller
        name="primaryPasscode"
        control={control}
        render={({ field }) => (
          <PasswordInput
            autoComplete="new-password"
            data-testid="primary-passcode"
            label="Primary Passcode"
            mt="md"
            error={errors.primaryPasscode?.message}
            value={field.value || ""}
            onChange={field.onChange}
            onBlur={field.onBlur}
          />
        )}
      />
```

#### 2. Update UpdateFacility.tsx to remove unused register prop

**File**: `frontend/src/components/CustomerDetailPage/FacilityLayout/Facility/UpdateFacility.tsx`

**Change**: Remove `registerFormField={register}` prop from WifiPasscodeForm (line 888)

```typescript
// BEFORE (lines 884-892):
                <WifiPasscodeForm
                  control={control}
                  customerOwnWifi={watchedValues.customerOwnWifi}
                  extfid={facility?.extfid}
                  registerFormField={register}
                  watch={watch}
                  setValue={setValue}
                  errors={errors}
                />

// AFTER:
                <WifiPasscodeForm
                  control={control}
                  customerOwnWifi={watchedValues.customerOwnWifi}
                  extfid={facility?.extfid}
                  watch={watch}
                  setValue={setValue}
                  errors={errors}
                />
```

### Success Criteria:

#### Automated Verification:

- [ ] Type checking passes: `make -C frontend check`
- [ ] Linting passes: `make -C frontend check`
- [ ] Unit tests pass: `cd frontend && npm test -- --run`
- [ ] Build succeeds: `make -C frontend build`

#### Manual Verification:

- [ ] Open Edit Facility modal for a facility with existing Wi-Fi credentials
- [ ] Navigate to WiFi tab
- [ ] Primary SSID field displays the existing value
- [ ] Primary Passcode field displays the existing value (masked)
- [ ] "Customer using their own WIFI?" radio shows correct selection
- [ ] "Customer has WIFI mesh devices?" radio shows correct selection
- [ ] Can modify and save Wi-Fi credentials successfully
- [ ] Generate New Primary Passcode button still works
- [ ] Show History button still works

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before considering the bug fixed.

---

## Testing Strategy

### Unit Tests:

The existing form and component tests should continue to pass. No new unit tests are strictly required since we're fixing a bug by aligning with an existing pattern.

### Integration Tests:

- Existing facility form tests should validate that form fields can be populated and submitted

### Manual Testing Steps:

1. Navigate to any customer's Facility Layout page
2. Click "Edit" on an existing facility with Wi-Fi credentials
3. Go to the "WiFi" tab
4. Verify Primary SSID shows the existing value
5. Verify Primary Passcode shows the existing value (masked with dots)
6. Verify radio buttons show correct selections
7. Modify the SSID and save - verify it persists
8. Test the "Generate New Primary Passcode" button
9. Test the "Show History" button opens the history modal

## Performance Considerations

None - this is a simple pattern change from uncontrolled to controlled inputs with no performance implications.

## Migration Notes

No migration required - this is a pure frontend bug fix.

## References

- Original ticket: https://nikolalabs.atlassian.net/browse/IWA-14635
- Related pattern in FacilityForm: `frontend/src/components/CustomerDetailPage/FacilityLayout/Facility/FacilityForm.tsx:150-164`
- React Hook Form documentation on Controller vs register: https://react-hook-form.com/docs/usecontroller/controller
