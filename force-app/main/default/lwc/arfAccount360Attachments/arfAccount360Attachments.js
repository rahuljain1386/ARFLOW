import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAccountAttachments from '@salesforce/apex/ARF_Account360Controller.getAccountAttachments';

export default class ArfAccount360Attachments extends LightningElement {
    @api recordId;
    @track attachments = [];
    error;

    _refreshKey = 0;
    @api
    get refreshKey() { return this._refreshKey; }
    set refreshKey(value) {
        this._refreshKey = value;
        if (this.recordId) {
            this.loadAttachments();
        }
    }

    connectedCallback() {
        this.loadAttachments();
    }

    async loadAttachments() {
        try {
            const data = await getAccountAttachments({ accountId: this.recordId });
            this.attachments = (data || []).map(f => ({
                ...f,
                downloadUrl: '/sfc/servlet.shepherd/version/download/' + f.versionId,
                previewUrl: '/sfc/servlet.shepherd/document/download/' + f.documentId,
                sizeLabel: this.formatFileSize(f.size),
                iconName: this.getFileIcon(f.extension),
                sourceLabel: f.commSubject ? f.commSubject : 'Account',
                formattedDate: f.createdDate ? new Date(f.createdDate).toLocaleDateString() : ''
            }));
            this.error = undefined;
        } catch (err) {
            this.error = err;
            this.attachments = [];
        }
    }

    handleUploadFinished(event) {
        const files = event.detail.files;
        this.dispatchEvent(new ShowToastEvent({
            title: 'Files Uploaded',
            message: `${files.length} file(s) uploaded`,
            variant: 'success'
        }));
        this.loadAttachments();
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
        if (['txt', 'log'].includes(lower)) return 'doctype:txt';
        if (lower === 'zip') return 'doctype:zip';
        return 'doctype:unknown';
    }

    get hasData() { return this.attachments && this.attachments.length > 0; }
    get recordCount() { return this.attachments ? this.attachments.length : 0; }
    get cardTitle() { return `Attachments (${this.recordCount})`; }
    get acceptedFormats() {
        return ['.pdf', '.xlsx', '.xls', '.csv', '.doc', '.docx', '.png', '.jpg', '.jpeg', '.gif', '.txt', '.zip'];
    }
}
