import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import prepareMassEmail from '@salesforce/apex/ARF_WorklistController.prepareMassEmail';
import executeMassEmail from '@salesforce/apex/ARF_WorklistController.executeMassEmail';

export default class ArfMassEmailModal extends LightningElement {
    @api taskIds = [];

    @track accounts = [];
    isLoading = true;
    isSending = false;

    totalAccounts = 0;
    accountsWithContact = 0;
    accountsWithoutContact = 0;

    attachmentFormat = 'none';

    get formatOptions() {
        return [
            { label: 'None', value: 'none' },
            { label: 'PDF Statement', value: 'pdf' },
            { label: 'Excel (CSV)', value: 'csv' }
        ];
    }

    get sendableCount() {
        return this.accounts.filter(a => !a.skip && a.hasContact).length;
    }

    get isSendDisabled() {
        return this.isSending || this.sendableCount === 0;
    }

    get sendButtonLabel() {
        return this.isSending ? 'Sending...' : `Send ${this.sendableCount} Email(s)`;
    }

    connectedCallback() {
        this.loadPreview();
    }

    async loadPreview() {
        this.isLoading = true;
        try {
            const preview = await prepareMassEmail({ taskIds: this.taskIds });
            this.accounts = (preview.accounts || []).map((acct, idx) => ({
                ...acct,
                index: idx,
                skipChecked: acct.skip,
                disableSkip: !acct.hasContact,
                statusIcon: acct.hasContact ? 'utility:check' : 'utility:warning',
                statusVariant: acct.hasContact ? 'success' : 'warning',
                formattedBalance: acct.totalBalance
                    ? '$' + acct.totalBalance.toLocaleString('en-US', { minimumFractionDigits: 2 })
                    : '$0.00',
                templateDisplay: acct.matchedTemplateName || '(none)'
            }));
            this.totalAccounts = preview.totalAccounts;
            this.accountsWithContact = preview.accountsWithContact;
            this.accountsWithoutContact = preview.accountsWithoutContact;
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleSkipChange(event) {
        const idx = parseInt(event.target.dataset.index, 10);
        this.accounts = this.accounts.map((acct, i) => {
            if (i === idx) {
                return { ...acct, skip: event.target.checked, skipChecked: event.target.checked };
            }
            return acct;
        });
    }

    handleFormatChange(event) {
        this.attachmentFormat = event.detail.value;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSend() {
        this.isSending = true;
        try {
            const accountConfigs = this.accounts.map(acct => ({
                accountId: acct.accountId,
                contactEmail: acct.contactEmail,
                contactId: acct.contactId,
                templateId: acct.matchedTemplateId,
                taskIds: acct.taskIds,
                skip: acct.skip
            }));

            const configJson = JSON.stringify({
                attachmentFormat: this.attachmentFormat,
                accounts: accountConfigs
            });

            const result = await executeMassEmail({ configJson });

            let message = `${result.emailsSent} email(s) sent`;
            if (result.skipped > 0) message += `, ${result.skipped} skipped`;
            if (result.failed > 0) message += `, ${result.failed} failed`;

            this.showToast('Mass Email Complete', message,
                result.failed > 0 ? 'warning' : 'success');

            this.dispatchEvent(new CustomEvent('save'));
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        } finally {
            this.isSending = false;
        }
    }

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
