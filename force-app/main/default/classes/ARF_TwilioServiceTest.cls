@isTest
private class ARF_TwilioServiceTest {

    private class MockTwilioSmsSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"sid":"SM1234567890abcdef","status":"queued","to":"+14155551234","from":"+14155559999"}');
            return res;
        }
    }

    private class MockTwilioCallSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"sid":"CA1234567890abcdef","status":"queued","to":"+14155551234","from":"+14155559999"}');
            return res;
        }
    }

    private class MockTwilioError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('{"code":20003,"message":"Authentication Error"}');
            return res;
        }
    }

    @TestSetup
    static void setupTestData() {
        // Configure Twilio
        ARF_Twilio_Config__c config = ARF_Twilio_Config__c.getOrgDefaults();
        config.Account_SID__c = 'ACtest1234567890';
        config.Auth_Token__c = 'test-auth-token-1234';
        config.Phone_Number__c = '+14155559999';
        config.Callback_Base_URL__c = 'https://test.my.salesforce-sites.com';
        upsert config;

        Account acct = new Account(Name = 'Twilio Test Account', Phone = '4155551234');
        insert acct;

        Contact con = new Contact(
            FirstName = 'Test', LastName = 'Contact',
            AccountId = acct.Id,
            Phone = '+14155551234',
            MobilePhone = '+14155551234',
            Email = 'test@twiliotest.com'
        );
        insert con;
    }

    @isTest
    static void testIsConfigured() {
        System.assertEquals(true, ARF_TwilioService.isConfigured());
    }

    @isTest
    static void testSendSms() {
        Test.setMock(HttpCalloutMock.class, new MockTwilioSmsSuccess());
        Test.startTest();
        String sid = ARF_TwilioService.sendSms('+14155551234', 'Test SMS message');
        Test.stopTest();
        System.assertEquals('SM1234567890abcdef', sid);
    }

    @isTest
    static void testSendSmsError() {
        Test.setMock(HttpCalloutMock.class, new MockTwilioError());
        Test.startTest();
        try {
            ARF_TwilioService.sendSms('+14155551234', 'Test');
            System.assert(false, 'Should have thrown exception');
        } catch (ARF_TwilioService.TwilioException e) {
            System.assert(e.getMessage().contains('SMS failed'));
        }
        Test.stopTest();
    }

    @isTest
    static void testInitiateCall() {
        Test.setMock(HttpCalloutMock.class, new MockTwilioCallSuccess());
        Test.startTest();
        String sid = ARF_TwilioService.initiateCall('+14155551234');
        Test.stopTest();
        System.assertEquals('CA1234567890abcdef', sid);
    }

    @isTest
    static void testSendSmsWithRecord() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Twilio Test Account' LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockTwilioSmsSuccess());
        Test.startTest();
        Id commId = ARF_TwilioService.sendSmsWithRecord('+14155551234', 'Hello from AR Flow', acct.Id, con.Id);
        Test.stopTest();

        ARF_Communication__c comm = [
            SELECT Channel__c, Direction__c, Status__c, Thread_ID__c, Body__c
            FROM ARF_Communication__c WHERE Id = :commId
        ];
        System.assertEquals('SMS', comm.Channel__c);
        System.assertEquals('Outbound', comm.Direction__c);
        System.assertEquals('Sent', comm.Status__c);
        System.assertEquals('SM1234567890abcdef', comm.Thread_ID__c);
    }

    @isTest
    static void testInitiateCallWithRecord() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Twilio Test Account' LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockTwilioCallSuccess());
        Test.startTest();
        Id commId = ARF_TwilioService.initiateCallWithRecord('+14155551234', acct.Id, con.Id);
        Test.stopTest();

        ARF_Communication__c comm = [
            SELECT Channel__c, Direction__c, Status__c, Thread_ID__c
            FROM ARF_Communication__c WHERE Id = :commId
        ];
        System.assertEquals('Phone', comm.Channel__c);
        System.assertEquals('Outbound', comm.Direction__c);
        System.assertEquals('In Progress', comm.Status__c);
        System.assertEquals('CA1234567890abcdef', comm.Thread_ID__c);
    }

    @isTest
    static void testNotConfigured() {
        // Clear config
        ARF_Twilio_Config__c config = ARF_Twilio_Config__c.getOrgDefaults();
        config.Account_SID__c = '';
        config.Auth_Token__c = '';
        config.Phone_Number__c = '';
        upsert config;

        System.assertEquals(false, ARF_TwilioService.isConfigured());
    }

    @isTest
    static void testBuildAuthHeader() {
        ARF_Twilio_Config__c config = ARF_Twilio_Config__c.getOrgDefaults();
        String header = ARF_TwilioService.buildAuthHeader(config);
        System.assert(header.startsWith('Basic '));
    }
}
