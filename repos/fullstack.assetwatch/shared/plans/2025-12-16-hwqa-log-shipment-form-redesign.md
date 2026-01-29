# LogShipmentForm Hierarchical Redesign Implementation Plan

## Overview

Redesign LogShipmentForm to support manual shipment entry with a hierarchical data structure matching the actual domain model: one shipment contains multiple boxes, each box contains multiple serial numbers. Uses Mantine Accordion for expandable box rows with real-time serial count badges.

## Current State Analysis

### Existing Components
- **LogShipmentForm** (`features/shipments/LogShipmentForm.tsx`): Excel-only upload with column mapping UI
- **CreateShipmentForm** (`features/shipments/CreateShipmentForm.tsx`): Flat manual entry form (unused, to be absorbed)
- **LogTestForm** (`features/tests/LogTestForm.tsx`): Has serial number parsing pattern to reuse

### Key Discoveries
- Backend endpoints accept arrays of `ImportRow` - one row per box, shipment info repeated
- LogTestForm uses `.slice(-7)` to strip part number prefixes from serials
- Mantine `useForm` supports nested arrays with `insertListItem`/`removeListItem`
- Mantine Accordion supports controlled single-item expansion

## Desired End State

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  SHIPMENT DETAILS (entered once)                                            │
│  [Date Shipped]  [Manufacturer ▼]  [Invoice Number]  [PO Number]            │
├─────────────────────────────────────────────────────────────────────────────┤
│  BOXES                                                        [+ Add Box]   │
│                                                                             │
│ ┌─ ▼ ADL-2024-001 │ Available (New) │ 12/15/2024 ───────────────────[42]─┐ │
│ │  [Box Label *]  [Box Status ▼]  [Date Received]  [Description]         │ │
│ │                                                                         │ │
│ │  Serial Numbers *                                          [42 serials] │ │
│ │  ┌──────────────────────────────────────────────────────────────────┐  │ │
│ │  │ 710-001F:1015535, 1015536, 1015537...                            │  │ │
│ │  └──────────────────────────────────────────────────────────────────┘  │ │
│ │                                                            [🗑 Remove]  │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│ ┌─ ▶ (empty) │ - │ - ───────────────────────────────────────────────[0]─┐ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Cancel]                                              [Create Shipment]    │
│                                                                             │
│  ─────────────────────── OR Upload from Excel ───────────────────────────  │
│                            [Upload Excel File]                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Verification
- Manual entry creates shipments with multiple boxes successfully
- Serial numbers with part prefixes are parsed correctly (`.slice(-7)`)
- Accordion expands one box at a time
- Validation triggers when adding new box or on submit
- Excel upload continues to work exactly as before
- Works for both hub and sensor shipments

## What We're NOT Doing

- No backend changes (existing endpoints work as-is)
- No changes to shipment services or hooks
- No changes to page components (they just pass `deviceType` prop)
- Not implementing "load serials from existing shipment" feature

## Implementation Approach

1. Add `deviceType` prop and fix service selection
2. Create new form state with nested box array using `useForm`
3. Build Accordion-based UI for boxes
4. Implement serial parsing with `.slice(-7)` pattern
5. Add validation on box change and submit
6. Keep Excel upload as secondary option
7. Clean up unused code

---

## Phase 1: Add Device Type Support

### Overview
Add deviceType prop to LogShipmentForm and fix the hardcoded sensor service.

### Changes Required:

#### 1. Update LogShipmentForm Props and Service Selection
**File**: `frontend/src/components/HwqaPage/features/shipments/LogShipmentForm.tsx`

