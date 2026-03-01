@RestResource(urlMapping='/arflow/credit/*')
global with sharing class ARF_CreditApplicationResource {

    // ===== GET: Load application by access token =====
    // GET /services/apexrest/arflow/credit/application?token={token}

    @HttpGet
    global static void handleGet() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String token = RestContext.request.params.get('token');

            if (String.isBlank(token)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                    'success' => false,
                    'error' => 'Missing required parameter: token'
                }));
                return;
            }

            List<ARF_Credit_Application__c> apps = [
                SELECT Id, Name, Status__c, Legal_Name__c, DBA_Name__c, Phone__c, Fax__c,
                       Email__c, Website__c, Federal_Tax_ID__c, Business_Type__c,
                       Years_In_Business__c, Date_Established__c, Annual_Revenue__c,
                       Number_Of_Employees__c, Requested_Credit_Limit__c,
                       Billing_Street__c, Billing_City__c, Billing_State__c,
                       Billing_Zip__c, Billing_Country__c,
                       Shipping_Street__c, Shipping_City__c, Shipping_State__c,
                       Shipping_Zip__c, Shipping_Country__c,
                       AP_Contact_Name__c, AP_Contact_Email__c, AP_Contact_Phone__c,
                       DUNS_Number__c, State_Of_Incorporation__c,
                       Signature_Data__c, Signature_Date__c, Signature_Name__c,
                       Signature_Title__c, Terms_Accepted__c, Credit_Auth_Accepted__c,
                       Submitted_Date__c, Access_Token__c, Token_Expiry__c,
                       Account__c
                FROM ARF_Credit_Application__c
                WHERE Access_Token__c = :token
                LIMIT 1
            ];

            if (apps.isEmpty()) {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                    'success' => false,
                    'error' => 'Credit application not found'
                }));
                return;
            }

            ARF_Credit_Application__c app = apps[0];

            // Check token expiry
            if (app.Token_Expiry__c != null && app.Token_Expiry__c < Datetime.now()) {
                res.statusCode = 401;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                    'success' => false,
                    'error' => 'Access token has expired. Please request a new application link.'
                }));
                return;
            }

            // Build response with application + child records
            Map<String, Object> result = buildApplicationResponse(app);
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(result));

        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            }));
        }
    }

    // ===== POST: Route by last URI segment =====
    // POST /services/apexrest/arflow/credit/prospect
    // POST /services/apexrest/arflow/credit/application

    @HttpPost
    global static void handlePost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String uri = req.requestURI;
            String body = req.requestBody != null ? req.requestBody.toString() : '{}';
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);

            Map<String, Object> result;

            if (uri.endsWith('/prospect')) {
                result = createProspect(payload);
            } else if (uri.endsWith('/application')) {
                result = saveApplication(payload);
            } else {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                    'success' => false,
                    'error' => 'Unknown action. Use: prospect, application'
                }));
                return;
            }

            Integer statusCode = result.containsKey('statusCode')
                ? (Integer) result.get('statusCode') : 200;
            result.remove('statusCode');
            res.statusCode = statusCode;
            res.responseBody = Blob.valueOf(JSON.serialize(result));

        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            }));
        }
    }

    // ===== CREATE PROSPECT =====
    // Receives prospect details from external sales system, creates draft application,
    // generates access token, and sends email with application link.

    @TestVisible
    private static Map<String, Object> createProspect(Map<String, Object> payload) {
        String companyName = (String) payload.get('companyName');
        String email = (String) payload.get('email');
        String phone = (String) payload.get('phone');
        String contactName = (String) payload.get('contactName');
        Decimal requestedCreditLimit = payload.get('requestedCreditLimit') != null
            ? Decimal.valueOf(String.valueOf(payload.get('requestedCreditLimit'))) : null;

        if (String.isBlank(companyName) || String.isBlank(email)) {
            Map<String, Object> errResult = new Map<String, Object>{
                'success' => false,
                'error' => 'companyName and email are required',
                'statusCode' => 400
            };
            return errResult;
        }

        // Generate unique access token (UUID)
        String accessToken = generateUUID();

        ARF_Credit_Application__c app = new ARF_Credit_Application__c(
            Legal_Name__c = companyName,
            Email__c = email,
            Phone__c = phone,
            AP_Contact_Name__c = contactName,
            Requested_Credit_Limit__c = requestedCreditLimit,
            Status__c = 'Draft',
            Access_Token__c = accessToken,
            Token_Expiry__c = Datetime.now().addDays(30)
        );
        insert app;

        // Send email with application link
        sendApplicationEmail(email, contactName, companyName, accessToken);

        return new Map<String, Object>{
            'success' => true,
            'applicationId' => app.Id,
            'accessToken' => accessToken
        };
    }

    // ===== SAVE / UPDATE APPLICATION =====
    // Accepts token + step number + step-specific data.
    // Step 1: Company info
    // Step 2: Trade references + bank references
    // Step 3: Personal guarantors
    // Step 4: Tax info
    // Step 5: Submit (signature, terms)

    @TestVisible
    private static Map<String, Object> saveApplication(Map<String, Object> payload) {
        String token = (String) payload.get('token');
        Integer step = payload.get('step') != null
            ? Integer.valueOf(String.valueOf(payload.get('step'))) : null;

        if (String.isBlank(token) || step == null) {
            return new Map<String, Object>{
                'success' => false,
                'error' => 'token and step are required',
                'statusCode' => 400
            };
        }

        // Find the application by token
        List<ARF_Credit_Application__c> apps = [
            SELECT Id, Status__c, Token_Expiry__c
            FROM ARF_Credit_Application__c
            WHERE Access_Token__c = :token
            LIMIT 1
        ];

        if (apps.isEmpty()) {
            return new Map<String, Object>{
                'success' => false,
                'error' => 'Credit application not found',
                'statusCode' => 404
            };
        }

        ARF_Credit_Application__c app = apps[0];

        // Check token expiry
        if (app.Token_Expiry__c != null && app.Token_Expiry__c < Datetime.now()) {
            return new Map<String, Object>{
                'success' => false,
                'error' => 'Access token has expired. Please request a new application link.',
                'statusCode' => 401
            };
        }

        // Check if already submitted
        if (app.Status__c == 'Submitted') {
            return new Map<String, Object>{
                'success' => false,
                'error' => 'This application has already been submitted',
                'statusCode' => 400
            };
        }

        Map<String, Object> data = payload.containsKey('data')
            ? (Map<String, Object>) payload.get('data') : payload;

        switch on step {
            when 1 { saveStep1CompanyInfo(app.Id, data); }
            when 2 { saveStep2References(app.Id, data); }
            when 3 { saveStep3Guarantors(app.Id, data); }
            when 4 { saveStep4TaxInfo(app.Id, data); }
            when 5 { saveStep5Submit(app.Id, data); }
            when else {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'Invalid step. Must be 1-5.',
                    'statusCode' => 400
                };
            }
        }

        return new Map<String, Object>{
            'success' => true,
            'applicationId' => app.Id,
            'step' => step,
            'message' => step == 5 ? 'Application submitted successfully' : 'Step ' + step + ' saved'
        };
    }

    // ===== STEP 1: Company Information =====

    @TestVisible
    private static void saveStep1CompanyInfo(Id appId, Map<String, Object> data) {
        ARF_Credit_Application__c app = new ARF_Credit_Application__c(Id = appId);

        if (data.containsKey('legalName'))          app.Legal_Name__c = (String) data.get('legalName');
        if (data.containsKey('dbaName'))             app.DBA_Name__c = (String) data.get('dbaName');
        if (data.containsKey('phone'))               app.Phone__c = (String) data.get('phone');
        if (data.containsKey('fax'))                 app.Fax__c = (String) data.get('fax');
        if (data.containsKey('email'))               app.Email__c = (String) data.get('email');
        if (data.containsKey('website'))             app.Website__c = (String) data.get('website');
        if (data.containsKey('businessType'))        app.Business_Type__c = (String) data.get('businessType');
        if (data.containsKey('yearsInBusiness'))     app.Years_In_Business__c = toDecimal(data.get('yearsInBusiness'));
        if (data.containsKey('dateEstablished'))     app.Date_Established__c = Date.valueOf((String) data.get('dateEstablished'));
        if (data.containsKey('annualRevenue'))       app.Annual_Revenue__c = toDecimal(data.get('annualRevenue'));
        if (data.containsKey('numberOfEmployees'))   app.Number_Of_Employees__c = toDecimal(data.get('numberOfEmployees'));
        if (data.containsKey('requestedCreditLimit'))app.Requested_Credit_Limit__c = toDecimal(data.get('requestedCreditLimit'));
        if (data.containsKey('stateOfIncorporation'))app.State_Of_Incorporation__c = (String) data.get('stateOfIncorporation');

        // Billing address
        if (data.containsKey('billingStreet'))       app.Billing_Street__c = (String) data.get('billingStreet');
        if (data.containsKey('billingCity'))          app.Billing_City__c = (String) data.get('billingCity');
        if (data.containsKey('billingState'))         app.Billing_State__c = (String) data.get('billingState');
        if (data.containsKey('billingZip'))           app.Billing_Zip__c = (String) data.get('billingZip');
        if (data.containsKey('billingCountry'))       app.Billing_Country__c = (String) data.get('billingCountry');

        // Shipping address
        if (data.containsKey('shippingStreet'))      app.Shipping_Street__c = (String) data.get('shippingStreet');
        if (data.containsKey('shippingCity'))         app.Shipping_City__c = (String) data.get('shippingCity');
        if (data.containsKey('shippingState'))        app.Shipping_State__c = (String) data.get('shippingState');
        if (data.containsKey('shippingZip'))          app.Shipping_Zip__c = (String) data.get('shippingZip');
        if (data.containsKey('shippingCountry'))      app.Shipping_Country__c = (String) data.get('shippingCountry');

        // AP contact
        if (data.containsKey('apContactName'))       app.AP_Contact_Name__c = (String) data.get('apContactName');
        if (data.containsKey('apContactEmail'))      app.AP_Contact_Email__c = (String) data.get('apContactEmail');
        if (data.containsKey('apContactPhone'))      app.AP_Contact_Phone__c = (String) data.get('apContactPhone');

        update app;
    }

    // ===== STEP 2: Trade References + Bank References =====

    @TestVisible
    private static void saveStep2References(Id appId, Map<String, Object> data) {
        // --- Trade References ---
        if (data.containsKey('tradeReferences')) {
            // Delete existing trade refs for this application
            delete [SELECT Id FROM ARF_Trade_Reference__c WHERE Credit_Application__c = :appId];

            List<Object> tradeRefs = (List<Object>) data.get('tradeReferences');
            List<ARF_Trade_Reference__c> newTradeRefs = new List<ARF_Trade_Reference__c>();

            for (Object refObj : tradeRefs) {
                Map<String, Object> ref = (Map<String, Object>) refObj;
                newTradeRefs.add(new ARF_Trade_Reference__c(
                    Credit_Application__c = appId,
                    Company_Name__c = (String) ref.get('companyName'),
                    Contact_Name__c = (String) ref.get('contactName'),
                    Phone__c = (String) ref.get('phone'),
                    Email__c = (String) ref.get('email'),
                    Account_Number__c = (String) ref.get('accountNumber'),
                    Credit_Limit__c = ref.get('creditLimit') != null ? toDecimal(ref.get('creditLimit')) : null,
                    Balance_Owed__c = ref.get('balanceOwed') != null ? toDecimal(ref.get('balanceOwed')) : null
                ));
            }

            if (!newTradeRefs.isEmpty()) {
                insert newTradeRefs;
            }
        }

        // --- Bank References ---
        if (data.containsKey('bankReferences')) {
            // Delete existing bank refs for this application
            delete [SELECT Id FROM ARF_Bank_Reference__c WHERE Credit_Application__c = :appId];

            List<Object> bankRefs = (List<Object>) data.get('bankReferences');
            List<ARF_Bank_Reference__c> newBankRefs = new List<ARF_Bank_Reference__c>();

            for (Object refObj : bankRefs) {
                Map<String, Object> ref = (Map<String, Object>) refObj;
                newBankRefs.add(new ARF_Bank_Reference__c(
                    Credit_Application__c = appId,
                    Bank_Name__c = (String) ref.get('bankName'),
                    Branch__c = (String) ref.get('branch'),
                    Contact_Name__c = (String) ref.get('contactName'),
                    Phone__c = (String) ref.get('phone'),
                    Account_Type__c = (String) ref.get('accountType'),
                    Account_Number__c = (String) ref.get('accountNumber'),
                    Routing_Number__c = (String) ref.get('routingNumber')
                ));
            }

            if (!newBankRefs.isEmpty()) {
                insert newBankRefs;
            }
        }
    }

    // ===== STEP 3: Personal Guarantors =====

    @TestVisible
    private static void saveStep3Guarantors(Id appId, Map<String, Object> data) {
        if (!data.containsKey('guarantors')) return;

        // Delete existing guarantors for this application
        delete [SELECT Id FROM ARF_Personal_Guarantor__c WHERE Credit_Application__c = :appId];

        List<Object> guarantors = (List<Object>) data.get('guarantors');
        List<ARF_Personal_Guarantor__c> newGuarantors = new List<ARF_Personal_Guarantor__c>();

        for (Object gObj : guarantors) {
            Map<String, Object> g = (Map<String, Object>) gObj;
            newGuarantors.add(new ARF_Personal_Guarantor__c(
                Credit_Application__c = appId,
                First_Name__c = (String) g.get('firstName'),
                Last_Name__c = (String) g.get('lastName'),
                SSN__c = (String) g.get('ssn'),
                Date_Of_Birth__c = g.get('dateOfBirth') != null ? Date.valueOf((String) g.get('dateOfBirth')) : null,
                Street__c = (String) g.get('street'),
                City__c = (String) g.get('city'),
                State__c = (String) g.get('state'),
                Zip__c = (String) g.get('zip'),
                Phone__c = (String) g.get('phone'),
                Email__c = (String) g.get('email'),
                Ownership_Percentage__c = g.get('ownershipPercentage') != null
                    ? toDecimal(g.get('ownershipPercentage')) : null
            ));
        }

        if (!newGuarantors.isEmpty()) {
            insert newGuarantors;
        }
    }

    // ===== STEP 4: Tax Info =====

    @TestVisible
    private static void saveStep4TaxInfo(Id appId, Map<String, Object> data) {
        ARF_Credit_Application__c app = new ARF_Credit_Application__c(Id = appId);

        if (data.containsKey('federalTaxId'))        app.Federal_Tax_ID__c = (String) data.get('federalTaxId');
        if (data.containsKey('dunsNumber'))           app.DUNS_Number__c = (String) data.get('dunsNumber');
        if (data.containsKey('stateOfIncorporation')) app.State_Of_Incorporation__c = (String) data.get('stateOfIncorporation');

        update app;
    }

    // ===== STEP 5: Submit Application =====

    @TestVisible
    private static void saveStep5Submit(Id appId, Map<String, Object> data) {
        ARF_Credit_Application__c app = new ARF_Credit_Application__c(Id = appId);

        if (data.containsKey('signatureData'))       app.Signature_Data__c = (String) data.get('signatureData');
        if (data.containsKey('signatureName'))       app.Signature_Name__c = (String) data.get('signatureName');
        if (data.containsKey('signatureTitle'))      app.Signature_Title__c = (String) data.get('signatureTitle');
        if (data.containsKey('signatureDate'))       app.Signature_Date__c = Datetime.valueOf((String) data.get('signatureDate'));
        if (data.containsKey('termsAccepted'))       app.Terms_Accepted__c = (Boolean) data.get('termsAccepted');
        if (data.containsKey('creditAuthAccepted'))  app.Credit_Auth_Accepted__c = (Boolean) data.get('creditAuthAccepted');

        app.Status__c = 'Submitted';
        app.Submitted_Date__c = Datetime.now();

        update app;
    }

    // ===== BUILD APPLICATION RESPONSE (for GET) =====

    @TestVisible
    private static Map<String, Object> buildApplicationResponse(ARF_Credit_Application__c app) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('success', true);

        // Application fields
        Map<String, Object> appData = new Map<String, Object>{
            'id' => app.Id,
            'name' => app.Name,
            'status' => app.Status__c,
            'legalName' => app.Legal_Name__c,
            'dbaName' => app.DBA_Name__c,
            'phone' => app.Phone__c,
            'fax' => app.Fax__c,
            'email' => app.Email__c,
            'website' => app.Website__c,
            'federalTaxId' => app.Federal_Tax_ID__c,
            'businessType' => app.Business_Type__c,
            'yearsInBusiness' => app.Years_In_Business__c,
            'dateEstablished' => app.Date_Established__c,
            'annualRevenue' => app.Annual_Revenue__c,
            'numberOfEmployees' => app.Number_Of_Employees__c,
            'requestedCreditLimit' => app.Requested_Credit_Limit__c,
            'dunsNumber' => app.DUNS_Number__c,
            'stateOfIncorporation' => app.State_Of_Incorporation__c,
            'billingStreet' => app.Billing_Street__c,
            'billingCity' => app.Billing_City__c,
            'billingState' => app.Billing_State__c,
            'billingZip' => app.Billing_Zip__c,
            'billingCountry' => app.Billing_Country__c,
            'shippingStreet' => app.Shipping_Street__c,
            'shippingCity' => app.Shipping_City__c,
            'shippingState' => app.Shipping_State__c,
            'shippingZip' => app.Shipping_Zip__c,
            'shippingCountry' => app.Shipping_Country__c,
            'apContactName' => app.AP_Contact_Name__c,
            'apContactEmail' => app.AP_Contact_Email__c,
            'apContactPhone' => app.AP_Contact_Phone__c,
            'signatureData' => app.Signature_Data__c,
            'signatureDate' => app.Signature_Date__c,
            'signatureName' => app.Signature_Name__c,
            'signatureTitle' => app.Signature_Title__c,
            'termsAccepted' => app.Terms_Accepted__c,
            'creditAuthAccepted' => app.Credit_Auth_Accepted__c,
            'submittedDate' => app.Submitted_Date__c
        };
        result.put('application', appData);

        // Child records: Applicants
        List<Map<String, Object>> applicantList = new List<Map<String, Object>>();
        for (ARF_Credit_Applicant__c a : [
            SELECT Id, First_Name__c, Last_Name__c, Title__c, Email__c,
                   Phone__c, Ownership_Percentage__c, Is_Primary__c
            FROM ARF_Credit_Applicant__c
            WHERE Credit_Application__c = :app.Id
            ORDER BY Is_Primary__c DESC, First_Name__c ASC
        ]) {
            applicantList.add(new Map<String, Object>{
                'id' => a.Id,
                'firstName' => a.First_Name__c,
                'lastName' => a.Last_Name__c,
                'title' => a.Title__c,
                'email' => a.Email__c,
                'phone' => a.Phone__c,
                'ownershipPercentage' => a.Ownership_Percentage__c,
                'isPrimary' => a.Is_Primary__c
            });
        }
        result.put('applicants', applicantList);

        // Child records: Trade References
        List<Map<String, Object>> tradeRefList = new List<Map<String, Object>>();
        for (ARF_Trade_Reference__c t : [
            SELECT Id, Company_Name__c, Contact_Name__c, Phone__c, Email__c,
                   Account_Number__c, Credit_Limit__c, Balance_Owed__c
            FROM ARF_Trade_Reference__c
            WHERE Credit_Application__c = :app.Id
            ORDER BY Company_Name__c ASC
        ]) {
            tradeRefList.add(new Map<String, Object>{
                'id' => t.Id,
                'companyName' => t.Company_Name__c,
                'contactName' => t.Contact_Name__c,
                'phone' => t.Phone__c,
                'email' => t.Email__c,
                'accountNumber' => t.Account_Number__c,
                'creditLimit' => t.Credit_Limit__c,
                'balanceOwed' => t.Balance_Owed__c
            });
        }
        result.put('tradeReferences', tradeRefList);

        // Child records: Bank References
        List<Map<String, Object>> bankRefList = new List<Map<String, Object>>();
        for (ARF_Bank_Reference__c b : [
            SELECT Id, Bank_Name__c, Branch__c, Contact_Name__c, Phone__c,
                   Account_Type__c, Account_Number__c, Routing_Number__c
            FROM ARF_Bank_Reference__c
            WHERE Credit_Application__c = :app.Id
            ORDER BY Bank_Name__c ASC
        ]) {
            bankRefList.add(new Map<String, Object>{
                'id' => b.Id,
                'bankName' => b.Bank_Name__c,
                'branch' => b.Branch__c,
                'contactName' => b.Contact_Name__c,
                'phone' => b.Phone__c,
                'accountType' => b.Account_Type__c,
                'accountNumber' => b.Account_Number__c,
                'routingNumber' => b.Routing_Number__c
            });
        }
        result.put('bankReferences', bankRefList);

        // Child records: Personal Guarantors
        List<Map<String, Object>> guarantorList = new List<Map<String, Object>>();
        for (ARF_Personal_Guarantor__c g : [
            SELECT Id, First_Name__c, Last_Name__c, SSN__c, Date_Of_Birth__c,
                   Street__c, City__c, State__c, Zip__c, Phone__c, Email__c,
                   Ownership_Percentage__c
            FROM ARF_Personal_Guarantor__c
            WHERE Credit_Application__c = :app.Id
            ORDER BY Last_Name__c ASC
        ]) {
            guarantorList.add(new Map<String, Object>{
                'id' => g.Id,
                'firstName' => g.First_Name__c,
                'lastName' => g.Last_Name__c,
                'ssn' => g.SSN__c,
                'dateOfBirth' => g.Date_Of_Birth__c,
                'street' => g.Street__c,
                'city' => g.City__c,
                'state' => g.State__c,
                'zip' => g.Zip__c,
                'phone' => g.Phone__c,
                'email' => g.Email__c,
                'ownershipPercentage' => g.Ownership_Percentage__c
            });
        }
        result.put('guarantors', guarantorList);

        return result;
    }

    // ===== SEND APPLICATION EMAIL =====

    @TestVisible
    private static void sendApplicationEmail(String toEmail, String contactName, String companyName, String accessToken) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        String applicationLink = baseUrl + '/credit-application?token=' + accessToken;

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ toEmail });
        mail.setSubject('Credit Application — ' + companyName);
        mail.setSaveAsActivity(false);
        mail.setHtmlBody(
            '<p>Hello ' + (String.isNotBlank(contactName) ? contactName : '') + ',</p>' +
            '<p>Thank you for your interest. Please complete your credit application using the link below:</p>' +
            '<p><a href="' + applicationLink + '">' + applicationLink + '</a></p>' +
            '<p>This link will expire in 30 days.</p>' +
            '<p>If you have any questions, please do not hesitate to contact us.</p>' +
            '<p>Best regards,<br/>Accounts Receivable Team</p>'
        );

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            // Log but do not fail the API call if email send fails
            System.debug(LoggingLevel.ERROR, 'Failed to send credit application email: ' + e.getMessage());
        }
    }

    // ===== UTILITY: Generate UUID =====

    @TestVisible
    private static String generateUUID() {
        Blob randomBytes = Crypto.generateAesKey(128);
        String hex = EncodingUtil.convertToHex(randomBytes);
        return hex.substring(0, 8) + '-' +
               hex.substring(8, 12) + '-' +
               hex.substring(12, 16) + '-' +
               hex.substring(16, 20) + '-' +
               hex.substring(20, 32);
    }

    // ===== UTILITY: Safe Decimal conversion =====

    @TestVisible
    private static Decimal toDecimal(Object val) {
        if (val == null) return null;
        return Decimal.valueOf(String.valueOf(val));
    }
}
