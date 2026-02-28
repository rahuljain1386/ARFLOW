public class ARF_AIEmailClassifier implements Queueable, Database.AllowsCallouts {

    private Id communicationId;

    public ARF_AIEmailClassifier(Id commId) {
        this.communicationId = commId;
    }

    public void execute(QueueableContext ctx) {
        ARF_Communication__c comm = [
            SELECT Id, Account__c, Subject__c, Body__c, From_Address__c,
                   Match_Method__c, Match_Confidence__c, Needs_Review__c,
                   Thread_ID__c, Channel__c
            FROM ARF_Communication__c
            WHERE Id = :communicationId
            LIMIT 1
        ];

        String prompt = buildPrompt(comm);
        String aiResponse = callClaudeAPI(prompt);

        if (String.isBlank(aiResponse)) {
            return;
        }

        Map<String, Object> parsed;
        String intent;
        String summary;

        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(aiResponse);
            intent = normalizeIntent((String) parsed.get('intent'));
            summary = (String) parsed.get('summary');

            // Update communication record
            comm.AI_Intent__c = intent;
            comm.AI_Drafted__c = true;
            update comm;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ARF_AIEmailClassifier parse error: ' + e.getMessage());
            return;
        }

        // If no account linked, try to suggest one from AI-extracted entities
        if (comm.Account__c == null) {
            suggestAccountFromEntities(comm, parsed);
        }

        // Auto-actions in separate try-catch so intent is preserved even if action fails
        try {
            if (intent == 'Dispute' && comm.Account__c != null) {
                createAutoDispute(comm, parsed);
            } else if (intent == 'Promise to Pay' && comm.Account__c != null) {
                createAutoPromise(comm, parsed);
            } else if (intent == 'Escalation' && comm.Account__c != null) {
                createEscalationTask(comm, summary);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ARF_AIEmailClassifier auto-action error: ' + e.getMessage());
        }

        // Send auto-acknowledgment email for actionable intents
        try {
            if (comm.Account__c != null && isActionableIntent(intent)) {
                sendAutoAcknowledgment(comm, intent, summary);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ARF_AIEmailClassifier ack error: ' + e.getMessage());
        }
    }

    @TestVisible
    private String buildPrompt(ARF_Communication__c comm) {
        String channelLabel = comm.Channel__c == 'SMS' ? 'SMS message' : (comm.Channel__c == 'Phone' ? 'call transcript' : 'email');
        return 'You are an AR (Accounts Receivable) communication classifier. Analyze the following ' + channelLabel + ' and return JSON only:\n' +
            '{\n' +
            '  "intent": "one of: payment_inquiry, dispute, promise_to_pay, invoice_request, general, escalation, payment_confirmation",\n' +
            '  "confidence": 0.0-1.0,\n' +
            '  "entities": {\n' +
            '    "invoice_numbers": [],\n' +
            '    "po_numbers": [],\n' +
            '    "amounts": [],\n' +
            '    "dates": [],\n' +
            '    "account_names": [],\n' +
            '    "reference_numbers": []\n' +
            '  },\n' +
            '  "suggested_action": "description of recommended action",\n' +
            '  "summary": "one line summary"\n' +
            '}\n\n' +
            'Extract ALL invoice numbers (INV-XXXX), PO numbers (PO-XXXX), company/account names, ' +
            'and reference numbers mentioned in the email.\n\n' +
            'Email Subject: ' + (comm.Subject__c != null ? comm.Subject__c : '') + '\n' +
            'Email From: ' + (comm.From_Address__c != null ? comm.From_Address__c : '') + '\n' +
            'Email Body:\n' + (comm.Body__c != null ? comm.Body__c.left(4000) : '');
    }

    @TestVisible
    private void suggestAccountFromEntities(ARF_Communication__c comm, Map<String, Object> parsed) {
        Map<String, Object> entities = (Map<String, Object>) parsed.get('entities');
        if (entities == null) return;

        Id suggestedAccountId = null;

        // Try invoice_numbers first
        List<Object> invoiceNums = (List<Object>) entities.get('invoice_numbers');
        if (invoiceNums != null && !invoiceNums.isEmpty()) {
            Set<String> invSet = new Set<String>();
            for (Object inv : invoiceNums) {
                invSet.add(String.valueOf(inv));
            }
            List<ARF_Invoice__c> invoices = [
                SELECT Account__c FROM ARF_Invoice__c
                WHERE Document_Number__c IN :invSet AND Account__c != null
                LIMIT 1
            ];
            if (!invoices.isEmpty()) {
                suggestedAccountId = invoices[0].Account__c;
            }
        }

        // Try po_numbers
        if (suggestedAccountId == null) {
            List<Object> poNums = (List<Object>) entities.get('po_numbers');
            if (poNums != null && !poNums.isEmpty()) {
                Set<String> poSet = new Set<String>();
                for (Object po : poNums) {
                    poSet.add(String.valueOf(po));
                }
                List<ARF_Invoice__c> invoices = [
                    SELECT Account__c FROM ARF_Invoice__c
                    WHERE PO_Number__c IN :poSet AND Account__c != null
                    LIMIT 1
                ];
                if (!invoices.isEmpty()) {
                    suggestedAccountId = invoices[0].Account__c;
                }
            }
        }

        // Try account_names
        if (suggestedAccountId == null) {
            List<Object> accountNames = (List<Object>) entities.get('account_names');
            if (accountNames != null && !accountNames.isEmpty()) {
                String nameSearch = '%' + String.escapeSingleQuotes(String.valueOf(accountNames[0])) + '%';
                List<Account> accounts = [
                    SELECT Id FROM Account WHERE Name LIKE :nameSearch LIMIT 1
                ];
                if (!accounts.isEmpty()) {
                    suggestedAccountId = accounts[0].Id;
                }
            }
        }

        // Apply suggestion if found
        if (suggestedAccountId != null) {
            comm.Account__c = suggestedAccountId;
            comm.Match_Method__c = 'AI Suggestion';
            comm.Match_Confidence__c = 70;
            comm.Needs_Review__c = true;
            update comm;
        }
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
            return extractJson(text);
        }
        return null;
    }

    private String extractJson(String text) {
        if (String.isBlank(text)) return null;
        Integer startIdx = text.indexOf('{');
        Integer endIdx = text.lastIndexOf('}');
        if (startIdx >= 0 && endIdx > startIdx) {
            return text.substring(startIdx, endIdx + 1);
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
        if (lower.contains('payment') && lower.contains('confirm')) return 'Payment Confirmation';
        if (lower.contains('payment') && lower.contains('inquir')) return 'Payment Inquiry';
        if (lower.contains('promise') || lower.contains('pay')) return 'Promise to Pay';
        if (lower.contains('invoice') && lower.contains('request')) return 'Invoice Request';
        if (lower.contains('escalat')) return 'Escalation';
        return 'General';
    }

    private Decimal parseAmount(Object rawAmount) {
        if (rawAmount == null) return 0;
        if (rawAmount instanceof Decimal) return (Decimal) rawAmount;
        if (rawAmount instanceof Double) return Decimal.valueOf((Double) rawAmount);
        if (rawAmount instanceof Integer) return Decimal.valueOf((Integer) rawAmount);
        if (rawAmount instanceof Long) return Decimal.valueOf((Long) rawAmount);
        String s = String.valueOf(rawAmount).replaceAll('[^0-9.]', '');
        return String.isBlank(s) ? 0 : Decimal.valueOf(s);
    }

    private void createAutoDispute(ARF_Communication__c comm, Map<String, Object> parsed) {
        Map<String, Object> entities = (Map<String, Object>) parsed.get('entities');
        List<Object> amounts = entities != null ? (List<Object>) entities.get('amounts') : null;
        Decimal amount = (amounts != null && !amounts.isEmpty()) ? parseAmount(amounts[0]) : 0;

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

        Decimal amount = (amounts != null && !amounts.isEmpty()) ? parseAmount(amounts[0]) : 0;
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

    @TestVisible
    private Boolean isActionableIntent(String intent) {
        Set<String> actionable = new Set<String>{
            'Dispute', 'Promise to Pay', 'Escalation', 'Invoice Request'
        };
        return intent != null && actionable.contains(intent);
    }

    private void sendAutoAcknowledgment(ARF_Communication__c comm, String intent, String summary) {
        if (String.isBlank(comm.From_Address__c)) {
            return;
        }

        String channel = comm.Channel__c != null ? comm.Channel__c : 'Email';

        if (channel == 'SMS') {
            sendSmsAcknowledgment(comm, intent, summary);
        } else if (channel == 'Phone') {
            sendCallSummaryEmail(comm, intent, summary);
        } else {
            sendEmailAcknowledgment(comm, intent, summary);
        }
    }

    private void sendEmailAcknowledgment(ARF_Communication__c comm, String intent, String summary) {
        Account acct = [SELECT Name FROM Account WHERE Id = :comm.Account__c LIMIT 1];

        List<OrgWideEmailAddress> owas = [SELECT Id, Address FROM OrgWideEmailAddress LIMIT 1];
        if (owas.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'ARF_AIEmailClassifier: No OrgWideEmailAddress configured, skipping ack');
            return;
        }

        String subject = 'Re: ' + (comm.Subject__c != null ? comm.Subject__c : 'Your Recent Email');
        String htmlBody = buildAckBody(intent, summary, acct.Name);

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ comm.From_Address__c });
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);
        email.setOrgWideEmailAddressId(owas[0].Id);
        email.setSaveAsActivity(false);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

        ARF_Communication__c outbound = new ARF_Communication__c(
            Account__c = comm.Account__c,
            Channel__c = 'Email',
            Direction__c = 'Outbound',
            Subject__c = subject,
            Body__c = htmlBody,
            HTML_Body__c = htmlBody,
            To_Address__c = comm.From_Address__c,
            From_Address__c = owas[0].Address,
            Status__c = 'Sent',
            Sent_Date__c = Datetime.now(),
            Thread_ID__c = comm.Thread_ID__c
        );
        insert outbound;
    }

    private void sendSmsAcknowledgment(ARF_Communication__c comm, String intent, String summary) {
        if (!ARF_TwilioService.isConfigured()) {
            System.debug(LoggingLevel.WARN, 'ARF_AIEmailClassifier: Twilio not configured, skipping SMS ack');
            return;
        }

        String smsBody = buildSmsAckBody(intent);

        try {
            String smsSid = ARF_TwilioService.sendSms(comm.From_Address__c, smsBody);

            ARF_Communication__c outbound = new ARF_Communication__c(
                Account__c = comm.Account__c,
                Channel__c = 'SMS',
                Direction__c = 'Outbound',
                Subject__c = 'SMS Ack: ' + intent,
                Body__c = smsBody,
                To_Address__c = comm.From_Address__c,
                From_Address__c = ARF_TwilioService.getConfig().Phone_Number__c,
                Status__c = 'Sent',
                Sent_Date__c = Datetime.now(),
                Thread_ID__c = smsSid
            );
            insert outbound;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ARF_AIEmailClassifier SMS ack error: ' + e.getMessage());
        }
    }

    private void sendCallSummaryEmail(ARF_Communication__c comm, String intent, String summary) {
        Account acct = [SELECT Name FROM Account WHERE Id = :comm.Account__c LIMIT 1];

        List<OrgWideEmailAddress> owas = [SELECT Id, Address FROM OrgWideEmailAddress LIMIT 1];
        if (owas.isEmpty()) return;

        // Send internal email summary of the call to the AR team
        String subject = 'Call Summary: ' + intent + ' — ' + acct.Name;
        String htmlBody = buildCallSummaryBody(intent, summary, acct.Name, comm.Body__c);

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ owas[0].Address });
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);
        email.setOrgWideEmailAddressId(owas[0].Id);
        email.setSaveAsActivity(false);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

        ARF_Communication__c outbound = new ARF_Communication__c(
            Account__c = comm.Account__c,
            Channel__c = 'Email',
            Direction__c = 'Outbound',
            Subject__c = subject,
            Body__c = htmlBody,
            HTML_Body__c = htmlBody,
            To_Address__c = owas[0].Address,
            From_Address__c = owas[0].Address,
            Status__c = 'Sent',
            Sent_Date__c = Datetime.now(),
            Thread_ID__c = comm.Thread_ID__c
        );
        insert outbound;
    }

    @TestVisible
    private String buildSmsAckBody(String intent) {
        if (intent == 'Dispute') {
            return 'Your dispute has been received and logged. Our AR team will investigate and follow up. Reply STOP to opt out.';
        } else if (intent == 'Promise to Pay') {
            return 'Thank you for your payment commitment. We have recorded your promise to pay. Reply STOP to opt out.';
        } else if (intent == 'Escalation') {
            return 'Your request has been escalated to a senior representative who will contact you shortly. Reply STOP to opt out.';
        } else if (intent == 'Invoice Request') {
            return 'We received your invoice inquiry. Our team will respond with the requested information. Reply STOP to opt out.';
        }
        return 'We have received your message and will respond shortly. Reply STOP to opt out.';
    }

    @TestVisible
    private String buildCallSummaryBody(String intent, String summary, String accountName, String transcript) {
        String intentAction;
        if (intent == 'Dispute') {
            intentAction = 'A dispute has been auto-created based on this call.';
        } else if (intent == 'Promise to Pay') {
            intentAction = 'A promise to pay has been auto-recorded based on this call.';
        } else if (intent == 'Escalation') {
            intentAction = 'An escalation task has been created based on this call.';
        } else if (intent == 'Invoice Request') {
            intentAction = 'An invoice inquiry was identified during this call.';
        } else {
            intentAction = 'No auto-action was taken.';
        }

        return '<div style="font-family: Arial, sans-serif; font-size: 14px; color: #333;">' +
            '<h2 style="color: #1a73e8;">Call Summary — ' + (accountName != null ? accountName : '') + '</h2>' +
            '<p><strong>AI Intent:</strong> ' + intent + '</p>' +
            '<p><strong>Summary:</strong> ' + (summary != null ? summary : 'N/A') + '</p>' +
            '<p><strong>Action Taken:</strong> ' + intentAction + '</p>' +
            '<hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;" />' +
            '<h3>Transcript</h3>' +
            '<pre style="background: #f5f5f5; padding: 12px; border-radius: 4px; white-space: pre-wrap; font-size: 13px;">' +
            (transcript != null ? transcript : 'No transcript available') +
            '</pre></div>';
    }

    @TestVisible
    private String buildAckBody(String intent, String summary, String accountName) {
        String intentMessage;
        if (intent == 'Dispute') {
            intentMessage = 'We have received your dispute and it has been logged for review. Our team will investigate and follow up.';
        } else if (intent == 'Promise to Pay') {
            intentMessage = 'Thank you for your payment commitment. We have recorded your promise to pay and will follow up accordingly.';
        } else if (intent == 'Escalation') {
            intentMessage = 'Your request has been escalated to a senior representative. Someone will reach out to you shortly.';
        } else if (intent == 'Invoice Request') {
            intentMessage = 'We have received your invoice inquiry. Our team will review and respond with the requested information.';
        } else {
            intentMessage = 'We have received your email and will respond shortly.';
        }

        return '<div style="font-family: Arial, sans-serif; font-size: 14px; color: #333;">' +
            '<p>Dear Customer,</p>' +
            '<p>' + intentMessage + '</p>' +
            '<p>If you have any further questions, please reply to this email or contact our accounts receivable team.</p>' +
            '<p>Best regards,<br/>Accounts Receivable Team</p>' +
            '<hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;" />' +
            '<p style="font-size: 12px; color: #999;">This is an automated acknowledgment. Reference: ' +
            (accountName != null ? accountName : '') + '</p>' +
            '</div>';
    }
}
