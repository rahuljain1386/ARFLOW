import { LightningElement, api } from 'lwc';
import getDeductions from '@salesforce/apex/ARF_Account360Controller.getDeductions';

const COLUMNS = [
    {
        label: 'Deduction #', fieldName: 'deductionUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' }
    },
    { label: 'Amount', fieldName: 'Amount__c', type: 'currency' },
    { label: 'Category', fieldName: 'Category__c', type: 'text' },
    { label: 'Type', fieldName: 'Type__c', type: 'text' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    { label: 'Invoice', fieldName: 'invoiceNumber', type: 'text' },
    { label: 'Validity Score', fieldName: 'Validity_Score__c', type: 'number' },
    { label: 'Recovery', fieldName: 'Recovery_Amount__c', type: 'currency' },
    { label: 'Recovery Status', fieldName: 'Recovery_Status__c', type: 'text' },
    { label: 'Created', fieldName: 'CreatedDate', type: 'date' }
];

export default class ArfAccount360Deductions extends LightningElement {
    @api recordId;
    columns = COLUMNS;
    deductions;
    error;

    _refreshKey = 0;
    @api
    get refreshKey() { return this._refreshKey; }
    set refreshKey(value) {
        this._refreshKey = value;
        if (this.recordId) {
            this.loadDeductions();
        }
    }

    connectedCallback() {
        this.loadDeductions();
    }

    async loadDeductions() {
        try {
            const data = await getDeductions({ accountId: this.recordId });
            this.deductions = data.map(d => ({
                ...d,
                deductionUrl: '/' + d.Id,
                invoiceNumber: d.Invoice__r ? d.Invoice__r.Document_Number__c : ''
            }));
            this.error = undefined;
        } catch (error) {
            this.error = error;
            this.deductions = undefined;
        }
    }

    get hasData() { return this.deductions && this.deductions.length > 0; }
    get recordCount() { return this.deductions ? this.deductions.length : 0; }
    get cardTitle() { return `Deductions (${this.recordCount})`; }
}
