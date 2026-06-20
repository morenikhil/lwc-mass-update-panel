import { LightningElement, api } from 'lwc';

export default class MassUpdateConfirmModal extends LightningElement {

    /** Number of records being affected. */
    @api selectedCount = 0;

    /** Display label of the field being updated. */
    @api fieldLabel = '';

    /** The new value being applied (display string). */
    @api newValue = '';

    /**
     * 'update'   — confirming a mass update operation
     * 'rollback' — confirming a rollback to original values
     */
    @api mode = 'update';

    // ── Derived getters ──────────────────────────────────────────────────────

    get isUpdateMode()   { return this.mode === 'update'; }
    get isRollbackMode() { return this.mode === 'rollback'; }

    get headerTitle() {
        return this.isUpdateMode ? 'Confirm Mass Update' : 'Confirm Rollback';
    }

    get headerIcon() {
        return this.isUpdateMode ? 'utility:edit' : 'utility:undo';
    }

    get headerIconVariant() {
        return this.isUpdateMode ? 'inverse' : 'inverse';
    }

    get confirmLabel() {
        return this.isUpdateMode ? 'Apply Update' : 'Rollback';
    }

    get confirmVariant() {
        return this.isUpdateMode ? 'brand' : 'destructive';
    }

    get confirmIcon() {
        return this.isUpdateMode ? 'utility:apex' : 'utility:undo';
    }

    // ── Event handlers ───────────────────────────────────────────────────────

    handleConfirm() {
        this.dispatchEvent(new CustomEvent('confirm'));
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }
}
