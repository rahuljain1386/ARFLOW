public class ARF_PromiseTracker implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Account__c, Account__r.Name, Account__r.ARF_Assigned_Collector__c,
                   Account__r.OwnerId,
                   Invoice__c, Invoice__r.Document_Number__c,
                   Amount__c, Amount_Received__c, Promise_Date__c,
                   Status__c, Broken_Count__c
            FROM ARF_Promise_To_Pay__c
            WHERE Status__c = 'Open'
        ]);
    }

    public void execute(Database.BatchableContext bc, List<ARF_Promise_To_Pay__c> scope) {
        List<ARF_Promise_To_Pay__c> toUpdate = new List<ARF_Promise_To_Pay__c>();
        List<Task> followUpTasks = new List<Task>();
        List<ARF_Communication__c> commsToInsert = new List<ARF_Communication__c>();
        Set<Id> accountIdsToResumeStrategy = new Set<Id>();

        for (ARF_Promise_To_Pay__c ptp : scope) {
            Decimal received = ptp.Amount_Received__c != null ? ptp.Amount_Received__c : 0;

            // Case 1: Fully kept
            if (received >= ptp.Amount__c) {
                ptp.Status__c = 'Kept';
                toUpdate.add(ptp);
                accountIdsToResumeStrategy.add(ptp.Account__c);
                continue;
            }

            // Case 2: Promise date has passed
            if (ptp.Promise_Date__c != null && ptp.Promise_Date__c < Date.today()) {
                if (received > 0) {
                    ptp.Status__c = 'Partially Kept';
                } else {
                    ptp.Status__c = 'Broken';
                }
                ptp.Broken_Count__c = (ptp.Broken_Count__c != null ? ptp.Broken_Count__c : 0) + 1;
                toUpdate.add(ptp);

                Id taskOwnerId = ptp.Account__r.ARF_Assigned_Collector__c != null
                    ? ptp.Account__r.ARF_Assigned_Collector__c : ptp.Account__r.OwnerId;

                String invoiceRef = ptp.Invoice__r != null && ptp.Invoice__r.Document_Number__c != null
                    ? ptp.Invoice__r.Document_Number__c : 'N/A';

                followUpTasks.add(new Task(
                    Subject = 'Broken Promise Follow-Up: ' + ptp.Account__r.Name,
                    WhatId = ptp.Account__c,
                    OwnerId = taskOwnerId,
                    ActivityDate = Date.today().addDays(1),
                    Status = 'Open',
                    Priority = 'High',
                    Description = 'Promise to pay $' + ptp.Amount__c +
                        ' was ' + ptp.Status__c.toLowerCase() + '. Received: $' + received +
                        '. Invoice: ' + invoiceRef
                ));

                commsToInsert.add(new ARF_Communication__c(
                    Account__c = ptp.Account__c,
                    Channel__c = 'Note',
                    Direction__c = 'Outbound',
                    Subject__c = 'Promise ' + ptp.Status__c,
                    Body__c = 'Promise of $' + ptp.Amount__c + ' due ' +
                        String.valueOf(ptp.Promise_Date__c) + ' was ' + ptp.Status__c.toLowerCase() +
                        '. Amount received: $' + received + '.',
                    Status__c = 'Sent',
                    Sent_Date__c = Datetime.now()
                ));

                accountIdsToResumeStrategy.add(ptp.Account__c);
            }
            // Case 3: Promise date not yet reached -> leave as Open
        }

        if (!toUpdate.isEmpty()) update toUpdate;
        if (!followUpTasks.isEmpty()) insert followUpTasks;
        if (!commsToInsert.isEmpty()) insert commsToInsert;

        // Resume paused strategy executions
        if (!accountIdsToResumeStrategy.isEmpty()) {
            List<ARF_Strategy_Execution__c> execsToResume = [
                SELECT Id, Status__c, Pause_Reason__c
                FROM ARF_Strategy_Execution__c
                WHERE Account__c IN :accountIdsToResumeStrategy
                  AND Status__c = 'Paused'
                  AND Pause_Reason__c = 'Promise Made'
            ];
            for (ARF_Strategy_Execution__c exec : execsToResume) {
                exec.Status__c = 'Active';
                exec.Pause_Reason__c = null;
            }
            if (!execsToResume.isEmpty()) update execsToResume;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // No post-processing needed
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new ARF_PromiseTracker(), 200);
    }
}
