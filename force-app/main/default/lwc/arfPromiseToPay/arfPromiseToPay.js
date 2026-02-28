import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getPromises from '@salesforce/apex/ARF_PromiseToPayController.getPromises';
import createInstallmentPlan from '@salesforce/apex/ARF_PromiseToPayController.createInstallmentPlan';
import cancelPromise from '@salesforce/apex/ARF_PromiseToPayController.cancelPromise';
import recordPaymentReceived from '@salesforce/apex/ARF_PromiseToPayController.recordPaymentReceived';

const COLUMNS = [
    {
        label: 'Promise', fieldName: 'Name', type: 'text',
        initialWidth: 120
    },
    {
        label: 'Invoice', fieldName: 'invoiceNumber', type: 'text',
        initialWidth: 120
    },
    { label: 'Amount', fieldName: 'Amount__c', type: 'currency' },
    { label: 'Received', fieldName: 'Amount_Received__c', type: 'currency' },
    { label: 'Due Date', fieldName: 'Promise_Date__c', type: 'date' },
    {
        label: 'Status', fieldName: 'Status__c', type: 'text',
        cellAttributes: {
            class: { fieldName: 'statusClass' }
        }
    },
    { label: 'Broken', fieldName: 'Broken_Count__c', type: 'number', initialWidth: 80 },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Record Payment', name: 'record_payment' },
                { label: 'Cancel Promise', name: 'cancel' }
            ]
        }
    }
];

export default class ArfPromiseToPay extends LightningElement {
    @api recordId;
    columns = COLUMNS;

    _refreshKey = 0;
    @api
    get refreshKey() { return this._refreshKey; }
    set refreshKey(value) {
        this._refreshKey = value;
        if (this.wiredResult) {
            refreshApex(this.wiredResult);
        }
    }
    promises = [];
    error;
    isLoading = false;
    wiredResult;

    // Create form state
    showCreateForm = false;
    isInstallment = false;
    newInvoiceId = '';
    newAmount = 0;
    newPromiseDate = '';
    newNotes = '';
    installmentCount = 3;
    daysBetween = 30;

    // Payment modal state
    showPaymentModal = false;
    selectedPromiseId = '';
    paymentAmount = 0;

    @wire(getPromises, { accountId: '$recordId' })
    wiredPromises(result) {
        this.wiredResult = result;
        if (result.data) {
            this.promises = result.data.map(p => ({
                ...p,
                invoiceNumber: p.Invoice__r ? p.Invoice__r.Document_Number__c : '',
                statusClass: this.getStatusClass(p.Status__c)
            }));
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.promises = [];
        }
    }

    getStatusClass(status) {
        switch (status) {
            case 'Kept': return 'slds-text-color_success';
            case 'Broken': return 'slds-text-color_error';
            case 'Cancelled': return 'slds-text-color_weak';
            default: return '';
        }
    }

    get hasPromises() { return this.promises && this.promises.length > 0; }
    get promiseCount() { return this.promises ? this.promises.length : 0; }
    get cardTitle() { return `Promises to Pay (${this.promiseCount})`; }
    get noError() { return !this.error; }
    get createButtonLabel() { return this.showCreateForm ? 'Cancel' : 'New Promise'; }

    handleToggleCreateForm() {
        this.showCreateForm = !this.showCreateForm;
        if (!this.showCreateForm) this.resetCreateForm();
    }

    handleInstallmentToggle(event) {
        this.isInstallment = event.target.checked;
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        switch (field) {
            case 'invoiceId': this.newInvoiceId = event.detail.value; break;
            case 'amount': this.newAmount = event.detail.value; break;
            case 'promiseDate': this.newPromiseDate = event.detail.value; break;
            case 'notes': this.newNotes = event.detail.value; break;
            case 'installmentCount': this.installmentCount = event.detail.value; break;
            case 'daysBetween': this.daysBetween = event.detail.value; break;
        }
    }

    async handleCreate() {
        if (!this.newAmount || this.newAmount <= 0) {
            this.showToast('Error', 'Amount is required and must be greater than 0', 'error');
            return;
        }
        if (!this.newPromiseDate) {
            this.showToast('Error', 'Promise date is required', 'error');
            return;
        }

        this.isLoading = true;
        try {
            if (this.isInstallment) {
                await createInstallmentPlan({
                    accountId: this.recordId,
                    invoiceId: this.newInvoiceId || null,
                    totalAmount: parseFloat(this.newAmount),
                    installmentCount: parseInt(this.installmentCount, 10) || 3,
                    firstPaymentDate: this.newPromiseDate,
                    daysBetweenPayments: parseInt(this.daysBetween, 10) || 30,
                    notes: this.newNotes
                });
                this.showToast('Success', `Installment plan created with ${this.installmentCount} payments`, 'success');
            } else {
                await createInstallmentPlan({
                    accountId: this.recordId,
                    invoiceId: this.newInvoiceId || null,
                    totalAmount: parseFloat(this.newAmount),
                    installmentCount: 1,
                    firstPaymentDate: this.newPromiseDate,
                    daysBetweenPayments: 0,
                    notes: this.newNotes
                });
                this.showToast('Success', 'Promise to pay created', 'success');
            }
            this.showCreateForm = false;
            this.resetCreateForm();
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to create promise', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        switch (action.name) {
            case 'record_payment':
                this.selectedPromiseId = row.Id;
                this.paymentAmount = 0;
                this.showPaymentModal = true;
                break;
            case 'cancel':
                this.handleCancel(row.Id);
                break;
        }
    }

    async handleCancel(promiseId) {
        this.isLoading = true;
        try {
            await cancelPromise({ promiseId });
            this.showToast('Success', 'Promise cancelled', 'success');
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to cancel', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handlePaymentAmountChange(event) {
        this.paymentAmount = event.detail.value;
    }

    handleClosePaymentModal() {
        this.showPaymentModal = false;
        this.selectedPromiseId = '';
        this.paymentAmount = 0;
    }

    async handleSavePayment() {
        if (!this.paymentAmount || this.paymentAmount <= 0) {
            this.showToast('Error', 'Payment amount must be greater than 0', 'error');
            return;
        }
        this.isLoading = true;
        try {
            await recordPaymentReceived({
                promiseId: this.selectedPromiseId,
                amountReceived: parseFloat(this.paymentAmount)
            });
            this.showToast('Success', 'Payment recorded', 'success');
            this.showPaymentModal = false;
            this.selectedPromiseId = '';
            this.paymentAmount = 0;
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to record payment', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    resetCreateForm() {
        this.isInstallment = false;
        this.newInvoiceId = '';
        this.newAmount = 0;
        this.newPromiseDate = '';
        this.newNotes = '';
        this.installmentCount = 3;
        this.daysBetween = 30;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
