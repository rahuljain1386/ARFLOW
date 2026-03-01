trigger ARF_PromiseTrigger on ARF_Promise_To_Pay__c (after insert, after delete, after undelete) {
    List<ARF_Promise_To_Pay__c> promises = Trigger.isDelete ? Trigger.old : Trigger.new;
    ARF_InvoiceFlagHandler.updatePromiseFlags(promises);
}
