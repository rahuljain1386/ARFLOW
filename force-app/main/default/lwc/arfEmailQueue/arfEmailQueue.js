import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getEmailQueueFieldMetadata from '@salesforce/apex/ARF_EmailQueueController.getEmailQueueFieldMetadata';
import getEmailQueueDynamic from '@salesforce/apex/ARF_EmailQueueController.getEmailQueueDynamic';
import markAsSpam from '@salesforce/apex/ARF_EmailQueueController.markAsSpam';

const BUILTIN_VIEWS = [
    { label: 'Unmatched Emails', value: 'builtin_unmatched' },
    { label: 'Needs Review', value: 'builtin_needs_review' },
    { label: 'All Inbound', value: 'builtin_all_inbound' },
    { label: 'AI Classified', value: 'builtin_ai_classified' }
];

const DEFAULT_COLUMNS = [
    { label: 'Subject', fieldName: 'Subject__c', type: 'text', sortable: true,
        cellAttributes: { class: { fieldName: 'subjectClass' } } },
    { label: 'From', fieldName: 'From_Address__c', type: 'text', sortable: true },
    { label: 'Account', fieldName: 'accountName', type: 'text', sortable: true },
    { label: 'Match Method', fieldName: 'Match_Method__c', type: 'text', sortable: true },
    { label: 'Confidence', fieldName: 'Match_Confidence__c', type: 'percent', sortable: true,
        typeAttributes: { maximumFractionDigits: 0 },
        cellAttributes: { class: { fieldName: 'confidenceClass' } } },
    { label: 'AI Intent', fieldName: 'AI_Intent__c', type: 'text', sortable: true },
    { label: 'Date', fieldName: 'Sent_Date__c', type: 'date', sortable: true,
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit',
            hour: '2-digit', minute: '2-digit' } },
    { label: 'Review', fieldName: 'Needs_Review__c', type: 'boolean', sortable: true }
];

export default class ArfEmailQueue extends NavigationMixin(LightningElement) {
    // Data
    @track emails = [];
    @track columns = [];
    @track selectedRows = [];
    isLoading = true;

    // View state
    currentBuiltinView = 'unmatched';
    currentFilters = [];
    currentSortField = 'Sent_Date__c';
    currentSortDirection = 'desc';
    searchText = '';

    // Field metadata
    availableFields = [];

    // Assign modal
    showAssignModal = false;
    assignCommunicationIds = [];
    assignIsBulk = false;

    get builtinViews() {
        return BUILTIN_VIEWS;
    }

    get hasSelectedRows() {
        return this.selectedRows.length > 0;
    }

    get selectedCount() {
        return this.selectedRows.length;
    }

    get emailCount() {
        return this.emails.length;
    }

    connectedCallback() {
        this.loadFieldMetadata();
    }

    async loadFieldMetadata() {
        try {
            this.availableFields = await getEmailQueueFieldMetadata();
            this.buildColumns();
            await this.loadEmails();
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
            this.isLoading = false;
        }
    }

    buildColumns() {
        this.columns = [
            ...DEFAULT_COLUMNS,
            {
                type: 'action',
                typeAttributes: { rowActions: this.getRowActions.bind(this) }
            }
        ];
    }

    getRowActions(row, doneCallback) {
        const actions = [];
        if (!row.Account__c) {
            actions.push({ label: 'Assign Account', name: 'assign_account' });
        }
        if (row.Account__c) {
            actions.push({ label: 'View Account', name: 'view_account' });
        }
        actions.push({ label: 'View Email', name: 'view_email' });
        actions.push({ label: 'Mark Spam', name: 'mark_spam' });
        doneCallback(actions);
    }

