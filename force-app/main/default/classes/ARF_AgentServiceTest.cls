@isTest
private class ARF_AgentServiceTest {

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(Name = 'Agent Test Account');
        insert acct;

        ARF_Invoice__c inv1 = new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'INV-001',
            Amount__c = 5000,
            Balance__c = 5000,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-30),
            Due_Date__c = Date.today().addDays(-10)
        );
        ARF_Invoice__c inv2 = new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'INV-002',
            Amount__c = 3000,
            Balance__c = 3000,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-15),
            Due_Date__c = Date.today().addDays(5)
        );
        insert new List<ARF_Invoice__c>{ inv1, inv2 };
    }

    // ─── Tool Permission Tests ──────────────────────────────────────────

    @isTest
    static void testCollectorGetsAllTools() {
        List<Map<String, Object>> tools = ARF_AgentService.getToolsForUserType(ARF_AgentService.AgentUserType.COLLECTOR);
        Set<String> toolNames = new Set<String>();
        for (Map<String, Object> tool : tools) {
            toolNames.add((String) tool.get('name'));
        }
        // Collector should have collector-only tools
        System.assert(toolNames.contains('get_account_summary'), 'Collector should have get_account_summary');
        System.assert(toolNames.contains('get_invoices'), 'Collector should have get_invoices');
        System.assert(toolNames.contains('draft_email'), 'Collector should have draft_email');
        System.assert(toolNames.contains('snooze_account'), 'Collector should have snooze_account');
        System.assert(toolNames.contains('log_call'), 'Collector should have log_call');
        System.assert(toolNames.contains('create_note'), 'Collector should have create_note');
        System.assert(toolNames.contains('escalate_to_human'), 'Collector should have escalate');
    }

    @isTest
    static void testCustomerGetsSubset() {
        List<Map<String, Object>> tools = ARF_AgentService.getToolsForUserType(ARF_AgentService.AgentUserType.CUSTOMER);
        Set<String> toolNames = new Set<String>();
        for (Map<String, Object> tool : tools) {
            toolNames.add((String) tool.get('name'));
        }
        // Customer should have portal tools
        System.assert(toolNames.contains('get_portal_summary'), 'Customer should have get_portal_summary');
        System.assert(toolNames.contains('get_open_invoices'), 'Customer should have get_open_invoices');
        System.assert(toolNames.contains('create_dispute'), 'Customer should have create_dispute');
        System.assert(toolNames.contains('create_promise'), 'Customer should have create_promise');
        System.assert(toolNames.contains('escalate_to_human'), 'Customer should have escalate');

        // Customer should NOT have collector-only tools
        System.assert(!toolNames.contains('get_account_summary'), 'Customer should not have get_account_summary');
        System.assert(!toolNames.contains('draft_email'), 'Customer should not have draft_email');
        System.assert(!toolNames.contains('snooze_account'), 'Customer should not have snooze_account');
        System.assert(!toolNames.contains('get_notes'), 'Customer should not have get_notes');
        System.assert(!toolNames.contains('log_call'), 'Customer should not have log_call');
    }

    @isTest
    static void testCustomerDeniedCollectorTool() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'snooze_account',
            new Map<String, Object>{ 'snooze_days' => 7 },
            acct.Id,
            ARF_AgentService.AgentUserType.CUSTOMER
        );
        System.assertEquals(false, result.success, 'Customer should be denied snooze_account');
        System.assert(result.displayMessage.contains('permission'), 'Should mention permission');
    }

    // ─── Tool Execution Tests ───────────────────────────────────────────

    @isTest
    static void testGetInvoices() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'get_invoices',
            new Map<String, Object>{ 'account_id' => acct.Id },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
        System.assertEquals('data', result.actionType);
        System.assertNotEquals(null, result.resultJson);
    }

    @isTest
    static void testGetOpenInvoices() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'get_open_invoices',
            new Map<String, Object>{ 'account_id' => acct.Id },
            acct.Id,
            ARF_AgentService.AgentUserType.CUSTOMER
        );
        System.assertEquals(true, result.success);
        System.assertEquals('data', result.actionType);
    }

    @isTest
    static void testCreateDispute() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'create_dispute',
            new Map<String, Object>{
                'invoice_document_number' => 'INV-001',
                'category' => 'Pricing',
                'description' => 'Overcharged by $500'
            },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
        System.assertEquals('action', result.actionType);
        System.assert(result.displayMessage.contains('Dispute created'));

        List<ARF_Dispute__c> disputes = [SELECT Id, Category__c FROM ARF_Dispute__c WHERE Account__c = :acct.Id];
        System.assertEquals(1, disputes.size());
        System.assertEquals('Pricing', disputes[0].Category__c);
    }

    @isTest
    static void testCreateDisputeInvoiceNotFound() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'create_dispute',
            new Map<String, Object>{
                'invoice_document_number' => 'INV-999',
                'category' => 'Quality',
                'description' => 'Damaged goods'
            },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(false, result.success);
        System.assert(result.displayMessage.contains('not found'));
    }

    @isTest
    static void testCreatePromise() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'create_promise',
            new Map<String, Object>{
                'invoice_document_number' => 'INV-001',
                'promise_amount' => 5000,
                'promise_date' => '2026-04-01',
                'notes' => 'Will pay by end of month'
            },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
        System.assertEquals('action', result.actionType);

        List<ARF_Promise_To_Pay__c> promises = [SELECT Id, Amount__c FROM ARF_Promise_To_Pay__c WHERE Account__c = :acct.Id];
        System.assertEquals(1, promises.size());
        System.assertEquals(5000, promises[0].Amount__c);
    }

    @isTest
    static void testCreateNote() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'create_note',
            new Map<String, Object>{
                'subject' => 'Follow-up needed',
                'body' => 'Customer requested callback tomorrow'
            },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
        System.assertEquals('action', result.actionType);

        List<ARF_Note__c> notes = [SELECT Id, Title__c FROM ARF_Note__c WHERE Account__c = :acct.Id];
        System.assertEquals(1, notes.size());
    }

    @isTest
    static void testDraftEmail() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'draft_email',
            new Map<String, Object>{
                'to_address' => 'customer@test.com',
                'subject' => 'Payment Reminder',
                'body' => '<p>Please remit payment for INV-001.</p>'
            },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
        System.assertEquals('draft_email', result.actionType);
        System.assert(result.resultJson.contains('customer@test.com'));
    }

    @isTest
    static void testEscalateToHuman() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'escalate_to_human',
            new Map<String, Object>{ 'reason' => 'Customer upset' },
            acct.Id,
            ARF_AgentService.AgentUserType.CUSTOMER
        );
        System.assertEquals(true, result.success);
        System.assertEquals('escalation', result.actionType);
    }

    @isTest
    static void testUnknownTool() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'nonexistent_tool',
            new Map<String, Object>{},
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(false, result.success);
        System.assert(result.displayMessage.contains('permission'), 'Unknown tool should be denied by permission check');
    }

    // ─── Invoice Resolution Tests ───────────────────────────────────────

    @isTest
    static void testResolveInvoiceId() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Id invoiceId = ARF_AgentService.resolveInvoiceId('INV-001', acct.Id);
        System.assertNotEquals(null, invoiceId, 'Should resolve INV-001');
    }

    @isTest
    static void testResolveInvoiceIdNotFound() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Id invoiceId = ARF_AgentService.resolveInvoiceId('INV-NOPE', acct.Id);
        System.assertEquals(null, invoiceId, 'Should return null for non-existent invoice');
    }

    @isTest
    static void testResolveInvoiceIdNull() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        System.assertEquals(null, ARF_AgentService.resolveInvoiceId(null, acct.Id));
        System.assertEquals(null, ARF_AgentService.resolveInvoiceId('INV-001', null));
    }

    // ─── IsToolAllowed Direct Test ──────────────────────────────────────

    @isTest
    static void testIsToolAllowed() {
        System.assertEquals(true, ARF_AgentService.isToolAllowed('get_account_summary', ARF_AgentService.AgentUserType.COLLECTOR));
        System.assertEquals(false, ARF_AgentService.isToolAllowed('get_account_summary', ARF_AgentService.AgentUserType.CUSTOMER));
        System.assertEquals(true, ARF_AgentService.isToolAllowed('get_portal_summary', ARF_AgentService.AgentUserType.CUSTOMER));
        System.assertEquals(false, ARF_AgentService.isToolAllowed('get_portal_summary', ARF_AgentService.AgentUserType.COLLECTOR));
        System.assertEquals(true, ARF_AgentService.isToolAllowed('escalate_to_human', ARF_AgentService.AgentUserType.COLLECTOR));
        System.assertEquals(true, ARF_AgentService.isToolAllowed('escalate_to_human', ARF_AgentService.AgentUserType.CUSTOMER));
    }

    // ─── Additional Coverage ────────────────────────────────────────────

    @isTest
    static void testGetAccountSummary() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'get_account_summary',
            new Map<String, Object>{ 'account_id' => acct.Id },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
        System.assertEquals('data', result.actionType);
    }

    @isTest
    static void testGetDisputes() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'get_disputes',
            new Map<String, Object>{ 'account_id' => acct.Id },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
    }

    @isTest
    static void testGetPromises() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'get_promises',
            new Map<String, Object>{ 'account_id' => acct.Id },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
    }

    @isTest
    static void testGetCommunications() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'get_communications',
            new Map<String, Object>{ 'account_id' => acct.Id },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
    }

    @isTest
    static void testGetNotes() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'get_notes',
            new Map<String, Object>{ 'account_id' => acct.Id },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
    }

    @isTest
    static void testGetTabCounts() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'get_tab_counts',
            new Map<String, Object>{ 'account_id' => acct.Id },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
    }

    @isTest
    static void testGetInvoicesFiltered() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'get_invoices_filtered',
            new Map<String, Object>{
                'view_filter' => 'open',
                'aging_bucket' => null,
                'search_text' => null
            },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
    }

    @isTest
    static void testGetAgingSummary() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'get_aging_summary',
            new Map<String, Object>{ 'account_id' => acct.Id },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
    }

    @isTest
    static void testGetPayments() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(
            'get_payments',
            new Map<String, Object>{ 'account_id' => acct.Id },
            acct.Id,
            ARF_AgentService.AgentUserType.COLLECTOR
        );
        System.assertEquals(true, result.success);
    }
}
