import { LightningElement, api, track } from 'lwc';
import getInvoicesFiltered from '@salesforce/apex/ARF_Account360Controller.getInvoicesFiltered';
import getInvoicesDynamic from '@salesforce/apex/ARF_SavedViewController.getInvoicesDynamic';
import getInvoiceFieldMetadata from '@salesforce/apex/ARF_SavedViewController.getInvoiceFieldMetadata';
import getMyViews from '@salesforce/apex/ARF_SavedViewController.getMyViews';
import saveViewApex from '@salesforce/apex/ARF_SavedViewController.saveView';
import deleteViewApex from '@salesforce/apex/ARF_SavedViewController.deleteView';
import setDefaultViewApex from '@salesforce/apex/ARF_SavedViewController.setDefaultView';
import generateInvoiceCsv from '@salesforce/apex/ARF_TransactionActionController.generateInvoiceCsv';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Maps field API name → datatable column config
const ALL_COLUMNS_MAP = {
    Document_Number__c: {
        label: 'Invoice #', fieldName: 'invoiceUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'Document_Number__c' }, target: '_self' },
        sortable: true, initialWidth: 120, sortFieldName: 'Document_Number__c'
    },
    Invoice_Date__c: { label: 'Date', fieldName: 'Invoice_Date__c', type: 'date', sortable: true, initialWidth: 110 },
    Due_Date__c: { label: 'Due Date', fieldName: 'Due_Date__c', type: 'date', sortable: true, initialWidth: 110 },
    Amount__c: { label: 'Amount', fieldName: 'Amount__c', type: 'currency', sortable: true, initialWidth: 120 },
    Balance__c: { label: 'Balance', fieldName: 'Balance__c', type: 'currency', sortable: true, initialWidth: 120 },
    Status__c: { label: 'Status', fieldName: 'Status__c', type: 'text', initialWidth: 110 },
    Days_Past_Due__c: { label: 'DPD', fieldName: 'Days_Past_Due__c', type: 'number', sortable: true, initialWidth: 75 },
    Is_Overdue__c: { label: 'Overdue', fieldName: 'Is_Overdue__c', type: 'boolean', initialWidth: 80 },
    Has_Dispute__c: { label: 'Dispute', fieldName: 'Has_Dispute__c', type: 'boolean', initialWidth: 80 },
    Has_Promise__c: { label: 'P2P', fieldName: 'Has_Promise__c', type: 'boolean', initialWidth: 70 },
    Flags: { label: 'Flags', fieldName: 'flagsDisplay', type: 'text', initialWidth: 120 },
    PO_Number__c: { label: 'PO #', fieldName: 'PO_Number__c', type: 'text', initialWidth: 110 },
    Reference__c: { label: 'Ref', fieldName: 'Reference__c', type: 'text', initialWidth: 110 },
    Bill_To__c: { label: 'Bill To', fieldName: 'Bill_To__c', type: 'text', initialWidth: 130 },
    Ship_To__c: { label: 'Ship To', fieldName: 'Ship_To__c', type: 'text', initialWidth: 130 },
    ERP_ID__c: { label: 'ERP ID', fieldName: 'ERP_ID__c', type: 'text', initialWidth: 100 },
    ERP_Source__c: { label: 'ERP Source', fieldName: 'ERP_Source__c', type: 'text', initialWidth: 100 }
};

const DEFAULT_COLUMNS = [
    'Document_Number__c', 'Invoice_Date__c', 'Due_Date__c', 'Amount__c',
    'Balance__c', 'Status__c', 'Days_Past_Due__c', 'PO_Number__c',
    'Reference__c', 'Flags'
];

const BUILTIN_VIEWS = [
    { label: 'All Active', value: 'builtin_all' },
    { label: 'Past Due', value: 'builtin_pastDue' },
    { label: 'In Dispute', value: 'builtin_inDispute' }
];

