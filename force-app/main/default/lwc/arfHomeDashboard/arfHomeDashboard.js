import { LightningElement, wire } from 'lwc';
import getDashboardData from '@salesforce/apex/ARF_HomeDashboardController.getDashboardData';
import { refreshApex } from '@salesforce/apex';

export default class ArfHomeDashboard extends LightningElement {
    data;
    error;
    isLoading = true;
    _wiredResult;

    @wire(getDashboardData)
    wiredDashboard(result) {
        this._wiredResult = result;
        if (result.data) {
            this.data = result.data;
            this.isLoading = false;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.isLoading = false;
            this.data = undefined;
        }
    }

    get hasData() {
        return this.data != null && !this.isLoading;
    }

    get hasError() {
        return this.error != null && !this.isLoading;
    }

    get hasTopAccounts() {
        return this.data?.topAccounts?.length > 0;
    }

    get hasPaymentTrend() {
        return this.data?.paymentTrend?.length > 0;
    }

    get hasActivity() {
        return this.data?.recentActivity?.length > 0;
    }

    /* ── Top Accounts with bar widths ── */
    get topAccountsComputed() {
        if (!this.data?.topAccounts?.length) return [];
        const max = this.data.topAccounts[0].balance;
        return this.data.topAccounts.map(acct => ({
            ...acct,
            barStyle: `width: ${max > 0 ? (acct.balance / max) * 100 : 0}%`,
            formattedBalance: this._formatCompact(acct.balance)
        }));
    }

    /* ── Aging buckets with percentages ── */
    get agingComputed() {
        if (!this.data?.agingBuckets?.length) return [];
        const total = this.data.agingBuckets.reduce((s, b) => s + (b.amount || 0), 0);
        return this.data.agingBuckets.map(b => ({
            ...b,
            pct: total > 0 ? Math.round((b.amount / total) * 100) : 0,
            formattedAmount: this._formatCompact(b.amount),
            dotStyle: `background: ${b.color}`
        }));
    }

    get agingDonutStyle() {
        if (!this.data?.agingBuckets?.length) return 'background: #e2e8f0';
        const total = this.data.agingBuckets.reduce((s, b) => s + (b.amount || 0), 0);
        if (total === 0) return 'background: #e2e8f0';

        const segments = [];
        let cumPct = 0;
        for (const b of this.data.agingBuckets) {
            const pct = (b.amount / total) * 100;
            if (pct > 0) {
                segments.push(`${b.color} ${cumPct}% ${cumPct + pct}%`);
            }
            cumPct += pct;
        }
        return `background: conic-gradient(${segments.join(', ')})`;
    }

    get agingTotalFormatted() {
        if (!this.data?.agingBuckets?.length) return '$0';
        const total = this.data.agingBuckets.reduce((s, b) => s + (b.amount || 0), 0);
        return this._formatCompact(total);
    }

    /* ── Payment trend with bar heights ── */
    get paymentTrendComputed() {
        if (!this.data?.paymentTrend?.length) return [];
        const max = Math.max(...this.data.paymentTrend.map(m => m.amount || 0));
        return this.data.paymentTrend.map(m => ({
            ...m,
            barStyle: `height: ${max > 0 ? (m.amount / max) * 100 : 0}%`,
            formattedAmount: this._formatCompact(m.amount)
        }));
    }

    /* ── Helpers ── */
    _formatCompact(value) {
        if (value == null || value === 0) return '$0';
        if (value >= 1000000) return '$' + (value / 1000000).toFixed(1) + 'M';
        if (value >= 1000) return '$' + Math.round(value / 1000) + 'K';
        return '$' + Math.round(value);
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this._wiredResult);
    }
}
