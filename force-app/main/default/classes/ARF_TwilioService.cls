public class ARF_TwilioService {

    private static final String TWILIO_API_BASE = 'https://api.twilio.com/2010-04-01/Accounts/';

    // ===== CONFIGURATION =====

    public static ARF_Twilio_Config__c getConfig() {
        return ARF_Twilio_Config__c.getOrgDefaults();
    }

    public static Boolean isConfigured() {
        ARF_Twilio_Config__c config = getConfig();
        return config != null &&
               String.isNotBlank(config.Account_SID__c) &&
               String.isNotBlank(config.Auth_Token__c) &&
               String.isNotBlank(config.Phone_Number__c);
    }

    // ===== SEND SMS =====

    public static String sendSms(String toNumber, String messageBody) {
        ARF_Twilio_Config__c config = getConfig();
        if (!isConfigured()) {
            throw new TwilioException('Twilio not configured. Add credentials in Setup > Custom Settings > ARF Twilio Config.');
        }

        String endpoint = TWILIO_API_BASE + config.Account_SID__c + '/Messages.json';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setHeader('Authorization', buildAuthHeader(config));

        String body = 'To=' + EncodingUtil.urlEncode(toNumber, 'UTF-8') +
                      '&From=' + EncodingUtil.urlEncode(config.Phone_Number__c, 'UTF-8') +
                      '&Body=' + EncodingUtil.urlEncode(messageBody, 'UTF-8');

        // Add status callback if configured
        if (String.isNotBlank(config.Callback_Base_URL__c)) {
            String callbackUrl = config.Callback_Base_URL__c + '/services/apexrest/arflow/twilio/sms';
            body += '&StatusCallback=' + EncodingUtil.urlEncode(callbackUrl, 'UTF-8');
        }

        req.setBody(body);
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) responseBody.get('sid');
        } else {
            throw new TwilioException('SMS failed: ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }

    // ===== INITIATE CALL =====

    public static String initiateCall(String toNumber) {
        // Get collector's phone from current user
        String collectorPhone = getCollectorPhone();
        return initiateCallBridge(collectorPhone, toNumber);
    }

    // Click-to-Dial: Calls the collector first, then bridges to customer
    public static String initiateCallBridge(String collectorPhone, String customerPhone) {
        ARF_Twilio_Config__c config = getConfig();
        if (!isConfigured()) {
            throw new TwilioException('Twilio not configured. Add credentials in Setup > Custom Settings > ARF Twilio Config.');
        }

        if (String.isBlank(collectorPhone)) {
            throw new TwilioException('Your phone number is not set. Go to your User record and add your phone number in the Phone field, or add it in the Callback Base URL field of ARF_Twilio_Config__c.');
        }

        String endpoint = TWILIO_API_BASE + config.Account_SID__c + '/Calls.json';

        String callbackBase = String.isNotBlank(config.Callback_Base_URL__c)
            ? config.Callback_Base_URL__c : '';
        String statusUrl = String.isNotBlank(callbackBase)
            ? callbackBase + '/services/apexrest/arflow/twilio/voice/status' : '';

        // TwiML: Say a brief message, then Dial the customer with recording
        String twiml = '<Response>' +
            '<Say>Connecting you now. This call will be recorded.</Say>' +
            '<Dial record="record-from-answer-dual" timeout="30">' +
            '<Number>' + customerPhone + '</Number>' +
            '</Dial>' +
            '</Response>';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setHeader('Authorization', buildAuthHeader(config));

        // Call the COLLECTOR first — when they pick up, TwiML dials the CUSTOMER
        String body = 'To=' + EncodingUtil.urlEncode(collectorPhone, 'UTF-8') +
                      '&From=' + EncodingUtil.urlEncode(config.Phone_Number__c, 'UTF-8') +
                      '&Twiml=' + EncodingUtil.urlEncode(twiml, 'UTF-8');

        if (String.isNotBlank(statusUrl)) {
            body += '&StatusCallback=' + EncodingUtil.urlEncode(statusUrl, 'UTF-8') +
                    '&StatusCallbackEvent=' + EncodingUtil.urlEncode('completed', 'UTF-8');
        }

        req.setBody(body);
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) responseBody.get('sid');
        } else {
            throw new TwilioException('Call failed: ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }

    // Simple direct call — Twilio calls the number, plays message, records
    public static String initiateDirectCall(String toNumber) {
        ARF_Twilio_Config__c config = getConfig();
        if (!isConfigured()) {
            throw new TwilioException('Twilio not configured.');
        }

        String endpoint = TWILIO_API_BASE + config.Account_SID__c + '/Calls.json';

        // TwiML: just connect the call with recording
        String twiml = '<Response>' +
            '<Say voice="alice">Hello, this is a call from the accounts receivable team regarding your outstanding invoices. Please hold while we connect you.</Say>' +
            '<Pause length="60"/>' +
            '</Response>';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setHeader('Authorization', buildAuthHeader(config));

        String body = 'To=' + EncodingUtil.urlEncode(toNumber, 'UTF-8') +
                      '&From=' + EncodingUtil.urlEncode(config.Phone_Number__c, 'UTF-8') +
                      '&Twiml=' + EncodingUtil.urlEncode(twiml, 'UTF-8') +
                      '&Record=true';

        req.setBody(body);
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) responseBody.get('sid');
        } else {
            throw new TwilioException('Call failed: ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }

    // Get current user's phone number for click-to-dial
    private static String getCollectorPhone() {
        User currentUser = [SELECT Phone, MobilePhone FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (String.isNotBlank(currentUser.MobilePhone)) return currentUser.MobilePhone;
        if (String.isNotBlank(currentUser.Phone)) return currentUser.Phone;
        // Fallback: check if Callback_Base_URL has a phone (for testing)
        ARF_Twilio_Config__c config = getConfig();
        if (String.isNotBlank(config.Callback_Base_URL__c) && config.Callback_Base_URL__c.startsWith('+')) {
            return config.Callback_Base_URL__c;
        }
        return null;
    }

    // ===== SEND SMS + CREATE COMMUNICATION =====

    public static Id sendSmsWithRecord(String toNumber, String messageBody, Id accountId, Id contactId) {
        String smsSid = null;
        String status = 'Sent';

        try {
            smsSid = sendSms(toNumber, messageBody);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ARF_TwilioService SMS error: ' + e.getMessage());
            status = 'Failed';
        }

        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = accountId,
            Contact__c = contactId,
            Channel__c = 'SMS',
            Direction__c = 'Outbound',
            Subject__c = 'SMS: ' + (messageBody != null && messageBody.length() > 50
                ? messageBody.substring(0, 50) + '...' : messageBody),
            Body__c = messageBody,
            To_Address__c = toNumber,
            From_Address__c = getConfig().Phone_Number__c,
            Status__c = status,
            Sent_Date__c = Datetime.now(),
            Thread_ID__c = smsSid
        );
        insert comm;
        return comm.Id;
    }

    // ===== INITIATE CALL + CREATE COMMUNICATION =====

    public static Id initiateCallWithRecord(String toNumber, Id accountId, Id contactId) {
        String callSid = null;
        String status = 'Draft';

        try {
            callSid = initiateCall(toNumber);
            status = 'In Progress';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ARF_TwilioService Call error: ' + e.getMessage());
            status = 'Failed';
        }

        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = accountId,
            Contact__c = contactId,
            Channel__c = 'Phone',
            Direction__c = 'Outbound',
            Subject__c = 'Phone Call to ' + toNumber,
            Body__c = 'Call initiated via Twilio. Transcript will be recorded automatically.',
            To_Address__c = toNumber,
            From_Address__c = isConfigured() ? getConfig().Phone_Number__c : null,
            Status__c = status,
            Sent_Date__c = Datetime.now(),
            Thread_ID__c = callSid
        );
        insert comm;
        return comm.Id;
    }

    // ===== HELPERS =====

    @TestVisible
    private static String buildAuthHeader(ARF_Twilio_Config__c config) {
        return 'Basic ' + EncodingUtil.base64Encode(
            Blob.valueOf(config.Account_SID__c + ':' + config.Auth_Token__c)
        );
    }

    public class TwilioException extends Exception {}
}