const OPERATORS_BY_TYPE = {
    text: [
        { label: 'Equals', value: 'equals' },
        { label: 'Not Equals', value: 'notEquals' },
        { label: 'Contains', value: 'contains' }
    ],
    picklist: [
        { label: 'Equals', value: 'equals' },
        { label: 'Not Equals', value: 'notEquals' }
    ],
    currency: [
        { label: 'Equals', value: 'equals' },
        { label: 'Not Equals', value: 'notEquals' },
        { label: 'Greater Than', value: 'greaterThan' },
        { label: 'Less Than', value: 'lessThan' },
        { label: 'Greater or Equal', value: 'greaterOrEqual' },
        { label: 'Less or Equal', value: 'lessOrEqual' }
    ],
    number: [
        { label: 'Equals', value: 'equals' },
        { label: 'Not Equals', value: 'notEquals' },
        { label: 'Greater Than', value: 'greaterThan' },
        { label: 'Less Than', value: 'lessThan' },
        { label: 'Greater or Equal', value: 'greaterOrEqual' },
        { label: 'Less or Equal', value: 'lessOrEqual' }
    ],
    date: [
        { label: 'Equals', value: 'equals' },
        { label: 'Before', value: 'lessThan' },
        { label: 'After', value: 'greaterThan' },
        { label: 'On or Before', value: 'lessOrEqual' },
        { label: 'On or After', value: 'greaterOrEqual' }
    ],
    boolean: [
        { label: 'Equals', value: 'equals' }
    ]
};

const STATUS_OPTIONS = [
    { label: 'Open', value: 'Open' },
    { label: 'Partially Paid', value: 'Partially Paid' },
    { label: 'In Dispute', value: 'In Dispute' }
];

const PAGE_SIZE_OPTIONS = [
    { label: '25', value: '25' },
    { label: '50', value: '50' },
    { label: '100', value: '100' }
];

export default class ArfAccount360Transactions extends LightningElement {
    @api recordId;
    pageSizeOptions = PAGE_SIZE_OPTIONS;

    // Data
    allInvoices = [];
    error;
    isLoading = true;

    // Field metadata for column chooser & filter builder
    availableFields = [];

    // View management
    selectedViewValue = 'builtin_all';
    savedViews = [];
    _savedViewMap = {};

    // Active column selection
    selectedColumns = [...DEFAULT_COLUMNS];

    // Filters
    searchText = '';
    _searchTimeout;
    @track filterRows = [];
    _filterRowCounter = 0;

    // Selection
    selectedRows = [];
    _selectedInvoiceData = [];

    // Pagination
    pageSize = 50;
    currentPage = 1;

    // Sort
    sortedBy;
    sortDirection = 'asc';
    _sortField = 'Due_Date__c';

    // Modals
    showNoteModal = false;
    showDisputeModal = false;
    showPromiseModal = false;
    showContactModal = false;
    showColumnChooser = false;
    showFilterBuilder = false;
    showSaveDialog = false;

    // Save dialog state
    saveViewName = '';
    saveAsDefault = false;
    _editingViewId = null;

    connectedCallback() {
        this.loadFieldMetadata();
        this.loadSavedViews();
        this.loadInvoices();
    }

    // ===== FIELD METADATA =====

    async loadFieldMetadata() {
        try {
            this.availableFields = await getInvoiceFieldMetadata();
        } catch (err) {
            // Non-critical — column chooser / filters degrade gracefully
        }
    }

    // ===== VIEW MANAGEMENT =====

    async loadSavedViews() {
        try {
            this.savedViews = await getMyViews({ objectName: 'ARF_Invoice__c' });
            this._savedViewMap = {};
            for (const sv of this.savedViews) {
                this._savedViewMap[sv.Id] = sv;
            }
            // Auto-select default view if exists
            const defaultView = this.savedViews.find(v => v.Is_Default__c);
            if (defaultView) {
                this.selectedViewValue = 'saved_' + defaultView.Id;
                this._applyViewConfig(defaultView);
            }
        } catch (err) {
            // Fall back to built-in views silently
        }
    }

    get viewOptions() {
        const opts = [...BUILTIN_VIEWS];
        if (this.savedViews.length > 0) {
            opts.push({ label: '── Saved Views ──', value: 'divider', disabled: true });
            for (const sv of this.savedViews) {
                const label = sv.Is_Default__c ? sv.View_Name__c + ' ★' : sv.View_Name__c;
                opts.push({ label, value: 'saved_' + sv.Id });
            }
        }
        return opts;
    }

    get isBuiltinView() { return this.selectedViewValue.startsWith('builtin_'); }
    get isSavedView() { return this.selectedViewValue.startsWith('saved_'); }
    get activeViewId() {
        return this.isSavedView ? this.selectedViewValue.replace('saved_', '') : null;
    }
    get canDeleteView() { return this.isSavedView; }

