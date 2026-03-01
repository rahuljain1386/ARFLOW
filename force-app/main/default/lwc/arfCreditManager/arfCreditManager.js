import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApplications from '@salesforce/apex/ARF_CreditApplicationController.getApplications';
import getApplicationDetail from '@salesforce/apex/ARF_CreditApplicationController.getApplicationDetail';
import evaluateApplication from '@salesforce/apex/ARF_CreditApplicationController.evaluateApplication';
import runCreditCheck from '@salesforce/apex/ARF_CreditApplicationController.runCreditCheck';
import approveApplication from '@salesforce/apex/ARF_CreditApplicationController.approveApplication';
import declineApplication from '@salesforce/apex/ARF_CreditApplicationController.declineApplication';
import createAccountFromApplication from '@salesforce/apex/ARF_CreditApplicationController.createAccountFromApplication';

const STATUS_TABS = [
    { label: 'All', value: 'All' },
    { label: 'Draft', value: 'Draft' },
    { label: 'Submitted', value: 'Submitted' },
    { label: 'Under Review', value: 'Under Review' },
    { label: 'Approved', value: 'Approved' },
    { label: 'Declined', value: 'Declined' }
];

const LIST_COLUMNS = [
    {
        label: 'Application #', fieldName: 'Name', type: 'text', sortable: true,
        cellAttributes: { class: 'slds-text-link' }
    },
    { label: 'Company Name', fieldName: 'Legal_Name__c', type: 'text', sortable: true },
    {
        label: 'Status', fieldName: 'Status__c', type: 'text', sortable: true,
        cellAttributes: { class: { fieldName: 'statusClass' } }
    },
    {
        label: 'Requested Limit', fieldName: 'Requested_Credit_Limit__c', type: 'currency', sortable: true,
        typeAttributes: { currencyCode: 'USD', minimumFractionDigits: 0, maximumFractionDigits: 0 }
    },
    { label: 'Score', fieldName: 'Credit_Score__c', type: 'number', sortable: true },
    {
        label: 'Risk Rating', fieldName: 'Risk_Rating__c', type: 'text', sortable: true,
        cellAttributes: { class: { fieldName: 'riskClass' } }
    },
    {
        label: 'Submitted Date', fieldName: 'Submitted_Date__c', type: 'date', sortable: true,
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [{ label: 'View', name: 'view' }]
        }
    }
];

export default class ArfCreditManager extends LightningElement {
    // View state
    currentView = 'list'; // 'list' or 'detail'
    activeStatusTab = 'All';
    statusTabs = STATUS_TABS;

    // List data
    @track applications = [];
    columns = LIST_COLUMNS;
    isLoading = true;
    sortField = 'CreatedDate';
    sortDirection = 'desc';

    // Detail data
    selectedApplicationId = null;
    @track detail = null;
    @track application = {};
    @track applicants = [];
    @track tradeReferences = [];
    @track bankReferences = [];
    @track guarantors = [];
    @track creditChecks = [];
    isDetailLoading = false;
    activeDetailTab = 'company';

    // Scoring / evaluation
    @track scoringResult = null;

    // Approve modal
    showApproveModal = false;
    approvedLimit = null;
    approveNotes = '';

    // Decline modal
    showDeclineModal = false;
    declineNotes = '';

    // Processing flags
    isProcessing = false;

    // ===== COMPUTED: LIST VIEW =====

    get isListView() {
        return this.currentView === 'list';
    }

    get isDetailView() {
        return this.currentView === 'detail';
    }

    get applicationCount() {
        return this.applications.length;
    }

    get computedStatusTabs() {
        return this.statusTabs.map(tab => ({
            ...tab,
            cssClass: 'status-tab' + (this.activeStatusTab === tab.value ? ' status-tab-active' : '')
        }));
    }

    // ===== COMPUTED: DETAIL VIEW =====

    get companyName() {
        return this.application.Legal_Name__c || 'Application';
    }

    get applicationStatus() {
        return this.application.Status__c || '';
    }

