public with sharing class ARF_InvoiceFlagHandler {

    /**
     * Recalculate Has_Dispute__c on invoices related to the given disputes.
     * Called from ARF_DisputeTrigger after insert/delete/undelete.
     */
    public static void updateDisputeFlags(List<ARF_Dispute__c> disputes) {
        Set<Id> invoiceIds = new Set<Id>();
        for (ARF_Dispute__c d : disputes) {
            if (d.Invoice__c != null) {
                invoiceIds.add(d.Invoice__c);
            }
        }
        if (invoiceIds.isEmpty()) return;

        // Query invoices and check if any open disputes remain
        Map<Id, Boolean> invoiceHasDispute = new Map<Id, Boolean>();
        for (Id invId : invoiceIds) {
            invoiceHasDispute.put(invId, false);
        }

        for (AggregateResult ar : [
            SELECT Invoice__c invId, COUNT(Id) cnt
            FROM ARF_Dispute__c
            WHERE Invoice__c IN :invoiceIds
            GROUP BY Invoice__c
        ]) {
            Id invId = (Id) ar.get('invId');
            Integer cnt = (Integer) ar.get('cnt');
            invoiceHasDispute.put(invId, cnt > 0);
        }

        List<ARF_Invoice__c> toUpdate = new List<ARF_Invoice__c>();
        for (Id invId : invoiceIds) {
            toUpdate.add(new ARF_Invoice__c(
                Id = invId,
                Has_Dispute__c = invoiceHasDispute.get(invId)
            ));
        }
        update toUpdate;
    }

    /**
     * Recalculate Has_Promise__c on invoices related to the given promises.
     * Called from ARF_PromiseTrigger after insert/delete/undelete.
     */
    public static void updatePromiseFlags(List<ARF_Promise_To_Pay__c> promises) {
        Set<Id> invoiceIds = new Set<Id>();
        for (ARF_Promise_To_Pay__c p : promises) {
            if (p.Invoice__c != null) {
                invoiceIds.add(p.Invoice__c);
            }
        }
        if (invoiceIds.isEmpty()) return;

        Map<Id, Boolean> invoiceHasPromise = new Map<Id, Boolean>();
        for (Id invId : invoiceIds) {
            invoiceHasPromise.put(invId, false);
        }

        for (AggregateResult ar : [
            SELECT Invoice__c invId, COUNT(Id) cnt
            FROM ARF_Promise_To_Pay__c
            WHERE Invoice__c IN :invoiceIds
            GROUP BY Invoice__c
        ]) {
            Id invId = (Id) ar.get('invId');
            Integer cnt = (Integer) ar.get('cnt');
            invoiceHasPromise.put(invId, cnt > 0);
        }

        List<ARF_Invoice__c> toUpdate = new List<ARF_Invoice__c>();
        for (Id invId : invoiceIds) {
            toUpdate.add(new ARF_Invoice__c(
                Id = invId,
                Has_Promise__c = invoiceHasPromise.get(invId)
            ));
        }
        update toUpdate;
    }
}
