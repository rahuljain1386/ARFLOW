/**
 * ARF_PaymentAllocationEngine
 * Handles allocation of payments to invoices with rules:
 * - Past due invoices first, then by due date (oldest first)
 * - Partial allocations supported
 * - Updates invoice Balance and Status
 * - Updates payment Applied/Unapplied amounts
 */
public with sharing class ARF_PaymentAllocationEngine {

    public class AllocationLine {
        @AuraEnabled public Id invoiceId;
        @AuraEnabled public Decimal amount;
    }

    public class AllocationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id paymentId;
        @AuraEnabled public List<Id> applicationIds;
    }

    /**
     * Allocate payment to specific invoices with specified amounts
     */
    public static AllocationResult allocatePayment(Id paymentId, List<AllocationLine> allocations) {
        AllocationResult result = new AllocationResult();
        result.applicationIds = new List<Id>();

        Savepoint sp = Database.setSavepoint();
        try {
            // Get the payment
            ARF_Payment__c payment = [
                SELECT Id, Amount__c, Applied_Amount__c, Unapplied_Amount__c, Account__c, Status__c
                FROM ARF_Payment__c WHERE Id = :paymentId LIMIT 1
            ];

            // Get all invoices being allocated to
            Set<Id> invoiceIds = new Set<Id>();
            for (AllocationLine al : allocations) {
                invoiceIds.add(al.invoiceId);
            }
            Map<Id, ARF_Invoice__c> invoiceMap = new Map<Id, ARF_Invoice__c>([
                SELECT Id, Balance__c, Amount__c, Status__c
                FROM ARF_Invoice__c WHERE Id IN :invoiceIds
            ]);

            // Validate total allocation doesn't exceed unapplied amount
            Decimal totalAllocated = 0;
            for (AllocationLine al : allocations) {
                if (al.amount <= 0) {
                    result.success = false;
                    result.message = 'Allocation amount must be positive';
                    return result;
                }
                ARF_Invoice__c inv = invoiceMap.get(al.invoiceId);
                if (inv == null) {
                    result.success = false;
                    result.message = 'Invoice not found: ' + al.invoiceId;
                    return result;
                }
                if (al.amount > inv.Balance__c) {
                    result.success = false;
                    result.message = 'Allocation amount exceeds invoice balance for invoice ' + al.invoiceId;
                    return result;
                }
                totalAllocated += al.amount;
            }

            Decimal available = payment.Amount__c - (payment.Applied_Amount__c != null ? payment.Applied_Amount__c : 0);
            if (totalAllocated > available) {
                result.success = false;
                result.message = 'Total allocation (' + totalAllocated + ') exceeds unapplied amount (' + available + ')';
                return result;
            }

            // Create payment application records
            List<ARF_Payment_Application__c> apps = new List<ARF_Payment_Application__c>();
            List<ARF_Invoice__c> invoicesToUpdate = new List<ARF_Invoice__c>();

            for (AllocationLine al : allocations) {
                ARF_Payment_Application__c app = new ARF_Payment_Application__c();
                app.Payment__c = paymentId;
                app.Invoice__c = al.invoiceId;
                app.Amount_Applied__c = al.amount;
                app.Application_Date__c = Date.today();
                apps.add(app);

                // Update invoice balance
                ARF_Invoice__c inv = invoiceMap.get(al.invoiceId);
                inv.Balance__c = inv.Balance__c - al.amount;
                if (inv.Balance__c <= 0) {
                    inv.Balance__c = 0;
                    inv.Status__c = 'Paid';
                } else {
                    inv.Status__c = 'Partially Paid';
                }
                invoicesToUpdate.add(inv);
            }

            insert apps;
            update invoicesToUpdate;

            // Update payment applied/unapplied amounts and status
            Decimal newApplied = (payment.Applied_Amount__c != null ? payment.Applied_Amount__c : 0) + totalAllocated;
            payment.Applied_Amount__c = newApplied;
            payment.Unapplied_Amount__c = payment.Amount__c - newApplied;
            if (payment.Unapplied_Amount__c <= 0) {
                payment.Unapplied_Amount__c = 0;
                payment.Status__c = 'Applied';
            } else {
                payment.Status__c = 'Partially Applied';
            }
            update payment;

            for (ARF_Payment_Application__c app : apps) {
                result.applicationIds.add(app.Id);
            }
            result.success = true;
            result.paymentId = paymentId;
            result.message = 'Successfully allocated ' + totalAllocated + ' across ' + allocations.size() + ' invoice(s)';

        } catch (Exception e) {
            Database.rollback(sp);
            result.success = false;
            result.message = 'Allocation failed: ' + e.getMessage();
        }
        return result;
    }

    /**
     * Auto-allocate: Apply payment to oldest past-due invoices first, then by due date
     */
    public static AllocationResult autoAllocate(Id paymentId, Id accountId) {
        ARF_Payment__c payment = [
            SELECT Id, Amount__c, Applied_Amount__c, Unapplied_Amount__c
            FROM ARF_Payment__c WHERE Id = :paymentId LIMIT 1
        ];

        Decimal available = payment.Amount__c - (payment.Applied_Amount__c != null ? payment.Applied_Amount__c : 0);
        if (available <= 0) {
            AllocationResult result = new AllocationResult();
            result.success = false;
            result.message = 'No unapplied amount available';
            return result;
        }

        // Get open invoices ordered: past due first, then by due date ascending
        List<ARF_Invoice__c> invoices = [
            SELECT Id, Balance__c, Due_Date__c, Is_Overdue__c
            FROM ARF_Invoice__c
            WHERE Account__c = :accountId
              AND Balance__c > 0
              AND Status__c IN ('Open', 'Partially Paid')
            ORDER BY Is_Overdue__c DESC, Due_Date__c ASC
        ];

        List<AllocationLine> allocations = new List<AllocationLine>();
        Decimal remaining = available;

        for (ARF_Invoice__c inv : invoices) {
            if (remaining <= 0) break;

            AllocationLine al = new AllocationLine();
            al.invoiceId = inv.Id;
            al.amount = Math.min(remaining, inv.Balance__c);
            allocations.add(al);
            remaining -= al.amount;
        }

        if (allocations.isEmpty()) {
            AllocationResult result = new AllocationResult();
            result.success = false;
            result.message = 'No open invoices found for this account';
            return result;
        }

        return allocatePayment(paymentId, allocations);
    }

    /**
     * Reverse all allocations for a payment
     */
    public static AllocationResult reversePayment(Id paymentId) {
        AllocationResult result = new AllocationResult();
        Savepoint sp = Database.setSavepoint();

        try {
            // Get all payment applications
            List<ARF_Payment_Application__c> apps = [
                SELECT Id, Invoice__c, Amount_Applied__c
                FROM ARF_Payment_Application__c
                WHERE Payment__c = :paymentId
            ];

            if (apps.isEmpty()) {
                result.success = false;
                result.message = 'No allocations found to reverse';
                return result;
            }

            // Restore invoice balances
            Set<Id> invoiceIds = new Set<Id>();
            Map<Id, Decimal> restoreAmounts = new Map<Id, Decimal>();
            for (ARF_Payment_Application__c app : apps) {
                invoiceIds.add(app.Invoice__c);
                Decimal current = restoreAmounts.containsKey(app.Invoice__c) ? restoreAmounts.get(app.Invoice__c) : 0;
                restoreAmounts.put(app.Invoice__c, current + app.Amount_Applied__c);
            }

            List<ARF_Invoice__c> invoices = [
                SELECT Id, Balance__c, Amount__c, Status__c
                FROM ARF_Invoice__c WHERE Id IN :invoiceIds
            ];

            for (ARF_Invoice__c inv : invoices) {
                Decimal restoreAmt = restoreAmounts.get(inv.Id);
                inv.Balance__c = inv.Balance__c + restoreAmt;
                if (inv.Balance__c >= inv.Amount__c) {
                    inv.Status__c = 'Open';
                } else {
                    inv.Status__c = 'Partially Paid';
                }
            }
            update invoices;

            // Delete payment applications
            delete apps;

            // Reset payment
            ARF_Payment__c payment = [
                SELECT Id, Amount__c FROM ARF_Payment__c WHERE Id = :paymentId LIMIT 1
            ];
            payment.Applied_Amount__c = 0;
            payment.Unapplied_Amount__c = payment.Amount__c;
            payment.Status__c = 'Reversed';
            update payment;

            result.success = true;
            result.paymentId = paymentId;
            result.message = 'Payment reversed — ' + apps.size() + ' allocation(s) removed';

        } catch (Exception e) {
            Database.rollback(sp);
            result.success = false;
            result.message = 'Reversal failed: ' + e.getMessage();
        }
        return result;
    }
}