```typescript
// Add import
import { hubShipmentService } from '@components/HwqaPage/services/hubShipmentService';

// Update interface (around line 16)
interface LogShipmentFormProps {
  onSuccess: (data: ShipmentData) => Promise<ImportResult>;
  onCancel: () => void;
  deviceType: 'sensor' | 'hub';
}

// Add helper function
const getShipmentService = (deviceType: 'sensor' | 'hub') =>
  deviceType === 'sensor' ? sensorShipmentService : hubShipmentService;

// Update function signature
export function LogShipmentForm({ onSuccess, onCancel, deviceType }: LogShipmentFormProps) {

// Update validation call (line ~217) to use helper
const validationResponse = await getShipmentService(deviceType).validateShipment({
  data: transformedData
});
```

#### 2. Update SensorShipmentsPage
**File**: `frontend/src/components/HwqaPage/pages/SensorShipmentsPage.tsx`

```typescript
<LogShipmentForm
  onSuccess={handleLogShipment}
  onCancel={() => setApiResult(null)}
  deviceType="sensor"
/>
```

#### 3. Update HubShipmentsPage
**File**: `frontend/src/components/HwqaPage/pages/HubShipmentsPage.tsx`

```typescript
<LogShipmentForm
  onSuccess={handleLogShipment}
  onCancel={() => setApiResult(null)}
  deviceType="hub"
/>
```

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles: `cd frontend && npx tsc --noEmit 2>&1 | grep -i "LogShipmentForm\|ShipmentsPage"`
- [x] Lint passes: `cd frontend && npm run lint -- --quiet`

#### Manual Verification:
- [ ] Both shipment pages load without errors
- [ ] Excel upload still works on both pages

---

## Phase 2: Create Hierarchical Form State

### Overview
Replace flat form state with nested structure: shipment fields + array of boxes.

### Changes Required:

#### 1. Add New Imports and Types
**File**: `frontend/src/components/HwqaPage/features/shipments/LogShipmentForm.tsx`

```typescript
import { useForm } from '@mantine/form';
import { randomId } from '@mantine/hooks';
import {
  TextInput,
  Textarea,
  Select,
  Button,
  Group,
  Stack,
  Text,
  Badge,
  Box,
  Paper,
  Accordion,
  ActionIcon,
  Tooltip
} from '@mantine/core';
import { DatePickerInput } from '@mantine/dates';
import { DateTime } from 'luxon';
import { getJsDate } from '@components/Utilities';
import { faTrash, faPlus } from '@fortawesome/pro-solid-svg-icons';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { useState, useEffect, useMemo } from 'react';
```

#### 2. Define Form Types and Initial State
**File**: `frontend/src/components/HwqaPage/features/shipments/LogShipmentForm.tsx`

```typescript
interface BoxFormValues {
  key: string;  // Unique key for React
  boxLabel: string;
  boxStatus: string;
  dateReceived: Date | null;
  description: string;
  serialNumbers: string;
}

interface ShipmentFormValues {
  dateShipped: Date | null;
  manufacturer: string;
  invoiceNumber: string;
  poNumber: string;
  boxes: BoxFormValues[];
}

const createEmptyBox = (): BoxFormValues => ({
  key: randomId(),
  boxLabel: '',
  boxStatus: '',
  dateReceived: null,
  description: '',
  serialNumbers: '',
});

const boxStatusOptions = [
  { value: 'Available (New)', label: 'Available (New)' },
  { value: 'Available (Open)', label: 'Available (Open)' },
  { value: 'Consumed', label: 'Consumed' },
  { value: 'ENG-IQA', label: 'ENG-IQA' },
  { value: 'RMA-COAX', label: 'RMA-COAX' },
  { value: 'SC-OQA', label: 'SC-OQA' }
];

const manufacturerOptions = [
  { value: 'ADL', label: 'ADL' },
  { value: 'COAX', label: 'COAX' }
];
```

#### 3. Initialize Form with useForm Hook
**File**: `frontend/src/components/HwqaPage/features/shipments/LogShipmentForm.tsx`

Inside the component function:

