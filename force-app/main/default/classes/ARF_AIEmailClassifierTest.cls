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
                '\\"amounts\\":[5000],\\"dates\\":[]},' +
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
                '\\"amounts\\":[10000],\\"dates\\":[\\"2026-03-15\\"]},' +
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
                '\\"amounts\\":[],\\"dates\\":[]},' +
                '\\"suggested_action\\":\\"Escalate to supervisor\\",' +
                '\\"summary\\":\\"Customer demands to speak with manager\\"}' +
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
            Sent_Date__c = Datetime.now()
        );
        insert comm;
    }

    @isTest
    static void testDisputeClassification() {
        ARF_Communication__c comm = [SELECT Id FROM ARF_Communication__c LIMIT 1];

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
        ARF_Communication__c comm = [SELECT Id FROM ARF_Communication__c LIMIT 1];

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
        ARF_Communication__c comm = [SELECT Id FROM ARF_Communication__c LIMIT 1];

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
        ARF_Communication__c comm = [SELECT Id FROM ARF_Communication__c LIMIT 1];

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
        ARF_Communication__c comm = [SELECT Id, Subject__c, Body__c, From_Address__c FROM ARF_Communication__c LIMIT 1];
        ARF_AIEmailClassifier classifier = new ARF_AIEmailClassifier(comm.Id);
        String prompt = classifier.buildPrompt(comm);
        System.assert(prompt.contains('email classifier'));
        System.assert(prompt.contains(comm.Subject__c));
    }
}
