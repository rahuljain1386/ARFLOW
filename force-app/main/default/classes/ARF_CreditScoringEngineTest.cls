@isTest
private class ARF_CreditScoringEngineTest {

    @TestSetup
    static void setupTestData() {
        ARF_Credit_Application__c app = new ARF_Credit_Application__c(
            Status__c = 'Submitted',
            Legal_Name__c = 'Scoring Test Corp',
            Years_In_Business__c = 8,
            Annual_Revenue__c = 5000000,
            Requested_Credit_Limit__c = 200000,
            Federal_Tax_ID__c = '12-3456789',
            DUNS_Number__c = '123456789',
            AP_Contact_Name__c = 'AP Team',
            Email__c = 'scoring@test.com',
            Phone__c = '555-500-1000',
            Access_Token__c = 'scoring-token-001',
            Token_Expiry__c = Datetime.now().addDays(30)
        );
        insert app;

        // 3 trade references
        List<ARF_Trade_Reference__c> tradeRefs = new List<ARF_Trade_Reference__c>();
        for (Integer i = 1; i <= 3; i++) {
            tradeRefs.add(new ARF_Trade_Reference__c(
                Credit_Application__c = app.Id,
                Company_Name__c = 'Trade Ref ' + i,
                Contact_Name__c = 'Contact ' + i,
                Phone__c = '555-600-000' + i,
                Email__c = 'ref' + i + '@trade.com',
                Account_Number__c = 'TR-00' + i,
                Credit_Limit__c = 50000 * i,
                Balance_Owed__c = 5000 * i
            ));
        }
        insert tradeRefs;

        // 1 bank reference
        ARF_Bank_Reference__c bankRef = new ARF_Bank_Reference__c(
            Credit_Application__c = app.Id,
            Bank_Name__c = 'Scoring Test Bank',
            Branch__c = 'Main Branch',
            Contact_Name__c = 'Bank Contact',
            Phone__c = '555-700-1000',
            Account_Type__c = 'Checking',
            Account_Number__c = '5555666677',
            Routing_Number__c = '111000025'
        );
        insert bankRef;

        // 1 personal guarantor
        ARF_Personal_Guarantor__c guarantor = new ARF_Personal_Guarantor__c(
            Credit_Application__c = app.Id,
            First_Name__c = 'Gina',
            Last_Name__c = 'Guarantor',
            Date_Of_Birth__c = Date.newInstance(1975, 3, 20),
            Street__c = '123 Guarantor St',
            City__c = 'Dallas',
            State__c = 'TX',
            Zip__c = '75201',
            Ownership_Percentage__c = 100,
            Phone__c = '555-800-1000',
            Email__c = 'gina@guarantor.com'
        );
        insert guarantor;
    }

    private static ARF_Credit_Application__c getTestApp() {
        return [
            SELECT Id, Status__c, Years_In_Business__c, Annual_Revenue__c,
                   Requested_Credit_Limit__c, Credit_Score__c, Risk_Rating__c
            FROM ARF_Credit_Application__c
            WHERE Access_Token__c = 'scoring-token-001'
            LIMIT 1
        ];
    }

