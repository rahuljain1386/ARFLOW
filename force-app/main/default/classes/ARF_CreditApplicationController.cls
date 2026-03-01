public with sharing class ARF_CreditApplicationController {

    // ===== STAFF-SIDE: LIST & MANAGE APPLICATIONS =====

    @AuraEnabled(cacheable=true)
    public static List<ARF_Credit_Application__c> getApplications(String statusFilter) {
        String query = 'SELECT Id, Name, Legal_Name__c, Status__c, Email__c, Phone__c, ' +
            'Requested_Credit_Limit__c, Approved_Credit_Limit__c, Credit_Score__c, ' +
            'Risk_Rating__c, Submitted_Date__c, Decision_Date__c, CreatedDate ' +
            'FROM ARF_Credit_Application__c';

        if (String.isNotBlank(statusFilter) && statusFilter != 'All') {
            query += ' WHERE Status__c = :statusFilter';
        }
        query += ' ORDER BY CreatedDate DESC LIMIT 200';
        return Database.query(query);
    }

    @AuraEnabled
    public static Map<String, Object> getApplicationDetail(Id applicationId) {
        ARF_Credit_Application__c app = [
            SELECT Id, Name, Status__c, Legal_Name__c, DBA_Name__c, Phone__c, Fax__c,
                Email__c, Website__c, Federal_Tax_ID__c, Business_Type__c,
                Years_In_Business__c, Date_Established__c, Annual_Revenue__c,
                Number_Of_Employees__c, Requested_Credit_Limit__c,
                Billing_Street__c, Billing_City__c, Billing_State__c,
                Billing_Zip__c, Billing_Country__c,
                Shipping_Street__c, Shipping_City__c, Shipping_State__c,
                Shipping_Zip__c, Shipping_Country__c,
                AP_Contact_Name__c, AP_Contact_Email__c, AP_Contact_Phone__c,
                Signature_Data__c, Signature_Date__c, Signature_Name__c, Signature_Title__c,
                Terms_Accepted__c, Credit_Auth_Accepted__c, Submitted_Date__c,
                Account__c, Credit_Score__c, Risk_Rating__c,
                Approved_Credit_Limit__c, Decision_Date__c, Decision_Notes__c,
                DUNS_Number__c, State_Of_Incorporation__c
            FROM ARF_Credit_Application__c
            WHERE Id = :applicationId
        ];

        List<ARF_Credit_Applicant__c> applicants = [
            SELECT Id, First_Name__c, Last_Name__c, Title__c, Email__c, Phone__c,
                Ownership_Percentage__c, Is_Primary__c
            FROM ARF_Credit_Applicant__c
            WHERE Credit_Application__c = :applicationId
            ORDER BY Is_Primary__c DESC
        ];

        List<ARF_Trade_Reference__c> tradeRefs = [
            SELECT Id, Company_Name__c, Contact_Name__c, Phone__c, Email__c,
                Account_Number__c, Credit_Limit__c, Balance_Owed__c
            FROM ARF_Trade_Reference__c
            WHERE Credit_Application__c = :applicationId
        ];

        List<ARF_Bank_Reference__c> bankRefs = [
            SELECT Id, Bank_Name__c, Branch__c, Contact_Name__c, Phone__c,
                Account_Type__c, Account_Number__c, Routing_Number__c
            FROM ARF_Bank_Reference__c
            WHERE Credit_Application__c = :applicationId
        ];

        List<ARF_Personal_Guarantor__c> guarantors = [
            SELECT Id, First_Name__c, Last_Name__c, Date_Of_Birth__c,
                Street__c, City__c, State__c, Zip__c,
                Ownership_Percentage__c, Phone__c, Email__c
            FROM ARF_Personal_Guarantor__c
            WHERE Credit_Application__c = :applicationId
        ];

        List<ARF_Credit_Check__c> creditChecks = [
            SELECT Id, Agency__c, Score__c, Rating__c, Report_Date__c,
                Status__c, Paydex_Score__c, Financial_Stress_Score__c
            FROM ARF_Credit_Check__c
            WHERE Credit_Application__c = :applicationId
            ORDER BY CreatedDate DESC
        ];

        Map<String, Object> result = new Map<String, Object>();
        result.put('application', app);
        result.put('applicants', applicants);
        result.put('tradeReferences', tradeRefs);
        result.put('bankReferences', bankRefs);
        result.put('guarantors', guarantors);
        result.put('creditChecks', creditChecks);
        return result;
    }

    // ===== STAFF ACTIONS =====

    @AuraEnabled
    public static Map<String, Object> runCreditCheck(Id applicationId, String agency) {
        ARF_CreditScoringEngine.runCreditCheck(applicationId, agency);
        Map<String, Object> scoring = ARF_CreditScoringEngine.evaluateApplication(applicationId);
        String recommendation = ARF_CreditScoringEngine.getRecommendedCreditLimit(applicationId);
        scoring.put('recommendation', recommendation);
        return scoring;
    }

    @AuraEnabled
    public static Map<String, Object> evaluateApplication(Id applicationId) {
        Map<String, Object> scoring = ARF_CreditScoringEngine.evaluateApplication(applicationId);
        String recommendation = ARF_CreditScoringEngine.getRecommendedCreditLimit(applicationId);
        scoring.put('recommendation', recommendation);
        return scoring;
    }

    @AuraEnabled
    public static void approveApplication(Id applicationId, Decimal approvedLimit, String notes) {
        ARF_Credit_Application__c app = new ARF_Credit_Application__c(
            Id = applicationId,
            Status__c = 'Approved',
            Approved_Credit_Limit__c = approvedLimit,
            Decision_Date__c = Datetime.now(),
            Decision_Notes__c = notes
        );
        update app;
    }

    @AuraEnabled
    public static void declineApplication(Id applicationId, String notes) {
        ARF_Credit_Application__c app = new ARF_Credit_Application__c(
            Id = applicationId,
            Status__c = 'Declined',
            Approved_Credit_Limit__c = 0,
            Decision_Date__c = Datetime.now(),
            Decision_Notes__c = notes
        );
        update app;
    }

    @AuraEnabled
    public static void createAccountFromApplication(Id applicationId) {
        ARF_Credit_Application__c app = [
            SELECT Id, Legal_Name__c, DBA_Name__c, Phone__c, Email__c, Website__c,
                Billing_Street__c, Billing_City__c, Billing_State__c, Billing_Zip__c, Billing_Country__c,
                Shipping_Street__c, Shipping_City__c, Shipping_State__c, Shipping_Zip__c, Shipping_Country__c,
                Approved_Credit_Limit__c, Account__c
            FROM ARF_Credit_Application__c
            WHERE Id = :applicationId
        ];

        if (app.Account__c != null) {
            throw new AuraHandledException('Account already created for this application');
        }

        Account acct = new Account(
            Name = app.Legal_Name__c,
            Phone = app.Phone__c,
            Website = app.Website__c,
            BillingStreet = app.Billing_Street__c,
            BillingCity = app.Billing_City__c,
            BillingState = app.Billing_State__c,
            BillingPostalCode = app.Billing_Zip__c,
            BillingCountry = app.Billing_Country__c,
            ShippingStreet = app.Shipping_Street__c,
            ShippingCity = app.Shipping_City__c,
            ShippingState = app.Shipping_State__c,
            ShippingPostalCode = app.Shipping_Zip__c,
            ShippingCountry = app.Shipping_Country__c
        );
        insert acct;

        // Link application to account
        app.Account__c = acct.Id;
        update app;

        // Create contacts from applicants
        List<ARF_Credit_Applicant__c> applicants = [
            SELECT First_Name__c, Last_Name__c, Email__c, Phone__c, Title__c, Is_Primary__c
            FROM ARF_Credit_Applicant__c
            WHERE Credit_Application__c = :applicationId
        ];
        List<Contact> contacts = new List<Contact>();
        for (ARF_Credit_Applicant__c applicant : applicants) {
            contacts.add(new Contact(
                AccountId = acct.Id,
                FirstName = applicant.First_Name__c,
                LastName = applicant.Last_Name__c,
                Email = applicant.Email__c,
                Phone = applicant.Phone__c,
                Title = applicant.Title__c,
                ARF_Primary_AR_Contact__c = applicant.Is_Primary__c
            ));
        }
        if (!contacts.isEmpty()) {
            insert contacts;
        }
    }

    // ===== EXTERNAL FORM: LOAD & SAVE BY TOKEN =====

    @AuraEnabled
    public static Map<String, Object> loadApplicationByToken(String token) {
        if (String.isBlank(token)) {
            throw new AuraHandledException('Access token is required');
        }

        List<ARF_Credit_Application__c> apps = [
            SELECT Id, Token_Expiry__c, Status__c
            FROM ARF_Credit_Application__c
            WHERE Access_Token__c = :token
            LIMIT 1
        ];

        if (apps.isEmpty()) {
            throw new AuraHandledException('Application not found');
        }

        ARF_Credit_Application__c app = apps[0];
        if (app.Token_Expiry__c != null && app.Token_Expiry__c < Datetime.now()) {
            throw new AuraHandledException('This link has expired');
        }

        if (app.Status__c == 'Submitted' || app.Status__c == 'Approved' || app.Status__c == 'Declined') {
            throw new AuraHandledException('This application has already been submitted');
        }

        return getApplicationDetail(app.Id);
    }

    @AuraEnabled
    public static void saveApplicationStep(String token, Integer step, String dataJson) {
        if (String.isBlank(token)) {
            throw new AuraHandledException('Access token is required');
        }

        List<ARF_Credit_Application__c> apps = [
            SELECT Id, Token_Expiry__c, Status__c
            FROM ARF_Credit_Application__c
            WHERE Access_Token__c = :token
            LIMIT 1
        ];

        if (apps.isEmpty()) {
            throw new AuraHandledException('Application not found');
        }

        ARF_Credit_Application__c app = apps[0];
        if (app.Token_Expiry__c != null && app.Token_Expiry__c < Datetime.now()) {
            throw new AuraHandledException('This link has expired');
        }
        if (app.Status__c == 'Submitted') {
            throw new AuraHandledException('This application has already been submitted');
        }

        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(dataJson);
        Id appId = app.Id;

        switch on step {
            when 1 { saveStep1(appId, data); }
            when 2 { saveStep2(appId, data); }
            when 3 { saveStep3(appId, data); }
            when 4 { saveStep4(appId, data); }
            when 5 { saveStep5(appId, data); }
        }
    }

    @TestVisible
    private static void saveStep1(Id appId, Map<String, Object> data) {
        ARF_Credit_Application__c app = new ARF_Credit_Application__c(Id = appId);
        app.Legal_Name__c = (String) data.get('legalName');
        app.DBA_Name__c = (String) data.get('dbaName');
        app.Phone__c = (String) data.get('phone');
        app.Fax__c = (String) data.get('fax');
        app.Email__c = (String) data.get('email');
        app.Website__c = (String) data.get('website');
        app.Business_Type__c = (String) data.get('businessType');
        app.Years_In_Business__c = data.get('yearsInBusiness') != null ?
            Decimal.valueOf(String.valueOf(data.get('yearsInBusiness'))) : null;
        app.Date_Established__c = data.get('dateEstablished') != null ?
            Date.valueOf((String) data.get('dateEstablished')) : null;
        app.Annual_Revenue__c = data.get('annualRevenue') != null ?
            Decimal.valueOf(String.valueOf(data.get('annualRevenue'))) : null;
        app.Number_Of_Employees__c = data.get('numberOfEmployees') != null ?
            Decimal.valueOf(String.valueOf(data.get('numberOfEmployees'))) : null;
        app.Requested_Credit_Limit__c = data.get('requestedCreditLimit') != null ?
            Decimal.valueOf(String.valueOf(data.get('requestedCreditLimit'))) : null;
        app.Billing_Street__c = (String) data.get('billingStreet');
        app.Billing_City__c = (String) data.get('billingCity');
        app.Billing_State__c = (String) data.get('billingState');
        app.Billing_Zip__c = (String) data.get('billingZip');
        app.Billing_Country__c = (String) data.get('billingCountry');
        app.Shipping_Street__c = (String) data.get('shippingStreet');
        app.Shipping_City__c = (String) data.get('shippingCity');
        app.Shipping_State__c = (String) data.get('shippingState');
        app.Shipping_Zip__c = (String) data.get('shippingZip');
        app.Shipping_Country__c = (String) data.get('shippingCountry');
        app.AP_Contact_Name__c = (String) data.get('apContactName');
        app.AP_Contact_Email__c = (String) data.get('apContactEmail');
        app.AP_Contact_Phone__c = (String) data.get('apContactPhone');
        update app;

        // Save applicants
        if (data.containsKey('applicants')) {
            delete [SELECT Id FROM ARF_Credit_Applicant__c WHERE Credit_Application__c = :appId];
            List<Object> applicantList = (List<Object>) data.get('applicants');
            List<ARF_Credit_Applicant__c> applicants = new List<ARF_Credit_Applicant__c>();
            for (Object obj : applicantList) {
                Map<String, Object> a = (Map<String, Object>) obj;
                applicants.add(new ARF_Credit_Applicant__c(
                    Credit_Application__c = appId,
                    First_Name__c = (String) a.get('firstName'),
                    Last_Name__c = (String) a.get('lastName'),
                    Title__c = (String) a.get('title'),
                    Email__c = (String) a.get('email'),
                    Phone__c = (String) a.get('phone'),
                    Ownership_Percentage__c = a.get('ownershipPercentage') != null ?
                        Decimal.valueOf(String.valueOf(a.get('ownershipPercentage'))) : null,
                    Is_Primary__c = a.get('isPrimary') == true
                ));
            }
            if (!applicants.isEmpty()) insert applicants;
        }
    }

    @TestVisible
    private static void saveStep2(Id appId, Map<String, Object> data) {
        // Trade references
        if (data.containsKey('tradeReferences')) {
            delete [SELECT Id FROM ARF_Trade_Reference__c WHERE Credit_Application__c = :appId];
            List<Object> refList = (List<Object>) data.get('tradeReferences');
            List<ARF_Trade_Reference__c> refs = new List<ARF_Trade_Reference__c>();
            for (Object obj : refList) {
                Map<String, Object> r = (Map<String, Object>) obj;
                refs.add(new ARF_Trade_Reference__c(
                    Credit_Application__c = appId,
                    Company_Name__c = (String) r.get('companyName'),
                    Contact_Name__c = (String) r.get('contactName'),
                    Phone__c = (String) r.get('phone'),
                    Email__c = (String) r.get('email'),
                    Account_Number__c = (String) r.get('accountNumber'),
                    Credit_Limit__c = r.get('creditLimit') != null ?
                        Decimal.valueOf(String.valueOf(r.get('creditLimit'))) : null,
                    Balance_Owed__c = r.get('balanceOwed') != null ?
                        Decimal.valueOf(String.valueOf(r.get('balanceOwed'))) : null
                ));
            }
            if (!refs.isEmpty()) insert refs;
        }

        // Bank references
        if (data.containsKey('bankReferences')) {
            delete [SELECT Id FROM ARF_Bank_Reference__c WHERE Credit_Application__c = :appId];
            List<Object> bankList = (List<Object>) data.get('bankReferences');
            List<ARF_Bank_Reference__c> banks = new List<ARF_Bank_Reference__c>();
            for (Object obj : bankList) {
                Map<String, Object> b = (Map<String, Object>) obj;
                banks.add(new ARF_Bank_Reference__c(
                    Credit_Application__c = appId,
                    Bank_Name__c = (String) b.get('bankName'),
                    Branch__c = (String) b.get('branch'),
                    Contact_Name__c = (String) b.get('contactName'),
                    Phone__c = (String) b.get('phone'),
                    Account_Type__c = (String) b.get('accountType'),
                    Account_Number__c = (String) b.get('accountNumber'),
                    Routing_Number__c = (String) b.get('routingNumber')
                ));
            }
            if (!banks.isEmpty()) insert banks;
        }
    }

    @TestVisible
    private static void saveStep3(Id appId, Map<String, Object> data) {
        if (data.containsKey('guarantors')) {
            delete [SELECT Id FROM ARF_Personal_Guarantor__c WHERE Credit_Application__c = :appId];
            List<Object> gList = (List<Object>) data.get('guarantors');
            List<ARF_Personal_Guarantor__c> guarantors = new List<ARF_Personal_Guarantor__c>();
            for (Object obj : gList) {
                Map<String, Object> g = (Map<String, Object>) obj;
                guarantors.add(new ARF_Personal_Guarantor__c(
                    Credit_Application__c = appId,
                    First_Name__c = (String) g.get('firstName'),
                    Last_Name__c = (String) g.get('lastName'),
                    SSN__c = (String) g.get('ssn'),
                    Date_Of_Birth__c = g.get('dateOfBirth') != null ?
                        Date.valueOf((String) g.get('dateOfBirth')) : null,
                    Street__c = (String) g.get('street'),
                    City__c = (String) g.get('city'),
                    State__c = (String) g.get('state'),
                    Zip__c = (String) g.get('zip'),
                    Ownership_Percentage__c = g.get('ownershipPercentage') != null ?
                        Decimal.valueOf(String.valueOf(g.get('ownershipPercentage'))) : null,
                    Phone__c = (String) g.get('phone'),
                    Email__c = (String) g.get('email')
                ));
            }
            if (!guarantors.isEmpty()) insert guarantors;
        }
    }

    @TestVisible
    private static void saveStep4(Id appId, Map<String, Object> data) {
        ARF_Credit_Application__c app = new ARF_Credit_Application__c(Id = appId);
        app.Federal_Tax_ID__c = (String) data.get('federalTaxId');
        app.DUNS_Number__c = (String) data.get('dunsNumber');
        app.State_Of_Incorporation__c = (String) data.get('stateOfIncorporation');
        update app;
    }

    @TestVisible
    private static void saveStep5(Id appId, Map<String, Object> data) {
        ARF_Credit_Application__c app = new ARF_Credit_Application__c(Id = appId);
        app.Signature_Data__c = (String) data.get('signatureData');
        app.Signature_Name__c = (String) data.get('signatureName');
        app.Signature_Title__c = (String) data.get('signatureTitle');
        app.Signature_Date__c = Datetime.now();
        app.Terms_Accepted__c = data.get('termsAccepted') == true;
        app.Credit_Auth_Accepted__c = data.get('creditAuthAccepted') == true;
        app.Status__c = 'Submitted';
        app.Submitted_Date__c = Datetime.now();
        update app;
    }
}
