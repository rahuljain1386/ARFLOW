import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getStrategy from '@salesforce/apex/ARF_StrategyBuilderController.getStrategy';
import getSteps from '@salesforce/apex/ARF_StrategyBuilderController.getSteps';
import saveSteps from '@salesforce/apex/ARF_StrategyBuilderController.saveSteps';
import activateStrategy from '@salesforce/apex/ARF_StrategyBuilderController.activateStrategy';
import deactivateStrategy from '@salesforce/apex/ARF_StrategyBuilderController.deactivateStrategy';

const ACTION_OPTIONS = [
    { label: 'Email', value: 'Email' },
    { label: 'Task', value: 'Task' },
    { label: 'Escalate', value: 'Escalate' },
    { label: 'SMS', value: 'SMS' },
    { label: 'Letter', value: 'Letter' }
];

const EMPTY_STEP = {
    stepNumber: 1, name: '', dayOffset: 0, action: 'Email', channel: 'Email',
    subject: '', body: '', escalateTo: '', createTask: false, taskSubject: '',
    skipIfPromise: true, skipIfDispute: true
};

export default class ArfStrategyBuilder extends LightningElement {
    @api recordId;
    strategy;
    steps = [];
    error;
    isLoading = false;
    isDirty = false;
    wiredStrategyResult;
    wiredStepsResult;

    // Modal state
    showStepModal = false;
    editingStep = {};
    editingIndex = -1;
    actionOptions = ACTION_OPTIONS;

    @wire(getStrategy, { strategyId: '$recordId' })
    wiredStrategy(result) {
        this.wiredStrategyResult = result;
        if (result.data) {
            this.strategy = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.strategy = undefined;
        }
    }

    @wire(getSteps, { strategyId: '$recordId' })
    wiredStepsList(result) {
        this.wiredStepsResult = result;
        if (result.data) {
            this.steps = result.data.map((s, i) => ({ ...s, index: i, id: 'step-' + i }));
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.steps = [];
        }
    }

    get hasSteps() { return this.steps && this.steps.length > 0; }
    get stepCount() { return this.steps ? this.steps.length : 0; }
    get isActive() { return this.strategy && this.strategy.Active__c; }
    get strategyName() { return this.strategy ? this.strategy.Strategy_Name__c || this.strategy.Name : ''; }
    get activateLabel() { return this.isActive ? 'Deactivate' : 'Activate'; }
    get activateVariant() { return this.isActive ? 'destructive' : 'success'; }
    get activateIcon() { return this.isActive ? 'utility:ban' : 'utility:check'; }
    get saveDisabled() { return !this.isDirty; }
    get noError() { return !this.error; }
    get modalTitle() { return this.editingIndex >= 0 ? 'Edit Step' : 'Add Step'; }

    handleAddStep() {
        const nextNumber = this.steps.length > 0
            ? Math.max(...this.steps.map(s => s.stepNumber)) + 1
            : 1;
        const nextDay = this.steps.length > 0
            ? Math.max(...this.steps.map(s => s.dayOffset)) + 7
            : 1;
        this.editingStep = { ...EMPTY_STEP, stepNumber: nextNumber, dayOffset: nextDay };
        this.editingIndex = -1;
        this.showStepModal = true;
    }

    handleEditStep(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.editingStep = { ...this.steps[idx] };
        this.editingIndex = idx;
        this.showStepModal = true;
    }

    handleDeleteStep(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.steps = this.steps
            .filter((_, i) => i !== idx)
            .map((s, i) => ({ ...s, stepNumber: i + 1, index: i, id: 'step-' + i }));
        this.isDirty = true;
    }

    handleMoveUp(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        if (idx <= 0) return;
        const arr = [...this.steps];
        [arr[idx - 1], arr[idx]] = [arr[idx], arr[idx - 1]];
        this.steps = arr.map((s, i) => ({ ...s, stepNumber: i + 1, index: i, id: 'step-' + i }));
        this.isDirty = true;
    }

    handleMoveDown(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        if (idx >= this.steps.length - 1) return;
        const arr = [...this.steps];
        [arr[idx], arr[idx + 1]] = [arr[idx + 1], arr[idx]];
        this.steps = arr.map((s, i) => ({ ...s, stepNumber: i + 1, index: i, id: 'step-' + i }));
        this.isDirty = true;
    }

    // Modal field handlers
    handleStepFieldChange(event) {
        const field = event.target.dataset.field;
        this.editingStep = { ...this.editingStep, [field]: event.detail.value };
    }

    handleStepCheckboxChange(event) {
        const field = event.target.dataset.field;
        this.editingStep = { ...this.editingStep, [field]: event.target.checked };
    }

    handleCloseModal() {
        this.showStepModal = false;
        this.editingStep = {};
    }

    handleSaveStep() {
        // Validate required fields
        if (!this.editingStep.name || !this.editingStep.action) {
            this.showToast('Error', 'Step name and action are required', 'error');
            return;
        }
        const step = { ...this.editingStep };
        let arr = [...this.steps];
        if (this.editingIndex >= 0) {
            arr[this.editingIndex] = step;
        } else {
            arr.push(step);
        }
        this.steps = arr.map((s, i) => ({ ...s, stepNumber: i + 1, index: i, id: 'step-' + i }));
        this.isDirty = true;
        this.showStepModal = false;
        this.editingStep = {};
    }

    async handleSave() {
        this.isLoading = true;
        try {
            const cleanSteps = this.steps.map(s => ({
                stepNumber: s.stepNumber,
                name: s.name,
                dayOffset: s.dayOffset,
                action: s.action,
                channel: s.channel || s.action,
                subject: s.subject || '',
                body: s.body || '',
                escalateTo: s.escalateTo || null,
                createTask: s.createTask || false,
                taskSubject: s.taskSubject || '',
                skipIfPromise: s.skipIfPromise !== false,
                skipIfDispute: s.skipIfDispute !== false
            }));
            const json = JSON.stringify({ steps: cleanSteps });
            await saveSteps({ strategyId: this.recordId, stepsJson: json });
            this.isDirty = false;
            this.showToast('Success', 'Strategy steps saved', 'success');
            await refreshApex(this.wiredStepsResult);
            await refreshApex(this.wiredStrategyResult);
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to save steps', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleToggleActive() {
        this.isLoading = true;
        try {
            if (this.isActive) {
                await deactivateStrategy({ strategyId: this.recordId });
                this.showToast('Success', 'Strategy deactivated', 'success');
            } else {
                await activateStrategy({ strategyId: this.recordId });
                this.showToast('Success', 'Strategy activated', 'success');
            }
            await refreshApex(this.wiredStrategyResult);
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to update strategy', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
