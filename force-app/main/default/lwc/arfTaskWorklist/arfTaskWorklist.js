import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getTaskFieldMetadata from '@salesforce/apex/ARF_WorklistController.getTaskFieldMetadata';
import getTasksDynamic from '@salesforce/apex/ARF_WorklistController.getTasksDynamic';
import massCloseTasks from '@salesforce/apex/ARF_WorklistController.massCloseTasks';
import completePhoneTask from '@salesforce/apex/ARF_WorklistController.completePhoneTask';

const BUILTIN_VIEWS = [
    { label: 'All Open Tasks', value: 'builtin_all_open' },
    { label: 'My Tasks', value: 'builtin_my_tasks' },
    { label: 'Email Tasks', value: 'builtin_email_tasks' },
    { label: 'Phone Tasks', value: 'builtin_phone_tasks' },
    { label: 'Overdue Tasks', value: 'builtin_overdue_tasks' }
];

const DEFAULT_COLUMNS = [
    { label: 'Subject', fieldName: 'Subject', type: 'text', sortable: true },
    { label: 'Account', fieldName: 'accountName', type: 'text', sortable: true },
    { label: 'Type', fieldName: 'ARF_Task_Type__c', type: 'text', sortable: true },
    { label: 'Priority', fieldName: 'Priority', type: 'text', sortable: true,
        cellAttributes: { class: { fieldName: 'priorityClass' } } },
    { label: 'Due Date', fieldName: 'ActivityDate', type: 'date', sortable: true,
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } },
    { label: 'Owner', fieldName: 'ownerName', type: 'text', sortable: true },
    { label: 'Status', fieldName: 'Status', type: 'text', sortable: true }
];

const ROW_ACTIONS = [
    { label: 'View Account', name: 'view_account' },
    { label: 'Log Call', name: 'log_call' },
    { label: 'Close Task', name: 'close_task' }
];

export default class ArfTaskWorklist extends NavigationMixin(LightningElement) {
    // Data
    @track tasks = [];
    @track columns = [];
    @track selectedRows = [];
    isLoading = true;

    // View state
    currentBuiltinView = 'all_open';
    currentFilters = [];
    currentSortField = 'ActivityDate';
    currentSortDirection = 'asc';
    searchText = '';

    // Field metadata
    availableFields = [];

    // Phone log modal
    showPhoneModal = false;
    phoneTaskId = null;
    phoneSubject = '';
    phoneBody = '';
    phoneDuration = 0;

    // Mass email/SMS modals
    showMassEmailModal = false;
    showMassSmsModal = false;

    get builtinViews() {
        return BUILTIN_VIEWS;
    }

    get hasSelectedRows() {
        return this.selectedRows.length > 0;
    }

    get selectedCount() {
        return this.selectedRows.length;
    }

    get hasEmailTasksSelected() {
        return this.selectedRows.some(id => {
            const task = this.tasks.find(t => t.Id === id);
            return task && task.ARF_Task_Type__c === 'Email';
        });
    }

    get hasSmsTasksSelected() {
        return this.selectedRows.some(id => {
            const task = this.tasks.find(t => t.Id === id);
            return task && task.ARF_Task_Type__c === 'SMS';
        });
    }

    get selectedTaskIds() {
        return this.selectedRows;
    }

    get taskCount() {
        return this.tasks.length;
    }

    connectedCallback() {
        this.loadFieldMetadata();
    }

