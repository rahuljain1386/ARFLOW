import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import getAccountSummary from '@salesforce/apex/ARF_Account360Controller.getAccountSummary';
import getContactsForEmail from '@salesforce/apex/ARF_TransactionActionController.getContactsForEmail';
import getEmailTemplates from '@salesforce/apex/ARF_TransactionActionController.getEmailTemplates';
import getOrgWideEmailAddresses from '@salesforce/apex/ARF_TransactionActionController.getOrgWideEmailAddresses';
import getCurrentUserEmail from '@salesforce/apex/ARF_TransactionActionController.getCurrentUserEmail';
import resolveTemplate from '@salesforce/apex/ARF_TransactionActionController.resolveTemplate';
import executeContactCustomerWithFormat from '@salesforce/apex/ARF_TransactionActionController.executeContactCustomerWithFormat';
import initiateCallNow from '@salesforce/apex/ARF_TransactionActionController.initiateCallNow';
import getOpenInvoicesForAccount from '@salesforce/apex/ARF_TransactionActionController.getOpenInvoicesForAccount';
import getVoiceToken from '@salesforce/apex/ARF_TwilioTokenService.getVoiceToken';
import TWILIO_CLIENT_JS from '@salesforce/resourceUrl/TwilioClientJS';

export default class ArfContactCustomerModal extends LightningElement {
    @api accountId;
    @api selectedInvoices = [];

    // Reply/Forward prefill props
    @api replyMode = false;
    @api prefillSubject = '';
    @api prefillBody = '';
    @api prefillTo = '';
    @api prefillCc = '';

    // Channel
    channel = 'Email';
    isSubmitting = false;
    accountLocale = 'en_US';

    // Invoice management
    @track _modalInvoices = [];

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
    @track contactPickerOptions = [];
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
    contactPhoneNumber = '';
    allContactsData = [];
    callState = 'pre'; // pre, active, post
    callTimerSeconds = 0;
    collectorPhone = '';
    rememberMyNumber = true;
    _callTimerInterval = null;
    _callCommunicationId = null;
    _callSid = null;
    _COLLECTOR_PHONE_KEY = 'arf_collector_phone';

    // Browser calling (WebRTC)
    isBrowserCallReady = false;
    isBrowserCall = false;
    isMuted = false;
    _twilioDevice = null;
    _activeConnection = null;
    _twilioSdkLoaded = false;

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

    get isEmail() { return this.channel === 'Email'; }
    get isPhone() { return this.channel === 'Phone'; }
    get isSms() { return this.channel === 'SMS'; }

    get emailVariant() { return this.isEmail ? 'brand' : 'neutral'; }
    get phoneVariant() { return this.isPhone ? 'brand' : 'neutral'; }
    get smsVariant() { return this.isSms ? 'brand' : 'neutral'; }

    // === GETTERS: Invoice ===

    get modalInvoices() { return this._modalInvoices; }
    get invoiceCount() { return this._modalInvoices.length; }
    get invoiceIds() { return this._modalInvoices.map(inv => inv.Id); }
    get totalBalance() {
        return this._modalInvoices.reduce((sum, inv) => sum + (inv.Balance__c || 0), 0);
    }
    get formattedBalance() {
        return '$' + this.totalBalance.toLocaleString('en-US', { minimumFractionDigits: 2 });
    }

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

    // === GETTERS: Submit ===

    get isSubmitDisabled() {
        if (this.isPhone && this.callState !== 'post') return true;
        return this.isSubmitting;
    }
    get hideFooterButtons() {
        return this.isPhone && this.callState !== 'post';
    }
    get sendButtonLabel() {
        if (this.isSubmitting) return 'Sending...';
        if (this.isEmail) return 'Send Email';
        if (this.isPhone) return 'Save Call Log';
        if (this.isSms) return 'Send SMS';
        return 'Execute';
    }

    // === LIFECYCLE ===

