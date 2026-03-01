@isTest
private class ARF_CreditApplicationResourceTest {

    // ===== Helper: create a draft application with a known token =====
    private static ARF_Credit_Application__c createTestApplication(String token, Datetime tokenExpiry) {
        ARF_Credit_Application__c app = new ARF_Credit_Application__c(
            Legal_Name__c = 'Test Company LLC',
            Email__c = 'ap@testcompany.com',
            Phone__c = '555-0100',
            AP_Contact_Name__c = 'Jane Doe',
            Status__c = 'Draft',
            Access_Token__c = token,
            Token_Expiry__c = tokenExpiry
        );
        insert app;
        return app;
    }

    // ───────────────────────────────────────────────────────────────
    // 1. POST /prospect — happy path
    // ───────────────────────────────────────────────────────────────
    @isTest
    static void testCreateProspect() {
        Map<String, Object> payload = new Map<String, Object>{
            'companyName' => 'Acme Corp',
            'email' => 'ap@acmecorp.com',
            'phone' => '555-1234',
            'contactName' => 'John Smith'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/credit/prospect';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_CreditApplicationResource.handlePost();
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'Expected 200 for valid prospect creation');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(true, body.get('success'));
        System.assertNotEquals(null, body.get('applicationId'), 'applicationId should be returned');
        System.assertNotEquals(null, body.get('accessToken'), 'accessToken should be returned');

        // Verify the record was created correctly
        ARF_Credit_Application__c app = [
            SELECT Legal_Name__c, Email__c, Phone__c, AP_Contact_Name__c, Status__c, Access_Token__c
            FROM ARF_Credit_Application__c
            WHERE Id = :(String) body.get('applicationId')
        ];
        System.assertEquals('Acme Corp', app.Legal_Name__c);
        System.assertEquals('ap@acmecorp.com', app.Email__c);
        System.assertEquals('Draft', app.Status__c);
        System.assertNotEquals(null, app.Access_Token__c);
    }