```typescript
// Mode state: 'manual' or 'excel'
const [mode, setMode] = useState<'manual' | 'excel'>('manual');

// Accordion state: which box is expanded (by key)
const [expandedBox, setExpandedBox] = useState<string | null>(null);

// Form state with nested boxes array
const form = useForm<ShipmentFormValues>({
  initialValues: {
    dateShipped: null,
    manufacturer: '',
    invoiceNumber: '',
    poNumber: '',
    boxes: [createEmptyBox()],
  },
  validate: {
    dateShipped: (value) => (!value ? 'Date Shipped is required' : null),
    manufacturer: (value) => (!value ? 'Manufacturer is required' : null),
    invoiceNumber: (value) => (!value ? 'Invoice Number is required' : null),
    poNumber: (value) => (!value ? 'PO Number is required' : null),
  },
});

// Expand the first box by default
useEffect(() => {
  if (form.values.boxes.length > 0 && !expandedBox) {
    setExpandedBox(form.values.boxes[0].key);
  }
}, []);
```

#### 4. Add Serial Count Calculator
**File**: `frontend/src/components/HwqaPage/features/shipments/LogShipmentForm.tsx`

```typescript
// Calculate serial count for a box (memoized per box)
const getSerialCount = (serialNumbers: string): number => {
  if (!serialNumbers.trim()) return 0;
  return serialNumbers
    .split(/[\s,\n]+/)
    .map((s) => s.trim())
    .filter((s) => s.length >= 7)
    .length;
};

// Parse and dedupe serials (same logic as LogTestForm)
const parseSerials = (serialNumbers: string): string[] => {
  return serialNumbers
    .split(/[\s,\n]+/)
    .map((s) => s.trim())
    .filter((s) => s.length >= 7)
    .map((s) => s.slice(-7))  // Strip part number prefix
    .filter((s, i, arr) => arr.indexOf(s) === i);  // Dedupe
};
```

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles without errors (unused variable warnings expected - will be used in Phase 3)
- [x] No unused variable warnings

#### Manual Verification:
- [ ] Component renders (state added but UI not yet implemented)

---

## Phase 3: Build Accordion UI for Boxes

### Overview
Implement the visual layout with Accordion for expandable box rows.

### Changes Required:

#### 1. Update CSS Module
**File**: `frontend/src/components/HwqaPage/features/shipments/LogShipmentForm.module.css`

Add new styles:

```css
.root {
  position: relative;
}

.shipmentSection {
  margin-bottom: var(--mantine-spacing-lg);
  padding-bottom: var(--mantine-spacing-lg);
  border-bottom: 1px solid var(--mantine-color-neutral80);
}

.shipmentFields {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: var(--mantine-spacing-md);
}

@media (max-width: 900px) {
  .shipmentFields {
    grid-template-columns: repeat(2, 1fr);
  }
}

.boxesHeader {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: var(--mantine-spacing-md);
}

.accordionControl {
  padding: var(--mantine-spacing-sm) var(--mantine-spacing-md);
}

.accordionControlInner {
  display: flex;
  align-items: center;
  gap: var(--mantine-spacing-md);
  width: 100%;
}

.boxSummary {
  display: flex;
  align-items: center;
  gap: var(--mantine-spacing-lg);
  flex: 1;
}

.boxSummaryItem {
  color: var(--mantine-color-neutral40);
  font-size: var(--mantine-font-size-sm);
}

.boxSummaryItem.hasValue {
  color: var(--mantine-color-neutral20);
}

.boxSummaryDivider {
  color: var(--mantine-color-neutral70);
}

.serialBadge {
  margin-left: auto;
}

.boxPanel {
  padding: var(--mantine-spacing-md);
  background-color: var(--mantine-color-neutral98);
}

.boxFields {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: var(--mantine-spacing-md);
  margin-bottom: var(--mantine-spacing-md);
}

@media (max-width: 900px) {
  .boxFields {
    grid-template-columns: repeat(2, 1fr);
  }
}

.serialSection {
  margin-top: var(--mantine-spacing-md);
}

.serialHeader {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: var(--mantine-spacing-xs);
}

.serialInput textarea {
  resize: vertical;
  min-height: 120px !important;
  font-family: var(--mantine-font-family-monospace);
  background-image: linear-gradient(135deg,
    transparent 0%,
    transparent 75%,
    var(--mantine-color-neutral90) 75%,
    var(--mantine-color-neutral90) 100%
  );
  background-size: 10px 10px;
  background-repeat: no-repeat;
  background-position: right bottom;
}

.boxActions {
  display: flex;
  justify-content: flex-end;
  margin-top: var(--mantine-spacing-md);
  padding-top: var(--mantine-spacing-md);
  border-top: 1px solid var(--mantine-color-neutral90);
}

.formActions {
  display: flex;
  gap: var(--mantine-spacing-md);
  margin-top: var(--mantine-spacing-xl);
}

.uploadSection {
  margin-top: var(--mantine-spacing-xl);
  padding-top: var(--mantine-spacing-lg);
  border-top: 1px solid var(--mantine-color-neutral80);
}

.uploadDivider {
  display: flex;
  align-items: center;
  gap: var(--mantine-spacing-md);
  margin-bottom: var(--mantine-spacing-md);
  color: var(--mantine-color-neutral50);
  font-size: var(--mantine-font-size-sm);
}

.uploadDivider::before,
.uploadDivider::after {
  content: '';
  flex: 1;
  height: 1px;
  background-color: var(--mantine-color-neutral80);
}
```

