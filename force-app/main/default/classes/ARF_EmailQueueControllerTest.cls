@isTest
private class ARF_EmailQueueControllerTest {

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(Name = 'Queue Test Account', Website = 'https://queuetest.com');
        insert acct;

        Account acct2 = new Account(Name = 'Second Account', Website = 'https://secondacct.com');
        insert acct2;

        Contact con = new Contact(
            FirstName = 'Queue', LastName = 'Tester',
            Email = 'tester@queuetest.com', AccountId = acct.Id
        );
        insert con;

        // Unmatched inbound email
        ARF_Communication__c unmatchedComm = new ARF_Communication__c(
            Channel__c = 'Email', Direction__c = 'Inbound',
            Subject__c = 'Unknown sender question',
            Body__c = 'Who am I?',
            From_Address__c = 'stranger@unknown.org',
            To_Address__c = 'ar-inbox@test.com',
            Status__c = 'Received',
            Sent_Date__c = Datetime.now(),
            Match_Method__c = 'Unmatched',
            Match_Confidence__c = 0
        );
        insert unmatchedComm;

        // Needs review inbound email
        ARF_Communication__c reviewComm = new ARF_Communication__c(
            Account__c = acct.Id,
            Channel__c = 'Email', Direction__c = 'Inbound',
            Subject__c = 'Maybe from this account?',
            Body__c = 'Domain matched but uncertain',
            From_Address__c = 'maybe@queuetest.com',
            To_Address__c = 'ar-inbox@test.com',
            Status__c = 'Received',
            Sent_Date__c = Datetime.now(),
            Match_Method__c = 'Domain',
            Match_Confidence__c = 40,
            Needs_Review__c = true
        );
        insert reviewComm;

        // Matched inbound email with AI intent
        ARF_Communication__c matchedComm = new ARF_Communication__c(
            Account__c = acct.Id,
            Channel__c = 'Email', Direction__c = 'Inbound',
            Subject__c = 'I dispute INV-001',
            Body__c = 'We are disputing the charges.',
            From_Address__c = 'tester@queuetest.com',
            To_Address__c = 'ar-inbox@test.com',
            Status__c = 'Received',
            Sent_Date__c = Datetime.now(),
            Match_Method__c = 'Contact',
            Match_Confidence__c = 100,
            AI_Intent__c = 'Dispute'
        );
        insert matchedComm;

        // Outbound email (should not appear in queue)
        ARF_Communication__c outboundComm = new ARF_Communication__c(
            Account__c = acct.Id,
            Channel__c = 'Email', Direction__c = 'Outbound',
            Subject__c = 'Payment Reminder',
            Body__c = 'Please pay',
            Status__c = 'Sent',
            Sent_Date__c = Datetime.now()
        );
        insert outboundComm;

