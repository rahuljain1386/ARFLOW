import { LightningElement, track } from 'lwc';
import parseCSV from '@salesforce/apex/ARF_BulkImportController.parseCSV';
import executeImport from '@salesforce/apex/ARF_BulkImportController.executeImport';
import getCSVTemplate from '@salesforce/apex/ARF_BulkImportController.getCSVTemplate';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ArfBulkImport extends LightningElement {
    // ─── State ───
    currentStep = '1';
    importType = '';
    csvContent = '';
    pastedCSV = '';
    fileName = '';
    isDragOver = false;
    isLoading = false;
    isImporting = false;

    @track previewData = {};
    @track importResult = {};

    // ═══════════ Step Computed Properties ═══════════

    get isStep1() { return this.currentStep === '1'; }
    get isStep2() { return this.currentStep === '2'; }
    get isStep3() { return this.currentStep === '3'; }
    get isStep4() { return this.currentStep === '4'; }
    get isStep5() { return this.currentStep === '5'; }

    get importTypeLower() {
        return this.importType ? this.importType.toLowerCase() : '';
    }

    get columnCount() {
        return this.previewData?.columns?.length || 0;
    }

    // ─── Navigation ───

    get showBackButton() {
        const step = parseInt(this.currentStep, 10);
        return step > 1 && step < 5;
    }

    get showNextButton() {
        const step = parseInt(this.currentStep, 10);
        return step >= 1 && step <= 3;
    }

    get nextButtonLabel() {
        if (this.currentStep === '3') return 'Continue to Import';
        return 'Next';
    }

    get isNextDisabled() {
        if (this.currentStep === '1') return !this.importType;
        if (this.currentStep === '2') return !this.csvContent && !this.pastedCSV;
        if (this.currentStep === '3') return this.hasPreviewErrors || this.isLoading;
        return false;
    }

    // ─── Card Classes ───

    get invoiceCardClass() {
        return this.importType === 'Invoice' ? 'type-card-selected' : 'type-card';
    }

    get paymentCardClass() {
        return this.importType === 'Payment' ? 'type-card-selected' : 'type-card';
    }

    get dropzoneClass() {
        return this.isDragOver ? 'dropzone-active' : 'dropzone';
    }

    // ─── Preview / Result Checks ───

    get hasPreviewErrors() {
        return this.previewData?.errors?.length > 0;
    }

    get hasPreviewWarnings() {
        return this.previewData?.warnings?.length > 0;
    }

    get hasImportErrors() {
        return this.importResult?.errors?.length > 0;
    }

    get importFullySuccessful() {
        return this.importResult?.errorCount === 0;
    }

    get previewRowsWithIndex() {
        if (!this.previewData?.rows || !this.previewData?.columns) return [];
        return this.previewData.rows.map((row, idx) => {
            const cells = this.previewData.columns.map((col) => ({
                key: col + '_' + idx,
                value: row[col] || ''
            }));
            return { index: idx + 1, cells };
        });
    }

    // ═══════════ Step 1 Handlers ═══════════

    handleSelectInvoice() {
        this.importType = 'Invoice';
    }

    handleSelectPayment() {
        this.importType = 'Payment';
    }

    // ═══════════ Step 2 Handlers ═══════════

    handleDragOver(event) {
        event.preventDefault();
        this.isDragOver = true;
    }

    handleDragLeave() {
        this.isDragOver = false;
    }

    handleDrop(event) {
        event.preventDefault();
        this.isDragOver = false;
        const files = event.dataTransfer.files;
        if (files.length > 0) {
            this.processFile(files[0]);
        }
    }

    handleFileUpload(event) {
        const files = event.detail.files;
        if (files && files.length > 0) {
            this.fileName = files[0].name;
            // Read file content using FileReader
            const reader = new FileReader();
            reader.onload = () => {
                this.csvContent = reader.result;
                this.pastedCSV = '';
            };
            reader.readAsText(files[0]);
        }
    }

    processFile(file) {
        if (!file.name.toLowerCase().endsWith('.csv')) {
            this.showToast('Error', 'Please upload a CSV file.', 'error');
            return;
        }
        this.fileName = file.name;
        const reader = new FileReader();
        reader.onload = () => {
            this.csvContent = reader.result;
            this.pastedCSV = '';
        };
        reader.readAsText(file);
    }

    handleRemoveFile() {
        this.csvContent = '';
        this.fileName = '';
    }

    handlePasteCSV(event) {
        this.pastedCSV = event.detail.value;
        if (this.pastedCSV) {
            this.csvContent = '';
            this.fileName = '';
        }
    }

    async handleDownloadTemplate() {
        try {
            const template = await getCSVTemplate({ importType: this.importType });
            this.downloadFile(
                `${this.importType}_Import_Template.csv`,
                template,
                'text/csv'
            );
        } catch (error) {
            this.showToast('Error', 'Failed to generate template: ' + this.reduceErrors(error), 'error');
        }
    }

    // ═══════════ Step 3: Parse & Preview ═══════════

    async parseAndPreview() {
        this.isLoading = true;
        const content = this.csvContent || this.pastedCSV;

        try {
            this.previewData = await parseCSV({
                csvContent: content,
                importType: this.importType
            });
        } catch (error) {
            this.previewData = {
                errors: ['Failed to parse CSV: ' + this.reduceErrors(error)],
                warnings: [],
                rows: [],
                columns: [],
                totalRows: 0,
                previewRows: 0
            };
        } finally {
            this.isLoading = false;
        }
    }

    // ═══════════ Step 4: Execute Import ═══════════

    async handleExecuteImport() {
        this.isImporting = true;
        const content = this.csvContent || this.pastedCSV;

        try {
            this.importResult = await executeImport({
                csvContent: content,
                importType: this.importType
            });
            this.currentStep = '5';
        } catch (error) {
            this.showToast('Import Error', 'Import failed: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isImporting = false;
        }
    }

    // ═══════════ Step 5: Results Actions ═══════════

    handleDownloadErrors() {
        if (!this.importResult?.errors?.length) return;

        let csv = 'Row,Error\n';
        this.importResult.errors.forEach((err) => {
            csv += `"${err.replace(/"/g, '""')}"\n`;
        });
        this.downloadFile('Import_Errors.csv', csv, 'text/csv');
    }

    handleReset() {
        this.currentStep = '1';
        this.importType = '';
        this.csvContent = '';
        this.pastedCSV = '';
        this.fileName = '';
        this.previewData = {};
        this.importResult = {};
        this.isLoading = false;
        this.isImporting = false;
    }

    // ═══════════ Navigation ═══════════

    handleNext() {
        const step = parseInt(this.currentStep, 10);
        if (step === 2) {
            // Moving to preview - trigger parse
            this.currentStep = '3';
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => { this.parseAndPreview(); }, 50);
        } else if (step < 5) {
            this.currentStep = String(step + 1);
        }
    }

    handleBack() {
        const step = parseInt(this.currentStep, 10);
        if (step > 1) {
            this.currentStep = String(step - 1);
        }
    }

    // ═══════════ Utility ═══════════

    downloadFile(filename, content, mimeType) {
        const blob = new Blob([content], { type: mimeType });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceErrors(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        if (Array.isArray(error?.body)) {
            return error.body.map(e => e.message).join(', ');
        }
        return 'Unknown error';
    }
}
