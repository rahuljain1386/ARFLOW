@isTest
private class ARF_PaymentAllocationEngineTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Account Alloc');
        insert acc;

        // Create 3 invoices
        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 100, Balance__c = 100,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(-30),
            Invoice_Date__c = Date.today().addDays(-60), Document_Number__c = 'INV-001'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 200, Balance__c = 200,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(-10),
            Invoice_Date__c = Date.today().addDays(-40), Document_Number__c = 'INV-002'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 150, Balance__c = 150,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(20),
            Invoice_Date__c = Date.today().addDays(-10), Document_Number__c = 'INV-003'
        ));
        insert invoices;

        // Create a payment
        ARF_Payment__c payment = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 250, Applied_Amount__c = 0,
            Unapplied_Amount__c = 250, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'ACH'
        );
        insert payment;
    }

    @isTest
    static void testAllocatePayment() {
        ARF_Payment__c payment = [SELECT Id FROM ARF_Payment__c LIMIT 1];
        List<ARF_Invoice__c> invoices = [SELECT Id, Balance__c FROM ARF_Invoice__c ORDER BY Document_Number__c];

        List<ARF_PaymentAllocationEngine.AllocationLine> lines = new List<ARF_PaymentAllocationEngine.AllocationLine>();
        ARF_PaymentAllocationEngine.AllocationLine line1 = new ARF_PaymentAllocationEngine.AllocationLine();
        line1.invoiceId = invoices[0].Id;
        line1.amount = 100;
        lines.add(line1);

        ARF_PaymentAllocationEngine.AllocationLine line2 = new ARF_PaymentAllocationEngine.AllocationLine();
        line2.invoiceId = invoices[1].Id;
        line2.amount = 150;
        lines.add(line2);

        Test.startTest();
        ARF_PaymentAllocationEngine.AllocationResult result = ARF_PaymentAllocationEngine.allocatePayment(payment.Id, lines);
        Test.stopTest();

        System.assert(result.success, 'Allocation should succeed: ' + result.message);
        System.assertEquals(2, result.applicationIds.size());

        // Check invoice balances
        ARF_Invoice__c inv1 = [SELECT Balance__c, Status__c FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-001'];
        System.assertEquals(0, inv1.Balance__c);
        System.assertEquals('Paid', inv1.Status__c);

        ARF_Invoice__c inv2 = [SELECT Balance__c, Status__c FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-002'];
        System.assertEquals(50, inv2.Balance__c);
        System.assertEquals('Partially Paid', inv2.Status__c);

        // Check payment
        ARF_Payment__c updatedPayment = [SELECT Applied_Amount__c, Unapplied_Amount__c, Status__c FROM ARF_Payment__c WHERE Id = :payment.Id];
        System.assertEquals(250, updatedPayment.Applied_Amount__c);
        System.assertEquals(0, updatedPayment.Unapplied_Amount__c);
        System.assertEquals('Applied', updatedPayment.Status__c);
    }

    @isTest
    static void testAllocateExceedsBalance() {
        ARF_Payment__c payment = [SELECT Id FROM ARF_Payment__c LIMIT 1];
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-001'];

        List<ARF_PaymentAllocationEngine.AllocationLine> lines = new List<ARF_PaymentAllocationEngine.AllocationLine>();
        ARF_PaymentAllocationEngine.AllocationLine line1 = new ARF_PaymentAllocationEngine.AllocationLine();
        line1.invoiceId = inv.Id;
        line1.amount = 999;
        lines.add(line1);

        ARF_PaymentAllocationEngine.AllocationResult result = ARF_PaymentAllocationEngine.allocatePayment(payment.Id, lines);
        System.assert(!result.success, 'Should fail when exceeding balance');
    }

    @isTest
    static void testAutoAllocate() {
        ARF_Payment__c payment = [SELECT Id FROM ARF_Payment__c LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        ARF_PaymentAllocationEngine.AllocationResult result = ARF_PaymentAllocationEngine.autoAllocate(payment.Id, acc.Id);
        Test.stopTest();

        System.assert(result.success, 'Auto allocation should succeed: ' + result.message);

        // Should allocate to oldest past-due first (INV-001: 100), then INV-002 (150 of 200)
        ARF_Invoice__c inv1 = [SELECT Balance__c FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-001'];
        System.assertEquals(0, inv1.Balance__c, 'Oldest past due should be fully paid');
    }

    @isTest
    static void testReversePayment() {
        // First allocate
        ARF_Payment__c payment = [SELECT Id FROM ARF_Payment__c LIMIT 1];
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-001'];

        List<ARF_PaymentAllocationEngine.AllocationLine> lines = new List<ARF_PaymentAllocationEngine.AllocationLine>();
        ARF_PaymentAllocationEngine.AllocationLine line1 = new ARF_PaymentAllocationEngine.AllocationLine();
        line1.invoiceId = inv.Id;
        line1.amount = 100;
        lines.add(line1);

        ARF_PaymentAllocationEngine.allocatePayment(payment.Id, lines);

        Test.startTest();
        ARF_PaymentAllocationEngine.AllocationResult reverseResult = ARF_PaymentAllocationEngine.reversePayment(payment.Id);
        Test.stopTest();

        System.assert(reverseResult.success, 'Reversal should succeed');

        ARF_Invoice__c invAfter = [SELECT Balance__c, Status__c FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-001'];
        System.assertEquals(100, invAfter.Balance__c, 'Balance should be restored');
        System.assertEquals('Open', invAfter.Status__c);
    }

    @isTest
    static void testAllocateNegativeAmount() {
        ARF_Payment__c payment = [SELECT Id FROM ARF_Payment__c LIMIT 1];
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-001'];

        List<ARF_PaymentAllocationEngine.AllocationLine> lines = new List<ARF_PaymentAllocationEngine.AllocationLine>();
        ARF_PaymentAllocationEngine.AllocationLine line1 = new ARF_PaymentAllocationEngine.AllocationLine();
        line1.invoiceId = inv.Id;
        line1.amount = -50;
        lines.add(line1);

        ARF_PaymentAllocationEngine.AllocationResult result = ARF_PaymentAllocationEngine.allocatePayment(payment.Id, lines);
        System.assert(!result.success, 'Should fail for negative amount');
    }
}
