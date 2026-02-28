@isTest
private class ARF_Account360ControllerTest {

    @TestSetup
    static void setupTestData() {
        Account testAccount = new Account(
            Name = 'Test Account 360',
            ARF_Total_AR__c = 50000,
            ARF_Past_Due__c = 15000,
            ARF_In_Dispute__c = 5000,
            ARF_Promised_Amount__c = 10000,
            ARF_Credit_Limit__c = 100000,
            ARF_Risk_Score__c = 65,
            ARF_Available_Credit__c = 50000,
            ARF_DSO__c = 45,
            ARF_Open_Invoice_Count__c = 10,
            ARF_Overdue_Invoice_Count__c = 3,
            ARF_Open_Dispute_Count__c = 2,
            ARF_Last_Contact_Date__c = Date.today().addDays(-5),
            ARF_Last_Payment_Date__c = Date.today().addDays(-10),
            ARF_Avg_Days_To_Pay__c = 38
        );
        insert testAccount;

        Contact testContact = new Contact(
            FirstName = 'AR',
            LastName = 'Contact',
            AccountId = testAccount.Id,
            Email = 'ar@test.com',
            Phone = '555-0100',
            ARF_AR_Role__c = 'AP Manager',
            ARF_Primary_AR_Contact__c = true,
            ARF_Preferred_Channel__c = 'Email',
            ARF_SMS_Opt_In__c = true,
            ARF_Phone_Direct__c = '555-1234'
        );
        insert testContact;

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = testAccount.Id,
            Document_Number__c = 'INV-001',
            Amount__c = 10000,
            Balance__c = 10000,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-30),
            Due_Date__c = Date.today().addDays(-5)
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = testAccount.Id,
            Document_Number__c = 'INV-002',
            Amount__c = 20000,
            Balance__c = 5000,
            Status__c = 'Partially Paid',
            Invoice_Date__c = Date.today().addDays(-60),
            Due_Date__c = Date.today().addDays(10)
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = testAccount.Id,
            Document_Number__c = 'INV-003',
            Amount__c = 5000,
            Balance__c = 5000,
            Status__c = 'In Dispute',
            Invoice_Date__c = Date.today().addDays(-20),
            Due_Date__c = Date.today().addDays(-2),
            Has_Dispute__c = true
        ));
        insert invoices;

        List<ARF_Payment__c> payments = new List<ARF_Payment__c>();
        payments.add(new ARF_Payment__c(
            Account__c = testAccount.Id,
            Amount__c = 15000,
            Payment_Date__c = Date.today().addDays(-10),
            Method__c = 'ACH',
            Status__c = 'Applied',
            Applied_Amount__c = 15000,
            Unapplied_Amount__c = 0
        ));
        payments.add(new ARF_Payment__c(
            Account__c = testAccount.Id,
            Amount__c = 8000,
            Payment_Date__c = Date.today().addDays(-3),
            Method__c = 'Check',
            Status__c = 'Applied',
            Applied_Amount__c = 5000,
            Unapplied_Amount__c = 3000,
            Has_Short_Pay__c = true
        ));
        insert payments;

        List<ARF_Dispute__c> disputes = new List<ARF_Dispute__c>();
        disputes.add(new ARF_Dispute__c(
            Account__c = testAccount.Id,
            Invoice__c = invoices[2].Id,
            Dispute_Amount__c = 5000,
            Status__c = 'New',
            Category__c = 'Pricing',
            Priority__c = 'High',
            SLA_Date__c = Date.today().addDays(5)
        ));
        disputes.add(new ARF_Dispute__c(
            Account__c = testAccount.Id,
            Invoice__c = invoices[0].Id,
            Dispute_Amount__c = 2000,
            Status__c = 'Under Investigation',
            Category__c = 'Shortage',
            Priority__c = 'Medium'
        ));
        insert disputes;

        ARF_Deduction__c deduction = new ARF_Deduction__c(
            Account__c = testAccount.Id,
            Invoice__c = invoices[0].Id,
            Payment__c = payments[1].Id,
            Amount__c = 3000,
            Category__c = 'Promotion',
            Type__c = 'Trade',
            Status__c = 'New',
            Validity_Score__c = 75
        );
        insert deduction;

        List<ARF_Communication__c> comms = new List<ARF_Communication__c>();
        comms.add(new ARF_Communication__c(
            Account__c = testAccount.Id,
            Channel__c = 'Email',
            Subject__c = 'Payment Reminder',
            Body__c = 'Please remit payment',
            Direction__c = 'Outbound',
            Contact__c = testContact.Id,
            Sent_Date__c = Datetime.now().addDays(-2),
            Status__c = 'Sent'
        ));
        comms.add(new ARF_Communication__c(
            Account__c = testAccount.Id,
            Channel__c = 'Phone',
            Subject__c = 'Collection Call',
            Body__c = 'Discussed payment plan',
            Direction__c = 'Outbound',
            Contact__c = testContact.Id,
            Sent_Date__c = Datetime.now().addDays(-1),
            Status__c = 'Sent',
            Call_Duration_Seconds__c = 300
        ));
        insert comms;

        List<ARF_Note__c> notes = new List<ARF_Note__c>();
        notes.add(new ARF_Note__c(
            Account__c = testAccount.Id,
            Title__c = 'VIP Account',
            Body__c = 'Handle with care',
            Type__c = 'General',
            Is_Pinned__c = true
        ));
        notes.add(new ARF_Note__c(
            Account__c = testAccount.Id,
            Title__c = 'Follow up needed',
            Body__c = 'Call back next week',
            Type__c = 'Follow Up',
            Is_Pinned__c = false
        ));
        insert notes;

        ARF_Promise_To_Pay__c ptp = new ARF_Promise_To_Pay__c(
            Account__c = testAccount.Id,
            Amount__c = 10000,
            Promise_Date__c = Date.today().addDays(7),
            Status__c = 'Open'
        );
        insert ptp;

        ARF_Collection_Strategy__c strategy = new ARF_Collection_Strategy__c(
            Strategy_Name__c = 'Standard 30-60-90',
            Strategy_Type__c = 'Standard',
            Active__c = true,
            Total_Steps__c = 5
        );
        insert strategy;

        ARF_Strategy_Execution__c exec = new ARF_Strategy_Execution__c(
            Account__c = testAccount.Id,
            Strategy__c = strategy.Id,
            Status__c = 'Active',
            Current_Step__c = 2,
            Next_Action_Date__c = Date.today().addDays(3)
        );
        insert exec;
    }

    private static Id getTestAccountId() {
        return [SELECT Id FROM Account WHERE Name = 'Test Account 360' LIMIT 1].Id;
    }

    // ===== READ METHOD TESTS =====

    @isTest
    static void testGetAccountSummary() {
        Id acctId = getTestAccountId();
        Test.startTest();
        Account result = ARF_Account360Controller.getAccountSummary(acctId);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Account should be returned');
        System.assertEquals(50000, result.ARF_Total_AR__c, 'Total AR should match');
        System.assertEquals(65, result.ARF_Risk_Score__c, 'Risk score should match');
    }

    @isTest
    static void testGetAccountSummaryNullId() {
        Test.startTest();
        try {
            ARF_Account360Controller.getAccountSummary(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetARContacts() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<Contact> contacts = ARF_Account360Controller.getARContacts(acctId);
        Test.stopTest();
        System.assertEquals(1, contacts.size(), 'Should return 1 contact');
        System.assertEquals(true, contacts[0].ARF_Primary_AR_Contact__c, 'Should be primary');
    }

    @isTest
    static void testGetInvoices() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Invoice__c> invoices = ARF_Account360Controller.getInvoices(acctId);
        Test.stopTest();
        System.assertEquals(3, invoices.size(), 'Should return 3 open invoices');
    }

    @isTest
    static void testGetDisputes() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Dispute__c> disputes = ARF_Account360Controller.getDisputes(acctId);
        Test.stopTest();
        System.assertEquals(2, disputes.size(), 'Should return 2 disputes');
    }

    @isTest
    static void testGetDeductions() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Deduction__c> deductions = ARF_Account360Controller.getDeductions(acctId);
        Test.stopTest();
        System.assertEquals(1, deductions.size(), 'Should return 1 deduction');
    }

    @isTest
    static void testGetCommunications() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Communication__c> comms = ARF_Account360Controller.getCommunications(acctId);
        Test.stopTest();
        System.assertEquals(2, comms.size(), 'Should return 2 communications');
    }

    @isTest
    static void testGetPayments() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Payment__c> payments = ARF_Account360Controller.getPayments(acctId);
        Test.stopTest();
        System.assertEquals(2, payments.size(), 'Should return 2 payments');
    }

    @isTest
    static void testGetNotes() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Note__c> notes = ARF_Account360Controller.getNotes(acctId);
        Test.stopTest();
        System.assertEquals(2, notes.size(), 'Should return 2 notes');
        System.assertEquals(true, notes[0].Is_Pinned__c, 'First note should be pinned');
    }

    @isTest
    static void testGetPromisesToPay() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Promise_To_Pay__c> ptps = ARF_Account360Controller.getPromisesToPay(acctId);
        Test.stopTest();
        System.assertEquals(1, ptps.size(), 'Should return 1 promise');
    }

    @isTest
    static void testGetStrategyExecutions() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Strategy_Execution__c> execs = ARF_Account360Controller.getStrategyExecutions(acctId);
        Test.stopTest();
        System.assertEquals(1, execs.size(), 'Should return 1 execution');
    }

    @isTest
    static void testGetAgingSummary() {
        Id acctId = getTestAccountId();
        Test.startTest();
        Map<String, Decimal> aging = ARF_Account360Controller.getAgingSummary(acctId);
        Test.stopTest();
        System.assertNotEquals(null, aging, 'Aging map should be returned');
        System.assertEquals(5, aging.size(), 'Should have 5 buckets');
        System.assert(aging.containsKey('current'), 'Should have current bucket');
        System.assert(aging.containsKey('90+'), 'Should have 90+ bucket');
    }

    @isTest
    static void testGetAgingSummaryNullId() {
        Test.startTest();
        try {
            ARF_Account360Controller.getAgingSummary(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ===== FILTERED INVOICE TESTS =====

    @isTest
    static void testGetInvoicesFiltered_AllActive() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Invoice__c> result = ARF_Account360Controller.getInvoicesFiltered(acctId, 'all', 'all', '');
        Test.stopTest();
        System.assertEquals(3, result.size(), 'Should return all 3 active invoices');
    }

    @isTest
    static void testGetInvoicesFiltered_PastDue() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Invoice__c> result = ARF_Account360Controller.getInvoicesFiltered(acctId, 'pastDue', 'all', '');
        Test.stopTest();
        // INV-001 (DPD=5) and INV-003 (DPD=2) are overdue
        System.assert(result.size() >= 1, 'Should return overdue invoices');
        for (ARF_Invoice__c inv : result) {
            System.assertEquals(true, inv.Is_Overdue__c, 'All should be overdue');
        }
    }

    @isTest
    static void testGetInvoicesFiltered_InDispute() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Invoice__c> result = ARF_Account360Controller.getInvoicesFiltered(acctId, 'inDispute', 'all', '');
        Test.stopTest();
        System.assertEquals(1, result.size(), 'Should return 1 disputed invoice');
        System.assertEquals(true, result[0].Has_Dispute__c);
    }

    @isTest
    static void testGetInvoicesFiltered_AgingBucket() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Invoice__c> current = ARF_Account360Controller.getInvoicesFiltered(acctId, 'all', 'current', '');
        List<ARF_Invoice__c> bucket130 = ARF_Account360Controller.getInvoicesFiltered(acctId, 'all', '1-30', '');
        Test.stopTest();
        // Just verify queries execute without error
        System.assertNotEquals(null, current);
        System.assertNotEquals(null, bucket130);
    }

    @isTest
    static void testGetInvoicesFiltered_Search() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Invoice__c> result = ARF_Account360Controller.getInvoicesFiltered(acctId, 'all', 'all', 'INV-001');
        Test.stopTest();
        System.assertEquals(1, result.size(), 'Should find INV-001');
        System.assertEquals('INV-001', result[0].Document_Number__c);
    }

    @isTest
    static void testGetInvoicesFiltered_NullAccountId() {
        Test.startTest();
        try {
            ARF_Account360Controller.getInvoicesFiltered(null, 'all', 'all', '');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ===== WRITE METHOD TESTS =====

    @isTest
    static void testCreateCommunication() {
        Id acctId = getTestAccountId();
        Contact con = [SELECT Id FROM Contact WHERE AccountId = :acctId LIMIT 1];
        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = acctId,
            Channel__c = 'Email',
            Subject__c = 'Test Email',
            Body__c = 'Test body',
            Direction__c = 'Outbound',
            Contact__c = con.Id,
            Status__c = 'Draft'
        );
        Test.startTest();
        ARF_Communication__c result = ARF_Account360Controller.createCommunication(comm);
        Test.stopTest();
        System.assertNotEquals(null, result.Id, 'Communication should be created');
    }

    @isTest
    static void testCreateNote() {
        Id acctId = getTestAccountId();
        ARF_Note__c note = new ARF_Note__c(
            Account__c = acctId,
            Title__c = 'New Note',
            Body__c = 'Note body',
            Type__c = 'General'
        );
        Test.startTest();
        ARF_Note__c result = ARF_Account360Controller.createNote(note);
        Test.stopTest();
        System.assertNotEquals(null, result.Id, 'Note should be created');
    }

    @isTest
    static void testCreateDispute() {
        Id acctId = getTestAccountId();
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c WHERE Account__c = :acctId LIMIT 1];
        ARF_Dispute__c dispute = new ARF_Dispute__c(
            Account__c = acctId,
            Invoice__c = inv.Id,
            Dispute_Amount__c = 1000,
            Status__c = 'New',
            Category__c = 'Pricing',
            Priority__c = 'Medium'
        );
        Test.startTest();
        ARF_Dispute__c result = ARF_Account360Controller.createDispute(dispute);
        Test.stopTest();
        System.assertNotEquals(null, result.Id, 'Dispute should be created');
    }

    @isTest
    static void testCreatePromiseToPay() {
        Id acctId = getTestAccountId();
        ARF_Promise_To_Pay__c ptp = new ARF_Promise_To_Pay__c(
            Account__c = acctId,
            Amount__c = 5000,
            Promise_Date__c = Date.today().addDays(14),
            Status__c = 'Open'
        );
        Test.startTest();
        ARF_Promise_To_Pay__c result = ARF_Account360Controller.createPromiseToPay(ptp);
        Test.stopTest();
        System.assertNotEquals(null, result.Id, 'Promise should be created');
    }

    // ===== TAB COUNTS =====

    @isTest
    static void testGetTabCounts() {
        Id acctId = getTestAccountId();
        Test.startTest();
        Map<String, Integer> counts = ARF_Account360Controller.getTabCounts(acctId);
        Test.stopTest();
        System.assertNotEquals(null, counts, 'Counts map should be returned');
        System.assertEquals(2, counts.get('disputes'), 'Should have 2 disputes');
        System.assertEquals(2, counts.get('emails'), 'Should have 2 communications');
        System.assertEquals(2, counts.get('payments'), 'Should have 2 payments');
        System.assertEquals(1, counts.get('deductions'), 'Should have 1 deduction');
        System.assertEquals(1, counts.get('promises'), 'Should have 1 promise');
        System.assertEquals(2, counts.get('notes'), 'Should have 2 notes');
    }

    @isTest
    static void testGetTabCountsNullId() {
        Test.startTest();
        try {
            ARF_Account360Controller.getTabCounts(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ===== REPLY / FORWARD =====

    @isTest
    static void testCreateReplyForward() {
        Id acctId = getTestAccountId();
        Contact con = [SELECT Id FROM Contact WHERE AccountId = :acctId LIMIT 1];
        ARF_Communication__c original = [
            SELECT Id FROM ARF_Communication__c WHERE Account__c = :acctId LIMIT 1
        ];
        Test.startTest();
        ARF_Communication__c reply = ARF_Account360Controller.createReplyForward(
            acctId, original.Id, 'Reply',
            null, 'test@example.com', null, null,
            'Re: Payment Reminder', '<p>Thanks for the reminder</p>', con.Id
        );
        Test.stopTest();
        System.assertNotEquals(null, reply.Id, 'Reply communication should be created');
        System.assertEquals('Re: Payment Reminder', reply.Subject__c);
        System.assertNotEquals(null, reply.Thread_ID__c, 'Thread ID should be set');
    }

    @isTest
    static void testCreateReplyForwardNoOriginal() {
        Id acctId = getTestAccountId();
        Contact con = [SELECT Id FROM Contact WHERE AccountId = :acctId LIMIT 1];
        Test.startTest();
        ARF_Communication__c fwd = ARF_Account360Controller.createReplyForward(
            acctId, null, 'Forward',
            null, 'recipient@example.com', 'cc@example.com', null,
            'Fwd: Payment Reminder', '<p>FYI</p>', con.Id
        );
        Test.stopTest();
        System.assertNotEquals(null, fwd.Id, 'Forward communication should be created');
    }

    @isTest
    static void testCreateReplyForwardNullAccountId() {
        Test.startTest();
        try {
            ARF_Account360Controller.createReplyForward(
                null, null, 'Reply', null, 'test@example.com',
                null, null, 'Test', '<p>Test</p>', null
            );
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ===== DISPUTE BULK STATUS =====

    @isTest
    static void testUpdateDisputeStatuses() {
        Id acctId = getTestAccountId();
        List<ARF_Dispute__c> disputes = [SELECT Id FROM ARF_Dispute__c WHERE Account__c = :acctId];
        List<Id> disputeIds = new List<Id>();
        for (ARF_Dispute__c d : disputes) {
            disputeIds.add(d.Id);
        }
        Test.startTest();
        ARF_Account360Controller.updateDisputeStatuses(disputeIds, 'Under Investigation');
        Test.stopTest();
        List<ARF_Dispute__c> updated = [SELECT Status__c FROM ARF_Dispute__c WHERE Id IN :disputeIds];
        for (ARF_Dispute__c d : updated) {
            System.assertEquals('Under Investigation', d.Status__c, 'Status should be updated');
        }
    }

    @isTest
    static void testUpdateDisputeStatusesClosed() {
        Id acctId = getTestAccountId();
        List<ARF_Dispute__c> disputes = [SELECT Id FROM ARF_Dispute__c WHERE Account__c = :acctId LIMIT 1];
        List<Id> disputeIds = new List<Id>{ disputes[0].Id };
        Test.startTest();
        ARF_Account360Controller.updateDisputeStatuses(disputeIds, 'Closed');
        Test.stopTest();
        ARF_Dispute__c updated = [SELECT Status__c, Resolution_Type__c FROM ARF_Dispute__c WHERE Id = :disputes[0].Id];
        System.assertEquals('Closed', updated.Status__c);
        System.assertEquals('Resolved', updated.Resolution_Type__c, 'Resolution type should default to Resolved');
    }

    @isTest
    static void testUpdateDisputeStatusesEmptyList() {
        Test.startTest();
        try {
            ARF_Account360Controller.updateDisputeStatuses(new List<Id>(), 'Closed');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ===== COMMUNICATIONS WITH EXTENDED FIELDS =====

    @isTest
    static void testGetCommunicationsExtendedFields() {
        Id acctId = getTestAccountId();
        Test.startTest();
        List<ARF_Communication__c> comms = ARF_Account360Controller.getCommunications(acctId);
        Test.stopTest();
        System.assertEquals(2, comms.size(), 'Should return 2 communications');
        // Verify extended fields are queryable (no exception thrown)
        for (ARF_Communication__c c : comms) {
            // These fields may be null but should be accessible
            String htmlBody = c.HTML_Body__c;
            String body = c.Body__c;
            Boolean hasAttachment = c.Has_Attachment__c;
        }
    }
}
