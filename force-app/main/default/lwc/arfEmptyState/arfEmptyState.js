import { LightningElement, api } from 'lwc';

export default class ArfEmptyState extends LightningElement {
    @api variant = 'default';
    @api title = 'No data available';
    @api message = '';
    @api actionLabel = '';

    get hasAction() { return !!this.actionLabel; }
    get isDefault() { return this.variant === 'default'; }
    get isNoData() { return this.variant === 'no-data'; }
    get isNoResults() { return this.variant === 'no-results'; }
    get isError() { return this.variant === 'error'; }

    get containerClass() { return 'empty-container'; }
    get iconContainerClass() { return this.isError ? 'icon-container-error' : 'icon-container'; }
    get actionButtonClass() { return this.isError ? 'action-button-error' : 'action-button'; }

    handleAction() {
        this.dispatchEvent(new CustomEvent('action'));
    }
}
