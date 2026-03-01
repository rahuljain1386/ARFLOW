import { LightningElement, api, wire, track } from 'lwc';
import getAccountSummary from '@salesforce/apex/ARF_PaymentPortalController.getAccountSummary';

export default class ArfPaymentPortal extends LightningElement {
    @api accountId;
    @track activeTab = 'invoices';
    @track summary = {};
    @track error;
    @track showPayNow = false;
    @track selectedInvoices = [];

    @wire(getAccountSummary, { accountId: '$accountId' })
    wiredSummary({ error, data }) {
        if (data) {
            this.summary = data;
            this.error = undefined;
        } else if (error) {
            this.error = error.body ? error.body.message : 'Failed to load account summary';
        }
    }

    get hasAccount() {
        return this.accountId != null;
    }

    get formattedOutstanding() {
        return this.summary.totalOutstanding != null ? '$' + Number(this.summary.totalOutstanding).toLocaleString('en-US', { minimumFractionDigits: 2 }) : '$0.00';
    }

    get formattedPastDue() {
        return this.summary.totalPastDue != null ? '$' + Number(this.summary.totalPastDue).toLocaleString('en-US', { minimumFractionDigits: 2 }) : '$0.00';
    }

    get hasPastDue() {
        return this.summary.totalPastDue > 0;
    }

    get isInvoicesTab() { return this.activeTab === 'invoices'; }
    get isPaymentMethodsTab() { return this.activeTab === 'methods'; }
    get isAutopayTab() { return this.activeTab === 'autopay'; }
    get isHistoryTab() { return this.activeTab === 'history'; }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
        this.showPayNow = false;
    }

    getTabClass(tabName) {
        return this.activeTab === tabName
            ? 'slds-tabs_default__item slds-is-active'
            : 'slds-tabs_default__item';
    }

    get invoicesTabClass() { return this.getTabClass('invoices'); }
    get methodsTabClass() { return this.getTabClass('methods'); }
    get autopayTabClass() { return this.getTabClass('autopay'); }
    get historyTabClass() { return this.getTabClass('history'); }

    handlePayNow(event) {
        this.selectedInvoices = event.detail.invoices;
        this.showPayNow = true;
    }

    handlePaymentComplete() {
        this.showPayNow = false;
        this.activeTab = 'history';
    }

    handleBackToInvoices() {
        this.showPayNow = false;
        this.activeTab = 'invoices';
    }
}
