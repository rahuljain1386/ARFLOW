@isTest
private class ARF_PromiseToPayControllerTest {

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(Name = 'PTP Controller Test Account');
        insert acct;

        ARF_Invoice__c inv = new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'PTP-001',
            Amount__c = 30000, Balance__c = 30000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-30),
            Due_Date__c = Date.today().addDays(-5)
        );
        insert inv;

        ARF_Promise_To_Pay__c ptp = new ARF_Promise_To_Pay__c(
            Account__c = acct.Id, Invoice__c = inv.Id,
            Amount__c = 10000, Amount_Received__c = 0,
            Promise_Date__c = Date.today().addDays(7),
            Status__c = 'Open'
        );
        insert ptp;
    }

    private static Account getTestAccount() {
        return [SELECT Id FROM Account WHERE Name = 'PTP Controller Test Account' LIMIT 1];
    }

    @isTest
    static void testGetPromises() {
        Account acct = getTestAccount();
        Test.startTest();
        List<ARF_Promise_To_Pay__c> result = ARF_PromiseToPayController.getPromises(acct.Id);
        Test.stopTest();
        System.assertEquals(1, result.size(), 'Should return 1 promise');
        System.assertEquals(10000, result[0].Amount__c, 'Amount should match');
    }

    @isTest
    static void testGetPromisesNullId() {
        Test.startTest();
        try {
            ARF_PromiseToPayController.getPromises(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateInstallmentPlan() {
        Account acct = getTestAccount();
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c WHERE Account__c = :acct.Id LIMIT 1];

        Test.startTest();
        List<ARF_Promise_To_Pay__c> result = ARF_PromiseToPayController.createInstallmentPlan(
            acct.Id, inv.Id, 9000, 3, Date.today().addDays(7), 30, 'Payment plan'
        );
        Test.stopTest();

        System.assertEquals(3, result.size(), 'Should create 3 installments');
        Decimal total = 0;
        for (ARF_Promise_To_Pay__c p : result) {
            total += p.Amount__c;
            System.assertEquals('Open', p.Status__c, 'All should be Open');
            System.assertEquals(3, p.Installment_Count__c, 'Installment count should be 3');
        }
        System.assertEquals(9000, total, 'Total should equal original amount');
    }

    @isTest
    static void testCancelPromise() {
        ARF_Promise_To_Pay__c ptp = [SELECT Id FROM ARF_Promise_To_Pay__c LIMIT 1];
        Test.startTest();
        ARF_Promise_To_Pay__c result = ARF_PromiseToPayController.cancelPromise(ptp.Id);
        Test.stopTest();

        ARF_Promise_To_Pay__c updated = [SELECT Status__c FROM ARF_Promise_To_Pay__c WHERE Id = :ptp.Id];
        System.assertEquals('Cancelled', updated.Status__c, 'Should be cancelled');
    }

    @isTest
    static void testRecordPaymentReceived() {
        ARF_Promise_To_Pay__c ptp = [SELECT Id FROM ARF_Promise_To_Pay__c LIMIT 1];
        Test.startTest();
        ARF_Promise_To_Pay__c result = ARF_PromiseToPayController.recordPaymentReceived(ptp.Id, 3000);
        Test.stopTest();

        ARF_Promise_To_Pay__c updated = [SELECT Amount_Received__c, Status__c FROM ARF_Promise_To_Pay__c WHERE Id = :ptp.Id];
        System.assertEquals(3000, updated.Amount_Received__c, 'Should record 3000 received');
        System.assertEquals('Open', updated.Status__c, 'Should still be Open (partial)');
    }

    @isTest
    static void testRecordPaymentReceivedFull() {
        ARF_Promise_To_Pay__c ptp = [SELECT Id FROM ARF_Promise_To_Pay__c LIMIT 1];
        Test.startTest();
        ARF_PromiseToPayController.recordPaymentReceived(ptp.Id, 10000);
        Test.stopTest();

        ARF_Promise_To_Pay__c updated = [SELECT Amount_Received__c, Status__c FROM ARF_Promise_To_Pay__c WHERE Id = :ptp.Id];
        System.assertEquals(10000, updated.Amount_Received__c, 'Should record full amount');
        System.assertEquals('Kept', updated.Status__c, 'Should be marked Kept');
    }
}
