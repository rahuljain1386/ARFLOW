import { LightningElement, api, wire, track } from 'lwc';
import getAutopaySchedule from '@salesforce/apex/ARF_PaymentPortalController.getAutopaySchedule';
import getPaymentMethods from '@salesforce/apex/ARF_PaymentPortalController.getPaymentMethods';
import saveAutopaySchedule from '@salesforce/apex/ARF_PaymentPortalController.saveAutopaySchedule';
import cancelAutopay from '@salesforce/apex/ARF_PaymentPortalController.cancelAutopay';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class ArfPortalAutopay extends LightningElement {
    @api accountId;
    @track schedule;
    @track paymentMethods = [];
    @track showSetupForm = false;
    @track isSaving = false;
    @track error;
    _wiredSchedule;

    // Form fields
    @track selectedMethodId = '';
    @track ruleType = 'All Due';
    @track fixedAmount;
    @track maxAmount;
    @track scheduleDay = 1;

    @wire(getAutopaySchedule, { accountId: '$accountId' })
    wiredSchedule(result) {
        this._wiredSchedule = result;
        if (result.data) {
            this.schedule = result.data;
        } else {
            this.schedule = null;
        }
    }

    @wire(getPaymentMethods, { accountId: '$accountId' })
    wiredMethods({ data }) {
        if (data) {
            this.paymentMethods = data.map(m => ({
                label: m.displayLabel,
                value: m.id
            }));
        }
    }

    get hasSchedule() {
        return this.schedule != null;
    }

    get isActive() {
        return this.schedule && this.schedule.isActive;
    }

    get ruleTypeOptions() {
        return [
            { label: 'All Due — Pay all open invoices', value: 'All Due' },
            { label: 'Past Due Only — Only pay overdue invoices', value: 'Past Due Only' },
            { label: 'Fixed Amount — Pay a set amount each month', value: 'Fixed Amount' }
        ];
    }

    get isFixedAmount() {
        return this.ruleType === 'Fixed Amount';
    }

    get dayOptions() {
        return Array.from({ length: 28 }, (_, i) => ({
            label: String(i + 1),
            value: i + 1
        }));
    }

    get hasMethods() {
        return this.paymentMethods.length > 0;
    }

    get statusBadgeClass() {
        return this.isActive ? 'slds-badge slds-theme_success' : 'slds-badge';
    }

    get saveLabel() {
        return this.isSaving ? 'Saving...' : 'Save Autopay Schedule';
    }

    handleShowSetup() {
        this.showSetupForm = true;
        if (this.schedule) {
            this.selectedMethodId = this.schedule.paymentMethodId;
            this.ruleType = this.schedule.ruleType;
            this.fixedAmount = this.schedule.fixedAmount;
            this.maxAmount = this.schedule.maxAmount;
            this.scheduleDay = this.schedule.scheduleDay || 1;
        }
    }

    handleCancelSetup() {
        this.showSetupForm = false;
    }

    handleMethodChange(event) { this.selectedMethodId = event.detail.value; }
    handleRuleTypeChange(event) { this.ruleType = event.detail.value; }
    handleFixedAmountChange(event) { this.fixedAmount = parseFloat(event.detail.value); }
    handleMaxAmountChange(event) { this.maxAmount = parseFloat(event.detail.value); }
    handleDayChange(event) { this.scheduleDay = parseInt(event.detail.value, 10); }

    async handleSave() {
        if (!this.selectedMethodId) {
            this.error = 'Please select a payment method';
            return;
        }
        this.isSaving = true;
        this.error = undefined;
        try {
            await saveAutopaySchedule({
                accountId: this.accountId,
                paymentMethodId: this.selectedMethodId,
                ruleType: this.ruleType,
                fixedAmount: this.fixedAmount,
                maxAmount: this.maxAmount,
                scheduleDay: this.scheduleDay
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Autopay Enabled',
                message: 'Your autopay schedule has been saved',
                variant: 'success'
            }));
            this.showSetupForm = false;
            await refreshApex(this._wiredSchedule);
        } catch (err) {
            this.error = err.body ? err.body.message : 'Failed to save autopay';
        } finally {
            this.isSaving = false;
        }
    }

    async handleCancel() {
        if (!this.schedule) return;
        try {
            await cancelAutopay({ scheduleId: this.schedule.id });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Autopay Cancelled',
                message: 'Your autopay schedule has been cancelled',
                variant: 'success'
            }));
            await refreshApex(this._wiredSchedule);
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err.body ? err.body.message : 'Failed to cancel',
                variant: 'error'
            }));
        }
    }
}
