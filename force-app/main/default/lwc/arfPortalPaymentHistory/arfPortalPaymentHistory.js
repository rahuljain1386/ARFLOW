import { LightningElement, api, wire, track } from 'lwc';
import getPaymentHistory from '@salesforce/apex/ARF_PaymentPortalController.getPaymentHistory';

export default class ArfPortalPaymentHistory extends LightningElement {
    @api accountId;
    @track payments = [];
    @track isLoading = true;
    @track error;
    @track expandedIds = new Set();

    @wire(getPaymentHistory, { accountId: '$accountId' })
    wiredHistory({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.payments = data.map(p => ({
                ...p,
                formattedAmount: '$' + Number(p.amount).toLocaleString('en-US', { minimumFractionDigits: 2 }),
                statusClass: this.getStatusClass(p.status),
                hasApplications: p.applications && p.applications.length > 0,
                isExpanded: false,
                expandIcon: 'utility:chevronright',
                applications: p.applications ? p.applications.map((app, idx) => ({
                    ...app,
                    key: p.id + '-' + idx,
                    formattedAmount: '$' + Number(app.amountApplied).toLocaleString('en-US', { minimumFractionDigits: 2 })
                })) : []
            }));
        } else if (error) {
            this.error = error.body ? error.body.message : 'Failed to load payment history';
        }
    }

    get hasPayments() {
        return this.payments.length > 0;
    }

    getStatusClass(status) {
        switch (status) {
            case 'Applied': return 'slds-badge badge-applied';
            case 'Partially Applied': return 'slds-badge badge-partial';
            case 'Received': return 'slds-badge badge-received';
            case 'Reversed': return 'slds-badge badge-reversed';
            case 'Void': return 'slds-badge badge-void';
            default: return 'slds-badge';
        }
    }

    handleToggleExpand(event) {
        const paymentId = event.currentTarget.dataset.id;
        const updated = new Set(this.expandedIds);
        if (updated.has(paymentId)) {
            updated.delete(paymentId);
        } else {
            updated.add(paymentId);
        }
        this.expandedIds = updated;
        this.payments = this.payments.map(p => ({
            ...p,
            isExpanded: this.expandedIds.has(p.id),
            expandIcon: this.expandedIds.has(p.id) ? 'utility:chevrondown' : 'utility:chevronright'
        }));
    }
}