    connectedCallback() {
        const passedInvoices = this.selectedInvoices || [];
        this._modalInvoices = passedInvoices.map(inv => ({
            ...inv,
            pillLabel: `${inv.Document_Number__c || inv.Name} — $${(inv.Balance__c || 0).toLocaleString('en-US', { minimumFractionDigits: 2 })}`
        }));

        // Auto-load saved collector phone from localStorage
        try {
            const savedPhone = localStorage.getItem(this._COLLECTOR_PHONE_KEY);
            if (savedPhone) {
                this.collectorPhone = savedPhone;
                this.rememberMyNumber = true;
            }
        } catch (e) {
            // localStorage may not be available in some contexts
        }

        // Apply reply/forward prefills
        if (this.replyMode) {
            this.emailSubject = this.prefillSubject || '';
            this.emailBodyHtml = this.prefillBody || '';
            if (this.prefillTo) {
                this.toRecipients = this.prefillTo.split(';').filter(Boolean).map(email => ({
                    email: email.trim(),
                    label: email.trim()
                }));
            }
            if (this.prefillCc) {
                this.ccRecipients = this.prefillCc.split(';').filter(Boolean).map(email => ({
                    email: email.trim(),
                    label: email.trim()
                }));
            }
        }

        // Auto-load all open invoices if none were passed in
        if (passedInvoices.length === 0 && this.accountId) {
            this.loadOpenInvoices();
        }

        this.loadAllData();
    }

    async loadOpenInvoices() {
        try {
            const invoices = await getOpenInvoicesForAccount({ accountId: this.accountId });
            this._modalInvoices = (invoices || []).map(inv => ({
                ...inv,
                pillLabel: `${inv.Document_Number__c || inv.Name} — $${(inv.Balance__c || 0).toLocaleString('en-US', { minimumFractionDigits: 2 })}`
            }));
        } catch (error) {
            // Non-critical — modal still works without invoices
        }
    }

    async loadAllData() {
        try {
            const [account, contacts, templates, orgEmails] = await Promise.all([
                getAccountSummary({ accountId: this.accountId }),
                getContactsForEmail({ accountId: this.accountId }),
                getEmailTemplates({ locale: null, category: null }),
                getOrgWideEmailAddresses()
            ]);

            // Account locale for template filtering
            this.accountLocale = account?.ARF_Template_Locale__c || 'en_US';

            // From addresses
            this.fromAddressOptions = (orgEmails || []).map(addr => ({
                label: `${addr.displayName} <${addr.address}>`,
                value: addr.id
            }));
            if (this.fromAddressOptions.length > 0) {
                this.selectedFromAddress = this.fromAddressOptions[0].value;
            } else {
                // Fallback to logged-in user's email
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

            // All contacts for Phone/SMS
            const allContacts = [...toContacts, ...ccContacts];
            this.allContactsData = allContacts;
            this.contactPickerOptions = allContacts.map(c => {
                const phone = c.phoneDirect || c.phone || '';
                const phoneLabel = phone ? ` — ${phone}` : '';
                return {
                    label: `${c.name} (${c.email})${phoneLabel}`,
                    value: c.id
                };
            });
            if (allContacts.length > 0) {
                this.selectedContactId = allContacts[0].id;
                this.contactPhoneNumber = allContacts[0].phoneDirect || allContacts[0].phone || '';
            }

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
            this.followUpSubject = `Follow up on communication`;

        } catch (error) {
            this.showToast('Error loading data', this.extractError(error), 'error');
        }

        // Initialize browser calling (non-blocking)
        this.initTwilioDevice();
    }

    async initTwilioDevice() {
        try {
            // Load Twilio Client JS SDK from static resource
            if (!this._twilioSdkLoaded) {
                await loadScript(this, TWILIO_CLIENT_JS);
                this._twilioSdkLoaded = true;
            }

            // Check if Twilio global is available (SDK loaded successfully)
            if (typeof Twilio === 'undefined' || !Twilio.Device) {
                this.isBrowserCallReady = false;
                return;
            }

            // Get a voice token from Apex
            const tokenResult = await getVoiceToken();
            if (tokenResult && tokenResult.token) {
                // Initialize the Twilio Device
                this._twilioDevice = new Twilio.Device(tokenResult.token, {
                    codecPreferences: ['opus', 'pcmu'],
                    enableRingingState: true
                });

                this._twilioDevice.on('ready', () => {
                    this.isBrowserCallReady = true;
                });

                this._twilioDevice.on('error', (err) => {
                    console.error('Twilio Device error:', err);
                    this.isBrowserCallReady = false;
                });

                this._twilioDevice.on('disconnect', () => {
                    this.handleBrowserCallDisconnect();
                });
            }
        } catch (e) {
            // If SDK fails to load or token fails, fall back to phone bridge
            console.warn('Browser calling unavailable, falling back to phone bridge:', e);
            this.isBrowserCallReady = false;
        }
    }

    // === HANDLERS: Channel ===

    handleSelectEmail() { this.channel = 'Email'; }
    handleSelectPhone() { this.channel = 'Phone'; }
    handleSelectSms() { this.channel = 'SMS'; }

    // === HANDLERS: FROM ===

    handleFromChange(event) {
        this.selectedFromAddress = event.detail.value;
    }

    // === HANDLERS: TO ===

    handleNewToChange(event) { this.newToAddress = event.detail.value; }

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

    handleNewCcChange(event) { this.newCcAddress = event.detail.value; }

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

    handleBccChange(event) { this.bccAddress = event.detail.value; }
    handleIncludeMeChange(event) { this.includeMeBcc = event.target.checked; }

    // === HANDLERS: Template ===

    async handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        if (!this.selectedTemplateId) {
            this.emailSubject = '';
            this.emailBodyHtml = '';
            return;
        }
        try {
            const result = await resolveTemplate({
                templateId: this.selectedTemplateId,
                accountId: this.accountId,
                invoiceIds: this.invoiceIds
            });
            this.emailSubject = result.subject || '';
            this.emailBodyHtml = result.body || '';
        } catch (error) {
            this.showToast('Error loading template', this.extractError(error), 'error');
        }
    }

