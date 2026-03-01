trigger ARF_DisputeTrigger on ARF_Dispute__c (after insert, after delete, after undelete) {
    List<ARF_Dispute__c> disputes = Trigger.isDelete ? Trigger.old : Trigger.new;
    ARF_InvoiceFlagHandler.updateDisputeFlags(disputes);
}
