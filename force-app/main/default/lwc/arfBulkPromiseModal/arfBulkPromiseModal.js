import { LightningElement, api, track } from 'lwc';
import createBulkPromisesEnhanced from '@salesforce/apex/ARF_TransactionActionController.createBulkPromisesEnhanced';
import executeContactCustomerWithFormat from '@salesforce/apex/ARF_TransactionActionController.executeContactCustomerWithFormat';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ArfBulkPromiseModal extends LightningElement {
    @api accountId;
    @api selectedInvoices = [];

    isSubmitting = false;

    // Global config
    globalPromiseDate;
    globalNotes = '';
    applySameDate = true;

    // Per-invoice rows
    @track promiseRows = [];

    // === GETTERS ===

    get showPerRowDate() { return !this.applySameDate; }

    get invoiceCount() { return this.promiseRows.length; }

    get totalBalance() {
        return this.promiseRows.reduce((sum, r) => sum + (r.balance || 0), 0);
    }
    get totalPromiseAmount() {
        return this.promiseRows.reduce((sum, r) => sum + (r.amount || 0), 0);
    }
    get formattedTotalBalance() {
        return '$' + this.totalBalance.toLocaleString('en-US', { minimumFractionDigits: 2 });
    }
    get formattedTotalPromise() {
        return '$' + this.totalPromiseAmount.toLocaleString('en-US', { minimumFractionDigits: 2 });
    }

    get subtitle() {
        const bal = this.totalBalance.toLocaleString('en-US', { minimumFractionDigits: 2 });
        return `${this.invoiceCount} invoice(s) — Outstanding: $${bal}`;
    }

    get isSubmitDisabled() {
        return this.promiseRows.length === 0 || !this.globalPromiseDate || this.isSubmitting;
    }

    get invoiceIdList() {
        return this.promiseRows.map(r => r.invoiceId);
    }

    get submitLabel() {
        const commStep = this.template.querySelector('c-arf-communication-step');
        if (commStep) {
            const params = commStep.getCommunicationParams();
            if (params.channel !== 'SaveOnly') {
                return 'Create & Send';
            }
        }
        return 'Create Promise';
    }

    get defaultDate() {
        const d = new Date();
        d.setDate(d.getDate() + 7);
        return d.toISOString().split('T')[0];
    }

    // === LIFECYCLE ===

    connectedCallback() {
        this.globalPromiseDate = this.defaultDate;

        this.promiseRows = (this.selectedInvoices || []).map(inv => ({
            invoiceId: inv.Id,
            documentNumber: inv.Document_Number__c || inv.Name,
            balance: inv.Balance__c || 0,
            formattedBalance: '$' + (inv.Balance__c || 0).toLocaleString('en-US', { minimumFractionDigits: 2 }),
            amount: inv.Balance__c || 0,
            promiseDate: this.defaultDate
        }));
    }

    // === HANDLERS: Global config ===

    handleGlobalDateChange(event) {
        this.globalPromiseDate = event.detail.value;
        if (this.applySameDate) {
            this.promiseRows = this.promiseRows.map(row => ({
                ...row,
                promiseDate: this.globalPromiseDate
            }));
        }
    }

    handleTotalAmountChange(event) {
        const newTotal = parseFloat(event.detail.value) || 0;
        const currentTotal = this.totalBalance;
        if (currentTotal === 0) return;

        // Proportional allocation based on each invoice's balance
        this.promiseRows = this.promiseRows.map(row => ({
            ...row,
            amount: Math.round((row.balance / currentTotal) * newTotal * 100) / 100
        }));
    }

    handleSameDateToggle(event) {
        this.applySameDate = event.target.checked;
        if (this.applySameDate) {
            this.promiseRows = this.promiseRows.map(row => ({
                ...row,
                promiseDate: this.globalPromiseDate
            }));
        }
    }

    handleGlobalNotesChange(event) {
        this.globalNotes = event.detail.value;
    }

    // === HANDLERS: Per-row ===

    handleRowFieldChange(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;
        const value = field === 'amount'
            ? (parseFloat(event.detail.value) || 0)
            : event.detail.value;

        this.promiseRows = this.promiseRows.map(row => {
            if (row.invoiceId === id) {
                return { ...row, [field]: value };
            }
            return row;
        });
    }

    handleRemoveRow(event) {
        const id = event.target.dataset.id;
        this.promiseRows = this.promiseRows.filter(r => r.invoiceId !== id);
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // === SUBMIT ===

    async handleSubmit() {
        const commStep = this.template.querySelector('c-arf-communication-step');
        if (commStep && !commStep.validate()) return;

        this.isSubmitting = true;
        try {
            // Build per-invoice config JSON
            const configArray = this.promiseRows.map(row => ({
                invoiceId: row.invoiceId,
                amount: row.amount,
                promiseDate: this.applySameDate ? this.globalPromiseDate : row.promiseDate,
                notes: this.globalNotes
            }));

            // Create promises
            await createBulkPromisesEnhanced({
                accountId: this.accountId,
                promiseConfigJson: JSON.stringify(configArray)
            });

            // Handle communication
            if (commStep) {
                const commParams = commStep.getCommunicationParams();
                if (commParams.channel !== 'SaveOnly') {
                    await executeContactCustomerWithFormat({
                        accountId: this.accountId,
                        invoiceIds: this.invoiceIdList,
                        channel: commParams.channel,
                        fromAddressId: commParams.fromAddressId || null,
                        toAddress: commParams.toAddress || '',
                        ccAddresses: commParams.ccAddresses || null,
                        bccAddresses: commParams.bccAddresses || null,
                        subject: commParams.subject || '',
                        htmlBody: commParams.htmlBody || '',
                        attachStatement: commParams.attachStatement || false,
                        contactId: commParams.contactId || null,
                        templateName: commParams.templateName || '',
                        noteCategory: commParams.noteCategory || null,
                        noteTitle: commParams.noteTitle || null,
                        noteBody: commParams.noteBody || null,
                        createFollowUp: commParams.createFollowUp || false,
                        followUpDays: commParams.followUpDays || null,
                        followUpSubject: commParams.followUpSubject || null,
                        followUpBody: null,
                        attachmentFormat: commParams.attachmentFormat || 'pdf'
                    });
                }
            }

            const amt = this.totalPromiseAmount.toLocaleString('en-US', { minimumFractionDigits: 2 });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Promise Created',
                message: `Created ${this.promiseRows.length} promise(s) totaling $${amt}`,
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('save'));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body ? error.body.message : error.message,
                variant: 'error'
            }));
        } finally {
            this.isSubmitting = false;
        }
    }
}