    get statusBadgeClass() {
        const status = this.applicationStatus;
        const base = 'status-badge';
        switch (status) {
            case 'Draft': return base + ' status-draft';
            case 'Submitted': return base + ' status-submitted';
            case 'Under Review': return base + ' status-under-review';
            case 'Approved': return base + ' status-approved';
            case 'Declined': return base + ' status-declined';
            default: return base;
        }
    }

    get isCompanyTab() { return this.activeDetailTab === 'company'; }
    get isReferencesTab() { return this.activeDetailTab === 'references'; }
    get isGuarantorsTab() { return this.activeDetailTab === 'guarantors'; }
    get isTaxTab() { return this.activeDetailTab === 'tax'; }
    get isCreditChecksTab() { return this.activeDetailTab === 'creditChecks'; }

    // Detail tab CSS classes
    get companyTabClass() { return 'detail-tab' + (this.isCompanyTab ? ' detail-tab-active' : ''); }
    get referencesTabClass() { return 'detail-tab' + (this.isReferencesTab ? ' detail-tab-active' : ''); }
    get guarantorsTabClass() { return 'detail-tab' + (this.isGuarantorsTab ? ' detail-tab-active' : ''); }
    get taxTabClass() { return 'detail-tab' + (this.isTaxTab ? ' detail-tab-active' : ''); }
    get creditChecksTabClass() { return 'detail-tab' + (this.isCreditChecksTab ? ' detail-tab-active' : ''); }

    get hasTradeReferences() { return this.tradeReferences.length > 0; }
    get hasBankReferences() { return this.bankReferences.length > 0; }
    get hasGuarantors() { return this.guarantors.length > 0; }
    get hasCreditChecks() { return this.creditChecks.length > 0; }
    get hasApplicants() { return this.applicants.length > 0; }

    // Credit score display
    get creditScore() {
        return this.application.Credit_Score__c || 0;
    }

    get hasCreditScore() {
        return this.application.Credit_Score__c != null && this.application.Credit_Score__c > 0;
    }

    get creditScoreLabel() {
        const score = this.creditScore;
        if (score >= 80) return 'Excellent';
        if (score >= 60) return 'Good';
        if (score >= 40) return 'Fair';
        if (score >= 20) return 'Poor';
        return 'Very Poor';
    }

    get creditScoreClass() {
        const score = this.creditScore;
        if (score >= 80) return 'score-excellent';
        if (score >= 60) return 'score-good';
        if (score >= 40) return 'score-fair';
        if (score >= 20) return 'score-poor';
        return 'score-very-poor';
    }

    get scoreGaugeStyle() {
        const score = this.creditScore;
        const pct = Math.min(Math.max(score, 0), 100);
        return `width: ${pct}%`;
    }

    get riskRating() {
        return this.application.Risk_Rating__c || 'N/A';
    }

    get riskBadgeClass() {
        const rating = this.riskRating;
        const base = 'risk-badge';
        switch (rating) {
            case 'Low': return base + ' risk-low';
            case 'Medium': return base + ' risk-medium';
            case 'High': return base + ' risk-high';
            case 'Very High': return base + ' risk-very-high';
            default: return base;
        }
    }

    // Action button visibility
    get canRunCreditCheck() {
        const s = this.applicationStatus;
        return s === 'Submitted' || s === 'Under Review';
    }

    get canEvaluate() {
        const s = this.applicationStatus;
        return s === 'Submitted' || s === 'Under Review';
    }

    get canApprove() {
        const s = this.applicationStatus;
        return s === 'Submitted' || s === 'Under Review';
    }

    get canDecline() {
        const s = this.applicationStatus;
        return s === 'Submitted' || s === 'Under Review';
    }

    get canCreateAccount() {
        return this.applicationStatus === 'Approved' && !this.application.Account__c;
    }

    get hasAccountLinked() {
        return this.application.Account__c != null;
    }

    // Scoring result getters
    get hasScoringResult() {
        return this.scoringResult != null;
    }

    get scoringRecommendation() {
        return this.scoringResult ? this.scoringResult.recommendation : '';
    }

    get scoringScore() {
        return this.scoringResult ? this.scoringResult.score : null;
    }

    get scoringRiskRating() {
        return this.scoringResult ? this.scoringResult.riskRating : '';
    }

