@RestResource(urlMapping='/arflow/twilio/*')
global class ARF_TwilioCallbackResource {

    @HttpPost
    global static void handleCallback() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        // Parse form-encoded body (Twilio sends application/x-www-form-urlencoded)
        Map<String, String> params = parseFormBody(req);

        // Also merge query string params
        if (req.params != null) {
            params.putAll(req.params);
        }

        String path = req.requestURI;

        try {
            if (path.contains('/voice/transcription')) {
                handleTranscription(params);
            } else if (path.contains('/voice/status')) {
                handleCallStatus(params);
            } else if (path.contains('/sms')) {
                handleInboundSms(params);
            }

            res.statusCode = 200;
            res.addHeader('Content-Type', 'text/xml');
            res.responseBody = Blob.valueOf('<Response></Response>');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ARF_TwilioCallbackResource error: ' + e.getMessage());
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('<Response></Response>');
        }
    }

    // ===== INBOUND SMS =====

    @TestVisible
    private static void handleInboundSms(Map<String, String> params) {
        String fromNumber = params.get('From');
        String toNumber = params.get('To');
        String body = params.get('Body');
        String smsSid = params.get('SmsSid');

        if (String.isBlank(fromNumber) || String.isBlank(body)) return;

        // Match sender to account by phone number
        Id accountId = matchAccountByPhone(fromNumber);

        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = accountId,
            Channel__c = 'SMS',
            Direction__c = 'Inbound',
            Subject__c = 'SMS from ' + fromNumber,
            Body__c = body,
            From_Address__c = fromNumber,
            To_Address__c = toNumber,
            Status__c = 'Received',
            Sent_Date__c = Datetime.now(),
            Thread_ID__c = smsSid
        );
        insert comm;

        // Queue AI classifier
        System.enqueueJob(new ARF_AIEmailClassifier(comm.Id));
    }

    // ===== CALL STATUS =====

    @TestVisible
    private static void handleCallStatus(Map<String, String> params) {
        String callSid = params.get('CallSid');
        String callStatus = params.get('CallStatus');
        String callDuration = params.get('CallDuration');

        if (String.isBlank(callSid)) return;

        List<ARF_Communication__c> comms = [
            SELECT Id, Account__c, Status__c
            FROM ARF_Communication__c
            WHERE Thread_ID__c = :callSid
            LIMIT 1
        ];

        if (comms.isEmpty()) return;

        ARF_Communication__c comm = comms[0];

        if (String.isNotBlank(callDuration)) {
            try {
                comm.Call_Duration_Seconds__c = Integer.valueOf(callDuration);
            } catch (Exception e) {
                // ignore parse errors
            }
        }

        if (callStatus == 'completed') {
            comm.Status__c = 'Sent';
        } else if (callStatus == 'failed' || callStatus == 'busy' || callStatus == 'no-answer') {
            comm.Status__c = 'Failed';
        }

        update comm;
    }

    // ===== CALL TRANSCRIPTION =====

    @TestVisible
    private static void handleTranscription(Map<String, String> params) {
        String callSid = params.get('CallSid');
        String transcriptionText = params.get('TranscriptionText');
        String transcriptionStatus = params.get('TranscriptionStatus');

        if (String.isBlank(callSid)) return;
        if (transcriptionStatus != 'completed' || String.isBlank(transcriptionText)) return;

        List<ARF_Communication__c> comms = [
            SELECT Id, Account__c, Body__c
            FROM ARF_Communication__c
            WHERE Thread_ID__c = :callSid
            LIMIT 1
        ];

        if (comms.isEmpty()) return;

        ARF_Communication__c comm = comms[0];
        String existingBody = String.isNotBlank(comm.Body__c) ? comm.Body__c + '\n\n' : '';
        comm.Body__c = existingBody + '--- Call Transcript ---\n' + transcriptionText;
        update comm;

        // Queue AI classifier on the transcript
        System.enqueueJob(new ARF_AIEmailClassifier(comm.Id));
    }

    // ===== PHONE MATCHING =====

    @TestVisible
    private static Id matchAccountByPhone(String phoneNumber) {
        if (String.isBlank(phoneNumber)) return null;

        // Strip to last 10 digits for matching
        String digits = phoneNumber.replaceAll('[^0-9]', '');
        String last10 = digits.length() >= 10 ? digits.right(10) : digits;
        String searchPattern = '%' + last10;

        // Try Contact phone fields first
        List<Contact> contacts = [
            SELECT AccountId FROM Contact
            WHERE (Phone LIKE :searchPattern
                   OR MobilePhone LIKE :searchPattern)
            AND AccountId != null
            LIMIT 1
        ];

        if (!contacts.isEmpty()) {
            return contacts[0].AccountId;
        }

        // Try Account phone
        List<Account> accounts = [
            SELECT Id FROM Account
            WHERE Phone LIKE :searchPattern
            LIMIT 1
        ];

        return accounts.isEmpty() ? null : accounts[0].Id;
    }

    // ===== HELPERS =====

    @TestVisible
    private static Map<String, String> parseFormBody(RestRequest req) {
        Map<String, String> params = new Map<String, String>();
        if (req.requestBody == null) return params;

        String body = req.requestBody.toString();
        if (String.isBlank(body)) return params;

        for (String pair : body.split('&')) {
            List<String> keyVal = pair.split('=', 2);
            if (keyVal.size() == 2) {
                String key = EncodingUtil.urlDecode(keyVal[0], 'UTF-8');
                String val = EncodingUtil.urlDecode(keyVal[1], 'UTF-8');
                params.put(key, val);
            }
        }
        return params;
    }
}