    // ───────────────────────────────────────────────────────────────
    // 2. POST /prospect — missing required fields
    // ───────────────────────────────────────────────────────────────
    @isTest
    static void testCreateProspect_MissingFields() {
        Map<String, Object> payload = new Map<String, Object>();

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/credit/prospect';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_CreditApplicationResource.handlePost();
        Test.stopTest();

        System.assertEquals(400, res.statusCode, 'Expected 400 for missing required fields');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false, body.get('success'));
    }

    // ───────────────────────────────────────────────────────────────
    // 3. GET /application?token=... — valid token
    // ───────────────────────────────────────────────────────────────
    @isTest
    static void testGetApplication_ValidToken() {
        String testToken = 'valid-test-token-1234';
        ARF_Credit_Application__c app = createTestApplication(testToken, Datetime.now().addDays(30));

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/credit/application';
        req.httpMethod = 'GET';
        req.params.put('token', testToken);
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_CreditApplicationResource.handleGet();
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'Expected 200 for valid token');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(true, body.get('success'));
        System.assertNotEquals(null, body.get('application'), 'Response should contain application data');

        Map<String, Object> appData = (Map<String, Object>) body.get('application');
        System.assertEquals('Test Company LLC', appData.get('legalName'));
        System.assertEquals('Draft', appData.get('status'));
    }

    // ───────────────────────────────────────────────────────────────
    // 4. GET /application?token=... — expired token
    // ───────────────────────────────────────────────────────────────
    @isTest
    static void testGetApplication_ExpiredToken() {
        String testToken = 'expired-test-token-5678';
        createTestApplication(testToken, Datetime.now().addDays(-1));

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/credit/application';
        req.httpMethod = 'GET';
        req.params.put('token', testToken);
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_CreditApplicationResource.handleGet();
        Test.stopTest();

        System.assertEquals(401, res.statusCode, 'Expected 401 for expired token');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false, body.get('success'));
    }

    // ───────────────────────────────────────────────────────────────
    // 5. GET /application?token=... — not found
    // ───────────────────────────────────────────────────────────────
    @isTest
    static void testGetApplication_NotFound() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/credit/application';
        req.httpMethod = 'GET';
        req.params.put('token', 'nonexistent-random-token-xyz');
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_CreditApplicationResource.handleGet();
        Test.stopTest();

        System.assertEquals(404, res.statusCode, 'Expected 404 for unknown token');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false, body.get('success'));
    }

    // ───────────────────────────────────────────────────────────────
    // 6. POST /application — save step 1 (company info)
    // ───────────────────────────────────────────────────────────────
    @isTest
    static void testSaveStep1() {
        String testToken = 'step1-test-token-0001';
        ARF_Credit_Application__c app = createTestApplication(testToken, Datetime.now().addDays(30));

        Map<String, Object> data = new Map<String, Object>{
            'legalName' => 'Updated Company Name',
            'dbaName' => 'UCN Inc',
            'businessType' => 'Corporation',
            'yearsInBusiness' => 10,
            'annualRevenue' => 5000000,
            'requestedCreditLimit' => 100000,
            'billingStreet' => '123 Main St',
            'billingCity' => 'Springfield',
            'billingState' => 'IL',
            'billingZip' => '62701',
            'billingCountry' => 'US',
            'apContactName' => 'Jane Doe',
            'apContactEmail' => 'jane@updated.com',
            'apContactPhone' => '555-9999'
        };

        Map<String, Object> payload = new Map<String, Object>{
            'token' => testToken,
            'step' => 1,
            'data' => data
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/credit/application';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_CreditApplicationResource.handlePost();
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'Expected 200 for step 1 save');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(true, body.get('success'));

        // Verify the record was updated
        ARF_Credit_Application__c updated = [
            SELECT Legal_Name__c, DBA_Name__c, Business_Type__c, Billing_City__c, AP_Contact_Email__c
            FROM ARF_Credit_Application__c
            WHERE Id = :app.Id
        ];
        System.assertEquals('Updated Company Name', updated.Legal_Name__c);
        System.assertEquals('UCN Inc', updated.DBA_Name__c);
        System.assertEquals('Corporation', updated.Business_Type__c);
        System.assertEquals('Springfield', updated.Billing_City__c);
        System.assertEquals('jane@updated.com', updated.AP_Contact_Email__c);
    }

    // ───────────────────────────────────────────────────────────────
    // 7. POST /application — save step 5 (submit)
    // ───────────────────────────────────────────────────────────────
    @isTest
    static void testSaveStep5_Submit() {
        String testToken = 'step5-test-token-0005';
        ARF_Credit_Application__c app = createTestApplication(testToken, Datetime.now().addDays(30));

        Map<String, Object> data = new Map<String, Object>{
            'signatureData' => 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg...',
            'signatureName' => 'Jane Doe',
            'signatureTitle' => 'CFO',
            'signatureDate' => String.valueOf(Datetime.now()),
            'termsAccepted' => true,
            'creditAuthAccepted' => true
        };

        Map<String, Object> payload = new Map<String, Object>{
            'token' => testToken,
            'step' => 5,
            'data' => data
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/credit/application';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_CreditApplicationResource.handlePost();
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'Expected 200 for step 5 submit');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(true, body.get('success'));
        System.assertEquals('Application submitted successfully', body.get('message'));

        // Verify the application is now Submitted
        ARF_Credit_Application__c updated = [
            SELECT Status__c, Signature_Name__c, Terms_Accepted__c, Submitted_Date__c
            FROM ARF_Credit_Application__c
            WHERE Id = :app.Id
        ];
        System.assertEquals('Submitted', updated.Status__c);
        System.assertEquals('Jane Doe', updated.Signature_Name__c);
        System.assertEquals(true, updated.Terms_Accepted__c);
        System.assertNotEquals(null, updated.Submitted_Date__c, 'Submitted_Date__c should be set');
    }

    // ───────────────────────────────────────────────────────────────
    // 8. POST /unknown-action — bad route
    // ───────────────────────────────────────────────────────────────
    @isTest
    static void testUnknownAction() {
        Map<String, Object> payload = new Map<String, Object>{
            'foo' => 'bar'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/arflow/credit/unknown-action';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ARF_CreditApplicationResource.handlePost();
        Test.stopTest();

        System.assertEquals(400, res.statusCode, 'Expected 400 for unknown action');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false, body.get('success'));
    }
}
