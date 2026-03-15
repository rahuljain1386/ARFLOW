import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import processPayments from '@salesforce/apex/ARF_CashApplicationEngine.processPayments';
import autoApplyMatches from '@salesforce/apex/ARF_CashApplicationEngine.autoApplyMatches';
import reviewMatch from '@salesforce/apex/ARF_CashApplicationEngine.reviewMatch';
import getStats from '@salesforce/apex/ARF_CashApplicationEngine.getStats';

export default class ArfCashApplication extends LightningElement {
    @track stats = {};
    @track results = [];
    @track selectedIds = new Set();
    isLoading = true;
    isProcessing = false;
    searchTerm = '';

    connectedCallback() { this.loadStats(); }

    async loadStats() {
        try {
            this.stats = await getStats();
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Failed to load stats', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleRunMatching() {
        this.isProcessing = true;
        try {
            this.showToast('Info', 'Select payments to run matching against', 'info');
        } finally {
            this.isProcessing = false;
        }
    }

    async handleAutoApplyAll() {
        const highConfIds = this.results
            .filter(r => r.confidence >= 90 && r.status === 'Pending_Review')
            .map(r => r.id);
        if (highConfIds.length === 0) {
            this.showToast('Info', 'No high-confidence matches to auto-apply', 'info');
            return;
        }
        this.isProcessing = true;
        try {
            const result = await autoApplyMatches({ resultIds: highConfIds });
            this.showToast('Success', `Applied ${result.successCount} matches ($${result.totalApplied.toFixed(2)})`, 'success');
            this.loadStats();
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Auto-apply failed', 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    async handleApprove(event) {
        const resultId = event.currentTarget.dataset.id;
        try {
            await reviewMatch({ resultId, action: 'approve', overrideAmount: null });
            this.showToast('Success', 'Match approved and applied', 'success');
            this.loadStats();
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Approve failed', 'error');
        }
    }

    async handleReject(event) {
        const resultId = event.currentTarget.dataset.id;
        try {
            await reviewMatch({ resultId, action: 'reject', overrideAmount: null });
            this.showToast('Success', 'Match rejected', 'success');
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Reject failed', 'error');
        }
    }

    handleCheckbox(event) {
        const id = event.currentTarget.dataset.id;
        if (event.target.checked) { this.selectedIds.add(id); }
        else { this.selectedIds.delete(id); }
        this.selectedIds = new Set(this.selectedIds);
    }

    handleSelectAll(event) {
        if (event.target.checked) {
            this.selectedIds = new Set(this.filteredResults.map(r => r.id));
        } else {
            this.selectedIds = new Set();
        }
    }

    handleSearch(event) { this.searchTerm = event.target.value.toLowerCase(); }

    async handleBulkApply() {
        if (this.selectedIds.size === 0) return;
        this.isProcessing = true;
        try {
            const result = await autoApplyMatches({ resultIds: Array.from(this.selectedIds) });
            this.showToast('Success', `Applied ${result.successCount} matches`, 'success');
            this.selectedIds = new Set();
            this.loadStats();
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Bulk apply failed', 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    async handleBulkReject() {
        if (this.selectedIds.size === 0) return;
        this.isProcessing = true;
        try {
            const promises = Array.from(this.selectedIds).map(id =>
                reviewMatch({ resultId: id, action: 'reject', overrideAmount: null })
            );
            await Promise.all(promises);
            this.showToast('Success', `Rejected ${this.selectedIds.size} matches`, 'success');
            this.selectedIds = new Set();
            this.loadStats();
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Bulk reject failed', 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    get filteredResults() {
        if (!this.searchTerm) return this.decoratedResults;
        return this.decoratedResults.filter(r =>
            (r.paymentRef && r.paymentRef.toLowerCase().includes(this.searchTerm)) ||
            (r.invoiceNum && r.invoiceNum.toLowerCase().includes(this.searchTerm)) ||
            (r.ruleName && r.ruleName.toLowerCase().includes(this.searchTerm))
        );
    }

    get decoratedResults() {
        return this.results.map(r => {
            const conf = r.confidence || 0;
            let confBarClass = 'confidence-fill';
            if (conf >= 90) confBarClass += ' confidence-high';
            else if (conf >= 70) confBarClass += ' confidence-medium';
            else confBarClass += ' confidence-low';

            let statusClass = 'status-badge';
            if (r.status === 'Auto_Applied') statusClass += ' status-applied';
            else if (r.status === 'Pending_Review') statusClass += ' status-pending';
            else if (r.status === 'Rejected') statusClass += ' status-rejected';
            else if (r.status === 'Manual') statusClass += ' status-manual';

            return {
                ...r,
                confBarClass,
                confBarStyle: `width: ${conf}%`,
                confLabel: conf + '%',
                statusClass,
                statusLabel: (r.status || '').replace(/_/g, ' '),
                isSelected: this.selectedIds.has(r.id),
                isPending: r.status === 'Pending_Review',
                rowClass: this.selectedIds.has(r.id) ? 'table-row row-selected' : 'table-row'
            };
        });
    }

    get hasResults() { return this.filteredResults.length > 0; }
    get showEmpty() { return !this.isLoading && !this.hasResults; }
    get hasSelection() { return this.selectedIds.size > 0; }
    get selectedCount() { return this.selectedIds.size; }
    get allSelected() {
        return this.filteredResults.length > 0 && this.filteredResults.every(r => this.selectedIds.has(r.id));
    }

    get formattedUnmatched() {
        return this.stats.unmatchedAmount ? '$' + this.formatNumber(this.stats.unmatchedAmount) : '$0';
    }
    get formattedAutoApplied() {
        return this.stats.autoAppliedAmount ? '$' + this.formatNumber(this.stats.autoAppliedAmount) : '$0';
    }
    get formattedPendingCount() { return this.stats.pendingReviewCount || 0; }
    get formattedMatchRate() {
        return this.stats.matchRate ? this.stats.matchRate.toFixed(1) + '%' : '0%';
    }

    formatNumber(val) {
        if (val >= 1000000) return (val / 1000000).toFixed(1) + 'M';
        if (val >= 1000) return (val / 1000).toFixed(1) + 'K';
        return val.toFixed(0);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
