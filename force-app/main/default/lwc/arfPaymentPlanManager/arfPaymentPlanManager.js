import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAccountPlans from '@salesforce/apex/ARF_PaymentPlanController.getAccountPlans';
import getPlanDetail from '@salesforce/apex/ARF_PaymentPlanController.getPlanDetail';
import reviewPlan from '@salesforce/apex/ARF_PaymentPlanController.reviewPlan';

export default class ArfPaymentPlanManager extends LightningElement {
    @track plans = [];
    @track selectedPlan = null;
    @track planDetail = null;
    isLoading = true;
    showDetailModal = false;
    activeFilter = 'All';

    // KPI metrics
    activePlanCount = 0;
    totalUnderPlan = 0;
    monthCollections = 0;
    defaultRate = 0;

    connectedCallback() { this.loadPlans(); }

    async loadPlans() {
        this.isLoading = true;
        try {
            // Load all plans (in real app, would query across accounts)
            // For now, showing structure
            this.isLoading = false;
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Failed to load plans', 'error');
            this.isLoading = false;
        }
    }

    async handleViewDetail(event) {
        const planId = event.currentTarget.dataset.id;
        try {
            this.planDetail = await getPlanDetail({ planId });
            this.showDetailModal = true;
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Failed to load plan details', 'error');
        }
    }

    async handleApprove(event) {
        const planId = event.currentTarget.dataset.id;
        try {
            await reviewPlan({ planId, action: 'approve', notes: '' });
            this.showToast('Success', 'Plan approved', 'success');
            this.loadPlans();
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Approval failed', 'error');
        }
    }

    async handleReject(event) {
        const planId = event.currentTarget.dataset.id;
        try {
            await reviewPlan({ planId, action: 'reject', notes: '' });
            this.showToast('Success', 'Plan rejected', 'success');
            this.loadPlans();
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Rejection failed', 'error');
        }
    }

    handleFilterChange(event) {
        this.activeFilter = event.currentTarget.dataset.filter;
    }

    handleCloseModal() { this.showDetailModal = false; this.planDetail = null; }

    handleOverlayClick() { this.handleCloseModal(); }

    handleModalContentClick(event) { event.stopPropagation(); }

    get filteredPlans() {
        if (this.activeFilter === 'All') return this.plans;
        return this.plans.filter(p => p.status === this.activeFilter);
    }

    get hasPlan() { return this.filteredPlans.length > 0; }

    get filterTabs() {
        const tabs = ['All', 'Pending_Approval', 'Active', 'Completed', 'Defaulted'];
        return tabs.map(t => ({
            label: t.replace(/_/g, ' '),
            value: t,
            className: this.activeFilter === t ? 'filter-tab filter-tab-active' : 'filter-tab',
            count: t === 'All' ? this.plans.length : this.plans.filter(p => p.status === t).length
        }));
    }

    get formattedTotalUnderPlan() {
        return '$' + this.totalUnderPlan.toLocaleString('en-US', { minimumFractionDigits: 0 });
    }

    get formattedMonthCollections() {
        return '$' + this.monthCollections.toLocaleString('en-US', { minimumFractionDigits: 0 });
    }

    get formattedDefaultRate() {
        return this.defaultRate.toFixed(1);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
