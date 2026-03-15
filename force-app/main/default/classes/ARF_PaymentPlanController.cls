public with sharing class ARF_PaymentPlanController {

    @AuraEnabled
    public static PlanRecommendation getRecommendation(Id accountId, List<Id> invoiceIds) {
        Account acct = [SELECT Id, ARF_Risk_Score__c, ARF_Total_AR__c, ARF_Past_Due__c FROM Account WHERE Id = :accountId];

        Decimal totalAmount = 0;
        List<ARF_Invoice__c> invoices = [SELECT Id, Balance__c FROM ARF_Invoice__c WHERE Id IN :invoiceIds];
        for (ARF_Invoice__c inv : invoices) totalAmount += inv.Balance__c;

        PlanRecommendation rec = new PlanRecommendation();
        rec.totalAmount = totalAmount;
        rec.availableFrequencies = new List<String>{ 'Weekly', 'Bi_Weekly', 'Monthly' };
        rec.sampleSchedules = new List<SampleSchedule>();

        Decimal riskScore = acct.ARF_Risk_Score__c != null ? acct.ARF_Risk_Score__c : 50;

        if (riskScore < 30) {
            rec.riskLevel = 'Low';
            rec.maxInstallments = 6;
            rec.downPaymentPercent = 0;
            rec.interestRate = 0;
            rec.lateFee = 0;
            rec.reason = 'Based on your excellent payment history, you qualify for our most flexible terms with no down payment required.';
        } else if (riskScore < 60) {
            rec.riskLevel = 'Medium';
            rec.maxInstallments = 4;
            rec.downPaymentPercent = 10;
            rec.interestRate = 0;
            rec.lateFee = 0;
            rec.reason = 'Standard payment plan terms based on your account history. A small down payment helps get you started.';
        } else if (riskScore < 80) {
            rec.riskLevel = 'High';
            rec.maxInstallments = 3;
            rec.downPaymentPercent = 25;
            rec.interestRate = 0;
            rec.lateFee = 25;
            rec.reason = 'Modified terms due to recent payment delays. A down payment and shorter duration help manage risk.';
        } else {
            rec.riskLevel = 'Very High';
            rec.maxInstallments = 2;
            rec.downPaymentPercent = 50;
            rec.interestRate = 0;
            rec.lateFee = 50;
            rec.reason = 'Accelerated terms required based on payment history. Larger down payment needed for plan approval.';
        }

        // Generate 2-3 sample schedules
        Decimal downPayment = totalAmount * (rec.downPaymentPercent / 100);
        Decimal remaining = totalAmount - downPayment;

        // Option 1: Max installments, monthly
        SampleSchedule opt1 = new SampleSchedule();
        opt1.installments = rec.maxInstallments;
        opt1.frequency = 'Monthly';
        opt1.downPayment = downPayment;
        opt1.installmentAmount = (remaining / rec.maxInstallments).setScale(2, System.RoundingMode.CEILING);
        opt1.totalWithFees = totalAmount;
        opt1.firstPayment = Date.today().addDays(7);
        opt1.lastPayment = opt1.firstPayment.addMonths(rec.maxInstallments);
        rec.sampleSchedules.add(opt1);

        // Option 2: Fewer installments, bi-weekly
        if (rec.maxInstallments >= 3) {
            Integer biWeeklyCount = Math.max(2, rec.maxInstallments - 1);
            SampleSchedule opt2 = new SampleSchedule();
            opt2.installments = biWeeklyCount;
            opt2.frequency = 'Bi_Weekly';
            opt2.downPayment = downPayment;
            opt2.installmentAmount = (remaining / biWeeklyCount).setScale(2, System.RoundingMode.CEILING);
            opt2.totalWithFees = totalAmount;
            opt2.firstPayment = Date.today().addDays(7);
            opt2.lastPayment = opt2.firstPayment.addDays(biWeeklyCount * 14);
            rec.sampleSchedules.add(opt2);
        }

        // Option 3: Quick pay, weekly
        SampleSchedule opt3 = new SampleSchedule();
        opt3.installments = Math.max(2, rec.maxInstallments > 2 ? rec.maxInstallments - 2 : 2);
        opt3.frequency = 'Weekly';
        opt3.downPayment = downPayment;
        opt3.installmentAmount = (remaining / opt3.installments).setScale(2, System.RoundingMode.CEILING);
        opt3.totalWithFees = totalAmount;
        opt3.firstPayment = Date.today().addDays(7);
        opt3.lastPayment = opt3.firstPayment.addDays(opt3.installments * 7);
        rec.sampleSchedules.add(opt3);

        return rec;
    }

    @AuraEnabled
    public static Id createPlan(PlanRequest request) {
        // Calculate amounts
        List<ARF_Invoice__c> invoices = [SELECT Id, Balance__c FROM ARF_Invoice__c WHERE Id IN :request.invoiceIds];
        Decimal totalAmount = 0;
        for (ARF_Invoice__c inv : invoices) totalAmount += inv.Balance__c;

        Integer installments = request.installments;
        Decimal installmentAmount = (totalAmount / installments).setScale(2, System.RoundingMode.CEILING);

        // Determine frequency days
        Integer freqDays = 30;
        if (request.frequency == 'Weekly') freqDays = 7;
        else if (request.frequency == 'Bi_Weekly') freqDays = 14;

        Date startDate = request.startDate != null ? request.startDate : Date.today().addDays(7);
        Date endDate = startDate.addDays(freqDays * installments);

        // Create plan
        ARF_Payment_Plan__c plan = new ARF_Payment_Plan__c();
        plan.Account__c = request.accountId;
        plan.Plan_Name__c = 'Payment Plan - ' + Date.today().format();
        plan.Total_Amount__c = totalAmount;
        plan.Remaining_Amount__c = totalAmount;
        plan.Number_Of_Installments__c = installments;
        plan.Installment_Amount__c = installmentAmount;
        plan.Frequency__c = request.frequency;
        plan.Start_Date__c = startDate;
        plan.Next_Payment_Date__c = startDate;
        plan.End_Date__c = endDate;
        plan.Status__c = request.createdByCustomer ? 'Pending_Approval' : 'Active';
        plan.Down_Payment_Amount__c = 0;
        plan.Down_Payment_Paid__c = false;
        plan.Auto_Pay_Enabled__c = request.autoPayEnabled;
        plan.Payment_Method__c = request.paymentMethodId;
        plan.Created_By_Customer__c = request.createdByCustomer;
        plan.Missed_Payments__c = 0;
        plan.Max_Missed_Before_Default__c = 2;
        insert plan;

        // Create junction records
        List<ARF_Plan_Invoice__c> junctions = new List<ARF_Plan_Invoice__c>();
        for (ARF_Invoice__c inv : invoices) {
            ARF_Plan_Invoice__c pi = new ARF_Plan_Invoice__c();
            pi.Payment_Plan__c = plan.Id;
            pi.Invoice__c = inv.Id;
            pi.Amount_Included__c = inv.Balance__c;
            junctions.add(pi);
        }
        if (!junctions.isEmpty()) insert junctions;

        // Generate installment records
        List<ARF_Plan_Installment__c> installmentRecords = new List<ARF_Plan_Installment__c>();
        Decimal remainingAmount = totalAmount;
        for (Integer i = 1; i <= installments; i++) {
            ARF_Plan_Installment__c inst = new ARF_Plan_Installment__c();
            inst.Payment_Plan__c = plan.Id;
            inst.Installment_Number__c = i;
            inst.Due_Date__c = startDate.addDays((i - 1) * freqDays);
            inst.Amount__c = (i == installments) ? remainingAmount : installmentAmount;
            inst.Status__c = 'Scheduled';
            inst.Late_Fee_Applied__c = 0;
            installmentRecords.add(inst);
            remainingAmount -= installmentAmount;
        }
        if (!installmentRecords.isEmpty()) insert installmentRecords;

        return plan.Id;
    }

    @AuraEnabled(cacheable=true)
    public static PlanDetail getPlanDetail(Id planId) {
        ARF_Payment_Plan__c plan = [
            SELECT Id, Name, Plan_Name__c, Account__c, Account__r.Name, Total_Amount__c, Remaining_Amount__c,
                   Number_Of_Installments__c, Installment_Amount__c, Frequency__c, Start_Date__c,
                   Next_Payment_Date__c, End_Date__c, Status__c, Down_Payment_Amount__c, Down_Payment_Paid__c,
                   Auto_Pay_Enabled__c, Created_By_Customer__c, AI_Recommended__c, AI_Recommendation_Reason__c,
                   Missed_Payments__c, Max_Missed_Before_Default__c, Interest_Rate__c, Late_Fee__c,
                   Terms_Accepted__c, Terms_Accepted_Date__c
            FROM ARF_Payment_Plan__c WHERE Id = :planId
        ];

        List<ARF_Plan_Installment__c> installments = [
            SELECT Id, Name, Installment_Number__c, Due_Date__c, Amount__c, Status__c,
                   Payment__c, Paid_Date__c, Paid_Amount__c, Late_Fee_Applied__c
            FROM ARF_Plan_Installment__c WHERE Payment_Plan__c = :planId
            ORDER BY Installment_Number__c ASC
        ];

        List<ARF_Plan_Invoice__c> planInvoices = [
            SELECT Id, Invoice__c, Invoice__r.Document_Number__c, Invoice__r.Amount__c,
                   Invoice__r.Balance__c, Invoice__r.Status__c, Amount_Included__c
            FROM ARF_Plan_Invoice__c WHERE Payment_Plan__c = :planId
        ];

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        for (ARF_Plan_Invoice__c pi : planInvoices) {
            invoices.add(pi.Invoice__r);
        }

        PlanDetail detail = new PlanDetail();
        detail.plan = plan;
        detail.installments = installments;
        detail.invoices = invoices;

        Integer paid = 0;
        for (ARF_Plan_Installment__c inst : installments) {
            if (inst.Status__c == 'Paid') paid++;
        }
        detail.paidCount = paid;
        detail.remainingCount = (Integer) plan.Number_Of_Installments__c - paid;
        detail.progressPercent = plan.Number_Of_Installments__c > 0
            ? (paid * 100.0 / plan.Number_Of_Installments__c).setScale(0) : 0;

        // Find next due
        for (ARF_Plan_Installment__c inst : installments) {
            if (inst.Status__c == 'Scheduled' || inst.Status__c == 'Late') {
                detail.nextDueDate = inst.Due_Date__c;
                detail.nextDueAmount = inst.Amount__c;
                break;
            }
        }

        return detail;
    }

    @AuraEnabled(cacheable=true)
    public static List<PlanSummary> getAccountPlans(Id accountId) {
        List<ARF_Payment_Plan__c> plans = [
            SELECT Id, Name, Plan_Name__c, Total_Amount__c, Remaining_Amount__c,
                   Number_Of_Installments__c, Status__c, Next_Payment_Date__c, Installment_Amount__c,
                   Frequency__c, Start_Date__c, End_Date__c
            FROM ARF_Payment_Plan__c WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC
        ];

        // Get paid installment counts in bulk
        Map<Id, Integer> paidCounts = new Map<Id, Integer>();
        Set<Id> planIds = new Set<Id>();
        for (ARF_Payment_Plan__c p : plans) planIds.add(p.Id);

        for (AggregateResult ar : [
            SELECT Payment_Plan__c, COUNT(Id) cnt
            FROM ARF_Plan_Installment__c
            WHERE Payment_Plan__c IN :planIds AND Status__c = 'Paid'
            GROUP BY Payment_Plan__c
        ]) {
            paidCounts.put((Id) ar.get('Payment_Plan__c'), (Integer) ar.get('cnt'));
        }

        List<PlanSummary> summaries = new List<PlanSummary>();
        for (ARF_Payment_Plan__c plan : plans) {
            PlanSummary s = new PlanSummary();
            s.planId = plan.Id;
            s.planName = plan.Plan_Name__c;
            s.totalAmount = plan.Total_Amount__c;
            s.remainingAmount = plan.Remaining_Amount__c;
            s.status = plan.Status__c;
            s.nextPaymentDate = plan.Next_Payment_Date__c;
            s.nextPaymentAmount = plan.Installment_Amount__c;
            s.totalInstallments = plan.Number_Of_Installments__c != null ? (Integer) plan.Number_Of_Installments__c : 0;
            s.installmentsPaid = paidCounts.containsKey(plan.Id) ? paidCounts.get(plan.Id) : 0;
            s.progressPercent = s.totalInstallments > 0 ? (s.installmentsPaid * 100.0 / s.totalInstallments).setScale(0) : 0;
            summaries.add(s);
        }

        return summaries;
    }

    @AuraEnabled
    public static void reviewPlan(Id planId, String action, String notes) {
        ARF_Payment_Plan__c plan = [SELECT Id, Status__c, Account__c FROM ARF_Payment_Plan__c WHERE Id = :planId];

        if (action == 'approve') {
            plan.Status__c = 'Active';
            update plan;

            // Create task notification
            Task t = new Task();
            t.Subject = 'Payment Plan Approved';
            t.Description = 'Payment plan ' + planId + ' has been approved.' + (String.isNotBlank(notes) ? ' Notes: ' + notes : '');
            t.WhatId = plan.Account__c;
            t.Status = 'Completed';
            t.Priority = 'Normal';
            t.ActivityDate = Date.today();
            insert t;
        } else {
            plan.Status__c = 'Cancelled';
            update plan;
        }
    }

    @AuraEnabled
    public static void recordInstallmentPayment(Id planId, Id paymentId) {
        ARF_Payment_Plan__c plan = [
            SELECT Id, Remaining_Amount__c, Number_Of_Installments__c, Status__c
            FROM ARF_Payment_Plan__c WHERE Id = :planId
        ];

        List<ARF_Plan_Installment__c> installments = [
            SELECT Id, Amount__c, Status__c, Due_Date__c
            FROM ARF_Plan_Installment__c
            WHERE Payment_Plan__c = :planId AND (Status__c = 'Scheduled' OR Status__c = 'Late')
            ORDER BY Due_Date__c ASC LIMIT 1
        ];

        if (installments.isEmpty()) return;

        ARF_Plan_Installment__c inst = installments[0];
        inst.Status__c = 'Paid';
        inst.Payment__c = paymentId;
        inst.Paid_Date__c = Date.today();
        inst.Paid_Amount__c = inst.Amount__c;
        update inst;

        plan.Remaining_Amount__c = plan.Remaining_Amount__c - inst.Amount__c;

        // Check if all installments are paid
        Integer remaining = [
            SELECT COUNT() FROM ARF_Plan_Installment__c
            WHERE Payment_Plan__c = :planId AND Status__c != 'Paid' AND Status__c != 'Waived'
        ];

        if (remaining == 0) {
            plan.Status__c = 'Completed';
            plan.Remaining_Amount__c = 0;
        } else {
            // Update next payment date
            List<ARF_Plan_Installment__c> nextInst = [
                SELECT Due_Date__c FROM ARF_Plan_Installment__c
                WHERE Payment_Plan__c = :planId AND Status__c = 'Scheduled'
                ORDER BY Due_Date__c ASC LIMIT 1
            ];
            if (!nextInst.isEmpty()) {
                plan.Next_Payment_Date__c = nextInst[0].Due_Date__c;
            }
        }
        update plan;
    }

    public static void checkDefaults() {
        List<ARF_Payment_Plan__c> activePlans = [
            SELECT Id, Account__c, Missed_Payments__c, Max_Missed_Before_Default__c
            FROM ARF_Payment_Plan__c WHERE Status__c = 'Active'
        ];

        Set<Id> planIds = new Set<Id>();
        for (ARF_Payment_Plan__c p : activePlans) planIds.add(p.Id);

        // Count missed installments per plan
        Map<Id, Integer> missedCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Payment_Plan__c, COUNT(Id) cnt
            FROM ARF_Plan_Installment__c
            WHERE Payment_Plan__c IN :planIds AND Status__c = 'Missed'
            GROUP BY Payment_Plan__c
        ]) {
            missedCounts.put((Id) ar.get('Payment_Plan__c'), (Integer) ar.get('cnt'));
        }

        List<ARF_Payment_Plan__c> toDefault = new List<ARF_Payment_Plan__c>();
        List<Task> alertTasks = new List<Task>();

        for (ARF_Payment_Plan__c plan : activePlans) {
            Integer missed = missedCounts.containsKey(plan.Id) ? missedCounts.get(plan.Id) : 0;
            Integer maxMissed = plan.Max_Missed_Before_Default__c != null ? (Integer) plan.Max_Missed_Before_Default__c : 2;

            if (missed >= maxMissed) {
                plan.Status__c = 'Defaulted';
                plan.Missed_Payments__c = missed;
                toDefault.add(plan);

                Task t = new Task();
                t.Subject = 'Payment Plan Defaulted - Immediate Action Required';
                t.Description = 'Payment plan ' + plan.Id + ' has defaulted after ' + missed + ' missed payments.';
                t.WhatId = plan.Account__c;
                t.Status = 'Open';
                t.Priority = 'High';
                t.ActivityDate = Date.today();
                alertTasks.add(t);
            }
        }

        if (!toDefault.isEmpty()) update toDefault;
        if (!alertTasks.isEmpty()) insert alertTasks;
    }

    // ─── Inner Classes ───
    public class PlanRecommendation {
        @AuraEnabled public Integer maxInstallments;
        @AuraEnabled public Decimal downPaymentPercent;
        @AuraEnabled public Decimal interestRate;
        @AuraEnabled public Decimal lateFee;
        @AuraEnabled public List<String> availableFrequencies;
        @AuraEnabled public String riskLevel;
        @AuraEnabled public String reason;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public List<SampleSchedule> sampleSchedules;
    }

    public class SampleSchedule {
        @AuraEnabled public Integer installments;
        @AuraEnabled public String frequency;
        @AuraEnabled public Decimal installmentAmount;
        @AuraEnabled public Decimal downPayment;
        @AuraEnabled public Decimal totalWithFees;
        @AuraEnabled public Date firstPayment;
        @AuraEnabled public Date lastPayment;
    }

    public class PlanRequest {
        @AuraEnabled public Id accountId;
        @AuraEnabled public List<Id> invoiceIds;
        @AuraEnabled public Integer installments;
        @AuraEnabled public String frequency;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Boolean autoPayEnabled;
        @AuraEnabled public Id paymentMethodId;
        @AuraEnabled public Boolean createdByCustomer;
    }

    public class PlanDetail {
        @AuraEnabled public ARF_Payment_Plan__c plan;
        @AuraEnabled public List<ARF_Plan_Installment__c> installments;
        @AuraEnabled public List<ARF_Invoice__c> invoices;
        @AuraEnabled public Decimal progressPercent;
        @AuraEnabled public Integer paidCount;
        @AuraEnabled public Integer remainingCount;
        @AuraEnabled public Date nextDueDate;
        @AuraEnabled public Decimal nextDueAmount;
    }

    public class PlanSummary {
        @AuraEnabled public Id planId;
        @AuraEnabled public String planName;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal remainingAmount;
        @AuraEnabled public Decimal progressPercent;
        @AuraEnabled public String status;
        @AuraEnabled public Date nextPaymentDate;
        @AuraEnabled public Decimal nextPaymentAmount;
        @AuraEnabled public Integer installmentsPaid;
        @AuraEnabled public Integer totalInstallments;
    }
}
