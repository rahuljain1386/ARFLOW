public with sharing class ARF_FlowActions {

    // Send dunning email via Flow
    @InvocableMethod(label='Send Dunning Email' description='Sends a dunning email to the account contact' category='ARFLOW')
    public static List<FlowResult> sendDunningEmail(List<DunningEmailRequest> requests) {
        List<FlowResult> results = new List<FlowResult>();
        for (DunningEmailRequest req : requests) {
            FlowResult res = new FlowResult();
            try {
                // Get account and contact info
                Account acct = [SELECT Id, Name FROM Account WHERE Id = :req.accountId LIMIT 1];
                Contact con = [SELECT Id, Email, FirstName FROM Contact
                    WHERE AccountId = :req.accountId AND ARF_Primary_AR_Contact__c = true LIMIT 1];

                if (con.Email == null) {
                    res.success = false;
                    res.message = 'No email address found for primary AR contact';
                    results.add(res);
                    continue;
                }

                // Create communication record
                ARF_Communication__c comm = new ARF_Communication__c();
                comm.Account__c = req.accountId;
                comm.Channel__c = 'Email';
                comm.Direction__c = 'Outbound';
                comm.Subject__c = String.isNotBlank(req.subject) ? req.subject : 'Payment Reminder - ' + acct.Name;
                comm.Body__c = String.isNotBlank(req.body) ? req.body : 'Dear ' + con.FirstName + ', this is a friendly reminder regarding your outstanding balance.';
                comm.Status__c = 'Sent';
                insert comm;

                res.success = true;
                res.message = 'Dunning email sent to ' + con.Email;
                res.communicationId = comm.Id;
            } catch (Exception e) {
                res.success = false;
                res.message = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    public class DunningEmailRequest {
        @InvocableVariable(label='Account ID' required=true)
        public Id accountId;
        @InvocableVariable(label='Email Subject')
        public String subject;
        @InvocableVariable(label='Email Body')
        public String body;
    }

    public class FlowResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Communication ID')
        public Id communicationId;
    }
}
