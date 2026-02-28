@isTest
private class ARF_CollectionWorklistControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create accounts with different AR profiles
        List<Account> accounts = new List<Account>();
        accounts.add(new Account(
            Name = 'High Priority Acct',
            ARF_Past_Due__c = 50000, ARF_Total_AR__c = 75000,
            ARF_Risk_Score__c = 80, ARF_Stop_Status__c = 'Active',
            ARF_Open_Invoice_Count__c = 5, ARF_Overdue_Invoice_Count__c = 3,
            ARF_Last_Contact_Date__c = Date.today().addDays(-30)
        ));
        accounts.add(new Account(
            Name = 'Medium Priority Acct',
            ARF_Past_Due__c = 20000, ARF_Total_AR__c = 30000,
            ARF_Risk_Score__c = 50, ARF_Stop_Status__c = 'Active',
            ARF_Open_Invoice_Count__c = 3, ARF_Overdue_Invoice_Count__c = 1,
            ARF_Last_Contact_Date__c = Date.today().addDays(-7)
        ));
        accounts.add(new Account(
            Name = 'Low Priority Acct',
            ARF_Past_Due__c = 5000, ARF_Total_AR__c = 10000,
            ARF_Risk_Score__c = 20, ARF_Stop_Status__c = 'Active',
            ARF_Open_Invoice_Count__c = 1, ARF_Overdue_Invoice_Count__c = 1,
            ARF_Last_Contact_Date__c = Date.today().addDays(-3)
        ));
        insert accounts;

        // Create overdue invoices for each account
        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        for (Account a : accounts) {
            invoices.add(new ARF_Invoice__c(
                Account__c = a.Id, Document_Number__c = 'WL-' + a.Name.left(3),
                Amount__c = a.ARF_Past_Due__c, Balance__c = a.ARF_Past_Due__c,
                Status__c = 'Open',
                Invoice_Date__c = Date.today().addDays(-45),
                Due_Date__c = Date.today().addDays(-15)
            ));
        }
        insert invoices;
    }

    @isTest
    static void testGetWorklistAll() {
        Test.startTest();
        List<ARF_WorklistPrioritizer.PrioritizedAccount> result =
            ARF_CollectionWorklistController.getWorklist(true);
        Test.stopTest();
        System.assert(result.size() >= 3, 'Should return all accounts with past due');
    }

    @isTest
    static void testGetWorklistMine() {
        Test.startTest();
        List<ARF_WorklistPrioritizer.PrioritizedAccount> result =
            ARF_CollectionWorklistController.getWorklist(false);
        Test.stopTest();
        // No accounts assigned to current user
        System.assertNotEquals(null, result, 'Should return a list');
    }

    @isTest
    static void testWorklistSortOrder() {
        Test.startTest();
        List<ARF_WorklistPrioritizer.PrioritizedAccount> result =
            ARF_CollectionWorklistController.getWorklist(true);
        Test.stopTest();

        if (result.size() >= 2) {
            System.assert(result[0].priorityScore >= result[1].priorityScore,
                'Should be sorted by priority descending');
        }
    }

    @isTest
    static void testSnoozeAccount() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'High Priority Acct' LIMIT 1];
        Test.startTest();
        ARF_CollectionWorklistController.snoozeAccount(acct.Id, 7);
        Test.stopTest();

        Account updated = [SELECT ARF_Last_Contact_Date__c FROM Account WHERE Id = :acct.Id];
        System.assertEquals(Date.today(), updated.ARF_Last_Contact_Date__c,
            'Last contact date should be set to today');
    }

    @isTest
    static void testSnoozeAccountNullId() {
        Test.startTest();
        try {
            ARF_CollectionWorklistController.snoozeAccount(null, 7);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testQuickLogCall() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'High Priority Acct' LIMIT 1];
        Test.startTest();
        ARF_Communication__c comm = ARF_CollectionWorklistController.quickLogCall(
            acct.Id, 'Collection Call', 'Discussed payment plan', 300
        );
        Test.stopTest();

        System.assertNotEquals(null, comm.Id, 'Communication should be created');
        ARF_Communication__c inserted = [
            SELECT Channel__c, Direction__c, Subject__c, Call_Duration_Seconds__c
            FROM ARF_Communication__c WHERE Id = :comm.Id
        ];
        System.assertEquals('Phone', inserted.Channel__c, 'Should be phone channel');
        System.assertEquals('Outbound', inserted.Direction__c, 'Should be outbound');
        System.assertEquals(300, inserted.Call_Duration_Seconds__c, 'Duration should match');
    }

    @isTest
    static void testQuickLogCallNullId() {
        Test.startTest();
        try {
            ARF_CollectionWorklistController.quickLogCall(null, 'Test', 'Body', 60);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testReassignAccount() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'High Priority Acct' LIMIT 1];
        Id currentUserId = UserInfo.getUserId();
        Test.startTest();
        ARF_CollectionWorklistController.reassignAccount(acct.Id, currentUserId);
        Test.stopTest();

        Account updated = [SELECT ARF_Assigned_Collector__c FROM Account WHERE Id = :acct.Id];
        System.assertEquals(currentUserId, updated.ARF_Assigned_Collector__c,
            'Collector should be updated');
    }

    @isTest
    static void testPriorityScoreCalculation() {
        Decimal score = ARF_WorklistPrioritizer.calculateScore(50000, 30, 80, Date.today().addDays(-14));
        System.assert(score > 0, 'Score should be positive for past due account');

        Decimal zeroScore = ARF_WorklistPrioritizer.calculateScore(0, 30, 80, Date.today());
        System.assertEquals(0, zeroScore, 'Score should be 0 for no past due');

        Decimal nullScore = ARF_WorklistPrioritizer.calculateScore(null, null, null, null);
        System.assertEquals(0, nullScore, 'Score should be 0 for null inputs');
    }
}
