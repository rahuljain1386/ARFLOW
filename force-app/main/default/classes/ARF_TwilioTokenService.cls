public with sharing class ARF_TwilioTokenService {

    @AuraEnabled
    public static Map<String, String> getVoiceToken() {
        ARF_Twilio_Config__c config = ARF_Twilio_Config__c.getOrgDefaults();

        if (config == null || String.isBlank(config.Account_SID__c) || String.isBlank(config.Auth_Token__c)) {
            throw new AuraHandledException('Twilio is not configured.');
        }

        if (String.isBlank(config.TwiML_App_SID__c)) {
            throw new AuraHandledException('TwiML App SID is not configured. Please set it in ARF Twilio Config custom setting.');
        }

        String accountSid = config.Account_SID__c;
        String apiKey = config.Account_SID__c; // Using Account SID as API Key for simplicity
        String apiSecret = config.Auth_Token__c; // Using Auth Token as API Secret
        String identity = UserInfo.getUserId().left(15); // Unique identity for this user
        String twimlAppSid = config.TwiML_App_SID__c;

        // Build JWT manually
        // Header
        Map<String, Object> header = new Map<String, Object>{
            'typ' => 'JWT',
            'alg' => 'HS256',
            'cty' => 'twilio-fpa;v=1'
        };

        Long now = DateTime.now().getTime() / 1000;
        Long exp = now + 3600;

        // Voice grant
        Map<String, Object> outgoing = new Map<String, Object>{
            'application_sid' => twimlAppSid
        };
        Map<String, Object> voiceGrant = new Map<String, Object>{
            'outgoing' => outgoing,
            'incoming' => new Map<String, Object>{ 'allow' => false }
        };

        Map<String, Object> grants = new Map<String, Object>{
            'identity' => identity,
            'voice' => voiceGrant
        };

        Map<String, Object> payload = new Map<String, Object>{
            'jti' => apiKey + '-' + String.valueOf(now),
            'iss' => apiKey,
            'sub' => accountSid,
            'nbf' => now,
            'exp' => exp,
            'grants' => grants
        };

        String headerEncoded = base64UrlEncode(Blob.valueOf(JSON.serialize(header)));
        String payloadEncoded = base64UrlEncode(Blob.valueOf(JSON.serialize(payload)));

        String signatureInput = headerEncoded + '.' + payloadEncoded;
        Blob signatureBlob = Crypto.generateMac('HmacSHA256', Blob.valueOf(signatureInput), Blob.valueOf(apiSecret));
        String signature = base64UrlEncode(signatureBlob);

        String token = headerEncoded + '.' + payloadEncoded + '.' + signature;

        Map<String, String> result = new Map<String, String>();
        result.put('token', token);
        result.put('identity', identity);
        return result;
    }

    private static String base64UrlEncode(Blob input) {
        String output = EncodingUtil.base64Encode(input);
        output = output.replace('+', '-');
        output = output.replace('/', '_');
        output = output.replace('=', '');
        return output;
    }
}
