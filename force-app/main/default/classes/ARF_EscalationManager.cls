public with sharing class ARF_EscalationManager {

    public static final Integer SENIOR_THRESHOLD = 60;
    public static final Integer MANAGER_THRESHOLD = 90;
    public static final Integer LEGAL_THRESHOLD = 120;

    public static String getEscalationLevel(Integer daysPastDue) {
        if (daysPastDue == null) return 'None';
        if (daysPastDue >= LEGAL_THRESHOLD) return 'Legal';
        if (daysPastDue >= MANAGER_THRESHOLD) return 'Manager';
        if (daysPastDue >= SENIOR_THRESHOLD) return 'Senior Collector';
        return 'None';
    }

    public static void escalateAccount(Id accountId) {
        if (accountId == null) return;
        checkAndEscalateAll(new Set<Id>{ accountId });
    }

    public static void checkAndEscalateAll(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) return;

        // Get max days past due per account
        Map<Id, Integer> maxDPDMap = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Account__c acctId, MAX(Days_Past_Due__c) maxDPD
            FROM ARF_Invoice__c
            WHERE Account__c IN :accountIds
              AND Status__c NOT IN ('Paid', 'Cancelled', 'Written Off')
            GROUP BY Account__c
        ]) {
            Id acctId = (Id) ar.get('acctId');
            Decimal maxDPD = (Decimal) ar.get('maxDPD');
            maxDPDMap.put(acctId, maxDPD != null ? maxDPD.intValue() : 0);
        }

        // Get account details
        Map<Id, Account> accountMap = new Map<Id, Account>([
            SELECT Id, Name, ARF_Stop_Status__c, ARF_Assigned_Collector__c, OwnerId
            FROM Account
            WHERE Id IN :accountIds
        ]);

        List<Account> accountsToUpdate = new List<Account>();
        List<Task> tasksToCreate = new List<Task>();
        List<ARF_Communication__c> commsToCreate = new List<ARF_Communication__c>();

        for (Id acctId : accountIds) {
            Integer maxDPD = maxDPDMap.containsKey(acctId) ? maxDPDMap.get(acctId) : 0;
            String level = getEscalationLevel(maxDPD);
            if (level == 'None') continue;

            Account acct = accountMap.get(acctId);
            if (acct == null) continue;

            // Skip if already on Legal Hold
            if (acct.ARF_Stop_Status__c == 'Legal Hold' && level != 'Legal') continue;

            Id taskOwnerId = acct.ARF_Assigned_Collector__c != null
                ? acct.ARF_Assigned_Collector__c : acct.OwnerId;

            if (level == 'Legal') {
                Account upd = new Account(Id = acctId, ARF_Stop_Status__c = 'Legal Hold');
                accountsToUpdate.add(upd);
            }

            tasksToCreate.add(new Task(
                Subject = 'Escalation (' + level + '): ' + acct.Name,
                WhatId = acctId,
                OwnerId = taskOwnerId,
                ActivityDate = Date.today(),
                Status = 'Open',
                Priority = level == 'Legal' ? 'High' : 'Normal',
                Description = 'Account ' + acct.Name + ' has invoices ' + maxDPD +
                    ' days past due. Escalation level: ' + level + '.'
            ));

            commsToCreate.add(new ARF_Communication__c(
                Account__c = acctId,
                Channel__c = 'Note',
                Direction__c = 'Outbound',
                Subject__c = 'Auto-Escalation: ' + level,
                Body__c = 'Account automatically escalated to ' + level +
                    ' level. Max days past due: ' + maxDPD + '.',
                Status__c = 'Sent',
                Sent_Date__c = Datetime.now()
            ));
        }

        if (!accountsToUpdate.isEmpty()) update accountsToUpdate;
        if (!tasksToCreate.isEmpty()) insert tasksToCreate;
        if (!commsToCreate.isEmpty()) insert commsToCreate;
    }
}
