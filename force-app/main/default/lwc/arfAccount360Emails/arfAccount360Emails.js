import { LightningElement, api, track } from 'lwc';
import getCommunications from '@salesforce/apex/ARF_Account360Controller.getCommunications';
import getAttachmentsForCommunication from '@salesforce/apex/ARF_Account360Controller.getAttachmentsForCommunication';
import translateCommunication from '@salesforce/apex/ARF_Account360Controller.translateCommunication';

const CHANNEL_OPTIONS = [
    { label: 'All Channels', value: 'All' },
    { label: 'Email', value: 'Email' },
    { label: 'SMS', value: 'SMS' },
    { label: 'Phone', value: 'Phone' },
    { label: 'Note', value: 'Note' },
    { label: 'Letter', value: 'Letter' }
];

export default class ArfAccount360Emails extends LightningElement {
    @api recordId;
    channelOptions = CHANNEL_OPTIONS;
    @track allCommunications = [];
    @track filteredCommunications = [];
    error;
    selectedChannel = 'All';

    expandedCommId = null;
    @track expandedAttachments = [];
    translatingCommId = null;
    showTranslatedMap = {};

    // Reply / Forward / Compose modal
    showComposeModal = false;
    composeReplyMode = false;
    composePrefillSubject = '';
    composePrefillBody = '';
    composePrefillTo = '';
    composePrefillCc = '';

    _refreshKey = 0;
    @api
    get refreshKey() { return this._refreshKey; }
    set refreshKey(value) {
        this._refreshKey = value;
        if (this.recordId) {
            this.loadCommunications();
        }
    }

    _agentDraft = null;
    @api
    get agentDraft() { return this._agentDraft; }
    set agentDraft(value) {
        this._agentDraft = value;
        if (value) {
            this.composePrefillTo = value.to || '';
            this.composePrefillCc = '';
            this.composePrefillSubject = value.subject || '';
            this.composePrefillBody = value.body || '';
            this.composeReplyMode = true;
            this.showComposeModal = true;
        }
    }

    connectedCallback() {
        this.loadCommunications();
    }

    async loadCommunications() {
        try {
            const data = await getCommunications({ accountId: this.recordId });
            this.allCommunications = data.map(c => {
                const isNonEnglish = c.Detected_Language__c && c.Detected_Language__c !== 'en';
                const showTranslated = this.showTranslatedMap[c.Id] || false;
                const hasTranslation = !!c.Translated_Body__c;
                return {
                    ...c,
                    commUrl: '/' + c.Id,
                    contactName: c.Contact__r ? c.Contact__r.Name : '',
                    directionClass: c.Direction__c === 'Inbound' ? 'direction-inbound' : 'direction-outbound',
                    directionLabel: c.Direction__c === 'Inbound' ? 'IN' : 'OUT',
                    channelIcon: this.getChannelIcon(c.Channel__c),
                    isExpanded: c.Id === this.expandedCommId,
                    hasAttachment: c.Has_Attachment__c || false,
                    formattedDate: c.Sent_Date__c ? new Date(c.Sent_Date__c).toLocaleString() : '',
                    bodyPreview: (showTranslated && c.Translated_Body__c)
                        ? c.Translated_Body__c : (c.HTML_Body__c || c.Body__c || ''),
                    isNonEnglish,
                    languageBadge: c.Detected_Language_Name__c || c.Detected_Language__c || null,
                    hasTranslation,
                    showTranslated,
                    isTranslating: this.translatingCommId === c.Id,
                    displaySubject: (showTranslated && c.Translated_Subject__c)
                        ? c.Translated_Subject__c : (c.Subject__c || ''),
                    translateButtonLabel: hasTranslation
                        ? (showTranslated
                            ? 'Show Original (' + (c.Detected_Language_Name__c || c.Detected_Language__c) + ')'
                            : 'Show Translation (English)')
                        : 'Translate to English'
                };
            });
            this.applyFilter();
            this.error = undefined;
        } catch (error) {
            this.error = error;
            this.allCommunications = [];
            this.filteredCommunications = [];
        }
    }

