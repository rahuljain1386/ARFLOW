@isTest
private class ARF_StrategyBuilderControllerTest {

    private static String testStepsJson = '{"steps":[' +
        '{"stepNumber":1,"name":"Email","dayOffset":1,"action":"Email","channel":"Email",' +
        '"subject":"Reminder","body":"Please pay","escalateTo":null,"createTask":false,' +
        '"taskSubject":null,"skipIfPromise":true,"skipIfDispute":true},' +
        '{"stepNumber":2,"name":"Call","dayOffset":7,"action":"Task","channel":"Phone",' +
        '"subject":"Follow up call","body":"Call customer","escalateTo":null,"createTask":true,' +
        '"taskSubject":"Call task","skipIfPromise":true,"skipIfDispute":true},' +
        '{"stepNumber":3,"name":"Escalate","dayOffset":14,"action":"Escalate","channel":"Note",' +
        '"subject":"Escalation","body":"Escalate account","escalateTo":"Manager","createTask":true,' +
        '"taskSubject":"Escalation review","skipIfPromise":false,"skipIfDispute":true}' +
    ']}';

    @TestSetup
    static void setupTestData() {
        ARF_Collection_Strategy__c strategy = new ARF_Collection_Strategy__c(
            Strategy_Name__c = 'Test Strategy',
            Strategy_Type__c = 'Standard',
            Active__c = true,
            Total_Steps__c = 3,
            Steps_JSON__c = testStepsJson
        );
        insert strategy;

        ARF_Collection_Strategy__c emptyStrategy = new ARF_Collection_Strategy__c(
            Strategy_Name__c = 'Empty Strategy',
            Strategy_Type__c = 'Gentle',
            Active__c = false,
            Total_Steps__c = 0
        );
        insert emptyStrategy;
    }

    private static ARF_Collection_Strategy__c getStrategy(String name) {
        return [SELECT Id FROM ARF_Collection_Strategy__c WHERE Strategy_Name__c = :name LIMIT 1];
    }

    @isTest
    static void testGetStrategy() {
        ARF_Collection_Strategy__c s = getStrategy('Test Strategy');
        Test.startTest();
        ARF_Collection_Strategy__c result = ARF_StrategyBuilderController.getStrategy(s.Id);
        Test.stopTest();
        System.assertEquals('Test Strategy', result.Strategy_Name__c, 'Name should match');
        System.assertEquals(true, result.Active__c, 'Should be active');
    }

    @isTest
    static void testGetStrategyNullId() {
        Test.startTest();
        try {
            ARF_StrategyBuilderController.getStrategy(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGetSteps() {
        ARF_Collection_Strategy__c s = getStrategy('Test Strategy');
        Test.startTest();
        List<ARF_StrategyBuilderController.StrategyStep> steps =
            ARF_StrategyBuilderController.getSteps(s.Id);
        Test.stopTest();
        System.assertEquals(3, steps.size(), 'Should return 3 steps');
        System.assertEquals('Email', steps[0].action, 'First step should be Email');
        System.assertEquals(7, steps[1].dayOffset, 'Second step dayOffset should be 7');
        System.assertEquals('Escalate', steps[2].action, 'Third step should be Escalate');
    }

    @isTest
    static void testGetStepsEmpty() {
        ARF_Collection_Strategy__c s = getStrategy('Empty Strategy');
        Test.startTest();
        List<ARF_StrategyBuilderController.StrategyStep> steps =
            ARF_StrategyBuilderController.getSteps(s.Id);
        Test.stopTest();
        System.assertEquals(0, steps.size(), 'Empty strategy should return 0 steps');
    }

    @isTest
    static void testSaveSteps() {
        ARF_Collection_Strategy__c s = getStrategy('Empty Strategy');
        String newJson = '{"steps":[{"stepNumber":1,"name":"New Email","dayOffset":3,"action":"Email",' +
            '"channel":"Email","subject":"Test","body":"Body","escalateTo":null,"createTask":false,' +
            '"taskSubject":null,"skipIfPromise":true,"skipIfDispute":true}]}';

        Test.startTest();
        ARF_Collection_Strategy__c result = ARF_StrategyBuilderController.saveSteps(s.Id, newJson);
        Test.stopTest();

        ARF_Collection_Strategy__c updated = [
            SELECT Steps_JSON__c, Total_Steps__c FROM ARF_Collection_Strategy__c WHERE Id = :s.Id
        ];
        System.assertEquals(1, updated.Total_Steps__c, 'Total steps should be 1');
        System.assert(updated.Steps_JSON__c.contains('New Email'), 'JSON should contain new step');
    }

    @isTest
    static void testSaveStepsInvalidJson() {
        ARF_Collection_Strategy__c s = getStrategy('Test Strategy');
        Test.startTest();
        try {
            ARF_StrategyBuilderController.saveSteps(s.Id, 'not valid json');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid JSON') || e.getMessage().contains('Script-thrown'),
                'Should report invalid JSON');
        }
        Test.stopTest();
    }

    @isTest
    static void testActivateStrategy() {
        ARF_Collection_Strategy__c s = getStrategy('Empty Strategy');
        Test.startTest();
        ARF_StrategyBuilderController.activateStrategy(s.Id);
        Test.stopTest();

        ARF_Collection_Strategy__c updated = [SELECT Active__c FROM ARF_Collection_Strategy__c WHERE Id = :s.Id];
        System.assertEquals(true, updated.Active__c, 'Should be activated');
    }

    @isTest
    static void testDeactivateStrategy() {
        ARF_Collection_Strategy__c s = getStrategy('Test Strategy');
        Test.startTest();
        ARF_StrategyBuilderController.deactivateStrategy(s.Id);
        Test.stopTest();

        ARF_Collection_Strategy__c updated = [SELECT Active__c FROM ARF_Collection_Strategy__c WHERE Id = :s.Id];
        System.assertEquals(false, updated.Active__c, 'Should be deactivated');
    }
}
