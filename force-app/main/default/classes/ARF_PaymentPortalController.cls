/**
 * ARF_PaymentPortalController
 * Main controller for the customer Payment Portal (Experience Cloud).
 * Provides invoice visibility, payment processing, payment method management,
 * autopay configuration, and payment history.
 */
public with sharing class ARF_PaymentPortalController {

    // ─── Account Summary ───────────────────────────────────────────────

    public class AccountSummary {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Decimal totalOutstanding;
        @AuraEnabled public Decimal totalPastDue;
        @AuraEnabled public Date nextDueDate;
        @AuraEnabled public Integer openInvoiceCount;
        @AuraEnabled public Integer pastDueInvoiceCount;
    }

    @AuraEnabled(cacheable=true)
    public static AccountSummary getAccountSummary(Id accountId) {
        AccountSummary summary = new AccountSummary();
        Account acc = [SELECT Id, Name FROM Account WHERE Id = :accountId LIMIT 1];
        summary.accountId = acc.Id;
        summary.accountName = acc.Name;

        List<ARF_Invoice__c> invoices = [
            SELECT Id, Balance__c, Due_Date__c, Is_Overdue__c
            FROM ARF_Invoice__c
            WHERE Account__c = :accountId
              AND Balance__c > 0
              AND Status__c IN ('Open', 'Partially Paid')
            ORDER BY Due_Date__c ASC
        ];

        summary.totalOutstanding = 0;
        summary.totalPastDue = 0;
        summary.openInvoiceCount = invoices.size();
        summary.pastDueInvoiceCount = 0;
        summary.nextDueDate = null;

        for (ARF_Invoice__c inv : invoices) {
            summary.totalOutstanding += inv.Balance__c;
            if (inv.Is_Overdue__c) {
                summary.totalPastDue += inv.Balance__c;
                summary.pastDueInvoiceCount++;
            }
            if (summary.nextDueDate == null && !inv.Is_Overdue__c && inv.Due_Date__c != null) {
                summary.nextDueDate = inv.Due_Date__c;
            }
        }
        return summary;
    }

    // ─── Open Invoices ─────────────────────────────────────────────────

    public class InvoiceWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String documentNumber;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal balance;
        @AuraEnabled public Date invoiceDate;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Integer daysPastDue;
        @AuraEnabled public Boolean isOverdue;
        @AuraEnabled public String status;
        @AuraEnabled public String poNumber;
    }

    @AuraEnabled(cacheable=true)
    public static List<InvoiceWrapper> getOpenInvoices(Id accountId) {
        List<InvoiceWrapper> wrappers = new List<InvoiceWrapper>();
        for (ARF_Invoice__c inv : [
            SELECT Id, Name, Document_Number__c, Amount__c, Balance__c,
                   Invoice_Date__c, Due_Date__c, Days_Past_Due__c,
                   Is_Overdue__c, Status__c, PO_Number__c
            FROM ARF_Invoice__c
            WHERE Account__c = :accountId
              AND Balance__c > 0
              AND Status__c IN ('Open', 'Partially Paid')
            ORDER BY Is_Overdue__c DESC, Due_Date__c ASC
        ]) {
            InvoiceWrapper w = new InvoiceWrapper();
            w.id = inv.Id;
            w.name = inv.Name;
            w.documentNumber = inv.Document_Number__c;
            w.amount = inv.Amount__c;
            w.balance = inv.Balance__c;
            w.invoiceDate = inv.Invoice_Date__c;
            w.dueDate = inv.Due_Date__c;
            w.daysPastDue = inv.Days_Past_Due__c != null ? Integer.valueOf(inv.Days_Past_Due__c) : 0;
            w.isOverdue = inv.Is_Overdue__c;
            w.status = inv.Status__c;
            w.poNumber = inv.PO_Number__c;
            wrappers.add(w);
        }
        return wrappers;
    }

    // ─── Payment Methods ───────────────────────────────────────────────

    public class PaymentMethodWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public Id junctionId;
        @AuraEnabled public String name;
        @AuraEnabled public String methodType;
        @AuraEnabled public String lastFour;
        @AuraEnabled public String cardBrand;
        @AuraEnabled public String bankName;
        @AuraEnabled public String accountType;
        @AuraEnabled public Integer expiryMonth;
        @AuraEnabled public Integer expiryYear;
        @AuraEnabled public String nickname;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isPrimary;
        @AuraEnabled public String displayLabel;
    }

    @AuraEnabled(cacheable=true)
    public static List<PaymentMethodWrapper> getPaymentMethods(Id accountId) {
        List<PaymentMethodWrapper> wrappers = new List<PaymentMethodWrapper>();
        for (ARF_Account_Payment_Method__c apm : [
            SELECT Id, Is_Primary__c,
                   Payment_Method__c, Payment_Method__r.Name,
                   Payment_Method__r.Type__c, Payment_Method__r.Last_Four__c,
                   Payment_Method__r.Card_Brand__c, Payment_Method__r.Bank_Name__c,
                   Payment_Method__r.Account_Type__c, Payment_Method__r.Expiry_Month__c,
                   Payment_Method__r.Expiry_Year__c, Payment_Method__r.Nickname__c,
                   Payment_Method__r.Status__c
            FROM ARF_Account_Payment_Method__c
            WHERE Account__c = :accountId
              AND Payment_Method__r.Status__c = 'Active'
            ORDER BY Is_Primary__c DESC, CreatedDate DESC
        ]) {
            PaymentMethodWrapper w = new PaymentMethodWrapper();
            w.id = apm.Payment_Method__c;
            w.junctionId = apm.Id;
            w.name = apm.Payment_Method__r.Name;
            w.methodType = apm.Payment_Method__r.Type__c;
            w.lastFour = apm.Payment_Method__r.Last_Four__c;
            w.cardBrand = apm.Payment_Method__r.Card_Brand__c;
            w.bankName = apm.Payment_Method__r.Bank_Name__c;
            w.accountType = apm.Payment_Method__r.Account_Type__c;
            w.expiryMonth = apm.Payment_Method__r.Expiry_Month__c != null ?
                Integer.valueOf(apm.Payment_Method__r.Expiry_Month__c) : null;
            w.expiryYear = apm.Payment_Method__r.Expiry_Year__c != null ?
                Integer.valueOf(apm.Payment_Method__r.Expiry_Year__c) : null;
            w.nickname = apm.Payment_Method__r.Nickname__c;
            w.status = apm.Payment_Method__r.Status__c;
            w.isPrimary = apm.Is_Primary__c;

            // Build display label
            if (w.methodType == 'Credit Card') {
                w.displayLabel = (w.cardBrand != null ? w.cardBrand : 'Card') + ' ending in ' + w.lastFour;
            } else {
                w.displayLabel = (w.bankName != null ? w.bankName : 'Bank') + ' (' + w.accountType + ') ending in ' + w.lastFour;
            }
            if (String.isNotBlank(w.nickname)) {
                w.displayLabel = w.nickname + ' — ' + w.displayLabel;
            }
            wrappers.add(w);
        }
        return wrappers;
    }

    @AuraEnabled
    public static PaymentMethodWrapper addCreditCard(Id accountId, String cardNumber, String expMonth,
            String expYear, String cvv, String cardholderName, String nickname) {
        // Tokenize
        ARF_PaymentGatewayService.GatewayResponse resp =
            ARF_PaymentGatewayService.tokenizeCard(cardNumber, expMonth, expYear, cvv, cardholderName);
        if (!resp.success) {
            throw new AuraHandledException('Card tokenization failed: ' + resp.message);
        }

        // Determine card brand from first digit
        String brand = detectCardBrand(cardNumber);
        String lastFour = cardNumber.substring(cardNumber.length() - 4);

        // Create payment method
        ARF_Payment_Method__c pm = new ARF_Payment_Method__c();
        pm.Token__c = resp.token;
        pm.Type__c = 'Credit Card';
        pm.Last_Four__c = lastFour;
        pm.Card_Brand__c = brand;
        pm.Expiry_Month__c = Integer.valueOf(expMonth);
        pm.Expiry_Year__c = Integer.valueOf(expYear);
        pm.Nickname__c = nickname;
        pm.Status__c = 'Active';
        pm.Gateway_ID__c = resp.transactionId;
        insert pm;

        // Check if this is the first payment method (make it primary)
        Integer existingCount = [SELECT COUNT() FROM ARF_Account_Payment_Method__c WHERE Account__c = :accountId];
        Boolean makePrimary = existingCount == 0;

        // Create junction
        ARF_Account_Payment_Method__c apm = new ARF_Account_Payment_Method__c();
        apm.Account__c = accountId;
        apm.Payment_Method__c = pm.Id;
        apm.Is_Primary__c = makePrimary;
        apm.Added_Date__c = Date.today();
        insert apm;

        // Return wrapper
        PaymentMethodWrapper w = new PaymentMethodWrapper();
        w.id = pm.Id;
        w.junctionId = apm.Id;
        w.methodType = 'Credit Card';
        w.lastFour = lastFour;
        w.cardBrand = brand;
        w.expiryMonth = Integer.valueOf(expMonth);
        w.expiryYear = Integer.valueOf(expYear);
        w.nickname = nickname;
        w.status = 'Active';
        w.isPrimary = makePrimary;
        w.displayLabel = brand + ' ending in ' + lastFour;
        return w;
    }

    @AuraEnabled
    public static PaymentMethodWrapper addBankAccount(Id accountId, String routingNumber,
            String accountNumber, String accountType, String accountHolderName,
            String bankName, String nickname) {
        ARF_PaymentGatewayService.GatewayResponse resp =
            ARF_PaymentGatewayService.tokenizeBankAccount(routingNumber, accountNumber, accountType, accountHolderName);
        if (!resp.success) {
            throw new AuraHandledException('Bank tokenization failed: ' + resp.message);
        }

        String lastFour = accountNumber.substring(accountNumber.length() - 4);

        ARF_Payment_Method__c pm = new ARF_Payment_Method__c();
        pm.Token__c = resp.token;
        pm.Type__c = 'ACH';
        pm.Last_Four__c = lastFour;
        pm.Bank_Name__c = bankName;
        pm.Account_Type__c = accountType;
        pm.Nickname__c = nickname;
        pm.Status__c = 'Active';
        pm.Gateway_ID__c = resp.transactionId;
        insert pm;

        Integer existingCount = [SELECT COUNT() FROM ARF_Account_Payment_Method__c WHERE Account__c = :accountId];
        Boolean makePrimary = existingCount == 0;

        ARF_Account_Payment_Method__c apm = new ARF_Account_Payment_Method__c();
        apm.Account__c = accountId;
        apm.Payment_Method__c = pm.Id;
        apm.Is_Primary__c = makePrimary;
        apm.Added_Date__c = Date.today();
        insert apm;

        PaymentMethodWrapper w = new PaymentMethodWrapper();
        w.id = pm.Id;
        w.junctionId = apm.Id;
        w.methodType = 'ACH';
        w.lastFour = lastFour;
        w.bankName = bankName;
        w.accountType = accountType;
        w.nickname = nickname;
        w.status = 'Active';
        w.isPrimary = makePrimary;
        w.displayLabel = bankName + ' (' + accountType + ') ending in ' + lastFour;
        return w;
    }

    @AuraEnabled
    public static void removePaymentMethod(Id junctionId) {
        ARF_Account_Payment_Method__c apm = [
            SELECT Id, Payment_Method__c FROM ARF_Account_Payment_Method__c WHERE Id = :junctionId LIMIT 1
        ];

        // Check if used in active autopay
        Integer autopayCount = [
            SELECT COUNT() FROM ARF_Autopay_Schedule__c
            WHERE Payment_Method__c = :apm.Payment_Method__c AND Is_Active__c = true
        ];
        if (autopayCount > 0) {
            throw new AuraHandledException('Cannot remove — this payment method is used in an active autopay schedule. Cancel autopay first.');
        }

        // Check how many accounts still link to this payment method
        Integer linkCount = [
            SELECT COUNT() FROM ARF_Account_Payment_Method__c
            WHERE Payment_Method__c = :apm.Payment_Method__c
        ];

        delete apm;

        // If no more account links, revoke the payment method
        if (linkCount <= 1) {
            ARF_Payment_Method__c pm = new ARF_Payment_Method__c(Id = apm.Payment_Method__c);
            pm.Status__c = 'Revoked';
            update pm;
        }
    }

    @AuraEnabled
    public static void setDefaultPaymentMethod(Id accountId, Id junctionId) {
        // Clear existing primary
        List<ARF_Account_Payment_Method__c> existing = [
            SELECT Id, Is_Primary__c FROM ARF_Account_Payment_Method__c
            WHERE Account__c = :accountId AND Is_Primary__c = true
        ];
        for (ARF_Account_Payment_Method__c apm : existing) {
            apm.Is_Primary__c = false;
        }
        if (!existing.isEmpty()) update existing;

        // Set new primary
        ARF_Account_Payment_Method__c newPrimary = new ARF_Account_Payment_Method__c(Id = junctionId);
        newPrimary.Is_Primary__c = true;
        update newPrimary;
    }

    // ─── Process Payment ───────────────────────────────────────────────

    public class PaymentRequest {
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id paymentMethodId;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public List<ARF_PaymentAllocationEngine.AllocationLine> allocations;
    }

    public class PaymentResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id paymentId;
        @AuraEnabled public String confirmationNumber;
    }

    @AuraEnabled
    public static PaymentResult processPayment(String requestJson) {
        PaymentResult result = new PaymentResult();

        try {
            PaymentRequest req = (PaymentRequest) JSON.deserialize(requestJson, PaymentRequest.class);

            // Get payment method token
            ARF_Payment_Method__c pm = [
                SELECT Id, Token__c, Type__c, Status__c
                FROM ARF_Payment_Method__c WHERE Id = :req.paymentMethodId LIMIT 1
            ];
            if (pm.Status__c != 'Active') {
                result.success = false;
                result.message = 'Payment method is no longer active';
                return result;
            }

            // Charge via gateway
            ARF_PaymentGatewayService.GatewayResponse chargeResp =
                ARF_PaymentGatewayService.chargePaymentMethod(pm.Token__c, req.totalAmount, 'USD', 'Portal Payment');
            if (!chargeResp.success) {
                result.success = false;
                result.message = 'Payment declined: ' + chargeResp.message;
                return result;
            }

            // Create payment record
            ARF_Payment__c payment = new ARF_Payment__c();
            payment.Account__c = req.accountId;
            payment.Amount__c = req.totalAmount;
            payment.Applied_Amount__c = 0;
            payment.Unapplied_Amount__c = req.totalAmount;
            payment.Payment_Date__c = Date.today();
            payment.Method__c = pm.Type__c == 'Credit Card' ? 'Credit Card' : 'ACH';
            payment.Status__c = 'Received';
            payment.Reference__c = 'Portal - ' + chargeResp.transactionId;
            payment.Is_Portal_Payment__c = true;
            payment.Payment_Method__c = pm.Id;
            payment.Portal_User__c = UserInfo.getUserId();
            payment.Gateway_Reference__c = chargeResp.transactionId;
            payment.Gateway_Token__c = pm.Token__c;
            insert payment;

            // Allocate to invoices
            if (req.allocations != null && !req.allocations.isEmpty()) {
                ARF_PaymentAllocationEngine.AllocationResult allocResult =
                    ARF_PaymentAllocationEngine.allocatePayment(payment.Id, req.allocations);
                if (!allocResult.success) {
                    result.success = false;
                    result.message = 'Payment charged but allocation failed: ' + allocResult.message;
                    result.paymentId = payment.Id;
                    return result;
                }
            }

            result.success = true;
            result.paymentId = payment.Id;
            result.confirmationNumber = chargeResp.transactionId;
            result.message = 'Payment of $' + req.totalAmount.setScale(2) + ' processed successfully';

        } catch (Exception e) {
            result.success = false;
            result.message = 'Payment error: ' + e.getMessage();
        }
        return result;
    }

    // ─── Payment History ───────────────────────────────────────────────

    public class PaymentHistoryItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date paymentDate;
        @AuraEnabled public String method;
        @AuraEnabled public String status;
        @AuraEnabled public String reference;
        @AuraEnabled public Boolean isPortalPayment;
        @AuraEnabled public List<PaymentAppItem> applications;
    }

    public class PaymentAppItem {
        @AuraEnabled public String invoiceNumber;
        @AuraEnabled public Decimal amountApplied;
        @AuraEnabled public Date applicationDate;
    }

    @AuraEnabled(cacheable=true)
    public static List<PaymentHistoryItem> getPaymentHistory(Id accountId) {
        List<PaymentHistoryItem> items = new List<PaymentHistoryItem>();

        // Get payments with their applications
        Map<Id, PaymentHistoryItem> paymentMap = new Map<Id, PaymentHistoryItem>();
        for (ARF_Payment__c p : [
            SELECT Id, Name, Amount__c, Payment_Date__c, Method__c,
                   Status__c, Reference__c, Is_Portal_Payment__c
            FROM ARF_Payment__c
            WHERE Account__c = :accountId
            ORDER BY Payment_Date__c DESC
            LIMIT 100
        ]) {
            PaymentHistoryItem item = new PaymentHistoryItem();
            item.id = p.Id;
            item.name = p.Name;
            item.amount = p.Amount__c;
            item.paymentDate = p.Payment_Date__c;
            item.method = p.Method__c;
            item.status = p.Status__c;
            item.reference = p.Reference__c;
            item.isPortalPayment = p.Is_Portal_Payment__c;
            item.applications = new List<PaymentAppItem>();
            paymentMap.put(p.Id, item);
            items.add(item);
        }

        // Get payment applications
        if (!paymentMap.isEmpty()) {
            for (ARF_Payment_Application__c app : [
                SELECT Id, Payment__c, Amount_Applied__c, Application_Date__c,
                       Invoice__r.Document_Number__c
                FROM ARF_Payment_Application__c
                WHERE Payment__c IN :paymentMap.keySet()
                ORDER BY Application_Date__c DESC
            ]) {
                PaymentHistoryItem item = paymentMap.get(app.Payment__c);
                if (item != null) {
                    PaymentAppItem appItem = new PaymentAppItem();
                    appItem.invoiceNumber = app.Invoice__r.Document_Number__c;
                    appItem.amountApplied = app.Amount_Applied__c;
                    appItem.applicationDate = app.Application_Date__c;
                    item.applications.add(appItem);
                }
            }
        }
        return items;
    }

    // ─── Autopay ───────────────────────────────────────────────────────

    public class AutopayWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String ruleType;
        @AuraEnabled public Decimal fixedAmount;
        @AuraEnabled public Decimal maxAmount;
        @AuraEnabled public Integer scheduleDay;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Date lastRunDate;
        @AuraEnabled public Date nextRunDate;
        @AuraEnabled public String status;
        @AuraEnabled public Id paymentMethodId;
        @AuraEnabled public String paymentMethodLabel;
    }

    @AuraEnabled(cacheable=true)
    public static AutopayWrapper getAutopaySchedule(Id accountId) {
        List<ARF_Autopay_Schedule__c> schedules = [
            SELECT Id, Rule_Type__c, Fixed_Amount__c, Max_Amount__c, Schedule_Day__c,
                   Is_Active__c, Last_Run_Date__c, Next_Run_Date__c, Status__c,
                   Payment_Method__c, Payment_Method__r.Type__c,
                   Payment_Method__r.Last_Four__c, Payment_Method__r.Card_Brand__c,
                   Payment_Method__r.Bank_Name__c, Payment_Method__r.Nickname__c
            FROM ARF_Autopay_Schedule__c
            WHERE Account__c = :accountId
              AND Status__c != 'Cancelled'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (schedules.isEmpty()) return null;

        ARF_Autopay_Schedule__c sched = schedules[0];
        AutopayWrapper w = new AutopayWrapper();
        w.id = sched.Id;
        w.ruleType = sched.Rule_Type__c;
        w.fixedAmount = sched.Fixed_Amount__c;
        w.maxAmount = sched.Max_Amount__c;
        w.scheduleDay = sched.Schedule_Day__c != null ? Integer.valueOf(sched.Schedule_Day__c) : null;
        w.isActive = sched.Is_Active__c;
        w.lastRunDate = sched.Last_Run_Date__c;
        w.nextRunDate = sched.Next_Run_Date__c;
        w.status = sched.Status__c;
        w.paymentMethodId = sched.Payment_Method__c;

        // Build label
        if (sched.Payment_Method__r.Type__c == 'Credit Card') {
            w.paymentMethodLabel = (sched.Payment_Method__r.Card_Brand__c != null ?
                sched.Payment_Method__r.Card_Brand__c : 'Card') + ' ending in ' + sched.Payment_Method__r.Last_Four__c;
        } else {
            w.paymentMethodLabel = (sched.Payment_Method__r.Bank_Name__c != null ?
                sched.Payment_Method__r.Bank_Name__c : 'Bank') + ' ending in ' + sched.Payment_Method__r.Last_Four__c;
        }
        return w;
    }

    @AuraEnabled
    public static AutopayWrapper saveAutopaySchedule(Id accountId, Id paymentMethodId,
            String ruleType, Decimal fixedAmount, Decimal maxAmount, Integer scheduleDay) {
        // Cancel any existing active schedule
        List<ARF_Autopay_Schedule__c> existing = [
            SELECT Id FROM ARF_Autopay_Schedule__c
            WHERE Account__c = :accountId AND Status__c = 'Active'
        ];
        for (ARF_Autopay_Schedule__c ex : existing) {
            ex.Status__c = 'Cancelled';
            ex.Is_Active__c = false;
        }
        if (!existing.isEmpty()) update existing;

        // Calculate next run date
        Integer day = scheduleDay != null ? scheduleDay : 1;
        if (day > 28) day = 28;
        if (day < 1) day = 1;

        Date today = Date.today();
        Date nextRun;
        if (today.day() <= day) {
            Integer daysInMonth = Date.daysInMonth(today.year(), today.month());
            Integer actualDay = Math.min(day, daysInMonth);
            nextRun = Date.newInstance(today.year(), today.month(), actualDay);
        } else {
            Date nextMonth = today.addMonths(1);
            Integer daysInMonth = Date.daysInMonth(nextMonth.year(), nextMonth.month());
            Integer actualDay = Math.min(day, daysInMonth);
            nextRun = Date.newInstance(nextMonth.year(), nextMonth.month(), actualDay);
        }

        ARF_Autopay_Schedule__c sched = new ARF_Autopay_Schedule__c();
        sched.Account__c = accountId;
        sched.Payment_Method__c = paymentMethodId;
        sched.Rule_Type__c = ruleType;
        sched.Fixed_Amount__c = fixedAmount;
        sched.Max_Amount__c = maxAmount;
        sched.Schedule_Day__c = day;
        sched.Is_Active__c = true;
        sched.Status__c = 'Active';
        sched.Next_Run_Date__c = nextRun;
        insert sched;

        return getAutopaySchedule(accountId);
    }

    @AuraEnabled
    public static void cancelAutopay(Id scheduleId) {
        ARF_Autopay_Schedule__c sched = new ARF_Autopay_Schedule__c(Id = scheduleId);
        sched.Status__c = 'Cancelled';
        sched.Is_Active__c = false;
        update sched;
    }

    // ─── Helpers ───────────────────────────────────────────────────────

    private static String detectCardBrand(String cardNumber) {
        if (String.isBlank(cardNumber)) return 'Unknown';
        String num = cardNumber.replaceAll('[^0-9]', '');
        if (num.startsWith('4')) return 'Visa';
        if (num.startsWith('5') || num.startsWith('2')) return 'Mastercard';
        if (num.startsWith('3')) return 'Amex';
        if (num.startsWith('6')) return 'Discover';
        return 'Unknown';
    }
}
