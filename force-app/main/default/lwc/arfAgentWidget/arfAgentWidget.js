import { LightningElement, api, track } from 'lwc';
import sendMessage from '@salesforce/apex/ARF_AgentController.sendMessage';
import saveChatTranscript from '@salesforce/apex/ARF_AgentController.saveChatTranscript';

export default class ArfAgentWidget extends LightningElement {
    @api recordId;
    @api accountId;
    @api userType = 'collector';

    @track isOpen = false;
    @track messages = [];
    @track isTyping = false;

    inputText = '';
    chatSessionId = null;
    hasGreeted = false;

    get effectiveAccountId() {
        return this.recordId || this.accountId;
    }

    get isCollector() {
        return this.userType === 'collector';
    }

    get panelTitle() {
        return this.isCollector ? 'AR Flow Assistant' : 'Support Assistant';
    }

    get welcomeMessage() {
        return this.isCollector
            ? 'Hi! I can help you manage this account — query invoices, log disputes, draft emails, and more. What would you like to do?'
            : 'Hi! I can help you with your invoices, payments, disputes, and more. How can I assist you today?';
    }

    get hasMessages() {
        return this.messages.length > 0;
    }

    get sendDisabled() {
        return this.isTyping;
    }

    // ─── Toggle & Lifecycle ─────────────────────────────────────────────

    handleToggle() {
        this.isOpen = !this.isOpen;
        if (this.isOpen && !this.hasGreeted) {
            this.hasGreeted = true;
            this.messages = [this.buildMessage('agent', this.welcomeMessage)];
        }
        if (this.isOpen) {
            this.scrollToBottomDelayed();
        }
    }

    handleClose() {
        if (this.messages.length > 1) {
            const transcript = this.messages
                .map(m => `[${m.timestamp}] ${m.role === 'user' ? 'User' : 'Agent'}: ${m.text}`)
                .join('\n');
            saveChatTranscript({
                accountId: this.effectiveAccountId,
                chatSessionId: this.chatSessionId || 'unsaved',
                transcriptText: transcript,
                status: 'Completed'
            }).catch(err => console.error('Save transcript error:', err));
        }
        this.isOpen = false;
    }

    // ─── Message Handling ───────────────────────────────────────────────

    handleInputChange(event) {
        this.inputText = event.target.value;
    }

    handleKeyPress(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSend();
        }
    }

    async handleSend() {
        const text = this.inputText?.trim();
        if (!text || this.isTyping) return;

        // Add user message
        this.messages = [...this.messages, this.buildMessage('user', text)];
        this.inputText = '';

        // Clear textarea
        const textarea = this.template.querySelector('.chat-input');
        if (textarea) textarea.value = '';

        this.isTyping = true;
        this.scrollToBottomDelayed();

        try {
            // Build conversation history for API (exclude welcome message if it has no tool context)
            const conversationHistory = this.buildConversationHistory();

            const result = await sendMessage({
                accountId: this.effectiveAccountId,
                userMessage: text,
                conversationJson: JSON.stringify(conversationHistory),
                userType: this.userType,
                chatSessionId: this.chatSessionId
            });

            this.chatSessionId = result.chatSessionId;

            // Build action cards
            const actions = (result.actions || []).map(a => ({
                ...a,
                id: this.generateMsgId(),
                isAction: a.cardType === 'action',
                isDraftEmail: a.cardType === 'draft_email',
                isEscalation: a.cardType === 'escalation',
                parsedData: a.dataJson ? JSON.parse(a.dataJson) : null
            }));

            this.messages = [...this.messages, this.buildMessage('agent', result.message || '', {
                actions: actions,
                escalated: result.escalated
            })];

        } catch (error) {
            const errMsg = error?.body?.message || error?.message || 'Something went wrong. Please try again.';
            this.messages = [...this.messages, this.buildMessage('agent', errMsg, { isError: true })];
        } finally {
            this.isTyping = false;
            this.scrollToBottomDelayed();
        }
    }

    // ─── Draft Email Actions ────────────────────────────────────────────

    handleSendDraft(event) {
        const msgId = event.currentTarget.dataset.msgId;
        const msg = this.messages.find(m => m.actions?.some(a => a.id === msgId));
        const action = msg?.actions?.find(a => a.id === msgId);
        if (!action?.parsedData) return;

        // Dispatch event for parent (email composer) to handle
        this.dispatchEvent(new CustomEvent('sendemail', {
            detail: {
                to: action.parsedData.to,
                subject: action.parsedData.subject,
                body: action.parsedData.body,
                accountId: action.parsedData.accountId
            },
            bubbles: true,
            composed: true
        }));
    }

    handleEditDraft(event) {
        const msgId = event.currentTarget.dataset.msgId;
        const msg = this.messages.find(m => m.actions?.some(a => a.id === msgId));
        const action = msg?.actions?.find(a => a.id === msgId);
        if (!action?.parsedData) return;

        this.dispatchEvent(new CustomEvent('editemail', {
            detail: {
                to: action.parsedData.to,
                subject: action.parsedData.subject,
                body: action.parsedData.body,
                accountId: action.parsedData.accountId
            },
            bubbles: true,
            composed: true
        }));
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    buildConversationHistory() {
        // Convert UI messages to Claude API format (skip the welcome message)
        const history = [];
        for (const msg of this.messages) {
            if (msg.role === 'user') {
                history.push({ role: 'user', content: msg.text });
            }
            // We don't send agent messages back — the backend manages full conversation state
        }
        // Remove the last user message since it's sent separately
        if (history.length > 0) {
            history.pop();
        }
        return history;
    }

    scrollToBottomDelayed() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const container = this.template.querySelector('.chat-messages');
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        }, 50);
    }

    buildMessage(role, text, extras = {}) {
        return {
            id: this.generateMsgId(),
            role: role,
            text: text,
            timestamp: this.formatTime(),
            actions: [],
            isUser: role === 'user',
            isAgent: role === 'agent' && !extras.isError,
            isError: false,
            bubbleWrapperClass: role === 'user' ? 'user' : 'agent',
            ...extras
        };
    }

    generateMsgId() {
        return 'msg-' + Date.now() + '-' + Math.random().toString(36).substr(2, 5);
    }

    formatTime() {
        return new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }
}
