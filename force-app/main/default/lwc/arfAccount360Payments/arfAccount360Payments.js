import { LightningElement, api } from 'lwc';
import getPayments from '@salesforce/apex/ARF_Account360Controller.getPayments';

const COLUMNS = [
    {
        label: 'Payment #', fieldName: 'paymentUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' }
    },
    { label: 'Amount', fieldName: 'Amount__c', type: 'currency' },
    { label: 'Date', fieldName: 'Payment_Date__c', type: 'date' },
    { label: 'Method', fieldName: 'Method__c', type: 'text' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    { label: 'Applied', fieldName: 'Applied_Amount__c', type: 'currency' },
    { label: 'Unapplied', fieldName: 'Unapplied_Amount__c', type: 'currency' },
    { label: 'Reference', fieldName: 'Reference__c', type: 'text' },
    { label: 'Short Pay', fieldName: 'Has_Short_Pay__c', type: 'boolean' }
];

export default class ArfAccount360Payments extends LightningElement {
    @api recordId;
    columns = COLUMNS;
    payments;
    error;

    _refreshKey = 0;
    @api
    get refreshKey() { return this._refreshKey; }
    set refreshKey(value) {
        this._refreshKey = value;
        if (this.recordId) {
            this.loadPayments();
        }
    }

    connectedCallback() {
        this.loadPayments();
    }

    async loadPayments() {
        try {
            const data = await getPayments({ accountId: this.recordId });
            this.payments = data.map(p => ({
                ...p,
                paymentUrl: '/' + p.Id
            }));
            this.error = undefined;
        } catch (error) {
            this.error = error;
            this.payments = undefined;
        }
    }

    get hasData() { return this.payments && this.payments.length > 0; }
    get recordCount() { return this.payments ? this.payments.length : 0; }
    get cardTitle() { return `Payments (${this.recordCount})`; }
}
