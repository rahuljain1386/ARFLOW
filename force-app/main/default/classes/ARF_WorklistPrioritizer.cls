public with sharing class ARF_WorklistPrioritizer {

    public class PrioritizedAccount {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountUrl;
        @AuraEnabled public Decimal totalAR;
        @AuraEnabled public Decimal pastDue;
        @AuraEnabled public Decimal inDispute;
        @AuraEnabled public Decimal promisedAmount;
        @AuraEnabled public Integer riskScore;
        @AuraEnabled public Decimal dso;
        @AuraEnabled public Integer openInvoiceCount;
        @AuraEnabled public Integer overdueInvoiceCount;
        @AuraEnabled public Date lastContactDate;
        @AuraEnabled public Date lastPaymentDate;
        @AuraEnabled public String collectorName;
        @AuraEnabled public String stopStatus;
        @AuraEnabled public String collectionStrategy;
        @AuraEnabled public Decimal priorityScore;
        @AuraEnabled public Integer maxDaysPastDue;
    }

    /**
     * Score = pastDue * daysFactor * riskFactor * recencyFactor
     *   daysFactor    = MAX(maxDaysPastDue, 1) / 30
     *   riskFactor    = MAX(riskScore, 1) / 50
     *   recencyFactor = MAX(daysSinceLastContact, 1) / 14
     */
    public static Decimal calculateScore(
        Decimal pastDue,
        Integer maxDaysPastDue,
        Integer riskScore,
        Date lastContactDate
    ) {
        if (pastDue == null || pastDue <= 0) return 0;

        Decimal daysFactor = Math.max(maxDaysPastDue != null ? maxDaysPastDue : 1, 1) / 30.0;
        Decimal riskFactor = Math.max(riskScore != null ? riskScore : 50, 1) / 50.0;

        Integer daysSinceContact = 90; // default if never contacted
        if (lastContactDate != null) {
            daysSinceContact = Math.max(lastContactDate.daysBetween(Date.today()), 1);
        }
        Decimal recencyFactor = Math.max(daysSinceContact, 1) / 14.0;

        return (pastDue * daysFactor * riskFactor * recencyFactor).setScale(0, RoundingMode.HALF_UP);
    }

    public static List<PrioritizedAccount> getPrioritizedAccounts(
        Id collectorUserId,
        Boolean showAll,
        Integer recordLimit
    ) {
        // Query accounts with AR data
        String query = 'SELECT Id, Name, ARF_Total_AR__c, ARF_Past_Due__c, ARF_In_Dispute__c, ' +
            'ARF_Promised_Amount__c, ARF_Risk_Score__c, ARF_DSO__c, ' +
            'ARF_Open_Invoice_Count__c, ARF_Overdue_Invoice_Count__c, ' +
            'ARF_Last_Contact_Date__c, ARF_Last_Payment_Date__c, ' +
            'ARF_Assigned_Collector__c, ARF_Assigned_Collector__r.Name, ' +
            'ARF_Stop_Status__c, ARF_Collection_Strategy__c ' +
            'FROM Account ' +
            'WHERE ARF_Past_Due__c > 0 ' +
            'AND (ARF_Stop_Status__c = null OR ARF_Stop_Status__c != \'Legal Hold\') ';

        if (!showAll && collectorUserId != null) {
            query += 'AND ARF_Assigned_Collector__c = :collectorUserId ';
        }
        query += 'LIMIT 1000';

        List<Account> accounts = Database.query(query);
        if (accounts.isEmpty()) return new List<PrioritizedAccount>();

        // Get max days past due per account via aggregate
        Set<Id> accountIds = new Set<Id>();
        for (Account a : accounts) {
            accountIds.add(a.Id);
        }

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

        // Build prioritized list
        List<PrioritizedAccount> result = new List<PrioritizedAccount>();
        for (Account a : accounts) {
            PrioritizedAccount pa = new PrioritizedAccount();
            pa.accountId = a.Id;
            pa.accountName = a.Name;
            pa.accountUrl = '/' + a.Id;
            pa.totalAR = a.ARF_Total_AR__c != null ? a.ARF_Total_AR__c : 0;
            pa.pastDue = a.ARF_Past_Due__c != null ? a.ARF_Past_Due__c : 0;
            pa.inDispute = a.ARF_In_Dispute__c != null ? a.ARF_In_Dispute__c : 0;
            pa.promisedAmount = a.ARF_Promised_Amount__c != null ? a.ARF_Promised_Amount__c : 0;
            pa.riskScore = a.ARF_Risk_Score__c != null ? Integer.valueOf(a.ARF_Risk_Score__c) : 0;
            pa.dso = a.ARF_DSO__c;
            pa.openInvoiceCount = a.ARF_Open_Invoice_Count__c != null ? Integer.valueOf(a.ARF_Open_Invoice_Count__c) : 0;
            pa.overdueInvoiceCount = a.ARF_Overdue_Invoice_Count__c != null ? Integer.valueOf(a.ARF_Overdue_Invoice_Count__c) : 0;
            pa.lastContactDate = a.ARF_Last_Contact_Date__c;
            pa.lastPaymentDate = a.ARF_Last_Payment_Date__c;
            pa.collectorName = a.ARF_Assigned_Collector__r != null ? a.ARF_Assigned_Collector__r.Name : '';
            pa.stopStatus = a.ARF_Stop_Status__c;
            pa.collectionStrategy = a.ARF_Collection_Strategy__c;
            pa.maxDaysPastDue = maxDPDMap.containsKey(a.Id) ? maxDPDMap.get(a.Id) : 0;
            pa.priorityScore = calculateScore(
                pa.pastDue, pa.maxDaysPastDue, pa.riskScore, pa.lastContactDate
            );
            result.add(pa);
        }

        // Sort by priority score descending
        result.sort(new PriorityComparator());

        // Trim to limit
        if (recordLimit != null && recordLimit > 0 && result.size() > recordLimit) {
            List<PrioritizedAccount> trimmed = new List<PrioritizedAccount>();
            for (Integer i = 0; i < recordLimit; i++) {
                trimmed.add(result[i]);
            }
            return trimmed;
        }
        return result;
    }

    private class PriorityComparator implements Comparator<PrioritizedAccount> {
        public Integer compare(PrioritizedAccount a, PrioritizedAccount b) {
            if (a.priorityScore == b.priorityScore) return 0;
            return a.priorityScore > b.priorityScore ? -1 : 1;
        }
    }
}
