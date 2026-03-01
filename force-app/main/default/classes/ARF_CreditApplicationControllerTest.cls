@isTest
private class ARF_CreditApplicationControllerTest {

    @TestSetup
    static void setupTestData() {
        ARF_Credit_Application__c app = new ARF_Credit_Application__c(
            Status__c = 'Draft',
            Legal_Name__c = 'Test Credit Corp',
            DBA_Name__c = 'TCC',
            Phone__c = '555-100-2000',
            Fax__c = '555-100-2001',
            Email__c = 'apply@testcreditcorp.com',
            Website__c = 'www.testcreditcorp.com',
            Business_Type__c = 'Corporation',
            Years_In_Business__c = 10,
            Annual_Revenue__c = 5000000,
            Number_Of_Employees__c = 50,
            Requested_Credit_Limit__c = 250000,
            Billing_Street__c = '100 Main St',
            Billing_City__c = 'Dallas',
            Billing_State__c = 'TX',
            Billing_Zip__c = '75201',
            Billing_Country__c = 'US',
            Shipping_Street__c = '200 Warehouse Blvd',
            Shipping_City__c = 'Dallas',
            Shipping_State__c = 'TX',
            Shipping_Zip__c = '75202',
            Shipping_Country__c = 'US',
            AP_Contact_Name__c = 'Jane Doe',
            AP_Contact_Email__c = 'jane@testcreditcorp.com',
            AP_Contact_Phone__c = '555-100-3000',
            Federal_Tax_ID__c = '12-3456789',
            DUNS_Number__c = '123456789',
            Access_Token__c = 'test-token-123',
            Token_Expiry__c = Datetime.now().addDays(30)
        );
        insert app;

        ARF_Credit_Applicant__c applicant = new ARF_Credit_Applicant__c(
            Credit_Application__c = app.Id,
            First_Name__c = 'John',
            Last_Name__c = 'Smith',
            Title__c = 'CEO',
            Email__c = 'john@testcreditcorp.com',
            Phone__c = '555-200-1000',
            Ownership_Percentage__c = 60,
            Is_Primary__c = true
        );
        insert applicant;

        ARF_Trade_Reference__c tradeRef = new ARF_Trade_Reference__c(
            Credit_Application__c = app.Id,
            Company_Name__c = 'Supplier One',
            Contact_Name__c = 'Alice Brown',
            Phone__c = '555-300-1000',
            Email__c = 'alice@supplier1.com',
            Account_Number__c = 'SUP-001',
            Credit_Limit__c = 50000,
            Balance_Owed__c = 12000
        );
        insert tradeRef;

        ARF_Bank_Reference__c bankRef = new ARF_Bank_Reference__c(
            Credit_Application__c = app.Id,
            Bank_Name__c = 'First National Bank',
            Branch__c = 'Downtown Dallas',
            Contact_Name__c = 'Bob Banker',
            Phone__c = '555-400-1000',
            Account_Type__c = 'Checking',
            Account_Number__c = '9876543210',
            Routing_Number__c = '111000025'
        );
        insert bankRef;
    }

    private static ARF_Credit_Application__c getTestApp() {
        return [
            SELECT Id, Status__c, Legal_Name__c, Access_Token__c, Token_Expiry__c, Account__c
            FROM ARF_Credit_Application__c
            WHERE Access_Token__c = 'test-token-123'
            LIMIT 1
        ];
    }

    @isTest
    static void testGetApplications() {
        Test.startTest();
        List<ARF_Credit_Application__c> allApps = ARF_CreditApplicationController.getApplications('All');
        List<ARF_Credit_Application__c> draftApps = ARF_CreditApplicationController.getApplications('Draft');
        Test.stopTest();

        System.assert(!allApps.isEmpty(), 'All filter should return at least one application');
        System.assert(!draftApps.isEmpty(), 'Draft filter should return at least one application');
        System.assertEquals('Draft', draftApps[0].Status__c, 'Filtered app should be Draft');
    }

    @isTest
    static void testGetApplicationDetail() {
        ARF_Credit_Application__c app = getTestApp();

        Test.startTest();
        Map<String, Object> detail = ARF_CreditApplicationController.getApplicationDetail(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, detail.get('application'), 'Application should be returned');
        List<ARF_Credit_Applicant__c> applicants = (List<ARF_Credit_Applicant__c>) detail.get('applicants');
        System.assertEquals(1, applicants.size(), 'Should have 1 applicant');
        List<ARF_Trade_Reference__c> tradeRefs = (List<ARF_Trade_Reference__c>) detail.get('tradeReferences');
        System.assertEquals(1, tradeRefs.size(), 'Should have 1 trade reference');
        List<ARF_Bank_Reference__c> bankRefs = (List<ARF_Bank_Reference__c>) detail.get('bankReferences');
        System.assertEquals(1, bankRefs.size(), 'Should have 1 bank reference');
    }

