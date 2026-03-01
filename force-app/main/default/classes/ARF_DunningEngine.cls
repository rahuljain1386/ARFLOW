public class ARF_DunningEngine implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Account__c, Strategy__c, Strategy__r.Steps_JSON__c,
                   Strategy__r.Total_Steps__c, Current_Step__c,
                   Next_Action_Date__c, Status__c, Pause_Reason__c, CreatedDate,
                   Account__r.Name, Account__r.ARF_Past_Due__c,
                   Account__r.ARF_Stop_Status__c,
                   Account__r.ARF_Open_Dispute_Count__c,
                   Account__r.ARF_Assigned_Collector__c,
                   Account__r.OwnerId
            FROM ARF_Strategy_Execution__c
            WHERE Status__c = 'Active'
              AND Next_Action_Date__c <= TODAY
        ]);
    }

    public void execute(Database.BatchableContext bc, List<ARF_Strategy_Execution__c> scope) {
        // Collect account IDs for bulk promise check
        Set<Id> accountIds = new Set<Id>();
        for (ARF_Strategy_Execution__c exec : scope) {
            accountIds.add(exec.Account__c);
        }

        // Check for active promises (bulkified)
        Set<Id> accountsWithPromise = new Set<Id>();
        for (ARF_Promise_To_Pay__c p : [
            SELECT Account__c FROM ARF_Promise_To_Pay__c
            WHERE Account__c IN :accountIds AND Status__c = 'Open'
        ]) {
            accountsWithPromise.add(p.Account__c);
        }

        // Get primary contacts for communications
        Map<Id, Id> accountContactMap = new Map<Id, Id>();
        for (Contact c : [
            SELECT Id, AccountId FROM Contact
            WHERE AccountId IN :accountIds
            ORDER BY ARF_Primary_AR_Contact__c DESC, CreatedDate ASC
        ]) {
            if (!accountContactMap.containsKey(c.AccountId)) {
                accountContactMap.put(c.AccountId, c.Id);
            }
        }

        List<ARF_Communication__c> commsToInsert = new List<ARF_Communication__c>();
        List<Task> tasksToInsert = new List<Task>();
        List<ARF_Strategy_Execution__c> execsToUpdate = new List<ARF_Strategy_Execution__c>();

        for (ARF_Strategy_Execution__c exec : scope) {
            // Check pause conditions
            String pauseReason = checkPauseConditions(exec, accountsWithPromise);
            if (pauseReason != null) {
                exec.Status__c = 'Paused';
                exec.Pause_Reason__c = pauseReason;
                execsToUpdate.add(exec);
                continue;
            }

            // Parse steps and find current
            Map<String, Object> step = getStepByNumber(
                exec.Strategy__r.Steps_JSON__c,
                Integer.valueOf(exec.Current_Step__c)
            );
            if (step == null) {
                exec.Status__c = 'Completed';
                exec.Last_Action_Date__c = Datetime.now();
                exec.Last_Action_Result__c = 'No step found for step ' + exec.Current_Step__c;
                execsToUpdate.add(exec);
                continue;
            }

            // Check step-level skip conditions
            Boolean skipForPromise = step.containsKey('skipIfPromise') && (Boolean) step.get('skipIfPromise');
            Boolean skipForDispute = step.containsKey('skipIfDispute') && (Boolean) step.get('skipIfDispute');

            if (skipForPromise && accountsWithPromise.contains(exec.Account__c)) {
                exec.Status__c = 'Paused';
                exec.Pause_Reason__c = 'Promise Made';
                execsToUpdate.add(exec);
                continue;
            }
            if (skipForDispute && exec.Account__r.ARF_Open_Dispute_Count__c > 0) {
                exec.Status__c = 'Paused';
                exec.Pause_Reason__c = 'Dispute Open';
                execsToUpdate.add(exec);
                continue;
            }

            String action = (String) step.get('action');
            Id taskOwnerId = exec.Account__r.ARF_Assigned_Collector__c != null
                ? exec.Account__r.ARF_Assigned_Collector__c : exec.Account__r.OwnerId;

            // Execute step action
            if (action == 'Email' || action == 'SMS' || action == 'Letter') {
                commsToInsert.add(buildCommunication(step, exec.Account__c,
                    accountContactMap.get(exec.Account__c)));
            } else if (action == 'Task') {
                tasksToInsert.add(buildTask(step, exec.Account__c, taskOwnerId));
            } else if (action == 'Escalate') {
                // Create escalation communication
                commsToInsert.add(buildCommunication(step, exec.Account__c,
                    accountContactMap.get(exec.Account__c)));
            }

            // Create task if step config says so
            if (step.containsKey('createTask') && (Boolean) step.get('createTask') && action != 'Task') {
                String taskSubject = step.containsKey('taskSubject') ? (String) step.get('taskSubject') : 'Follow up';
                String taskType = action;
                if (taskType == 'Letter') taskType = 'Reminder';
                if (taskType == 'Escalate') taskType = 'Follow-Up';
                String channel = step.containsKey('channel') ? (String) step.get('channel') : action;
                String templateName = step.containsKey('templateName') ? (String) step.get('templateName') : '';

                tasksToInsert.add(new Task(
                    Subject = taskSubject,
                    WhatId = exec.Account__c,
                    OwnerId = taskOwnerId,
                    ActivityDate = Date.today().addDays(1),
                    Status = 'Open',
                    Priority = 'Normal',
                    ARF_Task_Type__c = taskType,
                    ARF_Channel__c = channel,
                    ARF_Template_Name__c = templateName
                ));
            }

            // Advance execution
            Integer nextStep = Integer.valueOf(exec.Current_Step__c) + 1;
            Integer totalSteps = exec.Strategy__r.Total_Steps__c != null
                ? Integer.valueOf(exec.Strategy__r.Total_Steps__c) : 0;

            exec.Last_Action_Date__c = Datetime.now();
            exec.Last_Action_Result__c = 'Step ' + Integer.valueOf(exec.Current_Step__c) + ' executed: ' + action;

            if (nextStep > totalSteps) {
                exec.Status__c = 'Completed';
                exec.Current_Step__c = exec.Current_Step__c;
            } else {
                exec.Current_Step__c = nextStep;
                exec.Next_Action_Date__c = computeNextActionDate(
                    exec.Strategy__r.Steps_JSON__c, nextStep, exec.CreatedDate.date()
                );
            }
            execsToUpdate.add(exec);
        }

        if (!commsToInsert.isEmpty()) insert commsToInsert;
        if (!tasksToInsert.isEmpty()) insert tasksToInsert;
        if (!execsToUpdate.isEmpty()) update execsToUpdate;
    }

    public void finish(Database.BatchableContext bc) {
        // No post-processing needed
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new ARF_DunningEngine(), 200);
    }

    private static String checkPauseConditions(
        ARF_Strategy_Execution__c exec,
        Set<Id> accountsWithPromise
    ) {
        String stopStatus = exec.Account__r.ARF_Stop_Status__c;
        if (stopStatus != null && stopStatus != 'Active') {
            return 'Account On Hold';
        }
        return null;
    }

    @TestVisible
    private static Map<String, Object> getStepByNumber(String stepsJson, Integer stepNumber) {
        if (String.isBlank(stepsJson)) return null;
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(stepsJson);
            List<Object> steps = (List<Object>) parsed.get('steps');
            if (steps == null) return null;
            for (Object s : steps) {
                Map<String, Object> step = (Map<String, Object>) s;
                Integer sn = Integer.valueOf(step.get('stepNumber'));
                if (sn == stepNumber) return step;
            }
        } catch (Exception e) {
            // Invalid JSON - return null
        }
        return null;
    }

    private static Date computeNextActionDate(String stepsJson, Integer nextStepNumber, Date createdDate) {
        Map<String, Object> nextStep = getStepByNumber(stepsJson, nextStepNumber);
        if (nextStep != null && nextStep.containsKey('dayOffset')) {
            Integer dayOffset = Integer.valueOf(nextStep.get('dayOffset'));
            return createdDate.addDays(dayOffset);
        }
        return Date.today().addDays(7); // fallback
    }

    private static ARF_Communication__c buildCommunication(
        Map<String, Object> step, Id accountId, Id contactId
    ) {
        String channel = step.containsKey('channel') ? (String) step.get('channel') : 'Email';
        String subject = step.containsKey('subject') ? (String) step.get('subject') : 'Collection Notice';
        String body = step.containsKey('body') ? (String) step.get('body') : '';

        return new ARF_Communication__c(
            Account__c = accountId,
            Contact__c = contactId,
            Channel__c = channel,
            Direction__c = 'Outbound',
            Subject__c = subject,
            Body__c = body,
            Status__c = 'Sent',
            Sent_Date__c = Datetime.now()
        );
    }

    private static Task buildTask(
        Map<String, Object> step, Id accountId, Id ownerId
    ) {
        String subject = step.containsKey('subject') ? (String) step.get('subject') : 'Collection Task';
        String action = step.containsKey('action') ? (String) step.get('action') : 'Reminder';
        String taskType = action;
        if (taskType == 'Letter') taskType = 'Reminder';
        if (taskType == 'Escalate') taskType = 'Follow-Up';
        String channel = step.containsKey('channel') ? (String) step.get('channel') : action;
        String templateName = step.containsKey('templateName') ? (String) step.get('templateName') : '';

        return new Task(
            Subject = subject,
            WhatId = accountId,
            OwnerId = ownerId,
            ActivityDate = Date.today(),
            Status = 'Open',
            Priority = 'Normal',
            Description = step.containsKey('body') ? (String) step.get('body') : '',
            ARF_Task_Type__c = taskType,
            ARF_Channel__c = channel,
            ARF_Template_Name__c = templateName
        );
    }
}
