@IsTest
public class ARF_HomeDashboardControllerTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Dashboard Account');
        insert acc;

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id,
            Amount__c = 10000,
            Balance__c = 10000,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-45),
            Due_Date__c = Date.today().addDays(-15)
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id,
            Amount__c = 5000,
            Balance__c = 5000,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-10),
            Due_Date__c = Date.today().addDays(20)
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id,
            Amount__c = 3000,
            Balance__c = 3000,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-100),
            Due_Date__c = Date.today().addDays(-70)
        ));
        insert invoices;

        ARF_Dispute__c dispute = new ARF_Dispute__c(
            Account__c = acc.Id,
            Invoice__c = invoices[0].Id,
            Dispute_Amount__c = 2000,
            Status__c = 'New',
            Category__c = 'Pricing'
        );
        insert dispute;

        ARF_Promise_To_Pay__c promise = new ARF_Promise_To_Pay__c(
            Account__c = acc.Id,
            Invoice__c = invoices[0].Id,
            Amount__c = 5000,
            Promise_Date__c = Date.today().addDays(7),
            Status__c = 'Open'
        );
        insert promise;

        ARF_Payment__c payment = new ARF_Payment__c(
            Account__c = acc.Id,
            Amount__c = 3000,
            Payment_Date__c = Date.today(),
            Status__c = 'Applied',
            Method__c = 'Check'
        );
        insert payment;

        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = acc.Id,
            Channel__c = 'Email',
            Direction__c = 'Outbound',
            Subject__c = 'Payment Reminder',
            Sent_Date__c = Datetime.now(),
            Status__c = 'Sent'
        );
        insert comm;
    }

    @IsTest
    static void testGetDashboardData() {
        Test.startTest();
        ARF_HomeDashboardController.DashboardData data =
            ARF_HomeDashboardController.getDashboardData();
        Test.stopTest();

        System.assertNotEquals(null, data, 'Data should not be null');
        System.assert(data.totalAR > 0, 'Should have total AR');
        System.assertEquals(3, data.openInvoiceCount, 'Should have 3 open invoices');
        System.assert(data.inDispute > 0, 'Should have dispute amount');
        System.assertEquals(1, data.openDisputeCount, 'Should have 1 open dispute');
        System.assert(data.promisedAmount > 0, 'Should have promised amount');
        System.assertEquals(1, data.promiseCount, 'Should have 1 promise');
        System.assert(data.paymentsThisMonth > 0, 'Should have payments this month');
        System.assertEquals(5, data.agingBuckets.size(), 'Should have 5 aging buckets');
        System.assert(data.topAccounts.size() > 0, 'Should have top accounts');
        System.assertNotEquals(null, data.paymentTrend, 'Payment trend should not be null');
        System.assert(data.disputeBreakdown.size() > 0, 'Should have dispute breakdown');
        System.assert(data.recentActivity.size() > 0, 'Should have recent activity');
    }
}
