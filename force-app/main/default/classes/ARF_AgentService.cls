public with sharing class ARF_AgentService {

    public enum AgentUserType { COLLECTOR, CUSTOMER }

    public class ToolResult {
        public Boolean success;
        public String resultJson;
        public String displayMessage;
        public String actionType; // data, action, draft_email, escalation

        public ToolResult(Boolean success, String resultJson, String displayMessage, String actionType) {
            this.success = success;
            this.resultJson = resultJson;
            this.displayMessage = displayMessage;
            this.actionType = actionType;
        }
    }

    // ─── Tool Definitions ───────────────────────────────────────────────

    public static List<Map<String, Object>> getToolsForUserType(AgentUserType userType) {
        List<Map<String, Object>> tools = new List<Map<String, Object>>();

        if (userType == AgentUserType.COLLECTOR) {
            tools.add(buildTool('get_account_summary', 'Get comprehensive account summary including balance, aging, risk score, and collection strategy.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('get_invoices', 'Get all invoices for an account.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('get_invoices_filtered', 'Get invoices filtered by view, aging bucket, or search text.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID'),
                'view_filter' => optStr('Filter: all, open, overdue, disputed, promised'),
                'aging_bucket' => optStr('Aging bucket: current, 1-30, 31-60, 61-90, 90+'),
                'search_text' => optStr('Search text for document number or reference')
            }));
            tools.add(buildTool('get_aging_summary', 'Get aging bucket summary (current, 1-30, 31-60, 61-90, 90+ days).', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('get_payments', 'Get payment history for an account.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('get_disputes', 'Get all disputes for an account.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('get_promises', 'Get all promises to pay for an account.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('get_communications', 'Get communication history (emails, calls, etc.) for an account.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('get_notes', 'Get all notes for an account.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('get_tab_counts', 'Get counts for each tab (invoices, disputes, payments, etc.).', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('get_email_templates', 'Get available email templates filtered by locale and category.', new Map<String, Object>{
                'locale' => optStr('Locale code, e.g. en_US'),
                'category' => optStr('Template category, e.g. Collection, Reminder')
            }));
            tools.add(buildTool('get_open_invoices', 'Get open (unpaid) invoices for an account.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('create_dispute', 'Create a dispute on a specific invoice.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID'),
                'invoice_document_number' => reqStr('Invoice document number (e.g. INV-001)'),
                'category' => reqStr('Dispute category: Pricing, Quality, Delivery, Duplicate, Other'),
                'priority' => optStr('Priority: Low, Medium, High. Defaults to Medium'),
                'description' => reqStr('Description of the dispute reason')
            }));
            tools.add(buildTool('create_promise', 'Create a promise to pay on a specific invoice.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID'),
                'invoice_document_number' => reqStr('Invoice document number (e.g. INV-001)'),
                'promise_amount' => reqNum('Amount promised to pay'),
                'promise_date' => reqStr('Date the payment is promised (YYYY-MM-DD)'),
                'notes' => optStr('Additional notes about the promise')
            }));
            tools.add(buildTool('create_note', 'Create a note on an account.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID'),
                'subject' => reqStr('Note subject'),
                'body' => reqStr('Note body content')
            }));
            tools.add(buildTool('create_bulk_disputes', 'Create disputes on multiple invoices at once.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID'),
                'invoice_document_numbers' => reqArr('List of invoice document numbers'),
                'category' => reqStr('Dispute category'),
                'priority' => optStr('Priority: Low, Medium, High'),
                'description' => reqStr('Description of the dispute reason')
            }));
            tools.add(buildTool('create_bulk_promises', 'Create promises to pay on multiple invoices.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID'),
                'invoice_document_numbers' => reqArr('List of invoice document numbers'),
                'total_amount' => reqNum('Total amount promised'),
                'promise_date' => reqStr('Date the payment is promised (YYYY-MM-DD)'),
                'notes' => optStr('Additional notes')
            }));
            tools.add(buildTool('resolve_email_template', 'Resolve an email template with account/invoice merge fields.', new Map<String, Object>{
                'template_id' => reqStr('Salesforce Email Template ID'),
                'account_id' => reqStr('Salesforce Account ID'),
                'invoice_document_numbers' => optArr('List of invoice document numbers to include')
            }));
            tools.add(buildTool('draft_email', 'Draft an email for the collector to review before sending. If template_id is provided, the template is auto-resolved with merge fields and used as subject/body (subject and body params are ignored). Returns a preview — does NOT auto-send.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID'),
                'to_address' => reqStr('Recipient email address'),
                'template_id' => optStr('Email Template ID from get_email_templates. If provided, template is resolved and used as subject/body.'),
                'invoice_document_numbers' => optArr('Invoice document numbers to include in template merge fields'),
                'subject' => optStr('Email subject (ignored if template_id provided)'),
                'body' => optStr('Email body HTML (ignored if template_id provided)')
            }));
            tools.add(buildTool('snooze_account', 'Snooze an account to remove it from the worklist for a specified number of days.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID'),
                'snooze_days' => reqNum('Number of days to snooze (1-90)')
            }));
            tools.add(buildTool('log_call', 'Log a call/communication on an account.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID'),
                'subject' => reqStr('Call subject'),
                'body' => reqStr('Call notes/summary'),
                'duration_seconds' => optNum('Call duration in seconds')
            }));
        } else {
            // CUSTOMER tools — restricted subset
            tools.add(buildTool('get_portal_summary', 'Get your account summary including outstanding balance and past due amount.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('get_open_invoices', 'Get your open (unpaid) invoices.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('get_payment_history', 'Get your payment history.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('get_disputes', 'Get your disputes.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('get_promises', 'Get your promises to pay.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID')
            }));
            tools.add(buildTool('create_dispute', 'File a dispute on a specific invoice.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID'),
                'invoice_document_number' => reqStr('Invoice document number (e.g. INV-001)'),
                'category' => reqStr('Dispute category: Pricing, Quality, Delivery, Duplicate, Other'),
                'description' => reqStr('Description of the dispute reason')
            }));
            tools.add(buildTool('create_promise', 'Create a promise to pay on a specific invoice.', new Map<String, Object>{
                'account_id' => reqStr('Salesforce Account ID'),
                'invoice_document_number' => reqStr('Invoice document number (e.g. INV-001)'),
                'promise_amount' => reqNum('Amount promised to pay'),
                'promise_date' => reqStr('Date the payment is promised (YYYY-MM-DD)'),
                'notes' => optStr('Additional notes about the promise')
            }));
        }

        // Both user types can escalate
        tools.add(buildTool('escalate_to_human', 'Escalate the conversation to a human agent when you cannot resolve the request.', new Map<String, Object>{
            'account_id' => reqStr('Salesforce Account ID'),
            'reason' => reqStr('Reason for escalation')
        }));

        return tools;
    }

    // ─── Tool Execution Router ──────────────────────────────────────────

    public static ToolResult executeTool(String toolName, Map<String, Object> arguments, Id accountId, AgentUserType userType) {
        // Permission check
        if (!isToolAllowed(toolName, userType)) {
            return new ToolResult(false, null, 'You do not have permission to use this tool.', 'data');
        }

        try {
            switch on toolName {
                when 'get_account_summary' {
                    Account acct = ARF_Account360Controller.getAccountSummary(accountId);
                    return new ToolResult(true, JSON.serialize(acct), null, 'data');
                }
                when 'get_portal_summary' {
                    Object summary = ARF_PaymentPortalController.getAccountSummary(accountId);
                    return new ToolResult(true, JSON.serialize(summary), null, 'data');
                }
                when 'get_invoices' {
                    List<ARF_Invoice__c> invoices = ARF_Account360Controller.getInvoices(accountId);
                    return new ToolResult(true, JSON.serialize(invoices), null, 'data');
                }
                when 'get_open_invoices' {
                    Object invoices = ARF_PaymentPortalController.getOpenInvoices(accountId);
                    return new ToolResult(true, JSON.serialize(invoices), null, 'data');
                }
                when 'get_invoices_filtered' {
                    String viewFilter = (String) arguments.get('view_filter');
                    String agingBucket = (String) arguments.get('aging_bucket');
                    String searchText = (String) arguments.get('search_text');
                    List<ARF_Invoice__c> invoices = ARF_Account360Controller.getInvoicesFiltered(accountId, viewFilter, agingBucket, searchText);
                    return new ToolResult(true, JSON.serialize(invoices), null, 'data');
                }
                when 'get_aging_summary' {
                    Map<String, Decimal> aging = ARF_Account360Controller.getAgingSummary(accountId);
                    return new ToolResult(true, JSON.serialize(aging), null, 'data');
                }
                when 'get_payments' {
                    List<ARF_Payment__c> payments = ARF_Account360Controller.getPayments(accountId);
                    return new ToolResult(true, JSON.serialize(payments), null, 'data');
                }
                when 'get_payment_history' {
                    Object history = ARF_PaymentPortalController.getPaymentHistory(accountId);
                    return new ToolResult(true, JSON.serialize(history), null, 'data');
                }
                when 'get_disputes' {
                    List<ARF_Dispute__c> disputes = ARF_Account360Controller.getDisputes(accountId);
                    return new ToolResult(true, JSON.serialize(disputes), null, 'data');
                }
                when 'get_promises' {
                    List<ARF_Promise_To_Pay__c> promises = ARF_Account360Controller.getPromisesToPay(accountId);
                    return new ToolResult(true, JSON.serialize(promises), null, 'data');
                }
                when 'get_communications' {
                    List<ARF_Communication__c> comms = ARF_Account360Controller.getCommunications(accountId);
                    return new ToolResult(true, JSON.serialize(comms), null, 'data');
                }
                when 'get_notes' {
                    List<ARF_Note__c> notes = ARF_Account360Controller.getNotes(accountId);
                    return new ToolResult(true, JSON.serialize(notes), null, 'data');
                }
                when 'get_tab_counts' {
                    Map<String, Integer> counts = ARF_Account360Controller.getTabCounts(accountId);
                    return new ToolResult(true, JSON.serialize(counts), null, 'data');
                }
                when 'get_email_templates' {
                    String locale = (String) arguments.get('locale');
                    String category = (String) arguments.get('category');
                    List<ARF_Email_Template__c> templates = ARF_TransactionActionController.getEmailTemplates(locale, category);
                    return new ToolResult(true, JSON.serialize(templates), null, 'data');
                }
                when 'create_dispute' {
                    String docNum = (String) arguments.get('invoice_document_number');
                    Id invoiceId = resolveInvoiceId(docNum, accountId);
                    if (invoiceId == null) {
                        return new ToolResult(false, null, 'Invoice ' + docNum + ' not found for this account.', 'data');
                    }
                    ARF_Dispute__c dispute = new ARF_Dispute__c();
                    dispute.put('Account__c', accountId);
                    dispute.put('Invoice__c', invoiceId);
                    dispute.put('Category__c', (String) arguments.get('category'));
                    dispute.put('Priority__c', arguments.containsKey('priority') ? (String) arguments.get('priority') : 'Medium');
                    dispute.put('Description__c', (String) arguments.get('description'));
                    dispute.put('Status__c', 'New');
                    ARF_Dispute__c created = ARF_Account360Controller.createDispute(dispute);
                    return new ToolResult(true, JSON.serialize(created), 'Dispute created on invoice ' + docNum + '.', 'action');
                }
                when 'create_promise' {
                    String docNum = (String) arguments.get('invoice_document_number');
                    Id invoiceId = resolveInvoiceId(docNum, accountId);
                    if (invoiceId == null) {
                        return new ToolResult(false, null, 'Invoice ' + docNum + ' not found for this account.', 'data');
                    }
                    ARF_Promise_To_Pay__c promise = new ARF_Promise_To_Pay__c();
                    promise.put('Account__c', accountId);
                    promise.put('Invoice__c', invoiceId);
                    promise.put('Amount__c', (Decimal) arguments.get('promise_amount'));
                    promise.put('Promise_Date__c', Date.valueOf((String) arguments.get('promise_date')));
                    promise.put('Status__c', 'Open');
                    if (arguments.containsKey('notes') && arguments.get('notes') != null) {
                        promise.put('Notes__c', (String) arguments.get('notes'));
                    }
                    ARF_Promise_To_Pay__c created = ARF_Account360Controller.createPromiseToPay(promise);
                    return new ToolResult(true, JSON.serialize(created), 'Promise to pay created on invoice ' + docNum + '.', 'action');
                }
                when 'create_note' {
                    ARF_Note__c note = new ARF_Note__c();
                    note.put('Account__c', accountId);
                    note.put('Title__c', (String) arguments.get('subject'));
                    note.put('Body__c', (String) arguments.get('body'));
                    ARF_Note__c created = ARF_Account360Controller.createNote(note);
                    return new ToolResult(true, JSON.serialize(created), 'Note created.', 'action');
                }
                when 'create_bulk_disputes' {
                    List<Object> docNums = (List<Object>) arguments.get('invoice_document_numbers');
                    List<Id> invoiceIds = resolveInvoiceIds(docNums, accountId);
                    if (invoiceIds.isEmpty()) {
                        return new ToolResult(false, null, 'No matching invoices found.', 'data');
                    }
                    List<ARF_Dispute__c> disputes = ARF_TransactionActionController.createBulkDisputes(
                        accountId, invoiceIds,
                        (String) arguments.get('category'),
                        arguments.containsKey('priority') ? (String) arguments.get('priority') : 'Medium',
                        (String) arguments.get('description')
                    );
                    return new ToolResult(true, JSON.serialize(disputes), disputes.size() + ' dispute(s) created.', 'action');
                }
                when 'create_bulk_promises' {
                    List<Object> docNums = (List<Object>) arguments.get('invoice_document_numbers');
                    List<Id> invoiceIds = resolveInvoiceIds(docNums, accountId);
                    if (invoiceIds.isEmpty()) {
                        return new ToolResult(false, null, 'No matching invoices found.', 'data');
                    }
                    List<ARF_Promise_To_Pay__c> promises = ARF_TransactionActionController.createBulkPromises(
                        accountId, invoiceIds,
                        (Decimal) arguments.get('total_amount'),
                        Date.valueOf((String) arguments.get('promise_date')),
                        (String) arguments.get('notes')
                    );
                    return new ToolResult(true, JSON.serialize(promises), promises.size() + ' promise(s) created.', 'action');
                }
                when 'resolve_email_template' {
                    Id templateId = (Id) arguments.get('template_id');
                    List<Id> invoiceIds = new List<Id>();
                    if (arguments.containsKey('invoice_document_numbers') && arguments.get('invoice_document_numbers') != null) {
                        List<Object> docNums = (List<Object>) arguments.get('invoice_document_numbers');
                        invoiceIds = resolveInvoiceIds(docNums, accountId);
                    }
                    Map<String, String> resolved = ARF_TransactionActionController.resolveTemplate(templateId, accountId, invoiceIds);
                    return new ToolResult(true, JSON.serialize(resolved), null, 'data');
                }
                when 'draft_email' {
                    String emailSubject = (String) arguments.get('subject');
                    String emailBody = (String) arguments.get('body');

                    // If template_id provided, resolve template and use its subject/body
                    if (arguments.containsKey('template_id') && arguments.get('template_id') != null) {
                        Id templateId = (Id) arguments.get('template_id');
                        List<Id> invoiceIds = new List<Id>();
                        if (arguments.containsKey('invoice_document_numbers') && arguments.get('invoice_document_numbers') != null) {
                            List<Object> docNums = (List<Object>) arguments.get('invoice_document_numbers');
                            invoiceIds = resolveInvoiceIds(docNums, accountId);
                        }
                        Map<String, String> resolved = ARF_TransactionActionController.resolveTemplate(templateId, accountId, invoiceIds);
                        emailSubject = resolved.get('subject');
                        emailBody = resolved.get('body');
                    }

                    Map<String, Object> draft = new Map<String, Object>{
                        'to' => (String) arguments.get('to_address'),
                        'subject' => emailSubject,
                        'body' => emailBody,
                        'accountId' => accountId
                    };
                    return new ToolResult(true, JSON.serialize(draft), 'Email draft ready for review.', 'draft_email');
                }
                when 'snooze_account' {
                    Integer days = ((Decimal) arguments.get('snooze_days')).intValue();
                    ARF_CollectionWorklistController.snoozeAccount(accountId, days);
                    return new ToolResult(true, null, 'Account snoozed for ' + days + ' day(s).', 'action');
                }
                when 'log_call' {
                    Integer duration = arguments.containsKey('duration_seconds') && arguments.get('duration_seconds') != null
                        ? ((Decimal) arguments.get('duration_seconds')).intValue()
                        : 0;
                    ARF_Communication__c comm = ARF_CollectionWorklistController.quickLogCall(
                        accountId,
                        (String) arguments.get('subject'),
                        (String) arguments.get('body'),
                        duration
                    );
                    return new ToolResult(true, JSON.serialize(comm), 'Call logged.', 'action');
                }
                when 'escalate_to_human' {
                    // Handled by ARF_AgentController.escalateToHuman — return marker
                    return new ToolResult(true, null, 'Conversation escalated to a human agent.', 'escalation');
                }
                when else {
                    return new ToolResult(false, null, 'Unknown tool: ' + toolName, 'data');
                }
            }
        } catch (Exception e) {
            return new ToolResult(false, null, 'Error executing ' + toolName + ': ' + e.getMessage(), 'data');
        }
    }

    // ─── Permission Check ───────────────────────────────────────────────

    private static final Set<String> CUSTOMER_TOOLS = new Set<String>{
        'get_portal_summary', 'get_open_invoices', 'get_payment_history',
        'get_disputes', 'get_promises',
        'create_dispute', 'create_promise',
        'escalate_to_human'
    };

    private static final Set<String> COLLECTOR_TOOLS = new Set<String>{
        'get_account_summary', 'get_invoices', 'get_invoices_filtered',
        'get_aging_summary', 'get_payments', 'get_disputes', 'get_promises',
        'get_communications', 'get_notes', 'get_tab_counts',
        'get_email_templates', 'get_open_invoices',
        'create_dispute', 'create_promise', 'create_note',
        'create_bulk_disputes', 'create_bulk_promises',
        'resolve_email_template', 'draft_email',
        'snooze_account', 'log_call',
        'escalate_to_human'
    };

    @TestVisible
    private static Boolean isToolAllowed(String toolName, AgentUserType userType) {
        if (userType == AgentUserType.CUSTOMER) {
            return CUSTOMER_TOOLS.contains(toolName);
        }
        return COLLECTOR_TOOLS.contains(toolName);
    }

    // ─── Invoice Resolution Helpers ─────────────────────────────────────

    public static Id resolveInvoiceId(String documentNumber, Id accountId) {
        if (String.isBlank(documentNumber) || accountId == null) {
            return null;
        }
        List<ARF_Invoice__c> invoices = [
            SELECT Id FROM ARF_Invoice__c
            WHERE Document_Number__c = :documentNumber
            AND Account__c = :accountId
            LIMIT 1
        ];
        return invoices.isEmpty() ? null : invoices[0].Id;
    }

    private static List<Id> resolveInvoiceIds(List<Object> documentNumbers, Id accountId) {
        Set<String> docNums = new Set<String>();
        for (Object o : documentNumbers) {
            docNums.add(String.valueOf(o));
        }
        List<ARF_Invoice__c> invoices = [
            SELECT Id FROM ARF_Invoice__c
            WHERE Document_Number__c IN :docNums
            AND Account__c = :accountId
        ];
        List<Id> ids = new List<Id>();
        for (ARF_Invoice__c inv : invoices) {
            ids.add(inv.Id);
        }
        return ids;
    }

    // ─── Tool Definition Builders ───────────────────────────────────────

    private static Map<String, Object> buildTool(String name, String description, Map<String, Object> properties) {
        Map<String, Object> tool = new Map<String, Object>{
            'name' => name,
            'description' => description,
            'input_schema' => buildSchema(properties)
        };
        return tool;
    }

    private static Map<String, Object> buildSchema(Map<String, Object> properties) {
        Map<String, Object> schema = new Map<String, Object>();
        schema.put('type', 'object');

        Map<String, Object> props = new Map<String, Object>();
        List<String> required = new List<String>();

        for (String key : properties.keySet()) {
            Map<String, Object> propDef = (Map<String, Object>) properties.get(key);
            props.put(key, propDef);
            if (propDef.containsKey('required') && (Boolean) propDef.get('required')) {
                required.add(key);
                propDef.remove('required');
            }
        }

        schema.put('properties', props);
        if (!required.isEmpty()) {
            schema.put('required', required);
        }
        return schema;
    }

    private static Map<String, Object> reqStr(String description) {
        return new Map<String, Object>{ 'type' => 'string', 'description' => description, 'required' => true };
    }
    private static Map<String, Object> optStr(String description) {
        return new Map<String, Object>{ 'type' => 'string', 'description' => description };
    }
    private static Map<String, Object> reqNum(String description) {
        return new Map<String, Object>{ 'type' => 'number', 'description' => description, 'required' => true };
    }
    private static Map<String, Object> optNum(String description) {
        return new Map<String, Object>{ 'type' => 'number', 'description' => description };
    }
    private static Map<String, Object> reqArr(String description) {
        return new Map<String, Object>{ 'type' => 'array', 'description' => description, 'items' => new Map<String, Object>{ 'type' => 'string' }, 'required' => true };
    }
    private static Map<String, Object> optArr(String description) {
        return new Map<String, Object>{ 'type' => 'array', 'description' => description, 'items' => new Map<String, Object>{ 'type' => 'string' } };
    }
}
