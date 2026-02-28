public class ARF_AIEmailClassifier implements Queueable, Database.AllowsCallouts {

    private Id communicationId;

    public ARF_AIEmailClassifier(Id commId) {
        this.communicationId = commId;
    }

    public void execute(QueueableContext ctx) {
        ARF_Communication__c comm = [
            SELECT Id, Account__c, Subject__c, Body__c, From_Address__c
            FROM ARF_Communication__c
            WHERE Id = :communicationId
            LIMIT 1
        ];

        String prompt = buildPrompt(comm);
        String aiResponse = callClaudeAPI(prompt);

        if (String.isBlank(aiResponse)) {
            return;
        }

        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(aiResponse);
            String intent = (String) parsed.get('intent');
            String summary = (String) parsed.get('summary');

            // Normalize intent
            intent = normalizeIntent(intent);

            // Update communication record
            comm.AI_Intent__c = intent;
            comm.AI_Drafted__c = true;
            update comm;

            // Auto-actions based on intent
            if (intent == 'Dispute' && comm.Account__c != null) {
                createAutoDispute(comm, parsed);
            } else if (intent == 'Promise to Pay' && comm.Account__c != null) {
                createAutoPromise(comm, parsed);
            } else if (intent == 'Escalation' && comm.Account__c != null) {
                createEscalationTask(comm, summary);
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ARF_AIEmailClassifier parse error: ' + e.getMessage());
        }
    }

    @TestVisible
    private String buildPrompt(ARF_Communication__c comm) {
        return 'You are an AR (Accounts Receivable) email classifier. Analyze the following email and return JSON only:\n' +
            '{\n' +
            '  "intent": "one of: payment_inquiry, dispute, promise_to_pay, invoice_request, general, escalation, payment_confirmation",\n' +
            '  "confidence": 0.0-1.0,\n' +
            '  "entities": {\n' +
            '    "invoice_numbers": [],\n' +
            '    "amounts": [],\n' +
            '    "dates": []\n' +
            '  },\n' +
            '  "suggested_action": "description of recommended action",\n' +
            '  "summary": "one line summary"\n' +
            '}\n\n' +
            'Email Subject: ' + (comm.Subject__c != null ? comm.Subject__c : '') + '\n' +
            'Email From: ' + (comm.From_Address__c != null ? comm.From_Address__c : '') + '\n' +
            'Email Body:\n' + (comm.Body__c != null ? comm.Body__c.left(4000) : '');
    }

    private String callClaudeAPI(String prompt) {
        String apiKey = getAPIKey();
        if (String.isBlank(apiKey)) {
            System.debug(LoggingLevel.WARN, 'ARF_AIEmailClassifier: No API key configured');
            return null;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.anthropic.com/v1/messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('anthropic-version', '2023-06-01');
        req.setHeader('x-api-key', apiKey);

        Map<String, Object> body = new Map<String, Object>{
            'model' => 'claude-sonnet-4-20250514',
            'max_tokens' => 1024,
            'messages' => new List<Object>{
                new Map<String, String>{ 'role' => 'user', 'content' => prompt }
            }
        };
        req.setBody(JSON.serialize(body));
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            System.debug(LoggingLevel.ERROR, 'Claude API error: ' + res.getStatusCode() + ' ' + res.getBody());
            return null;
        }

        // Parse the response — extract text from content[0].text
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> content = (List<Object>) responseBody.get('content');
        if (content != null && !content.isEmpty()) {
            Map<String, Object> firstBlock = (Map<String, Object>) content[0];
            String text = (String) firstBlock.get('text');
            // Extract JSON from the response text (may have markdown wrapping)
            return extractJson(text);
        }
        return null;
    }

    private String extractJson(String text) {
        if (String.isBlank(text)) return null;
        // Try to find JSON block between { and }
        Integer start = text.indexOf('{');
        Integer end = text.lastIndexOf('}');
        if (start >= 0 && end > start) {
            return text.substring(start, end + 1);
        }
        return text;
    }

    private String getAPIKey() {
        ARF_AI_Config__c config = ARF_AI_Config__c.getInstance();
        return config != null ? config.API_Key__c : null;
    }

    @TestVisible
    private String normalizeIntent(String rawIntent) {
        if (String.isBlank(rawIntent)) return 'General';
        String lower = rawIntent.toLowerCase().replace('_', ' ');
        if (lower.contains('dispute')) return 'Dispute';
        if (lower.contains('promise') || lower.contains('pay')) return 'Promise to Pay';
        if (lower.contains('payment') && lower.contains('confirm')) return 'Payment Confirmation';
        if (lower.contains('payment') && lower.contains('inquir')) return 'Payment Inquiry';
        if (lower.contains('invoice') && lower.contains('request')) return 'Invoice Request';
        if (lower.contains('escalat')) return 'Escalation';
        return 'General';
    }

    private void createAutoDispute(ARF_Communication__c comm, Map<String, Object> parsed) {
        // Extract invoice references if available
        Map<String, Object> entities = (Map<String, Object>) parsed.get('entities');
        List<Object> amounts = entities != null ? (List<Object>) entities.get('amounts') : null;
        Decimal amount = (amounts != null && !amounts.isEmpty()) ? Decimal.valueOf(String.valueOf(amounts[0])) : 0;

        ARF_Dispute__c dispute = new ARF_Dispute__c(
            Account__c = comm.Account__c,
            Status__c = 'New',
            Category__c = 'Other',
            Priority__c = 'Medium',
            Dispute_Amount__c = amount,
            Description__c = 'Auto-created from inbound email: ' + (comm.Subject__c != null ? comm.Subject__c : '')
        );
        insert dispute;
    }

    private void createAutoPromise(ARF_Communication__c comm, Map<String, Object> parsed) {
        Map<String, Object> entities = (Map<String, Object>) parsed.get('entities');
        List<Object> amounts = entities != null ? (List<Object>) entities.get('amounts') : null;
        List<Object> dates = entities != null ? (List<Object>) entities.get('dates') : null;

        Decimal amount = (amounts != null && !amounts.isEmpty()) ? Decimal.valueOf(String.valueOf(amounts[0])) : 0;
        Date promiseDate = Date.today().addDays(7);
        if (dates != null && !dates.isEmpty()) {
            try {
                promiseDate = Date.valueOf((String) dates[0]);
            } catch (Exception e) {
                // Keep default
            }
        }

        ARF_Promise_To_Pay__c promise = new ARF_Promise_To_Pay__c(
            Account__c = comm.Account__c,
            Amount__c = amount,
            Promise_Date__c = promiseDate,
            Status__c = 'Open',
            Notes__c = 'Auto-created from inbound email: ' + (comm.Subject__c != null ? comm.Subject__c : '')
        );
        insert promise;
    }

    private void createEscalationTask(ARF_Communication__c comm, String summary) {
        Task escalation = new Task(
            WhatId = comm.Account__c,
            Subject = 'Escalation: ' + (comm.Subject__c != null ? comm.Subject__c.left(200) : 'Inbound Email'),
            Description = 'Auto-escalated from inbound email.\n\nSummary: ' + (summary != null ? summary : ''),
            ActivityDate = Date.today().addDays(1),
            Priority = 'High',
            Status = 'Not Started'
        );
        insert escalation;
    }
}