#### 2. Implement JSX Layout
**File**: `frontend/src/components/HwqaPage/features/shipments/LogShipmentForm.tsx`

Replace the return statement:

```tsx
return (
  <Paper p="md" className={classes.root}>
    {mode === 'manual' ? (
      <form onSubmit={handleManualSubmit}>
        {/* Shipment Details Section */}
        <Box className={classes.shipmentSection}>
          <Text fw={600} size="sm" mb="md">Shipment Details</Text>
          <div className={classes.shipmentFields}>
            <DatePickerInput
              label="Date Shipped *"
              placeholder="Select date"
              value={form.values.dateShipped}
              onChange={(date) => form.setFieldValue('dateShipped', date ? getJsDate(date) : null)}
              error={form.errors.dateShipped}
              clearable
              data-testid="hwqa-shipment-date-shipped"
            />
            <Select
              label="Manufacturer *"
              placeholder="Select"
              data={manufacturerOptions}
              {...form.getInputProps('manufacturer')}
              clearable
              data-testid="hwqa-shipment-manufacturer"
            />
            <TextInput
              label="Invoice Number *"
              placeholder="Enter invoice"
              {...form.getInputProps('invoiceNumber')}
              data-testid="hwqa-shipment-invoice"
            />
            <TextInput
              label="PO Number *"
              placeholder="Enter PO"
              {...form.getInputProps('poNumber')}
              data-testid="hwqa-shipment-po"
            />
          </div>
        </Box>

        {/* Boxes Section */}
        <Box>
          <div className={classes.boxesHeader}>
            <Text fw={600} size="sm">Boxes</Text>
            <Button
              variant="light"
              size="xs"
              leftSection={<FontAwesomeIcon icon={faPlus} size="sm" />}
              onClick={handleAddBox}
            >
              Add Box
            </Button>
          </div>

          <Accordion
            value={expandedBox}
            onChange={setExpandedBox}
            variant="separated"
          >
            {form.values.boxes.map((box, index) => (
              <Accordion.Item key={box.key} value={box.key}>
                <Accordion.Control className={classes.accordionControl}>
                  <div className={classes.accordionControlInner}>
                    <div className={classes.boxSummary}>
                      <span className={`${classes.boxSummaryItem} ${box.boxLabel ? classes.hasValue : ''}`}>
                        {box.boxLabel || '(no label)'}
                      </span>
                      <span className={classes.boxSummaryDivider}>│</span>
                      <span className={`${classes.boxSummaryItem} ${box.boxStatus ? classes.hasValue : ''}`}>
                        {box.boxStatus || '-'}
                      </span>
                      <span className={classes.boxSummaryDivider}>│</span>
                      <span className={`${classes.boxSummaryItem} ${box.dateReceived ? classes.hasValue : ''}`}>
                        {box.dateReceived ? DateTime.fromJSDate(box.dateReceived).toFormat('MM/dd/yyyy') : '-'}
                      </span>
                    </div>
                    <Badge
                      size="lg"
                      color={getSerialCount(box.serialNumbers) > 0 ? 'tertiary60' : 'neutral60'}
                      className={classes.serialBadge}
                    >
                      {getSerialCount(box.serialNumbers)}
                    </Badge>
                  </div>
                </Accordion.Control>

                <Accordion.Panel className={classes.boxPanel}>
                  <div className={classes.boxFields}>
                    <TextInput
                      label="Box Label *"
                      placeholder="Enter box label"
                      {...form.getInputProps(`boxes.${index}.boxLabel`)}
                      data-testid={`hwqa-box-${index}-label`}
                    />
                    <Select
                      label="Box Status *"
                      placeholder="Select status"
                      data={boxStatusOptions}
                      {...form.getInputProps(`boxes.${index}.boxStatus`)}
                      clearable
                      data-testid={`hwqa-box-${index}-status`}
                    />
                    <DatePickerInput
                      label="Date Received *"
                      placeholder="Select date"
                      value={form.values.boxes[index].dateReceived}
                      onChange={(date) => form.setFieldValue(`boxes.${index}.dateReceived`, date ? getJsDate(date) : null)}
                      clearable
                      data-testid={`hwqa-box-${index}-date-received`}
                    />
                    <TextInput
                      label="Description"
                      placeholder="Optional"
                      {...form.getInputProps(`boxes.${index}.description`)}
                      data-testid={`hwqa-box-${index}-description`}
                    />
                  </div>

                  <div className={classes.serialSection}>
                    <div className={classes.serialHeader}>
                      <Text size="sm" fw={500}>Serial Numbers *</Text>
                      <Badge size="md" color={getSerialCount(box.serialNumbers) > 0 ? 'tertiary60' : 'neutral60'}>
                        {getSerialCount(box.serialNumbers)} serial{getSerialCount(box.serialNumbers) !== 1 ? 's' : ''}
                      </Badge>
                    </div>
                    <Textarea
                      placeholder="Enter serial numbers (comma, space, or newline separated). Part number prefixes like '710-001F:' will be automatically stripped."
                      className={classes.serialInput}
                      minRows={4}
                      {...form.getInputProps(`boxes.${index}.serialNumbers`)}
                      data-testid={`hwqa-box-${index}-serials`}
                    />
                  </div>

                  {form.values.boxes.length > 1 && (
                    <div className={classes.boxActions}>
                      <Tooltip label="Remove this box">
                        <ActionIcon
                          variant="subtle"
                          color="red"
                          onClick={() => handleRemoveBox(index)}
                          data-testid={`hwqa-box-${index}-remove`}
                        >
                          <FontAwesomeIcon icon={faTrash} />
                        </ActionIcon>
                      </Tooltip>
                    </div>
                  )}
                </Accordion.Panel>
              </Accordion.Item>
            ))}
          </Accordion>
        </Box>

        {/* Form Actions */}
        <Group className={classes.formActions}>
          <Button variant="default" onClick={handleCancel}>
            Cancel
          </Button>
          <Button type="submit" loading={isProcessing}>
            Create Shipment
          </Button>
        </Group>

        {/* Excel Upload Section */}
        <Box className={classes.uploadSection}>
          <div className={classes.uploadDivider}>
            OR Upload from Excel
          </div>
          <FileButton onChange={handleSwitchToExcelMode} accept=".xlsx,.xls">
            {(props) => (
              <Button {...props} variant="default" data-testid="hwqa-log-shipment-upload">
                Upload Excel File
              </Button>
            )}
          </FileButton>
        </Box>
      </form>
    ) : (
      /* Excel Mode - Keep existing implementation */
      <>
        <Group mb="md">
          <Button variant="subtle" onClick={() => setMode('manual')}>
            ← Back to Manual Entry
          </Button>
        </Group>
        {/* ... existing Excel upload UI (headers, columnMapping, previewData, etc.) ... */}
      </>
    )}
  </Paper>
);
```

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles without errors (parseSerials unused warning will be resolved in Phase 4)
- [x] Lint passes

