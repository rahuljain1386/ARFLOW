import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchAccounts from '@salesforce/apex/ARF_EmailQueueController.searchAccounts';
import assignAccountToCommunication from '@salesforce/apex/ARF_EmailQueueController.assignAccountToCommunication';
import bulkAssignAccount from '@salesforce/apex/ARF_EmailQueueController.bulkAssignAccount';

export default class ArfAssignEmailModal extends LightningElement {
    @api communicationIds = [];
    @api isBulk = false;

    @track accountResults = [];
    @track selectedAccount = null;

    searchTerm = '';
    rememberSender = true;
    isSearching = false;
    isSaving = false;
    _debounceTimer;

    get hasResults() {
        return this.accountResults.length > 0;
    }

    get hasSelectedAccount() {
        return this.selectedAccount != null;
    }

    get modalTitle() {
        if (this.isBulk) {
            return `Assign Account to ${this.communicationIds.length} Email(s)`;
        }
        return 'Assign Account to Email';
    }

    get assignButtonLabel() {
        return this.isBulk ? `Assign to ${this.communicationIds.length} Email(s)` : 'Assign Account';
    }

    // === SEARCH ===

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
        clearTimeout(this._debounceTimer);

        if (this.searchTerm.length < 2) {
            this.accountResults = [];
            return;
        }

        // Debounce 300ms
        this._debounceTimer = setTimeout(() => {
            this.performSearch();
        }, 300);
    }

    async performSearch() {
        this.isSearching = true;
        try {
            const results = await searchAccounts({ searchText: this.searchTerm });
            this.accountResults = (results || []).map(acct => ({
                ...acct,
                displayAR: acct.TotalAR != null ? `$${Number(acct.TotalAR).toLocaleString()}` : '$0',
                isSelected: this.selectedAccount && this.selectedAccount.Id === acct.Id
            }));
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        } finally {
            this.isSearching = false;
        }
    }

    handleSelectAccount(event) {
        const accountId = event.currentTarget.dataset.id;
        const account = this.accountResults.find(a => a.Id === accountId);
        if (account) {
            this.selectedAccount = account;
            // Update selection state
            this.accountResults = this.accountResults.map(a => ({
                ...a,
                isSelected: a.Id === accountId
            }));
        }
    }

    // === REMEMBER SENDER ===

    handleRememberChange(event) {
        this.rememberSender = event.target.checked;
    }

    // === ACTIONS ===

    async handleAssign() {
        if (!this.selectedAccount) {
            this.showToast('Error', 'Please select an account', 'error');
            return;
        }

        this.isSaving = true;
        try {
            if (this.isBulk && this.communicationIds.length > 1) {
                await bulkAssignAccount({
                    communicationIds: this.communicationIds,
                    accountId: this.selectedAccount.Id,
                    saveSenderMapping: this.rememberSender
                });
            } else {
                await assignAccountToCommunication({
                    communicationId: this.communicationIds[0],
                    accountId: this.selectedAccount.Id,
                    saveSenderMapping: this.rememberSender
                });
            }

            this.showToast('Success',
                `Assigned to ${this.selectedAccount.Name}` +
                (this.rememberSender ? ' (sender remembered)' : ''),
                'success'
            );
            this.dispatchEvent(new CustomEvent('save'));
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
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
