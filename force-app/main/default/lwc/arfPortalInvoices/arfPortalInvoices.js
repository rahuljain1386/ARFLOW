import { LightningElement, api, wire, track } from 'lwc';
import getOpenInvoices from '@salesforce/apex/ARF_PaymentPortalController.getOpenInvoices';

export default class ArfPortalInvoices extends LightningElement {
    @api accountId;
    @track invoices = [];
    @track selectedIds = new Set();
    @track isLoading = true;
    @track error;

    @wire(getOpenInvoices, { accountId: '$accountId' })
    wiredInvoices({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.invoices = data.map(inv => ({
                ...inv,
                isSelected: false,
                rowClass: inv.isOverdue ? 'invoice-row overdue' : 'invoice-row',
                formattedAmount: '$' + Number(inv.amount).toLocaleString('en-US', { minimumFractionDigits: 2 }),
                formattedBalance: '$' + Number(inv.balance).toLocaleString('en-US', { minimumFractionDigits: 2 }),
                statusClass: inv.isOverdue ? 'slds-badge badge-overdue' : 'slds-badge badge-open'
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error.body ? error.body.message : 'Failed to load invoices';
        }
    }

    get hasInvoices() {
        return this.invoices.length > 0;
    }

    get hasSelections() {
        return this.selectedIds.size > 0;
    }

    get selectedCount() {
        return this.selectedIds.size;
    }

    get selectedTotal() {
        let total = 0;
        this.invoices.forEach(inv => {
            if (this.selectedIds.has(inv.id)) {
                total += inv.balance;
            }
        });
        return '$' + total.toLocaleString('en-US', { minimumFractionDigits: 2 });
    }

    get allSelected() {
        return this.invoices.length > 0 && this.selectedIds.size === this.invoices.length;
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        if (checked) {
            this.selectedIds = new Set(this.invoices.map(i => i.id));
        } else {
            this.selectedIds = new Set();
        }
        this.updateSelections();
    }

    handleRowSelect(event) {
        const invoiceId = event.currentTarget.dataset.id;
        const checked = event.target.checked;
        const updated = new Set(this.selectedIds);
        if (checked) {
            updated.add(invoiceId);
        } else {
            updated.delete(invoiceId);
        }
        this.selectedIds = updated;
        this.updateSelections();
    }

    updateSelections() {
        this.invoices = this.invoices.map(inv => ({
            ...inv,
            isSelected: this.selectedIds.has(inv.id)
        }));
    }

    handlePaySelected() {
        const selectedInvoices = this.invoices.filter(inv => this.selectedIds.has(inv.id));
        this.dispatchEvent(new CustomEvent('paynow', {
            detail: { invoices: selectedInvoices }
        }));
    }

    handlePayAll() {
        this.dispatchEvent(new CustomEvent('paynow', {
            detail: { invoices: [...this.invoices] }
        }));
    }
}
