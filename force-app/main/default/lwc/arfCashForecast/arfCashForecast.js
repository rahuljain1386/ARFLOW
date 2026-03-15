import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generateForecasts from '@salesforce/apex/ARF_CashForecastEngine.generateForecasts';
import getDashboard from '@salesforce/apex/ARF_CashForecastEngine.getDashboard';
import getAccuracyMetrics from '@salesforce/apex/ARF_CashForecastEngine.getAccuracyMetrics';

export default class ArfCashForecast extends LightningElement {
    @track dashboard = {};
    @track accuracy = {};
    @track periods = [];
    isLoading = true;
    isGenerating = false;
    periodType = 'Weekly';
    maxBarValue = 0;

    connectedCallback() { this.loadData(); }

    async loadData() {
        this.isLoading = true;
        try {
            const [dash, acc] = await Promise.all([
                getDashboard({ periodType: this.periodType, periodsAhead: 12 }),
                getAccuracyMetrics()
            ]);
            this.dashboard = dash;
            this.accuracy = acc;
            this.periods = (dash.periods || []).map((p, i) => {
                return { ...p, key: 'period-' + i, index: i };
            });
            this.maxBarValue = Math.max(...this.periods.map(p => p.predicted || 0), 1);
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Failed to load forecast', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleGenerate() {
        this.isGenerating = true;
        try {
            const result = await generateForecasts();
            this.showToast('Success',
                `Generated ${result.predictionsCreated} predictions, ${result.forecastsCreated} forecast periods ($${this.formatNumber(result.totalForecastedAmount)})`,
                'success');
            await this.loadData();
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Forecast generation failed', 'error');
        } finally {
            this.isGenerating = false;
        }
    }

    handlePeriodChange(event) {
        this.periodType = event.currentTarget.dataset.period;
        this.loadData();
    }

    // Chart bar heights computed per period
    get chartPeriods() {
        return this.periods.map(p => {
            const predicted = p.predicted || 0;
            const high = p.highConfidence || 0;
            const med = p.mediumConfidence || 0;
            const low = p.lowConfidence || 0;
            const maxH = 250;

            return {
                ...p,
                totalBarHeight: Math.max(4, (predicted / this.maxBarValue) * maxH) + 'px',
                highBarHeight: predicted > 0 ? Math.max(2, (high / this.maxBarValue) * maxH) + 'px' : '0px',
                medBarHeight: predicted > 0 ? Math.max(2, (med / this.maxBarValue) * maxH) + 'px' : '0px',
                lowBarHeight: predicted > 0 ? Math.max(2, (low / this.maxBarValue) * maxH) + 'px' : '0px',
                formattedTotal: '$' + this.formatNumber(predicted),
                formattedHigh: '$' + this.formatNumber(high),
                formattedMed: '$' + this.formatNumber(med),
                formattedLow: '$' + this.formatNumber(low)
            };
        });
    }

    get formattedTotalForecast() { return '$' + this.formatNumber(this.dashboard.totalForecast || 0); }
    get formattedHighConfidence() { return '$' + this.formatNumber(this.dashboard.highConfidenceTotal || 0); }
    get formattedAccuracy() { return (this.dashboard.accuracy || 0).toFixed(1) + '%'; }
    get formattedAvgDaysOff() { return (this.accuracy.avgDaysOff || 0).toFixed(1); }
    get accuracyWidth() { return 'width: ' + Math.min(100, this.dashboard.accuracy || 0) + '%'; }

    get hasPeriods() { return this.periods.length > 0; }
    get showEmpty() { return !this.isLoading && !this.hasPeriods; }
    get isWeekly() { return this.periodType === 'Weekly'; }
    get isMonthly() { return this.periodType === 'Monthly'; }
    get weeklyClass() { return this.isWeekly ? 'period-btn period-btn-active' : 'period-btn'; }
    get monthlyClass() { return this.isMonthly ? 'period-btn period-btn-active' : 'period-btn'; }

    formatNumber(val) {
        if (val == null) return '0';
        if (val >= 1000000) return (val / 1000000).toFixed(1) + 'M';
        if (val >= 1000) return (val / 1000).toFixed(1) + 'K';
        return val.toFixed(0);
    }

    formatCurrency(val) {
        if (val == null) return '$0';
        return '$' + Number(val).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 0 });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
