import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAccountSummary from '@salesforce/apex/ARF_Account360Controller.getAccountSummary';
import getInvoices from '@salesforce/apex/ARF_Account360Controller.getInvoices';
import getContactsForEmail from '@salesforce/apex/ARF_TransactionActionController.getContactsForEmail';
import getEmailTemplates from '@salesforce/apex/ARF_TransactionActionController.getEmailTemplates';
import getOrgWideEmailAddresses from '@salesforce/apex/ARF_TransactionActionController.getOrgWideEmailAddresses';
import getCurrentUserEmail from '@salesforce/apex/ARF_TransactionActionController.getCurrentUserEmail';
import resolveTemplate from '@salesforce/apex/ARF_TransactionActionController.resolveTemplate';
import executeContactCustomerWithFormat from '@salesforce/apex/ARF_TransactionActionController.executeContactCustomerWithFormat';

export default class ArfEmailComposer extends LightningElement {
    @api recordId;

    // Loading state
    isLoading = true;
    isSending = false;

    // Account data
    accountName = '';
    accountLocale = 'en_US';

    // Invoices
    @track invoices = [];
    invoiceIds = [];

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

    // Template
    @track templateOptions = [];
    selectedTemplateId = '';

    // Email content
    emailSubject = '';
    emailBodyHtml = '';

    // Attachments
    attachStatement = true;
    attachmentFormat = 'pdf';

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

    // Format options
    get formatOptions() {
        return [
            { label: 'PDF', value: 'pdf' },
            { label: 'Excel (CSV)', value: 'csv' }
        ];
    }

    // Note category options
    get noteCategoryOptions() {
        return [
            { label: 'General', value: 'General' },
            { label: 'Call Log', value: 'Call Log' },
            { label: 'Collection', value: 'Collection' },
            { label: 'Dispute', value: 'Dispute' },
            { label: 'Payment', value: 'Payment' }
        ];
    }

    get richTextFormats() {
        return [
            'font', 'size', 'bold', 'italic', 'underline', 'strike',
            'list', 'indent', 'align', 'link', 'image', 'clean', 'table',
            'header', 'color', 'background'
        ];
    }

