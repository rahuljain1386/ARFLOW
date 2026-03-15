public with sharing class ARF_CreditBureauService {

    // ===== MAIN ENTRY POINT =====

    @AuraEnabled
    public static CreditReport pullReport(Id creditApplicationId) {
        ARF_Credit_Application__c app = [
            SELECT Id, Legal_Name__c, DUNS_Number__c, Federal_Tax_ID__c,
                   Billing_Street__c, Billing_City__c, Billing_State__c,
                   Billing_Zip__c, Billing_Country__c
            FROM ARF_Credit_Application__c
            WHERE Id = :creditApplicationId
            LIMIT 1
        ];

        ARF_CreditBureau_Config__c config = ARF_CreditBureau_Config__c.getInstance();

        // Route to the correct provider
        CreditReport report;
        String provider = config != null && String.isNotBlank(config.Provider__c)
            ? config.Provider__c : 'Mock';

        Boolean isSandbox = config != null ? config.Sandbox_Mode__c : true;

        if (isSandbox || provider == 'Mock') {
            report = generateMockReport(app);
        } else if (provider == 'D&B') {
            report = pullDnbReport(app, config);
        } else if (provider == 'Creditsafe') {
            report = pullCreditsafeReport(app, config);
        } else {
            report = generateMockReport(app);
        }

        // Persist the credit check record
        ARF_Credit_Check__c chk = new ARF_Credit_Check__c(
            Credit_Application__c = creditApplicationId,
            Agency__c = report.provider,
            Status__c = 'Completed',
            Report_Date__c = Date.today(),
            Score__c = report.overallScore,
            Rating__c = report.riskRating,
            Paydex_Score__c = report.paydexScore,
            Financial_Stress_Score__c = report.financialStressScore,
            Raw_Response__c = report.rawResponseJson != null
                ? report.rawResponseJson.abbreviate(131072) : null
        );
        insert chk;

        report.creditCheckId = chk.Id;
        return report;
    }

    // ===== D&B INTEGRATION =====

    @TestVisible
    private static CreditReport pullDnbReport(ARF_Credit_Application__c app, ARF_CreditBureau_Config__c config) {
        CreditReport report = new CreditReport();
        report.provider = 'D&B';
        report.reportDate = Date.today();

        String baseUrl = String.isNotBlank(config.Base_URL__c) ? config.Base_URL__c : 'https://plus.dnb.com';

        // Step 1: Authenticate
        String authToken = authenticateDnb(baseUrl, config.API_Key__c, config.API_Secret__c);

        // Step 2: Search for company by DUNS or name
        String dunsNumber = app.DUNS_Number__c;
        if (String.isBlank(dunsNumber)) {
            dunsNumber = searchDnbCompany(baseUrl, authToken, app.Legal_Name__c,
                app.Billing_City__c, app.Billing_State__c, app.Billing_Country__c);
        }

        if (String.isBlank(dunsNumber)) {
            report.overallScore = 0;
            report.riskRating = 'Unknown';
            report.summary = 'Company not found in D&B database.';
            return report;
        }

        // Step 3: Pull full credit report
        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseUrl + '/v1/data/duns/' + dunsNumber + '?productId=cmpelk&versionId=v1');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + authToken);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            report.overallScore = 0;
            report.riskRating = 'Error';
            report.summary = 'D&B API error: HTTP ' + res.getStatusCode();
            report.rawResponseJson = res.getBody();
            return report;
        }

        report.rawResponseJson = res.getBody();
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        // Parse D&B response
        parseDnbResponse(report, body);

        return report;
    }

    private static String authenticateDnb(String baseUrl, String apiKey, String apiSecret) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseUrl + '/v2/token');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(15000);
        req.setBody(JSON.serialize(new Map<String, String>{
            'grant_type' => 'client_credentials'
        }));
        req.setHeader('x-dnb-user', apiKey);
        req.setHeader('x-dnb-pwd', apiSecret);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new CreditBureauException('D&B authentication failed: HTTP ' + res.getStatusCode());
        }

        Map<String, Object> authResult = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) authResult.get('access_token');
    }

    private static String searchDnbCompany(String baseUrl, String authToken, String companyName,
            String city, String state, String country) {
        String searchUrl = baseUrl + '/v1/match/cleanseMatch?name=' + EncodingUtil.urlEncode(companyName, 'UTF-8');
        if (String.isNotBlank(state)) {
            searchUrl += '&addressRegion=' + EncodingUtil.urlEncode(state, 'UTF-8');
        }
        if (String.isNotBlank(country)) {
            searchUrl += '&countryISOAlpha2Code=' + EncodingUtil.urlEncode(country, 'UTF-8');
        } else {
            searchUrl += '&countryISOAlpha2Code=US';
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(searchUrl);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + authToken);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(15000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            return null;
        }

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> matchCandidates = (Map<String, Object>) result.get('matchCandidates');
        if (matchCandidates != null) {
            List<Object> candidates = (List<Object>) matchCandidates.get('candidates');
            if (candidates != null && !candidates.isEmpty()) {
                Map<String, Object> bestMatch = (Map<String, Object>) candidates[0];
                Map<String, Object> organization = (Map<String, Object>) bestMatch.get('organization');
                if (organization != null) {
                    return (String) organization.get('duns');
                }
            }
        }

        return null;
    }

    private static void parseDnbResponse(CreditReport report, Map<String, Object> body) {
        Map<String, Object> org = (Map<String, Object>) body.get('organization');
        if (org == null) {
            report.overallScore = 0;
            report.riskRating = 'Unknown';
            report.summary = 'No organization data in D&B response.';
            return;
        }

        // Company info
        Map<String, Object> primaryName = (Map<String, Object>) org.get('primaryName');
        if (primaryName != null) {
            report.companyName = (String) primaryName.get('name');
        }

        report.dunsNumber = (String) org.get('duns');

        // Financial data
        Map<String, Object> dnbAssessment = (Map<String, Object>) org.get('dnbAssessment');
        if (dnbAssessment != null) {
            // Paydex
            List<Object> paymentBehavior = (List<Object>) dnbAssessment.get('standardRating');
            if (paymentBehavior != null && !paymentBehavior.isEmpty()) {
                Map<String, Object> rating = (Map<String, Object>) paymentBehavior[0];
                Object scoreVal = rating.get('scoreValue');
                if (scoreVal != null) {
                    report.paydexScore = Integer.valueOf(String.valueOf(scoreVal));
                }
            }

            // Financial Stress Score
            Map<String, Object> failureScore = (Map<String, Object>) dnbAssessment.get('failureScore');
            if (failureScore != null) {
                Object stressVal = failureScore.get('scoreValue');
                if (stressVal != null) {
                    report.financialStressScore = Integer.valueOf(String.valueOf(stressVal));
                }
            }

            // Overall rating
            Map<String, Object> overallRating = (Map<String, Object>) dnbAssessment.get('overallRating');
            if (overallRating != null) {
                Object ratingVal = overallRating.get('scoreValue');
                if (ratingVal != null) {
                    report.overallScore = Integer.valueOf(String.valueOf(ratingVal));
                }
                report.riskRating = (String) overallRating.get('ratingDescription');
            }
        }

        // Financials
        Map<String, Object> financials = (Map<String, Object>) org.get('financials');
        if (financials != null) {
            List<Object> yearlyRevenue = (List<Object>) financials.get('yearlyRevenue');
            if (yearlyRevenue != null && !yearlyRevenue.isEmpty()) {
                Map<String, Object> revenue = (Map<String, Object>) yearlyRevenue[0];
                Object revVal = revenue.get('value');
                if (revVal != null) {
                    report.annualRevenue = Decimal.valueOf(String.valueOf(revVal));
                }
            }
        }

        // Employee count
        Object empCount = org.get('numberOfEmployees');
        if (empCount != null) {
            List<Object> empList = (List<Object>) empCount;
            if (!empList.isEmpty()) {
                Map<String, Object> emp = (Map<String, Object>) empList[0];
                Object val = emp.get('value');
                if (val != null) {
                    report.employeeCount = Integer.valueOf(String.valueOf(val));
                }
            }
        }

        // Trade payment experiences
        report.tradePaymentExperiences = 0;
        Map<String, Object> tradePayment = (Map<String, Object>) org.get('tradePaymentExperiences');
        if (tradePayment != null) {
            Object totalCount = tradePayment.get('totalExperienceCount');
            if (totalCount != null) {
                report.tradePaymentExperiences = Integer.valueOf(String.valueOf(totalCount));
            }
        }

        // Build summary
        report.summary = buildSummary(report);

        // Ensure we have risk rating
        if (String.isBlank(report.riskRating)) {
            report.riskRating = deriveRiskRating(report.paydexScore, report.financialStressScore);
        }
        if (report.overallScore == null || report.overallScore == 0) {
            report.overallScore = report.paydexScore != null ? report.paydexScore : 0;
        }
    }

    // ===== CREDITSAFE INTEGRATION =====

    @TestVisible
    private static CreditReport pullCreditsafeReport(ARF_Credit_Application__c app, ARF_CreditBureau_Config__c config) {
        CreditReport report = new CreditReport();
        report.provider = 'Creditsafe';
        report.reportDate = Date.today();

        String baseUrl = String.isNotBlank(config.Base_URL__c) ? config.Base_URL__c : 'https://connect.creditsafe.com';

        // Step 1: Authenticate
        String authToken = authenticateCreditsafe(baseUrl, config.API_Key__c, config.API_Secret__c);

        // Step 2: Search for company
        String companyId = searchCreditsafeCompany(baseUrl, authToken, app.Legal_Name__c,
            app.Billing_Country__c, app.Federal_Tax_ID__c);

        if (String.isBlank(companyId)) {
            report.overallScore = 0;
            report.riskRating = 'Unknown';
            report.summary = 'Company not found in Creditsafe database.';
            return report;
        }

        // Step 3: Pull credit report
        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseUrl + '/v1/companies/' + companyId);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + authToken);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            report.overallScore = 0;
            report.riskRating = 'Error';
            report.summary = 'Creditsafe API error: HTTP ' + res.getStatusCode();
            report.rawResponseJson = res.getBody();
            return report;
        }

        report.rawResponseJson = res.getBody();
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        // Parse Creditsafe response
        parseCreditsafeResponse(report, body);

        return report;
    }

    private static String authenticateCreditsafe(String baseUrl, String apiKey, String apiSecret) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseUrl + '/v1/authenticate');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(15000);
        req.setBody(JSON.serialize(new Map<String, String>{
            'username' => apiKey,
            'password' => apiSecret
        }));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new CreditBureauException('Creditsafe authentication failed: HTTP ' + res.getStatusCode());
        }

        // Creditsafe returns the token as a plain string (with quotes)
        String token = res.getBody();
        token = token.removeStart('"').removeEnd('"');
        return token;
    }

    private static String searchCreditsafeCompany(String baseUrl, String authToken, String companyName,
            String country, String taxId) {
        String countryCode = String.isNotBlank(country) ? country : 'US';

        String searchUrl = baseUrl + '/v1/companies?countries=' + EncodingUtil.urlEncode(countryCode, 'UTF-8')
            + '&name=' + EncodingUtil.urlEncode(companyName, 'UTF-8');

        if (String.isNotBlank(taxId)) {
            searchUrl += '&regNo=' + EncodingUtil.urlEncode(taxId, 'UTF-8');
        }

        searchUrl += '&pageSize=1';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(searchUrl);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + authToken);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(15000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            return null;
        }

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> companies = (List<Object>) result.get('companies');
        if (companies != null && !companies.isEmpty()) {
            Map<String, Object> company = (Map<String, Object>) companies[0];
            return (String) company.get('id');
        }

        return null;
    }

    private static void parseCreditsafeResponse(CreditReport report, Map<String, Object> body) {
        Map<String, Object> reportData = (Map<String, Object>) body.get('report');
        if (reportData == null) {
            report.overallScore = 0;
            report.riskRating = 'Unknown';
            report.summary = 'No report data in Creditsafe response.';
            return;
        }

        // Company info
        Map<String, Object> companyInfo = (Map<String, Object>) reportData.get('companySummary');
        if (companyInfo != null) {
            report.companyName = (String) companyInfo.get('businessName');
            Object creditRating = companyInfo.get('creditRating');
            if (creditRating != null) {
                Map<String, Object> ratingMap = (Map<String, Object>) creditRating;
                Object commonVal = ratingMap.get('commonValue');
                if (commonVal != null) {
                    report.overallScore = Integer.valueOf(String.valueOf(commonVal));
                }
                report.riskRating = (String) ratingMap.get('commonDescription');
            }
        }

        // Credit score details
        Map<String, Object> creditScore = (Map<String, Object>) reportData.get('creditScore');
        if (creditScore != null) {
            Object currentRating = creditScore.get('currentCreditRating');
            if (currentRating != null) {
                Map<String, Object> currentMap = (Map<String, Object>) currentRating;
                Object scoreVal = currentMap.get('value');
                if (scoreVal != null && report.overallScore == null) {
                    report.overallScore = Integer.valueOf(String.valueOf(scoreVal));
                }
            }

            // Credit limit
            Object limitVal = creditScore.get('currentContractLimit');
            if (limitVal != null) {
                Map<String, Object> limitMap = (Map<String, Object>) limitVal;
                Object val = limitMap.get('value');
                if (val != null) {
                    report.recommendedCreditLimit = Decimal.valueOf(String.valueOf(val));
                }
            }
        }

        // Financial data
        Map<String, Object> financials = (Map<String, Object>) reportData.get('financialStatements');
        if (financials != null) {
            List<Object> statements = (List<Object>) financials.get('statements');
            if (statements != null && !statements.isEmpty()) {
                Map<String, Object> latest = (Map<String, Object>) statements[0];
                Map<String, Object> profitLoss = (Map<String, Object>) latest.get('profitAndLoss');
                if (profitLoss != null) {
                    Object revenue = profitLoss.get('revenue');
                    if (revenue != null) {
                        report.annualRevenue = Decimal.valueOf(String.valueOf(revenue));
                    }
                }
            }
        }

        // Payment data
        Map<String, Object> paymentData = (Map<String, Object>) reportData.get('paymentData');
        if (paymentData != null) {
            Object dbt = paymentData.get('dbt');
            if (dbt != null) {
                report.daysBeyondTerms = Integer.valueOf(String.valueOf(dbt));
            }
            Object totalExperiences = paymentData.get('totalTradeExperiences');
            if (totalExperiences != null) {
                report.tradePaymentExperiences = Integer.valueOf(String.valueOf(totalExperiences));
            }
        }

        // Derive risk rating if missing
        if (String.isBlank(report.riskRating) && report.overallScore != null) {
            if (report.overallScore >= 80) report.riskRating = 'Low';
            else if (report.overallScore >= 50) report.riskRating = 'Medium';
            else if (report.overallScore >= 25) report.riskRating = 'High';
            else report.riskRating = 'Very High';
        }

        report.summary = buildSummary(report);
    }

    // ===== MOCK REPORT GENERATOR =====

    @TestVisible
    private static CreditReport generateMockReport(ARF_Credit_Application__c app) {
        CreditReport report = new CreditReport();
        report.provider = 'Mock';
        report.reportDate = Date.today();
        report.companyName = app.Legal_Name__c;
        report.dunsNumber = String.isNotBlank(app.DUNS_Number__c) ? app.DUNS_Number__c : '00-000-0000';

        // Use company name hash for consistent mock data across calls
        Integer nameHash = Math.abs(app.Legal_Name__c != null ? app.Legal_Name__c.hashCode() : 0);
        Integer seed = Math.mod(nameHash, 1000);

        // Paydex Score: 1-100 (higher is better)
        report.paydexScore = 40 + Math.mod(seed, 55); // Range: 40-94

        // Financial Stress Score: 1001-1875 (higher is better)
        report.financialStressScore = 1001 + Math.mod(seed * 3, 874);

        // Overall score (weighted blend)
        report.overallScore = (Integer) Math.round(
            report.paydexScore * 0.5 + (report.financialStressScore - 1000) * 0.057
        );

        // Risk rating derived from paydex
        report.riskRating = deriveRiskRating(report.paydexScore, report.financialStressScore);

        // Annual revenue
        Decimal revenueBase = 500000 + Math.mod(seed * 7, 9500000);
        report.annualRevenue = revenueBase.setScale(0);

        // Employee count
        report.employeeCount = 5 + Math.mod(seed * 2, 495);

        // Years in business
        report.yearsInBusiness = 1 + Math.mod(seed, 30);

        // Trade payment experiences
        report.tradePaymentExperiences = 3 + Math.mod(seed, 47);

        // Days beyond terms
        report.daysBeyondTerms = Math.mod(seed, 30);

        // Recommended credit limit based on revenue and risk
        if (report.riskRating == 'Low') {
            report.recommendedCreditLimit = (report.annualRevenue * 0.15).setScale(0);
        } else if (report.riskRating == 'Medium') {
            report.recommendedCreditLimit = (report.annualRevenue * 0.10).setScale(0);
        } else if (report.riskRating == 'High') {
            report.recommendedCreditLimit = (report.annualRevenue * 0.05).setScale(0);
        } else {
            report.recommendedCreditLimit = 0;
        }

        // Payment trend
        if (report.paydexScore >= 80) {
            report.paymentTrend = 'Prompt';
        } else if (report.paydexScore >= 60) {
            report.paymentTrend = 'Slow 15 days';
        } else if (report.paydexScore >= 40) {
            report.paymentTrend = 'Slow 30 days';
        } else {
            report.paymentTrend = 'Slow 60+ days';
        }

        // Legal filings
        report.legalFilings = Math.mod(seed, 5) == 0 ? 1 : 0;
        report.liens = Math.mod(seed, 7) == 0 ? 1 : 0;
        report.bankruptcyFlag = Math.mod(seed, 20) == 0;

        report.summary = buildSummary(report);

        // Build mock raw JSON for reference
        report.rawResponseJson = JSON.serialize(new Map<String, Object>{
            'provider' => 'Mock',
            'generated' => Datetime.now().format(),
            'companyName' => report.companyName,
            'paydexScore' => report.paydexScore,
            'financialStressScore' => report.financialStressScore,
            'overallScore' => report.overallScore,
            'riskRating' => report.riskRating,
            'annualRevenue' => report.annualRevenue,
            'employeeCount' => report.employeeCount,
            'yearsInBusiness' => report.yearsInBusiness,
            'tradeExperiences' => report.tradePaymentExperiences,
            'daysBeyondTerms' => report.daysBeyondTerms,
            'recommendedCreditLimit' => report.recommendedCreditLimit,
            'paymentTrend' => report.paymentTrend,
            'legalFilings' => report.legalFilings,
            'liens' => report.liens,
            'bankruptcyFlag' => report.bankruptcyFlag
        });

        return report;
    }

    // ===== HELPER METHODS =====

    private static String deriveRiskRating(Integer paydexScore, Integer financialStressScore) {
        Integer effectivePaydex = paydexScore != null ? paydexScore : 0;
        Integer effectiveStress = financialStressScore != null ? financialStressScore : 1000;

        if (effectivePaydex >= 80 && effectiveStress >= 1400) return 'Low';
        if (effectivePaydex >= 60 && effectiveStress >= 1200) return 'Medium';
        if (effectivePaydex >= 40 || effectiveStress >= 1000) return 'High';
        return 'Very High';
    }

    private static String buildSummary(CreditReport report) {
        List<String> lines = new List<String>();
        lines.add('Provider: ' + report.provider);

        if (report.paydexScore != null) {
            lines.add('Paydex Score: ' + report.paydexScore + '/100');
        }
        if (report.financialStressScore != null) {
            lines.add('Financial Stress Score: ' + report.financialStressScore + '/1875');
        }
        if (report.riskRating != null) {
            lines.add('Risk Rating: ' + report.riskRating);
        }
        if (report.annualRevenue != null) {
            lines.add('Annual Revenue: $' + report.annualRevenue.setScale(0).format());
        }
        if (report.paymentTrend != null) {
            lines.add('Payment Trend: ' + report.paymentTrend);
        }
        if (report.recommendedCreditLimit != null) {
            lines.add('Recommended Credit Limit: $' + report.recommendedCreditLimit.setScale(0).format());
        }
        if (report.bankruptcyFlag) {
            lines.add('** BANKRUPTCY FLAG **');
        }

        return String.join(lines, '\n');
    }

    // ===== INNER CLASSES =====

    public class CreditReport {
        @AuraEnabled public String provider;
        @AuraEnabled public Date reportDate;
        @AuraEnabled public String companyName;
        @AuraEnabled public String dunsNumber;
        @AuraEnabled public Integer overallScore;
        @AuraEnabled public String riskRating;
        @AuraEnabled public Integer paydexScore;
        @AuraEnabled public Integer financialStressScore;
        @AuraEnabled public Decimal annualRevenue;
        @AuraEnabled public Integer employeeCount;
        @AuraEnabled public Integer yearsInBusiness;
        @AuraEnabled public Integer tradePaymentExperiences;
        @AuraEnabled public Integer daysBeyondTerms;
        @AuraEnabled public String paymentTrend;
        @AuraEnabled public Decimal recommendedCreditLimit;
        @AuraEnabled public Integer legalFilings;
        @AuraEnabled public Integer liens;
        @AuraEnabled public Boolean bankruptcyFlag;
        @AuraEnabled public String summary;
        @AuraEnabled public String rawResponseJson;
        @AuraEnabled public Id creditCheckId;

        public CreditReport() {
            this.bankruptcyFlag = false;
            this.legalFilings = 0;
            this.liens = 0;
        }
    }

    public class CreditBureauException extends Exception {}
}
