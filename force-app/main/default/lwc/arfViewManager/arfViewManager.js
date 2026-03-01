import { LightningElement, api, track } from 'lwc';
import getMyViews from '@salesforce/apex/ARF_SavedViewController.getMyViews';
import saveView from '@salesforce/apex/ARF_SavedViewController.saveView';
import deleteView from '@salesforce/apex/ARF_SavedViewController.deleteView';
import setDefaultView from '@salesforce/apex/ARF_SavedViewController.setDefaultView';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const BUILTIN_VIEWS = [
    { label: 'All Active', value: 'builtin_all' },
    { label: 'Past Due', value: 'builtin_pastDue' },
    { label: 'In Dispute', value: 'builtin_inDispute' }
];

const DEFAULT_COLUMNS = [
    'Document_Number__c', 'Invoice_Date__c', 'Due_Date__c', 'Amount__c',
    'Balance__c', 'Status__c', 'Days_Past_Due__c', 'PO_Number__c',
    'Reference__c', 'Has_Dispute__c'
];

// Operators by data type
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

export default class ArfViewManager extends LightningElement {
    @api objectName = 'ARF_Invoice__c';
    @api availableFields = [];
    @api builtinViews;

    // View state
    selectedViewValue = 'builtin_all';
    savedViews = [];
    _savedViewMap = {};

    // Column chooser
    showColumnChooser = false;
    selectedColumns = [...DEFAULT_COLUMNS];

    // Filter builder
    showFilterBuilder = false;
    @track filterRows = [];
    _filterRowCounter = 0;

    // Save dialog
    showSaveDialog = false;
    saveViewName = '';
    saveAsDefault = false;
    _editingViewId = null;

    connectedCallback() {
        this.loadSavedViews();
    }

    // ===== GETTERS =====

    get _builtinViewList() {
        return this.builtinViews && this.builtinViews.length > 0 ? this.builtinViews : BUILTIN_VIEWS;
    }

    get viewOptions() {
        const opts = [...this._builtinViewList];
        if (this.savedViews.length > 0) {
            opts.push({ label: '--- Saved Views ---', value: 'divider', disabled: true });
            for (const sv of this.savedViews) {
                const label = sv.Is_Default__c ? sv.View_Name__c + ' (Default)' : sv.View_Name__c;
                opts.push({ label: label, value: 'saved_' + sv.Id });
            }
        }
        return opts;
    }

    get allColumnOptions() {
        return this.availableFields.map(f => ({
            label: f.label,
            value: f.apiName
        }));
    }

    get fieldOptions() {
        return this.availableFields.map(f => ({
            label: f.label,
            value: f.apiName
        }));
    }

    get isBuiltinView() {
        return this.selectedViewValue.startsWith('builtin_');
    }

    get isSavedView() {
        return this.selectedViewValue.startsWith('saved_');
    }

    get activeViewId() {
        if (this.isSavedView) {
            return this.selectedViewValue.replace('saved_', '');
        }
        return null;
    }

    get hasFilters() {
        return this.filterRows.length > 0;
    }

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

    get columnsButtonLabel() {
        return `Columns (${this.selectedColumns.length})`;
    }

    get canDeleteView() {
        return this.isSavedView;
    }

    get canSetDefault() {
        return this.isSavedView;
    }

    // ===== DATA LOADING =====

    async loadSavedViews() {
        try {
            this.savedViews = await getMyViews({ objectName: this.objectName });
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
            // Silently fall back to built-in views
        }
    }

    // ===== VIEW SELECTION =====

    handleViewChange(e) {
        const val = e.detail.value;
        if (val === 'divider') return;
        this.selectedViewValue = val;

        if (val.startsWith('builtin_')) {
            const builtinKey = val.replace('builtin_', '');
            this.selectedColumns = [...DEFAULT_COLUMNS];
            this.filterRows = [];
            this._fireViewChange({
                viewType: 'builtin',
                builtinView: builtinKey,
                columns: DEFAULT_COLUMNS,
                filters: [],
                sortField: 'Due_Date__c',
                sortDirection: 'asc'
            });
        } else if (val.startsWith('saved_')) {
            const viewId = val.replace('saved_', '');
            const savedView = this._savedViewMap[viewId];
            if (savedView) {
                this._applyViewConfig(savedView);
            }
        }
    }

    _applyViewConfig(savedView) {
        // Parse columns
        try {
            this.selectedColumns = JSON.parse(savedView.Column_Config__c || '[]');
        } catch (e) {
            this.selectedColumns = [...DEFAULT_COLUMNS];
        }

        // Parse filters
        try {
            const parsed = JSON.parse(savedView.Filter_Config__c || '[]');
            this.filterRows = parsed.map((f, i) => this._enrichFilterRow({
                id: ++this._filterRowCounter,
                field: f.field,
                operator: f.operator,
                value: f.value,
                dataType: f.dataType
            }));
        } catch (e) {
            this.filterRows = [];
        }

        this._fireViewChange({
            viewType: 'saved',
            columns: this.selectedColumns,
            filters: this._getCleanFilters(),
            sortField: savedView.Sort_Field__c || 'Due_Date__c',
            sortDirection: savedView.Sort_Direction__c || 'asc'
        });
    }

