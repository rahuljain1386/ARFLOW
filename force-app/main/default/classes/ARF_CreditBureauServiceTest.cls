@isTest
private class ARF_CreditBureauServiceTest {

    @TestSetup
    static void setupTestData() {
        ARF_Credit_Application__c app = new ARF_Credit_Application__c(
            Status__c = 'Submitted',
            Legal_Name__c = 'Bureau Test Corp',
            Years_In_Business__c = 10,
            Annual_Revenue__c = 5000000,
            Requested_Credit_Limit__c = 200000,
            Federal_Tax_ID__c = '12-3456789',
            DUNS_Number__c = '123456789',
            Billing_Street__c = '100 Main St',
            Billing_City__c = 'New York',
            Billing_State__c = 'NY',
            Billing_Zip__c = '10001',
            Billing_Country__c = 'US',
            AP_Contact_Name__c = 'AP Team',
            Email__c = 'bureau@test.com',
            Phone__c = '555-100-2000',
            Access_Token__c = 'bureau-test-token-001',
            Token_Expiry__c = Datetime.now().addDays(30)
        );
        insert app;
    }

    private static ARF_Credit_Application__c getTestApp() {
        return [
            SELECT Id, Legal_Name__c, DUNS_Number__c, Federal_Tax_ID__c,
                   Billing_Street__c, Billing_City__c, Billing_State__c,
                   Billing_Zip__c, Billing_Country__c
            FROM ARF_Credit_Application__c
            WHERE Access_Token__c = 'bureau-test-token-001'
            LIMIT 1
        ];
    }

    // ===== Mock Report Tests =====

    @isTest
    static void testPullReport_MockProvider() {
        ARF_Credit_Application__c app = getTestApp();

        // No config set — defaults to Mock/Sandbox
        Test.startTest();
        ARF_CreditBureauService.CreditReport report = ARF_CreditBureauService.pullReport(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, report, 'Report should not be null');
        System.assertEquals('Mock', report.provider, 'Provider should be Mock');
        System.assertEquals('Bureau Test Corp', report.companyName, 'Company name should match');
        System.assertNotEquals(null, report.paydexScore, 'Paydex score should be populated');
        System.assert(report.paydexScore >= 40 && report.paydexScore <= 94,
            'Paydex should be in range 40-94, got: ' + report.paydexScore);
        System.assertNotEquals(null, report.financialStressScore, 'Financial stress score should be populated');
        System.assertNotEquals(null, report.overallScore, 'Overall score should be populated');
        System.assertNotEquals(null, report.riskRating, 'Risk rating should be populated');
        System.assertNotEquals(null, report.annualRevenue, 'Annual revenue should be populated');
        System.assertNotEquals(null, report.employeeCount, 'Employee count should be populated');
        System.assertNotEquals(null, report.summary, 'Summary should be populated');
        System.assertNotEquals(null, report.rawResponseJson, 'Raw response should be populated');
        System.assertNotEquals(null, report.creditCheckId, 'Credit check ID should be populated');

        // Verify credit check record was persisted
        List<ARF_Credit_Check__c> checks = [
            SELECT Id, Agency__c, Status__c, Score__c, Rating__c, Report_Date__c,
                   Paydex_Score__c, Financial_Stress_Score__c
            FROM ARF_Credit_Check__c
            WHERE Credit_Application__c = :app.Id
        ];
        System.assertEquals(1, checks.size(), 'Should have 1 credit check record');
        System.assertEquals('Mock', checks[0].Agency__c, 'Agency should be Mock');
        System.assertEquals('Completed', checks[0].Status__c, 'Status should be Completed');
        System.assertEquals(Date.today(), checks[0].Report_Date__c, 'Report date should be today');
        System.assertEquals(report.overallScore, checks[0].Score__c.intValue(), 'Score should match');
        System.assertEquals(report.riskRating, checks[0].Rating__c, 'Rating should match');
    }

    @isTest
    static void testMockReport_Consistency() {
        ARF_Credit_Application__c app = getTestApp();

        // Pull two reports — mock data should be consistent (same hash)
        ARF_CreditBureauService.CreditReport report1 = ARF_CreditBureauService.generateMockReport(app);
        ARF_CreditBureauService.CreditReport report2 = ARF_CreditBureauService.generateMockReport(app);

        System.assertEquals(report1.paydexScore, report2.paydexScore, 'Paydex should be consistent');
        System.assertEquals(report1.financialStressScore, report2.financialStressScore, 'FSS should be consistent');
        System.assertEquals(report1.overallScore, report2.overallScore, 'Overall score should be consistent');
        System.assertEquals(report1.riskRating, report2.riskRating, 'Risk rating should be consistent');
        System.assertEquals(report1.annualRevenue, report2.annualRevenue, 'Revenue should be consistent');
        System.assertEquals(report1.employeeCount, report2.employeeCount, 'Employee count should be consistent');
    }

