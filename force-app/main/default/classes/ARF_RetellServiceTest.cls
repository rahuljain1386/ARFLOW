@IsTest
private class ARF_RetellServiceTest {

    @TestSetup
    static void setupTestData() {
        ARF_Retell_Config__c config = ARF_Retell_Config__c.getOrgDefaults();
        config.API_Key__c = 'test-retell-api-key';
        config.Agent_ID__c = 'agent_test_123';
        config.From_Number__c = '+15005550006';
        config.Webhook_Base_URL__c = 'https://test.salesforce-sites.com';
        upsert config;

        Account acct = new Account(
            Name = 'Retell Test Corp',
            Phone = '+14155551234',
            ARF_Past_Due__c = 5000,
            ARF_Total_AR__c = 8500,
            ARF_Overdue_Invoice_Count__c = 3
        );
        insert acct;

        Contact con = new Contact(
            FirstName = 'John',
            LastName = 'TestContact',
            AccountId = acct.Id,
            Phone = '+14155559999'
        );
        insert con;
    }

    @IsTest
    static void testIsConfigured_true() {
        System.assertEquals(true, ARF_RetellService.isConfigured());
    }

    @IsTest
    static void testIsConfigured_false() {
        ARF_Retell_Config__c config = ARF_Retell_Config__c.getOrgDefaults();
        config.API_Key__c = '';
        upsert config;
        System.assertEquals(false, ARF_RetellService.isConfigured());
    }

    @IsTest
    static void testInitiateCall_success() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockRetellSuccess());
        Test.startTest();
        String callId = ARF_RetellService.initiateCall(
            '+14155551234', acct.Id, null, new Map<String, Object>{ 'account_name' => 'Test' }
        );
        Test.stopTest();

        System.assertEquals('call_test_abc123', callId);
    }

    @IsTest
    static void testInitiateCall_error() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockRetellError());
        Test.startTest();
        try {
            ARF_RetellService.initiateCall('+14155551234', acct.Id, null, null);
            System.assert(false, 'Should have thrown exception');
        } catch (ARF_RetellService.RetellException e) {
            System.assert(e.getMessage().contains('401'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testInitiateCallWithRecord_success() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockRetellSuccess());
        Test.startTest();
        Id commId = ARF_RetellService.initiateCallWithRecord(
            '+14155551234', acct.Id, null, null, new Map<String, Object>()
        );
        Test.stopTest();

        ARF_Communication__c comm = [
            SELECT Status__c, Thread_ID__c, Channel__c, Direction__c
            FROM ARF_Communication__c WHERE Id = :commId
        ];
        System.assertEquals('In Progress', comm.Status__c);
        System.assertEquals('call_test_abc123', comm.Thread_ID__c);
        System.assertEquals('Phone', comm.Channel__c);
        System.assertEquals('Outbound', comm.Direction__c);
    }

    @IsTest
    static void testInitiateCallWithRecord_failure() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockRetellError());
        Test.startTest();
        Id commId = ARF_RetellService.initiateCallWithRecord(
            '+14155551234', acct.Id, null, null, null
        );
        Test.stopTest();

        ARF_Communication__c comm = [
            SELECT Status__c, Thread_ID__c FROM ARF_Communication__c WHERE Id = :commId
        ];
        System.assertEquals('Failed', comm.Status__c);
        System.assertEquals(null, comm.Thread_ID__c);
    }

    @IsTest
    static void testBuildDynamicVars() {
        Account acct = [
            SELECT Id, Name, ARF_Past_Due__c, ARF_Total_AR__c, ARF_Overdue_Invoice_Count__c
            FROM Account LIMIT 1
        ];
        Contact con = [SELECT Id, Name FROM Contact LIMIT 1];

        Map<String, Object> vars = ARF_RetellService.buildDynamicVars(acct, con);

        System.assertEquals('Retell Test Corp', vars.get('account_name'));
        System.assertEquals('John TestContact', vars.get('contact_name'));
        System.assert(String.valueOf(vars.get('total_past_due')).contains('5000'));
        System.assertEquals('3', vars.get('overdue_count'));
    }

    @IsTest
    static void testBuildDynamicVars_noContact() {
        Account acct = [
            SELECT Id, Name, ARF_Past_Due__c, ARF_Total_AR__c, ARF_Overdue_Invoice_Count__c
            FROM Account LIMIT 1
        ];

        Map<String, Object> vars = ARF_RetellService.buildDynamicVars(acct, null);
        System.assertEquals('Valued Customer', vars.get('contact_name'));
    }

    @IsTest
    static void testInitiateCallQueueable() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockRetellSuccess());
        Test.startTest();
        System.enqueueJob(new ARF_RetellService.InitiateCallQueueable(
            acct.Id, con.Id, null, '+14155551234'
        ));
        Test.stopTest();

        List<ARF_Communication__c> comms = [
            SELECT Status__c, Thread_ID__c FROM ARF_Communication__c
            WHERE Account__c = :acct.Id AND Channel__c = 'Phone'
        ];
        System.assertEquals(1, comms.size());
        System.assertEquals('In Progress', comms[0].Status__c);
    }

    // ===== MOCKS =====

    private class MockRetellSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"call_id":"call_test_abc123","agent_id":"agent_test","from_number":"+15005550006"}');
            return res;
        }
    }

    private class MockRetellError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"Unauthorized"}');
            return res;
        }
    }
}
