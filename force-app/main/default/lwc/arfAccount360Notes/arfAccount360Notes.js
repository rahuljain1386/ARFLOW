import { LightningElement, api } from 'lwc';
import getNotes from '@salesforce/apex/ARF_Account360Controller.getNotes';

export default class ArfAccount360Notes extends LightningElement {
    @api recordId;
    pinnedNotes = [];
    unpinnedNotes = [];
    error;

    _refreshKey = 0;
    @api
    get refreshKey() { return this._refreshKey; }
    set refreshKey(value) {
        this._refreshKey = value;
        if (this.recordId) {
            this.loadNotes();
        }
    }

    connectedCallback() {
        this.loadNotes();
    }

    async loadNotes() {
        try {
            const data = await getNotes({ accountId: this.recordId });
            const mapNote = n => ({
                ...n,
                noteUrl: '/' + n.Id,
                authorName: n.CreatedBy ? n.CreatedBy.Name : '',
                truncatedBody: n.Body__c ? n.Body__c.substring(0, 300) : '',
                invoiceRef: n.Invoice__r ? n.Invoice__r.Document_Number__c : ''
            });
            this.pinnedNotes = data.filter(n => n.Is_Pinned__c).map(mapNote);
            this.unpinnedNotes = data.filter(n => !n.Is_Pinned__c).map(mapNote);
            this.error = undefined;
        } catch (error) {
            this.error = error;
            this.pinnedNotes = [];
            this.unpinnedNotes = [];
        }
    }

    get hasPinnedNotes() { return this.pinnedNotes.length > 0; }
    get hasUnpinnedNotes() { return this.unpinnedNotes.length > 0; }
    get hasAnyNotes() { return this.hasPinnedNotes || this.hasUnpinnedNotes; }
    get totalCount() { return this.pinnedNotes.length + this.unpinnedNotes.length; }
    get cardTitle() { return `Notes (${this.totalCount})`; }
}
