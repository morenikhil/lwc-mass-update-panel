import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import massUpdate    from '@salesforce/apex/MassUpdateController.massUpdate';
import rollbackUpdate from '@salesforce/apex/MassUpdateController.rollbackUpdate';

// Field types that map to specific input renderers
const TYPE_MAP = {
    picklist  : 'picklist',
    multipicklist: 'picklist',
    boolean   : 'checkbox',
    int       : 'number',
    double    : 'number',
    currency  : 'number',
    percent   : 'number',
    date      : 'date',
    datetime  : 'datetime',
    email     : 'email',
    url       : 'url',
    phone     : 'phone',
};

const STEP = { SELECT: 1, CONFIGURE: 2, CONFIRM: 3 };

export default class MassUpdatePanel extends LightningElement {

    // ── Public API ──────────────────────────────────────────────────────────

    /** API name of the SObject being edited (e.g. 'Account'). */
    @api sobjectApiName = '';

    /** Records array supplied by the host page. Each item must have an `Id`. */
    @api
    get records() { return this._records; }
    set records(val) {
        this._records = val || [];
    }

    /** lightning-datatable column definitions. */
    @api columns = [];

    /**
     * Array of field descriptors the user can mass-update.
     * Shape: [{ label, apiName, type, picklistOptions }]
     * `type` should be one of the keys in TYPE_MAP above, or 'text'.
     * `picklistOptions` is required when type === 'picklist':
     *   [{ label, value }]
     */
    @api editableFields = [];

    /** Maximum rows the user can select (default 200). */
    @api maxRowSelection = 200;

    // ── Tracked state ───────────────────────────────────────────────────────

    @track _records          = [];
    @track selectedRowIds    = [];
    @track selectedFieldApiName = '';
    @track newValue          = '';
    @track newValueBoolean   = false;
    @track isLoading         = false;
    @track showConfirmModal  = false;
    @track confirmMode       = 'update'; // 'update' | 'rollback'
    @track alertMessage      = '';
    @track alertType         = 'info';   // 'info' | 'success' | 'error' | 'warning'
    @track lastResult        = null;
    @track rollbackSnapshot  = null;     // stored after a successful massUpdate
    @track currentStep       = STEP.SELECT;

    // ── Derived getters ─────────────────────────────────────────────────────

    get noRecords()    { return !this._records || this._records.length === 0; }
    get hasSelection() { return this.selectedRowIds.length > 0; }
    get noSelection()  { return !this.hasSelection; }
    get selectedCount(){ return this.selectedRowIds.length; }
    get selectionLabel(){ return `${this.selectedCount} selected`; }
    get canRollback()  { return !!this.rollbackSnapshot; }
    get showResultSummary() { return !!this.lastResult; }
    get hasFailures()  { return this.lastResult?.failures?.length > 0; }

    get fieldOptions() {
        return (this.editableFields || []).map(f => ({ label: f.label, value: f.apiName }));
    }

    get selectedField() {
        return (this.editableFields || []).find(f => f.apiName === this.selectedFieldApiName);
    }

    get selectedFieldLabel() {
        return this.selectedField?.label || this.selectedFieldApiName;
    }

    get resolvedType() {
        const raw = (this.selectedField?.type || 'text').toLowerCase();
        return TYPE_MAP[raw] || 'text';
    }

    get showTextInput()     { return this.selectedFieldApiName && this.resolvedType === 'text'; }
    get showPicklistInput() { return this.selectedFieldApiName && this.resolvedType === 'picklist'; }
    get showNumberInput()   { return this.selectedFieldApiName && this.resolvedType === 'number'; }
    get showDateInput()     { return this.selectedFieldApiName && this.resolvedType === 'date'; }
    get showDatetimeInput() { return this.selectedFieldApiName && this.resolvedType === 'datetime'; }
    get showCheckboxInput() { return this.selectedFieldApiName && this.resolvedType === 'checkbox'; }
    get showEmailInput()    { return this.selectedFieldApiName && this.resolvedType === 'email'; }
    get showUrlInput()      { return this.selectedFieldApiName && this.resolvedType === 'url'; }
    get showPhoneInput()    { return this.selectedFieldApiName && this.resolvedType === 'phone'; }

    get currentPicklistOptions() {
        return this.selectedField?.picklistOptions || [];
    }

    get displayNewValue() {
        if (this.resolvedType === 'checkbox') {
            return this.newValueBoolean ? 'true' : 'false';
        }
        return this.newValue;
    }

    get showPreviewBar() {
        return this.selectedFieldApiName && (this.newValue !== '' || this.resolvedType === 'checkbox');
    }

    get isApplyDisabled() {
        if (this.isLoading || !this.hasSelection || !this.selectedFieldApiName) return true;
        if (this.resolvedType !== 'checkbox' && this.newValue === '') return true;
        return false;
    }

    // Step indicator CSS
    get stepClass1() { return this._stepCls(STEP.SELECT); }
    get stepClass2() { return this._stepCls(STEP.CONFIGURE); }
    get stepClass3() { return this._stepCls(STEP.CONFIRM); }

    _stepCls(step) {
        const base = 'step-item';
        if (this.currentStep === step)        return `${base} step-item_active`;
        if (this.currentStep > step)          return `${base} step-item_done`;
        return base;
    }

