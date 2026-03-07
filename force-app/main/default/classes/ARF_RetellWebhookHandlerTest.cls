@IsTest
private class ARF_RetellWebhookHandlerTest {

    @TestSetup
    static void setupTestData() {
        ARF_Retell_Config__c config = ARF_Retell_Config__c.getOrgDefaults();
        config.API_Key__c = 'test-retell-key';
        config.Agent_ID__c = 'agent_test_123';
        config.From_Number__c = '+15005550006';
        config.Webhook_Base_URL__c = 'https://test.salesforce-sites.com';
        upsert config;

        ARF_AI_Config__c aiConfig = ARF_AI_Config__c.getOrgDefaults();
        aiConfig.API_Key__c = 'test-ai-key';
        upsert aiConfig;

        Account acct = new Account(Name = 'Webhook Test Corp', Phone = '+14155551234');
        insert acct;

        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = acct.Id,
            Channel__c = 'Phone',
            Direction__c = 'Outbound',
            Subject__c = 'AI Voice Call',
            Status__c = 'In Progress',
            Sent_Date__c = Datetime.now(),
            Thread_ID__c = 'call_webhook_test_id'
        );
        insert comm;
    }

    @IsTest
    static void testCallEnded_success() {
        Test.setMock(HttpCalloutMock.class, new MockAIResponse());
        Map<String, Object> payload = new Map<String, Object>{
            'call_id' => 'call_webhook_test_id',
            'call_status' => 'ended',
            'transcript' => 'Agent: Hello, this is regarding your overdue balance. Customer: Yes, I will pay by Friday.',
            'start_timestamp' => 1709500000000L,
            'end_timestamp' => 1709500120000L,
            'recording_url' => 'https://storage.retellai.com/recordings/test.wav',
            'disconnection_reason' => 'agent_hangup'
        };

        Test.startTest();
        ARF_RetellWebhookHandler.handleCallEnded(payload);
        Test.stopTest();

        ARF_Communication__c comm = [
            SELECT Status__c, Body__c, Call_Duration_Seconds__c, HTML_Body__c
            FROM ARF_Communication__c WHERE Thread_ID__c = 'call_webhook_test_id'
        ];
        System.assertEquals('Sent', comm.Status__c);
        System.assert(comm.Body__c.contains('Call Transcript'));
        System.assertEquals(120, comm.Call_Duration_Seconds__c);
        System.assert(comm.HTML_Body__c.contains('Listen to Recording'));

        Account acct = [SELECT ARF_Last_Contact_Date__c FROM Account WHERE Name = 'Webhook Test Corp'];
        System.assertEquals(Date.today(), acct.ARF_Last_Contact_Date__c);
    }

    @IsTest
    static void testCallEnded_withTaskCompletion() {
        Test.setMock(HttpCalloutMock.class, new MockAIResponse());
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Task t = new Task(Subject = 'Test Phone Task', WhatId = acct.Id, Status = 'Open');
        insert t;

        Map<String, Object> payload = new Map<String, Object>{
            'call_id' => 'call_webhook_test_id',
            'call_status' => 'ended',
            'transcript' => 'Test transcript',
            'start_timestamp' => 1709500000000L,
            'end_timestamp' => 1709500060000L,
            'metadata' => new Map<String, Object>{ 'taskId' => String.valueOf(t.Id) }
        };

        Test.startTest();
        ARF_RetellWebhookHandler.handleCallEnded(payload);
        Test.stopTest();

        Task updatedTask = [SELECT Status FROM Task WHERE Id = :t.Id];
        System.assertEquals('Completed', updatedTask.Status);
    }

    @IsTest
    static void testCallEnded_failed() {
        Map<String, Object> payload = new Map<String, Object>{
            'call_id' => 'call_webhook_test_id',
            'call_status' => 'error',
            'disconnection_reason' => 'dial_failed',
            'start_timestamp' => 1709500000000L,
            'end_timestamp' => 1709500005000L
        };

        Test.startTest();
        ARF_RetellWebhookHandler.handleCallEnded(payload);
        Test.stopTest();

        ARF_Communication__c comm = [
            SELECT Status__c FROM ARF_Communication__c WHERE Thread_ID__c = 'call_webhook_test_id'
        ];
        System.assertEquals('Failed', comm.Status__c);
    }

    @IsTest
    static void testCallEnded_withCallAnalysis() {
        Test.setMock(HttpCalloutMock.class, new MockAIResponse());
        Map<String, Object> payload = new Map<String, Object>{
            'call_id' => 'call_webhook_test_id',
            'call_status' => 'ended',
            'transcript' => 'Customer promised to pay $3000 by March 15.',
            'start_timestamp' => 1709500000000L,
            'end_timestamp' => 1709500090000L,
            'call_analysis' => new Map<String, Object>{
                'intent' => 'promise_to_pay',
                'summary' => 'Customer agreed to pay $3,000 by March 15, 2026.'
            }
        };

        Test.startTest();
        ARF_RetellWebhookHandler.handleCallEnded(payload);
        Test.stopTest();

        ARF_Communication__c comm = [
            SELECT AI_Intent__c, AI_Drafted__c, Body__c
            FROM ARF_Communication__c WHERE Thread_ID__c = 'call_webhook_test_id'
        ];
        System.assertEquals('Promise to Pay', comm.AI_Intent__c);
        System.assertEquals(true, comm.AI_Drafted__c);
        System.assert(comm.Body__c.contains('Summary:'));
    }

    @IsTest
    static void testCallEnded_noMatchingComm() {
        Map<String, Object> payload = new Map<String, Object>{
            'call_id' => 'call_unknown_id',
            'call_status' => 'ended'
        };

        Test.startTest();
        ARF_RetellWebhookHandler.handleCallEnded(payload);
        Test.stopTest();

        // No exception — just exits silently
        ARF_Communication__c comm = [
            SELECT Status__c FROM ARF_Communication__c WHERE Thread_ID__c = 'call_webhook_test_id'
        ];
        System.assertEquals('In Progress', comm.Status__c); // unchanged
    }

    // Mock for AI classifier callouts
    private class MockAIResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"msg_test","content":[{"type":"text","text":"{\\"intent\\":\\"general\\",\\"confidence\\":0.8}"}]}');
            return res;
        }
    }

    @IsTest
    static void testMapRetellIntent() {
        System.assertEquals('Promise to Pay', ARF_RetellWebhookHandler.mapRetellIntent('promise_to_pay'));
        System.assertEquals('Dispute', ARF_RetellWebhookHandler.mapRetellIntent('dispute_charge'));
        System.assertEquals('Escalation', ARF_RetellWebhookHandler.mapRetellIntent('escalation_request'));
        System.assertEquals('Invoice Request', ARF_RetellWebhookHandler.mapRetellIntent('invoice_copy'));
        System.assertEquals('General', ARF_RetellWebhookHandler.mapRetellIntent('unknown'));
        System.assertEquals('General', ARF_RetellWebhookHandler.mapRetellIntent(null));
    }

    @IsTest
    static void testWebhookEndpoint() {
        Test.setMock(HttpCalloutMock.class, new MockAIResponse());

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/retell/call-ended';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'call_id' => 'call_webhook_test_id',
            'call_status' => 'ended',
            'transcript' => 'Hello test',
            'start_timestamp' => 1709500000000L,
            'end_timestamp' => 1709500030000L
        }));

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_RetellWebhookHandler.handleWebhook();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }
}
