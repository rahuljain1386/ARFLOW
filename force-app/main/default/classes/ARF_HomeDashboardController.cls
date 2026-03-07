public with sharing class ARF_HomeDashboardController {

    public class DashboardData {
        @AuraEnabled public Decimal totalAR = 0;
        @AuraEnabled public Integer openInvoiceCount = 0;
        @AuraEnabled public Decimal pastDue = 0;
        @AuraEnabled public Integer overdueCount = 0;
        @AuraEnabled public Decimal inDispute = 0;
        @AuraEnabled public Integer openDisputeCount = 0;
        @AuraEnabled public Decimal promisedAmount = 0;
        @AuraEnabled public Integer promiseCount = 0;
        @AuraEnabled public Decimal paymentsThisMonth = 0;
        @AuraEnabled public List<AgingBucket> agingBuckets = new List<AgingBucket>();
        @AuraEnabled public List<TopAccount> topAccounts = new List<TopAccount>();
        @AuraEnabled public List<PaymentMonth> paymentTrend = new List<PaymentMonth>();
        @AuraEnabled public List<DisputeStatus> disputeBreakdown = new List<DisputeStatus>();
        @AuraEnabled public List<ActivityItem> recentActivity = new List<ActivityItem>();
    }

    public class AgingBucket {
        @AuraEnabled public String label;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String color;

        public AgingBucket(String label, Decimal amount, String color) {
            this.label = label;
            this.amount = amount;
            this.color = color;
        }
    }

    public class TopAccount {
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Decimal balance;
    }

    public class PaymentMonth {
        @AuraEnabled public String label;
        @AuraEnabled public Decimal amount;
    }

    public class DisputeStatus {
        @AuraEnabled public String status;
        @AuraEnabled public Integer count;
        @AuraEnabled public Decimal amount;
    }

    public class ActivityItem {
        @AuraEnabled public String id;
        @AuraEnabled public String type;
        @AuraEnabled public String description;
        @AuraEnabled public String accountName;
        @AuraEnabled public String timeAgo;
        @AuraEnabled public String icon;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        DashboardData data = new DashboardData();

        loadInvoiceSummary(data);
        loadDisputeSummary(data);
        loadPromiseSummary(data);
        loadPaymentSummary(data);
        data.topAccounts = loadTopAccounts();
        data.paymentTrend = loadPaymentTrend();
        data.disputeBreakdown = loadDisputeBreakdown();
        data.recentActivity = loadRecentActivity();

        return data;
    }

    private static void loadInvoiceSummary(DashboardData data) {
        List<ARF_Invoice__c> invoices = [
            SELECT Balance__c, Days_Past_Due__c, Is_Overdue__c
            FROM ARF_Invoice__c
            WHERE Status__c NOT IN ('Paid', 'Cancelled', 'Void')
        ];

        Decimal totalAR = 0;
        Decimal pastDue = 0;
        Integer overdueCount = 0;
        Decimal current = 0;
        Decimal d130 = 0;
        Decimal d3160 = 0;
        Decimal d6190 = 0;
        Decimal d90plus = 0;

        for (ARF_Invoice__c inv : invoices) {
            Decimal bal = inv.Balance__c != null ? inv.Balance__c : 0;
            Decimal dpd = inv.Days_Past_Due__c != null ? inv.Days_Past_Due__c : 0;
            totalAR += bal;

            if (inv.Is_Overdue__c) {
                pastDue += bal;
                overdueCount++;
            }

            if (dpd <= 0) {
                current += bal;
            } else if (dpd <= 30) {
                d130 += bal;
            } else if (dpd <= 60) {
                d3160 += bal;
            } else if (dpd <= 90) {
                d6190 += bal;
            } else {
                d90plus += bal;
            }
        }

        data.totalAR = totalAR;
        data.openInvoiceCount = invoices.size();
        data.pastDue = pastDue;
        data.overdueCount = overdueCount;

        data.agingBuckets.add(new AgingBucket('Current', current, '#22c55e'));
        data.agingBuckets.add(new AgingBucket('1-30', d130, '#f59e0b'));
        data.agingBuckets.add(new AgingBucket('31-60', d3160, '#f97316'));
        data.agingBuckets.add(new AgingBucket('61-90', d6190, '#ef4444'));
        data.agingBuckets.add(new AgingBucket('90+', d90plus, '#b91c1c'));
    }

    private static void loadDisputeSummary(DashboardData data) {
        AggregateResult[] result = [
            SELECT SUM(Dispute_Amount__c) total, COUNT(Id) cnt
            FROM ARF_Dispute__c
            WHERE Status__c NOT IN ('Resolved', 'Closed')
        ];
        data.inDispute = result[0].get('total') != null ? (Decimal)result[0].get('total') : 0;
        data.openDisputeCount = (Integer)result[0].get('cnt');
    }

    private static void loadPromiseSummary(DashboardData data) {
        AggregateResult[] result = [
            SELECT SUM(Amount__c) total, COUNT(Id) cnt
            FROM ARF_Promise_To_Pay__c
            WHERE Status__c = 'Open'
        ];
        data.promisedAmount = result[0].get('total') != null ? (Decimal)result[0].get('total') : 0;
        data.promiseCount = (Integer)result[0].get('cnt');
    }

    private static void loadPaymentSummary(DashboardData data) {
        AggregateResult[] result = [
            SELECT SUM(Amount__c) total
            FROM ARF_Payment__c
            WHERE Payment_Date__c = THIS_MONTH
            AND Status__c NOT IN ('Reversed', 'Void')
        ];
        data.paymentsThisMonth = result[0].get('total') != null ? (Decimal)result[0].get('total') : 0;
    }

    private static List<TopAccount> loadTopAccounts() {
        List<TopAccount> accounts = new List<TopAccount>();
        for (AggregateResult ar : [
            SELECT Account__c acctId, Account__r.Name acctName, SUM(Balance__c) total
            FROM ARF_Invoice__c
            WHERE Status__c NOT IN ('Paid', 'Cancelled', 'Void')
            AND Account__c != null
            GROUP BY Account__c, Account__r.Name
            ORDER BY SUM(Balance__c) DESC
            LIMIT 8
        ]) {
            TopAccount ta = new TopAccount();
            ta.accountId = (String)ar.get('acctId');
            ta.accountName = (String)ar.get('acctName');
            ta.balance = (Decimal)ar.get('total');
            accounts.add(ta);
        }
        return accounts;
    }

    private static List<PaymentMonth> loadPaymentTrend() {
        List<PaymentMonth> months = new List<PaymentMonth>();
        String[] monthNames = new String[]{
            '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        };

        for (AggregateResult ar : [
            SELECT CALENDAR_MONTH(Payment_Date__c) m,
                   CALENDAR_YEAR(Payment_Date__c) y,
                   SUM(Amount__c) total
            FROM ARF_Payment__c
            WHERE Payment_Date__c = LAST_N_MONTHS:5
            AND Status__c NOT IN ('Reversed', 'Void')
            GROUP BY CALENDAR_MONTH(Payment_Date__c), CALENDAR_YEAR(Payment_Date__c)
            ORDER BY CALENDAR_YEAR(Payment_Date__c), CALENDAR_MONTH(Payment_Date__c)
        ]) {
            PaymentMonth pm = new PaymentMonth();
            Integer monthNum = (Integer)ar.get('m');
            pm.label = monthNames[monthNum];
            pm.amount = ar.get('total') != null ? (Decimal)ar.get('total') : 0;
            months.add(pm);
        }
        return months;
    }

    private static List<DisputeStatus> loadDisputeBreakdown() {
        List<DisputeStatus> statuses = new List<DisputeStatus>();
        for (AggregateResult ar : [
            SELECT Status__c status, COUNT(Id) cnt, SUM(Dispute_Amount__c) total
            FROM ARF_Dispute__c
            GROUP BY Status__c
            ORDER BY COUNT(Id) DESC
        ]) {
            DisputeStatus ds = new DisputeStatus();
            ds.status = (String)ar.get('status');
            ds.count = (Integer)ar.get('cnt');
            ds.amount = ar.get('total') != null ? (Decimal)ar.get('total') : 0;
            statuses.add(ds);
        }
        return statuses;
    }

    private static List<ActivityItem> loadRecentActivity() {
        List<ActivityItem> items = new List<ActivityItem>();
        for (ARF_Communication__c c : [
            SELECT Id, Subject__c, Channel__c, Account__r.Name, Sent_Date__c, Direction__c
            FROM ARF_Communication__c
            WHERE Sent_Date__c != null
            ORDER BY Sent_Date__c DESC
            LIMIT 8
        ]) {
            ActivityItem item = new ActivityItem();
            item.id = c.Id;
            item.type = c.Channel__c;
            String dir = c.Direction__c == 'Inbound' ? 'from' : 'to';
            item.description = c.Channel__c + ' ' + dir + ' ' + (c.Account__r.Name != null ? c.Account__r.Name : 'Unknown');
            if (c.Subject__c != null) {
                item.description += ': ' + c.Subject__c.abbreviate(50);
            }
            item.accountName = c.Account__r.Name;
            item.timeAgo = getTimeAgo(c.Sent_Date__c);

            if (c.Channel__c == 'Email') {
                item.icon = 'utility:email';
            } else if (c.Channel__c == 'Phone') {
                item.icon = 'utility:call';
            } else if (c.Channel__c == 'SMS') {
                item.icon = 'utility:chat';
            } else {
                item.icon = 'utility:comments';
            }

            items.add(item);
        }
        return items;
    }

    private static String getTimeAgo(Datetime dt) {
        if (dt == null) return '';
        Long minutes = (Datetime.now().getTime() - dt.getTime()) / 60000;
        if (minutes < 60) return minutes + 'm ago';
        Long hours = minutes / 60;
        if (hours < 24) return hours + 'h ago';
        Long days = hours / 24;
        if (days < 7) return days + 'd ago';
        return dt.format('MMM d');
    }
}