    // Alert styling
    get alertClass() {
        const base = 'slds-notify slds-notify_alert slds-m-bottom_small alert-bar';
        const map  = {
            success: 'slds-theme_success',
            error  : 'slds-theme_error',
            warning: 'slds-theme_warning',
            info   : 'slds-theme_info',
        };
        return `${base} ${map[this.alertType] || map.info}`;
    }

    get alertIcon() {
        const map = { success: 'utility:success', error: 'utility:error',
                      warning: 'utility:warning', info: 'utility:info' };
        return map[this.alertType] || map.info;
    }

    // ── Event handlers ──────────────────────────────────────────────────────

    handleRowSelection(evt) {
        this.selectedRowIds = evt.detail.selectedRows.map(r => r.Id);
        if (this.hasSelection) {
            this.currentStep = STEP.CONFIGURE;
        } else {
            this.currentStep = STEP.SELECT;
            this.newValue    = '';
            this.selectedFieldApiName = '';
        }
    }

    handleSelectAll() {
        this.selectedRowIds = (this._records || []).map(r => r.Id);
        this.currentStep    = STEP.CONFIGURE;
    }

    handleClearSelection() {
        this.selectedRowIds = [];
        this.currentStep    = STEP.SELECT;
        this.newValue       = '';
        this.selectedFieldApiName = '';
    }

    handleFieldChange(evt) {
        this.selectedFieldApiName = evt.detail.value;
        this.newValue             = '';
        this.newValueBoolean      = false;
    }

    handleValueChange(evt) {
        this.newValue = evt.detail.value;
    }

    handleCheckboxChange(evt) {
        this.newValueBoolean = evt.detail.checked;
        this.newValue        = String(evt.detail.checked);
    }

    handleOpenConfirm() {
        this.confirmMode    = 'update';
        this.showConfirmModal = true;
        this.currentStep    = STEP.CONFIRM;
    }

    handleRollbackConfirm() {
        this.confirmMode    = 'rollback';
        this.showConfirmModal = true;
    }

    handleCancelConfirm() {
        this.showConfirmModal = false;
        if (this.confirmMode === 'update') this.currentStep = STEP.CONFIGURE;
    }

    handleConfirm() {
        this.showConfirmModal = false;
        if (this.confirmMode === 'update') {
            this._doMassUpdate();
        } else {
            this._doRollback();
        }
    }

    clearAlert() {
        this.alertMessage = '';
    }

    // ── Private: Apex calls ─────────────────────────────────────────────────

    async _doMassUpdate() {
        this.isLoading = true;
        try {
            const valueToSend = this.resolvedType === 'checkbox'
                ? String(this.newValueBoolean)
                : this.newValue;

            const result = await massUpdate({
                sobjectApiName : this.sobjectApiName,
                fieldApiName   : this.selectedFieldApiName,
                newValue       : valueToSend,
                recordIdsJson  : JSON.stringify(this.selectedRowIds),
            });

            this.rollbackSnapshot = result.rollbackSnapshot;
            this.lastResult = {
                successCount : result.successCount,
                failureCount : result.failureCount,
                total        : result.successCount + result.failureCount,
                failures     : result.failures || [],
            };

            const type = result.failureCount === 0 ? 'success' : 'warning';
            this._showAlert(result.message, type);
            this._showToast(
                result.failureCount === 0 ? 'Update Complete' : 'Partial Update',
                result.message,
                type
            );

            this._fireEvent('massupdate', { result });
            this.currentStep = STEP.SELECT;
            this.selectedRowIds = [];

        } catch (err) {
            const msg = err?.body?.message || err?.message || 'Unknown error';
            this._showAlert(`Update failed: ${msg}`, 'error');
            this._showToast('Update Failed', msg, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async _doRollback() {
        if (!this.rollbackSnapshot) return;
        this.isLoading = true;
        try {
            const result = await rollbackUpdate({
                sobjectApiName  : this.sobjectApiName,
                fieldApiName    : this.selectedFieldApiName,
                rollbackDataJson: JSON.stringify(this.rollbackSnapshot),
            });

            this.lastResult = {
                successCount : result.successCount,
                failureCount : result.failureCount,
                total        : result.successCount + result.failureCount,
                failures     : result.failures || [],
            };

            if (result.failureCount === 0) {
                this.rollbackSnapshot = null; // consumed
            }

            const type = result.failureCount === 0 ? 'success' : 'warning';
            this._showAlert(result.message, type);
            this._showToast('Rollback Complete', result.message, type);
            this._fireEvent('rollback', { result });

        } catch (err) {
            const msg = err?.body?.message || err?.message || 'Unknown error';
            this._showAlert(`Rollback failed: ${msg}`, 'error');
            this._showToast('Rollback Failed', msg, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Private: utilities ──────────────────────────────────────────────────

    _showAlert(message, type = 'info') {
        this.alertMessage = message;
        this.alertType    = type;
    }

    _showToast(title, message, variant = 'info') {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _fireEvent(name, detail) {
        this.dispatchEvent(new CustomEvent(name, { detail, bubbles: true, composed: true }));
    }
}
