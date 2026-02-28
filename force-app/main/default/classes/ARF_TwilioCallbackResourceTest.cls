@isTest
private class ARF_TwilioCallbackResourceTest {

    private class MockClaudeResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"msg_test","type":"message","content":[{"type":"text","text":"' +
                '{\\"intent\\":\\"dispute\\",\\"confidence\\":0.9,' +
                '\\"entities\\":{\\"invoice_numbers\\":[],\\"po_numbers\\":[],\\"amounts\\":[],\\"dates\\":[],' +
                '\\"account_names\\":[],\\"reference_numbers\\":[]},' +
                '\\"suggested_action\\":\\"Review\\",\\"summary\\":\\"Customer dispute\\"}' +
                '"}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}');
            return res;
        }
    }

    @TestSetup
    static void setupTestData() {
        // Twilio config
        ARF_Twilio_Config__c config = ARF_Twilio_Config__c.getOrgDefaults();
        config.Account_SID__c = 'ACtest1234567890';
        config.Auth_Token__c = 'test-auth-token-1234';
        config.Phone_Number__c = '+14155559999';
        upsert config;

        // AI config (needed for AI classifier)
        ARF_AI_Config__c aiConfig = ARF_AI_Config__c.getOrgDefaults();
        aiConfig.API_Key__c = 'test-ai-key';
        upsert aiConfig;

        Account acct = new Account(
            Name = 'Callback Test Account',
            Phone = '4155551234'
        );
        insert acct;

        Contact con = new Contact(
            FirstName = 'Callback', LastName = 'Contact',
            AccountId = acct.Id,
            MobilePhone = '+14155551234'
        );
        insert con;

        // Existing outbound call communication (for status/transcription callbacks)
        ARF_Communication__c callComm = new ARF_Communication__c(
            Account__c = acct.Id,
            Channel__c = 'Phone',
            Direction__c = 'Outbound',
            Subject__c = 'Phone Call',
            Body__c = 'Call initiated',
            Status__c = 'In Progress',
            Sent_Date__c = Datetime.now(),
            Thread_ID__c = 'CA_TEST_CALL_SID'
        );
        insert callComm;
    }

    @isTest
    static void testInboundSms() {
        Test.setMock(HttpCalloutMock.class, new MockClaudeResponse());
        Test.startTest();

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/twilio/sms';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            'From=%2B14155551234&To=%2B14155559999&Body=I+want+to+dispute+invoice+INV-001&SmsSid=SM_TEST_123'
        );

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        ARF_TwilioCallbackResource.handleCallback();
        Test.stopTest();

        // Verify inbound Communication was created
        List<ARF_Communication__c> comms = [
            SELECT Channel__c, Direction__c, Body__c, From_Address__c, Thread_ID__c
            FROM ARF_Communication__c
            WHERE Thread_ID__c = 'SM_TEST_123'
        ];
        System.assertEquals(1, comms.size());
        System.assertEquals('SMS', comms[0].Channel__c);
        System.assertEquals('Inbound', comms[0].Direction__c);
        System.assert(comms[0].Body__c.contains('dispute'));
    }

    @isTest
    static void testCallStatus() {
        Test.startTest();

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/twilio/voice/status';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            'CallSid=CA_TEST_CALL_SID&CallStatus=completed&CallDuration=120'
        );

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        ARF_TwilioCallbackResource.handleCallback();
        Test.stopTest();

        ARF_Communication__c comm = [
            SELECT Status__c, Call_Duration_Seconds__c
            FROM ARF_Communication__c
            WHERE Thread_ID__c = 'CA_TEST_CALL_SID'
        ];
        System.assertEquals('Sent', comm.Status__c);
        System.assertEquals(120, comm.Call_Duration_Seconds__c);
    }

    @isTest
    static void testCallTranscription() {
        Test.setMock(HttpCalloutMock.class, new MockClaudeResponse());
        Test.startTest();

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/twilio/voice/transcription';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            'CallSid=CA_TEST_CALL_SID&TranscriptionText=Customer+wants+to+dispute+the+invoice&TranscriptionStatus=completed'
        );

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        ARF_TwilioCallbackResource.handleCallback();
        Test.stopTest();

        ARF_Communication__c comm = [
            SELECT Body__c FROM ARF_Communication__c
            WHERE Thread_ID__c = 'CA_TEST_CALL_SID'
        ];
        System.assert(comm.Body__c.contains('Call Transcript'));
        System.assert(comm.Body__c.contains('dispute'));
    }

    @isTest
    static void testCallStatusFailed() {
        Test.startTest();

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/twilio/voice/status';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('CallSid=CA_TEST_CALL_SID&CallStatus=no-answer');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        ARF_TwilioCallbackResource.handleCallback();
        Test.stopTest();

        ARF_Communication__c comm = [
            SELECT Status__c FROM ARF_Communication__c
            WHERE Thread_ID__c = 'CA_TEST_CALL_SID'
        ];
        System.assertEquals('Failed', comm.Status__c);
    }

    @isTest
    static void testMatchAccountByPhone() {
        Id accountId = ARF_TwilioCallbackResource.matchAccountByPhone('+14155551234');
        Account acct = [SELECT Id FROM Account WHERE Name = 'Callback Test Account' LIMIT 1];
        System.assertEquals(acct.Id, accountId);
    }

    @isTest
    static void testMatchAccountByPhoneNotFound() {
        Id accountId = ARF_TwilioCallbackResource.matchAccountByPhone('+19999999999');
        System.assertEquals(null, accountId);
    }

    @isTest
    static void testParseFormBody() {
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf('From=%2B14155551234&Body=Hello+World&SmsSid=SM123');

        Map<String, String> params = ARF_TwilioCallbackResource.parseFormBody(req);
        System.assertEquals('+14155551234', params.get('From'));
        System.assertEquals('Hello World', params.get('Body'));
        System.assertEquals('SM123', params.get('SmsSid'));
    }
}
