@IsTest
private class ARF_RetellAutoCallerTest {

    @TestSetup
    static void setupTestData() {
        ARF_Retell_Config__c config = ARF_Retell_Config__c.getOrgDefaults();
        config.API_Key__c = 'test-retell-key';
        config.Agent_ID__c = 'agent_test_123';
        config.From_Number__c = '+15005550006';
        config.Webhook_Base_URL__c = 'https://test.salesforce-sites.com';
        upsert config;

        // Eligible account
        Account eligible = new Account(
            Name = 'Eligible Corp',
            Phone = '+14155551111',
            ARF_Past_Due__c = 5000,
            ARF_Stop_Status__c = 'Active'
        );
        insert eligible;

        Contact eligibleContact = new Contact(
            FirstName = 'Jane',
            LastName = 'Doe',
            AccountId = eligible.Id,
            MobilePhone = '+14155552222'
        );
        insert eligibleContact;

        // Phone task for eligible account
        Task phoneTask = new Task(
            Subject = 'Collection Call',
            WhatId = eligible.Id,
            Status = 'Open',
            ARF_Task_Type__c = 'Phone',
            ActivityDate = Date.today()
        );
        insert phoneTask;

        // Account on hold
        Account holdAccount = new Account(
            Name = 'Hold Corp',
            Phone = '+14155553333',
            ARF_Past_Due__c = 3000,
            ARF_Stop_Status__c = 'Stop'
        );
        insert holdAccount;

        Task holdTask = new Task(
            Subject = 'Collection Call Hold',
            WhatId = holdAccount.Id,
            Status = 'Open',
            ARF_Task_Type__c = 'Phone',
            ActivityDate = Date.today()
        );
        insert holdTask;

        // Account with no past due
        Account noPastDue = new Account(
            Name = 'Current Corp',
            Phone = '+14155554444',
            ARF_Past_Due__c = 0,
            ARF_Stop_Status__c = 'Active'
        );
        insert noPastDue;

        Task noPastDueTask = new Task(
            Subject = 'Collection Call No PD',
            WhatId = noPastDue.Id,
            Status = 'Open',
            ARF_Task_Type__c = 'Phone',
            ActivityDate = Date.today()
        );
        insert noPastDueTask;

        // Account contacted today
        Account contactedToday = new Account(
            Name = 'Already Called Corp',
            Phone = '+14155555555',
            ARF_Past_Due__c = 2000,
            ARF_Stop_Status__c = 'Active',
            ARF_Last_Contact_Date__c = Date.today()
        );
        insert contactedToday;

        Task contactedTodayTask = new Task(
            Subject = 'Collection Call Today',
            WhatId = contactedToday.Id,
            Status = 'Open',
            ARF_Task_Type__c = 'Phone',
            ActivityDate = Date.today()
        );
        insert contactedTodayTask;
    }

    @IsTest
    static void testBatchProcessesEligibleAccount() {
        Test.setMock(HttpCalloutMock.class, new MockRetellSuccess());
        Test.startTest();
        Database.executeBatch(new ARF_RetellAutoCaller(), 200);
        Test.stopTest();

        // Eligible account should have a Communication record
        Account eligible = [SELECT Id FROM Account WHERE Name = 'Eligible Corp'];
        List<ARF_Communication__c> comms = [
            SELECT Status__c, Channel__c FROM ARF_Communication__c
            WHERE Account__c = :eligible.Id AND Channel__c = 'Phone'
        ];
        System.assert(comms.size() > 0, 'Should have created a Communication for eligible account');
    }

    @IsTest
    static void testBatchSkipsHoldAccount() {
        Test.setMock(HttpCalloutMock.class, new MockRetellSuccess());
        Test.startTest();
        Database.executeBatch(new ARF_RetellAutoCaller(), 200);
        Test.stopTest();

        Account holdAcct = [SELECT Id FROM Account WHERE Name = 'Hold Corp'];
        List<ARF_Communication__c> comms = [
            SELECT Id FROM ARF_Communication__c
            WHERE Account__c = :holdAcct.Id AND Channel__c = 'Phone'
        ];
        System.assertEquals(0, comms.size(), 'Should not call account on hold');
    }