    // === HANDLERS: Subject / Body ===

    handleSubjectChange(event) { this.emailSubject = event.detail.value; }

    handleRichTextChange(event) {
        this.emailBodyHtml = event.target.value;
    }

    // === HANDLERS: Attachments ===

    handleAttachChange(event) { this.attachStatement = event.target.checked; }
    handleFormatChange(event) { this.attachmentFormat = event.detail.value; }

    handleUploadFinished(event) {
        const files = event.detail.files;
        this.uploadedFileIds = [...this.uploadedFileIds, ...files.map(f => f.documentId)];
        this.showToast('Files Uploaded', `${files.length} file(s) attached`, 'success');
    }

    // === HANDLERS: Invoice removal ===

    handleRemoveInvoice(event) {
        const invId = event.target.dataset.id;
        this._modalInvoices = this._modalInvoices.filter(inv => inv.Id !== invId);
    }

    // === HANDLERS: Contact (Phone/SMS) ===

    handleContactPickerChange(event) {
        this.selectedContactId = event.detail.value;
        const contact = this.allContactsData.find(c => c.id === this.selectedContactId);
        if (contact) {
            this.contactPhoneNumber = contact.phoneDirect || contact.phone || '';
        }
    }
    handlePhoneNumberChange(event) { this.contactPhoneNumber = event.detail.value; }

    // === HANDLERS: Phone ===

    get isPreCall() { return this.callState === 'pre'; }
    get isCallActive() { return this.callState === 'active'; }
    get isPostCall() { return this.callState === 'post'; }
    get isCallDisabled() { return false; }
    get isCallDisabledOrSubmitting() { return this.isSubmitting; }
    get isBrowserCallDisabled() { return !this.contactPhoneNumber; }
    get muteIcon() { return this.isMuted ? 'utility:unmute' : 'utility:mute'; }
    get muteLabel() { return this.isMuted ? 'Unmute' : 'Mute'; }
    get muteButtonClass() { return this.isMuted ? 'mute-btn muted' : 'mute-btn'; }
    get hasRememberedPhone() {
        try { return !!localStorage.getItem(this._COLLECTOR_PHONE_KEY); }
        catch (e) { return false; }
    }

