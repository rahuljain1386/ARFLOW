import { LightningElement, api, wire } from 'lwc';
import getPromisesToPay from '@salesforce/apex/ARF_Account360Controller.getPromisesToPay';
import getStrategyExecutions from '@salesforce/apex/ARF_Account360Controller.getStrategyExecutions';

const PTP_COLUMNS = [
    {
        label: 'Promise #', fieldName: 'ptpUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' }
    },
    { label: 'Amount', fieldName: 'Amount__c', type: 'currency' },
    { label: 'Promise Date', fieldName: 'Promise_Date__c', type: 'date' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    { label: 'Received', fieldName: 'Amount_Received__c', type: 'currency' },
    { label: 'Times Broken', fieldName: 'Broken_Count__c', type: 'number' },
    { label: 'Invoice', fieldName: 'invoiceNumber', type: 'text' },
    { label: 'Created', fieldName: 'CreatedDate', type: 'date' }
];

const STRATEGY_COLUMNS = [
    {
        label: 'Execution #', fieldName: 'execUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' }
    },
    { label: 'Strategy', fieldName: 'strategyName', type: 'text' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    { label: 'Current Step', fieldName: 'Current_Step__c', type: 'number' },
    { label: 'Next Action', fieldName: 'Next_Action_Date__c', type: 'date' },
    { label: 'Last Action', fieldName: 'Last_Action_Date__c', type: 'date' },
    { label: 'Last Result', fieldName: 'Last_Action_Result__c', type: 'text' }
];

export default class ArfAccount360History extends LightningElement {
    @api recordId;
    ptpColumns = PTP_COLUMNS;
    strategyColumns = STRATEGY_COLUMNS;
    promises;
    executions;
    ptpError;
    execError;

    @wire(getPromisesToPay, { accountId: '$recordId' })
    wiredPromises({ data, error }) {
        if (data) {
            this.promises = data.map(p => ({
                ...p,
                ptpUrl: '/' + p.Id,
                invoiceNumber: p.Invoice__r ? p.Invoice__r.Document_Number__c : ''
            }));
            this.ptpError = undefined;
        } else if (error) {
            this.ptpError = error;
            this.promises = undefined;
        }
    }

    @wire(getStrategyExecutions, { accountId: '$recordId' })
    wiredExecutions({ data, error }) {
        if (data) {
            this.executions = data.map(e => ({
                ...e,
                execUrl: '/' + e.Id,
                strategyName: e.Strategy__r ? e.Strategy__r.Strategy_Name__c : ''
            }));
            this.execError = undefined;
        } else if (error) {
            this.execError = error;
            this.executions = undefined;
        }
    }

    get hasPromises() { return this.promises && this.promises.length > 0; }
    get promiseCount() { return this.promises ? this.promises.length : 0; }
    get hasExecutions() { return this.executions && this.executions.length > 0; }
    get executionCount() { return this.executions ? this.executions.length : 0; }
}
