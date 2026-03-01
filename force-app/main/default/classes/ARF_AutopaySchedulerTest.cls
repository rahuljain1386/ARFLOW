@isTest
private class ARF_AutopaySchedulerTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Autopay Test Account');
        insert acc;

        // Create payment method
        ARF_Payment_Method__c pm = new ARF_Payment_Method__c(
            Token__c = 'tok_card_autopaytest123',
            Type__c = 'Credit Card',
            Last_Four__c = '4242',
            Card_Brand__c = 'Visa',
            Status__c = 'Active',
            Nickname__c = 'Business Card'
        );
        insert pm;

        // Create junction
        ARF_Account_Payment_Method__c apm = new ARF_Account_Payment_Method__c(
            Account__c = acc.Id,
            Payment_Method__c = pm.Id,
            Is_Primary__c = true,
            Added_Date__c = Date.today()
        );
        insert apm;

        // Create invoices
        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 500, Balance__c = 500,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(-15),
            Invoice_Date__c = Date.today().addDays(-45), Document_Number__c = 'AP-INV-001'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 300, Balance__c = 300,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(5),
            Invoice_Date__c = Date.today().addDays(-25), Document_Number__c = 'AP-INV-002'
        ));
        insert invoices;

        // Create autopay schedule
        ARF_Autopay_Schedule__c schedule = new ARF_Autopay_Schedule__c(
            Account__c = acc.Id,
            Payment_Method__c = pm.Id,
            Rule_Type__c = 'All Due',
            Schedule_Day__c = Date.today().day(),
            Is_Active__c = true,
            Status__c = 'Active',
            Next_Run_Date__c = Date.today()
        );
        insert schedule;
    }

    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
        ARF_AutopayScheduler scheduler = new ARF_AutopayScheduler();
        String jobId = System.schedule('Test Autopay', '0 0 6 * * ?', scheduler);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be scheduled');
    }

    @isTest
    static void testProcessAutopaySchedules() {
        Test.startTest();
        ARF_AutopayScheduler.processAutopaySchedules();
        Test.stopTest();

        // Verify payment was created
        List<ARF_Payment__c> payments = [
            SELECT Id, Amount__c, Is_Portal_Payment__c, Method__c
            FROM ARF_Payment__c
            WHERE Is_Portal_Payment__c = true
        ];
        System.assert(!payments.isEmpty(), 'Autopay should create a payment');
        System.assertEquals('Credit Card', payments[0].Method__c);

        // Verify schedule was updated
        ARF_Autopay_Schedule__c sched = [
            SELECT Last_Run_Date__c, Next_Run_Date__c
            FROM ARF_Autopay_Schedule__c LIMIT 1
        ];
        System.assertEquals(Date.today(), sched.Last_Run_Date__c);
        System.assertNotEquals(null, sched.Next_Run_Date__c);
    }

    @isTest
    static void testCalculateNextRunDate() {
        ARF_Autopay_Schedule__c sched = new ARF_Autopay_Schedule__c();
        sched.Schedule_Day__c = 15;
        Date nextDate = ARF_AutopayScheduler.calculateNextRunDate(sched);
        System.assertNotEquals(null, nextDate);
        System.assertEquals(15, nextDate.day());
    }

    @isTest
    static void testNoInvoices() {
        // Delete all invoices
        delete [SELECT Id FROM ARF_Invoice__c];

        Test.startTest();
        ARF_AutopayScheduler.processAutopaySchedules();
        Test.stopTest();

        // Should still update schedule dates even with no invoices
        ARF_Autopay_Schedule__c sched = [SELECT Last_Run_Date__c FROM ARF_Autopay_Schedule__c LIMIT 1];
        System.assertEquals(Date.today(), sched.Last_Run_Date__c);
    }
}
