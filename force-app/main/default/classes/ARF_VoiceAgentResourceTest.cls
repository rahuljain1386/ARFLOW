@isTest
private class ARF_VoiceAgentResourceTest {

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(
            Name = 'Voice Test Corp',
            AccountNumber = 'VT-001',
            Phone = '4155551234'
        );
        insert acct;

        Contact con = new Contact(
            FirstName = 'Jane', LastName = 'Voice',
            AccountId = acct.Id,
            Email = 'jane@voicetest.com',
            MobilePhone = '+14155551234',
            ARF_Primary_AR_Contact__c = true,
            ARF_AR_Role__c = 'AP Contact'
        );
        insert con;

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'INV-V001',
            Amount__c = 5000, Balance__c = 5000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-60),
            Due_Date__c = Date.today().addDays(-30)
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'INV-V002',
            Amount__c = 3000, Balance__c = 3000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-20),
            Due_Date__c = Date.today().addDays(-5)
        ));
        insert invoices;

        ARF_Dispute__c dispute = new ARF_Dispute__c(
            Account__c = acct.Id,
            Invoice__c = invoices[0].Id,
            Category__c = 'Pricing',
            Priority__c = 'High',
            Dispute_Amount__c = 5000,
            Description__c = 'Overcharged',
            Status__c = 'New'
        );
        insert dispute;
    }

    private static Account getTestAccount() {
        return [SELECT Id FROM Account WHERE Name = 'Voice Test Corp' LIMIT 1];
    }

    // ===== GET CONTEXT TESTS =====

    @isTest
    static void testGetContext_ByAccountId() {
        Account acct = getTestAccount();

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/voice/context';
        req.httpMethod = 'GET';
        req.params.put('accountId', acct.Id);

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_VoiceAgentResource.getContext();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertNotEquals(null, result.get('account'));
        System.assertNotEquals(null, result.get('invoices'));
        System.assertNotEquals(null, result.get('callGuidance'));

        Map<String, Object> accountInfo = (Map<String, Object>) result.get('account');
        System.assertEquals('Voice Test Corp', accountInfo.get('name'));

        List<Object> invoices = (List<Object>) result.get('invoices');
        System.assertEquals(2, invoices.size());
    }

    @isTest
    static void testGetContext_ByPhone() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/voice/context';
        req.httpMethod = 'GET';
        req.params.put('phone', '+14155551234');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_VoiceAgentResource.getContext();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Map<String, Object> accountInfo = (Map<String, Object>) result.get('account');
        System.assertEquals('Voice Test Corp', accountInfo.get('name'));
    }

    @isTest
    static void testGetContext_NotFound() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/voice/context';
        req.httpMethod = 'GET';
        req.params.put('phone', '+19999999999');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_VoiceAgentResource.getContext();
        Test.stopTest();

        System.assertEquals(404, res.statusCode);
    }

    // ===== LOG PROMISE =====

    @isTest
    static void testLogPromise() {
        Account acct = getTestAccount();

        Map<String, Object> payload = new Map<String, Object>{
            'accountId' => acct.Id,
            'amount' => 5000,
            'promiseDate' => String.valueOf(Date.today().addDays(7)),
            'notes' => 'Customer said will pay next week',
            'invoiceNumber' => 'INV-V001'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/voice/log-promise';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_VoiceAgentResource.handleAction();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(true, result.get('success'));

        List<ARF_Promise_To_Pay__c> promises = [
            SELECT Amount__c, Notes__c, Invoice__c FROM ARF_Promise_To_Pay__c
            WHERE Account__c = :acct.Id
        ];
        System.assertEquals(1, promises.size());
        System.assertEquals(5000, promises[0].Amount__c);
        System.assertNotEquals(null, promises[0].Invoice__c, 'Should link to invoice');
    }

    // ===== LOG DISPUTE =====

    @isTest
    static void testLogDispute() {
        Account acct = getTestAccount();

        Map<String, Object> payload = new Map<String, Object>{
            'accountId' => acct.Id,
            'category' => 'Quality',
            'description' => 'Customer says goods were damaged',
            'invoiceNumber' => 'INV-V002'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/voice/log-dispute';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_VoiceAgentResource.handleAction();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);

        // Should have 2 disputes now (1 from setup + 1 new)
        List<ARF_Dispute__c> disputes = [
            SELECT Category__c, Description__c FROM ARF_Dispute__c
            WHERE Account__c = :acct.Id
        ];
        System.assertEquals(2, disputes.size());

        // Verify the new dispute exists
        List<ARF_Dispute__c> newDispute = [
            SELECT Category__c FROM ARF_Dispute__c
            WHERE Account__c = :acct.Id AND Category__c = 'Quality'
        ];
        System.assertEquals(1, newDispute.size());

        // Invoice should be flagged
        ARF_Invoice__c inv = [SELECT Has_Dispute__c FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-V002'];
        System.assertEquals(true, inv.Has_Dispute__c);
    }

    // ===== LOG NOTE =====

    @isTest
    static void testLogNote() {
        Account acct = getTestAccount();

        Map<String, Object> payload = new Map<String, Object>{
            'accountId' => acct.Id,
            'title' => 'Payment Reference',
            'body' => 'Customer says wire REF-56789 sent last Tuesday for INV-V001'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/voice/log-note';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_VoiceAgentResource.handleAction();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);

        List<ARF_Note__c> notes = [SELECT Title__c, Body__c, Type__c FROM ARF_Note__c WHERE Account__c = :acct.Id];
        System.assertEquals(1, notes.size());
        System.assertEquals('Payment Reference', notes[0].Title__c);
        System.assertEquals('Call Log', notes[0].Type__c);
    }

    // ===== LOG CALL =====

    @isTest
    static void testLogCall() {
        Account acct = getTestAccount();

        Map<String, Object> payload = new Map<String, Object>{
            'accountId' => acct.Id,
            'transcript' => 'Agent: Hi John... Customer: I will pay next week...',
            'summary' => 'Customer promised to pay $5000 by next Friday',
            'outcome' => 'Promise to Pay',
            'durationSeconds' => 180,
            'contactPhone' => '+14155551234'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/voice/log-call';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_VoiceAgentResource.handleAction();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);

        ARF_Communication__c comm = [
            SELECT Channel__c, Direction__c, Body__c, Call_Duration_Seconds__c, AI_Intent__c
            FROM ARF_Communication__c WHERE Account__c = :acct.Id LIMIT 1
        ];
        System.assertEquals('Phone', comm.Channel__c);
        System.assertEquals('Outbound', comm.Direction__c);
        System.assertEquals(180, comm.Call_Duration_Seconds__c);
        System.assertEquals('Promise to Pay', comm.AI_Intent__c);
        System.assert(comm.Body__c.contains('Customer promised'));
    }

    // ===== UNKNOWN ACTION =====

    @isTest
    static void testUnknownAction() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/voice/unknown-action';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{}');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_VoiceAgentResource.handleAction();
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
    }

    // ===== CALL GUIDANCE =====

    @isTest
    static void testBuildCallGuidance() {
        Account acct = getTestAccount();
        Map<String, Object> context = ARF_VoiceAgentResource.buildFullContext(acct.Id);

        String guidance = (String) context.get('callGuidance');
        System.assert(guidance.contains('Voice Test Corp'));
        System.assert(guidance.contains('overdue'));
        System.assert(guidance.contains('dispute'));
    }

    // ===== PHONE MATCHING =====

    @isTest
    static void testMatchAccountByPhone() {
        Id accountId = ARF_VoiceAgentResource.matchAccountByPhone('+14155551234');
        Account acct = getTestAccount();
        System.assertEquals(acct.Id, accountId);
    }

    @isTest
    static void testMatchAccountByPhone_NotFound() {
        Id accountId = ARF_VoiceAgentResource.matchAccountByPhone('+19999999999');
        System.assertEquals(null, accountId);
    }
}