    handleCollectorPhoneChange(event) { this.collectorPhone = event.detail.value; }
    handleRememberMyNumberChange(event) { this.rememberMyNumber = event.target.checked; }

    get selectedContactName() {
        const contact = this.allContactsData.find(c => c.id === this.selectedContactId);
        return contact ? contact.name : '';
    }

    get callTimerDisplay() {
        const mins = Math.floor(this.callTimerSeconds / 60);
        const secs = this.callTimerSeconds % 60;
        return String(mins).padStart(2, '0') + ':' + String(secs).padStart(2, '0');
    }

    handleClearSavedPhone() {
        try {
            localStorage.removeItem(this._COLLECTOR_PHONE_KEY);
            this.collectorPhone = '';
            this.rememberMyNumber = true;
        } catch (e) { /* ignore */ }
    }

    handleBrowserCall() {
        if (!this._twilioDevice || !this.contactPhoneNumber) return;

        this.isBrowserCall = true;
        this.callState = 'active';
        this.callTimerSeconds = 0;

        try {
            this._activeConnection = this._twilioDevice.connect({
                To: this.contactPhoneNumber
            });

            this._activeConnection.on('accept', () => {
                // Call connected — start timer
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                this._callTimerInterval = setInterval(() => {
                    this.callTimerSeconds++;
                }, 1000);
            });

            this._activeConnection.on('disconnect', () => {
                this.handleBrowserCallDisconnect();
            });

            this._activeConnection.on('error', (err) => {
                console.error('Browser call error:', err);
                this.showToast('Call Error', err.message || 'An error occurred during the call.', 'error');
                this.handleBrowserCallDisconnect();
            });
        } catch (error) {
            this.callState = 'pre';
            this.isBrowserCall = false;
            this.showToast('Call Failed', this.extractError(error), 'error');
        }
    }

    handleBrowserCallDisconnect() {
        if (this._callTimerInterval) {
            clearInterval(this._callTimerInterval);
            this._callTimerInterval = null;
        }
        if (this.callState === 'active') {
            this.callDuration = this.callTimerSeconds;
            this.callState = 'post';
        }
        this._activeConnection = null;
    }

    handleToggleMute() {
        if (this._activeConnection) {
            this.isMuted = !this.isMuted;
            this._activeConnection.mute(this.isMuted);
        }
    }

    async handleCallNow() {
        // Save collector phone to localStorage if "Remember" is checked
        try {
            if (this.rememberMyNumber && this.collectorPhone) {
                localStorage.setItem(this._COLLECTOR_PHONE_KEY, this.collectorPhone);
            } else {
                localStorage.removeItem(this._COLLECTOR_PHONE_KEY);
            }
        } catch (e) { /* localStorage may be unavailable */ }

        // Validate before calling
        if (!this.contactPhoneNumber) {
            this.showToast('Missing Phone', 'Enter the customer phone number.', 'error');
            return;
        }
        if (!this.collectorPhone) {
            this.showToast('Missing My Phone', 'Enter your phone number in the "My Phone" field.', 'error');
            return;
        }

        // Initiate real Twilio call immediately
        this.isSubmitting = true;
        try {
            const result = await initiateCallNow({
                accountId: this.accountId,
                contactId: this.selectedContactId,
                phoneNumber: this.contactPhoneNumber,
                collectorPhone: this.collectorPhone,
                invoiceIds: this.invoiceIds
            });

            this._callCommunicationId = result.communicationId;
            this._callSid = result.callSid;

            // Only go to active AFTER call is confirmed
            this.callState = 'active';
            this.callTimerSeconds = 0;
            this.isSubmitting = false;

            this.showToast('Call Connected', result.message, 'success');

            // Start timer
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._callTimerInterval = setInterval(() => {
                this.callTimerSeconds++;
            }, 1000);

        } catch (error) {
            this.isSubmitting = false;
            this.callState = 'pre';
            this.showToast('Call Failed', this.extractError(error), 'error');
        }
    }

