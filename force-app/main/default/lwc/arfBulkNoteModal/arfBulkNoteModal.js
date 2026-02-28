import { LightningElement, api } from 'lwc';
import createBulkNotes from '@salesforce/apex/ARF_TransactionActionController.createBulkNotes';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const TYPE_OPTIONS = [
    { label: 'General', value: 'General' },
    { label: 'Call Log', value: 'Call Log' },
    { label: 'Meeting Notes', value: 'Meeting Notes' },
    { label: 'Follow Up', value: 'Follow Up' },
    { label: 'Internal', value: 'Internal' }
];

export default class ArfBulkNoteModal extends LightningElement {
    @api accountId;
    @api selectedInvoices = [];

    noteTitle = '';
    noteBody = '';
    noteType = 'General';
    isSubmitting = false;
    typeOptions = TYPE_OPTIONS;

    get invoiceCount() { return this.selectedInvoices ? this.selectedInvoices.length : 0; }
    get subtitle() { return `Adding note to ${this.invoiceCount} invoice(s)`; }
    get isSaveDisabled() { return this.isSubmitting || !this.noteTitle; }

    handleTitleChange(e) { this.noteTitle = e.target.value; }
    handleBodyChange(e) { this.noteBody = e.target.value; }
    handleTypeChange(e) { this.noteType = e.detail.value; }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSave() {
        this.isSubmitting = true;
        try {
            const invoiceIds = this.selectedInvoices.map(inv => inv.Id);
            await createBulkNotes({
                accountId: this.accountId,
                invoiceIds: invoiceIds,
                noteTitle: this.noteTitle,
                noteBody: this.noteBody,
                noteType: this.noteType
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: `Created ${invoiceIds.length} note(s)`,
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('save'));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body ? error.body.message : error.message,
                variant: 'error'
            }));
        } finally {
            this.isSubmitting = false;
        }
    }
}
