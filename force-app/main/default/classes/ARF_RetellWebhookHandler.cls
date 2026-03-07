@RestResource(urlMapping='/arflow/retell/*')
global class ARF_RetellWebhookHandler {

    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String body = req.requestBody != null ? req.requestBody.toString() : '{}';
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);

            String path = req.requestURI;

            if (path.contains('/call-ended')) {
                handleCallEnded(payload);
            }

            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"ok":true}');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ARF_RetellWebhookHandler error: ' + e.getMessage());
            // Always return 200 to prevent Retell retries
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"ok":true}');
        }
    }

    @TestVisible
    private static void handleCallEnded(Map<String, Object> payload) {
        String callId = (String) payload.get('call_id');
        String callStatus = (String) payload.get('call_status');
        String transcript = (String) payload.get('transcript');
        String recordingUrl = (String) payload.get('recording_url');
        String disconnReason = (String) payload.get('disconnection_reason');

        // Duration from timestamps
        Integer durationSeconds = 0;
        if (payload.get('start_timestamp') != null && payload.get('end_timestamp') != null) {
            Long startTs = Long.valueOf(String.valueOf(payload.get('start_timestamp')));
            Long endTs = Long.valueOf(String.valueOf(payload.get('end_timestamp')));
            durationSeconds = Integer.valueOf((endTs - startTs) / 1000);
        }

        // Structured analysis from Retell agent
        Map<String, Object> callAnalysis = payload.containsKey('call_analysis')
            ? (Map<String, Object>) payload.get('call_analysis') : null;

        // Metadata echoed from our call creation
        Map<String, Object> metadata = payload.containsKey('metadata')
            ? (Map<String, Object>) payload.get('metadata') : null;

        if (String.isBlank(callId)) return;

        // Find Communication record
        List<ARF_Communication__c> comms = [
            SELECT Id, Account__c, Status__c, Body__c
            FROM ARF_Communication__c
            WHERE Thread_ID__c = :callId
            LIMIT 1
        ];
        if (comms.isEmpty()) return;

        ARF_Communication__c comm = comms[0];

        // Determine status
        String newStatus;
        if (callStatus == 'ended' || callStatus == 'completed') {
            newStatus = 'Sent';
        } else if (callStatus == 'error' || disconnReason == 'dial_failed'
                   || disconnReason == 'voicemail_reached' || disconnReason == 'busy') {
            newStatus = 'Failed';
        } else {
            newStatus = 'Sent';
        }

        // Build transcript body
        String transcriptBody = '';
        if (callAnalysis != null && callAnalysis.containsKey('summary')) {
            transcriptBody += 'Summary: ' + String.valueOf(callAnalysis.get('summary')) + '\n\n';
        }
        if (String.isNotBlank(transcript)) {
            transcriptBody += '--- Call Transcript ---\n' + transcript;
        }
        if (String.isBlank(transcriptBody)) {
            transcriptBody = 'Call ' + (newStatus == 'Sent' ? 'completed' : 'failed') +
                '. Duration: ' + durationSeconds + 's.';
        }

        // Update Communication
        comm.Status__c = newStatus;
        comm.Body__c = transcriptBody;
        comm.Call_Duration_Seconds__c = durationSeconds;

        if (String.isNotBlank(recordingUrl)) {
            comm.HTML_Body__c = '<a href="' + recordingUrl + '">Listen to Recording</a>' +
                '<pre>' + transcriptBody.escapeHtml4() + '</pre>';
        }

        // Set AI intent if structured analysis available
        if (callAnalysis != null && callAnalysis.containsKey('intent')) {
            String intent = String.valueOf(callAnalysis.get('intent'));
            comm.AI_Intent__c = mapRetellIntent(intent);
            comm.AI_Drafted__c = true;
        }

        update comm;

        // Complete associated Task
        if (metadata != null && metadata.containsKey('taskId')) {
            String taskIdStr = String.valueOf(metadata.get('taskId'));
            if (String.isNotBlank(taskIdStr) && taskIdStr != 'null') {
                try {
                    Id taskId = Id.valueOf(taskIdStr);
                    update new Task(Id = taskId, Status = 'Completed');
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN,
                        'ARF_RetellWebhookHandler: Could not complete task: ' + e.getMessage());
                }
            }
        }

        // Update Account last contact date
        if (comm.Account__c != null) {
            update new Account(Id = comm.Account__c, ARF_Last_Contact_Date__c = Date.today());
        }

        // Queue AI classifier for transcript analysis (reuses existing pipeline)
        // Skip if Retell already provided structured call analysis
        if (newStatus == 'Sent' && String.isNotBlank(transcript) && callAnalysis == null) {
            System.enqueueJob(new ARF_AIEmailClassifier(comm.Id));
        }
    }

    @TestVisible
    private static String mapRetellIntent(String retellIntent) {
        if (String.isBlank(retellIntent)) return 'General';
        String lower = retellIntent.toLowerCase();
        if (lower.contains('promise') || lower.contains('pay')) return 'Promise to Pay';
        if (lower.contains('dispute')) return 'Dispute';
        if (lower.contains('escalat')) return 'Escalation';
        if (lower.contains('invoice')) return 'Invoice Request';
        if (lower.contains('complaint')) return 'Complaint';
        if (lower.contains('query') || lower.contains('question')) return 'Query';
        return 'General';
    }
}