    @isTest
    static void testMockReport_DifferentCompanies() {
        // Two different companies should get different data
        ARF_Credit_Application__c app1 = new ARF_Credit_Application__c(
            Legal_Name__c = 'Alpha Corp',
            Status__c = 'Submitted',
            Email__c = 'alpha@test.com',
            Phone__c = '555-000-0001',
            Access_Token__c = 'alpha-token',
            Token_Expiry__c = Datetime.now().addDays(30)
        );
        ARF_Credit_Application__c app2 = new ARF_Credit_Application__c(
            Legal_Name__c = 'Zeta Industries',
            Status__c = 'Submitted',
            Email__c = 'zeta@test.com',
            Phone__c = '555-000-0002',
            Access_Token__c = 'zeta-token',
            Token_Expiry__c = Datetime.now().addDays(30)
        );
        insert new List<ARF_Credit_Application__c>{ app1, app2 };

        ARF_CreditBureauService.CreditReport r1 = ARF_CreditBureauService.generateMockReport(app1);
        ARF_CreditBureauService.CreditReport r2 = ARF_CreditBureauService.generateMockReport(app2);

        // At least one field should differ (extremely unlikely to collide)
        Boolean differs = r1.paydexScore != r2.paydexScore
            || r1.financialStressScore != r2.financialStressScore
            || r1.annualRevenue != r2.annualRevenue;
        System.assert(differs, 'Different companies should yield different mock data');
    }

    // ===== D&B Callout Tests =====

    @isTest
    static void testPullDnbReport_Success() {
        ARF_Credit_Application__c app = getTestApp();

        ARF_CreditBureau_Config__c config = new ARF_CreditBureau_Config__c(
            Provider__c = 'D&B',
            API_Key__c = 'test-key',
            API_Secret__c = 'test-secret',
            Base_URL__c = 'https://plus.dnb.com',
            Is_Active__c = true,
            Sandbox_Mode__c = false
        );

        Test.setMock(HttpCalloutMock.class, new DnbSuccessMock());

        Test.startTest();
        ARF_CreditBureauService.CreditReport report = ARF_CreditBureauService.pullDnbReport(app, config);
        Test.stopTest();

        System.assertEquals('D&B', report.provider, 'Provider should be D&B');
        System.assertNotEquals(null, report.rawResponseJson, 'Raw response should be populated');
        System.assertEquals(Date.today(), report.reportDate, 'Report date should be today');
    }

    @isTest
    static void testPullDnbReport_CompanyNotFound() {
        ARF_Credit_Application__c appNoDuns = new ARF_Credit_Application__c(
            Legal_Name__c = 'Unfindable Corp',
            Status__c = 'Submitted',
            Email__c = 'unfindable@test.com',
            Phone__c = '555-000-9999',
            Access_Token__c = 'unfindable-token',
            Token_Expiry__c = Datetime.now().addDays(30)
        );
        insert appNoDuns;

        appNoDuns = [SELECT Id, Legal_Name__c, DUNS_Number__c, Federal_Tax_ID__c,
            Billing_Street__c, Billing_City__c, Billing_State__c,
            Billing_Zip__c, Billing_Country__c
            FROM ARF_Credit_Application__c WHERE Id = :appNoDuns.Id];

        ARF_CreditBureau_Config__c config = new ARF_CreditBureau_Config__c(
            Provider__c = 'D&B',
            API_Key__c = 'test-key',
            API_Secret__c = 'test-secret',
            Base_URL__c = 'https://plus.dnb.com',
            Is_Active__c = true,
            Sandbox_Mode__c = false
        );

        Test.setMock(HttpCalloutMock.class, new DnbCompanyNotFoundMock());

        Test.startTest();
        ARF_CreditBureauService.CreditReport report = ARF_CreditBureauService.pullDnbReport(appNoDuns, config);
        Test.stopTest();

        System.assertEquals('Unknown', report.riskRating, 'Risk rating should be Unknown for unfound company');
        System.assert(report.summary.contains('not found'), 'Summary should indicate company not found');
    }

    // ===== Creditsafe Callout Tests =====

    @isTest
    static void testPullCreditsafeReport_Success() {
        ARF_Credit_Application__c app = getTestApp();

        ARF_CreditBureau_Config__c config = new ARF_CreditBureau_Config__c(
            Provider__c = 'Creditsafe',
            API_Key__c = 'test-user',
            API_Secret__c = 'test-pass',
            Base_URL__c = 'https://connect.creditsafe.com',
            Is_Active__c = true,
            Sandbox_Mode__c = false
        );

        Test.setMock(HttpCalloutMock.class, new CreditsafeSuccessMock());

        Test.startTest();
        ARF_CreditBureauService.CreditReport report = ARF_CreditBureauService.pullCreditsafeReport(app, config);
        Test.stopTest();

        System.assertEquals('Creditsafe', report.provider, 'Provider should be Creditsafe');
        System.assertNotEquals(null, report.rawResponseJson, 'Raw response should be populated');
        System.assertEquals(Date.today(), report.reportDate, 'Report date should be today');
    }