#### Manual Verification:
- [ ] Accordion renders with one box expanded
- [ ] Box fields display correctly in expanded state
- [ ] Collapsed boxes show summary (label, status, date, count)
- [ ] Serial count badge updates when typing

---

## Phase 4: Implement Form Handlers and Validation

### Overview
Add handlers for adding/removing boxes, validation, and form submission.

### Changes Required:

#### 1. Add Box Management Handlers
**File**: `frontend/src/components/HwqaPage/features/shipments/LogShipmentForm.tsx`

```typescript
// Validate a single box
const validateBox = (box: BoxFormValues, index: number): Record<string, string> => {
  const errors: Record<string, string> = {};

  if (!box.boxLabel.trim()) {
    errors[`boxes.${index}.boxLabel`] = 'Box Label is required';
  }
  if (!box.boxStatus) {
    errors[`boxes.${index}.boxStatus`] = 'Box Status is required';
  }
  if (!box.dateReceived) {
    errors[`boxes.${index}.dateReceived`] = 'Date Received is required';
  }
  if (!box.serialNumbers.trim()) {
    errors[`boxes.${index}.serialNumbers`] = 'Serial Numbers are required';
  } else {
    const serials = parseSerials(box.serialNumbers);
    if (serials.length === 0) {
      errors[`boxes.${index}.serialNumbers`] = 'Enter at least one valid serial number (7+ characters)';
    }
  }

  return errors;
};

// Handle adding a new box
const handleAddBox = () => {
  // Validate the currently expanded box first
  if (expandedBox) {
    const currentIndex = form.values.boxes.findIndex(b => b.key === expandedBox);
    if (currentIndex !== -1) {
      const currentBox = form.values.boxes[currentIndex];
      const errors = validateBox(currentBox, currentIndex);

      if (Object.keys(errors).length > 0) {
        form.setErrors(errors);
        toast.error('Please complete the current box before adding another');
        return;
      }
    }
  }

  // Add new box and expand it
  const newBox = createEmptyBox();
  form.insertListItem('boxes', newBox);
  setExpandedBox(newBox.key);
};

// Handle removing a box
const handleRemoveBox = (index: number) => {
  const boxToRemove = form.values.boxes[index];
  const hasData = boxToRemove.boxLabel || boxToRemove.serialNumbers;

  if (hasData) {
    // Could add confirmation modal here if desired
    const confirmed = window.confirm('Remove this box and its serial numbers?');
    if (!confirmed) return;
  }

  form.removeListItem('boxes', index);

  // If we removed the expanded box, expand the first remaining box
  if (boxToRemove.key === expandedBox && form.values.boxes.length > 1) {
    const remainingBoxes = form.values.boxes.filter((_, i) => i !== index);
    setExpandedBox(remainingBoxes[0]?.key || null);
  }
};

// Handle cancel
const handleCancel = () => {
  form.reset();
  setExpandedBox(form.values.boxes[0]?.key || null);
  onCancel();
};

// Handle switching to Excel mode
const handleSwitchToExcelMode = async (file: File | null) => {
  if (!file) return;
  setMode('excel');
  await handleFileUpload(file);  // existing function
};
```