    async loadEmails() {
        this.isLoading = true;
        try {
            const filterJson = this.currentFilters.length > 0
                ? JSON.stringify(this.currentFilters) : null;

            const result = await getEmailQueueDynamic({
                fields: null,
                filterConfigJson: filterJson,
                sortField: this.currentSortField,
                sortDirection: this.currentSortDirection,
                searchText: this.searchText || null,
                builtinView: this.currentBuiltinView
            });

            this.emails = (result || []).map(comm => ({
                ...comm,
                accountName: comm.Account__r ? comm.Account__r.Name : '',
                // Confidence needs to be decimal for percent type (divide by 100)
                Match_Confidence__c: comm.Match_Confidence__c != null
                    ? comm.Match_Confidence__c / 100 : null,
                confidenceClass: this.getConfidenceClass(comm.Match_Confidence__c),
                subjectClass: comm.Needs_Review__c ? 'slds-text-color_error' : ''
            }));
        } catch (error) {
            this.showToast('Error loading emails', this.extractError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    getConfidenceClass(confidence) {
        if (confidence == null) return '';
        if (confidence >= 80) return 'slds-text-color_success';
        if (confidence >= 40) return 'slds-text-color_weak';
        return 'slds-text-color_error';
    }

    // === VIEW MANAGER EVENTS ===

    handleViewChange(event) {
        const detail = event.detail;
        if (detail.builtinView) {
            this.currentBuiltinView = detail.builtinView;
        } else {
            this.currentBuiltinView = null;
        }
        this.currentFilters = detail.filters || [];
        this.currentSortField = detail.sortField || 'Sent_Date__c';
        this.currentSortDirection = detail.sortDirection || 'desc';
        this.loadEmails();
    }

    // === SEARCH ===

    handleSearchChange(event) {
        this.searchText = event.target.value;
    }

    handleSearchKeyup(event) {
        if (event.key === 'Enter') {
            this.loadEmails();
        }
    }

    // === SORT ===

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.currentSortField = fieldName === 'accountName' ? 'Account__r.Name' : fieldName;
        this.currentSortDirection = sortDirection;
        this.loadEmails();
    }

    // === ROW SELECTION ===

    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows.map(row => row.Id);
    }

    // === ROW ACTIONS ===

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        switch (action.name) {
            case 'assign_account':
                this.openAssignModal([row.Id], false);
                break;
            case 'view_account':
                this.navigateToAccount(row.Account__c);
                break;
            case 'view_email':
                this.navigateToRecord(row.Id);
                break;
            case 'mark_spam':
                this.handleMarkSpamSingle(row.Id);
                break;
            default:
                break;
        }
    }

    navigateToAccount(accountId) {
        if (!accountId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    navigateToRecord(recordId) {
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: 'ARF_Communication__c',
                actionName: 'view'
            }
        });
    }

    // === ACTION BAR ===

    handleRefresh() {
        this.selectedRows = [];
        this.loadEmails();
    }

    handleAssignSelected() {
        if (this.selectedRows.length === 0) return;
        this.openAssignModal(this.selectedRows, true);
    }

    async handleMarkSpam() {
        if (this.selectedRows.length === 0) return;
        this.isLoading = true;
        try {
            await markAsSpam({ communicationIds: this.selectedRows });
            this.showToast('Success', `${this.selectedRows.length} email(s) marked as spam`, 'success');
            this.selectedRows = [];
            await this.loadEmails();
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
            this.isLoading = false;
        }
    }

    async handleMarkSpamSingle(commId) {
        this.isLoading = true;
        try {
            await markAsSpam({ communicationIds: [commId] });
            this.showToast('Success', 'Email marked as spam', 'success');
            await this.loadEmails();
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
            this.isLoading = false;
        }
    }

    // === ASSIGN MODAL ===

    openAssignModal(commIds, isBulk) {
        this.assignCommunicationIds = commIds;
        this.assignIsBulk = isBulk;
        this.showAssignModal = true;
    }

    handleAssignModalClose() {
        this.showAssignModal = false;
    }

    handleAssignModalSave() {
        this.showAssignModal = false;
        this.selectedRows = [];
        this.loadEmails();
    }

    // === UTILITIES ===

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unexpected error occurred';
    }
}