    getChannelIcon(channel) {
        switch (channel) {
            case 'Email': return 'utility:email';
            case 'Phone': return 'utility:call';
            case 'SMS': return 'utility:sms';
            case 'Letter': return 'utility:page';
            case 'Note': return 'utility:note';
            default: return 'utility:email';
        }
    }

    handleChannelChange(event) {
        this.selectedChannel = event.detail.value;
        this.applyFilter();
    }

    applyFilter() {
        if (!this.allCommunications) return;
        if (this.selectedChannel === 'All') {
            this.filteredCommunications = [...this.allCommunications];
        } else {
            this.filteredCommunications = this.allCommunications.filter(
                c => c.Channel__c === this.selectedChannel
            );
        }
    }

    async handleRowClick(event) {
        const commId = event.currentTarget.dataset.id;
        this.expandedCommId = this.expandedCommId === commId ? null : commId;
        this.expandedAttachments = [];

        if (this.expandedCommId) {
            const comm = this.allCommunications.find(c => c.Id === this.expandedCommId);
            if (comm && comm.hasAttachment) {
                try {
                    const files = await getAttachmentsForCommunication({ communicationId: this.expandedCommId });
                    this.expandedAttachments = (files || []).map(f => ({
                        ...f,
                        downloadUrl: '/sfc/servlet.shepherd/version/download/' + f.versionId,
                        previewUrl: '/sfc/servlet.shepherd/document/download/' + f.documentId,
                        sizeLabel: this.formatFileSize(f.size),
                        iconName: this.getFileIcon(f.extension)
                    }));
                } catch (e) {
                    // Non-critical
                }
            }
        }

        this.allCommunications = this.allCommunications.map(c => ({
            ...c,
            isExpanded: c.Id === this.expandedCommId
        }));
        this.applyFilter();
    }

    async handleTranslate(event) {
        event.stopPropagation();
        const commId = event.currentTarget.dataset.id;
        const comm = this.allCommunications.find(c => c.Id === commId);

        // If already translated, toggle view
        if (comm && comm.hasTranslation) {
            this.showTranslatedMap = {
                ...this.showTranslatedMap,
                [commId]: !this.showTranslatedMap[commId]
            };
            this.refreshDisplayData();
            return;
        }

        // Call API to translate
        this.translatingCommId = commId;
        this.refreshDisplayData();
        try {
            const result = await translateCommunication({ communicationId: commId });
            this.allCommunications = this.allCommunications.map(c => {
                if (c.Id === commId) {
                    return {
                        ...c,
                        Translated_Body__c: result.Translated_Body__c || '',
                        Translated_Subject__c: result.Translated_Subject__c || '',
                        hasTranslation: true
                    };
                }
                return c;
            });
            this.showTranslatedMap = {
                ...this.showTranslatedMap,
                [commId]: true
            };
        } catch (error) {
            console.error('Translation error:', error);
        } finally {
            this.translatingCommId = null;
            this.refreshDisplayData();
        }
    }

    refreshDisplayData() {
        this.allCommunications = this.allCommunications.map(c => {
            const showTranslated = this.showTranslatedMap[c.Id] || false;
            const hasTranslation = !!c.Translated_Body__c;
            return {
                ...c,
                showTranslated,
                hasTranslation,
                isTranslating: this.translatingCommId === c.Id,
                bodyPreview: (showTranslated && c.Translated_Body__c)
                    ? c.Translated_Body__c : (c.HTML_Body__c || c.Body__c || ''),
                displaySubject: (showTranslated && c.Translated_Subject__c)
                    ? c.Translated_Subject__c : (c.Subject__c || ''),
                translateButtonLabel: hasTranslation
                    ? (showTranslated
                        ? 'Show Original (' + (c.Detected_Language_Name__c || c.Detected_Language__c) + ')'
                        : 'Show Translation (English)')
                    : 'Translate to English'
            };
        });
        this.applyFilter();
    }

