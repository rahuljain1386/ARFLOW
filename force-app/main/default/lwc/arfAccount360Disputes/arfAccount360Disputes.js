import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDisputes from '@salesforce/apex/ARF_Account360Controller.getDisputes';
import updateDisputeStatuses from '@salesforce/apex/ARF_Account360Controller.updateDisputeStatuses';

const COLUMNS = [
    {
        label: 'Dispute #', fieldName: 'disputeUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' }
    },
    { label: 'Amount', fieldName: 'Dispute_Amount__c', type: 'currency' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    { label: 'Category', fieldName: 'Category__c', type: 'text' },
    { label: 'Priority', fieldName: 'Priority__c', type: 'text' },
    { label: 'Invoice', fieldName: 'invoiceNumber', type: 'text' },
    { label: 'Assigned To', fieldName: 'assignedToName', type: 'text' },
    { label: 'SLA Date', fieldName: 'SLA_Date__c', type: 'date' },
    { label: 'SLA Days Left', fieldName: 'SLA_Days_Remaining__c', type: 'number' },
    { label: 'Created', fieldName: 'CreatedDate', type: 'date' }
];

export default class ArfAccount360Disputes extends LightningElement {
    @api recordId;
    columns = COLUMNS;
    disputes;
    error;

    // Selection
    selectedRows = [];
    @track _selectedDisputeData = [];

    // Modals
    showStatusModal = false;
    showContactModal = false;

    _refreshKey = 0;
    @api
    get refreshKey() { return this._refreshKey; }
    set refreshKey(value) {
        this._refreshKey = value;
        if (this.recordId) {
            this.loadDisputes();
        }
    }

    connectedCallback() {
        this.loadDisputes();
    }

    async loadDisputes() {
        try {
            const data = await getDisputes({ accountId: this.recordId });
            this.disputes = data.map(d => ({
                ...d,
                disputeUrl: '/' + d.Id,
                invoiceNumber: d.Invoice__r ? d.Invoice__r.Document_Number__c : '',
                assignedToName: d.Assigned_To__r ? d.Assigned_To__r.Name : ''
            }));
            this.error = undefined;
            this.selectedRows = [];
            this._selectedDisputeData = [];
        } catch (error) {
            this.error = error;
            this.disputes = undefined;
        }
    }

    // === GETTERS ===

    get hasData() { return this.disputes && this.disputes.length > 0; }
    get recordCount() { return this.disputes ? this.disputes.length : 0; }
    get cardTitle() { return `Disputes (${this.recordCount})`; }

    get selectedCount() { return this._selectedDisputeData.length; }
    get hasSelection() { return this.selectedCount > 0; }
    get hasNoSelection() { return this.selectedCount === 0; }

    get selectionSummary() {
        const totalAmt = this._selectedDisputeData.reduce(
            (sum, d) => sum + (d.Dispute_Amount__c || 0), 0
        );
        const formatted = '$' + totalAmt.toLocaleString('en-US', { minimumFractionDigits: 2 });
        return `Selected: ${this.selectedCount} | Amount: ${formatted}`;
    }

    get selectedDisputeIds() {
        return this._selectedDisputeData.map(d => d.Id);
    }

    get disputeInvoices() {
        // Build invoice-like objects from dispute data for the contact modal
        const invoiceMap = new Map();
        for (const d of this._selectedDisputeData) {
            if (d.Invoice__c && !invoiceMap.has(d.Invoice__c)) {
                invoiceMap.set(d.Invoice__c, {
                    Id: d.Invoice__c,
                    Document_Number__c: d.invoiceNumber || d.Invoice__c,
                    Balance__c: d.Dispute_Amount__c || 0
                });
            }
        }
        return Array.from(invoiceMap.values());
    }

    // === SELECTION HANDLERS ===

    handleRowSelection(event) {
        const selectedIds = event.detail.selectedRows.map(r => r.Id);
        this.selectedRows = selectedIds;
        this._selectedDisputeData = this.disputes.filter(d => selectedIds.includes(d.Id));
    }

    handleSelectAll() {
        const allIds = this.disputes.map(d => d.Id);
        this.selectedRows = allIds;
        this._selectedDisputeData = [...this.disputes];
    }

    handleClearSelection() {
        this.selectedRows = [];
        this._selectedDisputeData = [];
    }

    // === ACTION HANDLERS ===

    handleChangeStatus() {
        if (this.hasNoSelection) return;
        this.showStatusModal = true;
    }

    async handleCloseDisputes() {
        if (this.hasNoSelection) return;
        try {
            await updateDisputeStatuses({
                disputeIds: this.selectedDisputeIds,
                newStatus: 'Closed'
            });
            this.showToast('Success', `${this.selectedCount} dispute(s) closed`, 'success');
            this.loadDisputes();
            this.dispatchEvent(new CustomEvent('recordcreated', { bubbles: true, composed: true }));
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        }
    }

    handleFollowUpEmail() {
        if (this.hasNoSelection) return;
        this.showContactModal = true;
    }

    // === STATUS MODAL HANDLERS ===

    handleStatusModalClose() {
        this.showStatusModal = false;
    }

    async handleStatusModalSave(event) {
        const { disputeIds, newStatus } = event.detail;
        this.showStatusModal = false;
        try {
            await updateDisputeStatuses({ disputeIds, newStatus });
            this.showToast('Success', `${disputeIds.length} dispute(s) updated to ${newStatus}`, 'success');
            this.loadDisputes();
            this.dispatchEvent(new CustomEvent('recordcreated', { bubbles: true, composed: true }));
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        }
    }

    // === CONTACT MODAL HANDLERS ===

    handleContactModalClose() {
        this.showContactModal = false;
    }

    handleContactModalSave() {
        this.showContactModal = false;
        this.loadDisputes();
        this.dispatchEvent(new CustomEvent('recordcreated', { bubbles: true, composed: true }));
    }

    // === UTILITIES ===

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unexpected error occurred';
    }
}
