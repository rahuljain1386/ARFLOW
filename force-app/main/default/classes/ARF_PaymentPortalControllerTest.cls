@isTest
private class ARF_PaymentPortalControllerTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Portal Test Account');
        insert acc;

        // Create invoices
        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 500, Balance__c = 500,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(-20),
            Invoice_Date__c = Date.today().addDays(-50), Document_Number__c = 'PT-INV-001',
            PO_Number__c = 'PO-100'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 300, Balance__c = 300,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(10),
            Invoice_Date__c = Date.today().addDays(-20), Document_Number__c = 'PT-INV-002'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 1000, Balance__c = 0,
            Status__c = 'Paid', Due_Date__c = Date.today().addDays(-60),
            Invoice_Date__c = Date.today().addDays(-90), Document_Number__c = 'PT-INV-003'
        ));
        insert invoices;

        // Create payment method + junction
        ARF_Payment_Method__c pm = new ARF_Payment_Method__c(
            Token__c = 'tok_card_portaltest123',
            Type__c = 'Credit Card',
            Last_Four__c = '4242',
            Card_Brand__c = 'Visa',
            Expiry_Month__c = 12,
            Expiry_Year__c = 2028,
            Status__c = 'Active',
            Nickname__c = 'Test Visa'
        );
        insert pm;

        ARF_Account_Payment_Method__c apm = new ARF_Account_Payment_Method__c(
            Account__c = acc.Id,
            Payment_Method__c = pm.Id,
            Is_Primary__c = true,
            Added_Date__c = Date.today()
        );
        insert apm;

        // Create a historical payment
        ARF_Payment__c payment = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 1000, Applied_Amount__c = 1000,
            Unapplied_Amount__c = 0, Payment_Date__c = Date.today().addDays(-30),
            Method__c = 'ACH', Status__c = 'Applied', Reference__c = 'HIST-001'
        );
        insert payment;
    }

    @isTest
    static void testGetAccountSummary() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        ARF_PaymentPortalController.AccountSummary summary =
            ARF_PaymentPortalController.getAccountSummary(acc.Id);
        Test.stopTest();

        System.assertEquals(acc.Id, summary.accountId);
        System.assertEquals('Portal Test Account', summary.accountName);
        System.assertEquals(800, summary.totalOutstanding); // 500 + 300
        System.assertEquals(500, summary.totalPastDue); // only PT-INV-001
        System.assertEquals(2, summary.openInvoiceCount);
        System.assertEquals(1, summary.pastDueInvoiceCount);
    }

    @isTest
    static void testGetOpenInvoices() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<ARF_PaymentPortalController.InvoiceWrapper> invoices =
            ARF_PaymentPortalController.getOpenInvoices(acc.Id);
        Test.stopTest();

        System.assertEquals(2, invoices.size(), 'Should return 2 open invoices (not the paid one)');
        // First should be overdue
        System.assert(invoices[0].isOverdue, 'First invoice should be overdue');
    }

    @isTest
    static void testGetPaymentMethods() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<ARF_PaymentPortalController.PaymentMethodWrapper> methods =
            ARF_PaymentPortalController.getPaymentMethods(acc.Id);
        Test.stopTest();

        System.assertEquals(1, methods.size());
        System.assertEquals('Credit Card', methods[0].methodType);
        System.assertEquals('4242', methods[0].lastFour);
        System.assert(methods[0].isPrimary);
        System.assert(methods[0].displayLabel.contains('4242'));
    }

    @isTest
    static void testAddCreditCard() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        ARF_PaymentPortalController.PaymentMethodWrapper result =
            ARF_PaymentPortalController.addCreditCard(
                acc.Id, '5555555555554444', '06', '2029', '456', 'Jane Doe', 'Work MC'
            );
        Test.stopTest();

        System.assertEquals('Credit Card', result.methodType);
        System.assertEquals('4444', result.lastFour);
        System.assertEquals('Mastercard', result.cardBrand);
        System.assertEquals('Work MC', result.nickname);
        System.assert(!result.isPrimary, 'Second card should not be primary');
    }

    @isTest
    static void testAddBankAccount() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        ARF_PaymentPortalController.PaymentMethodWrapper result =
            ARF_PaymentPortalController.addBankAccount(
                acc.Id, '021000021', '9876543210', 'Checking', 'John Doe', 'Chase', 'Business Checking'
            );
        Test.stopTest();

        System.assertEquals('ACH', result.methodType);
        System.assertEquals('3210', result.lastFour);
        System.assertEquals('Chase', result.bankName);
    }

    @isTest
    static void testRemovePaymentMethod() {
        ARF_Account_Payment_Method__c apm = [SELECT Id FROM ARF_Account_Payment_Method__c LIMIT 1];

        Test.startTest();
        ARF_PaymentPortalController.removePaymentMethod(apm.Id);
        Test.stopTest();

        Integer remaining = [SELECT COUNT() FROM ARF_Account_Payment_Method__c WHERE Id = :apm.Id];
        System.assertEquals(0, remaining, 'Junction should be deleted');

        ARF_Payment_Method__c pm = [SELECT Status__c FROM ARF_Payment_Method__c LIMIT 1];
        System.assertEquals('Revoked', pm.Status__c, 'Method should be revoked when no links remain');
    }

    @isTest
    static void testSetDefaultPaymentMethod() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        // Add a second card
        ARF_Payment_Method__c pm2 = new ARF_Payment_Method__c(
            Token__c = 'tok_card_second', Type__c = 'Credit Card',
            Last_Four__c = '1234', Card_Brand__c = 'Amex', Status__c = 'Active'
        );
        insert pm2;
        ARF_Account_Payment_Method__c apm2 = new ARF_Account_Payment_Method__c(
            Account__c = acc.Id, Payment_Method__c = pm2.Id, Is_Primary__c = false, Added_Date__c = Date.today()
        );
        insert apm2;

        Test.startTest();
        ARF_PaymentPortalController.setDefaultPaymentMethod(acc.Id, apm2.Id);
        Test.stopTest();

        ARF_Account_Payment_Method__c updated = [SELECT Is_Primary__c FROM ARF_Account_Payment_Method__c WHERE Id = :apm2.Id];
        System.assert(updated.Is_Primary__c, 'New card should be primary');
    }

    @isTest
    static void testProcessPayment() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ARF_Payment_Method__c pm = [SELECT Id FROM ARF_Payment_Method__c LIMIT 1];
        ARF_Invoice__c inv = [SELECT Id, Balance__c FROM ARF_Invoice__c WHERE Document_Number__c = 'PT-INV-001'];

        ARF_PaymentPortalController.PaymentRequest req = new ARF_PaymentPortalController.PaymentRequest();
        req.accountId = acc.Id;
        req.paymentMethodId = pm.Id;
        req.totalAmount = 500;
        req.allocations = new List<ARF_PaymentAllocationEngine.AllocationLine>();
        ARF_PaymentAllocationEngine.AllocationLine line = new ARF_PaymentAllocationEngine.AllocationLine();
        line.invoiceId = inv.Id;
        line.amount = 500;
        req.allocations.add(line);

        Test.startTest();
        ARF_PaymentPortalController.PaymentResult result =
            ARF_PaymentPortalController.processPayment(JSON.serialize(req));
        Test.stopTest();

        System.assert(result.success, 'Payment should succeed: ' + result.message);
        System.assertNotEquals(null, result.paymentId);
        System.assertNotEquals(null, result.confirmationNumber);

        // Verify invoice updated
        ARF_Invoice__c updatedInv = [SELECT Balance__c, Status__c FROM ARF_Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(0, updatedInv.Balance__c);
        System.assertEquals('Paid', updatedInv.Status__c);
    }

    @isTest
    static void testGetPaymentHistory() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<ARF_PaymentPortalController.PaymentHistoryItem> history =
            ARF_PaymentPortalController.getPaymentHistory(acc.Id);
        Test.stopTest();

        System.assert(!history.isEmpty(), 'Should have payment history');
        System.assertEquals('Applied', history[0].status);
    }

    @isTest
    static void testAutopaySchedule() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ARF_Payment_Method__c pm = [SELECT Id FROM ARF_Payment_Method__c LIMIT 1];

        Test.startTest();
        // Save schedule
        ARF_PaymentPortalController.AutopayWrapper result =
            ARF_PaymentPortalController.saveAutopaySchedule(
                acc.Id, pm.Id, 'All Due', null, 5000, 15
            );
        System.assertNotEquals(null, result);
        System.assertEquals('All Due', result.ruleType);
        System.assertEquals(15, result.scheduleDay);
        System.assert(result.isActive);

        // Get schedule
        ARF_PaymentPortalController.AutopayWrapper fetched =
            ARF_PaymentPortalController.getAutopaySchedule(acc.Id);
        System.assertNotEquals(null, fetched);

        // Cancel
        ARF_PaymentPortalController.cancelAutopay(fetched.id);
        Test.stopTest();

        ARF_Autopay_Schedule__c cancelled = [SELECT Status__c, Is_Active__c FROM ARF_Autopay_Schedule__c WHERE Id = :fetched.id];
        System.assertEquals('Cancelled', cancelled.Status__c);
        System.assert(!cancelled.Is_Active__c);
    }

    @isTest
    static void testGetAutopayScheduleNone() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ARF_PaymentPortalController.AutopayWrapper result =
            ARF_PaymentPortalController.getAutopaySchedule(acc.Id);
        System.assertEquals(null, result, 'Should return null when no schedule');
    }
}
