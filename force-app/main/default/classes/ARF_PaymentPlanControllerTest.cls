@isTest
private class ARF_PaymentPlanControllerTest {

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(
            Name = 'PayPlan Test Account',
            ARF_Risk_Score__c = 50,
            ARF_Total_AR__c = 10000,
            ARF_Past_Due__c = 5000
        );
        insert acct;

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'PP-INV-001',
            Amount__c = 5000, Balance__c = 5000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-30),
            Due_Date__c = Date.today().addDays(-5)
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = acct.Id, Document_Number__c = 'PP-INV-002',
            Amount__c = 3000, Balance__c = 3000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-20),
            Due_Date__c = Date.today().addDays(-2)
        ));
        insert invoices;

        // Create a payment for recordInstallmentPayment test
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acct.Id,
            Amount__c = 2000,
            Status__c = 'Applied'
        );
        insert pmt;
    }

    private static Account getTestAccount() {
        return [SELECT Id FROM Account WHERE Name = 'PayPlan Test Account' LIMIT 1];
    }

    private static List<ARF_Invoice__c> getTestInvoices() {
        return [SELECT Id, Balance__c FROM ARF_Invoice__c WHERE Document_Number__c LIKE 'PP-INV%' ORDER BY Document_Number__c];
    }

    private static List<Id> getTestInvoiceIds() {
        List<Id> ids = new List<Id>();
        for (ARF_Invoice__c inv : getTestInvoices()) {
            ids.add(inv.Id);
        }
        return ids;
    }

    // ─── getRecommendation Tests ───

    @isTest
    static void testGetRecommendation_MediumRisk() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = getTestInvoiceIds();

        Test.startTest();
        ARF_PaymentPlanController.PlanRecommendation rec =
            ARF_PaymentPlanController.getRecommendation(acct.Id, invoiceIds);
        Test.stopTest();

        System.assertEquals(8000, rec.totalAmount, 'Total should be 8000');
        System.assertEquals('Medium', rec.riskLevel, 'Risk score 50 should be Medium');
        System.assertEquals(4, rec.maxInstallments, 'Medium risk max installments should be 4');
        System.assertEquals(10, rec.downPaymentPercent, 'Medium risk down payment should be 10%');
        System.assert(!rec.sampleSchedules.isEmpty(), 'Should have sample schedules');
        System.assertEquals(3, rec.availableFrequencies.size(), 'Should have 3 frequencies');
    }

    @isTest
    static void testGetRecommendation_LowRisk() {
        Account acct = getTestAccount();
        acct.ARF_Risk_Score__c = 20;
        update acct;
        List<Id> invoiceIds = getTestInvoiceIds();

        Test.startTest();
        ARF_PaymentPlanController.PlanRecommendation rec =
            ARF_PaymentPlanController.getRecommendation(acct.Id, invoiceIds);
        Test.stopTest();

        System.assertEquals('Low', rec.riskLevel, 'Risk score 20 should be Low');
        System.assertEquals(6, rec.maxInstallments, 'Low risk max installments should be 6');
        System.assertEquals(0, rec.downPaymentPercent, 'Low risk should have no down payment');
    }

    @isTest
    static void testGetRecommendation_HighRisk() {
        Account acct = getTestAccount();
        acct.ARF_Risk_Score__c = 70;
        update acct;
        List<Id> invoiceIds = getTestInvoiceIds();

        Test.startTest();
        ARF_PaymentPlanController.PlanRecommendation rec =
            ARF_PaymentPlanController.getRecommendation(acct.Id, invoiceIds);
        Test.stopTest();

        System.assertEquals('High', rec.riskLevel, 'Risk score 70 should be High');
        System.assertEquals(3, rec.maxInstallments, 'High risk max installments should be 3');
        System.assertEquals(25, rec.downPaymentPercent, 'High risk down payment should be 25%');
        System.assertEquals(25, rec.lateFee, 'High risk late fee should be 25');
    }

    @isTest
    static void testGetRecommendation_VeryHighRisk() {
        Account acct = getTestAccount();
        acct.ARF_Risk_Score__c = 90;
        update acct;
        List<Id> invoiceIds = getTestInvoiceIds();

        Test.startTest();
        ARF_PaymentPlanController.PlanRecommendation rec =
            ARF_PaymentPlanController.getRecommendation(acct.Id, invoiceIds);
        Test.stopTest();

        System.assertEquals('Very High', rec.riskLevel, 'Risk score 90 should be Very High');
        System.assertEquals(2, rec.maxInstallments, 'Very High risk max installments should be 2');
        System.assertEquals(50, rec.downPaymentPercent, 'Very High risk down payment should be 50%');
    }

    @isTest
    static void testGetRecommendation_NullRiskScore() {
        Account acct = getTestAccount();
        acct.ARF_Risk_Score__c = null;
        update acct;
        List<Id> invoiceIds = getTestInvoiceIds();

        Test.startTest();
        ARF_PaymentPlanController.PlanRecommendation rec =
            ARF_PaymentPlanController.getRecommendation(acct.Id, invoiceIds);
        Test.stopTest();

        // Null defaults to 50, which is Medium
        System.assertEquals('Medium', rec.riskLevel, 'Null risk score should default to Medium');
    }

    // ─── createPlan Tests ───

    @isTest
    static void testCreatePlan_Monthly() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = getTestInvoiceIds();

        ARF_PaymentPlanController.PlanRequest req = new ARF_PaymentPlanController.PlanRequest();
        req.accountId = acct.Id;
        req.invoiceIds = invoiceIds;
        req.installments = 4;
        req.frequency = 'Monthly';
        req.startDate = Date.today().addDays(7);
        req.autoPayEnabled = true;
        req.paymentMethodId = null;
        req.createdByCustomer = false;

        Test.startTest();
        Id planId = ARF_PaymentPlanController.createPlan(req);
        Test.stopTest();

        System.assertNotEquals(null, planId, 'Plan Id should not be null');

        ARF_Payment_Plan__c plan = [SELECT Id, Total_Amount__c, Status__c, Number_Of_Installments__c,
            Frequency__c, Auto_Pay_Enabled__c, Created_By_Customer__c, Account__c
            FROM ARF_Payment_Plan__c WHERE Id = :planId];
        System.assertEquals(8000, plan.Total_Amount__c, 'Total should be 8000');
        System.assertEquals('Active', plan.Status__c, 'Non-customer plan should be Active');
        System.assertEquals(4, plan.Number_Of_Installments__c, 'Should have 4 installments');
        System.assertEquals('Monthly', plan.Frequency__c, 'Frequency should be Monthly');
        System.assertEquals(true, plan.Auto_Pay_Enabled__c, 'Auto pay should be enabled');

        List<ARF_Plan_Installment__c> installments = [
            SELECT Id, Amount__c, Status__c, Installment_Number__c
            FROM ARF_Plan_Installment__c WHERE Payment_Plan__c = :planId
            ORDER BY Installment_Number__c
        ];
        System.assertEquals(4, installments.size(), 'Should have 4 installment records');
        for (ARF_Plan_Installment__c inst : installments) {
            System.assertEquals('Scheduled', inst.Status__c, 'All installments should be Scheduled');
        }

        List<ARF_Plan_Invoice__c> junctions = [
            SELECT Id FROM ARF_Plan_Invoice__c WHERE Payment_Plan__c = :planId
        ];
        System.assertEquals(2, junctions.size(), 'Should have 2 invoice junctions');
    }

    @isTest
    static void testCreatePlan_CustomerCreated() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = getTestInvoiceIds();

        ARF_PaymentPlanController.PlanRequest req = new ARF_PaymentPlanController.PlanRequest();
        req.accountId = acct.Id;
        req.invoiceIds = invoiceIds;
        req.installments = 3;
        req.frequency = 'Weekly';
        req.startDate = null; // test null start date
        req.autoPayEnabled = false;
        req.paymentMethodId = null;
        req.createdByCustomer = true;

        Test.startTest();
        Id planId = ARF_PaymentPlanController.createPlan(req);
        Test.stopTest();

        ARF_Payment_Plan__c plan = [SELECT Status__c, Created_By_Customer__c, Frequency__c
            FROM ARF_Payment_Plan__c WHERE Id = :planId];
        System.assertEquals('Pending_Approval', plan.Status__c, 'Customer-created plan should be Pending_Approval');
        System.assertEquals(true, plan.Created_By_Customer__c, 'Created_By_Customer should be true');
        System.assertEquals('Weekly', plan.Frequency__c, 'Frequency should be Weekly');
    }

    @isTest
    static void testCreatePlan_BiWeekly() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = getTestInvoiceIds();

        ARF_PaymentPlanController.PlanRequest req = new ARF_PaymentPlanController.PlanRequest();
        req.accountId = acct.Id;
        req.invoiceIds = invoiceIds;
        req.installments = 2;
        req.frequency = 'Bi_Weekly';
        req.startDate = Date.today().addDays(14);
        req.autoPayEnabled = false;
        req.paymentMethodId = null;
        req.createdByCustomer = false;

        Test.startTest();
        Id planId = ARF_PaymentPlanController.createPlan(req);
        Test.stopTest();

        ARF_Payment_Plan__c plan = [SELECT Frequency__c, Number_Of_Installments__c
            FROM ARF_Payment_Plan__c WHERE Id = :planId];
        System.assertEquals('Bi_Weekly', plan.Frequency__c, 'Frequency should be Bi_Weekly');
        System.assertEquals(2, plan.Number_Of_Installments__c, 'Should have 2 installments');
    }

    // ─── getPlanDetail Tests ───

    @isTest
    static void testGetPlanDetail() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = getTestInvoiceIds();

        ARF_PaymentPlanController.PlanRequest req = new ARF_PaymentPlanController.PlanRequest();
        req.accountId = acct.Id;
        req.invoiceIds = invoiceIds;
        req.installments = 3;
        req.frequency = 'Monthly';
        req.startDate = Date.today().addDays(7);
        req.autoPayEnabled = false;
        req.paymentMethodId = null;
        req.createdByCustomer = false;
        Id planId = ARF_PaymentPlanController.createPlan(req);

        Test.startTest();
        ARF_PaymentPlanController.PlanDetail detail =
            ARF_PaymentPlanController.getPlanDetail(planId);
        Test.stopTest();

        System.assertNotEquals(null, detail.plan, 'Plan should not be null');
        System.assertEquals(3, detail.installments.size(), 'Should have 3 installments');
        System.assertEquals(2, detail.invoices.size(), 'Should have 2 invoices');
        System.assertEquals(0, detail.paidCount, 'No installments should be paid yet');
        System.assertEquals(3, detail.remainingCount, 'All 3 installments should be remaining');
        System.assertEquals(0, detail.progressPercent, 'Progress should be 0%');
        System.assertNotEquals(null, detail.nextDueDate, 'Should have next due date');
        System.assertNotEquals(null, detail.nextDueAmount, 'Should have next due amount');
    }

    // ─── getAccountPlans Tests ───

    @isTest
    static void testGetAccountPlans() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = getTestInvoiceIds();

        // Create two plans
        ARF_PaymentPlanController.PlanRequest req1 = new ARF_PaymentPlanController.PlanRequest();
        req1.accountId = acct.Id;
        req1.invoiceIds = invoiceIds;
        req1.installments = 3;
        req1.frequency = 'Monthly';
        req1.startDate = Date.today().addDays(7);
        req1.autoPayEnabled = false;
        req1.paymentMethodId = null;
        req1.createdByCustomer = false;
        ARF_PaymentPlanController.createPlan(req1);

        ARF_PaymentPlanController.PlanRequest req2 = new ARF_PaymentPlanController.PlanRequest();
        req2.accountId = acct.Id;
        req2.invoiceIds = new List<Id>{ invoiceIds[0] };
        req2.installments = 2;
        req2.frequency = 'Weekly';
        req2.startDate = Date.today().addDays(14);
        req2.autoPayEnabled = true;
        req2.paymentMethodId = null;
        req2.createdByCustomer = false;
        ARF_PaymentPlanController.createPlan(req2);

        Test.startTest();
        List<ARF_PaymentPlanController.PlanSummary> summaries =
            ARF_PaymentPlanController.getAccountPlans(acct.Id);
        Test.stopTest();

        System.assertEquals(2, summaries.size(), 'Should return 2 plans');
        for (ARF_PaymentPlanController.PlanSummary s : summaries) {
            System.assertNotEquals(null, s.planId, 'Plan Id should not be null');
            System.assertNotEquals(null, s.planName, 'Plan name should not be null');
            System.assertEquals('Active', s.status, 'Both plans should be Active');
            System.assertEquals(0, s.installmentsPaid, 'No installments paid yet');
            System.assertEquals(0, s.progressPercent, 'Progress should be 0');
        }
    }

    @isTest
    static void testGetAccountPlans_NoPlans() {
        Account acct = getTestAccount();

        Test.startTest();
        List<ARF_PaymentPlanController.PlanSummary> summaries =
            ARF_PaymentPlanController.getAccountPlans(acct.Id);
        Test.stopTest();

        System.assertEquals(0, summaries.size(), 'Should return empty list');
    }

    // ─── reviewPlan Tests ───

    @isTest
    static void testReviewPlan_Approve() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = getTestInvoiceIds();

        ARF_PaymentPlanController.PlanRequest req = new ARF_PaymentPlanController.PlanRequest();
        req.accountId = acct.Id;
        req.invoiceIds = invoiceIds;
        req.installments = 3;
        req.frequency = 'Monthly';
        req.startDate = Date.today().addDays(7);
        req.autoPayEnabled = false;
        req.paymentMethodId = null;
        req.createdByCustomer = true;
        Id planId = ARF_PaymentPlanController.createPlan(req);

        ARF_Payment_Plan__c planBefore = [SELECT Status__c FROM ARF_Payment_Plan__c WHERE Id = :planId];
        System.assertEquals('Pending_Approval', planBefore.Status__c, 'Should start as Pending_Approval');

        Test.startTest();
        ARF_PaymentPlanController.reviewPlan(planId, 'approve', 'Looks good');
        Test.stopTest();

        ARF_Payment_Plan__c planAfter = [SELECT Status__c FROM ARF_Payment_Plan__c WHERE Id = :planId];
        System.assertEquals('Active', planAfter.Status__c, 'Should be Active after approval');

        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :acct.Id AND Subject = 'Payment Plan Approved'];
        System.assertEquals(1, tasks.size(), 'Should create an approval task');
    }

    @isTest
    static void testReviewPlan_Reject() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = getTestInvoiceIds();

        ARF_PaymentPlanController.PlanRequest req = new ARF_PaymentPlanController.PlanRequest();
        req.accountId = acct.Id;
        req.invoiceIds = invoiceIds;
        req.installments = 2;
        req.frequency = 'Monthly';
        req.startDate = Date.today().addDays(7);
        req.autoPayEnabled = false;
        req.paymentMethodId = null;
        req.createdByCustomer = true;
        Id planId = ARF_PaymentPlanController.createPlan(req);

        Test.startTest();
        ARF_PaymentPlanController.reviewPlan(planId, 'reject', null);
        Test.stopTest();

        ARF_Payment_Plan__c planAfter = [SELECT Status__c FROM ARF_Payment_Plan__c WHERE Id = :planId];
        System.assertEquals('Cancelled', planAfter.Status__c, 'Should be Cancelled after rejection');
    }

    // ─── recordInstallmentPayment Tests ───

    @isTest
    static void testRecordInstallmentPayment() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = getTestInvoiceIds();
        ARF_Payment__c pmt = [SELECT Id FROM ARF_Payment__c WHERE Account__c = :acct.Id LIMIT 1];

        ARF_PaymentPlanController.PlanRequest req = new ARF_PaymentPlanController.PlanRequest();
        req.accountId = acct.Id;
        req.invoiceIds = invoiceIds;
        req.installments = 3;
        req.frequency = 'Monthly';
        req.startDate = Date.today().addDays(7);
        req.autoPayEnabled = false;
        req.paymentMethodId = null;
        req.createdByCustomer = false;
        Id planId = ARF_PaymentPlanController.createPlan(req);

        Test.startTest();
        ARF_PaymentPlanController.recordInstallmentPayment(planId, pmt.Id);
        Test.stopTest();

        List<ARF_Plan_Installment__c> paidInst = [
            SELECT Id, Status__c, Paid_Amount__c, Payment__c
            FROM ARF_Plan_Installment__c
            WHERE Payment_Plan__c = :planId AND Status__c = 'Paid'
        ];
        System.assertEquals(1, paidInst.size(), 'Should have 1 paid installment');
        System.assertEquals(pmt.Id, paidInst[0].Payment__c, 'Payment should be linked');

        ARF_Payment_Plan__c plan = [SELECT Remaining_Amount__c, Status__c FROM ARF_Payment_Plan__c WHERE Id = :planId];
        System.assertEquals('Active', plan.Status__c, 'Plan should still be Active');
        System.assert(plan.Remaining_Amount__c < 8000, 'Remaining should decrease');
    }

    @isTest
    static void testRecordInstallmentPayment_CompletePlan() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = new List<Id>{ getTestInvoices()[0].Id };
        ARF_Payment__c pmt = [SELECT Id FROM ARF_Payment__c WHERE Account__c = :acct.Id LIMIT 1];

        ARF_PaymentPlanController.PlanRequest req = new ARF_PaymentPlanController.PlanRequest();
        req.accountId = acct.Id;
        req.invoiceIds = invoiceIds;
        req.installments = 2;
        req.frequency = 'Weekly';
        req.startDate = Date.today().addDays(7);
        req.autoPayEnabled = false;
        req.paymentMethodId = null;
        req.createdByCustomer = false;
        Id planId = ARF_PaymentPlanController.createPlan(req);

        Test.startTest();
        // Pay first installment
        ARF_PaymentPlanController.recordInstallmentPayment(planId, pmt.Id);
        // Pay second installment
        ARF_PaymentPlanController.recordInstallmentPayment(planId, pmt.Id);
        Test.stopTest();

        ARF_Payment_Plan__c plan = [SELECT Status__c, Remaining_Amount__c FROM ARF_Payment_Plan__c WHERE Id = :planId];
        System.assertEquals('Completed', plan.Status__c, 'Plan should be Completed after all installments paid');
        System.assertEquals(0, plan.Remaining_Amount__c, 'Remaining should be 0');
    }

    @isTest
    static void testRecordInstallmentPayment_NoScheduledInstallments() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = new List<Id>{ getTestInvoices()[0].Id };
        ARF_Payment__c pmt = [SELECT Id FROM ARF_Payment__c WHERE Account__c = :acct.Id LIMIT 1];

        ARF_PaymentPlanController.PlanRequest req = new ARF_PaymentPlanController.PlanRequest();
        req.accountId = acct.Id;
        req.invoiceIds = invoiceIds;
        req.installments = 2;
        req.frequency = 'Weekly';
        req.startDate = Date.today().addDays(7);
        req.autoPayEnabled = false;
        req.paymentMethodId = null;
        req.createdByCustomer = false;
        Id planId = ARF_PaymentPlanController.createPlan(req);

        // Pay all installments first
        ARF_PaymentPlanController.recordInstallmentPayment(planId, pmt.Id);
        ARF_PaymentPlanController.recordInstallmentPayment(planId, pmt.Id);

        Test.startTest();
        // Try paying again when no scheduled installments remain
        ARF_PaymentPlanController.recordInstallmentPayment(planId, pmt.Id);
        Test.stopTest();

        // Should not throw, just return early
        ARF_Payment_Plan__c plan = [SELECT Status__c FROM ARF_Payment_Plan__c WHERE Id = :planId];
        System.assertEquals('Completed', plan.Status__c, 'Plan should still be Completed');
    }

    // ─── checkDefaults Tests ───

    @isTest
    static void testCheckDefaults_NoMissed() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = getTestInvoiceIds();

        ARF_PaymentPlanController.PlanRequest req = new ARF_PaymentPlanController.PlanRequest();
        req.accountId = acct.Id;
        req.invoiceIds = invoiceIds;
        req.installments = 3;
        req.frequency = 'Monthly';
        req.startDate = Date.today().addDays(7);
        req.autoPayEnabled = false;
        req.paymentMethodId = null;
        req.createdByCustomer = false;
        Id planId = ARF_PaymentPlanController.createPlan(req);

        Test.startTest();
        ARF_PaymentPlanController.checkDefaults();
        Test.stopTest();

        ARF_Payment_Plan__c plan = [SELECT Status__c FROM ARF_Payment_Plan__c WHERE Id = :planId];
        System.assertEquals('Active', plan.Status__c, 'Plan should remain Active with no missed installments');
    }

    @isTest
    static void testCheckDefaults_WithMissed() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = getTestInvoiceIds();

        ARF_PaymentPlanController.PlanRequest req = new ARF_PaymentPlanController.PlanRequest();
        req.accountId = acct.Id;
        req.invoiceIds = invoiceIds;
        req.installments = 3;
        req.frequency = 'Monthly';
        req.startDate = Date.today().addDays(7);
        req.autoPayEnabled = false;
        req.paymentMethodId = null;
        req.createdByCustomer = false;
        Id planId = ARF_PaymentPlanController.createPlan(req);

        // Mark 2 installments as Missed (max_missed_before_default = 2)
        List<ARF_Plan_Installment__c> installments = [
            SELECT Id, Status__c FROM ARF_Plan_Installment__c
            WHERE Payment_Plan__c = :planId ORDER BY Installment_Number__c LIMIT 2
        ];
        for (ARF_Plan_Installment__c inst : installments) {
            inst.Status__c = 'Missed';
        }
        update installments;

        Test.startTest();
        ARF_PaymentPlanController.checkDefaults();
        Test.stopTest();

        ARF_Payment_Plan__c plan = [SELECT Status__c, Missed_Payments__c FROM ARF_Payment_Plan__c WHERE Id = :planId];
        System.assertEquals('Defaulted', plan.Status__c, 'Plan should be Defaulted after 2 missed installments');
        System.assertEquals(2, plan.Missed_Payments__c, 'Missed payments count should be 2');

        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :acct.Id AND Subject LIKE '%Defaulted%'];
        System.assertEquals(1, tasks.size(), 'Should create a default alert task');
    }

    @isTest
    static void testCheckDefaults_NullMaxMissed() {
        Account acct = getTestAccount();
        List<Id> invoiceIds = getTestInvoiceIds();

        ARF_PaymentPlanController.PlanRequest req = new ARF_PaymentPlanController.PlanRequest();
        req.accountId = acct.Id;
        req.invoiceIds = invoiceIds;
        req.installments = 3;
        req.frequency = 'Monthly';
        req.startDate = Date.today().addDays(7);
        req.autoPayEnabled = false;
        req.paymentMethodId = null;
        req.createdByCustomer = false;
        Id planId = ARF_PaymentPlanController.createPlan(req);

        // Set Max_Missed_Before_Default to null to test default behavior
        ARF_Payment_Plan__c plan = [SELECT Id FROM ARF_Payment_Plan__c WHERE Id = :planId];
        plan.Max_Missed_Before_Default__c = null;
        update plan;

        // Mark 2 installments as Missed (null defaults to 2)
        List<ARF_Plan_Installment__c> installments = [
            SELECT Id, Status__c FROM ARF_Plan_Installment__c
            WHERE Payment_Plan__c = :planId ORDER BY Installment_Number__c LIMIT 2
        ];
        for (ARF_Plan_Installment__c inst : installments) {
            inst.Status__c = 'Missed';
        }
        update installments;

        Test.startTest();
        ARF_PaymentPlanController.checkDefaults();
        Test.stopTest();

        ARF_Payment_Plan__c updatedPlan = [SELECT Status__c FROM ARF_Payment_Plan__c WHERE Id = :planId];
        System.assertEquals('Defaulted', updatedPlan.Status__c, 'Plan should be Defaulted when null max defaults to 2');
    }
}
