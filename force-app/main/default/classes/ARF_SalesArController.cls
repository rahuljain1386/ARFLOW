public with sharing class ARF_SalesArController {

    @AuraEnabled(cacheable=true)
    public static ArSummary getArSummary(Id accountId) {
        ArSummary summary = new ArSummary();

        // Get account data
        Account acct = [
            SELECT Id, Name, ARF_Total_AR__c, ARF_Past_Due__c, ARF_DSO__c,
                   ARF_Risk_Score__c, ARF_Credit_Limit__c, ARF_Open_Invoice_Count__c,
                   ARF_Current__c, ARF_1_30_Days__c, ARF_31_60_Days__c,
                   ARF_61_90_Days__c, ARF_Over_90_Days__c, ARF_Last_Contact_Date__c
            FROM Account WHERE Id = :accountId
        ];

        summary.totalAR = acct.ARF_Total_AR__c != null ? acct.ARF_Total_AR__c : 0;
        summary.pastDue = acct.ARF_Past_Due__c != null ? acct.ARF_Past_Due__c : 0;
        summary.dso = acct.ARF_DSO__c != null ? acct.ARF_DSO__c : 0;
        summary.riskScore = acct.ARF_Risk_Score__c != null ? acct.ARF_Risk_Score__c : 0;
        summary.openInvoiceCount = acct.ARF_Open_Invoice_Count__c != null ? (Integer) acct.ARF_Open_Invoice_Count__c : 0;
        summary.creditLimit = acct.ARF_Credit_Limit__c != null ? acct.ARF_Credit_Limit__c : 0;
        summary.creditUtilization = summary.creditLimit > 0 ? (summary.totalAR / summary.creditLimit * 100).setScale(1) : 0;

        // Aging
        summary.agingCurrent = acct.ARF_Current__c != null ? acct.ARF_Current__c : 0;
        summary.aging1to30 = acct.ARF_1_30_Days__c != null ? acct.ARF_1_30_Days__c : 0;
        summary.aging31to60 = acct.ARF_31_60_Days__c != null ? acct.ARF_31_60_Days__c : 0;
        summary.aging61to90 = acct.ARF_61_90_Days__c != null ? acct.ARF_61_90_Days__c : 0;
        summary.agingOver90 = acct.ARF_Over_90_Days__c != null ? acct.ARF_Over_90_Days__c : 0;

        // Past due over 60
        summary.pastDueOver60 = summary.aging61to90 + summary.agingOver90;

        // Count invoices over 60 days
        summary.invoicesOver60 = [
            SELECT COUNT() FROM ARF_Invoice__c
            WHERE Account__c = :accountId AND Days_Past_Due__c > 60
            AND (Status__c = 'Open' OR Status__c = 'Partially Paid')
        ];

        // Open disputes
        summary.openDisputes = [
            SELECT COUNT() FROM ARF_Dispute__c
            WHERE Invoice__r.Account__c = :accountId
            AND (Status__c = 'New' OR Status__c = 'Under Investigation' OR Status__c = 'Pending Approval')
        ];

        // Broken promises
        summary.brokenPromises = [
            SELECT COUNT() FROM ARF_Promise_To_Pay__c
            WHERE Invoice__r.Account__c = :accountId AND Status__c = 'Broken'
        ];

        // Last contact
        summary.lastContactDate = acct.ARF_Last_Contact_Date__c != null
            ? acct.ARF_Last_Contact_Date__c.format() : 'Never';

        List<ARF_Communication__c> recentComms = [
            SELECT Subject__c, Channel__c FROM ARF_Communication__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        summary.lastContactSummary = !recentComms.isEmpty()
            ? recentComms[0].Channel__c + ': ' + (recentComms[0].Subject__c != null ? recentComms[0].Subject__c.abbreviate(60) : 'No subject')
            : 'No communications on record';

        return summary;
    }

    public class ArSummary {
        @AuraEnabled public Decimal totalAR;
        @AuraEnabled public Decimal pastDue;
        @AuraEnabled public Decimal pastDueOver60;
        @AuraEnabled public Integer openInvoiceCount;
        @AuraEnabled public Integer invoicesOver60;
        @AuraEnabled public Decimal dso;
        @AuraEnabled public Decimal riskScore;
        @AuraEnabled public Decimal agingCurrent;
        @AuraEnabled public Decimal aging1to30;
        @AuraEnabled public Decimal aging31to60;
        @AuraEnabled public Decimal aging61to90;
        @AuraEnabled public Decimal agingOver90;
        @AuraEnabled public Integer openDisputes;
        @AuraEnabled public Integer brokenPromises;
        @AuraEnabled public String lastContactDate;
        @AuraEnabled public String lastContactSummary;
        @AuraEnabled public Decimal creditLimit;
        @AuraEnabled public Decimal creditUtilization;
    }
}
