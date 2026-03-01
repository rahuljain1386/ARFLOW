import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import loadApplicationByToken from '@salesforce/apex/ARF_CreditApplicationController.loadApplicationByToken';
import saveApplicationStep from '@salesforce/apex/ARF_CreditApplicationController.saveApplicationStep';

const US_STATES = [
    { label: 'Alabama', value: 'AL' }, { label: 'Alaska', value: 'AK' },
    { label: 'Arizona', value: 'AZ' }, { label: 'Arkansas', value: 'AR' },
    { label: 'California', value: 'CA' }, { label: 'Colorado', value: 'CO' },
    { label: 'Connecticut', value: 'CT' }, { label: 'Delaware', value: 'DE' },
    { label: 'Florida', value: 'FL' }, { label: 'Georgia', value: 'GA' },
    { label: 'Hawaii', value: 'HI' }, { label: 'Idaho', value: 'ID' },
    { label: 'Illinois', value: 'IL' }, { label: 'Indiana', value: 'IN' },
    { label: 'Iowa', value: 'IA' }, { label: 'Kansas', value: 'KS' },
    { label: 'Kentucky', value: 'KY' }, { label: 'Louisiana', value: 'LA' },
    { label: 'Maine', value: 'ME' }, { label: 'Maryland', value: 'MD' },
    { label: 'Massachusetts', value: 'MA' }, { label: 'Michigan', value: 'MI' },
    { label: 'Minnesota', value: 'MN' }, { label: 'Mississippi', value: 'MS' },
    { label: 'Missouri', value: 'MO' }, { label: 'Montana', value: 'MT' },
    { label: 'Nebraska', value: 'NE' }, { label: 'Nevada', value: 'NV' },
    { label: 'New Hampshire', value: 'NH' }, { label: 'New Jersey', value: 'NJ' },
    { label: 'New Mexico', value: 'NM' }, { label: 'New York', value: 'NY' },
    { label: 'North Carolina', value: 'NC' }, { label: 'North Dakota', value: 'ND' },
    { label: 'Ohio', value: 'OH' }, { label: 'Oklahoma', value: 'OK' },
    { label: 'Oregon', value: 'OR' }, { label: 'Pennsylvania', value: 'PA' },
    { label: 'Rhode Island', value: 'RI' }, { label: 'South Carolina', value: 'SC' },
    { label: 'South Dakota', value: 'SD' }, { label: 'Tennessee', value: 'TN' },
    { label: 'Texas', value: 'TX' }, { label: 'Utah', value: 'UT' },
    { label: 'Vermont', value: 'VT' }, { label: 'Virginia', value: 'VA' },
    { label: 'Washington', value: 'WA' }, { label: 'West Virginia', value: 'WV' },
    { label: 'Wisconsin', value: 'WI' }, { label: 'Wyoming', value: 'WY' },
    { label: 'District of Columbia', value: 'DC' }
];

const BUSINESS_TYPES = [
    { label: 'Corporation', value: 'Corporation' },
    { label: 'S-Corporation', value: 'S-Corporation' },
    { label: 'LLC', value: 'LLC' },
    { label: 'Partnership', value: 'Partnership' },
    { label: 'Sole Proprietorship', value: 'Sole Proprietorship' },
    { label: 'Non-Profit', value: 'Non-Profit' },
    { label: 'Government', value: 'Government' },
    { label: 'Other', value: 'Other' }
];

const ACCOUNT_TYPES = [
    { label: 'Checking', value: 'Checking' },
    { label: 'Savings', value: 'Savings' },
    { label: 'Line of Credit', value: 'Line of Credit' }
];

const EMPTY_APPLICANT = { firstName: '', lastName: '', title: '', email: '', phone: '', ownershipPercent: null, isPrimary: false };
const EMPTY_TRADE_REF = { companyName: '', contactName: '', phone: '', email: '', accountNumber: '', creditLimit: null, balanceOwed: null };
const EMPTY_BANK_REF = { bankName: '', branch: '', contact: '', phone: '', accountType: '', accountNumber: '', routingNumber: '' };
const EMPTY_GUARANTOR = { firstName: '', lastName: '', ssn: '', dob: '', street: '', city: '', state: '', zip: '', ownershipPercent: null, phone: '', email: '' };

