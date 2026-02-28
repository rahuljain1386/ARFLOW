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
        List<ARF_Communication__c> comms = [
            SELECT Id, Account__c, Direction__c, Thread_ID__c
            FROM ARF_Communication__c
            WHERE Direction__c = 'Inbound'
        ];
        System.assertEquals(1, comms.size());
        System.assertNotEquals(null, comms[0].Account__c, 'Should match account via thread');
        System.assertEquals('thread-12345', comms[0].Thread_ID__c);
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
        List<ARF_Communication__c> comms = [
            SELECT Id, Account__c, Contact__c, Direction__c
            FROM ARF_Communication__c
            WHERE Direction__c = 'Inbound'
        ];
        System.assertEquals(1, comms.size());
        System.assertNotEquals(null, comms[0].Account__c, 'Should match account via contact');
        System.assertNotEquals(null, comms[0].Contact__c, 'Should set contact');
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
        List<ARF_Communication__c> comms = [
            SELECT Id, Account__c, Direction__c
            FROM ARF_Communication__c
            WHERE Direction__c = 'Inbound'
        ];
        System.assertEquals(1, comms.size());
        System.assertNotEquals(null, comms[0].Account__c, 'Should match account via domain');
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
        List<ARF_Communication__c> comms = [
            SELECT Id, Account__c, Direction__c
            FROM ARF_Communication__c
            WHERE Direction__c = 'Inbound'
        ];
        System.assertEquals(1, comms.size());
        System.assertEquals(null, comms[0].Account__c, 'Should have null account for unmatched');
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
        List<ARF_Communication__c> comms = [
            SELECT Id, Has_Attachment__c
            FROM ARF_Communication__c
            WHERE Direction__c = 'Inbound'
        ];
        System.assertEquals(1, comms.size());
        System.assertEquals(true, comms[0].Has_Attachment__c);
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
            SELECT CC_Addresses__c FROM ARF_Communication__c
            WHERE Direction__c = 'Inbound' LIMIT 1
        ];
        System.assert(comm.CC_Addresses__c.contains('boss@testcorp.com'));
    }
}
