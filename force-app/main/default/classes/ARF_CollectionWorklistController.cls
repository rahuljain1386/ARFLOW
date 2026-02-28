public with sharing class ARF_CollectionWorklistController {

    @AuraEnabled(cacheable=true)
    public static List<ARF_WorklistPrioritizer.PrioritizedAccount> getWorklist(Boolean showAll) {
        return ARF_WorklistPrioritizer.getPrioritizedAccounts(
            UserInfo.getUserId(), showAll == true, 500
        );
    }

    @AuraEnabled
    public static void snoozeAccount(Id accountId, Integer snoozeDays) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        Account acct = new Account(
            Id = accountId,
            ARF_Last_Contact_Date__c = Date.today()
        );
        try {
            update acct;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static ARF_Communication__c quickLogCall(
        Id accountId, String subject, String body, Integer durationSeconds
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        try {
            ARF_Communication__c comm = new ARF_Communication__c(
                Account__c = accountId,
                Channel__c = 'Phone',
                Direction__c = 'Outbound',
                Subject__c = String.isBlank(subject) ? 'Collection Call' : subject,
                Body__c = body,
                Status__c = 'Sent',
                Sent_Date__c = Datetime.now(),
                Call_Duration_Seconds__c = durationSeconds
            );
            insert comm;

            // Update last contact date
            update new Account(Id = accountId, ARF_Last_Contact_Date__c = Date.today());

            return comm;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void reassignAccount(Id accountId, Id newCollectorId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        try {
            update new Account(Id = accountId, ARF_Assigned_Collector__c = newCollectorId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
