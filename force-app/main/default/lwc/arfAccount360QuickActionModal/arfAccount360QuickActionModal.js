import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getARContacts from '@salesforce/apex/ARF_Account360Controller.getARContacts';
import getInvoices from '@salesforce/apex/ARF_Account360Controller.getInvoices';
import createCommunication from '@salesforce/apex/ARF_Account360Controller.createCommunication';
import createNote from '@salesforce/apex/ARF_Account360Controller.createNote';
import createDispute from '@salesforce/apex/ARF_Account360Controller.createDispute';
import createPromiseToPay from '@salesforce/apex/ARF_Account360Controller.createPromiseToPay';

export default class ArfAccount360QuickActionModal extends LightningElement {
    @api recordId;
    @api actionType;
    isLoading = false;

    // Form fields
    contactId = '';
    subject = '';
    body = '';
    toAddress = '';
    callDuration = 0;
    direction = 'Outbound';
    noteTitle = '';
    noteBody = '';
    noteType = 'General';
    isPinned = false;
    invoiceId = '';
    disputeAmount = 0;
    disputeCategory = '';
    disputePriority = 'Medium';
    disputeDescription = '';
    promiseAmount = 0;
    promiseDate = '';
    promiseNotes = '';

    contactOptions = [];
    invoiceOptions = [];

    @wire(getARContacts, { accountId: '$recordId' })
    wiredContacts({ data }) {
        if (data) {
            this.contactOptions = data.map(c => ({
                label: `${c.Name} (${c.ARF_AR_Role__c || 'General'})`,
                value: c.Id
            }));
            if (data.length > 0) {
                this.contactId = data[0].Id;
                this.toAddress = data[0].Email || '';
            }
        }
    }

    @wire(getInvoices, { accountId: '$recordId' })
    wiredInvoices({ data }) {
        if (data) {
            this.invoiceOptions = [
                { label: '-- None --', value: '' },
                ...data.map(inv => ({
                    label: `${inv.Document_Number__c} - $${inv.Balance__c}`,
                    value: inv.Id
                }))
            ];
        }
    }

    get modalTitle() {
        const titles = {
            Email: 'Send Email',
            SMS: 'Send SMS',
            Call: 'Log Call',
            Note: 'Add Note',
            Dispute: 'Create Dispute',
            PromiseToPay: 'Promise to Pay'
        };
        return titles[this.actionType] || 'Quick Action';
    }

    get isEmail() { return this.actionType === 'Email'; }
    get isSMS() { return this.actionType === 'SMS'; }
    get isCall() { return this.actionType === 'Call'; }
    get isNote() { return this.actionType === 'Note'; }
    get isDispute() { return this.actionType === 'Dispute'; }
    get isPromiseToPay() { return this.actionType === 'PromiseToPay'; }
    get isCommunication() { return this.isEmail || this.isSMS || this.isCall; }

    get directionOptions() {
        return [
            { label: 'Outbound', value: 'Outbound' },
            { label: 'Inbound', value: 'Inbound' }
        ];
    }

    get noteTypeOptions() {
        return [
            { label: 'General', value: 'General' },
            { label: 'Call Log', value: 'Call Log' },
            { label: 'Meeting Notes', value: 'Meeting Notes' },
            { label: 'Follow Up', value: 'Follow Up' },
            { label: 'Internal', value: 'Internal' }
        ];
    }

    get disputeCategoryOptions() {
        return [
            { label: 'Pricing', value: 'Pricing' },
            { label: 'Shortage', value: 'Shortage' },
            { label: 'Quality', value: 'Quality' },
            { label: 'Delivery', value: 'Delivery' },
            { label: 'Duplicate', value: 'Duplicate' },
            { label: 'Damaged', value: 'Damaged' },
            { label: 'Tax', value: 'Tax' },
            { label: 'Other', value: 'Other' }
        ];
    }