    async loadFieldMetadata() {
        try {
            this.availableFields = await getTaskFieldMetadata();
            this.buildColumns();
            await this.loadTasks();
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
        const actions = [
            { label: 'View Account', name: 'view_account' },
            { label: 'Close Task', name: 'close_task' }
        ];
        if (row.ARF_Task_Type__c === 'Phone') {
            actions.splice(1, 0, { label: 'Log Call', name: 'log_call' });
        }
        doneCallback(actions);
    }

    async loadTasks() {
        this.isLoading = true;
        try {
            const filterJson = this.currentFilters.length > 0
                ? JSON.stringify(this.currentFilters) : null;

            const result = await getTasksDynamic({
                fields: null,
                filterConfigJson: filterJson,
                sortField: this.currentSortField,
                sortDirection: this.currentSortDirection,
                searchText: this.searchText || null,
                builtinView: this.currentBuiltinView
            });

            this.tasks = (result || []).map(task => ({
                ...task,
                accountName: task.What ? task.What.Name : '',
                ownerName: task.Owner ? task.Owner.Name : '',
                priorityClass: task.Priority === 'High' ? 'slds-text-color_error' : ''
            }));
        } catch (error) {
            this.showToast('Error loading tasks', this.extractError(error), 'error');
        } finally {
            this.isLoading = false;
        }
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
        this.currentSortField = detail.sortField || 'ActivityDate';
        this.currentSortDirection = detail.sortDirection || 'asc';
        this.loadTasks();
    }

    // === SEARCH ===

    handleSearchChange(event) {
        this.searchText = event.target.value;
    }

    handleSearchKeyup(event) {
        if (event.key === 'Enter') {
            this.loadTasks();
        }
    }

    handleClearSearch() {
        this.searchText = '';
        this.loadTasks();
    }

    // === SORT ===

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.currentSortField = fieldName === 'accountName' ? 'What.Name'
            : fieldName === 'ownerName' ? 'Owner.Name' : fieldName;
        this.currentSortDirection = sortDirection;
        this.loadTasks();
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
            case 'view_account':
                this.navigateToAccount(row.WhatId);
                break;
            case 'log_call':
                this.openPhoneModal(row);
                break;
            case 'close_task':
                this.closeSingleTask(row.Id);
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

    // === ACTION BAR ===

    handleRefresh() {
        this.selectedRows = [];
        this.loadTasks();
    }

    async handleCloseTasks() {
        if (this.selectedRows.length === 0) return;
        this.isLoading = true;
        try {
            await massCloseTasks({ taskIds: this.selectedRows });
            this.showToast('Success', `${this.selectedRows.length} task(s) closed`, 'success');
            this.selectedRows = [];
            await this.loadTasks();
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
            this.isLoading = false;
        }
    }

    handleSendEmail() {
        this.showMassEmailModal = true;
    }

    handleSendSms() {
        this.showMassSmsModal = true;
    }

    // === MASS EMAIL MODAL ===

    handleMassEmailClose() {
        this.showMassEmailModal = false;
    }

    handleMassEmailSave() {
        this.showMassEmailModal = false;
        this.selectedRows = [];
        this.loadTasks();
    }

    // === MASS SMS MODAL ===

    handleMassSmsClose() {
        this.showMassSmsModal = false;
    }

    handleMassSmsSave() {
        this.showMassSmsModal = false;
        this.selectedRows = [];
        this.loadTasks();
    }

    // === PHONE MODAL ===

    openPhoneModal(row) {
        this.phoneTaskId = row.Id;
        this.phoneSubject = row.Subject || 'Phone Call';
        this.phoneBody = '';
        this.phoneDuration = 0;
        this.showPhoneModal = true;
    }

    handlePhoneSubjectChange(event) {
        this.phoneSubject = event.detail.value;
    }

    handlePhoneBodyChange(event) {
        this.phoneBody = event.detail.value;
    }

    handlePhoneDurationChange(event) {
        this.phoneDuration = parseInt(event.detail.value, 10) || 0;
    }

    handlePhoneCancel() {
        this.showPhoneModal = false;
    }

    async handlePhoneSave() {
        this.isLoading = true;
        this.showPhoneModal = false;
        try {
            await completePhoneTask({
                taskId: this.phoneTaskId,
                subject: this.phoneSubject,
                body: this.phoneBody,
                durationSeconds: this.phoneDuration
            });
            this.showToast('Success', 'Call logged and task completed', 'success');
            await this.loadTasks();
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
            this.isLoading = false;
        }
    }

    async closeSingleTask(taskId) {
        this.isLoading = true;
        try {
            await massCloseTasks({ taskIds: [taskId] });
            this.showToast('Success', 'Task closed', 'success');
            await this.loadTasks();
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
            this.isLoading = false;
        }
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
