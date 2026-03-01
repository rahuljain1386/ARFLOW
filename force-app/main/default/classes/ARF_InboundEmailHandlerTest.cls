@isTest
private class ARF_InboundEmailHandlerTest {

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(Name = 'Inbound Test Account', Website = 'https://testcorp.com');
        insert acct;

        Contact con = new Contact(
            FirstName = 'Inbound',
            LastName = 'Tester',
            Email = 'tester@testcorp.com',
            AccountId = acct.Id
        );
        insert con;

        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = acct.Id,
            Channel__c = 'Email',
            Direction__c = 'Outbound',
            Subject__c = 'Payment Reminder',
            Body__c = 'Please remit payment',
            Status__c = 'Sent',
            Sent_Date__c = Datetime.now().addDays(-1),
            Thread_ID__c = 'thread-12345'
        );
        insert comm;

        // Invoice for body scan tests
        ARF_Invoice__c inv = new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'INV-2025-10051',
            PO_Number__c = 'PO-50051',
            Amount__c = 5000,
            Balance__c = 5000,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-30),
            Due_Date__c = Date.today().addDays(-10)
        );
        insert inv;

        // Sender map for sender map tests
        ARF_Email_Sender_Map__c senderMap = new ARF_Email_Sender_Map__c(
            Sender_Email__c = 'known@learnedcorp.com',
            Sender_Domain__c = 'learnedcorp.com',
            Account__c = acct.Id,
            Confidence__c = 91,
            Match_Count__c = 3,
            Last_Match_Date__c = Datetime.now().addDays(-5)
        );
        insert senderMap;
    }

    @isTest
    static void testThreadMatching() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = 'Re: Payment Reminder';
        email.plainTextBody = 'We will pay next week';
        email.fromAddress = 'unknown@unknown.com';
        email.inReplyTo = 'thread-12345';
        email.messageId = 'msg-001';

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'ar-inbox@test.com';

        Test.startTest();
        ARF_InboundEmailHandler handler = new ARF_InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();

        System.assertEquals(true, result.success);
        ARF_Communication__c comm = [
            SELECT Account__c, Direction__c, Thread_ID__c, Match_Method__c, Match_Confidence__c, Needs_Review__c
            FROM ARF_Communication__c WHERE Direction__c = 'Inbound' LIMIT 1
        ];
        System.assertNotEquals(null, comm.Account__c, 'Should match account via thread');
        System.assertEquals('thread-12345', comm.Thread_ID__c);
        System.assertEquals('Thread', comm.Match_Method__c);
        System.assertEquals(100, comm.Match_Confidence__c);
        System.assertEquals(false, comm.Needs_Review__c);
    }

    @isTest
    static void testContactMatching() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = 'Invoice question';
        email.plainTextBody = 'Can you send me a copy of INV-100?';
        email.fromAddress = 'tester@testcorp.com';
        email.messageId = 'msg-002';

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'ar-inbox@test.com';

        Test.startTest();
        ARF_InboundEmailHandler handler = new ARF_InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();

        System.assertEquals(true, result.success);
        ARF_Communication__c comm = [
            SELECT Account__c, Contact__c, Match_Method__c, Match_Confidence__c
            FROM ARF_Communication__c WHERE Direction__c = 'Inbound' LIMIT 1
        ];
        System.assertNotEquals(null, comm.Account__c, 'Should match account via contact');
        System.assertNotEquals(null, comm.Contact__c, 'Should set contact');
        System.assertEquals('Contact', comm.Match_Method__c);
        System.assertEquals(100, comm.Match_Confidence__c);
    }

    @isTest
    static void testSenderMapMatching() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = 'Follow up on payment';
        email.plainTextBody = 'Hi, following up on our earlier conversation';
        email.fromAddress = 'known@learnedcorp.com';
        email.messageId = 'msg-sendermap-001';

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'ar-inbox@test.com';

        Test.startTest();
        ARF_InboundEmailHandler handler = new ARF_InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();

        System.assertEquals(true, result.success);
        ARF_Communication__c comm = [
            SELECT Account__c, Match_Method__c, Match_Confidence__c, Needs_Review__c
            FROM ARF_Communication__c WHERE Direction__c = 'Inbound' LIMIT 1
        ];
        System.assertNotEquals(null, comm.Account__c, 'Should match account via sender map');
        System.assertEquals('Sender Map', comm.Match_Method__c);
        System.assert(comm.Match_Confidence__c >= 90, 'Confidence should be >= 90');
        System.assertEquals(false, comm.Needs_Review__c);

        // Verify sender map was updated (count incremented)
        ARF_Email_Sender_Map__c updatedMap = [
            SELECT Match_Count__c, Confidence__c FROM ARF_Email_Sender_Map__c
            WHERE Sender_Email__c = 'known@learnedcorp.com' LIMIT 1
        ];
        System.assertEquals(4, updatedMap.Match_Count__c, 'Match count should increment from 3 to 4');
    }

    @isTest
    static void testBodyScanMatching() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = 'Question about INV-2025-10051';
        email.plainTextBody = 'I have a question about invoice INV-2025-10051, could you clarify the charges?';
        email.fromAddress = 'newperson@brandnew.com';
        email.messageId = 'msg-bodyscan-001';

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'ar-inbox@test.com';

        Test.startTest();
        ARF_InboundEmailHandler handler = new ARF_InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();

        System.assertEquals(true, result.success);
        ARF_Communication__c comm = [
            SELECT Account__c, Match_Method__c, Match_Confidence__c
            FROM ARF_Communication__c WHERE Direction__c = 'Inbound' LIMIT 1
        ];
        System.assertNotEquals(null, comm.Account__c, 'Should match account via body scan');
        System.assertEquals('Body Scan', comm.Match_Method__c);
        System.assertEquals(85, comm.Match_Confidence__c);
    }

    @isTest
    static void testBodyScanPONumber() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = 'PO-50051 shipment update';
        email.plainTextBody = 'Regarding PO-50051, when will the order ship?';
        email.fromAddress = 'buyer@brandnew.com';
        email.messageId = 'msg-bodyscan-po';

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'ar-inbox@test.com';

        Test.startTest();
        ARF_InboundEmailHandler handler = new ARF_InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();

        System.assertEquals(true, result.success);
        ARF_Communication__c comm = [
            SELECT Account__c, Match_Method__c
            FROM ARF_Communication__c WHERE Direction__c = 'Inbound' LIMIT 1
        ];
        System.assertNotEquals(null, comm.Account__c, 'Should match via PO number in body');
        System.assertEquals('Body Scan', comm.Match_Method__c);
    }

    @isTest
    static void testDomainMatching() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = 'Payment update';
        email.plainTextBody = 'Our payment is on the way';
        email.fromAddress = 'newperson@testcorp.com';
        email.messageId = 'msg-003';

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'ar-inbox@test.com';

        Test.startTest();
        ARF_InboundEmailHandler handler = new ARF_InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();

        System.assertEquals(true, result.success);
        ARF_Communication__c comm = [
            SELECT Account__c, Match_Method__c, Match_Confidence__c
            FROM ARF_Communication__c WHERE Direction__c = 'Inbound' LIMIT 1
        ];
        System.assertNotEquals(null, comm.Account__c, 'Should match account via domain');
        System.assertEquals('Domain', comm.Match_Method__c);
        System.assertEquals(60, comm.Match_Confidence__c);
    }

    @isTest
    static void testUnmatchedEmail() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = 'Random inquiry';
        email.plainTextBody = 'Hello, who are you?';
        email.fromAddress = 'stranger@unknown.org';
        email.messageId = 'msg-004';

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'ar-inbox@test.com';

        Test.startTest();
        ARF_InboundEmailHandler handler = new ARF_InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();

        System.assertEquals(true, result.success);
        ARF_Communication__c comm = [
            SELECT Account__c, Match_Method__c, Match_Confidence__c, Needs_Review__c
            FROM ARF_Communication__c WHERE Direction__c = 'Inbound' LIMIT 1
        ];
        System.assertEquals(null, comm.Account__c, 'Should have null account for unmatched');
        System.assertEquals('Unmatched', comm.Match_Method__c);
        System.assertEquals(0, comm.Match_Confidence__c);
    }

    @isTest
    static void testConfidenceRoutingMedium() {
        // Domain match with multiple accounts triggers medium confidence (40%)
        // Create a second account with same domain
        Account acct2 = new Account(Name = 'Second Corp', Website = 'https://testcorp.com/about');
        insert acct2;

        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = 'Multi domain question';
        email.plainTextBody = 'Hello';
        email.fromAddress = 'someone@testcorp.com';
        email.messageId = 'msg-confidence-med';

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'ar-inbox@test.com';

        Test.startTest();
        ARF_InboundEmailHandler handler = new ARF_InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();

        ARF_Communication__c comm = [
            SELECT Account__c, Match_Method__c, Match_Confidence__c, Needs_Review__c
            FROM ARF_Communication__c WHERE Direction__c = 'Inbound' LIMIT 1
        ];
        // Multiple domain matches = 40% confidence = medium range
        System.assertEquals('Domain', comm.Match_Method__c);
        System.assertEquals(40, comm.Match_Confidence__c);
        System.assertEquals(true, comm.Needs_Review__c, 'Should be flagged for review');
        System.assertNotEquals(null, comm.Account__c, 'Should still link to an account');
    }

    @isTest
    static void testAIAlwaysQueued() {
        // Even unmatched emails should queue AI classifier
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = 'I dispute something';
        email.plainTextBody = 'Please fix this issue with my invoice';
        email.fromAddress = 'nobody@nowhere.xyz';
        email.messageId = 'msg-ai-always';

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'ar-inbox@test.com';

        Test.startTest();
        ARF_InboundEmailHandler handler = new ARF_InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        // Test.stopTest flushes the queueable — AI classifier will run
        Test.stopTest();

        System.assertEquals(true, result.success);
        // Comm was created even without account match
        ARF_Communication__c comm = [
            SELECT Account__c, Match_Method__c
            FROM ARF_Communication__c WHERE Direction__c = 'Inbound' LIMIT 1
        ];
        System.assertEquals(null, comm.Account__c);
        System.assertEquals('Unmatched', comm.Match_Method__c);
    }

    @isTest
    static void testWithAttachments() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = 'Invoice with attachment';
        email.plainTextBody = 'See attached';
        email.fromAddress = 'tester@testcorp.com';
        email.messageId = 'msg-005';

        Messaging.InboundEmail.BinaryAttachment att = new Messaging.InboundEmail.BinaryAttachment();
        att.fileName = 'invoice.pdf';
        att.body = Blob.valueOf('fake pdf content');
        att.mimeTypeSubType = 'application/pdf';
        email.binaryAttachments = new List<Messaging.InboundEmail.BinaryAttachment>{ att };

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'ar-inbox@test.com';

        Test.startTest();
        ARF_InboundEmailHandler handler = new ARF_InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();

        System.assertEquals(true, result.success);
        ARF_Communication__c comm = [
            SELECT Has_Attachment__c FROM ARF_Communication__c WHERE Direction__c = 'Inbound' LIMIT 1
        ];
        System.assertEquals(true, comm.Has_Attachment__c);
    }

    @isTest
    static void testWithCcAddresses() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = 'CC test';
        email.plainTextBody = 'Test with CC';
        email.fromAddress = 'tester@testcorp.com';
        email.messageId = 'msg-006';
        email.ccAddresses = new String[]{ 'boss@testcorp.com', 'team@testcorp.com' };

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'ar-inbox@test.com';

        Test.startTest();
        ARF_InboundEmailHandler handler = new ARF_InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();

        System.assertEquals(true, result.success);
        ARF_Communication__c comm = [
            SELECT CC_Addresses__c FROM ARF_Communication__c WHERE Direction__c = 'Inbound' LIMIT 1
        ];
        System.assert(comm.CC_Addresses__c.contains('boss@testcorp.com'));
    }
}
