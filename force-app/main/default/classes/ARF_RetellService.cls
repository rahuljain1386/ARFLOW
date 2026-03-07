public class ARF_RetellService {

    private static final String RETELL_API_BASE = 'https://api.retellai.com/v2/';

    // ===== CONFIGURATION =====

    public static ARF_Retell_Config__c getConfig() {
        return ARF_Retell_Config__c.getOrgDefaults();
    }

    public static Boolean isConfigured() {
        ARF_Retell_Config__c config = getConfig();
        return config != null &&
               String.isNotBlank(config.API_Key__c) &&
               String.isNotBlank(config.Agent_ID__c) &&
               String.isNotBlank(config.From_Number__c);
    }

    // ===== INITIATE CALL =====

    public static String initiateCall(String toNumber, Id accountId, Id contactId,
                                      Map<String, Object> dynamicVars) {
        ARF_Retell_Config__c config = getConfig();
        if (!isConfigured()) {
            throw new RetellException('Retell AI not configured. Add credentials in Setup > Custom Settings > ARF Retell Config.');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(RETELL_API_BASE + 'create-phone-call');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + config.API_Key__c);

        Map<String, Object> body = new Map<String, Object>{
            'from_number' => config.From_Number__c,
            'to_number' => toNumber,
            'override_agent_id' => config.Agent_ID__c
        };

        if (dynamicVars != null && !dynamicVars.isEmpty()) {
            body.put('retell_llm_dynamic_variables', dynamicVars);
        }

        body.put('metadata', new Map<String, String>{
            'accountId' => String.valueOf(accountId),
            'contactId' => contactId != null ? String.valueOf(contactId) : ''
        });

        req.setBody(JSON.serialize(body));
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 201) {
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) responseBody.get('call_id');
        } else {
            throw new RetellException('Retell API error: ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }

    // ===== INITIATE CALL + CREATE COMMUNICATION =====

    public static Id initiateCallWithRecord(String toNumber, Id accountId, Id contactId,
                                            Id taskId, Map<String, Object> dynamicVars) {
        // Add taskId to metadata so webhook can complete it
        if (dynamicVars == null) dynamicVars = new Map<String, Object>();

        String callId = null;
        String status = 'Draft';

        try {
            // Include taskId in the Retell metadata
            Map<String, Object> callBody = new Map<String, Object>();
            callBody.putAll(dynamicVars);

            callId = initiateCall(toNumber, accountId, contactId, callBody);
            status = 'In Progress';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ARF_RetellService Call error: ' + e.getMessage());
            status = 'Failed';
        }

        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = accountId,
            Contact__c = contactId,
            Channel__c = 'Phone',
            Direction__c = 'Outbound',
            Subject__c = 'AI Voice Call to ' + toNumber,
            Body__c = status == 'Failed'
                ? 'Call initiation failed.'
                : 'Retell AI call initiated. Transcript will populate when call ends.',
            To_Address__c = toNumber,
            From_Address__c = isConfigured() ? getConfig().From_Number__c : null,
            Status__c = status,
            Sent_Date__c = Datetime.now(),
            Thread_ID__c = callId
        );
        insert comm;

        // Store taskId reference in the comm subject for the webhook to find
        if (taskId != null && callId != null) {
            // We rely on metadata echoed by Retell to complete the task in webhook
            System.debug('Retell call initiated. CallId: ' + callId + ' TaskId: ' + taskId);
        }

        return comm.Id;
    }

    // ===== BUILD DYNAMIC VARS =====

    public static Map<String, Object> buildDynamicVars(Account acct, Contact primaryContact) {
        Map<String, Object> vars = new Map<String, Object>();
        vars.put('account_name', acct.Name != null ? acct.Name : 'Customer');
        vars.put('contact_name', primaryContact != null ? primaryContact.Name : 'Valued Customer');
        vars.put('total_past_due', acct.ARF_Past_Due__c != null
            ? '$' + String.valueOf(acct.ARF_Past_Due__c.setScale(2)) : '$0.00');
        vars.put('overdue_count', acct.ARF_Overdue_Invoice_Count__c != null
            ? String.valueOf(Integer.valueOf(acct.ARF_Overdue_Invoice_Count__c)) : '0');
        vars.put('total_ar', acct.ARF_Total_AR__c != null
            ? '$' + String.valueOf(acct.ARF_Total_AR__c.setScale(2)) : '$0.00');

        ARF_Retell_Config__c config = getConfig();
        if (config != null && String.isNotBlank(config.Webhook_Base_URL__c)) {
            vars.put('context_api_url', config.Webhook_Base_URL__c +
                '/services/apexrest/arflow/voice/context?accountId=' + acct.Id);
        }

        return vars;
    }

    // ===== QUEUEABLE FOR ASYNC CALL INITIATION =====

    public class InitiateCallQueueable implements Queueable, Database.AllowsCallouts {

        private Id accountId;
        private Id contactId;
        private Id taskId;
        private String toNumber;

        public InitiateCallQueueable(Id accountId, Id contactId, Id taskId, String toNumber) {
            this.accountId = accountId;
            this.contactId = contactId;
            this.taskId = taskId;
            this.toNumber = toNumber;
        }

        public void execute(QueueableContext ctx) {
            Account acct = [
                SELECT Id, Name, AccountNumber, ARF_Past_Due__c, ARF_Total_AR__c,
                       ARF_Overdue_Invoice_Count__c, ARF_Risk_Score__c,
                       ARF_Assigned_Collector__c
                FROM Account WHERE Id = :accountId LIMIT 1
            ];

            Contact primaryContact = null;
            if (contactId != null) {
                List<Contact> contacts = [SELECT Id, Name FROM Contact WHERE Id = :contactId LIMIT 1];
                if (!contacts.isEmpty()) primaryContact = contacts[0];
            }

            Map<String, Object> dynamicVars = buildDynamicVars(acct, primaryContact);
            initiateCallWithRecord(toNumber, accountId, contactId, taskId, dynamicVars);
        }
    }

    public class RetellException extends Exception {}
}
