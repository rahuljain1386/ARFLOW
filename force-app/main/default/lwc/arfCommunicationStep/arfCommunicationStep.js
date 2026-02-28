import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getContactsForEmail from '@salesforce/apex/ARF_TransactionActionController.getContactsForEmail';
import getEmailTemplates from '@salesforce/apex/ARF_TransactionActionController.getEmailTemplates';
import getOrgWideEmailAddresses from '@salesforce/apex/ARF_TransactionActionController.getOrgWideEmailAddresses';
import getCurrentUserEmail from '@salesforce/apex/ARF_TransactionActionController.getCurrentUserEmail';
import resolveTemplate from '@salesforce/apex/ARF_TransactionActionController.resolveTemplate';

export default class ArfCommunicationStep extends LightningElement {
    @api accountId;
    @api invoiceIds = [];
    @api contextLabel = '';
    @api stacked = false;

    // Channel
    selectedChannel = 'saveonly';

    // Loading
    isLoading = false;
    dataLoaded = false;

    // FROM
    @track fromAddressOptions = [];
    selectedFromAddress = '';

    // TO / CC / BCC
    @track toRecipients = [];
    @track ccRecipients = [];
    newToAddress = '';
    newCcAddress = '';
    bccAddress = '';
    includeMeBcc = false;
    primaryContactId = null;

    // Contacts (Phone/SMS)
    @track contactOptions = [];
    selectedContactId = '';

    // Template
    @track templateOptions = [];
    selectedTemplateId = '';

    // Email content
    emailSubject = '';
    emailBodyHtml = '';

    // Attachments
    attachStatement = true;
    attachmentFormat = 'pdf';
    uploadedFileIds = [];

    // Phone
    callDuration = 0;

    // SMS
    smsMessage = '';

    // Note
    showNoteSection = false;
    noteCategory = 'General';
    noteTitle = '';
    noteBody = '';

    // Follow-up
    showFollowUpSection = false;
    createFollowUp = false;
    followUpDays = 7;
    followUpSubject = '';

    // === GETTERS: Channel ===

    get isSaveOnly() { return this.selectedChannel === 'saveonly'; }
    get isEmail() { return this.selectedChannel === 'email'; }
    get commLayoutClass() { return this.stacked ? 'comm-layout comm-stacked' : 'comm-layout'; }
    get isPhone() { return this.selectedChannel === 'phone'; }
    get isSms() { return this.selectedChannel === 'sms'; }

    get saveOnlyVariant() { return this.isSaveOnly ? 'brand' : 'neutral'; }
    get emailVariant() { return this.isEmail ? 'brand' : 'neutral'; }
    get phoneVariant() { return this.isPhone ? 'brand' : 'neutral'; }
    get smsVariant() { return this.isSms ? 'brand' : 'neutral'; }

    // === GETTERS: Email ===

    get richTextFormats() {
        return [
            'font', 'size', 'bold', 'italic', 'underline', 'strike',
            'list', 'indent', 'align', 'link', 'image', 'clean', 'table',
            'header', 'color', 'background'
        ];
    }

    get formatOptions() {
        return [
            { label: 'PDF', value: 'pdf' },
            { label: 'Excel (CSV)', value: 'csv' }
        ];
    }

    get showFileUpload() { return this.isEmail; }

    get acceptedFormats() {
        return ['.pdf', '.xlsx', '.xls', '.csv', '.doc', '.docx', '.png', '.jpg'];
    }

    // === GETTERS: Note / Follow-up ===