#### 2. Add Form Submission Handler
**File**: `frontend/src/components/HwqaPage/features/shipments/LogShipmentForm.tsx`

```typescript
// Format date to YYYY-MM-DD
const formatDate = (date: Date | null): string => {
  if (!date) return '';
  try {
    const dt = DateTime.fromJSDate(date);
    if (!dt.isValid) return '';
    return dt.toFormat('yyyy-MM-dd');
  } catch {
    return '';
  }
};

// Handle manual form submission
const handleManualSubmit = async (e: React.FormEvent) => {
  e.preventDefault();

  // Validate shipment-level fields
  const shipmentValidation = form.validate();
  if (shipmentValidation.hasErrors) {
    toast.error('Please fill in all required shipment fields');
    return;
  }

  // Validate all boxes
  let allErrors: Record<string, string> = {};
  form.values.boxes.forEach((box, index) => {
    const boxErrors = validateBox(box, index);
    allErrors = { ...allErrors, ...boxErrors };
  });

  if (Object.keys(allErrors).length > 0) {
    form.setErrors(allErrors);
    // Expand the first box with errors
    const firstErrorKey = Object.keys(allErrors)[0];
    const match = firstErrorKey.match(/boxes\.(\d+)\./);
    if (match) {
      const errorBoxIndex = parseInt(match[1]);
      setExpandedBox(form.values.boxes[errorBoxIndex]?.key || null);
    }
    toast.error('Please complete all required box fields');
    return;
  }

  setIsProcessing(true);

  try {
    // Transform to ImportRow[] format (one row per box, shipment info repeated)
    const importRows: ImportRow[] = form.values.boxes.map((box) => ({
      dateShipped: formatDate(form.values.dateShipped),
      dateReceived: formatDate(box.dateReceived),
      manufacturer: form.values.manufacturer,
      boxStatus: box.boxStatus,
      boxLabel: box.boxLabel,
      serialNumbersCSV: parseSerials(box.serialNumbers).join(','),
      description: box.description,
      invoiceNumber: form.values.invoiceNumber,
      poNumber: form.values.poNumber,
    }));

    // Validate with backend
    const validationResponse = await getShipmentService(deviceType).validateShipment({
      data: importRows
    });

    if (!validationResponse.valid) {
      throw new Error(`Validation failed: ${validationResponse.errors} errors found`);
    }

    // Import
    const result = await onSuccess({ data: importRows });

    const totalSerials = form.values.boxes.reduce(
      (sum, box) => sum + parseSerials(box.serialNumbers).length,
      0
    );

    toast.success(
      `Created shipment with ${form.values.boxes.length} box${form.values.boxes.length !== 1 ? 'es' : ''} ` +
      `and ${totalSerials} serial${totalSerials !== 1 ? 's' : ''}`
    );

    // Reset form
    form.reset();
    form.setFieldValue('boxes', [createEmptyBox()]);
    setExpandedBox(null);
    setTimeout(() => {
      setExpandedBox(form.values.boxes[0]?.key || null);
    }, 0);

  } catch (error) {
    console.error('Manual entry error:', error);
    toast.error(error instanceof Error ? error.message : 'Failed to create shipment');
  } finally {
    setIsProcessing(false);
  }
};
```

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles without errors
- [x] Lint passes

