@isTest
private class ARF_InvoiceStatementPDFCtrlTest {

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(
            Name = 'PDF Test Corp',
            AccountNumber = 'PDF-001',
            BillingStreet = '123 Main St',
            BillingCity = 'San Francisco',
            BillingState = 'CA',
            BillingPostalCode = '94105',
            BillingCountry = 'US'
        );
        insert acct;

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'PDF-INV-001',
            Amount__c = 10000, Balance__c = 10000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-45),
            Due_Date__c = Date.today().addDays(-15),
            PO_Number__c = 'PO-PDF-1'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'PDF-INV-002',
            Amount__c = 5000, Balance__c = 3000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-20),
            Due_Date__c = Date.today().addDays(5)
        ));
        insert invoices;
    }

    private static Account getTestAccount() {
        return [SELECT Id FROM Account WHERE Name = 'PDF Test Corp' LIMIT 1];
    }

    private static List<ARF_Invoice__c> getTestInvoices() {
        return [SELECT Id FROM ARF_Invoice__c ORDER BY Document_Number__c];
    }

    @isTest
    static void testConstructor_WithValidParams() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();
        String invoiceIdsCsv = invoices[0].Id + ',' + invoices[1].Id;

        Test.startTest();
        PageReference pageRef = Page.ARF_InvoiceStatementPDF;
        pageRef.getParameters().put('accountId', acct.Id);
        pageRef.getParameters().put('invoiceIds', invoiceIdsCsv);
        Test.setCurrentPage(pageRef);

        ARF_InvoiceStatementPDFCtrl ctrl = new ARF_InvoiceStatementPDFCtrl();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.account, 'Account should be loaded');
        System.assertEquals('PDF Test Corp', ctrl.account.Name);
        System.assertEquals(2, ctrl.invoices.size(), 'Should load 2 invoices');
        System.assertEquals(15000, ctrl.totalAmount, 'Total amount should be 15000');
        System.assertEquals(13000, ctrl.totalBalance, 'Total balance should be 13000');
        System.assert(String.isNotBlank(ctrl.generatedDate), 'Generated date should be set');
    }

    @isTest
    static void testConstructor_NoAccountId() {
        Test.startTest();
        PageReference pageRef = Page.ARF_InvoiceStatementPDF;
        Test.setCurrentPage(pageRef);

        ARF_InvoiceStatementPDFCtrl ctrl = new ARF_InvoiceStatementPDFCtrl();
        Test.stopTest();

        System.assertEquals(0, ctrl.invoices.size(), 'Should have no invoices');
    }

    @isTest
    static void testConstructor_NoInvoiceIds() {
        Account acct = getTestAccount();

        Test.startTest();
        PageReference pageRef = Page.ARF_InvoiceStatementPDF;
        pageRef.getParameters().put('accountId', acct.Id);
        Test.setCurrentPage(pageRef);

        ARF_InvoiceStatementPDFCtrl ctrl = new ARF_InvoiceStatementPDFCtrl();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.account, 'Account should be loaded');
        System.assertEquals(0, ctrl.invoices.size(), 'Should have no invoices');
    }

    @isTest
    static void testConstructor_InvalidInvoiceIds() {
        Account acct = getTestAccount();

        Test.startTest();
        PageReference pageRef = Page.ARF_InvoiceStatementPDF;
        pageRef.getParameters().put('accountId', acct.Id);
        pageRef.getParameters().put('invoiceIds', 'invalid_id,another_bad');
        Test.setCurrentPage(pageRef);

        ARF_InvoiceStatementPDFCtrl ctrl = new ARF_InvoiceStatementPDFCtrl();
        Test.stopTest();

        System.assertEquals(0, ctrl.invoices.size(), 'Should handle invalid IDs gracefully');
    }

    @isTest
    static void testGeneratePdf() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();
        List<Id> invoiceIds = new List<Id>();
        for (ARF_Invoice__c inv : invoices) invoiceIds.add(inv.Id);

        Test.startTest();
        String pdfBase64 = ARF_InvoiceStatementPDFCtrl.generatePdf(acct.Id, invoiceIds);
        Test.stopTest();

        System.assert(String.isNotBlank(pdfBase64), 'Should return base64 encoded PDF');
        Blob decoded = EncodingUtil.base64Decode(pdfBase64);
        System.assert(decoded.size() > 0, 'Decoded blob should not be empty');
    }

    @isTest
    static void testGeneratePdf_NullParams() {
        Test.startTest();
        try {
            ARF_InvoiceStatementPDFCtrl.generatePdf(null, null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }
}
