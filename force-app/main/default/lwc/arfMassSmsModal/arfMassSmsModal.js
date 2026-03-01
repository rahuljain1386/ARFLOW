import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import prepareMassSms from '@salesforce/apex/ARF_WorklistController.prepareMassSms';
import executeMassSms from '@salesforce/apex/ARF_WorklistController.executeMassSms';

export default class ArfMassSmsModal extends LightningElement {
    @api taskIds = [];

    @track accounts = [];
    isLoading = true;
    isSending = false;

    totalAccounts = 0;
    accountsWithPhone = 0;
    accountsWithoutPhone = 0;

    smsMessage = '';

    get smsCharCount() {
        return (this.smsMessage || '').length;
    }

    get smsCharLabel() {
        return `${this.smsCharCount}/160`;
    }

    get sendableCount() {
        return this.accounts.filter(a => !a.skip && a.hasContact).length;
    }

    get isSendDisabled() {
        return this.isSending || this.sendableCount === 0 || !this.smsMessage;
    }

    get sendButtonLabel() {
        return this.isSending ? 'Sending...' : `Send ${this.sendableCount} SMS`;
    }

    connectedCallback() {
        this.loadPreview();
    }

    async loadPreview() {
        this.isLoading = true;
        try {
            const preview = await prepareMassSms({ taskIds: this.taskIds });
            this.accounts = (preview.accounts || []).map((acct, idx) => ({
                ...acct,
                index: idx,
                skipChecked: acct.skip,
                disableSkip: !acct.hasContact,
                statusIcon: acct.hasContact ? 'utility:check' : 'utility:warning',
                statusVariant: acct.hasContact ? 'success' : 'warning'
            }));
            this.totalAccounts = preview.totalAccounts;
            this.accountsWithPhone = preview.accountsWithPhone;
            this.accountsWithoutPhone = preview.accountsWithoutPhone;
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleMessageChange(event) {
        const val = event.detail.value || '';
        this.smsMessage = val.length > 160 ? val.substring(0, 160) : val;
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

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSend() {
        this.isSending = true;
        try {
            const accountConfigs = this.accounts.map(acct => ({
                accountId: acct.accountId,
                contactId: acct.contactId,
                contactPhone: acct.contactPhone,
                taskIds: acct.taskIds,
                skip: acct.skip
            }));

            const configJson = JSON.stringify({
                message: this.smsMessage,
                accounts: accountConfigs
            });

            const result = await executeMassSms({ configJson });

            let message = `${result.smsSent} SMS sent`;
            if (result.skipped > 0) message += `, ${result.skipped} skipped`;
            if (result.failed > 0) message += `, ${result.failed} failed`;

            this.showToast('Mass SMS Complete', message,
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