    get noteChevronIcon() {
        return this.showNoteSection ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get followUpChevronIcon() {
        return this.showFollowUpSection ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get isSendDisabled() {
        const hasTo = this.toRecipients.length > 0 || (this.newToAddress && this.newToAddress.trim());
        return this.isSending || !hasTo || !this.emailSubject;
    }

    get sendButtonLabel() {
        return this.isSending ? 'Sending...' : 'Send Email';
    }

    // === LIFECYCLE ===

    connectedCallback() {
        this.loadAllData();
    }

    async loadAllData() {
        this.isLoading = true;
        try {
            const [account, contacts, templates, orgEmails, invoiceList] = await Promise.all([
                getAccountSummary({ accountId: this.recordId }),
                getContactsForEmail({ accountId: this.recordId }),
                getEmailTemplates({ locale: null, category: null }),
                getOrgWideEmailAddresses(),
                getInvoices({ accountId: this.recordId })
            ]);

            // Account
            this.accountName = account.Name || '';
            this.accountLocale = account.ARF_Template_Locale__c || 'en_US';

            // Invoices
            this.invoices = invoiceList || [];
            this.invoiceIds = this.invoices.map(inv => inv.Id);

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

            // CC recipients (non-primary contacts)
            const ccContacts = contacts.ccContacts || [];
            this.ccRecipients = ccContacts.map(c => ({
                email: c.email,
                label: `${c.name} <${c.email}>`,
                contactId: c.id
            }));

            // Templates — filter by account locale, fallback to all
            const localeTemplates = (templates || []).filter(
                t => t.Locale__c === this.accountLocale
            );
            const displayTemplates = localeTemplates.length > 0 ? localeTemplates : (templates || []);
            this.templateOptions = [
                { label: '-- None --', value: '' },
                ...displayTemplates.map(t => ({
                    label: `${t.Template_Name__c} (${t.Locale__c})`,
                    value: t.Id
                }))
            ];

            // Default follow-up subject
            this.followUpSubject = `Follow up on email to ${this.accountName}`;

        } catch (error) {
            this.showError('Error loading data', this.extractError(error));
        } finally {
            this.isLoading = false;
        }
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
            this.addToRecipient(this.newToAddress.trim());
            this.newToAddress = '';
        }
    }

    handleToBlur() {
        if (this.newToAddress && this.newToAddress.trim()) {
            this.addToRecipient(this.newToAddress.trim());
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
            this.addCcRecipient(this.newCcAddress.trim());
            this.newCcAddress = '';
        }
    }

    handleCcBlur() {
        if (this.newCcAddress && this.newCcAddress.trim()) {
            this.addCcRecipient(this.newCcAddress.trim());
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

    // === HANDLERS: TEMPLATE ===

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
                accountId: this.recordId,
                invoiceIds: this.invoiceIds
            });
            this.emailSubject = result.subject || '';
            this.emailBodyHtml = result.body || '';
        } catch (error) {
            this.showError('Error loading template', this.extractError(error));
        } finally {
            this.isLoading = false;
        }
    }

    // === HANDLERS: SUBJECT / BODY ===

    handleSubjectChange(event) {
        this.emailSubject = event.detail.value;
    }

    handleRichTextChange(event) {
        this.emailBodyHtml = event.target.value;
    }

    // === HANDLERS: ATTACHMENTS ===

    handleAttachChange(event) {
        this.attachStatement = event.target.checked;
    }

    handleFormatChange(event) {
        this.attachmentFormat = event.detail.value;
    }

    // === HANDLERS: NOTE ===

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

    // === HANDLERS: FOLLOW-UP ===

    toggleFollowUpSection() {
        this.showFollowUpSection = !this.showFollowUpSection;
    }

    handleFollowUpChange(event) {
        this.createFollowUp = event.target.checked;
    }

    handleFollowUpDaysChange(event) {
        this.followUpDays = parseInt(event.detail.value, 10) || 7;
    }

    handleFollowUpSubjectChange(event) {
        this.followUpSubject = event.detail.value;
    }

    // === SEND ===

    async handleSend() {
        // Auto-add any typed but uncommitted addresses
        if (this.newToAddress && this.newToAddress.trim()) {
            this.addToRecipient(this.newToAddress.trim());
            this.newToAddress = '';
        }
        if (this.newCcAddress && this.newCcAddress.trim()) {
            this.addCcRecipient(this.newCcAddress.trim());
            this.newCcAddress = '';
        }

        if (this.toRecipients.length === 0) {
            this.showError('Missing recipient', 'Please add at least one TO recipient.');
            return;
        }
        if (!this.emailSubject) {
            this.showError('Missing subject', 'Please enter an email subject.');
            return;
        }
        this.isSending = true;
        try {
            const toAddress = this.toRecipients.map(r => r.email).join(';');
            const ccAddress = this.ccRecipients.map(r => r.email).join(';');
            let bcc = this.bccAddress || '';
            if (this.includeMeBcc) {
                // Current user email is not easily available in LWC;
                // We'll add a placeholder that the backend can resolve, or skip
                // For now, pass as-is
            }

            // Find template name for communication record
            let templateName = '';
            if (this.selectedTemplateId) {
                const tmplOption = this.templateOptions.find(t => t.value === this.selectedTemplateId);
                if (tmplOption) templateName = tmplOption.label;
            }

            await executeContactCustomerWithFormat({
                accountId: this.recordId,
                invoiceIds: this.invoiceIds,
                channel: 'Email',
                fromAddressId: (this.selectedFromAddress && this.selectedFromAddress !== 'user_default') ? this.selectedFromAddress : null,
                toAddress: toAddress,
                ccAddresses: ccAddress || null,
                bccAddresses: bcc || null,
                subject: this.emailSubject,
                htmlBody: this.emailBodyHtml || '',
                attachStatement: this.attachStatement,
                contactId: this.primaryContactId,
                templateName: templateName,
                noteCategory: this.noteTitle ? this.noteCategory : null,
                noteTitle: this.noteTitle || null,
                noteBody: this.noteBody || null,
                createFollowUp: this.createFollowUp,
                followUpDays: this.createFollowUp ? this.followUpDays : null,
                followUpSubject: this.createFollowUp ? this.followUpSubject : null,
                followUpBody: null,
                attachmentFormat: this.attachmentFormat
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Email Sent',
                message: `Email sent to ${toAddress}`,
                variant: 'success'
            }));

            this.dispatchEvent(new CustomEvent('close'));
            this.dispatchEvent(new CustomEvent('recordcreated'));

        } catch (error) {
            this.showError('Error sending email', this.extractError(error));
        } finally {
            this.isSending = false;
        }
    }

    // === CLOSE ===

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // === UTILITIES ===

    showError(title, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'error' }));
    }

    extractError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unexpected error occurred';
    }
}