    get scoringRiskFactors() {
        if (!this.scoringResult || !this.scoringResult.riskFactors) return [];
        return this.scoringResult.riskFactors.map((f, i) => ({ key: i, text: f }));
    }

    get hasScoringRiskFactors() {
        return this.scoringRiskFactors.length > 0;
    }

    // Formatted fields
    get formattedRequestedLimit() {
        return this.formatCurrency(this.application.Requested_Credit_Limit__c);
    }

    get formattedApprovedLimit() {
        return this.formatCurrency(this.application.Approved_Credit_Limit__c);
    }

    get formattedAnnualRevenue() {
        return this.formatCurrency(this.application.Annual_Revenue__c);
    }

    get formattedSubmittedDate() {
        return this.formatDate(this.application.Submitted_Date__c);
    }

    get formattedDecisionDate() {
        return this.formatDate(this.application.Decision_Date__c);
    }

    get formattedDateEstablished() {
        return this.formatDate(this.application.Date_Established__c);
    }

    get billingAddress() {
        const a = this.application;
        const parts = [a.Billing_Street__c, a.Billing_City__c, a.Billing_State__c, a.Billing_Zip__c, a.Billing_Country__c];
        return parts.filter(Boolean).join(', ');
    }

    get shippingAddress() {
        const a = this.application;
        const parts = [a.Shipping_Street__c, a.Shipping_City__c, a.Shipping_State__c, a.Shipping_Zip__c, a.Shipping_Country__c];
        return parts.filter(Boolean).join(', ');
    }

    get hasBillingAddress() {
        return this.billingAddress.length > 0;
    }

    get hasShippingAddress() {
        return this.shippingAddress.length > 0;
    }

    // ===== LIFECYCLE =====

    connectedCallback() {
        this.loadApplications();
    }

    // ===== DATA LOADING =====