    // ===== COLUMN CHOOSER =====

    handleOpenColumnChooser() {
        this.showColumnChooser = true;
    }

    handleCloseColumnChooser() {
        this.showColumnChooser = false;
    }

    handleColumnChange(e) {
        this.selectedColumns = e.detail.value;
    }

    handleApplyColumns() {
        this.showColumnChooser = false;
        this._fireCurrentViewChange();
    }

    // ===== FILTER BUILDER =====

    handleOpenFilterBuilder() {
        if (this.filterRows.length === 0) {
            this._addEmptyFilterRow();
        }
        this.showFilterBuilder = true;
    }

    handleCloseFilterBuilder() {
        this.showFilterBuilder = false;
    }

    handleAddFilter() {
        this._addEmptyFilterRow();
    }

    _addEmptyFilterRow() {
        this.filterRows = [...this.filterRows, this._enrichFilterRow({
            id: ++this._filterRowCounter,
            field: '',
            operator: '',
            value: '',
            dataType: ''
        })];
    }

    _enrichFilterRow(row) {
        const fieldMeta = this.availableFields.find(f => f.apiName === row.field);
        const dataType = fieldMeta ? fieldMeta.dataType : (row.dataType || '');
        const operatorOptions = OPERATORS_BY_TYPE[dataType] || [];

        return {
            ...row,
            dataType: dataType,
            operatorOptions: operatorOptions,
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
        this._fireCurrentViewChange();
    }

    handleClearFilters() {
        this.filterRows = [];
        this.showFilterBuilder = false;
        this._fireCurrentViewChange();
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

    // ===== SAVE / DELETE =====

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

    handleCloseSaveDialog() {
        this.showSaveDialog = false;
    }

    handleSaveViewNameChange(e) {
        this.saveViewName = e.target.value;
    }

    handleSaveAsDefaultChange(e) {
        this.saveAsDefault = e.target.checked;
    }

    async handleSaveView() {
        if (!this.saveViewName || !this.saveViewName.trim()) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Please enter a view name',
                variant: 'error'
            }));
            return;
        }

        const viewRecord = {
            sobjectType: 'ARF_Saved_View__c',
            View_Name__c: this.saveViewName.trim(),
            Object_Name__c: this.objectName,
            Column_Config__c: JSON.stringify(this.selectedColumns),
            Filter_Config__c: JSON.stringify(this._getCleanFilters()),
            Sort_Field__c: 'Due_Date__c',
            Sort_Direction__c: 'asc',
            Is_Default__c: this.saveAsDefault
        };

        if (this._editingViewId) {
            viewRecord.Id = this._editingViewId;
        }

        try {
            const saved = await saveView({ view: viewRecord });
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
            await deleteView({ viewId: this.activeViewId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Deleted',
                message: 'View deleted successfully',
                variant: 'success'
            }));
            this.selectedViewValue = 'builtin_all';
            this.selectedColumns = [...DEFAULT_COLUMNS];
            this.filterRows = [];
            await this.loadSavedViews();
            this._fireViewChange({
                viewType: 'builtin',
                builtinView: 'all',
                columns: DEFAULT_COLUMNS,
                filters: [],
                sortField: 'Due_Date__c',
                sortDirection: 'asc'
            });
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
            await setDefaultView({ viewId: this.activeViewId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Default view updated',
                variant: 'success'
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

    // ===== EVENT DISPATCH =====

    _fireCurrentViewChange() {
        if (this.isBuiltinView) {
            const builtinKey = this.selectedViewValue.replace('builtin_', '');
            this._fireViewChange({
                viewType: this.activeFilterCount > 0 || !this._arraysEqual(this.selectedColumns, DEFAULT_COLUMNS)
                    ? 'saved' : 'builtin',
                builtinView: builtinKey,
                columns: this.selectedColumns,
                filters: this._getCleanFilters(),
                sortField: 'Due_Date__c',
                sortDirection: 'asc'
            });
        } else {
            this._fireViewChange({
                viewType: 'saved',
                columns: this.selectedColumns,
                filters: this._getCleanFilters(),
                sortField: 'Due_Date__c',
                sortDirection: 'asc'
            });
        }
    }

    _fireViewChange(detail) {
        this.dispatchEvent(new CustomEvent('viewchange', { detail }));
    }

    _arraysEqual(a, b) {
        if (a.length !== b.length) return false;
        return a.every((v, i) => v === b[i]);
    }
}
