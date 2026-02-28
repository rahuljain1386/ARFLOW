import { LightningElement, api } from 'lwc';

export default class ArfDisputeStatusModal extends LightningElement {
    @api disputeIds = [];

    newStatus = '';
    notes = '';

    get statusOptions() {
        return [
            { label: '-- Select --', value: '' },
            { label: 'Open', value: 'New' },
            { label: 'In Progress', value: 'Under Investigation' },
            { label: 'Resolved', value: 'Resolved' },
            { label: 'Closed', value: 'Closed' },
            { label: 'Denied', value: 'Denied' }
        ];
    }

    get subtitle() {
        return `${this.disputeIds.length} dispute(s) selected`;
    }

    get isSaveDisabled() {
        return !this.newStatus;
    }

    handleStatusChange(event) {
        this.newStatus = event.detail.value;
    }

    handleNotesChange(event) {
        this.notes = event.detail.value;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleSave() {
        this.dispatchEvent(new CustomEvent('save', {
            detail: {
                disputeIds: this.disputeIds,
                newStatus: this.newStatus,
                notes: this.notes
            }
        }));
    }
}
