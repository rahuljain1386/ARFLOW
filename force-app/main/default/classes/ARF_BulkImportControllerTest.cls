@isTest
private class ARF_BulkImportControllerTest {

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(
            Name = 'Acme Corp',
            AccountNumber = 'ACME-001'
        );
        insert acct;

        Account acct2 = new Account(
            Name = 'Beta Inc',
            AccountNumber = 'BETA-001'
        );
        insert acct2;
    }

    // ─── parseCSV Tests ───

    @isTest
    static void testParseCSV_Invoice_Valid() {
        String csv = 'Account_Name,Document_Number,Amount,Due_Date,PO_Number,Reference\n'
                   + '"Acme Corp","INV-001","5000.00","2026-04-15","PO-1","Net 30"\n'
                   + '"Beta Inc","INV-002","3000.00","2026-05-01","PO-2","Net 60"';

        Test.startTest();
        ARF_BulkImportController.ImportPreview preview = ARF_BulkImportController.parseCSV(csv, 'Invoice');
        Test.stopTest();

        System.assertEquals(0, preview.errors.size(), 'Should have no errors');
        System.assertEquals(2, preview.rows.size(), 'Should parse 2 rows');
        System.assertEquals(6, preview.columns.size(), 'Should have 6 columns');
        System.assertEquals(2, preview.totalRows, 'Total rows should be 2');
        System.assertEquals('Invoice', preview.importType);
    }

    @isTest
    static void testParseCSV_Invoice_MissingColumn() {
        String csv = 'Account_Name,Amount,Due_Date\n"Acme Corp","5000","2026-04-15"';

        Test.startTest();
        ARF_BulkImportController.ImportPreview preview = ARF_BulkImportController.parseCSV(csv, 'Invoice');
        Test.stopTest();

        System.assert(preview.errors.size() > 0, 'Should report missing Document_Number column');
    }

    @isTest
    static void testParseCSV_Payment_Valid() {
        String csv = 'Account_Name,Amount,Payment_Date,Method,Reference,ERP_ID\n'
                   + '"Acme Corp","5000.00","2026-03-15","ACH","Wire 123","ERP-1"';

        Test.startTest();
        ARF_BulkImportController.ImportPreview preview = ARF_BulkImportController.parseCSV(csv, 'Payment');
        Test.stopTest();

        System.assertEquals(0, preview.errors.size(), 'Should have no errors');
        System.assertEquals(1, preview.rows.size(), 'Should parse 1 row');
    }

    @isTest
    static void testParseCSV_Payment_MissingColumn() {
        String csv = 'Account_Name,Amount\n"Acme Corp","5000"';

        Test.startTest();
        ARF_BulkImportController.ImportPreview preview = ARF_BulkImportController.parseCSV(csv, 'Payment');
        Test.stopTest();

        System.assert(preview.errors.size() > 0, 'Should report missing Payment_Date column');
    }

    @isTest
    static void testParseCSV_EmptyContent() {
        Test.startTest();
        ARF_BulkImportController.ImportPreview preview = ARF_BulkImportController.parseCSV('', 'Invoice');
        Test.stopTest();

        System.assert(preview.errors.size() > 0, 'Should report empty content error');
        System.assertEquals('CSV content is empty', preview.errors[0]);
    }

    @isTest
    static void testParseCSV_HeaderOnly() {
        String csv = 'Account_Name,Document_Number,Amount,Due_Date';

        Test.startTest();
        ARF_BulkImportController.ImportPreview preview = ARF_BulkImportController.parseCSV(csv, 'Invoice');
        Test.stopTest();

        System.assert(preview.errors.size() > 0, 'Should report no data rows');
    }

    @isTest
    static void testParseCSV_InvalidAmount_Warning() {
        String csv = 'Account_Name,Document_Number,Amount,Due_Date\n'
                   + '"Acme Corp","INV-001","not_a_number","2026-04-15"';

        Test.startTest();
        ARF_BulkImportController.ImportPreview preview = ARF_BulkImportController.parseCSV(csv, 'Invoice');
        Test.stopTest();

        System.assert(preview.warnings.size() > 0, 'Should have a warning for invalid amount');
    }

    // ─── executeImport Tests ───

    @isTest
    static void testExecuteImport_Invoice_Success() {
        String csv = 'Account_Name,Document_Number,Amount,Due_Date\n'
                   + '"Acme Corp","INV-BULK-001","5000.00","2026-04-15"\n'
                   + '"Beta Inc","INV-BULK-002","3000.00","2026-05-01"';

        Test.startTest();
        ARF_BulkImportController.ImportResult result = ARF_BulkImportController.executeImport(csv, 'Invoice');
        Test.stopTest();

        System.assertEquals(2, result.successCount, 'Should import 2 invoices');
        System.assertEquals(0, result.errorCount, 'Should have no errors');

        List<ARF_Invoice__c> invoices = [SELECT Id, Document_Number__c FROM ARF_Invoice__c WHERE Document_Number__c LIKE 'INV-BULK%'];
        System.assertEquals(2, invoices.size(), 'Should have inserted 2 invoices');
    }

    @isTest
    static void testExecuteImport_Invoice_AccountNotFound() {
        String csv = 'Account_Name,Document_Number,Amount,Due_Date\n'
                   + '"NonExistent Co","INV-BULK-003","1000.00","2026-04-15"';

        Test.startTest();
        ARF_BulkImportController.ImportResult result = ARF_BulkImportController.executeImport(csv, 'Invoice');
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'Should not import anything');
        System.assertEquals(1, result.errorCount, 'Should have 1 error');
        System.assert(result.errors[0].contains('not found'), 'Error should mention account not found');
    }

    @isTest
    static void testExecuteImport_Payment_Success() {
        String csv = 'Account_Name,Amount,Payment_Date,Method,Reference,ERP_ID\n'
                   + '"Acme Corp","5000.00","2026-03-15","ACH","Wire 123","ERP-PMT-001"';

        Test.startTest();
        ARF_BulkImportController.ImportResult result = ARF_BulkImportController.executeImport(csv, 'Payment');
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Should import 1 payment');
        System.assertEquals(0, result.errorCount, 'Should have no errors');

        List<ARF_Payment__c> payments = [SELECT Id, ERP_ID__c FROM ARF_Payment__c WHERE ERP_ID__c = 'ERP-PMT-001'];
        System.assertEquals(1, payments.size(), 'Should have inserted 1 payment');
    }

    @isTest
    static void testExecuteImport_Payment_AccountNotFound() {
        String csv = 'Account_Name,Amount,Payment_Date\n'
                   + '"Ghost Corp","2000.00","2026-03-15"';

        Test.startTest();
        ARF_BulkImportController.ImportResult result = ARF_BulkImportController.executeImport(csv, 'Payment');
        Test.stopTest();

        System.assertEquals(0, result.successCount);
        System.assertEquals(1, result.errorCount);
    }

    @isTest
    static void testExecuteImport_Invoice_BadData() {
        String csv = 'Account_Name,Document_Number,Amount,Due_Date\n'
                   + '"Acme Corp","INV-BAD","not_a_number","bad_date"';

        Test.startTest();
        ARF_BulkImportController.ImportResult result = ARF_BulkImportController.executeImport(csv, 'Invoice');
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'Should not import bad data');
        System.assert(result.errorCount > 0, 'Should have errors');
    }

    // ─── getCSVTemplate Tests ───

    @isTest
    static void testGetCSVTemplate_Invoice() {
        Test.startTest();
        String template = ARF_BulkImportController.getCSVTemplate('Invoice');
        Test.stopTest();

        System.assert(template.contains('Account_Name'), 'Template should have Account_Name column');
        System.assert(template.contains('Document_Number'), 'Template should have Document_Number column');
        System.assert(template.contains('Amount'), 'Template should have Amount column');
        System.assert(template.contains('Due_Date'), 'Template should have Due_Date column');
    }

    @isTest
    static void testGetCSVTemplate_Payment() {
        Test.startTest();
        String template = ARF_BulkImportController.getCSVTemplate('Payment');
        Test.stopTest();

        System.assert(template.contains('Account_Name'), 'Template should have Account_Name column');
        System.assert(template.contains('Amount'), 'Template should have Amount column');
        System.assert(template.contains('Payment_Date'), 'Template should have Payment_Date column');
    }

    // ─── Mixed / Edge Case Tests ───

    @isTest
    static void testExecuteImport_Invoice_WithOptionalFields() {
        String csv = 'Account_Name,Document_Number,Amount,Due_Date,PO_Number,Reference\n'
                   + '"Acme Corp","INV-OPT-001","7500.00","2026-06-01","PO-OPT-1","Net 45 terms"';

        Test.startTest();
        ARF_BulkImportController.ImportResult result = ARF_BulkImportController.executeImport(csv, 'Invoice');
        Test.stopTest();

        System.assertEquals(1, result.successCount);
        ARF_Invoice__c inv = [SELECT PO_Number__c, Reference__c FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-OPT-001' LIMIT 1];
        System.assertEquals('PO-OPT-1', inv.PO_Number__c);
        System.assertEquals('Net 45 terms', inv.Reference__c);
    }

    @isTest
    static void testParseCSV_QuotedFieldsWithCommas() {
        String csv = 'Account_Name,Document_Number,Amount,Due_Date\n'
                   + '"Acme, Corp","INV-Q1","1000.00","2026-04-15"';

        Test.startTest();
        ARF_BulkImportController.ImportPreview preview = ARF_BulkImportController.parseCSV(csv, 'Invoice');
        Test.stopTest();

        System.assertEquals(1, preview.rows.size());
        System.assertEquals('Acme, Corp', preview.rows[0].get('Account_Name'));
    }
}