#### Manual Verification:
- [ ] "Add Box" validates current box before adding
- [ ] "Add Box" creates new accordion item and expands it
- [ ] Remove box works (with confirmation if data entered)
- [ ] Submit validates all fields
- [ ] Submit transforms data correctly and calls API
- [ ] Success message shows box and serial counts
- [ ] Form resets after successful submission

---

## Phase 5: Preserve Excel Upload Mode

### Overview
Ensure the existing Excel upload functionality is preserved in the `mode === 'excel'` branch.

### Changes Required:

#### 1. Keep Existing Excel State and Functions
**File**: `frontend/src/components/HwqaPage/features/shipments/LogShipmentForm.tsx`

Ensure these existing pieces remain:
- `headers`, `setHeaders` state
- `columnMapping`, `setColumnMapping` state
- `previewData`, `setPreviewData` state
- `handleFileUpload` function
- `handleImport` function (update to use `getShipmentService(deviceType)`)
- `previewColumns` definition
- Column mapping UI with `ExpandableSection`
- Preview `DataTable`

#### 2. Update Excel Import to Use Device Service
```typescript
// In handleImport function, update the validation call:
const validationResponse = await getShipmentService(deviceType).validateShipment({
  data: transformedData
});
```

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles without errors

#### Manual Verification:
- [ ] Excel upload still works from the "Upload Excel File" button
- [ ] "Back to Manual Entry" returns to manual mode
- [ ] Column mapping works correctly
- [ ] Import processes Excel data correctly