    handleEndCall() {
        // Disconnect browser call if active
        if (this.isBrowserCall && this._activeConnection) {
            this._activeConnection.disconnect();
        }
        // Stop timer
        if (this._callTimerInterval) {
            clearInterval(this._callTimerInterval);
            this._callTimerInterval = null;
        }
        this.callDuration = this.callTimerSeconds;
        this.callState = 'post';
        this._activeConnection = null;
    }

    handleDurationChange(event) { this.callDuration = parseInt(event.detail.value, 10) || 0; }

    // === HANDLERS: SMS ===

    handleSmsMessageChange(event) { this.smsMessage = event.detail.value; }

    // === HANDLERS: Note ===

    toggleNoteSection() { this.showNoteSection = !this.showNoteSection; }
    handleNoteCategoryChange(event) { this.noteCategory = event.detail.value; }
    handleNoteTitleChange(event) { this.noteTitle = event.detail.value; }
    handleNoteBodyChange(event) { this.noteBody = event.detail.value; }

    // === HANDLERS: Follow-up ===

    toggleFollowUpSection() { this.showFollowUpSection = !this.showFollowUpSection; }
    handleFollowUpToggle(event) { this.createFollowUp = event.target.checked; }
    handleFollowUpDaysChange(event) { this.followUpDays = parseInt(event.detail.value, 10) || 7; }
    handleFollowUpSubjectChange(event) { this.followUpSubject = event.detail.value; }

    // === CANCEL ===

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // === EXECUTE ===

    async handleExecute() {
        // Auto-add any typed but uncommitted addresses
        if (this.newToAddress && this.newToAddress.trim()) {
            this.addToRecipient(this.newToAddress.trim());
            this.newToAddress = '';
        }
        if (this.newCcAddress && this.newCcAddress.trim()) {
            this.addCcRecipient(this.newCcAddress.trim());
            this.newCcAddress = '';
        }

        // Validate email
        if (this.isEmail) {
            if (this.toRecipients.length === 0) {
                this.showToast('Missing recipient', 'Please add at least one TO recipient.', 'error');
                return;
            }
            if (!this.emailSubject) {
                this.showToast('Missing subject', 'Please enter an email subject.', 'error');
                return;
            }
        }
        if (this.isSms && !this.smsMessage) {
            this.showToast('Missing message', 'Please enter an SMS message.', 'error');
            return;
        }

        this.isSubmitting = true;
        try {
            let templateName = '';
            if (this.selectedTemplateId) {
                const opt = this.templateOptions.find(t => t.value === this.selectedTemplateId);
                if (opt) templateName = opt.label;
            }

            await executeContactCustomerWithFormat({
                accountId: this.accountId,
                invoiceIds: this.invoiceIds,
                channel: this.channel,
                fromAddressId: (this.selectedFromAddress && this.selectedFromAddress !== 'user_default') ? this.selectedFromAddress : null,
                toAddress: this.isEmail ? this.toRecipients.map(r => r.email).join(';') : '',
                ccAddresses: this.isEmail ? (this.ccRecipients.map(r => r.email).join(';') || null) : null,
                bccAddresses: this.isEmail ? (this.bccAddress || null) : null,
                subject: this.emailSubject || '',
                htmlBody: this.emailBodyHtml || '',
                attachStatement: this.attachStatement,
                contactId: this.isEmail ? this.primaryContactId : this.selectedContactId,
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

            this.showToast('Success', `${this.channel} communication sent for ${this.invoiceIds.length} invoice(s)`, 'success');
            this.dispatchEvent(new CustomEvent('save'));
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        } finally {
            this.isSubmitting = false;
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
