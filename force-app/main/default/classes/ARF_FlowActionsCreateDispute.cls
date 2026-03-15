public with sharing class ARF_FlowActionsCreateDispute {

    @InvocableMethod(label='Create Invoice Dispute' description='Creates a dispute record for an invoice' category='ARFLOW')
    public static List<DisputeResult> createDispute(List<DisputeRequest> requests) {
        List<DisputeResult> results = new List<DisputeResult>();
        for (DisputeRequest req : requests) {
            DisputeResult res = new DisputeResult();
            try {
                ARF_Dispute__c dispute = new ARF_Dispute__c();
                dispute.Invoice__c = req.invoiceId;
                dispute.Dispute_Amount__c = req.amount;
                dispute.Category__c = String.isNotBlank(req.category) ? req.category : 'Other';
                dispute.Description__c = req.description;
                dispute.Status__c = 'New';
                dispute.Priority__c = 'Medium';
                insert dispute;

                res.success = true;
                res.message = 'Dispute created successfully';
                res.disputeId = dispute.Id;
            } catch (Exception e) {
                res.success = false;
                res.message = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    public class DisputeRequest {
        @InvocableVariable(label='Invoice ID' required=true)
        public Id invoiceId;
        @InvocableVariable(label='Dispute Amount')
        public Decimal amount;
        @InvocableVariable(label='Category')
        public String category;
        @InvocableVariable(label='Description')
        public String description;
    }

    public class DisputeResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Dispute ID')
        public Id disputeId;
    }
}
