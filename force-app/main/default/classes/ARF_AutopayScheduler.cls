/**
 * ARF_AutopayScheduler
 * Schedulable class that processes active autopay schedules.
 * Runs daily, checks which schedules are due, processes payments via gateway,
 * and allocates them to invoices.
 *
 * Schedule: System.schedule('ARF Autopay Daily', '0 0 6 * * ?', new ARF_AutopayScheduler());
 */
public with sharing class ARF_AutopayScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {
        processAutopaySchedules();
    }

    @future(callout=true)
    public static void processAutopaySchedules() {
        // Find active schedules due today or earlier
        List<ARF_Autopay_Schedule__c> schedules = [
            SELECT Id, Account__c, Payment_Method__c, Rule_Type__c,
                   Fixed_Amount__c, Max_Amount__c, Schedule_Day__c,
                   Next_Run_Date__c, Last_Run_Date__c, Is_Active__c
            FROM ARF_Autopay_Schedule__c
            WHERE Is_Active__c = true
              AND Status__c = 'Active'
              AND (Next_Run_Date__c <= TODAY OR Next_Run_Date__c = null)
        ];

        if (schedules.isEmpty()) return;

        // Collect account IDs
        Set<Id> accountIds = new Set<Id>();
        Set<Id> pmIds = new Set<Id>();
        for (ARF_Autopay_Schedule__c sched : schedules) {
            accountIds.add(sched.Account__c);
            pmIds.add(sched.Payment_Method__c);
        }

        // Get payment methods
        Map<Id, ARF_Payment_Method__c> pmMap = new Map<Id, ARF_Payment_Method__c>([
            SELECT Id, Token__c, Type__c, Status__c
            FROM ARF_Payment_Method__c
            WHERE Id IN :pmIds AND Status__c = 'Active'
        ]);

        // Get open invoices per account
        Map<Id, List<ARF_Invoice__c>> accountInvoices = new Map<Id, List<ARF_Invoice__c>>();
        for (ARF_Invoice__c inv : [
            SELECT Id, Account__c, Balance__c, Due_Date__c, Is_Overdue__c
            FROM ARF_Invoice__c
            WHERE Account__c IN :accountIds
              AND Balance__c > 0
              AND Status__c IN ('Open', 'Partially Paid')
            ORDER BY Is_Overdue__c DESC, Due_Date__c ASC
        ]) {
            if (!accountInvoices.containsKey(inv.Account__c)) {
                accountInvoices.put(inv.Account__c, new List<ARF_Invoice__c>());
            }
            accountInvoices.get(inv.Account__c).add(inv);
        }

        List<ARF_Autopay_Schedule__c> schedulesToUpdate = new List<ARF_Autopay_Schedule__c>();

        for (ARF_Autopay_Schedule__c sched : schedules) {
            ARF_Payment_Method__c pm = pmMap.get(sched.Payment_Method__c);
            if (pm == null) continue; // Payment method inactive or not found

            List<ARF_Invoice__c> invoices = accountInvoices.get(sched.Account__c);
            if (invoices == null || invoices.isEmpty()) {
                // No invoices to pay — just advance the schedule
                sched.Last_Run_Date__c = Date.today();
                sched.Next_Run_Date__c = calculateNextRunDate(sched);
                schedulesToUpdate.add(sched);
                continue;
            }

            // Calculate amount based on rule type
            Decimal payAmount = calculatePayAmount(sched, invoices);
            if (payAmount <= 0) {
                sched.Last_Run_Date__c = Date.today();
                sched.Next_Run_Date__c = calculateNextRunDate(sched);
                schedulesToUpdate.add(sched);
                continue;
            }

            // Apply max cap
            if (sched.Max_Amount__c != null && payAmount > sched.Max_Amount__c) {
                payAmount = sched.Max_Amount__c;
            }

            // Charge via gateway
            ARF_PaymentGatewayService.GatewayResponse chargeResp =
                ARF_PaymentGatewayService.chargePaymentMethod(pm.Token__c, payAmount, 'USD', 'Autopay');

            if (chargeResp.success) {
                // Create payment record
                ARF_Payment__c payment = new ARF_Payment__c();
                payment.Account__c = sched.Account__c;
                payment.Amount__c = payAmount;
                payment.Applied_Amount__c = 0;
                payment.Unapplied_Amount__c = payAmount;
                payment.Payment_Date__c = Date.today();
                payment.Method__c = pm.Type__c == 'Credit Card' ? 'Credit Card' : 'ACH';
                payment.Status__c = 'Received';
                payment.Reference__c = 'Autopay - ' + chargeResp.transactionId;
                payment.Is_Portal_Payment__c = true;
                payment.Payment_Method__c = pm.Id;
                payment.Autopay_Schedule__c = sched.Id;
                payment.Gateway_Reference__c = chargeResp.transactionId;
                payment.Gateway_Token__c = pm.Token__c;
                insert payment;

                // Auto-allocate
                ARF_PaymentAllocationEngine.autoAllocate(payment.Id, sched.Account__c);
            }

            sched.Last_Run_Date__c = Date.today();
            sched.Next_Run_Date__c = calculateNextRunDate(sched);
            schedulesToUpdate.add(sched);
        }

        if (!schedulesToUpdate.isEmpty()) {
            update schedulesToUpdate;
        }
    }

    private static Decimal calculatePayAmount(ARF_Autopay_Schedule__c sched, List<ARF_Invoice__c> invoices) {
        String ruleType = sched.Rule_Type__c;

        if (ruleType == 'Fixed Amount') {
            return sched.Fixed_Amount__c != null ? sched.Fixed_Amount__c : 0;
        }

        Decimal total = 0;
        for (ARF_Invoice__c inv : invoices) {
            if (ruleType == 'Past Due Only' && !inv.Is_Overdue__c) continue;
            total += inv.Balance__c;
        }
        return total;
    }

    @TestVisible
    private static Date calculateNextRunDate(ARF_Autopay_Schedule__c sched) {
        Integer day = sched.Schedule_Day__c != null ? Integer.valueOf(sched.Schedule_Day__c) : 1;
        if (day > 28) day = 28;
        if (day < 1) day = 1;

        Date today = Date.today();
        Date nextMonth = today.addMonths(1);
        Integer daysInMonth = Date.daysInMonth(nextMonth.year(), nextMonth.month());
        Integer actualDay = Math.min(day, daysInMonth);
        return Date.newInstance(nextMonth.year(), nextMonth.month(), actualDay);
    }
}