    @isTest
    static void testPullCreditsafeReport_CompanyNotFound() {
        ARF_Credit_Application__c appNoDuns = new ARF_Credit_Application__c(
            Legal_Name__c = 'Nowhere Inc',
            Status__c = 'Submitted',
            Email__c = 'nowhere@test.com',
            Phone__c = '555-000-8888',
            Access_Token__c = 'nowhere-token',
            Token_Expiry__c = Datetime.now().addDays(30)
        );
        insert appNoDuns;

        appNoDuns = [SELECT Id, Legal_Name__c, DUNS_Number__c, Federal_Tax_ID__c,
            Billing_Street__c, Billing_City__c, Billing_State__c,
            Billing_Zip__c, Billing_Country__c
            FROM ARF_Credit_Application__c WHERE Id = :appNoDuns.Id];

        ARF_CreditBureau_Config__c config = new ARF_CreditBureau_Config__c(
            Provider__c = 'Creditsafe',
            API_Key__c = 'test-user',
            API_Secret__c = 'test-pass',
            Base_URL__c = 'https://connect.creditsafe.com',
            Is_Active__c = true,
            Sandbox_Mode__c = false
        );

        Test.setMock(HttpCalloutMock.class, new CreditsafeCompanyNotFoundMock());

        Test.startTest();
        ARF_CreditBureauService.CreditReport report = ARF_CreditBureauService.pullCreditsafeReport(appNoDuns, config);
        Test.stopTest();

        System.assertEquals('Unknown', report.riskRating, 'Risk rating should be Unknown');
        System.assert(report.summary.contains('not found'), 'Summary should indicate company not found');
    }

    // ===== CreditReport Inner Class Tests =====

    @isTest
    static void testCreditReportDefaults() {
        ARF_CreditBureauService.CreditReport report = new ARF_CreditBureauService.CreditReport();

        System.assertEquals(false, report.bankruptcyFlag, 'Bankruptcy flag should default to false');
        System.assertEquals(0, report.legalFilings, 'Legal filings should default to 0');
        System.assertEquals(0, report.liens, 'Liens should default to 0');
    }

    // ===== HTTP CALLOUT MOCKS =====

    private class DnbSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/v2/token')) {
                // Auth response
                res.setBody('{"access_token":"mock-dnb-token-12345"}');
            } else if (endpoint.contains('/v1/match/cleanseMatch')) {
                // Search response
                res.setBody('{"matchCandidates":{"candidates":[{"organization":{"duns":"123456789","primaryName":{"name":"Bureau Test Corp"}}}]}}');
            } else if (endpoint.contains('/v1/data/duns/')) {
                // Full report response
                res.setBody('{"organization":{"duns":"123456789","primaryName":{"name":"Bureau Test Corp"},"dnbAssessment":{"standardRating":[{"scoreValue":82}],"failureScore":{"scoreValue":1450},"overallRating":{"scoreValue":78,"ratingDescription":"Low"}},"financials":{"yearlyRevenue":[{"value":5000000}]},"numberOfEmployees":[{"value":120}],"tradePaymentExperiences":{"totalExperienceCount":25}}}');
            }

            return res;
        }
    }

    private class DnbCompanyNotFoundMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/v2/token')) {
                res.setBody('{"access_token":"mock-dnb-token-12345"}');
            } else if (endpoint.contains('/v1/match/cleanseMatch')) {
                // No candidates
                res.setBody('{"matchCandidates":{"candidates":[]}}');
            }

            return res;
        }
    }

    private class CreditsafeSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/v1/authenticate')) {
                // Auth response (plain string token)
                res.setBody('"mock-creditsafe-token-67890"');
            } else if (endpoint.contains('/v1/companies?')) {
                // Search response
                res.setBody('{"companies":[{"id":"CS-12345","businessName":"Bureau Test Corp"}]}');
            } else if (endpoint.contains('/v1/companies/CS-12345')) {
                // Full report response
                res.setBody('{"report":{"companySummary":{"businessName":"Bureau Test Corp","creditRating":{"commonValue":75,"commonDescription":"Medium"}},"creditScore":{"currentCreditRating":{"value":75},"currentContractLimit":{"value":250000}},"financialStatements":{"statements":[{"profitAndLoss":{"revenue":5000000}}]},"paymentData":{"dbt":8,"totalTradeExperiences":30}}}');
            }

            return res;
        }
    }

    private class CreditsafeCompanyNotFoundMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint.contains('/v1/authenticate')) {
                res.setBody('"mock-creditsafe-token-67890"');
            } else if (endpoint.contains('/v1/companies?')) {
                // No companies
                res.setBody('{"companies":[]}');
            }

            return res;
        }
    }
}
