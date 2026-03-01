public with sharing class ARF_CreditScoringEngine {

    private static final Integer MAX_BUSINESS_MATURITY = 200;
    private static final Integer MAX_FINANCIAL_SCALE = 200;
    private static final Integer MAX_REFERENCE_QUALITY = 200;
    private static final Integer MAX_CREDIT_REQUEST_RATIO = 150;
    private static final Integer MAX_EXTERNAL_CREDIT = 150;
    private static final Integer MAX_COMPLETENESS = 100;

    public static Map<String, Object> evaluateApplication(Id applicationId) {
        ARF_Credit_Application__c app = [
            SELECT Id, Years_In_Business__c, Annual_Revenue__c,
                   Requested_Credit_Limit__c, AP_Contact_Name__c,
                   Federal_Tax_ID__c, DUNS_Number__c
            FROM ARF_Credit_Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];

        // Count references and guarantors via separate queries
        Integer tradeRefCount = [SELECT COUNT() FROM ARF_Trade_Reference__c WHERE Credit_Application__c = :applicationId];
        Integer bankRefCount = [SELECT COUNT() FROM ARF_Bank_Reference__c WHERE Credit_Application__c = :applicationId];
        Integer guarantorCount = [SELECT COUNT() FROM ARF_Personal_Guarantor__c WHERE Credit_Application__c = :applicationId];

        List<ARF_Credit_Check__c> creditChecks = [
            SELECT Id, Agency__c, Paydex_Score__c, Financial_Stress_Score__c, Status__c
            FROM ARF_Credit_Check__c
            WHERE Credit_Application__c = :applicationId
              AND Status__c = 'Completed'
            ORDER BY CreatedDate DESC
        ];

        Integer totalScore = 0;
        List<String> factors = new List<String>();

        // 1. Business Maturity (200 pts max)
        Integer maturityScore = scoreBusinessMaturity(app.Years_In_Business__c);
        totalScore += maturityScore;
        factors.add('Business Maturity: ' + maturityScore + '/' + MAX_BUSINESS_MATURITY
            + ' (' + formatYears(app.Years_In_Business__c) + ' years in business)');

        // 2. Financial Scale (200 pts max)
        Integer financialScore = scoreFinancialScale(app.Annual_Revenue__c);
        totalScore += financialScore;
        factors.add('Financial Scale: ' + financialScore + '/' + MAX_FINANCIAL_SCALE
            + ' (Annual revenue: ' + formatCurrency(app.Annual_Revenue__c) + ')');

        // 3. Reference Quality (200 pts max)
        Integer referenceScore = scoreReferenceQuality(tradeRefCount, bankRefCount);
        totalScore += referenceScore;
        factors.add('Reference Quality: ' + referenceScore + '/' + MAX_REFERENCE_QUALITY
            + ' (' + tradeRefCount + ' trade refs, ' + bankRefCount + ' bank refs)');

        // 4. Credit Request Ratio (150 pts max)
        Integer ratioScore = scoreCreditRequestRatio(app.Requested_Credit_Limit__c, app.Annual_Revenue__c);
        totalScore += ratioScore;
        Decimal ratio = calculateRatio(app.Requested_Credit_Limit__c, app.Annual_Revenue__c);
        factors.add('Credit Request Ratio: ' + ratioScore + '/' + MAX_CREDIT_REQUEST_RATIO
            + ' (Requested/Revenue ratio: ' + formatPercent(ratio) + ')');

        // 5. External Credit (150 pts max)
        Integer externalScore = scoreExternalCredit(creditChecks);
        totalScore += externalScore;
        factors.add('External Credit: ' + externalScore + '/' + MAX_EXTERNAL_CREDIT
            + ' (' + creditChecks.size() + ' completed credit check(s))');

        // 6. Completeness (100 pts max)
        Integer completenessScore = scoreCompleteness(app, guarantorCount);
        totalScore += completenessScore;
        factors.add('Completeness: ' + completenessScore + '/' + MAX_COMPLETENESS);

        String riskRating = determineRiskRating(totalScore);

        app.Credit_Score__c = totalScore;
        app.Risk_Rating__c = riskRating;
        update app;

        Map<String, Object> result = new Map<String, Object>();
        result.put('score', totalScore);
        result.put('rating', riskRating);
        result.put('factors', factors);
        return result;
    }

    public static String getRecommendedCreditLimit(Id applicationId) {
        ARF_Credit_Application__c app = [
            SELECT Id, Risk_Rating__c, Annual_Revenue__c, Requested_Credit_Limit__c
            FROM ARF_Credit_Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];

        if (app.Risk_Rating__c == null) {
            return 'Application has not been scored yet.';
        }

        Decimal revenue = app.Annual_Revenue__c != null ? app.Annual_Revenue__c : 0;
        Decimal requested = app.Requested_Credit_Limit__c != null ? app.Requested_Credit_Limit__c : 0;
        Decimal recommendedLimit;

        if (app.Risk_Rating__c == 'Low') {
            recommendedLimit = Math.min(requested, revenue * 0.15);
        } else if (app.Risk_Rating__c == 'Medium') {
            recommendedLimit = Math.min(requested, revenue * 0.10);
        } else if (app.Risk_Rating__c == 'High') {
            recommendedLimit = Math.min(requested, revenue * 0.05);
        } else {
            return '$0 — Recommend decline. Risk rating: Very High.';
        }

        return '$' + recommendedLimit.setScale(2).format()
            + ' (Risk: ' + app.Risk_Rating__c
            + ', Requested: $' + requested.setScale(2).format() + ')';
    }

    public static void runCreditCheck(Id applicationId, String agency) {
        Integer simulatedPaydex = 70 + (Integer) (Math.random() * 30);
        Integer simulatedStress = 1000 + (Integer) (Math.random() * 600);

        ARF_Credit_Check__c chk = new ARF_Credit_Check__c(
            Credit_Application__c = applicationId,
            Agency__c = agency,
            Status__c = 'Pending',
            Report_Date__c = Date.today(),
            Paydex_Score__c = simulatedPaydex,
            Financial_Stress_Score__c = simulatedStress
        );
        insert chk;
    }

    // ===== SCORING HELPERS =====

    @TestVisible
    private static Integer scoreBusinessMaturity(Decimal yearsInBusiness) {
        if (yearsInBusiness == null || yearsInBusiness < 0) return 0;
        if (yearsInBusiness > 10) return 200;
        if (yearsInBusiness >= 6) return 150;
        if (yearsInBusiness >= 2) return 100;
        return 50;
    }

    @TestVisible
    private static Integer scoreFinancialScale(Decimal annualRevenue) {
        if (annualRevenue == null || annualRevenue <= 0) return 0;
        if (annualRevenue >= 10000000) return 200;
        if (annualRevenue >= 1000000) return 150;
        if (annualRevenue >= 100000) return 100;
        return 50;
    }

    @TestVisible
    private static Integer scoreReferenceQuality(Integer tradeRefCount, Integer bankRefCount) {
        Integer score = 0;
        if (tradeRefCount >= 3) score += 150;
        else if (tradeRefCount == 2) score += 100;
        else if (tradeRefCount == 1) score += 50;

        if (bankRefCount > 0) score += 50;
        return score;
    }

    @TestVisible
    private static Integer scoreCreditRequestRatio(Decimal requested, Decimal revenue) {
        if (revenue == null || revenue <= 0 || requested == null) return 20;
        Decimal ratio = (requested / revenue) * 100;
        if (ratio < 5) return 150;
        if (ratio < 15) return 120;
        if (ratio < 30) return 80;
        if (ratio <= 50) return 50;
        return 20;
    }

    @TestVisible
    private static Integer scoreExternalCredit(List<ARF_Credit_Check__c> creditChecks) {
        if (creditChecks == null || creditChecks.isEmpty()) {
            return 50;
        }

        Integer score = 0;
        ARF_Credit_Check__c latest = creditChecks[0];

        if (latest.Paydex_Score__c != null) {
            Decimal paydex = latest.Paydex_Score__c;
            if (paydex >= 80) score += 75;
            else if (paydex >= 60) score += 50;
            else score += 25;
        }

        if (latest.Financial_Stress_Score__c != null) {
            Decimal stressScore = latest.Financial_Stress_Score__c;
            if (stressScore >= 1400) score += 75;
            else if (stressScore >= 1000) score += 50;
            else score += 25;
        }

        return score;
    }

    @TestVisible
    private static Integer scoreCompleteness(ARF_Credit_Application__c app, Integer guarantorCount) {
        Integer score = 0;
        if (String.isNotBlank(app.AP_Contact_Name__c)) score += 25;
        if (guarantorCount > 0) score += 25;
        if (String.isNotBlank(app.Federal_Tax_ID__c)) score += 25;
        if (String.isNotBlank(app.DUNS_Number__c)) score += 25;
        return score;
    }

    @TestVisible
    private static String determineRiskRating(Integer score) {
        if (score >= 800) return 'Low';
        if (score >= 600) return 'Medium';
        if (score >= 400) return 'High';
        return 'Very High';
    }

    private static String formatYears(Decimal years) {
        if (years == null) return '0';
        return String.valueOf(years.intValue());
    }

    private static String formatCurrency(Decimal amount) {
        if (amount == null) return '$0';
        return '$' + amount.setScale(0).format();
    }

    private static Decimal calculateRatio(Decimal requested, Decimal revenue) {
        if (revenue == null || revenue <= 0 || requested == null) return 0;
        return (requested / revenue) * 100;
    }

    private static String formatPercent(Decimal pct) {
        if (pct == null) return '0%';
        return pct.setScale(1) + '%';
    }
}