    @isTest
    static void testLoadApplicationByToken() {
        Test.startTest();
        Map<String, Object> result = ARF_CreditApplicationController.loadApplicationByToken('test-token-123');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.get('application'), 'Application should be returned');
    }

    @isTest
    static void testLoadApplicationByToken_Expired() {
        ARF_Credit_Application__c app = getTestApp();
        app.Token_Expiry__c = Datetime.now().addDays(-1);
        app.Access_Token__c = 'expired-token-999';
        update app;

        Test.startTest();
        try {
            ARF_CreditApplicationController.loadApplicationByToken('expired-token-999');
            System.assert(false, 'Should have thrown an exception for expired token');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('expired') || e.getMessage().contains('Script-thrown'),
                'Exception should mention expiry');
        }
        Test.stopTest();
    }

    @isTest
    static void testLoadApplicationByToken_Submitted() {
        ARF_Credit_Application__c app = getTestApp();
        app.Status__c = 'Submitted';
        update app;

        Test.startTest();
        try {
            ARF_CreditApplicationController.loadApplicationByToken('test-token-123');
            System.assert(false, 'Should have thrown an exception for submitted application');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('submitted') || e.getMessage().contains('Script-thrown'),
                'Exception should mention submission');
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveStep1() {
        String dataJson = JSON.serialize(new Map<String, Object>{
            'legalName' => 'Updated Corp Name',
            'dbaName' => 'Updated DBA',
            'phone' => '555-999-0000',
            'fax' => '555-999-0001',
            'email' => 'updated@corp.com',
            'website' => 'www.updatedcorp.com',
            'businessType' => 'LLC',
            'yearsInBusiness' => 12,
            'annualRevenue' => 8000000,
            'numberOfEmployees' => 75,
            'requestedCreditLimit' => 300000,
            'billingStreet' => '500 New St',
            'billingCity' => 'Austin',
            'billingState' => 'TX',
            'billingZip' => '73301',
            'billingCountry' => 'US',
            'shippingStreet' => '600 Ship Rd',
            'shippingCity' => 'Austin',
            'shippingState' => 'TX',
            'shippingZip' => '73302',
            'shippingCountry' => 'US',
            'apContactName' => 'Updated AP',
            'apContactEmail' => 'ap@updated.com',
            'apContactPhone' => '555-888-0000',
            'applicants' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'firstName' => 'NewFirst',
                    'lastName' => 'NewLast',
                    'title' => 'CFO',
                    'email' => 'cfo@updated.com',
                    'phone' => '555-777-0000',
                    'ownershipPercentage' => 40,
                    'isPrimary' => true
                }
            }
        });

        Test.startTest();
        ARF_CreditApplicationController.saveApplicationStep('test-token-123', 1, dataJson);
        Test.stopTest();

        ARF_Credit_Application__c updated = [
            SELECT Legal_Name__c, Email__c, Billing_City__c
            FROM ARF_Credit_Application__c
            WHERE Access_Token__c = 'test-token-123'
        ];
        System.assertEquals('Updated Corp Name', updated.Legal_Name__c, 'Legal name should be updated');
        System.assertEquals('updated@corp.com', updated.Email__c, 'Email should be updated');
        System.assertEquals('Austin', updated.Billing_City__c, 'Billing city should be updated');

        List<ARF_Credit_Applicant__c> applicants = [
            SELECT First_Name__c FROM ARF_Credit_Applicant__c
            WHERE Credit_Application__c IN (
                SELECT Id FROM ARF_Credit_Application__c WHERE Access_Token__c = 'test-token-123'
            )
        ];
        System.assertEquals(1, applicants.size(), 'Should have replaced applicants with 1 new one');
        System.assertEquals('NewFirst', applicants[0].First_Name__c, 'Applicant first name should match');
    }

    @isTest
    static void testSaveStep2() {
        String dataJson = JSON.serialize(new Map<String, Object>{
            'tradeReferences' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'companyName' => 'New Supplier A',
                    'contactName' => 'Contact A',
                    'phone' => '555-111-0001',
                    'email' => 'a@supplier.com',
                    'accountNumber' => 'NSUP-A',
                    'creditLimit' => 75000,
                    'balanceOwed' => 5000
                },
                new Map<String, Object>{
                    'companyName' => 'New Supplier B',
                    'contactName' => 'Contact B',
                    'phone' => '555-111-0002',
                    'email' => 'b@supplier.com',
                    'accountNumber' => 'NSUP-B',
                    'creditLimit' => 60000,
                    'balanceOwed' => 3000
                }
            },
            'bankReferences' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'bankName' => 'New Bank',
                    'branch' => 'Uptown',
                    'contactName' => 'Banker New',
                    'phone' => '555-222-0001',
                    'accountType' => 'Savings',
                    'accountNumber' => '1111222233',
                    'routingNumber' => '222000033'
                }
            }
        });

        Test.startTest();
        ARF_CreditApplicationController.saveApplicationStep('test-token-123', 2, dataJson);
        Test.stopTest();

        ARF_Credit_Application__c app = getTestApp();
        List<ARF_Trade_Reference__c> tradeRefs = [
            SELECT Company_Name__c FROM ARF_Trade_Reference__c
            WHERE Credit_Application__c = :app.Id
        ];
        System.assertEquals(2, tradeRefs.size(), 'Should have 2 trade references after step 2');

        List<ARF_Bank_Reference__c> bankRefs = [
            SELECT Bank_Name__c FROM ARF_Bank_Reference__c
            WHERE Credit_Application__c = :app.Id
        ];
        System.assertEquals(1, bankRefs.size(), 'Should have 1 bank reference after step 2');
        System.assertEquals('New Bank', bankRefs[0].Bank_Name__c, 'Bank name should be updated');
    }

    @isTest
    static void testSaveStep3() {
        String dataJson = JSON.serialize(new Map<String, Object>{
            'guarantors' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'firstName' => 'Gary',
                    'lastName' => 'Guarantor',
                    'ssn' => '123-45-6789',
                    'dateOfBirth' => '1980-06-15',
                    'street' => '789 Guarantor Ln',
                    'city' => 'Houston',
                    'state' => 'TX',
                    'zip' => '77001',
                    'ownershipPercentage' => 51,
                    'phone' => '555-333-0001',
                    'email' => 'gary@guarantor.com'
                }
            }
        });

        Test.startTest();
        ARF_CreditApplicationController.saveApplicationStep('test-token-123', 3, dataJson);
        Test.stopTest();

        ARF_Credit_Application__c app = getTestApp();
        List<ARF_Personal_Guarantor__c> guarantors = [
            SELECT First_Name__c, City__c FROM ARF_Personal_Guarantor__c
            WHERE Credit_Application__c = :app.Id
        ];
        System.assertEquals(1, guarantors.size(), 'Should have 1 guarantor');
        System.assertEquals('Gary', guarantors[0].First_Name__c, 'Guarantor first name should match');
        System.assertEquals('Houston', guarantors[0].City__c, 'Guarantor city should match');
    }

    @isTest
    static void testSaveStep4() {
        String dataJson = JSON.serialize(new Map<String, Object>{
            'federalTaxId' => '98-7654321',
            'dunsNumber' => '987654321',
            'stateOfIncorporation' => 'Delaware'
        });

        Test.startTest();
        ARF_CreditApplicationController.saveApplicationStep('test-token-123', 4, dataJson);
        Test.stopTest();

        ARF_Credit_Application__c updated = [
            SELECT Federal_Tax_ID__c, DUNS_Number__c, State_Of_Incorporation__c
            FROM ARF_Credit_Application__c
            WHERE Access_Token__c = 'test-token-123'
        ];
        System.assertEquals('98-7654321', updated.Federal_Tax_ID__c, 'Tax ID should be updated');
        System.assertEquals('987654321', updated.DUNS_Number__c, 'DUNS number should be updated');
        System.assertEquals('Delaware', updated.State_Of_Incorporation__c, 'State of incorporation should be updated');
    }

    @isTest
    static void testSaveStep5() {
        String dataJson = JSON.serialize(new Map<String, Object>{
            'signatureData' => 'base64signaturedata==',
            'signatureName' => 'John Smith',
            'signatureTitle' => 'CEO',
            'termsAccepted' => true,
            'creditAuthAccepted' => true
        });

        Test.startTest();
        ARF_CreditApplicationController.saveApplicationStep('test-token-123', 5, dataJson);
        Test.stopTest();

        ARF_Credit_Application__c updated = [
            SELECT Status__c, Signature_Name__c, Terms_Accepted__c, Submitted_Date__c
            FROM ARF_Credit_Application__c
            WHERE Access_Token__c = 'test-token-123'
        ];
        System.assertEquals('Submitted', updated.Status__c, 'Status should be Submitted after step 5');
        System.assertEquals('John Smith', updated.Signature_Name__c, 'Signature name should match');
        System.assertEquals(true, updated.Terms_Accepted__c, 'Terms should be accepted');
        System.assertNotEquals(null, updated.Submitted_Date__c, 'Submitted date should be set');
    }

    @isTest
    static void testApproveApplication() {
        ARF_Credit_Application__c app = getTestApp();

        Test.startTest();
        ARF_CreditApplicationController.approveApplication(app.Id, 200000, 'Good credit history');
        Test.stopTest();

        ARF_Credit_Application__c updated = [
            SELECT Status__c, Approved_Credit_Limit__c, Decision_Notes__c, Decision_Date__c
            FROM ARF_Credit_Application__c
            WHERE Id = :app.Id
        ];
        System.assertEquals('Approved', updated.Status__c, 'Status should be Approved');
        System.assertEquals(200000, updated.Approved_Credit_Limit__c, 'Approved limit should match');
        System.assertEquals('Good credit history', updated.Decision_Notes__c, 'Decision notes should match');
        System.assertNotEquals(null, updated.Decision_Date__c, 'Decision date should be set');
    }

    @isTest
    static void testDeclineApplication() {
        ARF_Credit_Application__c app = getTestApp();

        Test.startTest();
        ARF_CreditApplicationController.declineApplication(app.Id, 'Insufficient credit history');
        Test.stopTest();

        ARF_Credit_Application__c updated = [
            SELECT Status__c, Approved_Credit_Limit__c, Decision_Notes__c, Decision_Date__c
            FROM ARF_Credit_Application__c
            WHERE Id = :app.Id
        ];
        System.assertEquals('Declined', updated.Status__c, 'Status should be Declined');
        System.assertEquals(0, updated.Approved_Credit_Limit__c, 'Approved limit should be 0');
        System.assertEquals('Insufficient credit history', updated.Decision_Notes__c, 'Decision notes should match');
        System.assertNotEquals(null, updated.Decision_Date__c, 'Decision date should be set');
    }

    @isTest
    static void testCreateAccountFromApplication() {
        ARF_Credit_Application__c app = getTestApp();
        app.Status__c = 'Approved';
        app.Approved_Credit_Limit__c = 200000;
        update app;

        Test.startTest();
        ARF_CreditApplicationController.createAccountFromApplication(app.Id);
        Test.stopTest();

        ARF_Credit_Application__c updated = [
            SELECT Account__c FROM ARF_Credit_Application__c WHERE Id = :app.Id
        ];
        System.assertNotEquals(null, updated.Account__c, 'Account should be linked to application');

        Account acct = [SELECT Name, Phone, BillingCity FROM Account WHERE Id = :updated.Account__c];
        System.assertEquals('Test Credit Corp', acct.Name, 'Account name should match legal name');
        System.assertEquals('Dallas', acct.BillingCity, 'Billing city should match');

        List<Contact> contacts = [SELECT FirstName, LastName, Title FROM Contact WHERE AccountId = :acct.Id];
        System.assertEquals(1, contacts.size(), 'Should have 1 contact from applicant');
        System.assertEquals('John', contacts[0].FirstName, 'Contact first name should match applicant');
        System.assertEquals('Smith', contacts[0].LastName, 'Contact last name should match applicant');
    }

    @isTest
    static void testEvaluateApplication() {
        ARF_Credit_Application__c app = getTestApp();

        Test.startTest();
        Map<String, Object> result = ARF_CreditApplicationController.evaluateApplication(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        Integer score = (Integer) result.get('score');
        System.assert(score > 0, 'Score should be greater than 0');
        String rating = (String) result.get('rating');
        System.assert(
            rating == 'Low' || rating == 'Medium' || rating == 'High' || rating == 'Very High',
            'Rating should be a valid risk level, got: ' + rating
        );
        System.assertNotEquals(null, result.get('recommendation'), 'Recommendation should be returned');
    }
}