const STEP_CONFIG = [
    { num: 1, label: 'Company Info', icon: 'building', desc: 'Business details & contacts' },
    { num: 2, label: 'References', icon: 'handshake', desc: 'Trade & bank references' },
    { num: 3, label: 'Guarantor', icon: 'shield', desc: 'Personal guarantee info' },
    { num: 4, label: 'Tax Info', icon: 'document', desc: 'Tax identification' },
    { num: 5, label: 'Review & Sign', icon: 'check', desc: 'Final review & submit' }
];

export default class ArfCreditApplication extends LightningElement {
    @api token;

    // View state
    @track showLoginPage = true;
    @track currentStep = 1;
    @track isLoading = false;
    @track applicationId;
    @track loginToken = '';
    @track loginError = '';
    @track lastSaved = '';
    @track isSaving = false;
    @track companyName = '';

    // Step 1
    @track company = {
        legalName: '', dba: '', phone: '', fax: '', email: '', website: '',
        businessType: '', yearsInBusiness: null, dateEstablished: '',
        annualRevenue: null, numberOfEmployees: null, requestedCreditLimit: null
    };
    @track billingAddress = { street: '', city: '', state: '', zip: '', country: 'US' };
    @track shippingAddress = { street: '', city: '', state: '', zip: '', country: 'US' };
    @track shippingSameAsBilling = false;
    @track applicants = [{ ...EMPTY_APPLICANT, isPrimary: true }];
    @track apContact = { name: '', email: '', phone: '' };

    // Step 2
    @track tradeReferences = [{ ...EMPTY_TRADE_REF }, { ...EMPTY_TRADE_REF }, { ...EMPTY_TRADE_REF }];
    @track bankReferences = [{ ...EMPTY_BANK_REF }];

    // Step 3
    @track guarantors = [{ ...EMPTY_GUARANTOR }];

    // Step 4
    @track taxInfo = { ein: '', dunsNumber: '', stateOfIncorporation: '' };

    // Step 5
    @track termsAccepted = false;
    @track creditAuthAccepted = false;
    @track signatureName = '';
    @track signatureTitle = '';
    @track signatureData = '';
    @track isDrawingSignature = false;

    _autoSaveTimer;
    _signatureCanvas;
    _signatureCtx;
    _isDrawing = false;

    // ─── Getters ───

