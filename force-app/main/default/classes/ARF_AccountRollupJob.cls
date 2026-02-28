public class ARF_AccountRollupJob implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Semi-join sub-selects can't be combined with OR in SOQL.
        // Query all accounts — execute() efficiently zeros out accounts with no children.
        return Database.getQueryLocator([SELECT Id FROM Account]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        Set<Id> accountIds = new Set<Id>();
        for (Account a : scope) {
            accountIds.add(a.Id);
        }

        // 1. Total AR & Open Invoice Count: SUM(Balance), COUNT where not terminal
        Map<Id, Decimal> totalAR = new Map<Id, Decimal>();
        Map<Id, Integer> openInvCount = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Account__c acctId, SUM(Balance__c) totalBal, COUNT(Id) cnt
            FROM ARF_Invoice__c
            WHERE Account__c IN :accountIds
              AND Status__c NOT IN ('Paid', 'Cancelled', 'Written Off')
            GROUP BY Account__c
        ]) {
            Id acctId = (Id) ar.get('acctId');
            totalAR.put(acctId, (Decimal) ar.get('totalBal'));
            openInvCount.put(acctId, (Integer) ar.get('cnt'));
        }

        // 2. Past Due & Overdue Count: SUM(Balance), COUNT where overdue
        Map<Id, Decimal> pastDue = new Map<Id, Decimal>();
        Map<Id, Integer> overdueCount = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Account__c acctId, SUM(Balance__c) totalBal, COUNT(Id) cnt
            FROM ARF_Invoice__c
            WHERE Account__c IN :accountIds
              AND Status__c NOT IN ('Paid', 'Cancelled', 'Written Off')
              AND Due_Date__c < TODAY
            GROUP BY Account__c
        ]) {
            Id acctId = (Id) ar.get('acctId');
            pastDue.put(acctId, (Decimal) ar.get('totalBal'));
            overdueCount.put(acctId, (Integer) ar.get('cnt'));
        }

        // 3. In Dispute: SUM(Dispute_Amount) where open
        Map<Id, Decimal> inDispute = new Map<Id, Decimal>();
        Map<Id, Integer> openDisputeCount = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Account__c acctId, SUM(Dispute_Amount__c) totalAmt, COUNT(Id) cnt
            FROM ARF_Dispute__c
            WHERE Account__c IN :accountIds
              AND Status__c NOT IN ('Resolved', 'Closed', 'Denied')
            GROUP BY Account__c
        ]) {
            Id acctId = (Id) ar.get('acctId');
            inDispute.put(acctId, (Decimal) ar.get('totalAmt'));
            openDisputeCount.put(acctId, (Integer) ar.get('cnt'));
        }

        // 4. Promised Amount: SUM(Amount) where Open
        Map<Id, Decimal> promisedAmt = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Account__c acctId, SUM(Amount__c) totalAmt
            FROM ARF_Promise_To_Pay__c
            WHERE Account__c IN :accountIds
              AND Status__c = 'Open'
            GROUP BY Account__c
        ]) {
            Id acctId = (Id) ar.get('acctId');
            promisedAmt.put(acctId, (Decimal) ar.get('totalAmt'));
        }

        // 5. Last Payment Date: MAX(Payment_Date)
        Map<Id, Date> lastPayDate = new Map<Id, Date>();
        for (AggregateResult ar : [
            SELECT Account__c acctId, MAX(Payment_Date__c) maxDate
            FROM ARF_Payment__c
            WHERE Account__c IN :accountIds
            GROUP BY Account__c
        ]) {
            Id acctId = (Id) ar.get('acctId');
            lastPayDate.put(acctId, (Date) ar.get('maxDate'));
        }

        // 6. DSO: (Total AR / Total Invoiced last 365 days) * 365
        Map<Id, Decimal> totalInvoiced365 = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Account__c acctId, SUM(Amount__c) totalAmt
            FROM ARF_Invoice__c
            WHERE Account__c IN :accountIds
              AND Invoice_Date__c >= LAST_N_DAYS:365
            GROUP BY Account__c
        ]) {
            Id acctId = (Id) ar.get('acctId');
            totalInvoiced365.put(acctId, (Decimal) ar.get('totalAmt'));
        }

        // 7. Avg Days To Pay: AVG(Application_Date - Invoice_Date) for paid invoices
        Map<Id, Decimal> avgDaysToPay = new Map<Id, Decimal>();
        Map<Id, Integer> paidInvCountMap = new Map<Id, Integer>();
        Map<Id, Decimal> totalDaysMap = new Map<Id, Decimal>();
        for (ARF_Invoice__c inv : [
            SELECT Account__c, Invoice_Date__c,
                (SELECT Application_Date__c FROM Payment_Applications__r
                 WHERE Application_Date__c != null ORDER BY Application_Date__c DESC LIMIT 1)
            FROM ARF_Invoice__c
            WHERE Account__c IN :accountIds
              AND Status__c = 'Paid'
              AND Invoice_Date__c != null
        ]) {
            if (!inv.Payment_Applications__r.isEmpty()) {
                Date appDate = inv.Payment_Applications__r[0].Application_Date__c;
                Integer days = inv.Invoice_Date__c.daysBetween(appDate);
                Id acctId = inv.Account__c;
                if (!totalDaysMap.containsKey(acctId)) {
                    totalDaysMap.put(acctId, 0);
                    paidInvCountMap.put(acctId, 0);
                }
                totalDaysMap.put(acctId, totalDaysMap.get(acctId) + days);
                paidInvCountMap.put(acctId, paidInvCountMap.get(acctId) + 1);
            }
        }
        for (Id acctId : totalDaysMap.keySet()) {
            Integer cnt = paidInvCountMap.get(acctId);
            if (cnt > 0) {
                avgDaysToPay.put(acctId, (totalDaysMap.get(acctId) / cnt).setScale(1, RoundingMode.HALF_UP));
            }
        }

        // 8. Aging Buckets + DPD update on individual invoices
        Map<Id, Decimal> currentBucket = new Map<Id, Decimal>();
        Map<Id, Decimal> bucket1_30 = new Map<Id, Decimal>();
        Map<Id, Decimal> bucket31_60 = new Map<Id, Decimal>();
        Map<Id, Decimal> bucket61_90 = new Map<Id, Decimal>();
        Map<Id, Decimal> bucket90Plus = new Map<Id, Decimal>();

        List<ARF_Invoice__c> invoiceUpdates = new List<ARF_Invoice__c>();

        for (ARF_Invoice__c inv : [
            SELECT Id, Account__c, Balance__c, Due_Date__c
            FROM ARF_Invoice__c
            WHERE Account__c IN :accountIds
              AND Status__c NOT IN ('Paid', 'Cancelled', 'Written Off')
        ]) {
            Integer dpd = 0;
            if (inv.Due_Date__c != null) {
                dpd = Math.max(0, inv.Due_Date__c.daysBetween(Date.today()));
            }
            Decimal bal = inv.Balance__c != null ? inv.Balance__c : 0;
            Id acctId = inv.Account__c;

            // Update DPD on invoice
            invoiceUpdates.add(new ARF_Invoice__c(Id = inv.Id, Days_Past_Due__c = dpd));

            // Bucket by DPD
            if (dpd <= 0) {
                currentBucket.put(acctId, (currentBucket.containsKey(acctId) ? currentBucket.get(acctId) : 0) + bal);
            } else if (dpd <= 30) {
                bucket1_30.put(acctId, (bucket1_30.containsKey(acctId) ? bucket1_30.get(acctId) : 0) + bal);
            } else if (dpd <= 60) {
                bucket31_60.put(acctId, (bucket31_60.containsKey(acctId) ? bucket31_60.get(acctId) : 0) + bal);
            } else if (dpd <= 90) {
                bucket61_90.put(acctId, (bucket61_90.containsKey(acctId) ? bucket61_90.get(acctId) : 0) + bal);
            } else {
                bucket90Plus.put(acctId, (bucket90Plus.containsKey(acctId) ? bucket90Plus.get(acctId) : 0) + bal);
            }
        }

        // Update invoice DPD values
        if (!invoiceUpdates.isEmpty()) {
            update invoiceUpdates;
        }

        // 9. Last Contact Method: most recent communication channel
        Map<Id, String> lastContactMethod = new Map<Id, String>();
        for (ARF_Communication__c c : [
            SELECT Account__c, Channel__c
            FROM ARF_Communication__c
            WHERE Account__c IN :accountIds
            ORDER BY Sent_Date__c DESC
        ]) {
            if (!lastContactMethod.containsKey(c.Account__c)) {
                lastContactMethod.put(c.Account__c, c.Channel__c);
            }
        }

        // Build update list
        List<Account> updates = new List<Account>();
        for (Account a : scope) {
            Id aid = a.Id;
            Decimal arVal = totalAR.containsKey(aid) ? totalAR.get(aid) : 0;
            Decimal inv365 = totalInvoiced365.containsKey(aid) ? totalInvoiced365.get(aid) : 0;
            Decimal dso = (inv365 != 0) ? (arVal / inv365 * 365).setScale(1, RoundingMode.HALF_UP) : 0;

            updates.add(new Account(
                Id = aid,
                ARF_Total_AR__c = arVal,
                ARF_Past_Due__c = pastDue.containsKey(aid) ? pastDue.get(aid) : 0,
                ARF_Open_Invoice_Count__c = openInvCount.containsKey(aid) ? openInvCount.get(aid) : 0,
                ARF_Overdue_Invoice_Count__c = overdueCount.containsKey(aid) ? overdueCount.get(aid) : 0,
                ARF_In_Dispute__c = inDispute.containsKey(aid) ? inDispute.get(aid) : 0,
                ARF_Open_Dispute_Count__c = openDisputeCount.containsKey(aid) ? openDisputeCount.get(aid) : 0,
                ARF_Promised_Amount__c = promisedAmt.containsKey(aid) ? promisedAmt.get(aid) : 0,
                ARF_Last_Payment_Date__c = lastPayDate.containsKey(aid) ? lastPayDate.get(aid) : null,
                ARF_DSO__c = dso,
                ARF_Avg_Days_To_Pay__c = avgDaysToPay.containsKey(aid) ? avgDaysToPay.get(aid) : null,
                ARF_Current__c = currentBucket.containsKey(aid) ? currentBucket.get(aid) : 0,
                ARF_1_30_Days__c = bucket1_30.containsKey(aid) ? bucket1_30.get(aid) : 0,
                ARF_31_60_Days__c = bucket31_60.containsKey(aid) ? bucket31_60.get(aid) : 0,
                ARF_61_90_Days__c = bucket61_90.containsKey(aid) ? bucket61_90.get(aid) : 0,
                ARF_Over_90_Days__c = bucket90Plus.containsKey(aid) ? bucket90Plus.get(aid) : 0,
                ARF_Last_Contact_Method__c = lastContactMethod.containsKey(aid) ? lastContactMethod.get(aid) : null,
                ARF_Total_Disputed__c = inDispute.containsKey(aid) ? inDispute.get(aid) : 0
            ));
        }
        update updates;
    }

    public void finish(Database.BatchableContext bc) {
        // No post-processing needed
    }

    // Schedulable interface
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new ARF_AccountRollupJob(), 200);
    }
}
