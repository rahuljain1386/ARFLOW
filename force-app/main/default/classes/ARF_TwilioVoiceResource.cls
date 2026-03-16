@RestResource(urlMapping='/arflow/twilio/voice/outbound')
global without sharing class ARF_TwilioVoiceResource {

    @HttpPost
    global static void handleOutboundCall() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        // Twilio sends the "To" parameter that we passed from the browser
        String toNumber = req.params.get('To');
        String fromNumber = req.params.get('From');

        // Get our Twilio phone number
        ARF_Twilio_Config__c config = ARF_Twilio_Config__c.getOrgDefaults();
        String twilioNumber = config != null && config.Phone_Number__c != null ? config.Phone_Number__c : '+13503532311';

        String twiml;
        if (String.isNotBlank(toNumber) && toNumber.startsWith('+')) {
            // Dial the customer number with recording
            twiml = '<?xml version="1.0" encoding="UTF-8"?>' +
                '<Response>' +
                '<Dial callerId="' + twilioNumber + '" record="record-from-answer-dual">' +
                '<Number>' + toNumber + '</Number>' +
                '</Dial>' +
                '</Response>';
        } else {
            twiml = '<?xml version="1.0" encoding="UTF-8"?>' +
                '<Response><Say>No phone number provided.</Say></Response>';
        }

        res.statusCode = 200;
        res.addHeader('Content-Type', 'text/xml');
        res.responseBody = Blob.valueOf(twiml);
    }
}
