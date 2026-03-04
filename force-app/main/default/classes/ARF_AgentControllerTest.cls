@isTest
private class ARF_AgentControllerTest {

    // ─── Mock HTTP Callouts ─────────────────────────────────────────────

    private class MockClaudeSimpleResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"msg_test","type":"message","content":[{"type":"text","text":"The account has 2 open invoices totaling $8,000."}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}');
            return res;
        }
    }

    private class MockClaudeWithToolCall implements HttpCalloutMock {
        private Integer callCount = 0;
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            callCount++;
            if (callCount == 1) {
                // First call: agent wants to use a tool
                res.setBody('{"id":"msg_1","type":"message","content":[{"type":"tool_use","id":"toolu_01","name":"get_disputes","input":{"account_id":"001000000000001"}}],"model":"claude-sonnet-4-20250514","stop_reason":"tool_use"}');
            } else {
                // Second call: agent responds with final text
                res.setBody('{"id":"msg_2","type":"message","content":[{"type":"text","text":"There are no disputes on this account."}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}');
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

        Test.setMock(HttpCalloutMock.class, new MockClaudeWithToolCall());
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
}