---

## Phase 6: Cleanup

### Overview
Remove unused code and files.

### Changes Required:

#### 1. Delete CreateShipmentForm Files
```bash
rm frontend/src/components/HwqaPage/features/shipments/CreateShipmentForm.tsx
rm frontend/src/components/HwqaPage/features/shipments/CreateShipmentForm.module.css
```

#### 2. Clean Up Index Exports
**File**: `frontend/src/components/HwqaPage/features/shipments/index.ts`

Remove commented line:
```typescript
// export { CreateShipmentForm } from './CreateShipmentForm';
```

#### 3. Remove Dev Feature Flags
**Files**: `SensorShipmentsPage.tsx` and `HubShipmentsPage.tsx`

Remove:
- `SHOW_DEV_FEATURES` constant
- `importMethod` state
- Dev features Paper section with buttons

#### 4. Delete PasteShipmentForm (Also Unused)
```bash
rm frontend/src/components/HwqaPage/features/shipments/PasteShipmentForm.tsx
rm frontend/src/components/HwqaPage/features/shipments/PasteShipmentForm.module.css
```

Remove from index.ts:
```typescript
// export { PasteShipmentForm } from './PasteShipmentForm';
```

### Success Criteria:

#### Automated Verification:
- [x] TypeScript compiles without errors
- [x] No orphaned imports: `grep -r "CreateShipmentForm\|PasteShipmentForm\|SHOW_DEV_FEATURES" frontend/src/` (only README.md mentions old forms)
- [x] Lint passes

#### Manual Verification:
- [ ] Application builds successfully
- [ ] Both shipment pages function correctly

---

## Testing Strategy

### Unit Tests
- Form validation rejects empty required fields
- `parseSerials()` correctly strips part prefixes with `.slice(-7)`
- `getSerialCount()` returns correct counts
- Box add/remove maintains correct state

### Integration Tests
- Manual entry with single box
- Manual entry with multiple boxes
- Validation errors show correctly
- Excel upload still works
- Mode switching works

### Manual Testing Steps
1. Navigate to Sensor Shipments page
2. Fill shipment details (date, manufacturer, invoice, PO)
3. Fill first box (label, status, date received)
4. Enter serials with part prefixes: `710-001F:1015535, 710-001F:1015536`
5. Verify serial count badge shows correct count
6. Click "Add Box" - verify validation, new box appears expanded
7. Fill second box with different serials
8. Submit and verify success message with correct counts
9. Verify shipment appears in list
10. Test same flow on Hub Shipments page
11. Test Excel upload path still works

## Performance Considerations

- Serial count calculation is O(n) per keystroke - acceptable for typical serial counts
- Could memoize if performance issues arise with very large serial lists

## Migration Notes

- CreateShipmentForm and PasteShipmentForm deleted
- Users see new hierarchical UI immediately
- No database or API changes required

## References

- LogTestForm serial parsing: `features/tests/LogTestForm.tsx:197-202`
- Mantine useForm nested arrays: https://mantine.dev/form/nested/
- Mantine Accordion: https://mantine.dev/core/accordion/
- Backend validation: `lambdas/lf-vero-prod-hwqa/app/routes/sensor_shipment_routes.py:17`
