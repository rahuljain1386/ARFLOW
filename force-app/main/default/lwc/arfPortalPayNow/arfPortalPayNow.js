import { LightningElement, api, wire, track } from 'lwc';
import getPaymentMethods from '@salesforce/apex/ARF_PaymentPortalController.getPaymentMethods';
import processPayment from '@salesforce/apex/ARF_PaymentPortalController.processPayment';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ArfPortalPayNow extends LightningElement {
    @api accountId;
    @api invoices = [];
    @track paymentMethods = [];
    @track selectedMethodId;
    @track isProcessing = false;
    @track paymentComplete = false;
    @track confirmationNumber;
    @track error;

    @wire(getPaymentMethods, { accountId: '$accountId' })
    wiredMethods({ error, data }) {
        if (data) {
            this.paymentMethods = data.map(m => ({
                label: m.displayLabel + (m.isPrimary ? ' (Primary)' : ''),
                value: m.id
            }));
            const primary = data.find(m => m.isPrimary);
            if (primary) this.selectedMethodId = primary.id;
        } else if (error) {
            this.error = 'Failed to load payment methods';
        }
    }

    get totalAmount() {
        let total = 0;
        this.invoices.forEach(inv => { total += inv.balance; });
        return total;
    }

    get formattedTotal() {
        return '$' + this.totalAmount.toLocaleString('en-US', { minimumFractionDigits: 2 });
    }

    get invoiceCount() {
        return this.invoices.length;
    }

    get hasMethods() {
        return this.paymentMethods.length > 0;
    }

    get canSubmit() {
        return this.selectedMethodId && !this.isProcessing && this.totalAmount > 0;
    }

    get submitLabel() {
        return this.isProcessing ? 'Processing...' : 'Submit Payment \u2014 ' + this.formattedTotal;
    }

    get submitDisabled() {
        return !this.canSubmit;
    }

    get invoiceList() {
        return this.invoices.map(inv => ({
            ...inv,
            formattedBalance: '$' + Number(inv.balance).toLocaleString('en-US', { minimumFractionDigits: 2 })
        }));
    }

    handleMethodChange(event) {
        this.selectedMethodId = event.detail.value;
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    async handleSubmitPayment() {
        this.isProcessing = true;
        this.error = undefined;

        try {
            const allocations = this.invoices.map(inv => ({
                invoiceId: inv.id,
                amount: inv.balance
            }));

            const request = {
                accountId: this.accountId,
                paymentMethodId: this.selectedMethodId,
                totalAmount: this.totalAmount,
                allocations: allocations
            };

            const result = await processPayment({ requestJson: JSON.stringify(request) });

            if (result.success) {
                this.paymentComplete = true;
                this.confirmationNumber = result.confirmationNumber;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Payment Successful',
                    message: result.message,
                    variant: 'success'
                }));
            } else {
                this.error = result.message;
            }
        } catch (err) {
            this.error = err.body ? err.body.message : 'Payment failed. Please try again.';
        } finally {
            this.isProcessing = false;
        }
    }

    handleDone() {
        this.dispatchEvent(new CustomEvent('paymentcomplete'));
    }
}
