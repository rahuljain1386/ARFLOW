import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getWorklist from '@salesforce/apex/ARF_CollectionWorklistController.getWorklist';
import snoozeAccount from '@salesforce/apex/ARF_CollectionWorklistController.snoozeAccount';
import quickLogCall from '@salesforce/apex/ARF_CollectionWorklistController.quickLogCall';

const COLUMNS = [
    {
        label: 'Score', fieldName: 'priorityScore', type: 'number',
        typeAttributes: { maximumFractionDigits: 0 }, sortable: true,
        initialWidth: 80
    },
    {
        label: 'Account', fieldName: 'accountUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'accountName' }, target: '_self' },
        sortable: true
    },
    { label: 'Past Due', fieldName: 'pastDue', type: 'currency', sortable: true },
    { label: 'Total AR', fieldName: 'totalAR', type: 'currency', sortable: true },
    { label: 'Risk', fieldName: 'riskScore', type: 'number', sortable: true, initialWidth: 70 },
    { label: 'Max DPD', fieldName: 'maxDaysPastDue', type: 'number', sortable: true, initialWidth: 90 },
    { label: 'Last Contact', fieldName: 'lastContactDate', type: 'date', sortable: true },
    { label: 'Collector', fieldName: 'collectorName', type: 'text' },
    { label: 'Strategy', fieldName: 'collectionStrategy', type: 'text' },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'View Account', name: 'view' },
                { label: 'Log Call', name: 'log_call' },
                { label: 'Snooze 1 Day', name: 'snooze_1' },
                { label: 'Snooze 7 Days', name: 'snooze_7' }
            ]
        }
    }
];

export default class ArfCollectionWorklist extends NavigationMixin(LightningElement) {
    columns = COLUMNS;
    worklistData;
    error;
    isLoading = false;
    showAll = false;
    wiredResult;
    showCallModal = false;
    selectedAccountId = '';
    callSubject = '';
    callBody = '';
    callDuration = 0;
    sortedBy = 'priorityScore';
    sortedDirection = 'desc';

    @wire(getWorklist, { showAll: '$showAll' })
    wiredWorklist(result) {
        this.wiredResult = result;
        if (result.data) {
            this.worklistData = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.worklistData = undefined;
        }
    }

    get hasData() { return this.worklistData && this.worklistData.length > 0; }
    get recordCount() { return this.worklistData ? this.worklistData.length : 0; }
    get cardTitle() { return `Collection Worklist (${this.recordCount})`; }
    get toggleLabel() { return this.showAll ? 'Show My Accounts' : 'Show All Accounts'; }
    get toggleIcon() { return this.showAll ? 'utility:filterList' : 'utility:world'; }
    get noError() { return !this.error; }

    handleToggleView() { this.showAll = !this.showAll; }

    handleRefresh() { refreshApex(this.wiredResult); }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy = fieldName;
        this.sortedDirection = sortDirection;
        this.sortData(fieldName, sortDirection);
    }

    sortData(fieldName, direction) {
        const data = [...this.worklistData];
        data.sort((a, b) => {
            let valA = a[fieldName] || '';
            let valB = b[fieldName] || '';
            if (typeof valA === 'string') {
                valA = valA.toLowerCase();
                valB = (valB || '').toLowerCase();
            }
            let result = valA < valB ? -1 : valA > valB ? 1 : 0;
            return direction === 'asc' ? result : -result;
        });
        this.worklistData = data;
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        switch (action.name) {
            case 'view':
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: { recordId: row.accountId, objectApiName: 'Account', actionName: 'view' }
                });
                break;
            case 'log_call':
                this.selectedAccountId = row.accountId;
                this.callSubject = 'Collection Call - ' + row.accountName;
                this.showCallModal = true;
                break;
            case 'snooze_1':
                this.handleSnooze(row.accountId, 1);
                break;
            case 'snooze_7':
                this.handleSnooze(row.accountId, 7);
                break;
        }
    }

    async handleSnooze(accountId, days) {
        this.isLoading = true;
        try {
            await snoozeAccount({ accountId, snoozeDays: days });
            this.showToast('Success', `Account snoozed for ${days} day(s)`, 'success');
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Snooze failed', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleSaveCall() {
        this.isLoading = true;
        try {
            await quickLogCall({
                accountId: this.selectedAccountId,
                subject: this.callSubject,
                body: this.callBody,
                durationSeconds: parseInt(this.callDuration, 10) || 0
            });
            this.showToast('Success', 'Call logged successfully', 'success');
            this.showCallModal = false;
            this.resetCallForm();
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to log call', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCloseCallModal() {
        this.showCallModal = false;
        this.resetCallForm();
    }

    resetCallForm() {
        this.callSubject = '';
        this.callBody = '';
        this.callDuration = 0;
        this.selectedAccountId = '';
    }

    handleCallSubjectChange(event) { this.callSubject = event.detail.value; }
    handleCallBodyChange(event) { this.callBody = event.detail.value; }
    handleCallDurationChange(event) { this.callDuration = event.detail.value; }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
