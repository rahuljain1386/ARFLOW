import { LightningElement, api } from 'lwc';

export default class ArfLoadingSkeleton extends LightningElement {
    @api variant = 'card';
    @api count = 1;

    get items() {
        const c = parseInt(this.count, 10) || 1;
        return Array.from({ length: c }, (_, i) => ({ key: `skeleton-${this.variant}-${i}` }));
    }

    get isCard() { return this.variant === 'card'; }
    get isTable() { return this.variant === 'table'; }
    get isMetric() { return this.variant === 'metric'; }
    get isChart() { return this.variant === 'chart'; }
}
