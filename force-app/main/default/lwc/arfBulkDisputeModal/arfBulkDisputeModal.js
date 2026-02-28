import { LightningElement, api, track } from 'lwc';
import createBulkDisputesEnhanced from '@salesforce/apex/ARF_TransactionActionController.createBulkDisputesEnhanced';
import executeContactCustomerWithFormat from '@salesforce/apex/ARF_TransactionActionController.executeContactCustomerWithFormat';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const CATEGORY_OPTIONS = [
    { label: 'Pricing', value: 'Pricing' },
    { label: 'Shortage', value: 'Shortage' },
    { label: 'Quality', value: 'Quality' },
    { label: 'Delivery', value: 'Delivery' },
    { label: 'Duplicate', value: 'Duplicate' },
    { label: 'Damaged', value: 'Damaged' },
    { label: 'Unauthorized', value: 'Unauthorized' },
    { label: 'Tax', value: 'Tax' },
    { label: 'Other', value: 'Other' }
];

const SUBCATEGORY_OPTIONS = [
    { label: '-- None --', value: '' },
    { label: 'Pricing Error', value: 'Pricing Error' },
    { label: 'Shipping Error', value: 'Shipping Error' },
    { label: 'Quality Issue', value: 'Quality Issue' },
    { label: 'System Error', value: 'System Error' },
    { label: 'Customer Error', value: 'Customer Error' },
    { label: 'Vendor Error', value: 'Vendor Error' },
    { label: 'Process Gap', value: 'Process Gap' },
    { label: 'Other', value: 'Other' }
];

const PRIORITY_OPTIONS = [
    { label: 'High', value: 'High' },
    { label: 'Medium', value: 'Medium' },
    { label: 'Low', value: 'Low' }
];

export default class ArfBulkDisputeModal extends LightningElement {
    @api accountId;
    @api selectedInvoices = [];

    isSubmitting = false;

    // Global config
    applyToAll = true;
    globalCategory = 'Pricing';
    globalRootCause = '';
    globalPriority = 'Medium';
    globalDescription = '';

    // Per-invoice rows
    @track disputeRows = [];

    categoryOptions = CATEGORY_OPTIONS;
    subcategoryOptions = SUBCATEGORY_OPTIONS;
    priorityOptions = PRIORITY_OPTIONS;

    // === GETTERS ===

    get showPerRow() { return !this.applyToAll; }

    get invoiceCount() { return this.disputeRows.length; }
    get totalBalance() {
        return this.disputeRows.reduce((sum, r) => sum + (r.balance || 0), 0);
    }
    get totalDisputeAmount() {
        return this.disputeRows.reduce((sum, r) => sum + (r.amount || 0), 0);
    }
    get subtitle() {
        const bal = this.totalBalance.toLocaleString('en-US', { minimumFractionDigits: 2 });
        return `${this.invoiceCount} invoice(s) — Total: $${bal}`;
    }
    get isSubmitDisabled() {
        return this.disputeRows.length === 0 || this.isSubmitting;
    }

    get invoiceIdList() {
        return this.disputeRows.map(r => r.invoiceId);
    }

    get submitLabel() {
        const commStep = this.template.querySelector('c-arf-communication-step');
        if (commStep) {
            const params = commStep.getCommunicationParams();
            if (params.channel !== 'SaveOnly') {
                return 'Create & Send';
            }
        }
        return 'Create Disputes';
    }

    // === LIFECYCLE ===

    connectedCallback() {
        this.disputeRows = (this.selectedInvoices || []).map(inv => ({
            invoiceId: inv.Id,
            documentNumber: inv.Document_Number__c || inv.Name,
            balance: inv.Balance__c || 0,
            formattedBalance: '$' + (inv.Balance__c || 0).toLocaleString('en-US', { minimumFractionDigits: 2 }),
            category: this.globalCategory,
            rootCause: this.globalRootCause,
            priority: this.globalPriority,
            amount: inv.Balance__c || 0,
            description: ''
        }));
    }

    // === HANDLERS: Global config ===

    handleApplyToggle(event) {
        this.applyToAll = event.target.checked;
        if (this.applyToAll) {
            this.syncGlobalToRows();
        }
    }

    handleGlobalCategoryChange(event) {
        this.globalCategory = event.detail.value;
        if (this.applyToAll) this.syncGlobalToRows();
    }

    handleGlobalRootCauseChange(event) {
        this.globalRootCause = event.detail.value;
        if (this.applyToAll) this.syncGlobalToRows();
    }

    handleGlobalPriorityChange(event) {
        this.globalPriority = event.detail.value;
        if (this.applyToAll) this.syncGlobalToRows();
    }

    handleGlobalDescriptionChange(event) {
        this.globalDescription = event.detail.value;
    }

    syncGlobalToRows() {
        this.disputeRows = this.disputeRows.map(row => ({
            ...row,
            category: this.globalCategory,
            rootCause: this.globalRootCause,
            priority: this.globalPriority
        }));
    }

    // === HANDLERS: Per-row ===

    handleRowFieldChange(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;
        const value = field === 'amount'
            ? (parseFloat(event.detail.value) || 0)
            : event.detail.value;

        this.disputeRows = this.disputeRows.map(row => {
            if (row.invoiceId === id) {
                return { ...row, [field]: value };
            }
            return row;
        });
    }

    handleRemoveRow(event) {
        const id = event.target.dataset.id;
        this.disputeRows = this.disputeRows.filter(r => r.invoiceId !== id);
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // === SUBMIT ===

    async handleSubmit() {
        // Validate communication step
        const commStep = this.template.querySelector('c-arf-communication-step');
        if (commStep && !commStep.validate()) return;

        this.isSubmitting = true;
        try {
            // Build per-invoice config JSON
            const configArray = this.disputeRows.map(row => ({
                invoiceId: row.invoiceId,
                category: this.applyToAll ? this.globalCategory : row.category,
                rootCause: this.applyToAll ? this.globalRootCause : row.rootCause,
                priority: this.applyToAll ? this.globalPriority : row.priority,
                amount: row.amount,
                description: this.applyToAll ? this.globalDescription : (row.description || '')
            }));

            // Create disputes
            await createBulkDisputesEnhanced({
                accountId: this.accountId,
                disputeConfigJson: JSON.stringify(configArray)
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

            this.dispatchEvent(new ShowToastEvent({
                title: 'Disputes Created',
                message: `Created ${this.disputeRows.length} dispute(s)`,
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
