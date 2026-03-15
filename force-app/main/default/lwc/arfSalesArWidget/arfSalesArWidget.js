import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getArSummary from '@salesforce/apex/ARF_SalesArController.getArSummary';

export default class ArfSalesArWidget extends NavigationMixin(LightningElement) {
    @api recordId;
    summary;
    error;
    isLoading = true;

    @wire(getArSummary, { accountId: '$recordId' })
    wiredSummary({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.summary = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.summary = undefined;
        }
    }

    get hasData() {
        return this.summary && this.summary.totalAR > 0;
    }

    get formattedTotalAR() {
        return this.summary ? this.formatCurrency(this.summary.totalAR) : '$0';
    }

    get formattedPastDue() {
        return this.summary ? this.formatCurrency(this.summary.pastDue) : '$0';
    }

    get formattedDSO() {
        return this.summary ? Math.round(this.summary.dso) : 0;
    }

    get pastDueClass() {
        return this.summary && this.summary.pastDue > 0
            ? 'metric-value metric-value-error'
            : 'metric-value';
    }

    get riskLabel() {
        if (!this.summary) return '';
        const s = this.summary.riskScore;
        if (s < 30) return 'Low Risk';
        if (s < 60) return 'Medium';
        if (s < 80) return 'High Risk';
        return 'Critical';
    }

    get riskBadgeClass() {
        if (!this.summary) return 'risk-badge';
        const s = this.summary.riskScore;
        if (s < 30) return 'risk-badge risk-low';
        if (s < 60) return 'risk-badge risk-medium';
        if (s < 80) return 'risk-badge risk-high';
        return 'risk-badge risk-critical';
    }

    // Aging bar calculations
    get hasAgingCurrent() {
        return this.summary && this.summary.agingCurrent > 0;
    }
    get hasAging30() {
        return this.summary && this.summary.aging1to30 > 0;
    }
    get hasAging60() {
        return this.summary && this.summary.aging31to60 > 0;
    }
    get hasAging90() {
        return this.summary && this.summary.aging61to90 > 0;
    }
    get hasAgingOver90() {
        return this.summary && this.summary.agingOver90 > 0;
    }

    get currentBarStyle() {
        return 'width:' + this.agingPercent(this.summary.agingCurrent) + '%';
    }
    get aging30Style() {
        return 'width:' + this.agingPercent(this.summary.aging1to30) + '%';
    }
    get aging60Style() {
        return 'width:' + this.agingPercent(this.summary.aging31to60) + '%';
    }
    get aging90Style() {
        return 'width:' + this.agingPercent(this.summary.aging61to90) + '%';
    }
    get agingOver90Style() {
        return 'width:' + this.agingPercent(this.summary.agingOver90) + '%';
    }

    get currentTitle() {
        return 'Current: ' + this.formatCurrency(this.summary.agingCurrent);
    }
    get aging30Title() {
        return '1-30 Days: ' + this.formatCurrency(this.summary.aging1to30);
    }
    get aging60Title() {
        return '31-60 Days: ' + this.formatCurrency(this.summary.aging31to60);
    }
    get aging90Title() {
        return '61-90 Days: ' + this.formatCurrency(this.summary.aging61to90);
    }
    get agingOver90Title() {
        return '90+ Days: ' + this.formatCurrency(this.summary.agingOver90);
    }

    agingPercent(val) {
        if (!this.summary || this.summary.totalAR === 0) return 0;
        return Math.max(2, (val / this.summary.totalAR) * 100);
    }

    get alerts() {
        if (!this.summary) return [];
        const alerts = [];
        if (this.summary.invoicesOver60 > 0) {
            alerts.push({
                key: '1',
                icon: '\u26A0',
                message: this.summary.invoicesOver60 + ' invoice(s) over 60 days past due',
                className: 'alert alert-error'
            });
        }
        if (this.summary.openDisputes > 0) {
            alerts.push({
                key: '2',
                icon: '\u26A1',
                message: this.summary.openDisputes + ' open dispute(s)',
                className: 'alert alert-warning'
            });
        }
        if (this.summary.brokenPromises > 0) {
            alerts.push({
                key: '3',
                icon: '\u2717',
                message: this.summary.brokenPromises + ' broken promise(s) to pay',
                className: 'alert alert-error'
            });
        }
        if (this.summary.creditUtilization > 80) {
            alerts.push({
                key: '4',
                icon: '!',
                message: 'Credit utilization at ' + Math.round(this.summary.creditUtilization) + '%',
                className: 'alert alert-warning'
            });
        }
        return alerts;
    }

    get hasAlerts() {
        return this.alerts.length > 0;
    }

    navigateToAr() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'ARF_Collection_Worklist'
            }
        });
    }

    formatCurrency(val) {
        if (val == null) return '$0';
        if (val >= 1000000) return '$' + (val / 1000000).toFixed(1) + 'M';
        if (val >= 1000) return '$' + (val / 1000).toFixed(1) + 'K';
        return '$' + val.toFixed(0);
    }
}
