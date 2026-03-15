import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRecommendation from '@salesforce/apex/ARF_PaymentPlanController.getRecommendation';
import createPlan from '@salesforce/apex/ARF_PaymentPlanController.createPlan';

export default class ArfPortalPaymentPlan extends LightningElement {
    @api recordId; // Account ID
    @track currentStep = 1;
    @track invoices = [];
    @track recommendation = {};
    @track selectedOptionIndex = 0;

    customInstallments = 3;
    customFrequency = 'Monthly';
    customStartDate;
    autoPay = false;
    termsAccepted = false;
    isLoadingInvoices = true;
    isLoadingRecommendation = false;
    isSubmitting = false;
    createdPlanId = '';
    selectedTotal = 0;

    connectedCallback() {
        this.customStartDate = this.getDefaultStartDate();
        // In real usage, load invoices from Apex
        this.isLoadingInvoices = false;
    }

    get steps() {
        const stepLabels = ['Select Invoices', 'Recommendations', 'Customize', 'Review', 'Confirmed'];
        return stepLabels.map((label, i) => ({
            num: i + 1,
            label,
            completed: i + 1 < this.currentStep,
            className: i + 1 === this.currentStep ? 'step-item step-active' : i + 1 < this.currentStep ? 'step-item step-completed' : 'step-item',
            circleClass: i + 1 === this.currentStep ? 'step-circle step-circle-active' : i + 1 < this.currentStep ? 'step-circle step-circle-completed' : 'step-circle'
        }));
    }

    get progressStyle() { return 'width: ' + ((this.currentStep - 1) / 4 * 100) + '%'; }
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }
    get isStep5() { return this.currentStep === 5; }
    get isLastStep() { return this.currentStep === 4; }
    get hasInvoices() { return this.invoices.length > 0; }

    get selectedInvoices() { return this.invoices.filter(i => i.selected); }
    get selectedCount() { return this.selectedInvoices.length; }
    get selectedIds() { return this.selectedInvoices.map(i => i.Id); }
    get formattedSelectedTotal() { return '$' + this.selectedTotal.toLocaleString('en-US', {minimumFractionDigits: 2}); }
    get maxInstallments() { return this.recommendation.maxInstallments || 6; }

    get formattedInstallmentAmount() {
        const amt = this.selectedTotal / (this.customInstallments || 1);
        return '$' + amt.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2});
    }

    get planDuration() {
        const freqDays = this.customFrequency === 'Weekly' ? 7 : this.customFrequency === 'Bi_Weekly' ? 14 : 30;
        const totalDays = freqDays * this.customInstallments;
        return totalDays < 30 ? totalDays + ' days' : Math.round(totalDays / 30) + ' month(s)';
    }

    get customFrequencyLabel() {
        return this.customFrequency === 'Bi_Weekly' ? 'Bi-Weekly' : this.customFrequency;
    }
    get autoPayLabel() { return this.autoPay ? 'Enabled' : 'Disabled'; }
    get nextDisabled() {
        if (this.currentStep === 1) return this.selectedCount === 0;
        if (this.currentStep === 2) return false;
        return false;
    }
    get submitDisabled() { return !this.termsAccepted || this.isSubmitting; }

    get frequencyOptions() {
        return [
            { label: 'Weekly', value: 'Weekly' },
            { label: 'Bi-Weekly', value: 'Bi_Weekly' },
            { label: 'Monthly', value: 'Monthly' }
        ];
    }

    get minStartDate() {
        const d = new Date();
        d.setDate(d.getDate() + 1);
        return d.toISOString().split('T')[0];
    }

    handleInvoiceSelect(event) {
        const id = event.currentTarget.dataset.id;
        this.invoices = this.invoices.map(inv => {
            if (inv.Id === id) return { ...inv, selected: event.target.checked };
            return inv;
        });
        this.recalculateTotal();
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        this.invoices = this.invoices.map(inv => ({ ...inv, selected: checked }));
        this.recalculateTotal();
    }

    recalculateTotal() {
        this.selectedTotal = this.selectedInvoices.reduce((sum, inv) => sum + (inv.Balance__c || 0), 0);
    }

    handleSelectOption(event) {
        this.selectedOptionIndex = parseInt(event.currentTarget.dataset.index, 10);
        const option = this.recommendation.sampleSchedules[this.selectedOptionIndex];
        if (option) {
            this.customInstallments = option.installments;
            this.customFrequency = option.frequency;
        }
    }

    handleInstallmentsChange(event) { this.customInstallments = parseInt(event.target.value, 10); }
    handleFrequencyChange(event) { this.customFrequency = event.detail.value; }
    handleStartDateChange(event) { this.customStartDate = event.target.value; }
    handleAutoPayChange(event) { this.autoPay = event.target.checked; }
    handleTermsChange(event) { this.termsAccepted = event.target.checked; }

    async handleNext() {
        if (this.currentStep === 1 && this.selectedCount > 0) {
            this.currentStep = 2;
            await this.loadRecommendation();
        } else if (this.currentStep < 4) {
            this.currentStep++;
        }
    }

    handleBack() { if (this.currentStep > 1) this.currentStep--; }

    async loadRecommendation() {
        this.isLoadingRecommendation = true;
        try {
            const rec = await getRecommendation({ accountId: this.recordId, invoiceIds: this.selectedIds });
            // Enrich schedules for display
            rec.sampleSchedules = (rec.sampleSchedules || []).map((s, i) => ({
                ...s,
                key: 'opt-' + i,
                index: i,
                title: i === 0 ? 'Flexible' : i === 1 ? 'Balanced' : 'Quick Pay',
                isRecommended: i === 0,
                cardClass: i === this.selectedOptionIndex ? 'option-card option-card-selected' : 'option-card',
                frequencyLabel: s.frequency === 'Bi_Weekly' ? 'Bi-Weekly' : s.frequency,
                frequencyShort: s.frequency === 'Monthly' ? 'month' : s.frequency === 'Bi_Weekly' ? '2 weeks' : 'week',
                formattedInstallment: '$' + (s.installmentAmount || 0).toLocaleString('en-US', {minimumFractionDigits: 2}),
                formattedDownPayment: s.downPayment > 0 ? '$' + s.downPayment.toLocaleString('en-US', {minimumFractionDigits: 2}) : 'None',
                formattedFirstPayment: s.firstPayment || 'TBD',
                formattedLastPayment: s.lastPayment || 'TBD',
                formattedTotal: '$' + (s.totalWithFees || 0).toLocaleString('en-US', {minimumFractionDigits: 2})
            }));
            this.recommendation = rec;
            if (rec.sampleSchedules.length > 0) {
                this.customInstallments = rec.sampleSchedules[0].installments;
                this.customFrequency = rec.sampleSchedules[0].frequency;
            }
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Failed to get recommendation', 'error');
        } finally {
            this.isLoadingRecommendation = false;
        }
    }

    async handleSubmit() {
        this.isSubmitting = true;
        try {
            const planId = await createPlan({
                request: {
                    accountId: this.recordId,
                    invoiceIds: this.selectedIds,
                    installments: this.customInstallments,
                    frequency: this.customFrequency,
                    startDate: this.customStartDate,
                    autoPayEnabled: this.autoPay,
                    paymentMethodId: null,
                    createdByCustomer: true
                }
            });
            this.createdPlanId = planId;
            this.currentStep = 5;
            this.showToast('Success', 'Payment plan created successfully', 'success');
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Failed to create plan', 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    getDefaultStartDate() {
        const d = new Date();
        d.setDate(d.getDate() + 7);
        return d.toISOString().split('T')[0];
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
