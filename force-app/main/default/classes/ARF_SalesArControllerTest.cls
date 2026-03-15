@isTest
private class ARF_SalesArControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create Account with AR fields
        Account acct = new Account(
            Name = 'Sales AR Test Account',
            ARF_Total_AR__c = 150000,
            ARF_Past_Due__c = 45000,
            ARF_DSO__c = 42,
            ARF_Risk_Score__c = 55,
            ARF_Credit_Limit__c = 200000,
            ARF_Open_Invoice_Count__c = 8,
            ARF_Current__c = 105000,
            ARF_1_30_Days__c = 20000,
            ARF_31_60_Days__c = 10000,
            ARF_61_90_Days__c = 10000,
            ARF_Over_90_Days__c = 5000,
            ARF_Last_Contact_Date__c = Date.today().addDays(-3)
        );
        insert acct;

        // Create invoices — use Due_Date__c to drive Days_Past_Due__c formula
        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Status__c = 'Open',
            Amount__c = 10000,
            Balance__c = 10000,
            Due_Date__c = Date.today().addDays(-75)
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Status__c = 'Open',
            Amount__c = 5000,
            Balance__c = 5000,
            Due_Date__c = Date.today().addDays(-95)
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Status__c = 'Open',
            Amount__c = 20000,
            Balance__c = 20000,
            Due_Date__c = Date.today().addDays(-15)
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id,
            Status__c = 'Paid',
            Amount__c = 8000,
            Balance__c = 0,
            Due_Date__c = Date.today().addDays(-100)
        ));
        insert invoices;

        // Create disputes on the first invoice
        ARF_Dispute__c dispute = new ARF_Dispute__c(
            Invoice__c = invoices[0].Id,
            Status__c = 'Under Investigation',
            Dispute_Amount__c = 5000,
            Category__c = 'Pricing',
            Account__c = acct.Id
        );
        insert dispute;

        // Create a broken promise to pay on the second invoice
        ARF_Promise_To_Pay__c promise = new ARF_Promise_To_Pay__c(
            Invoice__c = invoices[1].Id,
            Status__c = 'Broken',
            Amount__c = 5000,
            Promise_Date__c = Date.today().addDays(-10),
            Account__c = acct.Id
        );
        insert promise;

        // Create a communication
        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = acct.Id,
            Channel__c = 'Email',
            Subject__c = 'Follow-up on outstanding invoices',
            Direction__c = 'Outbound'
        );
        insert comm;
    }

    private static Account getTestAccount() {
        return [SELECT Id FROM Account WHERE Name = 'Sales AR Test Account' LIMIT 1];
    }

    @isTest
    static void testGetArSummary_WithData() {
        Account acct = getTestAccount();

        Test.startTest();
        ARF_SalesArController.ArSummary summary = ARF_SalesArController.getArSummary(acct.Id);
        Test.stopTest();

        System.assertNotEquals(null, summary, 'Summary should not be null');
        System.assertEquals(150000, summary.totalAR, 'Total AR should be 150000');
        System.assertEquals(45000, summary.pastDue, 'Past due should be 45000');
        System.assertEquals(42, summary.dso, 'DSO should be 42');
        System.assertEquals(55, summary.riskScore, 'Risk score should be 55');
        System.assertEquals(8, summary.openInvoiceCount, 'Open invoice count should be 8');
        System.assertEquals(200000, summary.creditLimit, 'Credit limit should be 200000');

        // Aging
        System.assertEquals(105000, summary.agingCurrent, 'Current aging should be 105000');
        System.assertEquals(20000, summary.aging1to30, '1-30 aging should be 20000');
        System.assertEquals(10000, summary.aging31to60, '31-60 aging should be 10000');
        System.assertEquals(10000, summary.aging61to90, '61-90 aging should be 10000');
        System.assertEquals(5000, summary.agingOver90, 'Over 90 aging should be 5000');

        // Past due over 60
        System.assertEquals(15000, summary.pastDueOver60, 'Past due over 60 should be 15000');

        // Invoices over 60 days (2 open invoices with DPD > 60)
        System.assertEquals(2, summary.invoicesOver60, 'Should have 2 invoices over 60 days');

        // Open disputes
        System.assertEquals(1, summary.openDisputes, 'Should have 1 open dispute');

        // Broken promises
        System.assertEquals(1, summary.brokenPromises, 'Should have 1 broken promise');

        // Credit utilization
        System.assertEquals(75.0, summary.creditUtilization, 'Credit utilization should be 75%');

        // Last contact
        System.assertNotEquals('Never', summary.lastContactDate, 'Last contact date should not be Never');
        System.assert(summary.lastContactSummary.contains('Email'), 'Last contact summary should mention Email');
    }

    @isTest
    static void testGetArSummary_NoArData() {
        // Create account with no AR data
        Account emptyAcct = new Account(Name = 'Empty AR Account');
        insert emptyAcct;

        Test.startTest();
        ARF_SalesArController.ArSummary summary = ARF_SalesArController.getArSummary(emptyAcct.Id);
        Test.stopTest();

        System.assertNotEquals(null, summary, 'Summary should not be null');
        System.assertEquals(0, summary.totalAR, 'Total AR should default to 0');
        System.assertEquals(0, summary.pastDue, 'Past due should default to 0');
        System.assertEquals(0, summary.dso, 'DSO should default to 0');
        System.assertEquals(0, summary.riskScore, 'Risk score should default to 0');
        System.assertEquals(0, summary.openInvoiceCount, 'Open invoice count should default to 0');
        System.assertEquals(0, summary.creditLimit, 'Credit limit should default to 0');
        System.assertEquals(0, summary.creditUtilization, 'Credit utilization should be 0 when no limit');
        System.assertEquals(0, summary.invoicesOver60, 'Invoices over 60 should be 0');
        System.assertEquals(0, summary.openDisputes, 'Disputes should be 0');
        System.assertEquals(0, summary.brokenPromises, 'Broken promises should be 0');
        System.assertEquals('Never', summary.lastContactDate, 'Last contact should be Never');
        System.assertEquals('No communications on record', summary.lastContactSummary, 'Should show no communications');
    }

    @isTest
    static void testGetArSummary_CreditUtilizationCalculation() {
        Account acct = new Account(
            Name = 'High Utilization Account',
            ARF_Total_AR__c = 180000,
            ARF_Credit_Limit__c = 200000
        );
        insert acct;

        Test.startTest();
        ARF_SalesArController.ArSummary summary = ARF_SalesArController.getArSummary(acct.Id);
        Test.stopTest();

        System.assertEquals(90.0, summary.creditUtilization, 'Credit utilization should be 90%');
    }

    @isTest
    static void testGetArSummary_CommunicationWithNoSubject() {
        Account acct = new Account(Name = 'Comm No Subject Account');
        insert acct;

        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = acct.Id,
            Channel__c = 'Phone',
            Direction__c = 'Outbound'
        );
        insert comm;

        Test.startTest();
        ARF_SalesArController.ArSummary summary = ARF_SalesArController.getArSummary(acct.Id);
        Test.stopTest();

        System.assert(summary.lastContactSummary.contains('No subject'),
            'Should show No subject when subject is null');
    }
}