    handleViewSelectorChange(e) {
        const val = e.detail.value;
        if (val === 'divider') return;
        this.selectedViewValue = val;

        if (val.startsWith('builtin_')) {
            this.selectedColumns = [...DEFAULT_COLUMNS];
            this.filterRows = [];
            this.loadInvoices();
        } else if (val.startsWith('saved_')) {
            const viewId = val.replace('saved_', '');
            const savedView = this._savedViewMap[viewId];
            if (savedView) {
                this._applyViewConfig(savedView);
            }
        }
    }

    _applyViewConfig(savedView) {
        try {
            this.selectedColumns = JSON.parse(savedView.Column_Config__c || '[]');
            if (this.selectedColumns.length === 0) this.selectedColumns = [...DEFAULT_COLUMNS];
        } catch (e) {
            this.selectedColumns = [...DEFAULT_COLUMNS];
        }

        try {
            const parsed = JSON.parse(savedView.Filter_Config__c || '[]');
            this.filterRows = parsed.map(f => this._enrichFilterRow({
                id: ++this._filterRowCounter,
                field: f.field,
                operator: f.operator,
                value: f.value,
                dataType: f.dataType
            }));
        } catch (e) {
            this.filterRows = [];
        }

        this._sortField = savedView.Sort_Field__c || 'Due_Date__c';
        this.sortDirection = savedView.Sort_Direction__c || 'asc';
        this.loadInvoices();
    }

    // ===== DYNAMIC COLUMNS =====

    get columns() {
        return this.selectedColumns
            .filter(fieldName => ALL_COLUMNS_MAP[fieldName])
            .map(fieldName => ALL_COLUMNS_MAP[fieldName]);
    }

    get allColumnOptions() {
        return this.availableFields.map(f => ({
            label: f.label,
            value: f.apiName
        }));
    }

    get columnsButtonLabel() {
        return `Columns (${this.selectedColumns.length})`;
    }

    // ===== FILTER BUILDER =====

    get fieldOptions() {
        return this.availableFields.map(f => ({
            label: f.label,
            value: f.apiName
        }));
    }

    get hasFilters() { return this.filterRows.length > 0; }
    get activeFilterCount() {
        return this.filterRows.filter(r => r.field && r.operator && r.value).length;
    }
    get filterButtonLabel() {
        const count = this.activeFilterCount;
        return count > 0 ? `Filters (${count})` : 'Filters';
    }
    get filterButtonVariant() {
        return this.activeFilterCount > 0 ? 'brand' : 'neutral';
    }

    _enrichFilterRow(row) {
        const fieldMeta = this.availableFields.find(f => f.apiName === row.field);
        const dataType = fieldMeta ? fieldMeta.dataType : (row.dataType || '');
        const operatorOptions = OPERATORS_BY_TYPE[dataType] || [];

        return {
            ...row,
            dataType,
            operatorOptions,
            isText: dataType === 'text',
            isNumber: dataType === 'currency' || dataType === 'number',
            isDate: dataType === 'date',
            isBoolean: dataType === 'boolean',
            isPicklist: dataType === 'picklist',
            statusOptions: STATUS_OPTIONS,
            booleanOptions: [
                { label: 'True', value: 'true' },
                { label: 'False', value: 'false' }
            ]
        };
    }

    _getCleanFilters() {
        return this.filterRows
            .filter(r => r.field && r.operator && r.value)
            .map(r => ({
                field: r.field,
                operator: r.operator,
                value: r.value,
                dataType: r.dataType
            }));
    }

    // ===== DATA LOADING =====

    async loadInvoices() {
        this.isLoading = true;
        try {
            let data;
            const cleanFilters = this._getCleanFilters();
            const hasCustomFilters = cleanFilters.length > 0;
            const hasCustomColumns = !this._arraysEqual(this.selectedColumns, DEFAULT_COLUMNS);

            if (this.isBuiltinView && !hasCustomFilters && !hasCustomColumns) {
                // Use the original fast path for built-in views
                const builtinKey = this.selectedViewValue.replace('builtin_', '');
                data = await getInvoicesFiltered({
                    accountId: this.recordId,
                    viewFilter: builtinKey,
                    agingBucket: 'all',
                    searchText: this.searchText
                });
            } else {
                // Use dynamic query for saved views or custom filters/columns
                data = await getInvoicesDynamic({
                    accountId: this.recordId,
                    fields: this.selectedColumns,
                    filterConfigJson: hasCustomFilters ? JSON.stringify(cleanFilters) : null,
                    sortField: this._sortField || 'Due_Date__c',
                    sortDirection: this.sortDirection || 'asc',
                    searchText: this.searchText
                });
            }

            this.allInvoices = data.map(inv => ({
                ...inv,
                invoiceUrl: '/' + inv.Id,
                flagsDisplay: this._computeFlags(inv)
            }));
            this.error = undefined;
            this.currentPage = 1;
            this.selectedRows = [];
            this._selectedInvoiceData = [];
        } catch (err) {
            this.error = err;
            this.allInvoices = [];
        } finally {
            this.isLoading = false;
        }
    }