    @isTest
    static void testEvaluateApplication() {
        ARF_Credit_Application__c app = getTestApp();

        Test.startTest();
        Map<String, Object> result = ARF_CreditScoringEngine.evaluateApplication(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        Integer score = (Integer) result.get('score');
        System.assert(score > 0, 'Score should be greater than 0');

        String rating = (String) result.get('rating');
        System.assert(
            rating == 'Low' || rating == 'Medium' || rating == 'High' || rating == 'Very High',
            'Rating should be one of Low/Medium/High/Very High, got: ' + rating
        );

        List<String> factors = (List<String>) result.get('factors');
        System.assertNotEquals(null, factors, 'Factors list should not be null');
        System.assert(!factors.isEmpty(), 'Factors list should not be empty');

        // Verify score was persisted to the record
        ARF_Credit_Application__c updated = [
            SELECT Credit_Score__c, Risk_Rating__c
            FROM ARF_Credit_Application__c
            WHERE Id = :app.Id
        ];
        System.assertEquals(score, updated.Credit_Score__c.intValue(), 'Persisted score should match returned score');
        System.assertEquals(rating, updated.Risk_Rating__c, 'Persisted rating should match returned rating');
    }

    @isTest
    static void testGetRecommendedCreditLimit() {
        ARF_Credit_Application__c app = getTestApp();

        // First evaluate so the app has a score and rating
        ARF_CreditScoringEngine.evaluateApplication(app.Id);

        Test.startTest();
        String recommendation = ARF_CreditScoringEngine.getRecommendedCreditLimit(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, recommendation, 'Recommendation should not be null');
        System.assert(recommendation.length() > 0, 'Recommendation should not be empty');
    }

    @isTest
    static void testRunCreditCheck() {
        ARF_Credit_Application__c app = getTestApp();

        Test.startTest();
        ARF_CreditScoringEngine.runCreditCheck(app.Id, 'D&B');
        Test.stopTest();

        List<ARF_Credit_Check__c> checks = [
            SELECT Id, Agency__c, Status__c, Paydex_Score__c, Financial_Stress_Score__c
            FROM ARF_Credit_Check__c
            WHERE Credit_Application__c = :app.Id
        ];
        System.assertEquals(1, checks.size(), 'Should have 1 credit check record');
        System.assertEquals('D&B', checks[0].Agency__c, 'Agency should be D&B');
        System.assertEquals('Pending', checks[0].Status__c, 'Status should be Pending');
        System.assertNotEquals(null, checks[0].Paydex_Score__c, 'Paydex score should be populated');
        System.assertNotEquals(null, checks[0].Financial_Stress_Score__c, 'Financial stress score should be populated');
    }

    @isTest
    static void testHighRiskApplication() {
        // Create a weak application with minimal data
        ARF_Credit_Application__c weakApp = new ARF_Credit_Application__c(
            Status__c = 'Submitted',
            Legal_Name__c = 'Risky Startup LLC',
            Years_In_Business__c = 0,
            Annual_Revenue__c = 50000,
            Requested_Credit_Limit__c = 100000,
            Email__c = 'risky@startup.com',
            Phone__c = '555-999-0001',
            Access_Token__c = 'high-risk-token',
            Token_Expiry__c = Datetime.now().addDays(30)
        );
        insert weakApp;
        // No trade references, no bank references, no guarantors, no tax ID, no DUNS

        Test.startTest();
        Map<String, Object> result = ARF_CreditScoringEngine.evaluateApplication(weakApp.Id);
        Test.stopTest();

        String rating = (String) result.get('rating');
        System.assert(
            rating == 'High' || rating == 'Very High',
            'Weak application should be High or Very High risk, got: ' + rating
        );
    }

    @isTest
    static void testLowRiskApplication() {
        // Create a strong application
        ARF_Credit_Application__c strongApp = new ARF_Credit_Application__c(
            Status__c = 'Submitted',
            Legal_Name__c = 'Solid Enterprise Inc',
            Years_In_Business__c = 15,
            Annual_Revenue__c = 20000000,
            Requested_Credit_Limit__c = 100000,
            Federal_Tax_ID__c = '99-8765432',
            DUNS_Number__c = '999888777',
            AP_Contact_Name__c = 'Senior AP Manager',
            Email__c = 'solid@enterprise.com',
            Phone__c = '555-000-1111',
            Access_Token__c = 'low-risk-token',
            Token_Expiry__c = Datetime.now().addDays(30)
        );
        insert strongApp;

        // 3 trade references for maximum reference score
        List<ARF_Trade_Reference__c> tradeRefs = new List<ARF_Trade_Reference__c>();
        for (Integer i = 1; i <= 3; i++) {
            tradeRefs.add(new ARF_Trade_Reference__c(
                Credit_Application__c = strongApp.Id,
                Company_Name__c = 'Strong Ref ' + i,
                Contact_Name__c = 'Ref Contact ' + i,
                Phone__c = '555-000-200' + i,
                Email__c = 'ref' + i + '@strong.com',
                Account_Number__c = 'STR-00' + i,
                Credit_Limit__c = 100000,
                Balance_Owed__c = 0
            ));
        }
        insert tradeRefs;

        // Bank reference
        ARF_Bank_Reference__c bankRef = new ARF_Bank_Reference__c(
            Credit_Application__c = strongApp.Id,
            Bank_Name__c = 'Premier Bank',
            Branch__c = 'Corporate',
            Contact_Name__c = 'Premier Banker',
            Phone__c = '555-000-3000',
            Account_Type__c = 'Checking',
            Account_Number__c = '8888777766',
            Routing_Number__c = '333000044'
        );
        insert bankRef;

        // Personal guarantor
        ARF_Personal_Guarantor__c guarantor = new ARF_Personal_Guarantor__c(
            Credit_Application__c = strongApp.Id,
            First_Name__c = 'Reliable',
            Last_Name__c = 'Owner',
            Date_Of_Birth__c = Date.newInstance(1965, 1, 10),
            Street__c = '1 Enterprise Way',
            City__c = 'New York',
            State__c = 'NY',
            Zip__c = '10001',
            Ownership_Percentage__c = 100,
            Phone__c = '555-000-4000',
            Email__c = 'owner@strong.com'
        );
        insert guarantor;

        Test.startTest();
        Map<String, Object> result = ARF_CreditScoringEngine.evaluateApplication(strongApp.Id);
        Test.stopTest();

        String rating = (String) result.get('rating');
        System.assertEquals('Low', rating,
            'Strong application should be Low risk, got: ' + rating);
    }
}
