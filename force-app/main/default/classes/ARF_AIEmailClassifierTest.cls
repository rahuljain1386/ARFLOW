@isTest
private class ARF_AIEmailClassifierTest {

    private class MockClaudeSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"msg_test","type":"message","content":[{"type":"text","text":"' +
                '{\\"intent\\":\\"dispute\\",\\"confidence\\":0.92,' +
                '\\"entities\\":{\\"invoice_numbers\\":[\\"INV-001\\"],' +
                '\\"po_numbers\\":[],\\"amounts\\":[5000],\\"dates\\":[],' +
                '\\"account_names\\":[],\\"reference_numbers\\":[]},' +
                '\\"suggested_action\\":\\"Create dispute record\\",' +
                '\\"summary\\":\\"Customer disputes invoice INV-001 amount\\"}' +
                '"}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}');
            return res;
        }
    }

    private class MockClaudePromise implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"msg_test","type":"message","content":[{"type":"text","text":"' +
                '{\\"intent\\":\\"promise_to_pay\\",\\"confidence\\":0.88,' +
                '\\"entities\\":{\\"invoice_numbers\\":[],' +
                '\\"po_numbers\\":[],\\"amounts\\":[10000],\\"dates\\":[\\"2026-03-15\\"],' +
                '\\"account_names\\":[],\\"reference_numbers\\":[]},' +
                '\\"suggested_action\\":\\"Create promise to pay\\",' +
                '\\"summary\\":\\"Customer promises to pay $10,000 by March 15\\"}' +
                '"}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}');
            return res;
        }
    }

    private class MockClaudeEscalation implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"msg_test","type":"message","content":[{"type":"text","text":"' +
                '{\\"intent\\":\\"escalation\\",\\"confidence\\":0.95,' +
                '\\"entities\\":{\\"invoice_numbers\\":[],' +
                '\\"po_numbers\\":[],\\"amounts\\":[],\\"dates\\":[],' +
                '\\"account_names\\":[],\\"reference_numbers\\":[]},' +
                '\\"suggested_action\\":\\"Escalate to supervisor\\",' +
                '\\"summary\\":\\"Customer demands to speak with manager\\"}' +
                '"}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}');
            return res;
        }
    }

    private class MockClaudeWithEntities implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"msg_test","type":"message","content":[{"type":"text","text":"' +
                '{\\"intent\\":\\"payment_inquiry\\",\\"confidence\\":0.85,' +
                '\\"entities\\":{\\"invoice_numbers\\":[\\"INV-ENTITY-001\\"],' +
                '\\"po_numbers\\":[\\"PO-ENTITY-001\\"],\\"amounts\\":[1500],\\"dates\\":[],' +
                '\\"account_names\\":[\\"AI Suggest Account\\"],\\"reference_numbers\\":[\\"REF-123\\"]},' +
                '\\"suggested_action\\":\\"Look up invoice and respond\\",' +
                '\\"summary\\":\\"Customer asking about invoice INV-ENTITY-001\\"}' +
                '"}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn"}');
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

    @TestSetup
    static void setupTestData() {
        // Set up API key so classifier doesn't skip callout
        ARF_AI_Config__c config = ARF_AI_Config__c.getOrgDefaults();
        config.API_Key__c = 'test-key-for-unit-tests';
        upsert config;

        Account acct = new Account(Name = 'AI Test Account');
        insert acct;

        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = acct.Id,
            Channel__c = 'Email',
            Direction__c = 'Inbound',
            Subject__c = 'I dispute invoice INV-001',
            Body__c = 'We are disputing the charges on INV-001 for $5,000. The goods were damaged.',
            From_Address__c = 'customer@test.com',
            Status__c = 'Received',
            Sent_Date__c = Datetime.now(),
            Match_Method__c = 'Contact',
            Match_Confidence__c = 100
        );
        insert comm;

        // Account for entity-based suggestion
        Account suggestAcct = new Account(Name = 'AI Suggest Account');
        insert suggestAcct;

        // Invoice for entity matching
        ARF_Invoice__c inv = new ARF_Invoice__c(
            Account__c = suggestAcct.Id,
            Document_Number__c = 'INV-ENTITY-001',
            PO_Number__c = 'PO-ENTITY-001',
            Amount__c = 1500,
            Balance__c = 1500,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-15),
            Due_Date__c = Date.today().addDays(-5)
        );
        insert inv;

        // Unmatched communication for entity suggestion test
        ARF_Communication__c unmatchedComm = new ARF_Communication__c(
            Channel__c = 'Email',
            Direction__c = 'Inbound',
            Subject__c = 'Question about INV-ENTITY-001',
            Body__c = 'Can you tell me the status of INV-ENTITY-001?',
            From_Address__c = 'stranger@nowhere.com',
            Status__c = 'Received',
            Sent_Date__c = Datetime.now(),
            Match_Method__c = 'Unmatched',
            Match_Confidence__c = 0
        );
        insert unmatchedComm;
    }

    @isTest
    static void testDisputeClassification() {
        ARF_Communication__c comm = [SELECT Id FROM ARF_Communication__c WHERE Account__c != null LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockClaudeSuccess());
        Test.startTest();
        System.enqueueJob(new ARF_AIEmailClassifier(comm.Id));
        Test.stopTest();

        ARF_Communication__c updated = [
            SELECT AI_Intent__c, AI_Drafted__c FROM ARF_Communication__c WHERE Id = :comm.Id
        ];
        System.assertEquals('Dispute', updated.AI_Intent__c);
        System.assertEquals(true, updated.AI_Drafted__c);

        // Verify dispute was auto-created
        List<ARF_Dispute__c> disputes = [SELECT Id FROM ARF_Dispute__c];
        System.assertEquals(1, disputes.size());
    }

    @isTest
    static void testPromiseClassification() {
        ARF_Communication__c comm = [SELECT Id FROM ARF_Communication__c WHERE Account__c != null LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockClaudePromise());
        Test.startTest();
        System.enqueueJob(new ARF_AIEmailClassifier(comm.Id));
        Test.stopTest();

        ARF_Communication__c updated = [
            SELECT AI_Intent__c FROM ARF_Communication__c WHERE Id = :comm.Id
        ];
        System.assertEquals('Promise to Pay', updated.AI_Intent__c);

        // Verify promise was auto-created
        List<ARF_Promise_To_Pay__c> promises = [SELECT Id, Amount__c FROM ARF_Promise_To_Pay__c];
        System.assertEquals(1, promises.size());
        System.assertEquals(10000, promises[0].Amount__c);
    }

    @isTest
    static void testEscalationClassification() {
        ARF_Communication__c comm = [SELECT Id FROM ARF_Communication__c WHERE Account__c != null LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockClaudeEscalation());
        Test.startTest();
        System.enqueueJob(new ARF_AIEmailClassifier(comm.Id));
        Test.stopTest();

        ARF_Communication__c updated = [
            SELECT AI_Intent__c FROM ARF_Communication__c WHERE Id = :comm.Id
        ];
        System.assertEquals('Escalation', updated.AI_Intent__c);

        // Verify escalation task was created
        List<Task> tasks = [SELECT Id, Subject, Priority FROM Task WHERE Subject LIKE 'Escalation:%'];
        System.assertEquals(1, tasks.size());
        System.assertEquals('High', tasks[0].Priority);
    }

    @isTest
    static void testAPIError() {
        ARF_Communication__c comm = [SELECT Id FROM ARF_Communication__c WHERE Account__c != null LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockClaudeError());
        Test.startTest();
        System.enqueueJob(new ARF_AIEmailClassifier(comm.Id));
        Test.stopTest();

        // Should not update intent on error
        ARF_Communication__c updated = [
            SELECT AI_Intent__c FROM ARF_Communication__c WHERE Id = :comm.Id
        ];
        System.assertEquals(null, updated.AI_Intent__c);
    }

    @isTest
    static void testNormalizeIntent() {
        ARF_AIEmailClassifier classifier = new ARF_AIEmailClassifier(null);
        System.assertEquals('Dispute', classifier.normalizeIntent('dispute'));
        System.assertEquals('Promise to Pay', classifier.normalizeIntent('promise_to_pay'));
        System.assertEquals('Payment Confirmation', classifier.normalizeIntent('payment_confirmation'));
        System.assertEquals('Payment Inquiry', classifier.normalizeIntent('payment_inquiry'));
        System.assertEquals('Invoice Request', classifier.normalizeIntent('invoice_request'));
        System.assertEquals('Escalation', classifier.normalizeIntent('escalation'));
        System.assertEquals('General', classifier.normalizeIntent('general'));
        System.assertEquals('General', classifier.normalizeIntent(null));
    }

    @isTest
    static void testBuildPrompt() {
        ARF_Communication__c comm = [SELECT Id, Subject__c, Body__c, From_Address__c FROM ARF_Communication__c WHERE Account__c != null LIMIT 1];
        ARF_AIEmailClassifier classifier = new ARF_AIEmailClassifier(comm.Id);
        String prompt = classifier.buildPrompt(comm);
        System.assert(prompt.contains('email classifier'));
        System.assert(prompt.contains(comm.Subject__c));
        // Verify new entity types in prompt
        System.assert(prompt.contains('po_numbers'), 'Prompt should request PO numbers');
        System.assert(prompt.contains('account_names'), 'Prompt should request account names');
        System.assert(prompt.contains('reference_numbers'), 'Prompt should request reference numbers');
    }

    @isTest
    static void testSuggestAccountFromEntitiesViaInvoice() {
        ARF_Communication__c comm = [
            SELECT Id, Account__c, Match_Method__c, Match_Confidence__c, Needs_Review__c
            FROM ARF_Communication__c WHERE Account__c = null LIMIT 1
        ];

        Test.setMock(HttpCalloutMock.class, new MockClaudeWithEntities());
        Test.startTest();
        System.enqueueJob(new ARF_AIEmailClassifier(comm.Id));
        Test.stopTest();

        ARF_Communication__c updated = [
            SELECT Account__c, Match_Method__c, Match_Confidence__c, Needs_Review__c, AI_Intent__c
            FROM ARF_Communication__c WHERE Id = :comm.Id
        ];
        System.assertNotEquals(null, updated.Account__c, 'AI should suggest account from entities');
        System.assertEquals('AI Suggestion', updated.Match_Method__c);
        System.assertEquals(70, updated.Match_Confidence__c);
        System.assertEquals(true, updated.Needs_Review__c);
        System.assertEquals('Payment Inquiry', updated.AI_Intent__c);
    }

    @isTest
    static void testAutoAcknowledgmentSent() {
        ARF_Communication__c comm = [SELECT Id FROM ARF_Communication__c WHERE Account__c != null LIMIT 1];

        // Insert an OrgWideEmailAddress is not possible in tests, so we verify
        // the outbound Communication record creation by checking it after execution.
        // The Messaging.sendEmail will be skipped if no OWA exists, but we can
        // test the isActionableIntent and buildAckBody methods directly.

        Test.setMock(HttpCalloutMock.class, new MockClaudeSuccess());
        Test.startTest();
        System.enqueueJob(new ARF_AIEmailClassifier(comm.Id));
        Test.stopTest();

        // Verify intent was classified as Dispute
        ARF_Communication__c updated = [
            SELECT AI_Intent__c FROM ARF_Communication__c WHERE Id = :comm.Id
        ];
        System.assertEquals('Dispute', updated.AI_Intent__c);

        // Verify isActionableIntent returns correct values
        ARF_AIEmailClassifier classifier = new ARF_AIEmailClassifier(null);
        System.assertEquals(true, classifier.isActionableIntent('Dispute'));
        System.assertEquals(true, classifier.isActionableIntent('Promise to Pay'));
        System.assertEquals(true, classifier.isActionableIntent('Escalation'));
        System.assertEquals(true, classifier.isActionableIntent('Invoice Request'));
        System.assertEquals(false, classifier.isActionableIntent('General'));
        System.assertEquals(false, classifier.isActionableIntent('Payment Inquiry'));
        System.assertEquals(false, classifier.isActionableIntent(null));

        // Verify buildAckBody produces correct content per intent
        String disputeBody = classifier.buildAckBody('Dispute', 'Test summary', 'Test Account');
        System.assert(disputeBody.contains('dispute'), 'Dispute body should mention dispute');
        System.assert(disputeBody.contains('logged for review'), 'Dispute body should mention logged for review');

        String promiseBody = classifier.buildAckBody('Promise to Pay', 'Test', 'Test Account');
        System.assert(promiseBody.contains('payment commitment'), 'PTP body should mention payment commitment');

        String escalationBody = classifier.buildAckBody('Escalation', 'Test', 'Test Account');
        System.assert(escalationBody.contains('escalated'), 'Escalation body should mention escalated');

        String invoiceBody = classifier.buildAckBody('Invoice Request', 'Test', 'Test Account');
        System.assert(invoiceBody.contains('invoice inquiry'), 'Invoice body should mention invoice inquiry');
    }

    @isTest
    static void testSuggestAccountFromEntitiesViaAccountName() {
        // Remove the invoice so it falls through to account name matching
        delete [SELECT Id FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-ENTITY-001'];

        ARF_Communication__c comm = [
            SELECT Id FROM ARF_Communication__c WHERE Account__c = null LIMIT 1
        ];

        Test.setMock(HttpCalloutMock.class, new MockClaudeWithEntities());
        Test.startTest();
        System.enqueueJob(new ARF_AIEmailClassifier(comm.Id));
        Test.stopTest();

        ARF_Communication__c updated = [
            SELECT Account__c, Match_Method__c FROM ARF_Communication__c WHERE Id = :comm.Id
        ];
        System.assertNotEquals(null, updated.Account__c, 'AI should suggest via account name');
        System.assertEquals('AI Suggestion', updated.Match_Method__c);
    }
}
