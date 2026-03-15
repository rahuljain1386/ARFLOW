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
        // Overdue invoice (45 days past due)
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'PDF-INV-001',
            Amount__c = 10000, Balance__c = 10000, Status__c = 'Overdue',
            Invoice_Date__c = Date.today().addDays(-75),
            Due_Date__c = Date.today().addDays(-45),
            PO_Number__c = 'PO-PDF-1'
        ));
        // Open invoice (not yet due)
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'PDF-INV-002',
            Amount__c = 5000, Balance__c = 3000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-20),
            Due_Date__c = Date.today().addDays(5)
        ));
        // Overdue 15 days (1-30 bucket)
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'PDF-INV-003',
            Amount__c = 2000, Balance__c = 2000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-45),
            Due_Date__c = Date.today().addDays(-15)
        ));
        // Paid invoice
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'PDF-INV-004',
            Amount__c = 1000, Balance__c = 0, Status__c = 'Paid',
            Invoice_Date__c = Date.today().addDays(-60),
            Due_Date__c = Date.today().addDays(-30)
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
        List<String> invoiceIdStrings = new List<String>();
        for (ARF_Invoice__c inv : invoices) {
            invoiceIdStrings.add(inv.Id);
        }
        String invoiceIdsCsv = String.join(invoiceIdStrings, ',');

        Test.startTest();
        PageReference pageRef = Page.ARF_InvoiceStatementPDF;
        pageRef.getParameters().put('accountId', acct.Id);
        pageRef.getParameters().put('invoiceIds', invoiceIdsCsv);
        Test.setCurrentPage(pageRef);

        ARF_InvoiceStatementPDFCtrl ctrl = new ARF_InvoiceStatementPDFCtrl();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.account, 'Account should be loaded');
        System.assertEquals('PDF Test Corp', ctrl.account.Name);
        System.assertEquals(4, ctrl.invoices.size(), 'Should load 4 invoices');
        System.assertEquals(18000, ctrl.totalAmount, 'Total amount should be 18000');
        System.assertEquals(15000, ctrl.totalBalance, 'Total balance should be 15000');
        System.assert(String.isNotBlank(ctrl.generatedDate), 'Generated date should be set');

        // Aging verification
        System.assertEquals(3000, ctrl.agingCurrent, 'Current aging should be 3000 (not yet due)');
        System.assertEquals(2000, ctrl.aging1to30, '1-30 aging should be 2000');
        System.assertEquals(10000, ctrl.aging31to60, '31-60 aging should be 10000');
        System.assertEquals(0, ctrl.aging61to90, '61-90 aging should be 0');
        System.assertEquals(0, ctrl.agingOver90, '90+ aging should be 0');
        System.assertEquals(12000, ctrl.overdueBalance, 'Overdue balance should be 12000');

        // Open invoice count (Open + Overdue statuses)
        System.assertEquals(3, ctrl.openInvoiceCount, 'Should have 3 open/overdue invoices');

        // Company info
        System.assert(String.isNotBlank(ctrl.companyName), 'Company name should be set');
        System.assertEquals('Net 30', ctrl.paymentTerms, 'Payment terms should default to Net 30');
    }

    @isTest
    static void testConstructor_NoAccountId() {
        Test.startTest();
        PageReference pageRef = Page.ARF_InvoiceStatementPDF;
        Test.setCurrentPage(pageRef);

        ARF_InvoiceStatementPDFCtrl ctrl = new ARF_InvoiceStatementPDFCtrl();
        Test.stopTest();

        System.assertEquals(0, ctrl.invoices.size(), 'Should have no invoices');
        System.assertEquals(0, ctrl.totalAmount);
        System.assertEquals(0, ctrl.totalBalance);
        System.assertEquals(0, ctrl.agingCurrent);
        System.assertEquals(0, ctrl.aging1to30);
        System.assertEquals(0, ctrl.aging31to60);
        System.assertEquals(0, ctrl.aging61to90);
        System.assertEquals(0, ctrl.agingOver90);
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
        System.assertEquals(0, ctrl.openInvoiceCount);
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

    @isTest
    static void testGeneratePdf_EmptyInvoiceIds() {
        Account acct = getTestAccount();
        Test.startTest();
        try {
            ARF_InvoiceStatementPDFCtrl.generatePdf(acct.Id, new List<Id>());
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }
}
