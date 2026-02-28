@isTest
private class ARF_DunningEngineTest {

    private static String buildStepsJson(Integer numSteps) {
        List<String> steps = new List<String>();
        for (Integer i = 1; i <= numSteps; i++) {
            String action = (i == 1) ? 'Email' : (i == 2) ? 'Task' : 'Escalate';
            String channel = (action == 'Email') ? 'Email' : (action == 'Task') ? 'Phone' : 'Note';
            steps.add('{' +
                '"stepNumber":' + i + ',' +
                '"name":"Step ' + i + '",' +
                '"dayOffset":' + (i * 7) + ',' +
                '"action":"' + action + '",' +
                '"channel":"' + channel + '",' +
                '"subject":"Step ' + i + ' Subject",' +
                '"body":"Step ' + i + ' body",' +
                '"escalateTo":null,' +
                '"createTask":' + (i == 1 ? 'true' : 'false') + ',' +
                '"taskSubject":"Task for step ' + i + '",' +
                '"skipIfPromise":true,' +
                '"skipIfDispute":true' +
            '}');
        }
        return '{"steps":[' + String.join(steps, ',') + ']}';
    }

    @TestSetup
    static void setupTestData() {
        // Normal account with active strategy
        Account acct = new Account(Name = 'Dunning Test Account', ARF_Stop_Status__c = 'Active');
        insert acct;

        Contact con = new Contact(
            FirstName = 'AR', LastName = 'Contact', AccountId = acct.Id,
            Email = 'ar@test.com', ARF_Primary_AR_Contact__c = true
        );
        insert con;

        ARF_Invoice__c inv = new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'DUN-001',
            Amount__c = 10000, Balance__c = 10000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-30),
            Due_Date__c = Date.today().addDays(-15)
        );
        insert inv;

        ARF_Collection_Strategy__c strategy = new ARF_Collection_Strategy__c(
            Strategy_Name__c = 'Test Dunning Strategy',
            Strategy_Type__c = 'Standard',
            Active__c = true,
            Total_Steps__c = 3,
            Steps_JSON__c = buildStepsJson(3)
        );
        insert strategy;

        // Execution at step 1, due today
        ARF_Strategy_Execution__c exec = new ARF_Strategy_Execution__c(
            Account__c = acct.Id,
            Strategy__c = strategy.Id,
            Status__c = 'Active',
            Current_Step__c = 1,
            Next_Action_Date__c = Date.today()
        );
        insert exec;

        // Account with dispute (for pause test)
        Account disputeAcct = new Account(
            Name = 'Dispute Dunning Account',
            ARF_Stop_Status__c = 'Active',
            ARF_Open_Dispute_Count__c = 2
        );
        insert disputeAcct;

        ARF_Strategy_Execution__c disputeExec = new ARF_Strategy_Execution__c(
            Account__c = disputeAcct.Id,
            Strategy__c = strategy.Id,
            Status__c = 'Active',
            Current_Step__c = 1,
            Next_Action_Date__c = Date.today()
        );
        insert disputeExec;

        // Account with promise (for pause test)
        Account promiseAcct = new Account(Name = 'Promise Dunning Account', ARF_Stop_Status__c = 'Active');
        insert promiseAcct;

        ARF_Promise_To_Pay__c ptp = new ARF_Promise_To_Pay__c(
            Account__c = promiseAcct.Id,
            Amount__c = 5000,
            Promise_Date__c = Date.today().addDays(7),
            Status__c = 'Open'
        );
        insert ptp;

        ARF_Strategy_Execution__c promiseExec = new ARF_Strategy_Execution__c(
            Account__c = promiseAcct.Id,
            Strategy__c = strategy.Id,
            Status__c = 'Active',
            Current_Step__c = 1,
            Next_Action_Date__c = Date.today()
        );
        insert promiseExec;

        // Account with Stop status
        Account stopAcct = new Account(Name = 'Stop Dunning Account', ARF_Stop_Status__c = 'Stop');
        insert stopAcct;

        ARF_Strategy_Execution__c stopExec = new ARF_Strategy_Execution__c(
            Account__c = stopAcct.Id,
            Strategy__c = strategy.Id,
            Status__c = 'Active',
            Current_Step__c = 1,
            Next_Action_Date__c = Date.today()
        );
        insert stopExec;
    }

    @isTest
    static void testExecuteStep1Email() {
        Test.startTest();
        Database.executeBatch(new ARF_DunningEngine(), 200);
        Test.stopTest();

        ARF_Strategy_Execution__c exec = [
            SELECT Current_Step__c, Status__c, Last_Action_Result__c, Next_Action_Date__c
            FROM ARF_Strategy_Execution__c
            WHERE Account__r.Name = 'Dunning Test Account'
        ];
        System.assertEquals(2, exec.Current_Step__c, 'Should advance to step 2');
        System.assertEquals('Active', exec.Status__c, 'Should still be active');
        System.assert(exec.Last_Action_Result__c.contains('Email'), 'Should record email action');

        List<ARF_Communication__c> comms = [
            SELECT Channel__c, Subject__c FROM ARF_Communication__c
            WHERE Account__r.Name = 'Dunning Test Account' AND Subject__c = 'Step 1 Subject'
        ];
        System.assertEquals(1, comms.size(), 'Should create communication');
        System.assertEquals('Email', comms[0].Channel__c, 'Should be email channel');
    }

    @isTest
    static void testPauseForDispute() {
        Test.startTest();
        Database.executeBatch(new ARF_DunningEngine(), 200);
        Test.stopTest();

        ARF_Strategy_Execution__c exec = [
            SELECT Status__c, Pause_Reason__c
            FROM ARF_Strategy_Execution__c
            WHERE Account__r.Name = 'Dispute Dunning Account'
        ];
        System.assertEquals('Paused', exec.Status__c, 'Should be paused');
        System.assertEquals('Dispute Open', exec.Pause_Reason__c, 'Should pause for dispute');
    }

    @isTest
    static void testPauseForPromise() {
        Test.startTest();
        Database.executeBatch(new ARF_DunningEngine(), 200);
        Test.stopTest();

        ARF_Strategy_Execution__c exec = [
            SELECT Status__c, Pause_Reason__c
            FROM ARF_Strategy_Execution__c
            WHERE Account__r.Name = 'Promise Dunning Account'
        ];
        System.assertEquals('Paused', exec.Status__c, 'Should be paused');
        System.assertEquals('Promise Made', exec.Pause_Reason__c, 'Should pause for promise');
    }

    @isTest
    static void testPauseForStopStatus() {
        Test.startTest();
        Database.executeBatch(new ARF_DunningEngine(), 200);
        Test.stopTest();

        ARF_Strategy_Execution__c exec = [
            SELECT Status__c, Pause_Reason__c
            FROM ARF_Strategy_Execution__c
            WHERE Account__r.Name = 'Stop Dunning Account'
        ];
        System.assertEquals('Paused', exec.Status__c, 'Should be paused');
        System.assertEquals('Account On Hold', exec.Pause_Reason__c, 'Should pause for stop status');
    }

    @isTest
    static void testStrategyCompletion() {
        // Set execution to last step
        ARF_Strategy_Execution__c exec = [
            SELECT Id FROM ARF_Strategy_Execution__c
            WHERE Account__r.Name = 'Dunning Test Account'
        ];
        exec.Current_Step__c = 3;
        update exec;

        Test.startTest();
        Database.executeBatch(new ARF_DunningEngine(), 200);
        Test.stopTest();

        exec = [SELECT Status__c FROM ARF_Strategy_Execution__c WHERE Id = :exec.Id];
        System.assertEquals('Completed', exec.Status__c, 'Should be completed after last step');
    }

    @isTest
    static void testTaskCreation() {
        // Step 1 has createTask=true
        Test.startTest();
        Database.executeBatch(new ARF_DunningEngine(), 200);
        Test.stopTest();

        List<Task> tasks = [
            SELECT Subject FROM Task
            WHERE WhatId IN (SELECT Id FROM Account WHERE Name = 'Dunning Test Account')
              AND Subject = 'Task for step 1'
        ];
        System.assertEquals(1, tasks.size(), 'Should create task for step 1');
    }

    @isTest
    static void testSchedulableInterface() {
        Test.startTest();
        String jobId = System.schedule('Test Dunning', '0 0 6 * * ?', new ARF_DunningEngine());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Job should be scheduled');
    }

    @isTest
    static void testGetStepByNumber() {
        String json = buildStepsJson(3);
        Map<String, Object> step = ARF_DunningEngine.getStepByNumber(json, 2);
        System.assertNotEquals(null, step, 'Should find step 2');
        System.assertEquals('Task', (String) step.get('action'), 'Step 2 should be Task action');

        Map<String, Object> noStep = ARF_DunningEngine.getStepByNumber(json, 99);
        System.assertEquals(null, noStep, 'Should return null for non-existent step');

        Map<String, Object> nullJson = ARF_DunningEngine.getStepByNumber(null, 1);
        System.assertEquals(null, nullJson, 'Should return null for null JSON');
    }
}
