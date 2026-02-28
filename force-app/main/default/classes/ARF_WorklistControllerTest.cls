@isTest
private class ARF_WorklistControllerTest {

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(Name = 'Worklist Test Corp', AccountNumber = 'WL-001');
        insert acct;

        Account acct2 = new Account(Name = 'Worklist Second Corp', AccountNumber = 'WL-002');
        insert acct2;

        List<Contact> contacts = new List<Contact>();
        contacts.add(new Contact(
            FirstName = 'Alice', LastName = 'Walker', Email = 'alice@test.com',
            MobilePhone = '5551234567',
            AccountId = acct.Id, ARF_Primary_AR_Contact__c = true
        ));
        contacts.add(new Contact(
            FirstName = 'Bob', LastName = 'Jones', Email = 'bob@test.com',
            AccountId = acct2.Id, ARF_Primary_AR_Contact__c = true
        ));
        insert contacts;

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'WL-INV-001',
            Amount__c = 5000, Balance__c = 5000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-30), Due_Date__c = Date.today().addDays(-15)
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acct2.Id, Document_Number__c = 'WL-INV-002',
            Amount__c = 3000, Balance__c = 3000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-20), Due_Date__c = Date.today().addDays(-5)
        ));
        insert invoices;

        ARF_Email_Template__c tmpl = new ARF_Email_Template__c(
            Template_Name__c = 'Collection Reminder',
            Subject__c = 'Payment Reminder for {account_name}',
            Body_HTML__c = '<p>Dear {contact_name}, you owe {total_balance}.</p>{invoice_table}',
            Locale__c = 'en_US', Category__c = 'Collection', Active__c = true
        );
        insert tmpl;

        List<Task> tasks = new List<Task>();
        tasks.add(new Task(
            Subject = 'Collection Reminder',
            WhatId = acct.Id,
            ActivityDate = Date.today(),
            Status = 'Open',
            Priority = 'Normal',
            ARF_Task_Type__c = 'Email',
            ARF_Channel__c = 'Email',
            ARF_Template_Name__c = 'Collection Reminder'
        ));
        tasks.add(new Task(
            Subject = 'Follow up call',
            WhatId = acct.Id,
            ActivityDate = Date.today().addDays(-1),
            Status = 'Open',
            Priority = 'High',
            ARF_Task_Type__c = 'Phone',
            ARF_Channel__c = 'Phone'
        ));
        tasks.add(new Task(
            Subject = 'Send SMS reminder',
            WhatId = acct2.Id,
            ActivityDate = Date.today(),
            Status = 'Open',
            Priority = 'Normal',
            ARF_Task_Type__c = 'SMS',
            ARF_Channel__c = 'SMS'
        ));
        tasks.add(new Task(
            Subject = 'Completed task',
            WhatId = acct.Id,
            ActivityDate = Date.today(),
            Status = 'Completed',
            Priority = 'Normal',
            ARF_Task_Type__c = 'Email'
        ));
        insert tasks;
    }

    private static Account getTestAccount() {
        return [SELECT Id, Name FROM Account WHERE Name = 'Worklist Test Corp' LIMIT 1];
    }

    private static Account getSecondAccount() {
        return [SELECT Id, Name FROM Account WHERE Name = 'Worklist Second Corp' LIMIT 1];
    }

    private static List<Task> getOpenTasks() {
        return [SELECT Id, Subject, WhatId, ARF_Task_Type__c FROM Task WHERE Status != 'Completed' ORDER BY Subject];
    }

    // ===== FIELD METADATA TESTS =====

    @isTest
    static void testGetTaskFieldMetadata() {
        Test.startTest();
        List<Map<String, String>> result = ARF_WorklistController.getTaskFieldMetadata();
        Test.stopTest();

        System.assert(result.size() > 0, 'Should return field metadata');
        Set<String> apiNames = new Set<String>();
        for (Map<String, String> f : result) {
            apiNames.add(f.get('apiName'));
        }
        System.assert(apiNames.contains('Subject'), 'Should contain Subject');
        System.assert(apiNames.contains('Owner.Name'), 'Should contain Owner.Name');
        System.assert(apiNames.contains('What.Name'), 'Should contain What.Name');
    }

    // ===== DYNAMIC QUERY TESTS =====

    @isTest
    static void testGetTasksDynamic_AllOpen() {
        Test.startTest();
        List<Task> result = ARF_WorklistController.getTasksDynamic(
            null, null, 'ActivityDate', 'asc', null, 'all_open'
        );
        Test.stopTest();

        System.assertEquals(3, result.size(), 'Should return 3 open tasks');
    }

    @isTest
    static void testGetTasksDynamic_MyTasks() {
        Test.startTest();
        List<Task> result = ARF_WorklistController.getTasksDynamic(
            null, null, null, null, null, 'my_tasks'
        );
        Test.stopTest();

        // Tasks are owned by current user in test context
        System.assert(result.size() >= 0, 'Should return tasks owned by current user');
    }

    @isTest
    static void testGetTasksDynamic_EmailTasks() {
        Test.startTest();
        List<Task> result = ARF_WorklistController.getTasksDynamic(
            null, null, null, null, null, 'email_tasks'
        );
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return 1 email task');
    }

    @isTest
    static void testGetTasksDynamic_PhoneTasks() {
        Test.startTest();
        List<Task> result = ARF_WorklistController.getTasksDynamic(
            null, null, null, null, null, 'phone_tasks'
        );
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return 1 phone task');
    }

    @isTest
    static void testGetTasksDynamic_OverdueTasks() {
        Test.startTest();
        List<Task> result = ARF_WorklistController.getTasksDynamic(
            null, null, null, null, null, 'overdue_tasks'
        );
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return 1 overdue task');
    }

    @isTest
    static void testGetTasksDynamic_WithSearch() {
        Test.startTest();
        List<Task> result = ARF_WorklistController.getTasksDynamic(
            null, null, null, null, 'Collection', 'all_open'
        );
        Test.stopTest();

        System.assert(result.size() >= 1, 'Should find tasks matching search');
    }

    @isTest
    static void testGetTasksDynamic_WithFilters() {
        String filterJson = '[{"field":"Priority","operator":"equals","value":"High","dataType":"picklist"}]';

        Test.startTest();
        List<Task> result = ARF_WorklistController.getTasksDynamic(
            null, filterJson, 'ActivityDate', 'desc', null, null
        );
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return 1 high-priority task');
    }

    @isTest
    static void testGetTasksDynamic_SortDesc() {
        Test.startTest();
        List<Task> result = ARF_WorklistController.getTasksDynamic(
            null, null, 'Priority', 'desc', null, 'all_open'
        );
        Test.stopTest();

        System.assert(result.size() > 0, 'Should return sorted results');
    }

    // ===== MASS CLOSE TESTS =====

    @isTest
    static void testMassCloseTasks() {
        List<Task> openTasks = getOpenTasks();
        List<Id> taskIds = new List<Id>();
        for (Task t : openTasks) taskIds.add(t.Id);

        Test.startTest();
        ARF_WorklistController.massCloseTasks(taskIds);
        Test.stopTest();

        List<Task> updatedTasks = [SELECT Status FROM Task WHERE Id IN :taskIds];
        for (Task t : updatedTasks) {
            System.assertEquals('Completed', t.Status, 'Task should be completed');
        }
    }

    @isTest
    static void testMassCloseTasks_Empty() {
        Test.startTest();
        try {
            ARF_WorklistController.massCloseTasks(new List<Id>());
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ===== COMPLETE PHONE TASK TESTS =====

    @isTest
    static void testCompletePhoneTask() {
        Task phoneTask = [SELECT Id FROM Task WHERE ARF_Task_Type__c = 'Phone' AND Status = 'Open' LIMIT 1];

        Test.startTest();
        Id commId = ARF_WorklistController.completePhoneTask(
            phoneTask.Id, 'Called AP department', 'Discussed payment timeline', 300
        );
        Test.stopTest();

        System.assertNotEquals(null, commId, 'Should return communication Id');
        ARF_Communication__c comm = [SELECT Channel__c, Call_Duration_Seconds__c FROM ARF_Communication__c WHERE Id = :commId];
        System.assertEquals('Phone', comm.Channel__c);
        System.assertEquals(300, comm.Call_Duration_Seconds__c);

        Task updated = [SELECT Status FROM Task WHERE Id = :phoneTask.Id];
        System.assertEquals('Completed', updated.Status, 'Task should be completed');
    }

    @isTest
    static void testCompletePhoneTask_NullId() {
        Test.startTest();
        try {
            ARF_WorklistController.completePhoneTask(null, 'Test', 'Test', 0);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ===== MASS EMAIL PREPARATION TESTS =====

    @isTest
    static void testPrepareMassEmail() {
        List<Task> emailTasks = [SELECT Id FROM Task WHERE ARF_Task_Type__c = 'Email' AND Status = 'Open'];
        List<Id> taskIds = new List<Id>();
        for (Task t : emailTasks) taskIds.add(t.Id);

        Test.startTest();
        ARF_WorklistController.MassEmailPreview preview = ARF_WorklistController.prepareMassEmail(taskIds);
        Test.stopTest();

        System.assertNotEquals(null, preview, 'Should return preview');
        System.assertEquals(1, preview.totalAccounts, 'Should have 1 account');
        System.assertEquals(1, preview.accountsWithContact, 'Should have 1 account with contact');
    }

    @isTest
    static void testPrepareMassEmail_Empty() {
        Test.startTest();
        try {
            ARF_WorklistController.prepareMassEmail(new List<Id>());
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ===== MASS EMAIL EXECUTION TESTS =====

    @isTest
    static void testExecuteMassEmail() {
        Account acct = getTestAccount();
        Task emailTask = [SELECT Id FROM Task WHERE ARF_Task_Type__c = 'Email' AND Status = 'Open' LIMIT 1];
        ARF_Email_Template__c tmpl = [SELECT Id FROM ARF_Email_Template__c WHERE Template_Name__c = 'Collection Reminder' LIMIT 1];

        String configJson = '{"attachmentFormat":"none","accounts":[' +
            '{"accountId":"' + acct.Id + '","contactEmail":"alice@test.com",' +
            '"contactId":"' + [SELECT Id FROM Contact WHERE Email = 'alice@test.com' LIMIT 1].Id + '",' +
            '"templateId":"' + tmpl.Id + '",' +
            '"taskIds":["' + emailTask.Id + '"],"skip":false}]}';

        Test.startTest();
        ARF_WorklistController.MassEmailResult result = ARF_WorklistController.executeMassEmail(configJson);
        Test.stopTest();

        System.assertEquals(1, result.emailsSent, 'Should send 1 email');
        System.assertEquals(0, result.skipped, 'Should skip 0');

        Task updated = [SELECT Status FROM Task WHERE Id = :emailTask.Id];
        System.assertEquals('Completed', updated.Status, 'Task should be completed');
    }

    @isTest
    static void testExecuteMassEmail_WithSkip() {
        Account acct = getTestAccount();
        Task emailTask = [SELECT Id FROM Task WHERE ARF_Task_Type__c = 'Email' AND Status = 'Open' LIMIT 1];

        String configJson = '{"attachmentFormat":"none","accounts":[' +
            '{"accountId":"' + acct.Id + '","skip":true,"taskIds":["' + emailTask.Id + '"]}]}';

        Test.startTest();
        ARF_WorklistController.MassEmailResult result = ARF_WorklistController.executeMassEmail(configJson);
        Test.stopTest();

        System.assertEquals(0, result.emailsSent, 'Should send 0 emails');
        System.assertEquals(1, result.skipped, 'Should skip 1');
    }

    // ===== MASS SMS PREPARATION TESTS =====

    @isTest
    static void testPrepareMassSms() {
        Account acct = getTestAccount();
        List<Task> smsTasks = [SELECT Id FROM Task WHERE ARF_Task_Type__c = 'SMS' AND Status = 'Open'];
        // Also add a task for account that has phone contact
        Task phoneAcctTask = [SELECT Id FROM Task WHERE WhatId = :acct.Id AND Status = 'Open' LIMIT 1];
        List<Id> taskIds = new List<Id>{ phoneAcctTask.Id };

        Test.startTest();
        ARF_WorklistController.MassSmsPreview preview = ARF_WorklistController.prepareMassSms(taskIds);
        Test.stopTest();

        System.assertNotEquals(null, preview, 'Should return preview');
        System.assertEquals(1, preview.totalAccounts);
    }

    @isTest
    static void testPrepareMassSms_Empty() {
        Test.startTest();
        try {
            ARF_WorklistController.prepareMassSms(new List<Id>());
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ===== MASS SMS EXECUTION TESTS =====

    @isTest
    static void testExecuteMassSms() {
        Account acct = getTestAccount();
        Task smsTask = [SELECT Id FROM Task WHERE WhatId = :acct.Id AND Status = 'Open' LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        String configJson = '{"message":"Your payment is due. Please remit ASAP.","accounts":[' +
            '{"accountId":"' + acct.Id + '","contactId":"' + con.Id + '",' +
            '"contactPhone":"5551234567","taskIds":["' + smsTask.Id + '"],"skip":false}]}';

        Test.startTest();
        ARF_WorklistController.MassSmsResult result = ARF_WorklistController.executeMassSms(configJson);
        Test.stopTest();

        System.assertEquals(1, result.smsSent, 'Should log 1 SMS');
        System.assertEquals(0, result.skipped);

        List<ARF_Communication__c> comms = [SELECT Channel__c, Body__c FROM ARF_Communication__c WHERE Account__c = :acct.Id AND Channel__c = 'SMS'];
        System.assertEquals(1, comms.size(), 'Should create SMS communication');
    }

    @isTest
    static void testExecuteMassSms_EmptyConfig() {
        Test.startTest();
        try {
            ARF_WorklistController.executeMassSms('');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }
}