        // Sender map
        ARF_Email_Sender_Map__c senderMap = new ARF_Email_Sender_Map__c(
            Sender_Email__c = 'known@queuetest.com',
            Sender_Domain__c = 'queuetest.com',
            Account__c = acct.Id,
            Confidence__c = 92,
            Match_Count__c = 5,
            Last_Match_Date__c = Datetime.now().addDays(-1)
        );
        insert senderMap;
    }

    @isTest
    static void testGetFieldMetadata() {
        List<Map<String, String>> fields = ARF_EmailQueueController.getEmailQueueFieldMetadata();
        System.assert(fields.size() > 0, 'Should return field metadata');

        Set<String> apiNames = new Set<String>();
        for (Map<String, String> f : fields) {
            apiNames.add(f.get('apiName'));
        }
        System.assert(apiNames.contains('Subject__c'), 'Should include Subject');
        System.assert(apiNames.contains('Match_Method__c'), 'Should include Match Method');
        System.assert(apiNames.contains('Account__r.Name'), 'Should include Account relationship');
    }

    @isTest
    static void testGetAllInbound() {
        List<ARF_Communication__c> results = ARF_EmailQueueController.getEmailQueueDynamic(
            null, null, null, null, null, 'all_inbound'
        );
        System.assertEquals(3, results.size(), 'Should return 3 inbound emails (not outbound)');
    }

    @isTest
    static void testGetUnmatched() {
        List<ARF_Communication__c> results = ARF_EmailQueueController.getEmailQueueDynamic(
            null, null, null, null, null, 'unmatched'
        );
        System.assertEquals(1, results.size(), 'Should return 1 unmatched email');
        System.assertEquals(null, results[0].Account__c, 'Unmatched should have null account');
    }

    @isTest
    static void testGetNeedsReview() {
        List<ARF_Communication__c> results = ARF_EmailQueueController.getEmailQueueDynamic(
            null, null, null, null, null, 'needs_review'
        );
        System.assertEquals(1, results.size(), 'Should return 1 needs-review email');
        System.assertEquals(true, results[0].Needs_Review__c);
    }

    @isTest
    static void testGetAIClassified() {
        List<ARF_Communication__c> results = ARF_EmailQueueController.getEmailQueueDynamic(
            null, null, null, null, null, 'ai_classified'
        );
        System.assertEquals(1, results.size(), 'Should return 1 AI-classified email');
        System.assertEquals('Dispute', results[0].AI_Intent__c);
    }

    @isTest
    static void testSearchFilter() {
        List<ARF_Communication__c> results = ARF_EmailQueueController.getEmailQueueDynamic(
            null, null, null, null, 'dispute', 'all_inbound'
        );
        System.assert(results.size() >= 1, 'Should find email with dispute in subject');
    }

    @isTest
    static void testSortByConfidence() {
        List<ARF_Communication__c> results = ARF_EmailQueueController.getEmailQueueDynamic(
            null, null, 'Match_Confidence__c', 'asc', null, 'all_inbound'
        );
        System.assertEquals(3, results.size());
        System.assert(results[0].Match_Confidence__c <= results[2].Match_Confidence__c,
            'Should be sorted by confidence ascending');
    }

    @isTest
    static void testAssignAccountWithSenderMapping() {
        ARF_Communication__c comm = [
            SELECT Id, From_Address__c FROM ARF_Communication__c
            WHERE Match_Method__c = 'Unmatched' LIMIT 1
        ];
        Account acct = [SELECT Id FROM Account WHERE Name = 'Queue Test Account' LIMIT 1];

        Test.startTest();
        ARF_EmailQueueController.assignAccountToCommunication(comm.Id, acct.Id, true);
        Test.stopTest();

        ARF_Communication__c updated = [
            SELECT Account__c, Match_Method__c, Match_Confidence__c, Needs_Review__c
            FROM ARF_Communication__c WHERE Id = :comm.Id
        ];
        System.assertEquals(acct.Id, updated.Account__c, 'Account should be assigned');
        System.assertEquals('Manual', updated.Match_Method__c);
        System.assertEquals(100, updated.Match_Confidence__c);
        System.assertEquals(false, updated.Needs_Review__c);

        // Verify sender map was created
        List<ARF_Email_Sender_Map__c> maps = [
            SELECT Account__c FROM ARF_Email_Sender_Map__c
            WHERE Sender_Email__c = :comm.From_Address__c.toLowerCase()
        ];
        System.assertEquals(1, maps.size(), 'Sender map should be created');
        System.assertEquals(acct.Id, maps[0].Account__c);
    }

    @isTest
    static void testAssignAccountWithoutSenderMapping() {
        ARF_Communication__c comm = [
            SELECT Id FROM ARF_Communication__c WHERE Match_Method__c = 'Unmatched' LIMIT 1
        ];
        Account acct = [SELECT Id FROM Account WHERE Name = 'Queue Test Account' LIMIT 1];

        Test.startTest();
        ARF_EmailQueueController.assignAccountToCommunication(comm.Id, acct.Id, false);
        Test.stopTest();

        ARF_Communication__c updated = [
            SELECT Account__c, Match_Method__c FROM ARF_Communication__c WHERE Id = :comm.Id
        ];
        System.assertEquals(acct.Id, updated.Account__c);
        System.assertEquals('Manual', updated.Match_Method__c);
    }

    @isTest
    static void testBulkAssignAccount() {
        ARF_Communication__c comm1 = [
            SELECT Id FROM ARF_Communication__c WHERE Match_Method__c = 'Unmatched' LIMIT 1
        ];
        ARF_Communication__c comm2 = [
            SELECT Id FROM ARF_Communication__c WHERE Match_Method__c = 'Domain' LIMIT 1
        ];
        Account acct = [SELECT Id FROM Account WHERE Name = 'Second Account' LIMIT 1];

        Test.startTest();
        ARF_EmailQueueController.bulkAssignAccount(
            new List<Id>{ comm1.Id, comm2.Id }, acct.Id, true
        );
        Test.stopTest();

        List<ARF_Communication__c> updated = [
            SELECT Account__c, Match_Method__c FROM ARF_Communication__c
            WHERE Id IN :new List<Id>{ comm1.Id, comm2.Id }
        ];
        for (ARF_Communication__c c : updated) {
            System.assertEquals(acct.Id, c.Account__c);
            System.assertEquals('Manual', c.Match_Method__c);
        }
    }

    @isTest
    static void testMarkAsSpam() {
        ARF_Communication__c comm = [
            SELECT Id FROM ARF_Communication__c WHERE Needs_Review__c = true LIMIT 1
        ];

        Test.startTest();
        ARF_EmailQueueController.markAsSpam(new List<Id>{ comm.Id });
        Test.stopTest();

        ARF_Communication__c updated = [
            SELECT Needs_Review__c, AI_Intent__c FROM ARF_Communication__c WHERE Id = :comm.Id
        ];
        System.assertEquals(false, updated.Needs_Review__c);
        System.assertEquals('Other', updated.AI_Intent__c);
    }

    @isTest
    static void testSearchAccounts() {
        List<Map<String, Object>> results = ARF_EmailQueueController.searchAccounts('Queue Test');
        System.assertEquals(1, results.size(), 'Should find one matching account');
        System.assertEquals('Queue Test Account', results[0].get('Name'));
    }

    @isTest
    static void testSearchAccountsMinLength() {
        List<Map<String, Object>> results = ARF_EmailQueueController.searchAccounts('Q');
        System.assertEquals(0, results.size(), 'Should return empty for single char search');
    }
}
