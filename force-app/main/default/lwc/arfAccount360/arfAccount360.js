import { LightningElement, api, track } from 'lwc';
import getTabCounts from '@salesforce/apex/ARF_Account360Controller.getTabCounts';

const TAB_CONFIG = [
    { value: 'details', label: 'Details', iconName: 'utility:info', showProp: null },
    { value: 'transactions', label: 'Transactions', iconName: 'utility:moneydollar', showProp: null },
    { value: 'disputes', label: 'Disputes', iconName: 'utility:warning', showProp: null },
    { value: 'deductions', label: 'Deductions', iconName: 'utility:trending', showProp: 'showDeductions' },
    { value: 'emails', label: 'Communications', iconName: 'utility:email', showProp: null },
    { value: 'attachments', label: 'Attachments', iconName: 'utility:attach', showProp: null },
    { value: 'payments', label: 'Payments', iconName: 'utility:currency', showProp: 'showPayments' },
    { value: 'promises', label: 'Promises', iconName: 'utility:date_input', showProp: 'showPromises' },
    { value: 'notes', label: 'Notes', iconName: 'utility:note', showProp: 'showNotes' },
    { value: 'history', label: 'History', iconName: 'utility:clock', showProp: 'showHistory' }
];

export default class ArfAccount360 extends LightningElement {
    @api recordId;

    // Configurable tab visibility from App Builder (default=true set in meta.xml)
    @api showDeductions;
    @api showPayments;
    @api showPromises;
    @api showNotes;
    @api showHistory;

    activeTab = 'details';
    showQuickActionModal = false;
    quickActionType = '';
    showEmailComposer = false;

    @track refreshKey = 0;
    @track tabCounts = {};

    connectedCallback() {
        this.loadTabCounts();
    }

    async loadTabCounts() {
        if (!this.recordId) return;
        try {
            this.tabCounts = await getTabCounts({ accountId: this.recordId });
        } catch (e) {
            // Non-critical — badges just won't show
        }
    }

    get visibleTabs() {
        return TAB_CONFIG
            .filter(tab => {
                if (!tab.showProp) return true;
                return this[tab.showProp] !== false;
            })
            .map(tab => {
                const isActive = this.activeTab === tab.value;
                const count = this.tabCounts[tab.value] || 0;
                let badgeCls = 'tab-badge tab-badge-' + tab.value;
                if (isActive) badgeCls += ' tab-badge-active';
                return {
                    ...tab,
                    isActive,
                    tabClass: 'tab-button' + (isActive ? ' tab-button-active' : ''),
                    badgeCount: count,
                    hasBadge: count > 0,
                    badgeClass: badgeCls
                };
            });
    }

    // Tab content visibility
    get isDetailsTab() { return this.activeTab === 'details'; }
    get isTransactionsTab() { return this.activeTab === 'transactions'; }
    get isDisputesTab() { return this.activeTab === 'disputes'; }
    get isDeductionsTab() { return this.activeTab === 'deductions'; }
    get isEmailsTab() { return this.activeTab === 'emails'; }
    get isAttachmentsTab() { return this.activeTab === 'attachments'; }
    get isPaymentsTab() { return this.activeTab === 'payments'; }
    get isPromisesTab() { return this.activeTab === 'promises'; }
    get isNotesTab() { return this.activeTab === 'notes'; }
    get isHistoryTab() { return this.activeTab === 'history'; }
    get isEmailAction() { return this.showEmailComposer; }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleQuickAction(event) {
        this.quickActionType = event.detail.actionType;
        if (this.quickActionType === 'Email') {
            this.showEmailComposer = true;
        } else {
            this.showQuickActionModal = true;
        }
    }

    handleModalClose() {
        this.showQuickActionModal = false;
        this.showEmailComposer = false;
        this.quickActionType = '';
    }

    handleRecordCreated() {
        this.showQuickActionModal = false;
        this.showEmailComposer = false;
        this.quickActionType = '';
        this.refreshKey++;
        this.loadTabCounts();
    }

    handleChildRecordCreated() {
        this.refreshKey++;
        this.loadTabCounts();
    }
}
