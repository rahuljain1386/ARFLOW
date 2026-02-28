import { LightningElement, api, wire } from 'lwc';
import { updateRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAccountSummary from '@salesforce/apex/ARF_Account360Controller.getAccountSummary';
import getAgingSummary from '@salesforce/apex/ARF_Account360Controller.getAgingSummary';
import STICKY_NOTE_FIELD from '@salesforce/schema/Account.ARF_Sticky_Note__c';
import ID_FIELD from '@salesforce/schema/Account.Id';

export default class ArfAccount360Header extends LightningElement {
    @api recordId;
    account;
    aging;
    error;
    _wiredResult;
    _wiredAging;

    isEditingNote = false;
    editNoteValue = '';

    @wire(getAccountSummary, { accountId: '$recordId' })
    wiredAccount(result) {
        this._wiredResult = result;
        if (result.data) {
            this.account = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.account = undefined;
        }
    }

    @wire(getAgingSummary, { accountId: '$recordId' })
    wiredAging(result) {
        this._wiredAging = result;
        if (result.data) {
            this.aging = result.data;
        }
    }

    // === Account getters ===
    get hasAccount() { return !!this.account; }
    get accountName() { return this.account?.Name || ''; }
    get totalAR() { return this.account?.ARF_Total_AR__c || 0; }
    get pastDue() { return this.account?.ARF_Past_Due__c || 0; }
    get inDispute() { return this.account?.ARF_In_Dispute__c || 0; }
    get promised() { return this.account?.ARF_Promised_Amount__c || 0; }
    get creditLimit() { return this.account?.ARF_Credit_Limit__c || 0; }
    get riskScore() { return this.account?.ARF_Risk_Score__c || 0; }
    get dso() { return this.account?.ARF_DSO__c || 0; }
    get avgDaysToPay() { return this.account?.ARF_Avg_Days_To_Pay__c || 0; }
    get availableCredit() { return this.account?.ARF_Available_Credit__c || 0; }
    get openInvoiceCount() { return this.account?.ARF_Open_Invoice_Count__c || 0; }
    get overdueInvoiceCount() { return this.account?.ARF_Overdue_Invoice_Count__c || 0; }
    get openDisputeCount() { return this.account?.ARF_Open_Dispute_Count__c || 0; }
    get collectorName() { return this.account?.ARF_Assigned_Collector__r?.Name || 'Unassigned'; }
    get strategy() { return this.account?.ARF_Collection_Strategy__c || 'None'; }
    get stopStatus() { return this.account?.ARF_Stop_Status__c || ''; }
    get hasStopStatus() { return !!this.stopStatus; }
    get lastContactDate() { return this.account?.ARF_Last_Contact_Date__c; }
    get lastPaymentDate() { return this.account?.ARF_Last_Payment_Date__c; }

    // === Risk getters ===
    get riskLabel() {
        const s = this.riskScore;
        if (s >= 70) return 'HIGH';
        if (s >= 40) return 'MEDIUM';
        return 'LOW';
    }

    get riskBadgeClass() {
        const s = this.riskScore;
        if (s >= 70) return 'risk-badge risk-high';
        if (s >= 40) return 'risk-badge risk-medium';
        return 'risk-badge risk-low';
    }

    get riskDots() {
        const s = this.riskScore;
        const level = s >= 70 ? 3 : s >= 40 ? 2 : 1;
        const color = s >= 70 ? 'dot-red' : s >= 40 ? 'dot-yellow' : 'dot-green';
        return [1, 2, 3].map(i => ({
            key: i,
            class: `risk-dot ${i <= level ? color : 'dot-empty'}`
        }));
    }

    // === Credit utilization ===
    get creditUsed() {
        if (!this.creditLimit) return 0;
        return this.totalAR;
    }

    get creditUtilPct() {
        if (!this.creditLimit) return 0;
        return Math.min(Math.round((this.creditUsed / this.creditLimit) * 100), 100);
    }

    get creditBarStyle() {
        return `width: ${this.creditUtilPct}%`;
    }

    get creditBarClass() {
        const pct = this.creditUtilPct;
        if (pct > 80) return 'credit-fill credit-red';
        if (pct > 50) return 'credit-fill credit-yellow';
        return 'credit-fill credit-green';
    }

    get creditUsedFormatted() { return this.creditUsed; }
    get creditLimitFormatted() { return this.creditLimit; }

    // === Aging breakdown ===
    get hasAging() { return !!this.aging; }

    get agingTotal() {
        if (!this.aging) return 0;
        return Object.values(this.aging).reduce((sum, v) => sum + (v || 0), 0);
    }

    get agingBuckets() {
        if (!this.aging || !this.agingTotal) return [];
        const total = this.agingTotal;
        const buckets = [
            { key: 'current', label: 'Current', amount: this.aging['current'] || 0, colorClass: 'aging-current' },
            { key: '1-30', label: '1-30', amount: this.aging['1-30'] || 0, colorClass: 'aging-1-30' },
            { key: '31-60', label: '31-60', amount: this.aging['31-60'] || 0, colorClass: 'aging-31-60' },
            { key: '61-90', label: '61-90', amount: this.aging['61-90'] || 0, colorClass: 'aging-61-90' },
            { key: '90+', label: '90+', amount: this.aging['90+'] || 0, colorClass: 'aging-90-plus' }
        ];
        return buckets.map(b => ({
            ...b,
            pct: Math.round((b.amount / total) * 100),
            style: `width: ${Math.max((b.amount / total) * 100, b.amount > 0 ? 2 : 0)}%`,
            hasAmount: b.amount > 0
        }));
    }

    // === Sticky note ===
    get stickyNote() { return this.account?.ARF_Sticky_Note__c || ''; }
    get hasStickyNote() { return !!this.stickyNote; }
    get isNotEditing() { return !this.isEditingNote; }

    get stickyNoteClass() {
        return this.hasStickyNote
            ? 'sticky-note sticky-note_filled'
            : 'sticky-note sticky-note_empty';
    }

    handleEditNote() {
        this.editNoteValue = this.stickyNote;
        this.isEditingNote = true;
    }

    handleNoteInputChange(e) {
        this.editNoteValue = e.detail.value;
    }

    handleCancelNote() {
        this.isEditingNote = false;
        this.editNoteValue = '';
    }

    async handleSaveNote() {
        const fields = {};
        fields[ID_FIELD.fieldApiName] = this.recordId;
        fields[STICKY_NOTE_FIELD.fieldApiName] = this.editNoteValue;

        try {
            await updateRecord({ fields });
            this.isEditingNote = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Saved', message: 'Note updated', variant: 'success'
            }));
            await refreshApex(this._wiredResult);
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error saving note',
                message: err.body ? err.body.message : err.message,
                variant: 'error'
            }));
        }
    }

    // === Action buttons ===
    handleEmail() {
        this.dispatchEvent(new CustomEvent('quickaction', { detail: { actionType: 'Email' } }));
    }
    handleSMS() {
        this.dispatchEvent(new CustomEvent('quickaction', { detail: { actionType: 'SMS' } }));
    }
    handleCall() {
        this.dispatchEvent(new CustomEvent('quickaction', { detail: { actionType: 'Call' } }));
    }
    handleNote() {
        this.dispatchEvent(new CustomEvent('quickaction', { detail: { actionType: 'Note' } }));
    }
    handleDispute() {
        this.dispatchEvent(new CustomEvent('quickaction', { detail: { actionType: 'Dispute' } }));
    }
    handlePromiseToPay() {
        this.dispatchEvent(new CustomEvent('quickaction', { detail: { actionType: 'PromiseToPay' } }));
    }
}
