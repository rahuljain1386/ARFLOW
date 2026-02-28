@isTest
private class ARF_PromiseTrackerTest {

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(Name = 'Promise Tracker Test Account');
        insert acct;

        ARF_Invoice__c inv = new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'PT-001',
            Amount__c = 10000, Balance__c = 10000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-30),
            Due_Date__c = Date.today().addDays(-5)
        );
        insert inv;

        List<ARF_Promise_To_Pay__c> promises = new List<ARF_Promise_To_Pay__c>();
        // Promise A: Broken (past date, no payment)
        promises.add(new ARF_Promise_To_Pay__c(
            Account__c = acct.Id, Invoice__c = inv.Id,
            Amount__c = 5000, Amount_Received__c = 0,
            Promise_Date__c = Date.today().addDays(-1),
            Status__c = 'Open', Broken_Count__c = 0
        ));
        // Promise B: Partially Kept (past date, partial payment)
        promises.add(new ARF_Promise_To_Pay__c(
            Account__c = acct.Id, Invoice__c = inv.Id,
            Amount__c = 3000, Amount_Received__c = 1500,
            Promise_Date__c = Date.today().addDays(-1),
            Status__c = 'Open', Broken_Count__c = 0
        ));
        // Promise C: Kept (fully paid)
        promises.add(new ARF_Promise_To_Pay__c(
            Account__c = acct.Id,
            Amount__c = 2000, Amount_Received__c = 2000,
            Promise_Date__c = Date.today().addDays(5),
            Status__c = 'Open', Broken_Count__c = 0
        ));
        // Promise D: Future (not yet due)
        promises.add(new ARF_Promise_To_Pay__c(
            Account__c = acct.Id,
            Amount__c = 4000, Amount_Received__c = 0,
            Promise_Date__c = Date.today().addDays(10),
            Status__c = 'Open', Broken_Count__c = 0
        ));
        insert promises;

        // Paused strategy execution
        ARF_Collection_Strategy__c strategy = new ARF_Collection_Strategy__c(
            Strategy_Name__c = 'Test Strategy', Strategy_Type__c = 'Standard',
            Active__c = true, Total_Steps__c = 3
        );
        insert strategy;

        ARF_Strategy_Execution__c exec = new ARF_Strategy_Execution__c(
            Account__c = acct.Id, Strategy__c = strategy.Id,
            Status__c = 'Paused', Current_Step__c = 2,
            Pause_Reason__c = 'Promise Made',
            Next_Action_Date__c = Date.today()
        );
        insert exec;
    }

    private static List<ARF_Promise_To_Pay__c> getPromises() {
        return [
            SELECT Id, Amount__c, Amount_Received__c, Status__c, Broken_Count__c
            FROM ARF_Promise_To_Pay__c
            ORDER BY Amount__c ASC
        ];
    }

    @isTest
    static void testBrokenPromise() {
        Test.startTest();
        Database.executeBatch(new ARF_PromiseTracker(), 200);
        Test.stopTest();

        ARF_Promise_To_Pay__c broken = [
            SELECT Status__c, Broken_Count__c FROM ARF_Promise_To_Pay__c
            WHERE Amount__c = 5000
        ];
        System.assertEquals('Broken', broken.Status__c, 'Should be marked Broken');
        System.assertEquals(1, broken.Broken_Count__c, 'Broken count should increment');

        List<Task> tasks = [SELECT Subject FROM Task WHERE Subject LIKE 'Broken Promise%'];
        System.assert(tasks.size() > 0, 'Should create follow-up task');
    }

    @isTest
    static void testPartiallyKeptPromise() {
        Test.startTest();
        Database.executeBatch(new ARF_PromiseTracker(), 200);
        Test.stopTest();

        ARF_Promise_To_Pay__c partial = [
            SELECT Status__c, Broken_Count__c FROM ARF_Promise_To_Pay__c
            WHERE Amount__c = 3000
        ];
        System.assertEquals('Partially Kept', partial.Status__c, 'Should be marked Partially Kept');
        System.assertEquals(1, partial.Broken_Count__c, 'Broken count should increment');
    }

    @isTest
    static void testKeptPromise() {
        Test.startTest();
        Database.executeBatch(new ARF_PromiseTracker(), 200);
        Test.stopTest();

        ARF_Promise_To_Pay__c kept = [
            SELECT Status__c FROM ARF_Promise_To_Pay__c
            WHERE Amount__c = 2000
        ];
        System.assertEquals('Kept', kept.Status__c, 'Should be marked Kept');
    }

    @isTest
    static void testFuturePromiseUnchanged() {
        Test.startTest();
        Database.executeBatch(new ARF_PromiseTracker(), 200);
        Test.stopTest();

        ARF_Promise_To_Pay__c future = [
            SELECT Status__c FROM ARF_Promise_To_Pay__c
            WHERE Amount__c = 4000
        ];
        System.assertEquals('Open', future.Status__c, 'Future promise should stay Open');
    }

    @isTest
    static void testStrategyResumption() {
        Test.startTest();
        Database.executeBatch(new ARF_PromiseTracker(), 200);
        Test.stopTest();

        ARF_Strategy_Execution__c exec = [
            SELECT Status__c, Pause_Reason__c
            FROM ARF_Strategy_Execution__c
            WHERE Account__r.Name = 'Promise Tracker Test Account'
        ];
        System.assertEquals('Active', exec.Status__c, 'Should resume strategy');
        System.assertEquals(null, exec.Pause_Reason__c, 'Pause reason should be cleared');
    }

    @isTest
    static void testSchedulableInterface() {
        Test.startTest();
        String jobId = System.schedule('Test Promise Tracker', '0 0 7 * * ?', new ARF_PromiseTracker());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Job should be scheduled');
    }
}