    @IsTest
    static void testBatchSkipsNoPastDue() {
        Test.setMock(HttpCalloutMock.class, new MockRetellSuccess());
        Test.startTest();
        Database.executeBatch(new ARF_RetellAutoCaller(), 200);
        Test.stopTest();

        Account noPD = [SELECT Id FROM Account WHERE Name = 'Current Corp'];
        List<ARF_Communication__c> comms = [
            SELECT Id FROM ARF_Communication__c
            WHERE Account__c = :noPD.Id AND Channel__c = 'Phone'
        ];
        System.assertEquals(0, comms.size(), 'Should not call account with no past due');
    }

    @IsTest
    static void testBatchSkipsContactedToday() {
        Test.setMock(HttpCalloutMock.class, new MockRetellSuccess());
        Test.startTest();
        Database.executeBatch(new ARF_RetellAutoCaller(), 200);
        Test.stopTest();

        Account called = [SELECT Id FROM Account WHERE Name = 'Already Called Corp'];
        List<ARF_Communication__c> comms = [
            SELECT Id FROM ARF_Communication__c
            WHERE Account__c = :called.Id AND Channel__c = 'Phone'
        ];
        System.assertEquals(0, comms.size(), 'Should not call account already contacted today');
    }

    @IsTest
    static void testSchedulableExecutesBatch() {
        // Delete all but one task so batch size 1 works in test context
        List<Task> tasks = [SELECT Id FROM Task WHERE ARF_Task_Type__c = 'Phone'];
        if (tasks.size() > 1) {
            List<Task> toDelete = new List<Task>();
            for (Integer i = 1; i < tasks.size(); i++) {
                toDelete.add(tasks[i]);
            }
            delete toDelete;
        }
        Test.setMock(HttpCalloutMock.class, new MockRetellSuccess());
        Test.startTest();
        new ARF_RetellAutoCaller().execute((SchedulableContext) null);
        Test.stopTest();
        // No exception = success
    }

    @IsTest
    static void testResolvePhone_priority() {
        Account acct = new Account(Name = 'Phone Test', Phone = '+14155550000');
        Contact c = new Contact(
            FirstName = 'Test', LastName = 'Contact',
            MobilePhone = '+14155551111',
            Phone = '+14155552222'
        );

        // MobilePhone takes priority
        String phone = ARF_RetellAutoCaller.resolvePhone(c, acct);
        System.assertEquals('+14155551111', phone);

        // Falls back to Contact.Phone
        c.MobilePhone = null;
        phone = ARF_RetellAutoCaller.resolvePhone(c, acct);
        System.assertEquals('+14155552222', phone);

        // Falls back to Account.Phone
        phone = ARF_RetellAutoCaller.resolvePhone(null, acct);
        System.assertEquals('+14155550000', phone);

        // Returns null if nothing
        phone = ARF_RetellAutoCaller.resolvePhone(null, new Account(Name = 'No Phone'));
        System.assertEquals(null, phone);
    }

    @IsTest
    static void testBatchSkipsWhenNotConfigured() {
        // Clear config
        ARF_Retell_Config__c config = ARF_Retell_Config__c.getOrgDefaults();
        config.API_Key__c = '';
        upsert config;

        Test.startTest();
        Database.executeBatch(new ARF_RetellAutoCaller(), 200);
        Test.stopTest();

        // No comms should be created
        List<ARF_Communication__c> comms = [
            SELECT Id FROM ARF_Communication__c WHERE Channel__c = 'Phone'
        ];
        System.assertEquals(0, comms.size(), 'Should not create calls when not configured');
    }

    // ===== MOCK =====

    private class MockRetellSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"call_id":"call_batch_test_123","agent_id":"agent_test","from_number":"+15005550006"}');
            return res;
        }
    }
}