    get noteChevronIcon() {
        return this.showNoteSection ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get followUpChevronIcon() {
        return this.showFollowUpSection ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get noteCategoryOptions() {
        return [
            { label: 'General', value: 'General' },
            { label: 'Call Log', value: 'Call Log' },
            { label: 'Collection', value: 'Collection' },
            { label: 'Dispute', value: 'Dispute' },
            { label: 'Payment', value: 'Payment' }
        ];
    }

    // === GETTERS: SMS ===

    get smsCharCount() { return (this.smsMessage || '').length; }

    // === LIFECYCLE ===

    async loadCommunicationData() {
        if (this.dataLoaded) return;
        this.isLoading = true;
        try {
            const [contacts, templates, orgEmails] = await Promise.all([
                getContactsForEmail({ accountId: this.accountId }),
                getEmailTemplates({ locale: null, category: null }),
                getOrgWideEmailAddresses()
            ]);

            // From addresses
            this.fromAddressOptions = (orgEmails || []).map(addr => ({
                label: `${addr.displayName} <${addr.address}>`,
                value: addr.id
            }));
            if (this.fromAddressOptions.length > 0) {
                this.selectedFromAddress = this.fromAddressOptions[0].value;
            } else {
                const userInfo = await getCurrentUserEmail();
                this.fromAddressOptions = [{
                    label: `${userInfo.name} <${userInfo.email}>`,
                    value: 'user_default'
                }];
                this.selectedFromAddress = 'user_default';
            }

            // TO recipients (primary contacts)
            const toContacts = contacts.toContacts || [];
            this.toRecipients = toContacts.map(c => ({
                email: c.email,
                label: `${c.name} <${c.email}>`,
                contactId: c.id
            }));
            if (toContacts.length > 0) {
                this.primaryContactId = toContacts[0].id;
            }

            // CC recipients
            const ccContacts = contacts.ccContacts || [];
            this.ccRecipients = ccContacts.map(c => ({
                email: c.email,
                label: `${c.name} <${c.email}>`,
                contactId: c.id
            }));

            // All contacts for Phone/SMS picker
            const allContacts = [...toContacts, ...ccContacts];
            this.contactOptions = allContacts.map(c => ({
                label: `${c.name} (${c.email})`,
                value: c.id
            }));
            if (allContacts.length > 0) {
                this.selectedContactId = allContacts[0].id;
            }

            // Templates
            this.templateOptions = [
                { label: '-- None --', value: '' },
                ...(templates || []).map(t => ({
                    label: `${t.Template_Name__c} (${t.Locale__c})`,
                    value: t.Id
                }))
            ];

            this.dataLoaded = true;
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error loading communication data',
                message: this.extractError(error),
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    // === HANDLERS: Channel ===

    handleSaveOnly() {
        this.selectedChannel = 'saveonly';
    }

    handleSelectEmail() {
        this.selectedChannel = 'email';
        this.loadCommunicationData();
    }

    handleSelectPhone() {
        this.selectedChannel = 'phone';
        this.loadCommunicationData();
    }

    handleSelectSms() {
        this.selectedChannel = 'sms';
        this.loadCommunicationData();
    }

    // === HANDLERS: FROM ===

    handleFromChange(event) {
        this.selectedFromAddress = event.detail.value;
    }

    // === HANDLERS: TO ===

    handleNewToChange(event) {
        this.newToAddress = event.detail.value;
    }

    handleToKeyup(event) {
        if (event.key === 'Enter' && this.newToAddress) {
            this.addToRecipient(this.newToAddress);
            this.newToAddress = '';
        }
    }

    addToRecipient(email) {
        if (!email || this.toRecipients.some(r => r.email === email)) return;
        this.toRecipients = [...this.toRecipients, { email, label: email }];
    }

    handleRemoveTo(event) {
        const email = event.target.dataset.email;
        this.toRecipients = this.toRecipients.filter(r => r.email !== email);
    }

    // === HANDLERS: CC ===

    handleNewCcChange(event) {
        this.newCcAddress = event.detail.value;
    }

    handleCcKeyup(event) {
        if (event.key === 'Enter' && this.newCcAddress) {
            this.addCcRecipient(this.newCcAddress);
            this.newCcAddress = '';
        }
    }

    addCcRecipient(email) {
        if (!email || this.ccRecipients.some(r => r.email === email)) return;
        this.ccRecipients = [...this.ccRecipients, { email, label: email }];
    }

    handleRemoveCc(event) {
        const email = event.target.dataset.email;
        this.ccRecipients = this.ccRecipients.filter(r => r.email !== email);
    }

    // === HANDLERS: BCC ===

    handleBccChange(event) {
        this.bccAddress = event.detail.value;
    }

    handleIncludeMeChange(event) {
        this.includeMeBcc = event.target.checked;
    }

    // === HANDLERS: Template ===

    async handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        if (!this.selectedTemplateId) {
            this.emailSubject = '';
            this.emailBodyHtml = '';
            return;
        }
        try {
            this.isLoading = true;
            const result = await resolveTemplate({
                templateId: this.selectedTemplateId,
                accountId: this.accountId,
                invoiceIds: this.invoiceIds
            });
            this.emailSubject = result.subject || '';
            this.emailBodyHtml = result.body || '';
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error loading template',
                message: this.extractError(error),
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    // === HANDLERS: Subject / Body ===

    handleSubjectChange(event) {
        this.emailSubject = event.detail.value;
    }

    handleRichTextChange(event) {
        this.emailBodyHtml = event.target.value;
    }

    // === HANDLERS: Attachments ===

    handleAttachChange(event) {
        this.attachStatement = event.target.checked;
    }

    handleFormatChange(event) {
        this.attachmentFormat = event.detail.value;
    }

    handleUploadFinished(event) {
        const files = event.detail.files;
        this.uploadedFileIds = [...this.uploadedFileIds, ...files.map(f => f.documentId)];
        this.dispatchEvent(new ShowToastEvent({
            title: 'Files Uploaded',
            message: `${files.length} file(s) attached`,
            variant: 'success'
        }));
    }

    // === HANDLERS: Contact (Phone/SMS) ===

    handleContactChange(event) {
        this.selectedContactId = event.detail.value;
    }

    // === HANDLERS: Phone ===

    handleDurationChange(event) {
        this.callDuration = parseInt(event.detail.value, 10) || 0;
    }

    // === HANDLERS: SMS ===

    handleSmsMessageChange(event) {
        this.smsMessage = event.detail.value;
    }

    // === HANDLERS: Note ===

    toggleNoteSection() {
        this.showNoteSection = !this.showNoteSection;
    }

    handleNoteCategoryChange(event) {
        this.noteCategory = event.detail.value;
    }

    handleNoteTitleChange(event) {
        this.noteTitle = event.detail.value;
    }

    handleNoteBodyChange(event) {
        this.noteBody = event.detail.value;
    }

    // === HANDLERS: Follow-up ===

    toggleFollowUpSection() {
        this.showFollowUpSection = !this.showFollowUpSection;
    }

    handleFollowUpToggle(event) {
        this.createFollowUp = event.target.checked;
    }

    handleFollowUpDaysChange(event) {
        this.followUpDays = parseInt(event.detail.value, 10) || 7;
    }

    handleFollowUpSubjectChange(event) {
        this.followUpSubject = event.detail.value;
    }

    // === PUBLIC API ===

    @api
    getCommunicationParams() {
        if (this.isSaveOnly) {
            return { channel: 'SaveOnly' };
        }

        const baseParams = {
            noteCategory: this.noteTitle ? this.noteCategory : null,
            noteTitle: this.noteTitle || null,
            noteBody: this.noteBody || null,
            createFollowUp: this.createFollowUp,
            followUpDays: this.createFollowUp ? this.followUpDays : null,
            followUpSubject: this.createFollowUp ? this.followUpSubject : null,
            followUpBody: null
        };

        if (this.isEmail) {
            return {
                channel: 'Email',
                fromAddressId: (this.selectedFromAddress && this.selectedFromAddress !== 'user_default') ? this.selectedFromAddress : null,
                toAddress: this.toRecipients.map(r => r.email).join(';'),
                ccAddresses: this.ccRecipients.map(r => r.email).join(';') || null,
                bccAddresses: this.bccAddress || null,
                subject: this.emailSubject,
                htmlBody: this.emailBodyHtml || '',
                attachStatement: this.attachStatement,
                attachmentFormat: this.attachmentFormat,
                contactId: this.primaryContactId,
                templateName: this.getSelectedTemplateName(),
                uploadedFileIds: this.uploadedFileIds,
                ...baseParams
            };
        }

        if (this.isPhone) {
            return {
                channel: 'Phone',
                contactId: this.selectedContactId,
                subject: this.emailSubject,
                callDuration: this.callDuration,
                ...baseParams,
                noteBody: this.noteBody || null
            };
        }

        if (this.isSms) {
            return {
                channel: 'SMS',
                contactId: this.selectedContactId,
                smsMessage: this.smsMessage,
                ...baseParams
            };
        }

        return { channel: 'SaveOnly' };
    }

    @api
    validate() {
        if (this.isSaveOnly) return true;

        if (this.isEmail) {
            if (this.toRecipients.length === 0) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Missing recipient',
                    message: 'Please add at least one TO recipient.',
                    variant: 'error'
                }));
                return false;
            }
            if (!this.emailSubject) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Missing subject',
                    message: 'Please enter an email subject.',
                    variant: 'error'
                }));
                return false;
            }
        }

        if (this.isSms && !this.smsMessage) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Missing message',
                message: 'Please enter an SMS message.',
                variant: 'error'
            }));
            return false;
        }

        return true;
    }

    // === UTILITIES ===

    getSelectedTemplateName() {
        if (!this.selectedTemplateId) return '';
        const opt = this.templateOptions.find(t => t.value === this.selectedTemplateId);
        return opt ? opt.label : '';
    }

    extractError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unexpected error occurred';
    }
}