    get priorityOptions() {
        return [
            { label: 'High', value: 'High' },
            { label: 'Medium', value: 'Medium' },
            { label: 'Low', value: 'Low' }
        ];
    }

    get channelValue() {
        if (this.isEmail) return 'Email';
        if (this.isSMS) return 'SMS';
        if (this.isCall) return 'Phone';
        return '';
    }

    // Field change handlers
    handleContactChange(event) { this.contactId = event.detail.value; }
    handleSubjectChange(event) { this.subject = event.detail.value; }
    handleBodyChange(event) { this.body = event.detail.value; }
    handleToAddressChange(event) { this.toAddress = event.detail.value; }
    handleCallDurationChange(event) { this.callDuration = event.detail.value; }
    handleDirectionChange(event) { this.direction = event.detail.value; }
    handleNoteTitleChange(event) { this.noteTitle = event.detail.value; }
    handleNoteBodyChange(event) { this.noteBody = event.detail.value; }
    handleNoteTypeChange(event) { this.noteType = event.detail.value; }
    handlePinnedChange(event) { this.isPinned = event.target.checked; }
    handleInvoiceChange(event) { this.invoiceId = event.detail.value; }
    handleDisputeAmountChange(event) { this.disputeAmount = event.detail.value; }
    handleDisputeCategoryChange(event) { this.disputeCategory = event.detail.value; }
    handleDisputePriorityChange(event) { this.disputePriority = event.detail.value; }
    handleDisputeDescriptionChange(event) { this.disputeDescription = event.detail.value; }
    handlePromiseAmountChange(event) { this.promiseAmount = event.detail.value; }
    handlePromiseDateChange(event) { this.promiseDate = event.detail.value; }
    handlePromiseNotesChange(event) { this.promiseNotes = event.detail.value; }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSave() {
        this.isLoading = true;
        try {
            if (this.isCommunication) {
                await this.saveCommunication();
            } else if (this.isNote) {
                await this.saveNote();
            } else if (this.isDispute) {
                await this.saveDispute();
            } else if (this.isPromiseToPay) {
                await this.savePromiseToPay();
            }
            this.showToast('Success', `${this.modalTitle} completed successfully`, 'success');
            this.dispatchEvent(new CustomEvent('recordcreated'));
        } catch (error) {
            this.showToast('Error', error.body?.message || error.message || 'An error occurred', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async saveCommunication() {
        const comm = {
            Account__c: this.recordId,
            Channel__c: this.channelValue,
            Subject__c: this.subject,
            Body__c: this.body,
            Direction__c: this.direction,
            Contact__c: this.contactId || null,
            To_Address__c: this.toAddress,
            Status__c: 'Draft',
            Sent_Date__c: new Date().toISOString()
        };
        if (this.isCall) {
            comm.Call_Duration_Seconds__c = this.callDuration;
        }
        await createCommunication({ comm });
    }

    async saveNote() {
        const note = {
            Account__c: this.recordId,
            Title__c: this.noteTitle,
            Body__c: this.noteBody,
            Type__c: this.noteType,
            Is_Pinned__c: this.isPinned
        };
        if (this.invoiceId) {
            note.Invoice__c = this.invoiceId;
        }
        await createNote({ note });
    }

    async saveDispute() {
        const dispute = {
            Account__c: this.recordId,
            Dispute_Amount__c: this.disputeAmount,
            Category__c: this.disputeCategory,
            Priority__c: this.disputePriority,
            Description__c: this.disputeDescription,
            Status__c: 'New'
        };
        if (this.invoiceId) {
            dispute.Invoice__c = this.invoiceId;
        }
        await createDispute({ dispute });
    }

    async savePromiseToPay() {
        const promise = {
            Account__c: this.recordId,
            Amount__c: this.promiseAmount,
            Promise_Date__c: this.promiseDate,
            Notes__c: this.promiseNotes,
            Status__c: 'Open'
        };
        if (this.invoiceId) {
            promise.Invoice__c = this.invoiceId;
        }
        await createPromiseToPay({ promise });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
