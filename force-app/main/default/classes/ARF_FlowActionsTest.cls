@isTest
private class ARF_FlowActionsTest {

    @TestSetup
    static void setupData() {
        Account acct = new Account(Name = 'Test Flow Actions Account');
        insert acct;

        Contact con = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john.doe@test.com',
            Phone = '555-1234',
            AccountId = acct.Id,
            ARF_Primary_AR_Contact__c = true
        );
        insert con;

        // Create an invoice for dispute testing
        ARF_Invoice__c inv = new ARF_Invoice__c();
        inv.Account__c = acct.Id;
        inv.Amount__c = 5000;
        inv.Due_Date__c = Date.today().addDays(-30);
        inv.Status__c = 'Open';
        insert inv;
    }

    // =========================================================
    // ARF_FlowActions - Send Dunning Email Tests
    // =========================================================

    @isTest
    static void testSendDunningEmailSuccess() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Flow Actions Account' LIMIT 1];

        ARF_FlowActions.DunningEmailRequest req = new ARF_FlowActions.DunningEmailRequest();
        req.accountId = acct.Id;
        req.subject = 'Payment Reminder';
        req.body = 'Please pay your outstanding invoice.';

        Test.startTest();
        List<ARF_FlowActions.FlowResult> results = ARF_FlowActions.sendDunningEmail(
            new List<ARF_FlowActions.DunningEmailRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should have 1 result');
        System.assertEquals(true, results[0].success, 'Should be successful');
        System.assert(results[0].message.contains('john.doe@test.com'), 'Message should contain email');
        System.assertNotEquals(null, results[0].communicationId, 'Communication ID should be set');

        // Verify communication record was created
        ARF_Communication__c comm = [SELECT Channel__c, Direction__c, Subject__c, Status__c
            FROM ARF_Communication__c WHERE Id = :results[0].communicationId];
        System.assertEquals('Email', comm.Channel__c);
        System.assertEquals('Outbound', comm.Direction__c);
        System.assertEquals('Payment Reminder', comm.Subject__c);
        System.assertEquals('Sent', comm.Status__c);
    }

    @isTest
    static void testSendDunningEmailDefaultSubjectAndBody() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Flow Actions Account' LIMIT 1];

        ARF_FlowActions.DunningEmailRequest req = new ARF_FlowActions.DunningEmailRequest();
        req.accountId = acct.Id;
        // Leave subject and body null to test defaults

        Test.startTest();
        List<ARF_FlowActions.FlowResult> results = ARF_FlowActions.sendDunningEmail(
            new List<ARF_FlowActions.DunningEmailRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Should be successful with defaults');

        ARF_Communication__c comm = [SELECT Subject__c, Body__c FROM ARF_Communication__c WHERE Id = :results[0].communicationId];
        System.assert(comm.Subject__c.contains('Test Flow Actions Account'), 'Default subject should contain account name');
        System.assert(comm.Body__c.contains('John'), 'Default body should contain contact first name');
    }

    @isTest
    static void testSendDunningEmailNoContact() {
        Account acct = new Account(Name = 'No Contact Account');
        insert acct;

        ARF_FlowActions.DunningEmailRequest req = new ARF_FlowActions.DunningEmailRequest();
        req.accountId = acct.Id;

        Test.startTest();
        List<ARF_FlowActions.FlowResult> results = ARF_FlowActions.sendDunningEmail(
            new List<ARF_FlowActions.DunningEmailRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should have 1 result');
        System.assertEquals(false, results[0].success, 'Should fail without contact');
    }

    @isTest
    static void testSendDunningEmailNoEmail() {
        Account acct = new Account(Name = 'No Email Account');
        insert acct;
        Contact con = new Contact(
            FirstName = 'Jane',
            LastName = 'Smith',
            AccountId = acct.Id,
            ARF_Primary_AR_Contact__c = true
            // No email set
        );
        insert con;

        ARF_FlowActions.DunningEmailRequest req = new ARF_FlowActions.DunningEmailRequest();
        req.accountId = acct.Id;

        Test.startTest();
        List<ARF_FlowActions.FlowResult> results = ARF_FlowActions.sendDunningEmail(
            new List<ARF_FlowActions.DunningEmailRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Should fail without email');
        System.assert(results[0].message.contains('No email address'), 'Should mention missing email');
    }

    // =========================================================
    // ARF_FlowActionsTriggerCall Tests
    // =========================================================

    @isTest
    static void testTriggerCallSuccess() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Flow Actions Account' LIMIT 1];

        ARF_FlowActionsTriggerCall.CallRequest req = new ARF_FlowActionsTriggerCall.CallRequest();
        req.accountId = acct.Id;

        Test.startTest();
        List<ARF_FlowActionsTriggerCall.CallResult> results = ARF_FlowActionsTriggerCall.triggerCall(
            new List<ARF_FlowActionsTriggerCall.CallRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should have 1 result');
        System.assertEquals(true, results[0].success, 'Should be successful');
        System.assert(results[0].message.contains('555-1234'), 'Message should contain phone number');
        System.assertNotEquals(null, results[0].communicationId, 'Communication ID should be set');

        // Verify communication record
        ARF_Communication__c comm = [SELECT Channel__c, Direction__c, Status__c, Subject__c
            FROM ARF_Communication__c WHERE Id = :results[0].communicationId];
        System.assertEquals('Phone', comm.Channel__c);
        System.assertEquals('Outbound', comm.Direction__c);
        System.assertEquals('Initiated', comm.Status__c);
        System.assert(comm.Subject__c.contains('John'), 'Subject should contain contact name');
    }

    @isTest
    static void testTriggerCallNoPhone() {
        Account acct = new Account(Name = 'No Phone Account');
        insert acct;
        Contact con = new Contact(
            FirstName = 'No',
            LastName = 'Phone',
            AccountId = acct.Id,
            ARF_Primary_AR_Contact__c = true
            // No phone set
        );
        insert con;

        ARF_FlowActionsTriggerCall.CallRequest req = new ARF_FlowActionsTriggerCall.CallRequest();
        req.accountId = acct.Id;

        Test.startTest();
        List<ARF_FlowActionsTriggerCall.CallResult> results = ARF_FlowActionsTriggerCall.triggerCall(
            new List<ARF_FlowActionsTriggerCall.CallRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Should fail without phone');
        System.assert(results[0].message.contains('No phone number'), 'Should mention missing phone');
    }

    @isTest
    static void testTriggerCallNoContact() {
        Account acct = new Account(Name = 'Empty Account For Call');
        insert acct;

        ARF_FlowActionsTriggerCall.CallRequest req = new ARF_FlowActionsTriggerCall.CallRequest();
        req.accountId = acct.Id;

        Test.startTest();
        List<ARF_FlowActionsTriggerCall.CallResult> results = ARF_FlowActionsTriggerCall.triggerCall(
            new List<ARF_FlowActionsTriggerCall.CallRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Should fail without contact');
    }

    // =========================================================
    // ARF_FlowActionsCreateDispute Tests
    // =========================================================

    @isTest
    static void testCreateDisputeSuccess() {
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c LIMIT 1];

        ARF_FlowActionsCreateDispute.DisputeRequest req = new ARF_FlowActionsCreateDispute.DisputeRequest();
        req.invoiceId = inv.Id;
        req.amount = 1000;
        req.category = 'Billing Error';
        req.description = 'Customer disputes the billed amount due to pricing discrepancy.';

        Test.startTest();
        List<ARF_FlowActionsCreateDispute.DisputeResult> results = ARF_FlowActionsCreateDispute.createDispute(
            new List<ARF_FlowActionsCreateDispute.DisputeRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should have 1 result');
        System.assertEquals(true, results[0].success, 'Should be successful');
        System.assertNotEquals(null, results[0].disputeId, 'Dispute ID should be set');
        System.assertEquals('Dispute created successfully', results[0].message);

        // Verify dispute record
        ARF_Dispute__c dispute = [SELECT Invoice__c, Dispute_Amount__c, Category__c,
            Description__c, Status__c, Priority__c FROM ARF_Dispute__c WHERE Id = :results[0].disputeId];
        System.assertEquals(inv.Id, dispute.Invoice__c);
        System.assertEquals(1000, dispute.Dispute_Amount__c);
        System.assertEquals('Billing Error', dispute.Category__c);
        System.assertEquals('New', dispute.Status__c);
        System.assertEquals('Medium', dispute.Priority__c);
    }

    @isTest
    static void testCreateDisputeDefaultCategory() {
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c LIMIT 1];

        ARF_FlowActionsCreateDispute.DisputeRequest req = new ARF_FlowActionsCreateDispute.DisputeRequest();
        req.invoiceId = inv.Id;
        req.amount = 500;
        // Leave category null to test default

        Test.startTest();
        List<ARF_FlowActionsCreateDispute.DisputeResult> results = ARF_FlowActionsCreateDispute.createDispute(
            new List<ARF_FlowActionsCreateDispute.DisputeRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Should be successful');

        ARF_Dispute__c dispute = [SELECT Category__c FROM ARF_Dispute__c WHERE Id = :results[0].disputeId];
        System.assertEquals('Other', dispute.Category__c, 'Default category should be Other');
    }

    @isTest
    static void testCreateDisputeMultiple() {
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c LIMIT 1];

        List<ARF_FlowActionsCreateDispute.DisputeRequest> requests = new List<ARF_FlowActionsCreateDispute.DisputeRequest>();

        ARF_FlowActionsCreateDispute.DisputeRequest req1 = new ARF_FlowActionsCreateDispute.DisputeRequest();
        req1.invoiceId = inv.Id;
        req1.amount = 200;
        req1.category = 'Quality Issue';
        req1.description = 'Product quality was subpar.';
        requests.add(req1);

        ARF_FlowActionsCreateDispute.DisputeRequest req2 = new ARF_FlowActionsCreateDispute.DisputeRequest();
        req2.invoiceId = inv.Id;
        req2.amount = 300;
        req2.category = 'Duplicate Charge';
        req2.description = 'Invoice was sent twice.';
        requests.add(req2);

        Test.startTest();
        List<ARF_FlowActionsCreateDispute.DisputeResult> results = ARF_FlowActionsCreateDispute.createDispute(requests);
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should have 2 results');
        System.assertEquals(true, results[0].success, 'First should succeed');
        System.assertEquals(true, results[1].success, 'Second should succeed');
    }

    // =========================================================
    // Inner class property coverage
    // =========================================================

    @isTest
    static void testFlowResultProperties() {
        ARF_FlowActions.FlowResult fr = new ARF_FlowActions.FlowResult();
        fr.success = true;
        fr.message = 'Test message';
        fr.communicationId = null;
        System.assertEquals(true, fr.success);
        System.assertEquals('Test message', fr.message);
    }

    @isTest
    static void testCallResultProperties() {
        ARF_FlowActionsTriggerCall.CallResult cr = new ARF_FlowActionsTriggerCall.CallResult();
        cr.success = false;
        cr.message = 'Error';
        cr.communicationId = null;
        System.assertEquals(false, cr.success);
    }

    @isTest
    static void testDisputeResultProperties() {
        ARF_FlowActionsCreateDispute.DisputeResult dr = new ARF_FlowActionsCreateDispute.DisputeResult();
        dr.success = true;
        dr.message = 'Created';
        dr.disputeId = null;
        System.assertEquals(true, dr.success);
    }
}