    get stateOptions() { return US_STATES; }
    get businessTypeOptions() { return BUSINESS_TYPES; }
    get accountTypeOptions() { return ACCOUNT_TYPES; }

    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }
    get isStep5() { return this.currentStep === 5; }
    get isSubmitted() { return this.currentStep === 6; }
    get isFirstStep() { return this.currentStep === 1; }
    get isLastStep() { return this.currentStep === 5; }
    get showForm() { return !this.showLoginPage && !this.isSubmitted; }

    get nextButtonLabel() { return this.isLastStep ? 'Submit Application' : 'Save & Continue'; }
    get nextButtonIcon() { return this.isLastStep ? 'utility:check' : 'utility:chevronright'; }
    get submitDisabled() { return this.isLastStep && (!this.termsAccepted || !this.creditAuthAccepted || !this.signatureName); }

    get signatureToggleLabel() {
        return this.isDrawingSignature ? 'Switch to Typed Signature' : 'Switch to Drawn Signature';
    }

    get progressPercent() {
        return Math.round(((this.currentStep - 1) / 4) * 100);
    }

    get progressBarStyle() {
        return `width: ${this.progressPercent}%`;
    }

    get sidebarSteps() {
        return STEP_CONFIG.map(s => {
            let status = 'future';
            if (s.num < this.currentStep) status = 'completed';
            else if (s.num === this.currentStep) status = 'active';
            return {
                ...s,
                key: `step-${s.num}`,
                status,
                isCompleted: s.num < this.currentStep,
                isActive: s.num === this.currentStep,
                isFuture: s.num > this.currentStep,
                stepClass: `sidebar-step sidebar-step-${status}`,
                summary: this._getStepSummary(s.num)
            };
        });
    }

    get step1SectionSummary() {
        if (!this.company.legalName) return '';
        return this.company.legalName;
    }

    get formattedBillingAddress() {
        const a = this.billingAddress;
        return [a.street, a.city, a.state, a.zip].filter(Boolean).join(', ') || '';
    }

    get formattedShippingAddress() {
        if (this.shippingSameAsBilling) return 'Same as billing';
        const a = this.shippingAddress;
        return [a.street, a.city, a.state, a.zip].filter(Boolean).join(', ') || '';
    }

    get businessTypeLabel() {
        const found = BUSINESS_TYPES.find(b => b.value === this.company.businessType);
        return found ? found.label : this.company.businessType || '';
    }

    get stateOfIncorporationLabel() {
        const found = US_STATES.find(s => s.value === this.taxInfo.stateOfIncorporation);
        return found ? found.label : this.taxInfo.stateOfIncorporation || '';
    }

    get hasGuarantors() {
        return this.guarantors.some(g => g.firstName || g.lastName);
    }

    get indexedApplicants() {
        return this.applicants.map((a, i) => ({
            ...a, index: i, key: `applicant-${i}`,
            label: `Applicant ${i + 1}`, showRemove: this.applicants.length > 1
        }));
    }

    get indexedTradeReferences() {
        return this.tradeReferences.map((r, i) => ({
            ...r, index: i, key: `trade-${i}`,
            label: `Trade Reference ${i + 1}`, showRemove: this.tradeReferences.length > 1
        }));
    }

    get indexedBankReferences() {
        return this.bankReferences.map((r, i) => ({
            ...r, index: i, key: `bank-${i}`,
            label: `Bank Reference ${i + 1}`, showRemove: this.bankReferences.length > 1
        }));
    }

    get indexedGuarantors() {
        return this.guarantors.map((g, i) => ({
            ...g, index: i, key: `guarantor-${i}`,
            label: `Guarantor ${i + 1}`, showRemove: this.guarantors.length > 1
        }));
    }

    get completedStepCount() {
        return Math.max(0, this.currentStep - 1);
    }

    get totalSteps() { return 5; }

    // ─── Lifecycle ───

    connectedCallback() {
        if (!this.token) {
            const urlParams = new URLSearchParams(window.location.search);
            this.token = urlParams.get('token') || urlParams.get('t') || '';
        }
        if (this.token) {
            this.loginToken = this.token;
            this.showLoginPage = false;
            this.loadApplication();
        }
    }

    renderedCallback() {
        if (this.isStep5 && this.isDrawingSignature) {
            this._initSignatureCanvas();
        }
    }

    // ─── Login Page ───

    handleLoginTokenChange(event) {
        this.loginToken = event.target.value;
        this.loginError = '';
    }

    handleLoginSubmit() {
        if (!this.loginToken || this.loginToken.trim().length < 5) {
            this.loginError = 'Please enter a valid access token from your email.';
            return;
        }
        this.token = this.loginToken.trim();
        this.showLoginPage = false;
        this.loadApplication();
    }

    handleLoginKeyPress(event) {
        if (event.key === 'Enter') {
            this.handleLoginSubmit();
        }
    }

    // ─── Data Loading ───

    loadApplication() {
        this.isLoading = true;
        loadApplicationByToken({ token: this.token })
            .then(result => {
                if (result) {
                    this.applicationId = result.id;
                    if (result.company) {
                        this.company = { ...this.company, ...result.company };
                        this.companyName = result.company.legalName || '';
                    }
                    if (result.billingAddress) this.billingAddress = { ...this.billingAddress, ...result.billingAddress };
                    if (result.shippingAddress) this.shippingAddress = { ...this.shippingAddress, ...result.shippingAddress };
                    if (result.shippingSameAsBilling) this.shippingSameAsBilling = result.shippingSameAsBilling;
                    if (result.applicants && result.applicants.length > 0) this.applicants = result.applicants;
                    if (result.apContact) this.apContact = { ...this.apContact, ...result.apContact };
                    if (result.tradeReferences && result.tradeReferences.length > 0) this.tradeReferences = result.tradeReferences;
                    if (result.bankReferences && result.bankReferences.length > 0) this.bankReferences = result.bankReferences;
                    if (result.guarantors && result.guarantors.length > 0) this.guarantors = result.guarantors;
                    if (result.taxInfo) this.taxInfo = { ...this.taxInfo, ...result.taxInfo };
                    if (result.currentStep) this.currentStep = result.currentStep;
                }
            })
            .catch(error => {
                const msg = this.reduceError(error);
                if (this.showLoginPage === false && !this.applicationId) {
                    this.showLoginPage = true;
                    this.loginError = msg;
                } else {
                    this.showToast('Error', msg, 'error');
                }
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ─── Navigation ───

    handleNext() {
        if (!this.validateCurrentStep()) return;
        if (this.isLastStep) {
            this.handleSubmit();
            return;
        }
        this.handleSave(true);
        this.currentStep = Math.min(this.currentStep + 1, 5);
        this._scrollToTop();
    }

    handleBack() {
        this.currentStep = Math.max(this.currentStep - 1, 1);
        this._scrollToTop();
    }

    handleStepClick(event) {
        const targetStep = parseInt(event.currentTarget.dataset.step, 10);
        if (targetStep <= this.currentStep) {
            if (targetStep < this.currentStep) this.handleSave(false);
            this.currentStep = targetStep;
            this._scrollToTop();
        }
    }

    // ─── Auto Save ───

    _triggerAutoSave() {
        clearTimeout(this._autoSaveTimer);
        this._autoSaveTimer = setTimeout(() => {
            this.handleSave(false);
        }, 3000);
    }

    handleSave(showIndicator) {
        const stepData = this._getCurrentStepData();
        if (!this.token) return;

        if (showIndicator) this.isSaving = true;
        saveApplicationStep({
            token: this.token,
            stepNumber: this.currentStep,
            stepDataJson: JSON.stringify(stepData)
        })
            .then(() => {
                const now = new Date();
                this.lastSaved = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            })
            .catch(error => {
                console.error('Save error:', this.reduceError(error));
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    handleSaveDraft() {
        if (!this.token) {
            this.showToast('Info', 'No application token found.', 'info');
            return;
        }
        this.isLoading = true;
        const stepData = this._getCurrentStepData();
        saveApplicationStep({
            token: this.token,
            stepNumber: this.currentStep,
            stepDataJson: JSON.stringify(stepData)
        })
            .then(() => {
                const now = new Date();
                this.lastSaved = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
                this.showToast('Saved', 'Your progress has been saved. You can close this page and return later using the same link.', 'success');
            })
            .catch(error => {
                this.showToast('Save Error', this.reduceError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSubmit() {
        if (!this.termsAccepted || !this.creditAuthAccepted) {
            this.showToast('Required', 'Please accept the Terms & Conditions and Credit Authorization.', 'warning');
            return;
        }
        if (!this.signatureName) {
            this.showToast('Required', 'Please provide your signature.', 'warning');
            return;
        }

        this.isLoading = true;
        const submitData = { ...this._getCurrentStepData(), status: 'Submitted' };
        saveApplicationStep({
            token: this.token,
            stepNumber: 5,
            stepDataJson: JSON.stringify(submitData)
        })
            .then(() => {
                this.currentStep = 6;
            })
            .catch(error => {
                this.showToast('Submission Error', this.reduceError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ─── Step 1 Handlers ───

    handleCompanyChange(event) {
        const field = event.target.dataset.field;
        this.company = { ...this.company, [field]: event.target.value };
        if (field === 'legalName') this.companyName = event.target.value;
        this._triggerAutoSave();
    }

    handleBillingAddressChange(event) {
        const field = event.target.dataset.field;
        this.billingAddress = { ...this.billingAddress, [field]: event.target.value };
        if (this.shippingSameAsBilling) {
            this.shippingAddress = { ...this.billingAddress, [field]: event.target.value };
        }
        this._triggerAutoSave();
    }

    handleShippingSameToggle(event) {
        this.shippingSameAsBilling = event.target.checked;
        if (this.shippingSameAsBilling) this.shippingAddress = { ...this.billingAddress };
        this._triggerAutoSave();
    }

    handleShippingAddressChange(event) {
        const field = event.target.dataset.field;
        this.shippingAddress = { ...this.shippingAddress, [field]: event.target.value };
        this._triggerAutoSave();
    }

    handleApplicantChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const field = event.target.dataset.field;
        const value = field === 'isPrimary' ? event.target.checked : event.target.value;
        const updated = [...this.applicants];
        updated[index] = { ...updated[index], [field]: value };
        if (field === 'isPrimary' && value) {
            updated.forEach((a, i) => { if (i !== index) updated[i] = { ...a, isPrimary: false }; });
        }
        this.applicants = updated;
        this._triggerAutoSave();
    }

    handleAddApplicant() { this.applicants = [...this.applicants, { ...EMPTY_APPLICANT }]; }
    handleRemoveApplicant(event) {
        const i = parseInt(event.target.dataset.index, 10);
        const u = [...this.applicants]; u.splice(i, 1); this.applicants = u;
    }

    handleApContactChange(event) {
        const field = event.target.dataset.field;
        this.apContact = { ...this.apContact, [field]: event.target.value };
        this._triggerAutoSave();
    }

    // ─── Step 2 Handlers ───

    handleTradeRefChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const field = event.target.dataset.field;
        const updated = [...this.tradeReferences];
        updated[index] = { ...updated[index], [field]: event.target.value };
        this.tradeReferences = updated;
        this._triggerAutoSave();
    }

    handleAddTradeRef() { this.tradeReferences = [...this.tradeReferences, { ...EMPTY_TRADE_REF }]; }
    handleRemoveTradeRef(event) {
        const i = parseInt(event.target.dataset.index, 10);
        const u = [...this.tradeReferences]; u.splice(i, 1); this.tradeReferences = u;
    }

    handleBankRefChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const field = event.target.dataset.field;
        const updated = [...this.bankReferences];
        updated[index] = { ...updated[index], [field]: event.target.value };
        this.bankReferences = updated;
        this._triggerAutoSave();
    }

    handleAddBankRef() { this.bankReferences = [...this.bankReferences, { ...EMPTY_BANK_REF }]; }
    handleRemoveBankRef(event) {
        const i = parseInt(event.target.dataset.index, 10);
        const u = [...this.bankReferences]; u.splice(i, 1); this.bankReferences = u;
    }

    // ─── Step 3 Handlers ───

    handleGuarantorChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const field = event.target.dataset.field;
        const updated = [...this.guarantors];
        updated[index] = { ...updated[index], [field]: event.target.value };
        this.guarantors = updated;
        this._triggerAutoSave();
    }

    handleAddGuarantor() { this.guarantors = [...this.guarantors, { ...EMPTY_GUARANTOR }]; }
    handleRemoveGuarantor(event) {
        const i = parseInt(event.target.dataset.index, 10);
        const u = [...this.guarantors]; u.splice(i, 1); this.guarantors = u;
    }

    // ─── Step 4 Handlers ───

    handleTaxInfoChange(event) {
        const field = event.target.dataset.field;
        this.taxInfo = { ...this.taxInfo, [field]: event.target.value };
        this._triggerAutoSave();
    }

    // ─── Step 5 Handlers ───

    handleTermsAccepted(event) { this.termsAccepted = event.target.checked; }
    handleCreditAuthAccepted(event) { this.creditAuthAccepted = event.target.checked; }
    handleSignatureNameChange(event) { this.signatureName = event.target.value; }
    handleSignatureTitleChange(event) { this.signatureTitle = event.target.value; }

    handleToggleSignatureMode() {
        this.isDrawingSignature = !this.isDrawingSignature;
        if (!this.isDrawingSignature) this.signatureData = '';
    }

    // ─── Signature Canvas ───

    _initSignatureCanvas() {
        const canvas = this.template.querySelector('.signature-canvas');
        if (!canvas || this._signatureCanvas === canvas) return;
        this._signatureCanvas = canvas;
        this._signatureCtx = canvas.getContext('2d');
        this._signatureCtx.strokeStyle = '#1b2a4a';
        this._signatureCtx.lineWidth = 2;
        this._signatureCtx.lineCap = 'round';
        canvas.addEventListener('mousedown', this._startDraw.bind(this));
        canvas.addEventListener('mousemove', this._draw.bind(this));
        canvas.addEventListener('mouseup', this._endDraw.bind(this));
        canvas.addEventListener('mouseleave', this._endDraw.bind(this));
        canvas.addEventListener('touchstart', this._startDrawTouch.bind(this));
        canvas.addEventListener('touchmove', this._drawTouch.bind(this));
        canvas.addEventListener('touchend', this._endDraw.bind(this));
    }

    _startDraw(e) { this._isDrawing = true; this._signatureCtx.beginPath(); this._signatureCtx.moveTo(e.offsetX, e.offsetY); }
    _draw(e) { if (!this._isDrawing) return; this._signatureCtx.lineTo(e.offsetX, e.offsetY); this._signatureCtx.stroke(); }
    _startDrawTouch(e) {
        e.preventDefault();
        const r = this._signatureCanvas.getBoundingClientRect();
        this._isDrawing = true; this._signatureCtx.beginPath();
        this._signatureCtx.moveTo(e.touches[0].clientX - r.left, e.touches[0].clientY - r.top);
    }
    _drawTouch(e) {
        e.preventDefault(); if (!this._isDrawing) return;
        const r = this._signatureCanvas.getBoundingClientRect();
        this._signatureCtx.lineTo(e.touches[0].clientX - r.left, e.touches[0].clientY - r.top); this._signatureCtx.stroke();
    }
    _endDraw() {
        if (this._isDrawing && this._signatureCanvas) this.signatureData = this._signatureCanvas.toDataURL();
        this._isDrawing = false;
    }
    handleClearSignature() {
        if (this._signatureCtx && this._signatureCanvas) {
            this._signatureCtx.clearRect(0, 0, this._signatureCanvas.width, this._signatureCanvas.height);
            this.signatureData = '';
        }
    }

    // ─── Validation ───

    validateCurrentStep() {
        const inputs = this.template.querySelectorAll(
            '.form-panel lightning-input, .form-panel lightning-combobox, .form-panel lightning-textarea'
        );
        let allValid = true;
        inputs.forEach(input => { if (!input.reportValidity()) allValid = false; });

        if (this.currentStep === 1) {
            if (!this.company.legalName) {
                this.showToast('Required', 'Legal Company Name is required.', 'warning');
                return false;
            }
            if (!this.company.email) {
                this.showToast('Required', 'Company Email is required.', 'warning');
                return false;
            }
            if (!this.applicants.some(a => a.firstName && a.lastName)) {
                this.showToast('Required', 'At least one applicant with name is required.', 'warning');
                return false;
            }
        }
        if (this.currentStep === 2) {
            if (this.tradeReferences.filter(r => r.companyName).length < 1) {
                this.showToast('Required', 'At least one trade reference is required.', 'warning');
                return false;
            }
        }
        return allValid;
    }

    // ─── Helpers ───

    _getStepSummary(stepNum) {
        switch (stepNum) {
            case 1:
                if (!this.company.legalName) return '';
                return this.company.legalName + (this.company.businessType ? ` (${this.company.businessType})` : '');
            case 2: {
                const tradeCount = this.tradeReferences.filter(r => r.companyName).length;
                const bankCount = this.bankReferences.filter(r => r.bankName).length;
                if (!tradeCount && !bankCount) return '';
                return `${tradeCount} trade, ${bankCount} bank`;
            }
            case 3: {
                const gCount = this.guarantors.filter(g => g.firstName).length;
                if (!gCount) return '';
                const name = this.guarantors[0].firstName + ' ' + this.guarantors[0].lastName;
                return gCount === 1 ? name.trim() : `${gCount} guarantors`;
            }
            case 4:
                return this.taxInfo.ein || '';
            case 5:
                return this.termsAccepted && this.signatureName ? 'Ready' : '';
            default: return '';
        }
    }

    _getCurrentStepData() {
        switch (this.currentStep) {
            case 1: return {
                company: this.company,
                billingAddress: this.billingAddress,
                shippingAddress: this.shippingSameAsBilling ? this.billingAddress : this.shippingAddress,
                shippingSameAsBilling: this.shippingSameAsBilling,
                applicants: this.applicants, apContact: this.apContact
            };
            case 2: return { tradeReferences: this.tradeReferences, bankReferences: this.bankReferences };
            case 3: return { guarantors: this.guarantors };
            case 4: return { taxInfo: this.taxInfo };
            case 5: return {
                termsAccepted: this.termsAccepted, creditAuthAccepted: this.creditAuthAccepted,
                signatureName: this.signatureName, signatureTitle: this.signatureTitle,
                signatureData: this.signatureData
            };
            default: return {};
        }
    }

    _scrollToTop() {
        const el = this.template.querySelector('.form-panel');
        if (el) el.scrollTo({ top: 0, behavior: 'smooth' });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unexpected error occurred.';
    }
}
