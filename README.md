# Mass Update Panel — Salesforce LWC

A **reusable Lightning Web Component** that lets users bulk-edit a single field across multiple records from a data table, with a mandatory confirmation step and one-click rollback to the previous values.

---

## Table of Contents

1. [Features](#features)
2. [Architecture](#architecture)
3. [Component Inventory](#component-inventory)
4. [Prerequisites](#prerequisites)
5. [Installation](#installation)
6. [Usage — Quick Start](#usage--quick-start)
7. [Public API Reference](#public-api-reference)
8. [Custom Events](#custom-events)
9. [Supported Field Types](#supported-field-types)
10. [Rollback Behaviour](#rollback-behaviour)
11. [Security Model](#security-model)
12. [Testing](#testing)
13. [Known Limitations](#known-limitations)
14. [Contributing](#contributing)

---

## Features

| # | Feature |
|---|---------|
| 1 | Multi-row selection via `lightning-datatable` checkbox column |
| 2 | Dynamic field-type-aware value input (picklist, number, date, boolean, email, URL, phone, text) |
| 3 | Live preview bar showing field → new value before any DML |
| 4 | 3-step visual progress indicator (Select → Configure → Confirm) |
| 5 | Mandatory confirmation modal before DML executes |
| 6 | Partial-success reporting — failed rows listed with error messages |
| 7 | One-click **rollback** restores pre-update values captured server-side |
| 8 | Inline alert bar + Lightning toast notifications |
| 9 | FLS / CRUD enforced via `Security.stripInaccessible` and field describe checks |
| 10 | Zero external dependencies — pure LWC + Apex + SLDS |

---

## Architecture
<img width="4300" height="3100" alt="Mass-Update-Panel-Architecture" src="https://github.com/user-attachments/assets/2028137a-8919-4cc0-8160-60edd1f21590" />

```

### Data Flow — Update

```
User selects rows
      │
      ▼
User picks field + enters value
      │
      ▼
[Preview bar renders]
      │
      ▼
Click "Apply Update"
      │
      ▼
massUpdateConfirmModal shown (mode=update)
      │  confirm
      ▼
MassUpdateController.massUpdate()
  ├─ captureOriginals()  ──► rollbackSnapshot stored in JS state
  └─ Database.update(allOrNone=false)
      │
      ▼
Result surfaced: success count / failure list / toast
```

### Data Flow — Rollback

```
Click "Rollback Last Update"
      │
      ▼
massUpdateConfirmModal shown (mode=rollback)
      │  confirm
      ▼
MassUpdateController.rollbackUpdate(rollbackSnapshot)
      │
      ▼
Database.update restores original values
      │
      ▼
rollbackSnapshot cleared (single-use)
```

---

## Component Inventory

```
force-app/main/default/
├── lwc/
│   ├── massUpdatePanel/               ← Main reusable component
│   │   ├── massUpdatePanel.html
│   │   ├── massUpdatePanel.js
│   │   ├── massUpdatePanel.css
│   │   └── massUpdatePanel.js-meta.xml
│   │
│   ├── massUpdateConfirmModal/        ← Confirmation / rollback modal
│   │   ├── massUpdateConfirmModal.html
│   │   ├── massUpdateConfirmModal.js
│   │   ├── massUpdateConfirmModal.css
│   │   └── massUpdateConfirmModal.js-meta.xml
│   │
│   └── accountMassUpdatePage/         ← Example host page
│       ├── accountMassUpdatePage.html
│       ├── accountMassUpdatePage.js
│       └── accountMassUpdatePage.js-meta.xml
│
└── classes/
    ├── MassUpdateController.cls
    ├── MassUpdateController.cls-meta.xml
    ├── MassUpdateControllerTest.cls
    └── MassUpdateControllerTest.cls-meta.xml
```

---

## Prerequisites

- Salesforce DX CLI (`sf` or `sfdx`) v2+
- API version 61.0 (Summer '24) or later
- A scratch org or sandbox with LWC enabled
- The running user must have **Read** access on the target object and **Edit** access on the target field

---

## Installation

### Deploy to a scratch org

```bash
# Authenticate
sf org login web --alias my-scratch-org

# Deploy
sf project deploy start --source-dir force-app --target-org my-scratch-org

# Run Apex tests
sf apex run test --test-level RunLocalTests --target-org my-scratch-org --wait 10
```

### Deploy to a sandbox

```bash
sf org login web --alias my-sandbox --instance-url https://test.salesforce.com
sf project deploy start --source-dir force-app --target-org my-sandbox
```

---

## Usage — Quick Start

### 1. Add the component to a Lightning page

Drop `c-mass-update-panel` onto any Lightning App Page, Tab, or Record Page via the Lightning App Builder, or embed it in a parent component.

### 2. Wire in records from the parent

```html
<!-- myPage.html -->
<c-mass-update-panel
    sobject-api-name="Contact"
    records={contacts}
    columns={columns}
    editable-fields={editableFields}
    max-row-selection="300"
    onmassupdate={handleUpdate}
    onrollback={handleRollback}>
</c-mass-update-panel>
```

```js
// myPage.js
import { LightningElement, wire } from 'lwc';
import getRecords from '@salesforce/apex/MassUpdateController.getRecords';

const COLUMNS = [
    { label: 'Name',  fieldName: 'Name',  type: 'text' },
    { label: 'Title', fieldName: 'Title', type: 'text' },
    { label: 'Lead Source', fieldName: 'LeadSource', type: 'text' },
];

const EDITABLE_FIELDS = [
    {
        label          : 'Lead Source',
        apiName        : 'LeadSource',
        type           : 'picklist',
        picklistOptions: [
            { label: 'Web',     value: 'Web'     },
            { label: 'Phone',   value: 'Phone'   },
            { label: 'Partner', value: 'Partner' },
        ],
    },
    { label: 'Title', apiName: 'Title', type: 'text' },
];

export default class MyPage extends LightningElement {
    contacts       = [];
    columns        = COLUMNS;
    editableFields = EDITABLE_FIELDS;

    @wire(getRecords, {
        sobjectApiName: 'Contact',
        fields        : 'Id, Name, Title, LeadSource',
        whereClause   : '',
        maxRows       : 300,
    })
    wired({ data }) { if (data) this.contacts = data; }

    handleUpdate(evt)   { console.log('Updated:', evt.detail.result); }
    handleRollback(evt) { console.log('Rolled back:', evt.detail.result); }
}
```

---

## Public API Reference

### `massUpdatePanel` — `@api` properties

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `sobjectApiName` | `String` | ✅ | — | API name of the target SObject (e.g. `'Account'`) |
| `records` | `Array` | ✅ | `[]` | Array of record objects, each must contain an `Id` field |
| `columns` | `Array` | ✅ | `[]` | `lightning-datatable` column definitions |
| `editableFields` | `Array` | ✅ | `[]` | Field descriptors — see shape below |
| `maxRowSelection` | `Integer` | ❌ | `200` | Max rows a user can select at once |

#### `editableFields` item shape

```js
{
    label          : 'Rating',         // Display label shown in the field selector
    apiName        : 'Rating',         // Salesforce field API name
    type           : 'picklist',       // See Supported Field Types below
    picklistOptions: [                 // Required when type === 'picklist'
        { label: 'Hot',  value: 'Hot'  },
        { label: 'Warm', value: 'Warm' },
    ],
}
```

### `massUpdateConfirmModal` — `@api` properties

| Property | Type | Description |
|---|---|---|
| `selectedCount` | `Integer` | Number of records to be affected |
| `fieldLabel` | `String` | Display label of the field |
| `newValue` | `String` | String representation of the new value |
| `mode` | `String` | `'update'` or `'rollback'` |

---

## Custom Events

Events bubble and compose — a grandparent page can listen to them.

| Event | Fired by | `detail` payload | Description |
|---|---|---|---|
| `massupdate` | `massUpdatePanel` | `{ result: MassUpdateResult }` | Fired after a successful (or partial) mass update DML |
| `rollback` | `massUpdatePanel` | `{ result: MassUpdateResult }` | Fired after a rollback DML completes |
| `confirm` | `massUpdateConfirmModal` | — | User clicked the confirm button |
| `cancel` | `massUpdateConfirmModal` | — | User dismissed the modal |

#### `MassUpdateResult` shape (from Apex)

```js
{
    successCount    : 48,
    failureCount    : 2,
    message         : '48 record(s) updated successfully. 2 failed.',
    failures        : [
        { recordId: '001...', errorMessage: 'FIELD_CUSTOM_VALIDATION_EXCEPTION: ...' }
    ],
    rollbackSnapshot: [
        { recordId: '001...', originalValue: 'Warm' },
        // …one entry per record that was successfully updated
    ]
}
```

---

## Supported Field Types

| `type` value in `editableFields` | Input rendered |
|---|---|
| `text` (default) | `lightning-input` (text) |
| `picklist` / `multipicklist` | `lightning-combobox` |
| `boolean` | `lightning-input` (checkbox) |
| `int` / `double` / `currency` / `percent` | `lightning-input` (number) |
| `date` | `lightning-input` (date) |
| `datetime` | `lightning-input` (datetime) |
| `email` | `lightning-input` (email) |
| `url` | `lightning-input` (url) |
| `phone` | `lightning-input` (tel) |

---

## Rollback Behaviour

- The rollback snapshot is captured **server-side** immediately before the DML, so it reflects the true database state at the time of the update — not a client-side guess.
- The snapshot is held in the LWC component's JS state (not persisted to the database). Refreshing the page discards it.
- Only the **most recent** mass update can be rolled back. Performing a second update overwrites the snapshot.
- If the rollback itself partially fails, the snapshot is **not** cleared so a retry is possible.
- A rollback of a rollback is not supported — the snapshot is cleared on a fully successful rollback.

---

## Security Model

| Layer | Mechanism |
|---|---|
| Object-level | `Schema.SObjectType.getDescribe().isAccessible()` check before every query |
| Field-level (read) | `Security.stripInaccessible(AccessType.READABLE, …)` applied to all `getRecords` results |
| Field-level (write) | `dfr.isUpdateable()` checked before every mass update and rollback |
| SOQL injection | All field and object names escape-sanitised; `whereClause` is a known limitation (see below) |
| Sharing | `with sharing` on the controller class — respects record-level access |

---

## Testing

```bash
# Run all tests with coverage report
sf apex run test \
  --class-names MassUpdateControllerTest \
  --code-coverage \
  --result-format human \
  --target-org my-scratch-org \
  --wait 10
```

### Test coverage

| Scenario | Test method |
|---|---|
| Fetch records — happy path | `testGetRecords_returnsRows` |
| Fetch records — honours maxRows | `testGetRecords_respectsMaxRows` |
| Invalid object throws | `testGetRecords_invalidObject_throws` |
| Mass update — all succeed | `testMassUpdate_success` |
| Mass update — empty IDs throws | `testMassUpdate_emptyIds_throws` |
| Rollback snapshot values | `testMassUpdate_rollbackSnapshotValues` |
| Rollback — restores values | `testRollbackUpdate_restoresValues` |
| Rollback — empty data throws | `testRollbackUpdate_emptyData_throws` |

---

## Known Limitations

1. **`whereClause` injection risk** — the `whereClause` parameter in `getRecords` is passed directly into the SOQL string. The caller is responsible for sanitising it. Do not expose this parameter to untrusted user input.
2. **Rollback is session-scoped** — the snapshot lives in JS memory. A page reload discards it.
3. **Single-field update per operation** — by design. Updating multiple fields in one operation is out of scope for this component.
4. **Picklist options are static** — `picklistOptions` must be supplied by the host page. Dynamic retrieval via `getPicklistValues` from `lightning/ui-object-info-api` can be added in the host page and passed down.
5. **`multipicklist` field writing** — the component renders a single `combobox` for `multipicklist` fields. Multi-select UI support requires a custom input.
6. **No pagination on the datatable** — for very large record sets (> 2000), implement server-side pagination in the host page.

---

## Contributing

1. Fork the repository and create a feature branch.
2. Follow [Salesforce LWC best practices](https://developer.salesforce.com/docs/component-library/documentation/en/lwc/lwc.get_started_introduction).
3. Add or update Apex tests — maintain ≥ 85 % code coverage.
4. Submit a pull request with a clear description of the change.

---

*Built with Salesforce LWC · API v61.0 · SLDS 2.x*
