public class ARF_RetellAutoCaller implements Database.Batchable<SObject>, Schedulable {

    // Schedule: System.schedule('ARF Retell Auto Caller', '0 0 9 * * ?', new ARF_RetellAutoCaller());

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, WhatId, OwnerId, ARF_Task_Type__c
            FROM Task
            WHERE ARF_Task_Type__c = 'Phone'
              AND Status != 'Completed'
              AND ActivityDate <= TODAY
              AND What.Type = 'Account'
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Task> scope) {
        if (!ARF_RetellService.isConfigured()) return;

        // Collect account IDs
        Set<Id> accountIds = new Set<Id>();
        Map<Id, Id> accountToTaskMap = new Map<Id, Id>();
        for (Task t : scope) {
            if (t.WhatId != null) {
                accountIds.add(t.WhatId);
                if (!accountToTaskMap.containsKey(t.WhatId)) {
                    accountToTaskMap.put(t.WhatId, t.Id);
                }
            }
        }

        if (accountIds.isEmpty()) return;

        // Load accounts
        Map<Id, Account> accounts = new Map<Id, Account>([
            SELECT Id, Name, Phone, AccountNumber,
                   ARF_Stop_Status__c, ARF_Past_Due__c, ARF_Total_AR__c,
                   ARF_Overdue_Invoice_Count__c, ARF_Risk_Score__c,
                   ARF_Assigned_Collector__c, ARF_Last_Contact_Date__c
            FROM Account
            WHERE Id IN :accountIds
        ]);

        // Check for open promises
        Set<Id> accountsWithPromise = new Set<Id>();
        for (ARF_Promise_To_Pay__c p : [
            SELECT Account__c FROM ARF_Promise_To_Pay__c
            WHERE Account__c IN :accountIds AND Status__c = 'Open'
        ]) {
            accountsWithPromise.add(p.Account__c);
        }

        // Get primary contacts with phone numbers
        Map<Id, Contact> primaryContacts = new Map<Id, Contact>();
        for (Contact c : [
            SELECT Id, Name, AccountId, MobilePhone, ARF_Phone_Direct__c, Phone
            FROM Contact
            WHERE AccountId IN :accountIds
            ORDER BY ARF_Primary_AR_Contact__c DESC, CreatedDate ASC
        ]) {
            if (!primaryContacts.containsKey(c.AccountId)) {
                primaryContacts.put(c.AccountId, c);
            }
        }

        for (Id accountId : accountIds) {
            Account acct = accounts.get(accountId);
            if (acct == null) continue;

            // Skip conditions (mirrors DunningEngine)
            if (acct.ARF_Stop_Status__c != null && acct.ARF_Stop_Status__c != 'Active') continue;
            if (accountsWithPromise.contains(accountId)) continue;
            if (acct.ARF_Past_Due__c == null || acct.ARF_Past_Due__c <= 0) continue;
            if (acct.ARF_Last_Contact_Date__c == Date.today()) continue;

            // Resolve phone number
            Contact c = primaryContacts.get(accountId);
            String phone = resolvePhone(c, acct);
            if (String.isBlank(phone)) continue;

            // Enqueue the call
            Id taskId = accountToTaskMap.get(accountId);
            System.enqueueJob(new ARF_RetellService.InitiateCallQueueable(
                accountId, c != null ? c.Id : null, taskId, phone
            ));
        }
    }

    public void finish(Database.BatchableContext bc) {
        // No post-processing needed
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new ARF_RetellAutoCaller(), 1);
    }

    @TestVisible
    private static String resolvePhone(Contact c, Account acct) {
        if (c != null) {
            if (String.isNotBlank(c.MobilePhone)) return c.MobilePhone;
            if (String.isNotBlank(c.ARF_Phone_Direct__c)) return c.ARF_Phone_Direct__c;
            if (String.isNotBlank(c.Phone)) return c.Phone;
        }
        return acct != null ? acct.Phone : null;
    }
}
