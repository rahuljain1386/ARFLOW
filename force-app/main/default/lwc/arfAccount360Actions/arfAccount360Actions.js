import { LightningElement, api } from 'lwc';

export default class ArfAccount360Actions extends LightningElement {
    @api recordId;

    handleEmail() {
        this.dispatchEvent(new CustomEvent('quickaction', { detail: { actionType: 'Email' } }));
    }

    handleSMS() {
        this.dispatchEvent(new CustomEvent('quickaction', { detail: { actionType: 'SMS' } }));
    }

    handleCall() {
        this.dispatchEvent(new CustomEvent('quickaction', { detail: { actionType: 'Call' } }));
    }

    handleNote() {
        this.dispatchEvent(new CustomEvent('quickaction', { detail: { actionType: 'Note' } }));
    }

    handleDispute() {
        this.dispatchEvent(new CustomEvent('quickaction', { detail: { actionType: 'Dispute' } }));
    }

    handlePromiseToPay() {
        this.dispatchEvent(new CustomEvent('quickaction', { detail: { actionType: 'PromiseToPay' } }));
    }
}
