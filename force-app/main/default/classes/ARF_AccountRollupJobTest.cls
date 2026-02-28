@isTest
private class ARF_AccountRollupJobTest {

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(Name = 'Rollup Test Account');
        insert acct;

        // Open invoices (2 overdue, 1 future)
        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'RU-001',
            Amount__c = 10000,
            Balance__c = 10000,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-45),
            Due_Date__c = Date.today().addDays(-15)
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'RU-002',
            Amount__c = 5000,
            Balance__c = 3000,
            Status__c = 'Partially Paid',
            Invoice_Date__c = Date.today().addDays(-30),
            Due_Date__c = Date.today().addDays(-5)
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'RU-003',
            Amount__c = 8000,
            Balance__c = 8000,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-10),
            Due_Date__c = Date.today().addDays(20)
        ));
        // Paid invoice (for avg days to pay)
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'RU-004',
            Amount__c = 15000,
            Balance__c = 0,
            Status__c = 'Paid',
            Invoice_Date__c = Date.today().addDays(-60),
            Due_Date__c = Date.today().addDays(-30)
        ));
        // Invoice 61-90 days overdue
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'RU-005',
            Amount__c = 4000,
            Balance__c = 4000,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-100),
            Due_Date__c = Date.today().addDays(-75)
        ));
        // Invoice 90+ days overdue
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Document_Number__c = 'RU-006',
            Amount__c = 2000,
            Balance__c = 2000,
            Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-150),
            Due_Date__c = Date.today().addDays(-95)
        ));
        insert invoices;

        // Payment application on paid invoice
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acct.Id,
            Amount__c = 15000,
            Payment_Date__c = Date.today().addDays(-20),
            Method__c = 'ACH',
            Status__c = 'Applied',
            Applied_Amount__c = 15000,
            Unapplied_Amount__c = 0
        );
        insert pmt;

        ARF_Payment_Application__c pa = new ARF_Payment_Application__c(
            Invoice__c = invoices[3].Id,
            Payment__c = pmt.Id,
            Amount_Applied__c = 15000,
            Application_Date__c = Date.today().addDays(-20)
        );
        insert pa;

        // Open disputes
        List<ARF_Dispute__c> disputes = new List<ARF_Dispute__c>();
        disputes.add(new ARF_Dispute__c(
            Account__c = acct.Id,
            Invoice__c = invoices[0].Id,
            Dispute_Amount__c = 2000,
            Status__c = 'New',
            Category__c = 'Pricing',
            Priority__c = 'High'
        ));
        disputes.add(new ARF_Dispute__c(
            Account__c = acct.Id,
            Invoice__c = invoices[1].Id,
            Dispute_Amount__c = 1000,
            Status__c = 'Under Investigation',
            Category__c = 'Shortage',
            Priority__c = 'Medium'
        ));
        insert disputes;

        // Open promise to pay
        ARF_Promise_To_Pay__c ptp = new ARF_Promise_To_Pay__c(
            Account__c = acct.Id,
            Amount__c = 5000,
            Promise_Date__c = Date.today().addDays(7),
            Status__c = 'Open'
        );
        insert ptp;

        // Communication for last contact method
        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = acct.Id,
            Channel__c = 'Phone',
            Direction__c = 'Outbound',
            Subject__c = 'Collection Call',
            Body__c = 'Called about overdue invoices',
            Status__c = 'Sent',
            Sent_Date__c = Datetime.now().addDays(-1)
        );
        insert comm;
    }

    private static Account getTestAccount() {
        return [SELECT Id, ARF_Total_AR__c, ARF_Past_Due__c, ARF_Open_Invoice_Count__c,
                    ARF_Overdue_Invoice_Count__c, ARF_In_Dispute__c, ARF_Open_Dispute_Count__c,
                    ARF_Promised_Amount__c, ARF_Last_Payment_Date__c, ARF_DSO__c, ARF_Avg_Days_To_Pay__c,
                    ARF_Current__c, ARF_1_30_Days__c, ARF_31_60_Days__c, ARF_61_90_Days__c,
                    ARF_Over_90_Days__c, ARF_Last_Contact_Method__c, ARF_Total_Disputed__c
                FROM Account WHERE Name = 'Rollup Test Account' LIMIT 1];
    }

    @isTest
    static void testTotalARAndOpenCount() {
        Test.startTest();
        Database.executeBatch(new ARF_AccountRollupJob(), 200);
        Test.stopTest();

        Account a = getTestAccount();
        // 5 open invoices: 10000 + 3000 + 8000 + 4000 + 2000 = 27000
        System.assertEquals(27000, a.ARF_Total_AR__c, 'Total AR should be sum of open balances');
        System.assertEquals(5, a.ARF_Open_Invoice_Count__c, 'Should have 5 open invoices');
    }

    @isTest
    static void testPastDueAndOverdueCount() {
        Test.startTest();
        Database.executeBatch(new ARF_AccountRollupJob(), 200);
        Test.stopTest();

        Account a = getTestAccount();
        // 4 overdue: 10000 + 3000 + 4000 + 2000 = 19000
        System.assertEquals(19000, a.ARF_Past_Due__c, 'Past due should be sum of overdue balances');
        System.assertEquals(4, a.ARF_Overdue_Invoice_Count__c, 'Should have 4 overdue invoices');
    }

    @isTest
    static void testInDisputeAndDisputeCount() {
        Test.startTest();
        Database.executeBatch(new ARF_AccountRollupJob(), 200);
        Test.stopTest();

        Account a = getTestAccount();
        // 2 open disputes: 2000 + 1000 = 3000
        System.assertEquals(3000, a.ARF_In_Dispute__c, 'In dispute should be sum of open dispute amounts');
        System.assertEquals(2, a.ARF_Open_Dispute_Count__c, 'Should have 2 open disputes');
    }

    @isTest
    static void testPromisedAmount() {
        Test.startTest();
        Database.executeBatch(new ARF_AccountRollupJob(), 200);
        Test.stopTest();

        Account a = getTestAccount();
        System.assertEquals(5000, a.ARF_Promised_Amount__c, 'Promised amount should be 5000');
    }

    @isTest
    static void testLastPaymentDate() {
        Test.startTest();
        Database.executeBatch(new ARF_AccountRollupJob(), 200);
        Test.stopTest();

        Account a = getTestAccount();
        System.assertEquals(Date.today().addDays(-20), a.ARF_Last_Payment_Date__c, 'Last payment date should match');
    }

    @isTest
    static void testDSOAndAvgDaysToPay() {
        Test.startTest();
        Database.executeBatch(new ARF_AccountRollupJob(), 200);
        Test.stopTest();

        Account a = getTestAccount();
        System.assertNotEquals(null, a.ARF_DSO__c, 'DSO should be calculated');
        System.assert(a.ARF_DSO__c > 0, 'DSO should be positive');
        // Avg days to pay: invoice date -60, app date -20 = 40 days
        System.assertEquals(40.0, a.ARF_Avg_Days_To_Pay__c, 'Avg days to pay should be 40');
    }

    @isTest
    static void testAgingBuckets() {
        Test.startTest();
        Database.executeBatch(new ARF_AccountRollupJob(), 200);
        Test.stopTest();

        Account a = getTestAccount();
        // RU-003: due in +20 days → current = 8000
        System.assertEquals(8000, a.ARF_Current__c, 'Current bucket should be 8000');
        // RU-002: 5 DPD, RU-001: 15 DPD → 1-30 = 3000 + 10000 = 13000
        System.assertEquals(13000, a.ARF_1_30_Days__c, '1-30 bucket should be 13000');
        // No invoices 31-60 DPD
        System.assertEquals(0, a.ARF_31_60_Days__c, '31-60 bucket should be 0');
        // RU-005: 75 DPD → 61-90 = 4000
        System.assertEquals(4000, a.ARF_61_90_Days__c, '61-90 bucket should be 4000');
        // RU-006: 95 DPD → 90+ = 2000
        System.assertEquals(2000, a.ARF_Over_90_Days__c, '90+ bucket should be 2000');
    }

    @isTest
    static void testDaysPastDueOnInvoices() {
        Test.startTest();
        Database.executeBatch(new ARF_AccountRollupJob(), 200);
        Test.stopTest();

        // Verify DPD was updated on individual invoices
        ARF_Invoice__c inv = [
            SELECT Days_Past_Due__c FROM ARF_Invoice__c
            WHERE Document_Number__c = 'RU-001' LIMIT 1
        ];
        System.assertEquals(15, inv.Days_Past_Due__c, 'DPD should be 15 for RU-001');

        ARF_Invoice__c futureInv = [
            SELECT Days_Past_Due__c FROM ARF_Invoice__c
            WHERE Document_Number__c = 'RU-003' LIMIT 1
        ];
        System.assertEquals(0, futureInv.Days_Past_Due__c, 'DPD should be 0 for future invoice');
    }

    @isTest
    static void testLastContactMethod() {
        Test.startTest();
        Database.executeBatch(new ARF_AccountRollupJob(), 200);
        Test.stopTest();

        Account a = getTestAccount();
        System.assertEquals('Phone', a.ARF_Last_Contact_Method__c, 'Last contact method should be Phone');
    }

    @isTest
    static void testTotalDisputed() {
        Test.startTest();
        Database.executeBatch(new ARF_AccountRollupJob(), 200);
        Test.stopTest();

        Account a = getTestAccount();
        System.assertEquals(3000, a.ARF_Total_Disputed__c, 'Total disputed should be 3000');
    }

    @isTest
    static void testSchedulableInterface() {
        Test.startTest();
        String jobId = System.schedule('Test Rollup', '0 0 0 1 1 ?', new ARF_AccountRollupJob());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Job should be scheduled');
    }
}
