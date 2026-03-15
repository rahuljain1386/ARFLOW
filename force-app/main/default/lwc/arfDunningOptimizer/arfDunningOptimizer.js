import { LightningElement, track, wire } from 'lwc';
import getDashboard from '@salesforce/apex/ARF_DunningOptimizer.getDashboard';
import recommendChannel from '@salesforce/apex/ARF_DunningOptimizer.recommendChannel';

const CHANNEL_ICONS = {
    'Email': 'standard:email',
    'SMS': 'standard:sms',
    'Phone': 'standard:call',
    'AI_Voice': 'standard:voice_call'
};

const CHANNEL_BAR_CLASSES = {
    'Email': 'chart-bar chart-bar--email',
    'SMS': 'chart-bar chart-bar--sms',
    'Phone': 'chart-bar chart-bar--phone',
    'AI_Voice': 'chart-bar chart-bar--ai-voice'
};

export default class ArfDunningOptimizer extends LightningElement {
    @track dashboardData;
    @track recommendation;
    @track isLoading = false;
    @track error;

    selectedAccountId;

    // Wire the dashboard data
    @wire(getDashboard)
    wiredDashboard({ error, data }) {
        if (data) {
            this.dashboardData = data;
            this.error = undefined;
        } else if (error) {
            this.error = this.reduceErrors(error);
            this.dashboardData = undefined;
        }
    }

    // KPI getters
    get totalAttempts() {
        return this.dashboardData ? this.formatNumber(this.dashboardData.totalAttempts) : '0';
    }

    get totalResponses() {
        return this.dashboardData ? this.formatNumber(this.dashboardData.totalResponses) : '0';
    }

    get overallResponseRate() {
        return this.dashboardData ? this.dashboardData.overallResponseRate : '0';
    }

    get totalCollected() {
        return this.dashboardData ? this.formatCurrency(this.dashboardData.totalCollected) : '0';
    }

    // Chart data for bar chart
    get chartData() {
        if (!this.dashboardData || !this.dashboardData.channelSummaries) {
            return [];
        }

        const maxRate = Math.max(
            ...this.dashboardData.channelSummaries.map(s => s.avgResponseRate || 0),
            1
        );

        return this.dashboardData.channelSummaries.map(summary => {
            const rate = summary.avgResponseRate || 0;
            const widthPercent = Math.max(5, (rate / maxRate) * 100);
            const barClass = CHANNEL_BAR_CLASSES[summary.channel] || 'chart-bar chart-bar--default';

            return {
                channel: summary.channel,
                responseRate: rate.toFixed(1),
                totalCollected: this.formatCurrency(summary.totalCollected),
                barStyle: `width: ${widthPercent}%`,
                barClass: barClass
            };
        });
    }

    // Channel summaries for table
    get channelSummaries() {
        if (!this.dashboardData || !this.dashboardData.channelSummaries) {
            return [];
        }

        return this.dashboardData.channelSummaries.map(summary => {
            const rate = summary.avgResponseRate || 0;
            let rateBadgeClass = 'rate-badge--low';
            if (rate >= 50) {
                rateBadgeClass = 'rate-badge--high';
            } else if (rate >= 25) {
                rateBadgeClass = 'rate-badge--medium';
            }

            return {
                channel: summary.channel,
                iconName: CHANNEL_ICONS[summary.channel] || 'standard:default',
                totalAttempts: this.formatNumber(summary.totalAttempts),
                totalResponses: this.formatNumber(summary.totalResponses),
                responseRateLabel: rate.toFixed(1) + '%',
                rateBadgeClass: rateBadgeClass,
                totalPayments: this.formatNumber(summary.totalPayments),
                totalCollected: this.formatCurrency(summary.totalCollected)
            };
        });
    }

    // Handle account selection
    handleAccountSelect(event) {
        const recordId = event.detail.recordId;
        if (recordId) {
            this.selectedAccountId = recordId;
            this.fetchRecommendation(recordId);
        } else {
            this.selectedAccountId = null;
            this.recommendation = null;
        }
    }

    // Fetch channel recommendation for selected account
    fetchRecommendation(accountId) {
        this.isLoading = true;
        this.recommendation = null;

        recommendChannel({ accountId: accountId })
            .then(result => {
                // Enrich channel scores with bar styles
                if (result.channelScores) {
                    const maxScore = Math.max(
                        ...result.channelScores.map(s => s.compositeScore || 0),
                        1
                    );
                    result.channelScores = result.channelScores.map(score => ({
                        ...score,
                        barStyle: `width: ${Math.max(5, (score.compositeScore / maxScore) * 100)}%`
                    }));
                }
                this.recommendation = result;
                this.error = undefined;
            })
            .catch(error => {
                this.error = this.reduceErrors(error);
                this.recommendation = null;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Utility: format number with commas
    formatNumber(value) {
        if (value === null || value === undefined) return '0';
        return Number(value).toLocaleString();
    }

    // Utility: format currency
    formatCurrency(value) {
        if (value === null || value === undefined) return '0.00';
        return Number(value).toLocaleString(undefined, {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }

    // Utility: reduce errors to string
    reduceErrors(error) {
        if (typeof error === 'string') {
            return error;
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        }
        return 'Unknown error';
    }
}
