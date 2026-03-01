import { LightningElement, api, wire, track } from 'lwc';
import getPaymentMethods from '@salesforce/apex/ARF_PaymentPortalController.getPaymentMethods';
import addCreditCard from '@salesforce/apex/ARF_PaymentPortalController.addCreditCard';
import addBankAccount from '@salesforce/apex/ARF_PaymentPortalController.addBankAccount';
import removePaymentMethod from '@salesforce/apex/ARF_PaymentPortalController.removePaymentMethod';
import setDefaultPaymentMethod from '@salesforce/apex/ARF_PaymentPortalController.setDefaultPaymentMethod';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class ArfPortalPaymentMethods extends LightningElement {
    @api accountId;
    @track methods = [];
    @track isLoading = true;
    @track showAddForm = false;
    @track addType = 'card'; // 'card' or 'ach'
    @track isSaving = false;
    @track error;
    _wiredResult;

    // Card fields
    @track cardNumber = '';
    @track expMonth = '';
    @track expYear = '';
    @track cvv = '';
    @track cardholderName = '';
    @track cardNickname = '';

    // ACH fields
    @track routingNumber = '';
    @track accountNumber = '';
    @track achAccountType = 'Checking';
    @track accountHolderName = '';
    @track bankName = '';
    @track achNickname = '';

    @wire(getPaymentMethods, { accountId: '$accountId' })
    wiredMethods(result) {
        this._wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.methods = result.data.map(m => ({
                ...m,
                icon: m.methodType === 'Credit Card' ? 'standard:record' : 'standard:record',
                typeIcon: m.methodType === 'Credit Card' ? 'utility:money' : 'utility:bank',
                primaryBadge: m.isPrimary,
                expiryDisplay: m.expiryMonth && m.expiryYear ? m.expiryMonth + '/' + m.expiryYear : ''
            }));
        } else if (result.error) {
            this.error = 'Failed to load payment methods';
        }
    }

    get hasMethods() {
        return this.methods.length > 0;
    }

    get isCardType() {
        return this.addType === 'card';
    }

    get isAchType() {
        return this.addType === 'ach';
    }

    get addTypeOptions() {
        return [
            { label: 'Credit Card', value: 'card' },
            { label: 'Bank Account (ACH)', value: 'ach' }
        ];
    }

    get achAccountTypeOptions() {
        return [
            { label: 'Checking', value: 'Checking' },
            { label: 'Savings', value: 'Savings' }
        ];
    }

    get monthOptions() {
        return Array.from({ length: 12 }, (_, i) => {
            const m = String(i + 1).padStart(2, '0');
            return { label: m, value: m };
        });
    }

    get yearOptions() {
        const currentYear = new Date().getFullYear();
        return Array.from({ length: 10 }, (_, i) => {
            const y = String(currentYear + i);
            return { label: y, value: y };
        });
    }

    get saveLabel() {
        return this.isSaving ? 'Saving...' : 'Save Payment Method';
    }

    handleShowAddForm() {
        this.showAddForm = true;
        this.resetForm();
    }

    handleCancelAdd() {
        this.showAddForm = false;
        this.resetForm();
    }

    handleTypeChange(event) {
        this.addType = event.detail.value;
    }

    // Card handlers
    handleCardNumberChange(event) { this.cardNumber = event.detail.value; }
    handleExpMonthChange(event) { this.expMonth = event.detail.value; }
    handleExpYearChange(event) { this.expYear = event.detail.value; }
    handleCvvChange(event) { this.cvv = event.detail.value; }
    handleCardholderChange(event) { this.cardholderName = event.detail.value; }
    handleCardNicknameChange(event) { this.cardNickname = event.detail.value; }

    // ACH handlers
    handleRoutingChange(event) { this.routingNumber = event.detail.value; }
    handleAccountNumberChange(event) { this.accountNumber = event.detail.value; }
    handleAchTypeChange(event) { this.achAccountType = event.detail.value; }
    handleAccountHolderChange(event) { this.accountHolderName = event.detail.value; }
    handleBankNameChange(event) { this.bankName = event.detail.value; }
    handleAchNicknameChange(event) { this.achNickname = event.detail.value; }

    async handleSaveMethod() {
        this.isSaving = true;
        this.error = undefined;

        try {
            if (this.addType === 'card') {
                await addCreditCard({
                    accountId: this.accountId,
                    cardNumber: this.cardNumber,
                    expMonth: this.expMonth,
                    expYear: this.expYear,
                    cvv: this.cvv,
                    cardholderName: this.cardholderName,
                    nickname: this.cardNickname
                });
            } else {
                await addBankAccount({
                    accountId: this.accountId,
                    routingNumber: this.routingNumber,
                    accountNumber: this.accountNumber,
                    accountType: this.achAccountType,
                    accountHolderName: this.accountHolderName,
                    bankName: this.bankName,
                    nickname: this.achNickname
                });
            }

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Payment method added successfully',
                variant: 'success'
            }));
            this.showAddForm = false;
            this.resetForm();
            await refreshApex(this._wiredResult);
        } catch (err) {
            this.error = err.body ? err.body.message : 'Failed to save payment method';
        } finally {
            this.isSaving = false;
        }
    }

    async handleRemove(event) {
        const junctionId = event.currentTarget.dataset.junctionid;
        try {
            await removePaymentMethod({ junctionId: junctionId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Removed',
                message: 'Payment method removed',
                variant: 'success'
            }));
            await refreshApex(this._wiredResult);
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err.body ? err.body.message : 'Failed to remove',
                variant: 'error'
            }));
        }
    }

    async handleSetDefault(event) {
        const junctionId = event.currentTarget.dataset.junctionid;
        try {
            await setDefaultPaymentMethod({
                accountId: this.accountId,
                junctionId: junctionId
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Updated',
                message: 'Default payment method updated',
                variant: 'success'
            }));
            await refreshApex(this._wiredResult);
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err.body ? err.body.message : 'Failed to update',
                variant: 'error'
            }));
        }
    }

    resetForm() {
        this.cardNumber = '';
        this.expMonth = '';
        this.expYear = '';
        this.cvv = '';
        this.cardholderName = '';
        this.cardNickname = '';
        this.routingNumber = '';
        this.accountNumber = '';
        this.achAccountType = 'Checking';
        this.accountHolderName = '';
        this.bankName = '';
        this.achNickname = '';
        this.error = undefined;
    }
}
