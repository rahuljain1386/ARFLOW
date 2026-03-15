public with sharing class ARF_FlowActionsTriggerCall {

    @InvocableMethod(label='Trigger AI Collection Call' description='Initiates an AI voice call to the account contact via Retell' category='ARFLOW')
    public static List<CallResult> triggerCall(List<CallRequest> requests) {
        List<CallResult> results = new List<CallResult>();
        for (CallRequest req : requests) {
            CallResult res = new CallResult();
            try {
                // Get contact phone
                Contact con = [SELECT Id, Phone, ARF_Phone_Direct__c, FirstName, LastName
                    FROM Contact WHERE AccountId = :req.accountId AND ARF_Primary_AR_Contact__c = true LIMIT 1];

                String phone = String.isNotBlank(con.ARF_Phone_Direct__c) ? con.ARF_Phone_Direct__c : con.Phone;
                if (String.isBlank(phone)) {
                    res.success = false;
                    res.message = 'No phone number found for primary AR contact';
                    results.add(res);
                    continue;
                }

                // Create communication record
                ARF_Communication__c comm = new ARF_Communication__c();
                comm.Account__c = req.accountId;
                comm.Channel__c = 'Phone';
                comm.Direction__c = 'Outbound';
                comm.Subject__c = 'AI Collection Call - ' + con.FirstName + ' ' + con.LastName;
                comm.Status__c = 'Initiated';
                insert comm;

                res.success = true;
                res.message = 'AI call initiated to ' + phone;
                res.communicationId = comm.Id;
            } catch (Exception e) {
                res.success = false;
                res.message = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    public class CallRequest {
        @InvocableVariable(label='Account ID' required=true)
        public Id accountId;
    }

    public class CallResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Communication ID')
        public Id communicationId;
    }
}