    // ===== DATA GETTERS =====

    get hasData() { return this.allInvoices && this.allInvoices.length > 0; }
    get noError() { return !this.error; }
    get totalRecords() { return this.allInvoices.length; }
    get totalPages() { return Math.ceil(this.totalRecords / this.pageSize) || 1; }
    get cardTitle() { return `Transactions (${this.totalRecords})`; }

    get pagedData() {
        const start = (this.currentPage - 1) * this.pageSize;
        return this.allInvoices.slice(start, start + this.pageSize);
    }
    get pageInfo() {
        if (this.totalRecords === 0) return '0 of 0';
        const start = ((this.currentPage - 1) * this.pageSize) + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.totalRecords);
        return `${start}-${end} of ${this.totalRecords}`;
    }
    get isPrevDisabled() { return this.currentPage <= 1; }
    get isNextDisabled() { return this.currentPage >= this.totalPages; }

    get selectedCount() { return this._selectedInvoiceData.length; }
    get hasSelection() { return this.selectedCount > 0; }
    get hasNoSelection() { return this.selectedCount === 0; }
    get hasNoData() { return !this.allInvoices || this.allInvoices.length === 0; }
    get pageSizeStr() { return String(this.pageSize); }
    get selectedBalance() {
        return this._selectedInvoiceData.reduce((sum, inv) => sum + (inv.Balance__c || 0), 0);
    }
    get formattedSelectedBalance() {
        return '$' + this.selectedBalance.toLocaleString('en-US', { minimumFractionDigits: 2 });
    }
    get selectionSummary() {
        return `Selected: ${this.selectedCount} | Balance: ${this.formattedSelectedBalance}`;
    }

    // ===== SEARCH HANDLER =====

    handleSearchChange(e) {
        const val = e.target.value;
        clearTimeout(this._searchTimeout);
        this._searchTimeout = setTimeout(() => {
            this.searchText = val;
            this.loadInvoices();
        }, 400);
    }

    // ===== SELECTION HANDLERS =====

    handleRowSelection(e) {
        const selectedIds = e.detail.selectedRows.map(r => r.Id);
        this.selectedRows = selectedIds;
        this._selectedInvoiceData = this.allInvoices.filter(inv => selectedIds.includes(inv.Id));
    }

    handleSelectPage() {
        const pageIds = this.pagedData.map(inv => inv.Id);
        // Merge with existing selections from other pages
        const existingOtherPageIds = this.selectedRows.filter(id => !pageIds.includes(id));
        const allSelected = [...existingOtherPageIds, ...pageIds];
        this.selectedRows = allSelected;
        this._selectedInvoiceData = this.allInvoices.filter(inv => allSelected.includes(inv.Id));
    }

    handleSelectAll() {
        const allIds = this.allInvoices.map(inv => inv.Id);
        this.selectedRows = allIds;
        this._selectedInvoiceData = [...this.allInvoices];
    }

    handleClearSelection() {
        this.selectedRows = [];
        this._selectedInvoiceData = [];
    }

    // ===== PAGINATION =====

    handlePageSizeChange(e) {
        this.pageSize = parseInt(e.detail.value, 10);
        this.currentPage = 1;
    }
    handlePrevPage() {
        if (this.currentPage > 1) this.currentPage--;
    }
    handleNextPage() {
        if (this.currentPage < this.totalPages) this.currentPage++;
    }

    // ===== SORT =====

    handleSort(e) {
        const fieldName = e.detail.fieldName;
        this.sortDirection = e.detail.sortDirection;
        this.sortedBy = fieldName;

        // Resolve actual sort field (for URL columns)
        const colConfig = Object.values(ALL_COLUMNS_MAP).find(c => c.fieldName === fieldName);
        this._sortField = (colConfig && colConfig.sortFieldName) ? colConfig.sortFieldName : fieldName;

        const dir = this.sortDirection === 'asc' ? 1 : -1;
        const sortKey = this._sortField;
        this.allInvoices = [...this.allInvoices].sort((a, b) => {
            let valA = a[sortKey] || '';
            let valB = b[sortKey] || '';
            if (typeof valA === 'string') valA = valA.toLowerCase();
            if (typeof valB === 'string') valB = valB.toLowerCase();
            if (valA < valB) return -1 * dir;
            if (valA > valB) return 1 * dir;
            return 0;
        });
    }

    // ===== COLUMN CHOOSER =====

    handleOpenColumnChooser() { this.showColumnChooser = true; }
    handleCloseColumnChooser() { this.showColumnChooser = false; }

    handleColumnChange(e) {
        this.selectedColumns = e.detail.value;
    }

    handleApplyColumns() {
        this.showColumnChooser = false;
        this.loadInvoices();
    }

    // ===== FILTER BUILDER =====

    handleOpenFilterBuilder() {
        if (this.filterRows.length === 0) {
            this._addEmptyFilterRow();
        }
        this.showFilterBuilder = true;
    }
    handleCloseFilterBuilder() { this.showFilterBuilder = false; }

    handleAddFilter() { this._addEmptyFilterRow(); }

    _addEmptyFilterRow() {
        this.filterRows = [...this.filterRows, this._enrichFilterRow({
            id: ++this._filterRowCounter,
            field: '',
            operator: '',
            value: '',
            dataType: ''
        })];
    }

    handleFilterFieldChange(e) {
        const rowId = parseInt(e.currentTarget.dataset.rowId, 10);
        const newField = e.detail.value;
        const fieldMeta = this.availableFields.find(f => f.apiName === newField);
        this.filterRows = this.filterRows.map(row => {
            if (row.id === rowId) {
                return this._enrichFilterRow({
                    ...row,
                    field: newField,
                    dataType: fieldMeta ? fieldMeta.dataType : '',
                    operator: '',
                    value: ''
                });
            }
            return row;
        });
    }

    handleFilterOperatorChange(e) {
        const rowId = parseInt(e.currentTarget.dataset.rowId, 10);
        this.filterRows = this.filterRows.map(row => {
            if (row.id === rowId) {
                return { ...row, operator: e.detail.value };
            }
            return row;
        });
    }

    handleFilterValueChange(e) {
        const rowId = parseInt(e.currentTarget.dataset.rowId, 10);
        const val = e.detail ? e.detail.value : e.target.value;
        this.filterRows = this.filterRows.map(row => {
            if (row.id === rowId) {
                return { ...row, value: val };
            }
            return row;
        });
    }

    handleRemoveFilter(e) {
        const rowId = parseInt(e.currentTarget.dataset.rowId, 10);
        this.filterRows = this.filterRows.filter(row => row.id !== rowId);
    }

    handleApplyFilters() {
        this.showFilterBuilder = false;
        this.loadInvoices();
    }

    handleClearFilters() {
        this.filterRows = [];
        this.showFilterBuilder = false;
        this.loadInvoices();
    }

    // ===== SAVE / DELETE / DEFAULT VIEW =====

    handleOpenSaveDialog() {
        if (this.isSavedView) {
            const sv = this._savedViewMap[this.activeViewId];
            this.saveViewName = sv ? sv.View_Name__c : '';
            this._editingViewId = this.activeViewId;
        } else {
            this.saveViewName = '';
            this._editingViewId = null;
        }
        this.saveAsDefault = false;
        this.showSaveDialog = true;
    }
    handleCloseSaveDialog() { this.showSaveDialog = false; }
    handleSaveViewNameChange(e) { this.saveViewName = e.target.value; }
    handleSaveAsDefaultChange(e) { this.saveAsDefault = e.target.checked; }

    async handleSaveView() {
        if (!this.saveViewName || !this.saveViewName.trim()) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error', message: 'Please enter a view name', variant: 'error'
            }));
            return;
        }

        const viewRecord = {
            sobjectType: 'ARF_Saved_View__c',
            View_Name__c: this.saveViewName.trim(),
            Object_Name__c: 'ARF_Invoice__c',
            Column_Config__c: JSON.stringify(this.selectedColumns),
            Filter_Config__c: JSON.stringify(this._getCleanFilters()),
            Sort_Field__c: this._sortField || 'Due_Date__c',
            Sort_Direction__c: this.sortDirection || 'asc',
            Is_Default__c: this.saveAsDefault
        };

        if (this._editingViewId) {
            viewRecord.Id = this._editingViewId;
        }

        try {
            const saved = await saveViewApex({ view: viewRecord });
            this.showSaveDialog = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: `View "${this.saveViewName}" saved`,
                variant: 'success'
            }));
            await this.loadSavedViews();
            this.selectedViewValue = 'saved_' + saved.Id;
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error saving view',
                message: err.body ? err.body.message : err.message,
                variant: 'error'
            }));
        }
    }

    async handleDeleteView() {
        if (!this.activeViewId) return;
        try {
            await deleteViewApex({ viewId: this.activeViewId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Deleted', message: 'View deleted', variant: 'success'
            }));
            this.selectedViewValue = 'builtin_all';
            this.selectedColumns = [...DEFAULT_COLUMNS];
            this.filterRows = [];
            await this.loadSavedViews();
            this.loadInvoices();
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err.body ? err.body.message : err.message,
                variant: 'error'
            }));
        }
    }

    async handleSetDefault() {
        if (!this.activeViewId) return;
        try {
            await setDefaultViewApex({ viewId: this.activeViewId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success', message: 'Default view updated', variant: 'success'
            }));
            await this.loadSavedViews();
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err.body ? err.body.message : err.message,
                variant: 'error'
            }));
        }
    }

    // ===== ACTION HANDLERS =====

    handleAddNotes() { this.showNoteModal = true; }
    handleCreateDisputes() { this.showDisputeModal = true; }
    handlePromiseToPay() { this.showPromiseModal = true; }
    handleContactCustomer() { this.showContactModal = true; }

    handleModalClose() {
        this.showNoteModal = false;
        this.showDisputeModal = false;
        this.showPromiseModal = false;
        this.showContactModal = false;
    }

    handleModalSave() {
        this.showNoteModal = false;
        this.showDisputeModal = false;
        this.showPromiseModal = false;
        this.showContactModal = false;
        this.loadInvoices();
        this.dispatchEvent(new CustomEvent('recordcreated', { bubbles: true, composed: true }));
    }

    // ===== EXPORT =====

    async handleExportSelected() {
        if (this._selectedInvoiceData.length === 0) return;
        try {
            const invoiceIds = this._selectedInvoiceData.map(inv => inv.Id);
            const base64 = await generateInvoiceCsv({
                accountId: this.recordId,
                invoiceIds
            });
            this._downloadCsv(base64, 'Selected_Invoices.csv');
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Export Error',
                message: err.body ? err.body.message : err.message,
                variant: 'error'
            }));
        }
    }

    async handleExportAll() {
        if (this.allInvoices.length === 0) return;
        try {
            const invoiceIds = this.allInvoices.map(inv => inv.Id);
            const base64 = await generateInvoiceCsv({
                accountId: this.recordId,
                invoiceIds
            });
            this._downloadCsv(base64, 'All_Invoices.csv');
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Export Error',
                message: err.body ? err.body.message : err.message,
                variant: 'error'
            }));
        }
    }

    _downloadCsv(base64Data, filename) {
        const byteChars = atob(base64Data);
        const byteArray = new Uint8Array(byteChars.length);
        for (let i = 0; i < byteChars.length; i++) {
            byteArray[i] = byteChars.charCodeAt(i);
        }
        const blob = new Blob([byteArray], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        a.click();
        URL.revokeObjectURL(url);
    }

    // ===== UTILITIES =====

    _computeFlags(inv) {
        const flags = [];
        if (inv.Has_Dispute__c) flags.push('\u{1F534} Dispute');
        if (inv.Has_Promise__c) {
            if (inv.Promise_Status__c === 'Broken') {
                flags.push('\u{1F7E1} Broken');
            } else {
                flags.push('\u{1F535} Promise');
            }
        }
        return flags.length > 0 ? flags.join(' | ') : '\u2014';
    }

    _arraysEqual(a, b) {
        if (!a || !b || a.length !== b.length) return false;
        return a.every((v, i) => v === b[i]);
    }
}