    formatFileSize(bytes) {
        if (!bytes) return '0 B';
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / 1048576).toFixed(1) + ' MB';
    }

    getFileIcon(ext) {
        if (!ext) return 'doctype:unknown';
        const lower = ext.toLowerCase();
        if (lower === 'pdf') return 'doctype:pdf';
        if (['csv', 'xls', 'xlsx'].includes(lower)) return 'doctype:excel';
        if (['doc', 'docx'].includes(lower)) return 'doctype:word';
        if (['png', 'jpg', 'jpeg', 'gif'].includes(lower)) return 'doctype:image';
        return 'doctype:unknown';
    }

    get hasExpandedAttachments() {
        return this.expandedAttachments && this.expandedAttachments.length > 0;
    }

    handleReply(event) {
        event.stopPropagation();
        const commId = event.currentTarget.dataset.id;
        const comm = this.allCommunications.find(c => c.Id === commId);
        if (!comm) return;
        this.composeReplyMode = true;
        this.composePrefillTo = comm.From_Address__c || '';
        this.composePrefillCc = comm.CC_Addresses__c || '';
        this.composePrefillSubject = 'Re: ' + (comm.Subject__c || '');
        this.composePrefillBody = '<br/><br/><hr/><p><b>From:</b> ' + (comm.From_Address__c || '') +
            '<br/><b>Date:</b> ' + (comm.formattedDate || '') +
            '<br/><b>Subject:</b> ' + (comm.Subject__c || '') +
            '</p>' + (comm.HTML_Body__c || comm.Body__c || '');
        this.showComposeModal = true;
    }

    handleForward(event) {
        event.stopPropagation();
        const commId = event.currentTarget.dataset.id;
        const comm = this.allCommunications.find(c => c.Id === commId);
        if (!comm) return;
        this.composeReplyMode = true;
        this.composePrefillTo = '';
        this.composePrefillCc = '';
        this.composePrefillSubject = 'Fwd: ' + (comm.Subject__c || '');
        this.composePrefillBody = '<br/><br/><hr/><p><b>---------- Forwarded message ----------</b>' +
            '<br/><b>From:</b> ' + (comm.From_Address__c || '') +
            '<br/><b>Date:</b> ' + (comm.formattedDate || '') +
            '<br/><b>Subject:</b> ' + (comm.Subject__c || '') +
            '<br/><b>To:</b> ' + (comm.To_Address__c || '') +
            '</p>' + (comm.HTML_Body__c || comm.Body__c || '');
        this.showComposeModal = true;
    }

    handleCompose() {
        this.composeReplyMode = false;
        this.composePrefillTo = '';
        this.composePrefillCc = '';
        this.composePrefillSubject = '';
        this.composePrefillBody = '';
        this.showComposeModal = true;
    }

    handleComposeClose() {
        this.showComposeModal = false;
    }

    handleComposeSave() {
        this.showComposeModal = false;
        this.loadCommunications();
        this.dispatchEvent(new CustomEvent('recordcreated', { bubbles: true, composed: true }));
    }

    renderedCallback() {
        // Set innerHTML for expanded body divs (lwc:dom="manual")
        if (this.expandedCommId) {
            const bodyDivs = this.template.querySelectorAll('.comm-expanded-body[data-body-id]');
            bodyDivs.forEach(div => {
                const commId = div.dataset.bodyId;
                const comm = this.allCommunications.find(c => c.Id === commId);
                if (comm && div.innerHTML !== comm.bodyPreview) {
                    div.innerHTML = comm.bodyPreview || '';
                }
            });
        }
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    get emptyInvoices() { return []; }
    get hasData() { return this.filteredCommunications && this.filteredCommunications.length > 0; }
    get recordCount() { return this.filteredCommunications ? this.filteredCommunications.length : 0; }
    get cardTitle() { return `Communications (${this.recordCount})`; }
}
