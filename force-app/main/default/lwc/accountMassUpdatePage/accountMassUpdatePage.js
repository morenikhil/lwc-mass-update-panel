import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRecords from '@salesforce/apex/MassUpdateController.getRecords';

const COLUMNS = [
    { label: 'Account Name', fieldName: 'Name',            type: 'text'   },
    { label: 'Rating',       fieldName: 'Rating',           type: 'text'   },
    { label: 'Industry',     fieldName: 'Industry',         type: 'text'   },
    { label: 'Annual Revenue', fieldName: 'AnnualRevenue',  type: 'currency', typeAttributes: { currencyCode: 'USD' } },
    { label: 'Owner',        fieldName: 'Owner.Name',       type: 'text'   },
];

const EDITABLE_FIELDS = [
    {
        label          : 'Rating',
        apiName        : 'Rating',
        type           : 'picklist',
        picklistOptions: [
            { label: 'Hot',  value: 'Hot'  },
            { label: 'Warm', value: 'Warm' },
            { label: 'Cold', value: 'Cold' },
        ],
    },
    {
        label  : 'Industry',
        apiName: 'Industry',
        type   : 'picklist',
        picklistOptions: [
            { label: 'Technology',    value: 'Technology'    },
            { label: 'Finance',       value: 'Finance'       },
            { label: 'Healthcare',    value: 'Healthcare'    },
            { label: 'Retail',        value: 'Retail'        },
            { label: 'Manufacturing', value: 'Manufacturing' },
        ],
    },
    {
        label  : 'Annual Revenue',
        apiName: 'AnnualRevenue',
        type   : 'currency',
    },
    {
        label  : 'Description',
        apiName: 'Description',
        type   : 'text',
    },
];

export default class AccountMassUpdatePage extends LightningElement {

    accounts   = [];
    isLoading  = true;
    error      = '';
    columns    = COLUMNS;
    editableFields = EDITABLE_FIELDS;

    @wire(getRecords, {
        sobjectApiName: 'Account',
        fields        : 'Id, Name, Rating, Industry, AnnualRevenue',
        whereClause   : '',
        maxRows       : 200,
    })
    wiredAccounts({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.accounts = data;
        } else if (error) {
            this.error = error?.body?.message || 'Failed to load accounts.';
        }
    }

    handleMassUpdate(evt) {
        const { result } = evt.detail;
        this.dispatchEvent(new ShowToastEvent({
            title  : 'Mass Update Complete',
            message: result.message,
            variant: result.failureCount === 0 ? 'success' : 'warning',
        }));
        // Refresh the wire (simple approach — use refreshApex for reactive wire)
        this.isLoading = true;
        // Re-invoke wire by toggling a dummy reactive property if needed
    }

    handleRollback(evt) {
        const { result } = evt.detail;
        this.dispatchEvent(new ShowToastEvent({
            title  : 'Rollback Complete',
            message: result.message,
            variant: result.failureCount === 0 ? 'success' : 'warning',
        }));
    }
}
