@isTest
private class ARF_AgentControllerTest {

    // ─── Mock HTTP Callouts ─────────────────────────────────────────────

    // Static call counter — persists across mock invocations within the same test
    private static Integer sMockCallCount = 0;
    private static String sFirstResponse;
    private static String sSecondResponse;

    private class MockClaudeSimpleResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"msg_test","type":"message","content":[{"type":"text","text":"The account has 2 open invoices totaling $8,000."}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}');
            return res;
        }
    }

    private class MockClaudeMultiTurn implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            ARF_AgentControllerTest.sMockCallCount++;
            if (ARF_AgentControllerTest.sMockCallCount == 1) {
                res.setBody(ARF_AgentControllerTest.sFirstResponse);
            } else {
                res.setBody(ARF_AgentControllerTest.sSecondResponse);
            }
            return res;
        }
    }

    private class MockClaudeError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }

    private static void setupMultiTurnMock(String first, String second) {
        ARF_AgentControllerTest.sMockCallCount = 0;
        ARF_AgentControllerTest.sFirstResponse = first;
        ARF_AgentControllerTest.sSecondResponse = second;
        Test.setMock(HttpCalloutMock.class, new MockClaudeMultiTurn());
    }

    // ─── Test Setup ─────────────────────────────────────────────────────

    @TestSetup
    static void setupTestData() {
        ARF_AI_Config__c config = ARF_AI_Config__c.getOrgDefaults();
        config.API_Key__c = 'test-key-for-agent-tests';
        upsert config;

        Account acct = new Account(Name = 'Agent Controller Test Account');
        insert acct;

        ARF_Invoice__c inv = new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'INV-AGENT-001',
            Amount__c = 5000,
            Balance__c = 5000,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-30),
            Due_Date__c = Date.today().addDays(-10)
        );
        insert inv;
    }

    // ─── sendMessage Tests ──────────────────────────────────────────────

    @isTest
    static void testSendMessage_SimpleQuery() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockClaudeSimpleResponse());
        Test.startTest();
        ARF_AgentController.AgentResponse response = ARF_AgentController.sendMessage(
            acct.Id,
            'How many open invoices are there?',
            '[]',
            'collector',
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertNotEquals(null, response.message, 'Response message should not be null');
        System.assertNotEquals(null, response.chatSessionId, 'Chat session ID should not be null');
        System.assertEquals(false, response.escalated);
    }

    @isTest
    static void testSendMessage_WithToolCall() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        String first = '{"id":"msg_1","type":"message","content":[{"type":"tool_use","id":"toolu_01","name":"get_disputes","input":{"account_id":"' + acct.Id + '"}}],"model":"claude-sonnet-4-20250514","stop_reason":"tool_use"}';
        String second = '{"id":"msg_2","type":"message","content":[{"type":"text","text":"There are no disputes on this account."}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}';

        setupMultiTurnMock(first, second);
        Test.startTest();
        ARF_AgentController.AgentResponse response = ARF_AgentController.sendMessage(
            acct.Id,
            'Show me disputes',
            '[]',
            'collector',
            'CHAT-TEST-001'
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertNotEquals(null, response.message);
        System.assertEquals('CHAT-TEST-001', response.chatSessionId);
    }

    @isTest
    static void testSendMessage_CustomerType() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockClaudeSimpleResponse());
        Test.startTest();
        ARF_AgentController.AgentResponse response = ARF_AgentController.sendMessage(
            acct.Id,
            'What is my balance?',
            '[]',
            'customer',
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertNotEquals(null, response.chatSessionId);
    }

    @isTest
    static void testSendMessage_WithConversationHistory() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        String history = '[{"role":"user","content":"Hello"},{"role":"assistant","content":"Hi there!"}]';

        Test.setMock(HttpCalloutMock.class, new MockClaudeSimpleResponse());
        Test.startTest();
        ARF_AgentController.AgentResponse response = ARF_AgentController.sendMessage(
            acct.Id,
            'Show me invoices',
            history,
            'collector',
            'CHAT-HIST-001'
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
    }

    @isTest
    static void testSendMessage_APIError() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockClaudeError());
        Test.startTest();
        ARF_AgentController.AgentResponse response = ARF_AgentController.sendMessage(
            acct.Id,
            'Hello',
            '[]',
            'collector',
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.message.contains('error') || response.message.contains('Error') || response.message.contains('encountered'));
    }

    // ─── saveChatTranscript Tests ───────────────────────────────────────

    @isTest
    static void testSaveChatTranscript() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Id commId = ARF_AgentController.saveChatTranscript(
            acct.Id,
            'CHAT-SAVE-001',
            '[12:00] User: Hello\n[12:01] Agent: Hi there!',
            'Completed'
        );
        Test.stopTest();

        System.assertNotEquals(null, commId);
        ARF_Communication__c comm = [SELECT Channel__c, Status__c, Subject__c FROM ARF_Communication__c WHERE Id = :commId];
        System.assertEquals('Chat', comm.Channel__c);
        System.assertEquals('Completed', comm.Status__c);
        System.assert(comm.Subject__c.contains('CHAT-SAVE-001'));
    }

    @isTest
    static void testSaveChatTranscriptDefaultStatus() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Id commId = ARF_AgentController.saveChatTranscript(acct.Id, 'CHAT-002', 'Test transcript', null);
        Test.stopTest();

        ARF_Communication__c comm = [SELECT Status__c FROM ARF_Communication__c WHERE Id = :commId];
        System.assertEquals('Completed', comm.Status__c);
    }

    // ─── escalateToHuman Tests ──────────────────────────────────────────

    @isTest
    static void testEscalateToHuman() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        ARF_AgentController.escalateToHuman(acct.Id, 'CHAT-ESC-001', 'Customer is frustrated', 'Transcript here');
        Test.stopTest();

        // Verify Communication record
        List<ARF_Communication__c> comms = [SELECT Channel__c, Status__c, Subject__c FROM ARF_Communication__c WHERE Account__c = :acct.Id AND Channel__c = 'Chat'];
        System.assertEquals(1, comms.size());
        System.assertEquals('Escalated', comms[0].Status__c);
        System.assert(comms[0].Subject__c.contains('Escalation'));

        // Verify Task
        List<Task> tasks = [SELECT Subject, Priority, ARF_Task_Type__c FROM Task WHERE WhatId = :acct.Id];
        System.assertEquals(1, tasks.size());
        System.assertEquals('High', tasks[0].Priority);
        System.assertEquals('Chat Escalation', tasks[0].ARF_Task_Type__c);
    }

    // ─── Response Wrapper Tests ─────────────────────────────────────────

    @isTest
    static void testAgentResponseWrapper() {
        ARF_AgentController.AgentResponse resp = new ARF_AgentController.AgentResponse();
        System.assertNotEquals(null, resp.actions);
        System.assertEquals(false, resp.escalated);
    }

    @isTest
    static void testActionCardWrapper() {
        ARF_AgentController.ActionCard card = new ARF_AgentController.ActionCard('action', 'Dispute created', '{"id":"001"}');
        System.assertEquals('action', card.cardType);
        System.assertEquals('Dispute created', card.title);
        System.assertEquals('{"id":"001"}', card.dataJson);
    }

    // ─── Additional Coverage Tests ──────────────────────────────────────

    @isTest
    static void testSendMessage_WithActionToolCall() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        String first = '{"id":"msg_1","type":"message","content":[{"type":"tool_use","id":"toolu_02","name":"create_note","input":{"account_id":"' + acct.Id + '","subject":"Test Note","body":"Created by agent"}}],"model":"claude-sonnet-4-20250514","stop_reason":"tool_use"}';
        String second = '{"id":"msg_2","type":"message","content":[{"type":"text","text":"I have created the note for you."}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}';

        setupMultiTurnMock(first, second);
        Test.startTest();
        ARF_AgentController.AgentResponse response = ARF_AgentController.sendMessage(
            acct.Id, 'Create a note', '[]', 'collector', null
        );
        Test.stopTest();

        System.assertNotEquals(null, response.message);
        System.assert(response.actions.size() > 0, 'Should have action cards');
        System.assertEquals('action', response.actions[0].cardType);
    }

    @isTest
    static void testSendMessage_WithDraftEmail() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        String first = '{"id":"msg_1","type":"message","content":[{"type":"tool_use","id":"toolu_03","name":"draft_email","input":{"account_id":"' + acct.Id + '","to_address":"cust@test.com","subject":"Payment Reminder","body":"Please pay"}}],"model":"claude-sonnet-4-20250514","stop_reason":"tool_use"}';
        String second = '{"id":"msg_2","type":"message","content":[{"type":"text","text":"Here is your email draft."}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}';

        setupMultiTurnMock(first, second);
        Test.startTest();
        ARF_AgentController.AgentResponse response = ARF_AgentController.sendMessage(
            acct.Id, 'Draft an email', '[]', 'collector', null
        );
        Test.stopTest();

        System.assertNotEquals(null, response.message);
        System.assert(response.actions.size() > 0, 'Should have draft email card');
        System.assertEquals('draft_email', response.actions[0].cardType);
    }

    @isTest
    static void testSendMessage_WithEscalationTool() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        String first = '{"id":"msg_1","type":"message","content":[{"type":"tool_use","id":"toolu_04","name":"escalate_to_human","input":{"account_id":"' + acct.Id + '","reason":"Customer wants a manager"}}],"model":"claude-sonnet-4-20250514","stop_reason":"tool_use"}';
        String second = '{"id":"msg_2","type":"message","content":[{"type":"text","text":"I have escalated your request."}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}';

        setupMultiTurnMock(first, second);
        Test.startTest();
        ARF_AgentController.AgentResponse response = ARF_AgentController.sendMessage(
            acct.Id, 'I want to speak to a human', '[]', 'collector', 'CHAT-ESC-TOOL'
        );
        Test.stopTest();

        // escalateToHuman does DML, so the 2nd callout hits callout-after-DML
        // but the escalation DML and action cards are set before the 2nd callout attempt
        System.assertNotEquals(null, response);
        System.assertNotEquals(null, response.message);

        // Verify escalation DML completed (Task + Communication created)
        List<Task> tasks = [SELECT Id FROM Task WHERE WhatId = :acct.Id AND ARF_Task_Type__c = 'Chat Escalation'];
        System.assertEquals(1, tasks.size(), 'Escalation task should be created');

        List<ARF_Communication__c> comms = [SELECT Id FROM ARF_Communication__c WHERE Account__c = :acct.Id AND Channel__c = 'Chat' AND Status__c = 'Escalated'];
        System.assertEquals(1, comms.size(), 'Escalation communication should be created');
    }

    @isTest
    static void testSendMessage_WithTextAndToolMixed() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        String first = '{"id":"msg_1","type":"message","content":[{"type":"text","text":"Let me look that up."},{"type":"tool_use","id":"toolu_06","name":"get_disputes","input":{"account_id":"' + acct.Id + '"}}],"model":"claude-sonnet-4-20250514","stop_reason":"tool_use"}';
        String second = '{"id":"msg_2","type":"message","content":[{"type":"text","text":"No disputes found."}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}';

        setupMultiTurnMock(first, second);
        Test.startTest();
        ARF_AgentController.AgentResponse response = ARF_AgentController.sendMessage(
            acct.Id, 'Show disputes', '[]', 'collector', null
        );
        Test.stopTest();

        System.assertNotEquals(null, response.message);
    }

    @isTest
    static void testSendMessage_NullConversationJson() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockClaudeSimpleResponse());
        Test.startTest();
        ARF_AgentController.AgentResponse response = ARF_AgentController.sendMessage(
            acct.Id, 'Hello', null, 'collector', null
        );
        Test.stopTest();

        System.assertNotEquals(null, response.message);
    }

    @isTest
    static void testSendMessage_EmptyConversationJson() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockClaudeSimpleResponse());
        Test.startTest();
        ARF_AgentController.AgentResponse response = ARF_AgentController.sendMessage(
            acct.Id, 'Hello', '', 'collector', null
        );
        Test.stopTest();

        System.assertNotEquals(null, response.message);
    }

    @isTest
    static void testSendMessage_CustomerPermissionDeniedTool() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        // Mock returns get_invoices which is collector-only — customer will get permission denied error tool result
        String first = '{"id":"msg_1","type":"message","content":[{"type":"tool_use","id":"toolu_05","name":"get_invoices","input":{"account_id":"' + acct.Id + '"}}],"model":"claude-sonnet-4-20250514","stop_reason":"tool_use"}';
        String second = '{"id":"msg_2","type":"message","content":[{"type":"text","text":"I could not retrieve the invoices."}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}';

        setupMultiTurnMock(first, second);
        Test.startTest();
        ARF_AgentController.AgentResponse response = ARF_AgentController.sendMessage(
            acct.Id, 'Show invoices', '[]', 'customer', null
        );
        Test.stopTest();

        System.assertNotEquals(null, response.message);
    }

    @isTest
    static void testEscalateToHuman_NullTranscript() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        ARF_AgentController.escalateToHuman(acct.Id, 'CHAT-NULL', 'Test reason', null);
        Test.stopTest();

        ARF_Communication__c comm = [SELECT Body__c FROM ARF_Communication__c WHERE Account__c = :acct.Id AND Channel__c = 'Chat' LIMIT 1];
        System.assert(comm.Body__c.contains('No transcript available'));
    }
}
