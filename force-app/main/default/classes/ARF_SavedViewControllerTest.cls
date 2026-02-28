@isTest
private class ARF_SavedViewControllerTest {

    @TestSetup
    static void setupTestData() {
        Account testAccount = new Account(
            Name = 'Test Saved View Account',
            ARF_Total_AR__c = 50000,
            ARF_Past_Due__c = 15000,
            ARF_Credit_Limit__c = 100000,
            ARF_Risk_Score__c = 65
        );
        insert testAccount;

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = testAccount.Id,
            Document_Number__c = 'INV-SV-001',
            Amount__c = 10000,
            Balance__c = 10000,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-30),
            Due_Date__c = Date.today().addDays(-5),
            PO_Number__c = 'PO-100',
            Reference__c = 'REF-A',
            Bill_To__c = '123 Main St'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = testAccount.Id,
            Document_Number__c = 'INV-SV-002',
            Amount__c = 5000,
            Balance__c = 2500,
            Status__c = 'Partially Paid',
            Invoice_Date__c = Date.today().addDays(-60),
            Due_Date__c = Date.today().addDays(-30),
            PO_Number__c = 'PO-200',
            Reference__c = 'REF-B'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = testAccount.Id,
            Document_Number__c = 'INV-SV-003',
            Amount__c = 8000,
            Balance__c = 8000,
            Status__c = 'In Dispute',
            Invoice_Date__c = Date.today().addDays(-10),
            Due_Date__c = Date.today().addDays(20),
            Has_Dispute__c = true
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = testAccount.Id,
            Document_Number__c = 'INV-SV-004',
            Amount__c = 3000,
            Balance__c = 0,
            Status__c = 'Paid',
            Invoice_Date__c = Date.today().addDays(-90),
            Due_Date__c = Date.today().addDays(-60)
        ));
        insert invoices;
    }

    static Account getTestAccount() {
        return [SELECT Id FROM Account WHERE Name = 'Test Saved View Account' LIMIT 1];
    }

    // ===== FIELD METADATA TESTS =====

    @isTest
    static void testGetInvoiceFieldMetadata() {
        Test.startTest();
        List<Map<String, String>> fields = ARF_SavedViewController.getInvoiceFieldMetadata();
        Test.stopTest();

        System.assert(fields.size() >= 15, 'Should return at least 15 fields');

        Map<String, String> firstField = fields[0];
        System.assertEquals('Document_Number__c', firstField.get('apiName'));
        System.assertEquals('Invoice #', firstField.get('label'));
        System.assertEquals('text', firstField.get('dataType'));
    }

    // ===== VIEW CRUD TESTS =====

    @isTest
    static void testGetMyViews_NoViews() {
        Test.startTest();
        List<ARF_Saved_View__c> views = ARF_SavedViewController.getMyViews('ARF_Invoice__c');
        Test.stopTest();

        System.assertEquals(0, views.size(), 'Should return no views initially');
    }

    @isTest
    static void testGetMyViews_WithViews() {
        ARF_Saved_View__c view1 = new ARF_Saved_View__c(
            View_Name__c = 'My View A',
            Object_Name__c = 'ARF_Invoice__c',
            Column_Config__c = '["Document_Number__c","Balance__c"]',
            Is_Default__c = false
        );
        ARF_Saved_View__c view2 = new ARF_Saved_View__c(
            View_Name__c = 'My View B',
            Object_Name__c = 'ARF_Invoice__c',
            Column_Config__c = '["Document_Number__c","Amount__c"]',
            Is_Default__c = true
        );
        insert new List<ARF_Saved_View__c>{ view1, view2 };

        Test.startTest();
        List<ARF_Saved_View__c> views = ARF_SavedViewController.getMyViews('ARF_Invoice__c');
        Test.stopTest();

        System.assertEquals(2, views.size(), 'Should return 2 views');
        System.assertEquals(true, views[0].Is_Default__c, 'Default view should be first');
    }

    @isTest
    static void testGetMyViews_NullObjectName() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ARF_SavedViewController.getMyViews(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw exception for null object name');
    }

    @isTest
    static void testSaveView_CreateNew() {
        ARF_Saved_View__c view = new ARF_Saved_View__c(
            View_Name__c = 'New Test View',
            Object_Name__c = 'ARF_Invoice__c',
            Column_Config__c = '["Document_Number__c","Balance__c","Status__c"]',
            Filter_Config__c = '[{"field":"Status__c","operator":"equals","value":"Open","dataType":"picklist"}]',
            Sort_Field__c = 'Balance__c',
            Sort_Direction__c = 'desc',
            Is_Default__c = false
        );

        Test.startTest();
        ARF_Saved_View__c saved = ARF_SavedViewController.saveView(view);
        Test.stopTest();

        System.assertNotEquals(null, saved.Id, 'View should be saved with an Id');
        System.assertEquals('New Test View', saved.View_Name__c);
    }

    @isTest
    static void testSaveView_UpdateExisting() {
        ARF_Saved_View__c view = new ARF_Saved_View__c(
            View_Name__c = 'Original Name',
            Object_Name__c = 'ARF_Invoice__c',
            Column_Config__c = '["Document_Number__c"]'
        );
        insert view;

        view.View_Name__c = 'Updated Name';
        view.Column_Config__c = '["Document_Number__c","Balance__c"]';

        Test.startTest();
        ARF_Saved_View__c updated = ARF_SavedViewController.saveView(view);
        Test.stopTest();

        ARF_Saved_View__c reloaded = [SELECT View_Name__c, Column_Config__c FROM ARF_Saved_View__c WHERE Id = :view.Id];
        System.assertEquals('Updated Name', reloaded.View_Name__c);
    }

    @isTest
    static void testSaveView_SetDefaultClearsPrevious() {
        ARF_Saved_View__c view1 = new ARF_Saved_View__c(
            View_Name__c = 'View 1',
            Object_Name__c = 'ARF_Invoice__c',
            Column_Config__c = '["Document_Number__c"]',
            Is_Default__c = true
        );
        insert view1;

        ARF_Saved_View__c view2 = new ARF_Saved_View__c(
            View_Name__c = 'View 2',
            Object_Name__c = 'ARF_Invoice__c',
            Column_Config__c = '["Balance__c"]',
            Is_Default__c = true
        );

        Test.startTest();
        ARF_SavedViewController.saveView(view2);
        Test.stopTest();

        ARF_Saved_View__c reloaded1 = [SELECT Is_Default__c FROM ARF_Saved_View__c WHERE Id = :view1.Id];
        System.assertEquals(false, reloaded1.Is_Default__c, 'Previous default should be cleared');
    }

    @isTest
    static void testSaveView_Null() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ARF_SavedViewController.saveView(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for null view');
    }

    @isTest
    static void testDeleteView_Success() {
        ARF_Saved_View__c view = new ARF_Saved_View__c(
            View_Name__c = 'To Delete',
            Object_Name__c = 'ARF_Invoice__c',
            Column_Config__c = '["Document_Number__c"]'
        );
        insert view;

        Test.startTest();
        ARF_SavedViewController.deleteView(view.Id);
        Test.stopTest();

        List<ARF_Saved_View__c> remaining = [SELECT Id FROM ARF_Saved_View__c WHERE Id = :view.Id];
        System.assertEquals(0, remaining.size(), 'View should be deleted');
    }

    @isTest
    static void testDeleteView_NullId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ARF_SavedViewController.deleteView(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for null view Id');
    }

    @isTest
    static void testSetDefaultView() {
        ARF_Saved_View__c view1 = new ARF_Saved_View__c(
            View_Name__c = 'View A',
            Object_Name__c = 'ARF_Invoice__c',
            Column_Config__c = '["Document_Number__c"]',
            Is_Default__c = true
        );
        ARF_Saved_View__c view2 = new ARF_Saved_View__c(
            View_Name__c = 'View B',
            Object_Name__c = 'ARF_Invoice__c',
            Column_Config__c = '["Balance__c"]',
            Is_Default__c = false
        );
        insert new List<ARF_Saved_View__c>{ view1, view2 };

        Test.startTest();
        ARF_SavedViewController.setDefaultView(view2.Id);
        Test.stopTest();

        ARF_Saved_View__c reloaded1 = [SELECT Is_Default__c FROM ARF_Saved_View__c WHERE Id = :view1.Id];
        ARF_Saved_View__c reloaded2 = [SELECT Is_Default__c FROM ARF_Saved_View__c WHERE Id = :view2.Id];
        System.assertEquals(false, reloaded1.Is_Default__c, 'Old default should be cleared');
        System.assertEquals(true, reloaded2.Is_Default__c, 'New default should be set');
    }

    @isTest
    static void testSetDefaultView_NullId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ARF_SavedViewController.setDefaultView(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for null Id');
    }

    // ===== DYNAMIC QUERY TESTS =====

    @isTest
    static void testGetInvoicesDynamic_BasicQuery() {
        Account acct = getTestAccount();
        List<String> fields = new List<String>{
            'Document_Number__c', 'Balance__c', 'Status__c'
        };

        Test.startTest();
        List<ARF_Invoice__c> results = ARF_SavedViewController.getInvoicesDynamic(
            acct.Id, fields, null, null, null, null
        );
        Test.stopTest();

        // Should return 3 active invoices (excludes Paid)
        System.assertEquals(3, results.size(), 'Should return 3 active invoices');
    }

    @isTest
    static void testGetInvoicesDynamic_WithStatusFilter() {
        Account acct = getTestAccount();
        List<String> fields = new List<String>{ 'Document_Number__c', 'Status__c' };
        String filterJson = '[{"field":"Status__c","operator":"equals","value":"Open","dataType":"picklist"}]';

        Test.startTest();
        List<ARF_Invoice__c> results = ARF_SavedViewController.getInvoicesDynamic(
            acct.Id, fields, filterJson, null, null, null
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 Open invoice');
        System.assertEquals('Open', results[0].Status__c);
    }

    @isTest
    static void testGetInvoicesDynamic_WithCurrencyFilter() {
        Account acct = getTestAccount();
        List<String> fields = new List<String>{ 'Document_Number__c', 'Balance__c' };
        String filterJson = '[{"field":"Balance__c","operator":"greaterThan","value":"5000","dataType":"currency"}]';

        Test.startTest();
        List<ARF_Invoice__c> results = ARF_SavedViewController.getInvoicesDynamic(
            acct.Id, fields, filterJson, null, null, null
        );
        Test.stopTest();

        for (ARF_Invoice__c inv : results) {
            System.assert(inv.Balance__c > 5000, 'Balance should be > 5000');
        }
    }

    @isTest
    static void testGetInvoicesDynamic_WithDateFilter() {
        Account acct = getTestAccount();
        List<String> fields = new List<String>{ 'Document_Number__c', 'Due_Date__c' };
        String filterJson = '[{"field":"Due_Date__c","operator":"lessThan","value":"' +
            String.valueOf(Date.today()) + '","dataType":"date"}]';

        Test.startTest();
        List<ARF_Invoice__c> results = ARF_SavedViewController.getInvoicesDynamic(
            acct.Id, fields, filterJson, null, null, null
        );
        Test.stopTest();

        for (ARF_Invoice__c inv : results) {
            System.assert(inv.Due_Date__c < Date.today(), 'Due date should be before today');
        }
    }

    @isTest
    static void testGetInvoicesDynamic_WithBooleanFilter() {
        Account acct = getTestAccount();
        List<String> fields = new List<String>{ 'Document_Number__c', 'Has_Dispute__c' };
        String filterJson = '[{"field":"Has_Dispute__c","operator":"equals","value":"true","dataType":"boolean"}]';

        Test.startTest();
        List<ARF_Invoice__c> results = ARF_SavedViewController.getInvoicesDynamic(
            acct.Id, fields, filterJson, null, null, null
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 disputed invoice');
    }

    @isTest
    static void testGetInvoicesDynamic_WithContainsFilter() {
        Account acct = getTestAccount();
        List<String> fields = new List<String>{ 'Document_Number__c', 'PO_Number__c' };
        String filterJson = '[{"field":"PO_Number__c","operator":"contains","value":"PO-1","dataType":"text"}]';

        Test.startTest();
        List<ARF_Invoice__c> results = ARF_SavedViewController.getInvoicesDynamic(
            acct.Id, fields, filterJson, null, null, null
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 invoice with PO-100');
    }

    @isTest
    static void testGetInvoicesDynamic_WithSearch() {
        Account acct = getTestAccount();
        List<String> fields = new List<String>{ 'Document_Number__c', 'Balance__c' };

        Test.startTest();
        List<ARF_Invoice__c> results = ARF_SavedViewController.getInvoicesDynamic(
            acct.Id, fields, null, null, null, 'INV-SV-001'
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 invoice matching search');
    }

    @isTest
    static void testGetInvoicesDynamic_WithSort() {
        Account acct = getTestAccount();
        List<String> fields = new List<String>{ 'Document_Number__c', 'Balance__c' };

        Test.startTest();
        List<ARF_Invoice__c> results = ARF_SavedViewController.getInvoicesDynamic(
            acct.Id, fields, null, 'Balance__c', 'desc', null
        );
        Test.stopTest();

        if (results.size() >= 2) {
            System.assert(results[0].Balance__c >= results[1].Balance__c,
                'Results should be sorted by Balance desc');
        }
    }

    @isTest
    static void testGetInvoicesDynamic_InvalidField() {
        Account acct = getTestAccount();
        List<String> fields = new List<String>{ 'Document_Number__c', 'Fake_Field__c' };

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ARF_SavedViewController.getInvoicesDynamic(
                acct.Id, fields, null, null, null, null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for invalid field name');
    }

    @isTest
    static void testGetInvoicesDynamic_NullAccountId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ARF_SavedViewController.getInvoicesDynamic(
                null, new List<String>{ 'Document_Number__c' }, null, null, null, null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for null account Id');
    }

    @isTest
    static void testGetInvoicesDynamic_MultipleFilters() {
        Account acct = getTestAccount();
        List<String> fields = new List<String>{
            'Document_Number__c', 'Balance__c', 'Status__c', 'Due_Date__c'
        };
        String filterJson = '[' +
            '{"field":"Balance__c","operator":"greaterOrEqual","value":"2500","dataType":"currency"},' +
            '{"field":"Status__c","operator":"notEquals","value":"In Dispute","dataType":"picklist"}' +
        ']';

        Test.startTest();
        List<ARF_Invoice__c> results = ARF_SavedViewController.getInvoicesDynamic(
            acct.Id, fields, filterJson, 'Balance__c', 'asc', null
        );
        Test.stopTest();

        for (ARF_Invoice__c inv : results) {
            System.assert(inv.Balance__c >= 2500, 'Balance should be >= 2500');
            System.assertNotEquals('In Dispute', inv.Status__c);
        }
    }

    @isTest
    static void testGetInvoicesDynamic_NullFields() {
        Account acct = getTestAccount();

        Test.startTest();
        List<ARF_Invoice__c> results = ARF_SavedViewController.getInvoicesDynamic(
            acct.Id, null, null, null, null, null
        );
        Test.stopTest();

        System.assert(results.size() > 0, 'Should return invoices with default Id field');
    }

    @isTest
    static void testGetInvoicesDynamic_InvalidFilterField() {
        Account acct = getTestAccount();
        List<String> fields = new List<String>{ 'Document_Number__c' };
        String filterJson = '[{"field":"Hacked_Field__c","operator":"equals","value":"x","dataType":"text"}]';

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ARF_SavedViewController.getInvoicesDynamic(
                acct.Id, fields, filterJson, null, null, null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for invalid filter field');
    }

    @isTest
    static void testGetInvoicesDynamic_LessThanEqualOperators() {
        Account acct = getTestAccount();
        List<String> fields = new List<String>{ 'Document_Number__c', 'Balance__c' };
        String filterJson = '[{"field":"Balance__c","operator":"lessOrEqual","value":"5000","dataType":"currency"}]';

        Test.startTest();
        List<ARF_Invoice__c> results = ARF_SavedViewController.getInvoicesDynamic(
            acct.Id, fields, filterJson, null, null, null
        );
        Test.stopTest();

        for (ARF_Invoice__c inv : results) {
            System.assert(inv.Balance__c <= 5000, 'Balance should be <= 5000');
        }
    }
}