    async loadApplications() {
        this.isLoading = true;
        try {
            const result = await getApplications({ statusFilter: this.activeStatusTab });
            this.applications = (result || []).map(app => ({
                ...app,
                statusClass: this.getStatusCellClass(app.Status__c),
                riskClass: this.getRiskCellClass(app.Risk_Rating__c)
            }));
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async loadApplicationDetail() {
        this.isDetailLoading = true;
        this.scoringResult = null;
        try {
            const result = await getApplicationDetail({ applicationId: this.selectedApplicationId });
            this.application = result.application || {};
            this.applicants = result.applicants || [];
            this.tradeReferences = result.tradeReferences || [];
            this.bankReferences = result.bankReferences || [];
            this.guarantors = result.guarantors || [];
            this.creditChecks = result.creditChecks || [];
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        } finally {
            this.isDetailLoading = false;
        }
    }

    // ===== LIST VIEW HANDLERS =====

    handleStatusTabClick(event) {
        this.activeStatusTab = event.currentTarget.dataset.status;
        this.loadApplications();
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortField = fieldName;
        this.sortDirection = sortDirection;
        this.sortApplications();
    }

    sortApplications() {
        const field = this.sortField;
        const dir = this.sortDirection === 'asc' ? 1 : -1;
        this.applications = [...this.applications].sort((a, b) => {
            let valA = a[field] || '';
            let valB = b[field] || '';
            if (typeof valA === 'string') valA = valA.toLowerCase();
            if (typeof valB === 'string') valB = valB.toLowerCase();
            if (valA < valB) return -1 * dir;
            if (valA > valB) return 1 * dir;
            return 0;
        });
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        if (action.name === 'view') {
            this.navigateToDetail(row.Id);
        }
    }

    handleCellClick(event) {
        const rowId = event.detail.row.Id;
        const col = event.detail.column;
        if (col.fieldName === 'Name') {
            this.navigateToDetail(rowId);
        }
    }

    handleRefresh() {
        this.loadApplications();
    }

    // ===== DETAIL VIEW NAVIGATION =====

    navigateToDetail(applicationId) {
        this.selectedApplicationId = applicationId;
        this.currentView = 'detail';
        this.activeDetailTab = 'company';
        this.loadApplicationDetail();
    }

    handleBackToList() {
        this.currentView = 'list';
        this.selectedApplicationId = null;
        this.detail = null;
        this.application = {};
        this.scoringResult = null;
        this.loadApplications();
    }

    handleDetailTabClick(event) {
        this.activeDetailTab = event.currentTarget.dataset.tab;
    }

    // ===== STAFF ACTIONS =====

    async handleRunCreditCheck() {
        this.isProcessing = true;
        try {
            const result = await runCreditCheck({
                applicationId: this.selectedApplicationId,
                agency: 'DnB'
            });
            this.scoringResult = result;
            this.showToast('Success', 'Credit check completed successfully', 'success');
            await this.loadApplicationDetail();
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    async handleEvaluate() {
        this.isProcessing = true;
        try {
            const result = await evaluateApplication({
                applicationId: this.selectedApplicationId
            });
            this.scoringResult = result;
            this.showToast('Success', 'Risk evaluation completed', 'success');
            await this.loadApplicationDetail();
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    // Approve flow
    handleOpenApproveModal() {
        this.approvedLimit = this.application.Requested_Credit_Limit__c || 0;
        this.approveNotes = '';
        // Pre-fill with recommendation if available
        if (this.scoringResult && this.scoringResult.recommendation) {
            const match = this.scoringResult.recommendation.match(/[\d,]+/);
            if (match) {
                this.approvedLimit = parseFloat(match[0].replace(/,/g, ''));
            }
        }
        this.showApproveModal = true;
    }

    handleApprovedLimitChange(event) {
        this.approvedLimit = event.detail.value;
    }

    handleApproveNotesChange(event) {
        this.approveNotes = event.detail.value;
    }

    handleApproveCancel() {
        this.showApproveModal = false;
    }

    async handleApproveConfirm() {
        if (!this.approvedLimit || this.approvedLimit <= 0) {
            this.showToast('Error', 'Please enter a valid credit limit', 'error');
            return;
        }
        this.isProcessing = true;
        this.showApproveModal = false;
        try {
            await approveApplication({
                applicationId: this.selectedApplicationId,
                approvedLimit: this.approvedLimit,
                notes: this.approveNotes
            });
            this.showToast('Success', 'Application approved', 'success');
            await this.loadApplicationDetail();
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    // Decline flow
    handleOpenDeclineModal() {
        this.declineNotes = '';
        this.showDeclineModal = true;
    }

    handleDeclineNotesChange(event) {
        this.declineNotes = event.detail.value;
    }

    handleDeclineCancel() {
        this.showDeclineModal = false;
    }

    async handleDeclineConfirm() {
        this.isProcessing = true;
        this.showDeclineModal = false;
        try {
            await declineApplication({
                applicationId: this.selectedApplicationId,
                notes: this.declineNotes
            });
            this.showToast('Success', 'Application declined', 'success');
            await this.loadApplicationDetail();
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    // Create Account
    async handleCreateAccount() {
        this.isProcessing = true;
        try {
            await createAccountFromApplication({
                applicationId: this.selectedApplicationId
            });
            this.showToast('Success', 'Account and contacts created successfully', 'success');
            await this.loadApplicationDetail();
        } catch (error) {
            this.showToast('Error', this.extractError(error), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    // ===== UTILITIES =====

    getStatusCellClass(status) {
        switch (status) {
            case 'Approved': return 'slds-text-color_success';
            case 'Declined': return 'slds-text-color_error';
            case 'Submitted': return 'slds-text-color_default';
            case 'Under Review': return 'status-cell-review';
            default: return 'slds-text-color_weak';
        }
    }

    getRiskCellClass(rating) {
        switch (rating) {
            case 'Low': return 'slds-text-color_success';
            case 'Medium': return 'risk-cell-medium';
            case 'High': return 'risk-cell-high';
            case 'Very High': return 'slds-text-color_error';
            default: return '';
        }
    }

    formatCurrency(value) {
        if (value == null) return '--';
        return new Intl.NumberFormat('en-US', {
            style: 'currency', currency: 'USD',
            minimumFractionDigits: 0, maximumFractionDigits: 0
        }).format(value);
    }

    formatDate(value) {
        if (!value) return '--';
        return new Date(value).toLocaleDateString('en-US', {
            year: 'numeric', month: 'short', day: '2-digit'
        });
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
