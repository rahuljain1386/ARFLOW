@isTest
private class ARF_TransactionActionControllerTest {

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(Name = 'Transaction Test Corp', AccountNumber = 'ACCT-001');
        insert acct;

        List<Contact> contacts = new List<Contact>();
        contacts.add(new Contact(
            FirstName = 'Jane', LastName = 'Doe', Email = 'jane.doe@test.com',
            AccountId = acct.Id, ARF_Primary_AR_Contact__c = true, ARF_AR_Role__c = 'AP Contact'
        ));
        contacts.add(new Contact(
            FirstName = 'Bob', LastName = 'Smith', Email = 'bob.smith@test.com',
            AccountId = acct.Id, ARF_Primary_AR_Contact__c = false, ARF_AR_Role__c = 'Controller'
        ));
        insert contacts;

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'INV-001',
            Amount__c = 5000, Balance__c = 5000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-60), Due_Date__c = Date.today().addDays(-30),
            PO_Number__c = 'PO-100', Reference__c = 'REF-AAA'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'INV-002',
            Amount__c = 3000, Balance__c = 3000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-20), Due_Date__c = Date.today().addDays(-5),
            Has_Dispute__c = true
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'INV-003',
            Amount__c = 2000, Balance__c = 2000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-5), Due_Date__c = Date.today().addDays(10)
        ));
        insert invoices;

        List<ARF_Email_Template__c> templates = new List<ARF_Email_Template__c>();
        templates.add(new ARF_Email_Template__c(
            Template_Name__c = 'Collection Reminder EN',
            Subject__c = 'Payment Reminder for {account_name}',
            Body_HTML__c = '<p>Dear {contact_name},</p><p>You have {invoice_count} invoices totaling {total_balance}.</p>{invoice_table}<p>Please remit payment.</p><p>{collector_name}</p>',
            Locale__c = 'en_US', Category__c = 'Collection', Active__c = true
        ));
        templates.add(new ARF_Email_Template__c(
            Template_Name__c = 'Recordatorio de Cobro',
            Subject__c = 'Recordatorio de pago - {account_name}',
            Body_HTML__c = '<p>Estimado {contact_name},</p><p>Tiene {invoice_count} facturas.</p>',
            Locale__c = 'es', Category__c = 'Collection', Active__c = true
        ));
        templates.add(new ARF_Email_Template__c(
            Template_Name__c = 'Inactive Template',
            Subject__c = 'Test', Body_HTML__c = 'Test',
            Locale__c = 'en_US', Category__c = 'Reminder', Active__c = false
        ));
        insert templates;
    }

    private static Account getTestAccount() {
        return [SELECT Id, Name FROM Account WHERE Name = 'Transaction Test Corp' LIMIT 1];
    }

    private static List<ARF_Invoice__c> getTestInvoices() {
        return [SELECT Id, Balance__c, Document_Number__c FROM ARF_Invoice__c ORDER BY Document_Number__c];
    }

    // ===== EMAIL TEMPLATE TESTS =====

    @isTest
    static void testGetEmailTemplates_NoFilter() {
        Test.startTest();
        List<ARF_Email_Template__c> result = ARF_TransactionActionController.getEmailTemplates(null, null);
        Test.stopTest();
        System.assertEquals(2, result.size(), 'Should return 2 active templates');
    }

    @isTest
    static void testGetEmailTemplates_FilterByLocale() {
        Test.startTest();
        List<ARF_Email_Template__c> result = ARF_TransactionActionController.getEmailTemplates('es', null);
        Test.stopTest();
        System.assertEquals(1, result.size(), 'Should return 1 Spanish template');
        System.assertEquals('Recordatorio de Cobro', result[0].Template_Name__c);
    }

    @isTest
    static void testGetEmailTemplates_FilterByCategory() {
        Test.startTest();
        List<ARF_Email_Template__c> result = ARF_TransactionActionController.getEmailTemplates(null, 'Collection');
        Test.stopTest();
        System.assertEquals(2, result.size(), 'Should return 2 collection templates');
    }

    // ===== RESOLVE TEMPLATE TESTS =====

    @isTest
    static void testResolveTemplate_AllMergeFields() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();
        List<Id> invoiceIds = new List<Id>();
        for (ARF_Invoice__c inv : invoices) invoiceIds.add(inv.Id);

        ARF_Email_Template__c tmpl = [SELECT Id FROM ARF_Email_Template__c WHERE Template_Name__c = 'Collection Reminder EN' LIMIT 1];

        Test.startTest();
        Map<String, String> result = ARF_TransactionActionController.resolveTemplate(tmpl.Id, acct.Id, invoiceIds);
        Test.stopTest();

        System.assert(result.containsKey('subject'), 'Should have subject');
        System.assert(result.containsKey('body'), 'Should have body');
        System.assert(result.get('subject').contains('Transaction Test Corp'), 'Subject should contain account name');
        System.assert(result.get('body').contains('Jane Doe'), 'Body should contain contact name');
        System.assert(result.get('body').contains('INV-001'), 'Body should contain invoice table');
        System.assert(result.get('body').contains('3'), 'Body should contain invoice count');
    }

    @isTest
    static void testResolveTemplate_NullInvoices() {
        Account acct = getTestAccount();
        ARF_Email_Template__c tmpl = [SELECT Id FROM ARF_Email_Template__c WHERE Template_Name__c = 'Collection Reminder EN' LIMIT 1];

        Test.startTest();
        Map<String, String> result = ARF_TransactionActionController.resolveTemplate(tmpl.Id, acct.Id, new List<Id>());
        Test.stopTest();

        System.assert(result.get('body').contains('0 invoices') || result.get('body').contains('$0.00'),
            'Should handle empty invoices gracefully');
    }

    // ===== ORG-WIDE EMAIL TESTS =====

    @isTest
    static void testGetOrgWideEmailAddresses() {
        Test.startTest();
        List<Map<String, String>> result = ARF_TransactionActionController.getOrgWideEmailAddresses();
        Test.stopTest();
        System.assertNotEquals(null, result, 'Should return list (possibly empty in test context)');
    }

    // ===== CURRENT USER EMAIL =====

    @isTest
    static void testGetCurrentUserEmail() {
        Test.startTest();
        Map<String, String> result = ARF_TransactionActionController.getCurrentUserEmail();
        Test.stopTest();
        System.assertNotEquals(null, result, 'Should return user info');
        System.assertNotEquals(null, result.get('email'), 'Should have email');
        System.assertNotEquals(null, result.get('name'), 'Should have name');
    }

    // ===== CONTACT CUSTOMER TESTS =====

    @isTest
    static void testExecuteContactCustomer_EmailWithNote() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();
        List<Id> invoiceIds = new List<Id>{ invoices[0].Id, invoices[1].Id };
        Contact con = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        Test.startTest();
        Id commId = ARF_TransactionActionController.executeContactCustomer(
            acct.Id, invoiceIds, 'Phone', null, null, null, null,
            'Collection Call', 'Called about invoices', false, con.Id,
            null, 'Call Log', 'Followup: Collection Call', 'Called AP about past due',
            false, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, commId, 'Should return communication Id');
        ARF_Communication__c comm = [SELECT Channel__c, Invoice_Count__c, Total_Balance__c FROM ARF_Communication__c WHERE Id = :commId];
        System.assertEquals('Phone', comm.Channel__c);
        System.assertEquals(2, comm.Invoice_Count__c);
        System.assertEquals(8000, comm.Total_Balance__c);

        List<ARF_Communication_Invoice__c> junctions = [SELECT Id FROM ARF_Communication_Invoice__c WHERE Communication__c = :commId];
        System.assertEquals(2, junctions.size(), 'Should create 2 junction records');

        List<ARF_Note__c> notes = [SELECT Title__c FROM ARF_Note__c WHERE Account__c = :acct.Id AND Title__c = 'Followup: Collection Call'];
        System.assertEquals(1, notes.size(), 'Should create note');
    }

    @isTest
    static void testExecuteContactCustomer_WithFollowUp() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();
        List<Id> invoiceIds = new List<Id>{ invoices[0].Id };

        Test.startTest();
        ARF_TransactionActionController.executeContactCustomer(
            acct.Id, invoiceIds, 'Phone', null, null, null, null,
            'Call', 'Notes', false, null, null, null, null, null,
            true, 7, 'Follow up on INV-001', 'Check payment status'
        );
        Test.stopTest();

        List<Task> tasks = [SELECT Subject, ActivityDate FROM Task WHERE WhatId = :acct.Id AND Subject = 'Follow up on INV-001'];
        System.assertEquals(1, tasks.size(), 'Should create follow-up task');
        System.assertEquals(Date.today().addDays(7), tasks[0].ActivityDate);
    }

    @isTest
    static void testExecuteContactCustomer_NullAccountId() {
        Test.startTest();
        try {
            ARF_TransactionActionController.executeContactCustomer(
                null, new List<Id>(), 'Email', null, null, null, null,
                null, null, false, null, null, null, null, null,
                false, null, null, null
            );
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testExecuteContactCustomer_EmptyInvoices() {
        Account acct = getTestAccount();
        Test.startTest();
        Id commId = ARF_TransactionActionController.executeContactCustomer(
            acct.Id, new List<Id>(), 'Phone', null, null, null, null,
            'Call without invoices', 'General inquiry', false, null, null,
            null, null, null, false, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, commId, 'Should succeed without invoices');
        ARF_Communication__c comm = [SELECT Invoice_Count__c, Total_Balance__c FROM ARF_Communication__c WHERE Id = :commId];
        System.assertEquals(0, comm.Invoice_Count__c, 'Invoice count should be 0');
        System.assertEquals(0, comm.Total_Balance__c, 'Total balance should be 0');

        List<ARF_Communication_Invoice__c> junctions = [SELECT Id FROM ARF_Communication_Invoice__c WHERE Communication__c = :commId];
        System.assertEquals(0, junctions.size(), 'Should create no junction records');
    }

    @isTest
    static void testGetOpenInvoicesForAccount() {
        Account acct = getTestAccount();
        Test.startTest();
        List<ARF_Invoice__c> result = ARF_TransactionActionController.getOpenInvoicesForAccount(acct.Id);
        Test.stopTest();

        System.assertEquals(3, result.size(), 'Should return all 3 open invoices');
        // Verify ordered by Due_Date__c ASC
        System.assert(result[0].Due_Date__c <= result[1].Due_Date__c, 'Should be ordered by due date');
    }

    @isTest
    static void testGetOpenInvoicesForAccount_NullAccount() {
        Test.startTest();
        try {
            ARF_TransactionActionController.getOpenInvoicesForAccount(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testExecuteContactCustomer_PrintChannel() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();

        Test.startTest();
        Id commId = ARF_TransactionActionController.executeContactCustomer(
            acct.Id, new List<Id>{ invoices[0].Id }, 'Print', null, null, null, null,
            'Printed Statement', '<p>Statement body</p>', false, null,
            null, null, null, null, false, null, null, null
        );
        Test.stopTest();

        ARF_Communication__c comm = [SELECT Channel__c, Status__c FROM ARF_Communication__c WHERE Id = :commId];
        System.assertEquals('Letter', comm.Channel__c, 'Print should map to Letter');
        System.assertEquals('Draft', comm.Status__c);
    }

    // ===== CSV TESTS =====

    @isTest
    static void testGenerateInvoiceCsv_ValidData() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();
        List<Id> invoiceIds = new List<Id>();
        for (ARF_Invoice__c inv : invoices) invoiceIds.add(inv.Id);

        Test.startTest();
        String base64Csv = ARF_TransactionActionController.generateInvoiceCsv(acct.Id, invoiceIds);
        Test.stopTest();

        String csv = EncodingUtil.base64Decode(base64Csv).toString();
        System.assert(csv.contains('Document Number'), 'Should have header row');
        System.assert(csv.contains('INV-001'), 'Should contain invoice data');
        System.assert(csv.contains('INV-002'), 'Should contain all invoices');
    }

    @isTest
    static void testGenerateInvoiceCsv_NullFields() {
        Account acct = getTestAccount();
        // INV-003 has no PO_Number or Reference
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-003' LIMIT 1];

        Test.startTest();
        String base64Csv = ARF_TransactionActionController.generateInvoiceCsv(acct.Id, new List<Id>{ inv.Id });
        Test.stopTest();

        String csv = EncodingUtil.base64Decode(base64Csv).toString();
        System.assert(csv.contains('INV-003'), 'Should contain invoice');
    }

    @isTest
    static void testGenerateInvoiceCsv_SpecialCharacters() {
        Account acct = getTestAccount();
        ARF_Invoice__c inv = new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'INV-"SPECIAL"',
            Amount__c = 100, Balance__c = 100, Status__c = 'Open',
            Invoice_Date__c = Date.today(), Due_Date__c = Date.today().addDays(30)
        );
        insert inv;

        Test.startTest();
        String base64Csv = ARF_TransactionActionController.generateInvoiceCsv(acct.Id, new List<Id>{ inv.Id });
        Test.stopTest();

        String csv = EncodingUtil.base64Decode(base64Csv).toString();
        System.assert(csv.contains('INV-""SPECIAL""'), 'Should escape double quotes');
    }

    // ===== BULK NOTE TESTS =====

    @isTest
    static void testCreateBulkNotes_MultipleInvoices() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();
        List<Id> invoiceIds = new List<Id>();
        for (ARF_Invoice__c inv : invoices) invoiceIds.add(inv.Id);

        Test.startTest();
        List<ARF_Note__c> notes = ARF_TransactionActionController.createBulkNotes(
            acct.Id, invoiceIds, 'Aging review', 'Reviewed during aging meeting', 'General'
        );
        Test.stopTest();

        System.assertEquals(3, notes.size(), 'Should create one note per invoice');
        for (ARF_Note__c n : notes) {
            System.assertEquals('Aging review', n.Title__c);
        }
    }

    @isTest
    static void testCreateBulkNotes_NullAccountId() {
        Test.startTest();
        try {
            ARF_TransactionActionController.createBulkNotes(null, new List<Id>(), 'Title', 'Body', 'General');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ===== BULK DISPUTE TESTS =====

    @isTest
    static void testCreateBulkDisputes_MultipleInvoices() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();
        List<Id> invoiceIds = new List<Id>{ invoices[0].Id, invoices[1].Id };

        Test.startTest();
        List<ARF_Dispute__c> disputes = ARF_TransactionActionController.createBulkDisputes(
            acct.Id, invoiceIds, 'Pricing', 'High', 'Incorrect pricing on both invoices'
        );
        Test.stopTest();

        System.assertEquals(2, disputes.size(), 'Should create one dispute per invoice');
        // Verify dispute amount defaults to invoice balance
        Map<Id, Decimal> disputeAmounts = new Map<Id, Decimal>();
        for (ARF_Dispute__c d : [SELECT Invoice__c, Dispute_Amount__c FROM ARF_Dispute__c WHERE Id IN :disputes]) {
            disputeAmounts.put(d.Invoice__c, d.Dispute_Amount__c);
        }
        System.assertEquals(5000, disputeAmounts.get(invoices[0].Id), 'Dispute amount should equal invoice balance');
        System.assertEquals(3000, disputeAmounts.get(invoices[1].Id));
    }

    @isTest
    static void testCreateBulkDisputes_DefaultPriority() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();

        Test.startTest();
        List<ARF_Dispute__c> disputes = ARF_TransactionActionController.createBulkDisputes(
            acct.Id, new List<Id>{ invoices[0].Id }, 'Quality', null, 'Defective goods'
        );
        Test.stopTest();

        ARF_Dispute__c d = [SELECT Priority__c FROM ARF_Dispute__c WHERE Id = :disputes[0].Id];
        System.assertEquals('Medium', d.Priority__c, 'Should default to Medium priority');
    }

    // ===== BULK PROMISE TESTS =====

    @isTest
    static void testCreateBulkPromises_ProportionalAllocation() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();
        // INV-001=$5000, INV-002=$3000 = $8000 total. Promising $4000.
        List<Id> invoiceIds = new List<Id>{ invoices[0].Id, invoices[1].Id };

        Test.startTest();
        List<ARF_Promise_To_Pay__c> promises = ARF_TransactionActionController.createBulkPromises(
            acct.Id, invoiceIds, 4000, Date.today().addDays(14), 'Will pay in 2 weeks'
        );
        Test.stopTest();

        System.assertEquals(2, promises.size(), 'Should create one promise per invoice');
        Decimal totalPromised = 0;
        for (ARF_Promise_To_Pay__c p : promises) totalPromised += p.Amount__c;
        System.assertEquals(4000, totalPromised, 'Total promised should equal requested amount');
    }

    @isTest
    static void testCreateBulkPromises_SingleInvoice() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();

        Test.startTest();
        List<ARF_Promise_To_Pay__c> promises = ARF_TransactionActionController.createBulkPromises(
            acct.Id, new List<Id>{ invoices[0].Id }, 5000, Date.today().addDays(7), 'Full payment'
        );
        Test.stopTest();

        System.assertEquals(1, promises.size());
        System.assertEquals(5000, promises[0].Amount__c);
        System.assertEquals('Open', promises[0].Status__c);
    }

    @isTest
    static void testCreateBulkPromises_InvalidAmount() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();

        Test.startTest();
        try {
            ARF_TransactionActionController.createBulkPromises(
                acct.Id, new List<Id>{ invoices[0].Id }, 0, Date.today(), 'Test'
            );
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Should throw error for invalid amount');
        }
        Test.stopTest();
    }

    // ===== HELPER METHOD TESTS =====

    @isTest
    static void testBuildInvoiceHtmlTable() {
        List<ARF_Invoice__c> invoices = [
            SELECT Document_Number__c, Invoice_Date__c, Due_Date__c,
                   Amount__c, Balance__c, Days_Past_Due__c
            FROM ARF_Invoice__c ORDER BY Document_Number__c LIMIT 2
        ];

        Test.startTest();
        String html = ARF_TransactionActionController.buildInvoiceHtmlTable(invoices);
        Test.stopTest();

        System.assert(html.contains('<table'), 'Should contain table tag');
        System.assert(html.contains('INV-001'), 'Should contain invoice number');
        System.assert(html.contains('Total'), 'Should contain total row');
    }

    @isTest
    static void testReplaceMergeFields() {
        Account acct = getTestAccount();
        Account acctWithNumber = [SELECT Name, AccountNumber FROM Account WHERE Id = :acct.Id];
        Contact con = [SELECT Name, Email FROM Contact WHERE AccountId = :acct.Id AND ARF_Primary_AR_Contact__c = true LIMIT 1];
        String template = 'Dear {contact_name}, Account {account_name} has {invoice_count} invoices totaling {total_balance}. Past due: {past_due_amount}. - {collector_name}';

        Test.startTest();
        String result = ARF_TransactionActionController.replaceMergeFields(
            template, acctWithNumber, con, new List<ARF_Invoice__c>(), ''
        );
        Test.stopTest();

        System.assert(result.contains('Transaction Test Corp'), 'Should resolve account name');
        System.assert(result.contains('Jane Doe'), 'Should resolve contact name');
        System.assert(result.contains('0'), 'Should resolve invoice count');
    }

    // ===== CONTACTS FOR EMAIL TESTS =====

    @isTest
    static void testGetContactsForEmail() {
        Account acct = getTestAccount();

        Test.startTest();
        Map<String, Object> result = ARF_TransactionActionController.getContactsForEmail(acct.Id);
        Test.stopTest();

        List<Object> toContacts = (List<Object>) result.get('toContacts');
        List<Object> ccContacts = (List<Object>) result.get('ccContacts');
        System.assertEquals(1, toContacts.size(), 'Should have 1 primary (TO) contact');
        System.assertEquals(1, ccContacts.size(), 'Should have 1 non-primary (CC) contact');

        Map<String, String> toContact = (Map<String, String>) toContacts[0];
        System.assertEquals('jane.doe@test.com', toContact.get('email'));

        Map<String, String> ccContact = (Map<String, String>) ccContacts[0];
        System.assertEquals('bob.smith@test.com', ccContact.get('email'));
    }

    @isTest
    static void testGetContactsForEmail_NullAccountId() {
        Test.startTest();
        try {
            ARF_TransactionActionController.getContactsForEmail(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ===== EXECUTE CONTACT CUSTOMER WITH FORMAT TESTS =====

    @isTest
    static void testExecuteContactCustomerWithFormat_Pdf() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();
        List<Id> invoiceIds = new List<Id>{ invoices[0].Id };
        Contact con = [SELECT Id FROM Contact WHERE AccountId = :acct.Id AND ARF_Primary_AR_Contact__c = true LIMIT 1];

        Test.startTest();
        Id commId = ARF_TransactionActionController.executeContactCustomerWithFormat(
            acct.Id, invoiceIds, 'Phone', null, null, null, null,
            'Test Subject', '<p>Test body</p>', false, con.Id,
            'Test Template', null, null, null,
            false, null, null, null, 'pdf'
        );
        Test.stopTest();

        System.assertNotEquals(null, commId, 'Should return communication Id');
    }

    @isTest
    static void testExecuteContactCustomerWithFormat_Csv() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();
        List<Id> invoiceIds = new List<Id>{ invoices[0].Id };

        Test.startTest();
        Id commId = ARF_TransactionActionController.executeContactCustomerWithFormat(
            acct.Id, invoiceIds, 'Phone', null, null, null, null,
            'CSV Test', 'Body', false, null, null,
            null, null, null, false, null, null, null, 'csv'
        );
        Test.stopTest();

        System.assertNotEquals(null, commId, 'Should return communication Id');
    }

    // ===== ENHANCED BULK DISPUTE TESTS =====

    @isTest
    static void testCreateBulkDisputesEnhanced_PerInvoiceConfig() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();

        String configJson = '[' +
            '{"invoiceId":"' + invoices[0].Id + '","category":"Pricing","rootCause":"Pricing Error","priority":"High","amount":5000,"description":"Overcharged"},' +
            '{"invoiceId":"' + invoices[1].Id + '","category":"Quality","rootCause":"Quality Issue","priority":"Medium","amount":1500,"description":"Damaged goods"}' +
        ']';

        Test.startTest();
        List<ARF_Dispute__c> disputes = ARF_TransactionActionController.createBulkDisputesEnhanced(acct.Id, configJson);
        Test.stopTest();

        System.assertEquals(2, disputes.size(), 'Should create 2 disputes');
        Map<Id, ARF_Dispute__c> disputeMap = new Map<Id, ARF_Dispute__c>([
            SELECT Invoice__c, Category__c, Root_Cause__c, Priority__c, Dispute_Amount__c
            FROM ARF_Dispute__c WHERE Id IN :disputes
        ]);
        for (ARF_Dispute__c d : disputeMap.values()) {
            if (d.Invoice__c == invoices[0].Id) {
                System.assertEquals('Pricing', d.Category__c);
                System.assertEquals('High', d.Priority__c);
                System.assertEquals(5000, d.Dispute_Amount__c);
            }
        }
    }

    @isTest
    static void testCreateBulkDisputesEnhanced_SetsFlag() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();

        String configJson = '[{"invoiceId":"' + invoices[2].Id + '","category":"Delivery","priority":"Low","amount":2000,"description":"Late delivery"}]';

        Test.startTest();
        ARF_TransactionActionController.createBulkDisputesEnhanced(acct.Id, configJson);
        Test.stopTest();

        ARF_Invoice__c updated = [SELECT Has_Dispute__c FROM ARF_Invoice__c WHERE Id = :invoices[2].Id];
        System.assertEquals(true, updated.Has_Dispute__c, 'Has_Dispute__c should be set to true');
    }

    @isTest
    static void testCreateBulkDisputesEnhanced_InvalidJson() {
        Account acct = getTestAccount();
        Test.startTest();
        try {
            ARF_TransactionActionController.createBulkDisputesEnhanced(acct.Id, '');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ===== ENHANCED BULK PROMISE TESTS =====

    @isTest
    static void testCreateBulkPromisesEnhanced_PerInvoiceConfig() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();

        String configJson = '[' +
            '{"invoiceId":"' + invoices[0].Id + '","amount":3000,"promiseDate":"' + String.valueOf(Date.today().addDays(7)) + '","notes":"Will pay next week"},' +
            '{"invoiceId":"' + invoices[1].Id + '","amount":2000,"promiseDate":"' + String.valueOf(Date.today().addDays(14)) + '","notes":"Partial payment"}' +
        ']';

        Test.startTest();
        List<ARF_Promise_To_Pay__c> promises = ARF_TransactionActionController.createBulkPromisesEnhanced(acct.Id, configJson);
        Test.stopTest();

        System.assertEquals(2, promises.size(), 'Should create 2 promises');
        Decimal total = 0;
        for (ARF_Promise_To_Pay__c p : promises) total += p.Amount__c;
        System.assertEquals(5000, total, 'Total should be 5000');
    }

    @isTest
    static void testCreateBulkPromisesEnhanced_SetsFlag() {
        Account acct = getTestAccount();
        List<ARF_Invoice__c> invoices = getTestInvoices();

        String configJson = '[{"invoiceId":"' + invoices[0].Id + '","amount":5000,"promiseDate":"' + String.valueOf(Date.today().addDays(7)) + '"}]';

        Test.startTest();
        ARF_TransactionActionController.createBulkPromisesEnhanced(acct.Id, configJson);
        Test.stopTest();

        ARF_Invoice__c updated = [SELECT Has_Promise__c FROM ARF_Invoice__c WHERE Id = :invoices[0].Id];
        System.assertEquals(true, updated.Has_Promise__c, 'Has_Promise__c should be set to true');
    }

    @isTest
    static void testCreateBulkPromisesEnhanced_EmptyConfig() {
        Account acct = getTestAccount();
        Test.startTest();
        try {
            ARF_TransactionActionController.createBulkPromisesEnhanced(acct.Id, null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }
}
