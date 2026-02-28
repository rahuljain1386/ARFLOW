public with sharing class ARF_StrategyBuilderController {

    public class StrategyStep {
        @AuraEnabled public Integer stepNumber;
        @AuraEnabled public String name;
        @AuraEnabled public Integer dayOffset;
        @AuraEnabled public String action;
        @AuraEnabled public String channel;
        @AuraEnabled public String subject;
        @AuraEnabled public String body;
        @AuraEnabled public String escalateTo;
        @AuraEnabled public Boolean createTask;
        @AuraEnabled public String taskSubject;
        @AuraEnabled public Boolean skipIfPromise;
        @AuraEnabled public Boolean skipIfDispute;
    }

    @AuraEnabled(cacheable=true)
    public static ARF_Collection_Strategy__c getStrategy(Id strategyId) {
        if (strategyId == null) {
            throw new AuraHandledException('Strategy ID is required');
        }
        List<ARF_Collection_Strategy__c> strategies = [
            SELECT Id, Name, Strategy_Name__c, Description__c, Strategy_Type__c,
                   Active__c, Total_Steps__c, Steps_JSON__c
            FROM ARF_Collection_Strategy__c
            WHERE Id = :strategyId
            LIMIT 1
        ];
        if (strategies.isEmpty()) {
            throw new AuraHandledException('Strategy not found');
        }
        return strategies[0];
    }

    @AuraEnabled(cacheable=true)
    public static List<StrategyStep> getSteps(Id strategyId) {
        if (strategyId == null) {
            throw new AuraHandledException('Strategy ID is required');
        }
        ARF_Collection_Strategy__c strategy = [
            SELECT Steps_JSON__c FROM ARF_Collection_Strategy__c
            WHERE Id = :strategyId LIMIT 1
        ];
        if (String.isBlank(strategy.Steps_JSON__c)) {
            return new List<StrategyStep>();
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(strategy.Steps_JSON__c);
            List<Object> stepsList = (List<Object>) parsed.get('steps');
            if (stepsList == null) return new List<StrategyStep>();

            List<StrategyStep> result = new List<StrategyStep>();
            for (Object s : stepsList) {
                Map<String, Object> m = (Map<String, Object>) s;
                StrategyStep ss = new StrategyStep();
                ss.stepNumber = m.get('stepNumber') != null ? Integer.valueOf(m.get('stepNumber')) : 0;
                ss.name = (String) m.get('name');
                ss.dayOffset = m.get('dayOffset') != null ? Integer.valueOf(m.get('dayOffset')) : 0;
                ss.action = (String) m.get('action');
                ss.channel = (String) m.get('channel');
                ss.subject = (String) m.get('subject');
                ss.body = (String) m.get('body');
                ss.escalateTo = (String) m.get('escalateTo');
                ss.createTask = m.get('createTask') != null ? (Boolean) m.get('createTask') : false;
                ss.taskSubject = (String) m.get('taskSubject');
                ss.skipIfPromise = m.get('skipIfPromise') != null ? (Boolean) m.get('skipIfPromise') : true;
                ss.skipIfDispute = m.get('skipIfDispute') != null ? (Boolean) m.get('skipIfDispute') : true;
                result.add(ss);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Invalid strategy JSON: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static ARF_Collection_Strategy__c saveSteps(Id strategyId, String stepsJson) {
        if (strategyId == null) {
            throw new AuraHandledException('Strategy ID is required');
        }
        // Validate JSON structure
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(stepsJson);
            List<Object> steps = (List<Object>) parsed.get('steps');
            if (steps == null) {
                throw new AuraHandledException('JSON must contain a "steps" array');
            }

            ARF_Collection_Strategy__c strategy = new ARF_Collection_Strategy__c(
                Id = strategyId,
                Steps_JSON__c = stepsJson,
                Total_Steps__c = steps.size()
            );
            update strategy;
            return strategy;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Invalid JSON: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void activateStrategy(Id strategyId) {
        if (strategyId == null) {
            throw new AuraHandledException('Strategy ID is required');
        }
        update new ARF_Collection_Strategy__c(Id = strategyId, Active__c = true);
    }

    @AuraEnabled
    public static void deactivateStrategy(Id strategyId) {
        if (strategyId == null) {
            throw new AuraHandledException('Strategy ID is required');
        }
        update new ARF_Collection_Strategy__c(Id = strategyId, Active__c = false);
    }
}
