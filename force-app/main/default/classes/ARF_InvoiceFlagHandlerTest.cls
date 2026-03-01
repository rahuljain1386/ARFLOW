@isTest
private class ARF_InvoiceFlagHandlerTest {

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(Name = 'Flag Test Account');
        insert acct;

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'INV-FLAG-001',
            Amount__c = 1000, Balance__c = 1000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-30),
            Due_Date__c = Date.today().addDays(-10)
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'INV-FLAG-002',
            Amount__c = 2000, Balance__c = 2000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-20),
            Due_Date__c = Date.today().addDays(-5)
        ));
        insert invoices;
    }

    private static Account getTestAccount() {
        return [SELECT Id FROM Account WHERE Name = 'Flag Test Account' LIMIT 1];
    }

    private static ARF_Invoice__c getInvoice(String docNum) {
        return [SELECT Id, Has_Dispute__c, Has_Promise__c FROM ARF_Invoice__c WHERE Document_Number__c = :docNum LIMIT 1];
    }

    @isTest
    static void testDisputeInsertSetsFlag() {
        Account acct = getTestAccount();
        ARF_Invoice__c inv = getInvoice('INV-FLAG-001');
        System.assertEquals(false, inv.Has_Dispute__c, 'Should start without dispute flag');

        Test.startTest();
        ARF_Dispute__c dispute = new ARF_Dispute__c(
            Account__c = acct.Id,
            Invoice__c = inv.Id,
            Category__c = 'Pricing',
            Priority__c = 'Medium',
            Dispute_Amount__c = 500,
            Description__c = 'Test dispute',
            Status__c = 'New'
        );
        insert dispute;
        Test.stopTest();

        inv = getInvoice('INV-FLAG-001');
        System.assertEquals(true, inv.Has_Dispute__c, 'Dispute flag should be set after insert');
    }

    @isTest
    static void testDisputeDeleteClearsFlag() {
        Account acct = getTestAccount();
        ARF_Invoice__c inv = getInvoice('INV-FLAG-001');

        ARF_Dispute__c dispute = new ARF_Dispute__c(
            Account__c = acct.Id,
            Invoice__c = inv.Id,
            Category__c = 'Pricing',
            Priority__c = 'Medium',
            Dispute_Amount__c = 500,
            Description__c = 'Test dispute',
            Status__c = 'New'
        );
        insert dispute;

        inv = getInvoice('INV-FLAG-001');
        System.assertEquals(true, inv.Has_Dispute__c, 'Flag should be set');

        Test.startTest();
        delete dispute;
        Test.stopTest();

        inv = getInvoice('INV-FLAG-001');
        System.assertEquals(false, inv.Has_Dispute__c, 'Flag should be cleared after last dispute deleted');
    }

    @isTest
    static void testMultipleDisputesKeepFlag() {
        Account acct = getTestAccount();
        ARF_Invoice__c inv = getInvoice('INV-FLAG-001');

        List<ARF_Dispute__c> disputes = new List<ARF_Dispute__c>();
        disputes.add(new ARF_Dispute__c(
            Account__c = acct.Id, Invoice__c = inv.Id,
            Category__c = 'Pricing', Priority__c = 'Medium',
            Dispute_Amount__c = 300, Description__c = 'Dispute 1', Status__c = 'New'
        ));
        disputes.add(new ARF_Dispute__c(
            Account__c = acct.Id, Invoice__c = inv.Id,
            Category__c = 'Quality', Priority__c = 'High',
            Dispute_Amount__c = 200, Description__c = 'Dispute 2', Status__c = 'New'
        ));
        insert disputes;

        inv = getInvoice('INV-FLAG-001');
        System.assertEquals(true, inv.Has_Dispute__c);

        Test.startTest();
        delete disputes[0];
        Test.stopTest();

        inv = getInvoice('INV-FLAG-001');
        System.assertEquals(true, inv.Has_Dispute__c, 'Flag should remain while other disputes exist');
    }

    @isTest
    static void testPromiseInsertSetsFlag() {
        Account acct = getTestAccount();
        ARF_Invoice__c inv = getInvoice('INV-FLAG-002');
        System.assertEquals(false, inv.Has_Promise__c, 'Should start without promise flag');

        Test.startTest();
        ARF_Promise_To_Pay__c promise = new ARF_Promise_To_Pay__c(
            Account__c = acct.Id,
            Invoice__c = inv.Id,
            Amount__c = 2000,
            Promise_Date__c = Date.today().addDays(7),
            Status__c = 'Open'
        );
        insert promise;
        Test.stopTest();

        inv = getInvoice('INV-FLAG-002');
        System.assertEquals(true, inv.Has_Promise__c, 'Promise flag should be set after insert');
    }

    @isTest
    static void testPromiseDeleteClearsFlag() {
        Account acct = getTestAccount();
        ARF_Invoice__c inv = getInvoice('INV-FLAG-002');

        ARF_Promise_To_Pay__c promise = new ARF_Promise_To_Pay__c(
            Account__c = acct.Id,
            Invoice__c = inv.Id,
            Amount__c = 2000,
            Promise_Date__c = Date.today().addDays(7),
            Status__c = 'Open'
        );
        insert promise;

        inv = getInvoice('INV-FLAG-002');
        System.assertEquals(true, inv.Has_Promise__c);

        Test.startTest();
        delete promise;
        Test.stopTest();

        inv = getInvoice('INV-FLAG-002');
        System.assertEquals(false, inv.Has_Promise__c, 'Flag should be cleared after last promise deleted');
    }

    @isTest
    static void testDisputeWithoutInvoice() {
        Account acct = getTestAccount();

        Test.startTest();
        ARF_Dispute__c dispute = new ARF_Dispute__c(
            Account__c = acct.Id,
            Category__c = 'Other',
            Priority__c = 'Low',
            Dispute_Amount__c = 100,
            Description__c = 'No invoice dispute',
            Status__c = 'New'
        );
        insert dispute;
        Test.stopTest();

        // Should not throw — just skip invoice update
        ARF_Invoice__c inv = getInvoice('INV-FLAG-001');
        System.assertEquals(false, inv.Has_Dispute__c, 'Unrelated invoice should not be flagged');
    }
}
