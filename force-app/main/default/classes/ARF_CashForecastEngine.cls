public with sharing class ARF_CashForecastEngine implements Database.Batchable<SObject>, Schedulable {

    @AuraEnabled
    public static ForecastResult generateForecasts() {
        ForecastResult result = new ForecastResult();
        result.predictionsCreated = 0;
        result.forecastsCreated = 0;
        result.totalForecastedAmount = 0;

        // Delete old predictions for invoices still open
        List<ARF_Payment_Prediction__c> oldPreds = [
            SELECT Id FROM ARF_Payment_Prediction__c
            WHERE Invoice__r.Status__c IN ('Open', 'Partially Paid')
            AND Actual_Pay_Date__c = null
        ];
        if (!oldPreds.isEmpty()) delete oldPreds;

        // Get open invoices
        List<ARF_Invoice__c> invoices = [
            SELECT Id, Amount__c, Balance__c, Due_Date__c, Days_Past_Due__c, Account__c
            FROM ARF_Invoice__c
            WHERE Status__c IN ('Open', 'Partially Paid')
            ORDER BY Account__c, Due_Date__c
        ];

        if (invoices.isEmpty()) return result;

        // Build account profiles in bulk
        Set<Id> accountIds = new Set<Id>();
        for (ARF_Invoice__c inv : invoices) {
            if (inv.Account__c != null) accountIds.add(inv.Account__c);
        }
        Map<Id, AccountPaymentProfile> profiles = buildProfilesBulk(accountIds);

        // Generate predictions
        List<ARF_Payment_Prediction__c> predictions = new List<ARF_Payment_Prediction__c>();
        for (ARF_Invoice__c inv : invoices) {
            AccountPaymentProfile profile = profiles.containsKey(inv.Account__c) ? profiles.get(inv.Account__c) : getDefaultProfile();
            PaymentPrediction pred = predictInvoice(inv, profile);

            ARF_Payment_Prediction__c record = new ARF_Payment_Prediction__c();
            record.Invoice__c = inv.Id;
            record.Account__c = inv.Account__c;
            record.Predicted_Pay_Date__c = pred.predictedDate;
            record.Predicted_Amount__c = pred.predictedAmount;
            record.Confidence__c = pred.confidence;
            record.Prediction_Method__c = pred.method;
            record.Prediction_Date__c = DateTime.now();
            record.Week_Bucket__c = pred.weekBucket;
            predictions.add(record);

            result.predictionsCreated++;
            result.totalForecastedAmount += pred.predictedAmount;
        }

        if (!predictions.isEmpty()) insert predictions;

        // Aggregate into weekly forecasts
        result.forecastsCreated = generateWeeklyForecasts(predictions);

        return result;
    }

    public static PaymentPrediction predictInvoice(ARF_Invoice__c invoice, AccountPaymentProfile profile) {
        PaymentPrediction pred = new PaymentPrediction();
        pred.invoiceId = invoice.Id;
        pred.predictedAmount = invoice.Balance__c;

        Date dueDate = invoice.Due_Date__c != null ? invoice.Due_Date__c : Date.today();
        Integer daysPastDue = invoice.Days_Past_Due__c != null ? (Integer) invoice.Days_Past_Due__c : 0;

        // Factor 1: Historical pattern (weight 40%)
        Decimal histDays;
        Decimal histConfidence;
        if (profile.paymentCount >= 5) {
            histDays = profile.avgDaysToPay;
            histConfidence = Math.min(90, 50 + profile.paymentCount * 2);
        } else if (profile.paymentCount > 0) {
            histDays = profile.avgDaysToPay;
            histConfidence = 30 + profile.paymentCount * 5;
        } else {
            histDays = 30;
            histConfidence = 20;
        }

        // Factor 2: Invoice Aging (weight 25%)
        Decimal agingDays;
        Decimal agingConfidence;
        if (daysPastDue <= 0) {
            agingDays = histDays;
            agingConfidence = 80;
        } else if (daysPastDue <= 30) {
            agingDays = 14;
            agingConfidence = 65;
        } else if (daysPastDue <= 60) {
            agingDays = 30;
            agingConfidence = 45;
        } else if (daysPastDue <= 90) {
            agingDays = 45;
            agingConfidence = 30;
        } else {
            agingDays = 90;
            agingConfidence = 15;
        }

        // Factor 3: Account risk (weight 20%)
        Decimal riskAdjustment = 0;
        Decimal riskConfAdj = 0;
        // Query risk score from account
        List<Account> accts = [SELECT ARF_Risk_Score__c FROM Account WHERE Id = :invoice.Account__c LIMIT 1];
        Decimal riskScore = (!accts.isEmpty() && accts[0].ARF_Risk_Score__c != null) ? accts[0].ARF_Risk_Score__c : 50;
        if (riskScore < 30) { riskAdjustment = -5; riskConfAdj = 10; }
        else if (riskScore < 60) { riskAdjustment = 0; riskConfAdj = 0; }
        else if (riskScore < 80) { riskAdjustment = 10; riskConfAdj = -10; }
        else { riskAdjustment = 20; riskConfAdj = -20; }

        // Factor 4: Payment Amount (weight 15%)
        Decimal amountAdjustment = 0;
        if (invoice.Balance__c >= 50000) amountAdjustment = 15;
        else if (invoice.Balance__c >= 10000) amountAdjustment = 10;
        else if (invoice.Balance__c >= 1000) amountAdjustment = 5;

        // Calculate weighted prediction
        Decimal weightedDays;
        if (daysPastDue > 0) {
            weightedDays = (agingDays * 0.50) + (histDays * 0.25) + (riskAdjustment * 0.15) + (amountAdjustment * 0.10);
        } else {
            weightedDays = (histDays * 0.40) + (agingDays * 0.25) + (riskAdjustment * 0.20) + (amountAdjustment * 0.15);
        }

        Date baseDate = daysPastDue > 0 ? Date.today() : dueDate;
        pred.predictedDate = baseDate.addDays(Math.max(1, (Integer) weightedDays.round()));

        // Confidence (weighted average)
        pred.confidence = Math.max(5, Math.min(95,
            (histConfidence * 0.40) + (agingConfidence * 0.25) + ((70 + riskConfAdj) * 0.20) + (70 * 0.15)
        ));

        pred.method = 'Multi-Factor(' + profile.paymentCount + ' hist, ' + daysPastDue + 'd aging, ' + riskScore.setScale(0) + ' risk)';

        // Week bucket
        Integer daysFromNow = Date.today().daysBetween(pred.predictedDate);
        Integer weekNum = (Integer) Math.ceil(daysFromNow / 7.0);
        if (weekNum <= 0) weekNum = 1;
        pred.weekBucket = weekNum <= 12 ? 'Week ' + weekNum : 'Beyond 12 Weeks';

        return pred;
    }

    public static Map<Id, AccountPaymentProfile> buildProfilesBulk(Set<Id> accountIds) {
        Map<Id, AccountPaymentProfile> profiles = new Map<Id, AccountPaymentProfile>();

        // Get payment applications with dates
        List<ARF_Payment_Application__c> applications = [
            SELECT Id, Payment__r.Payment_Date__c, Invoice__r.Due_Date__c, Invoice__r.Account__c, Amount_Applied__c
            FROM ARF_Payment_Application__c
            WHERE Invoice__r.Account__c IN :accountIds
            AND Payment__r.Payment_Date__c != null
            AND Invoice__r.Due_Date__c != null
            ORDER BY Invoice__r.Account__c, Payment__r.Payment_Date__c DESC
            LIMIT 2000
        ];

        // Group by account
        Map<Id, List<Integer>> daysByAccount = new Map<Id, List<Integer>>();
        for (ARF_Payment_Application__c pa : applications) {
            Id acctId = pa.Invoice__r.Account__c;
            if (!daysByAccount.containsKey(acctId)) {
                daysByAccount.put(acctId, new List<Integer>());
            }
            Integer days = pa.Invoice__r.Due_Date__c.daysBetween(pa.Payment__r.Payment_Date__c);
            daysByAccount.get(acctId).add(days);
        }

        for (Id acctId : accountIds) {
            AccountPaymentProfile profile = new AccountPaymentProfile();
            List<Integer> days = daysByAccount.get(acctId);

            if (days != null && !days.isEmpty()) {
                profile.paymentCount = days.size();

                // Average
                Decimal sum = 0;
                for (Integer d : days) sum += d;
                profile.avgDaysToPay = sum / days.size();

                // Median
                days.sort();
                Integer mid = days.size() / 2;
                profile.medianDaysToPay = days.size() > 1 && Math.mod(days.size(), 2) == 0
                    ? (days[mid - 1] + days[mid]) / 2.0
                    : days[mid];

                // Std deviation
                Decimal sumSqDiff = 0;
                for (Integer d : days) {
                    Decimal diff = d - profile.avgDaysToPay;
                    sumSqDiff += diff * diff;
                }
                profile.stdDeviation = Math.sqrt(sumSqDiff / days.size());

                // Consistency (lower std dev = higher score, max 100)
                profile.consistencyScore = Math.max(0, Math.min(100, 100 - profile.stdDeviation * 2));

                // Trend (compare recent 5 vs older 5)
                if (days.size() >= 10) {
                    Decimal recentAvg = 0;
                    Decimal olderAvg = 0;
                    for (Integer i = 0; i < 5; i++) recentAvg += days[i];
                    for (Integer i = 5; i < 10; i++) olderAvg += days[i];
                    recentAvg /= 5; olderAvg /= 5;
                    if (recentAvg < olderAvg - 3) profile.trend = 'improving';
                    else if (recentAvg > olderAvg + 3) profile.trend = 'deteriorating';
                    else profile.trend = 'stable';
                } else {
                    profile.trend = 'insufficient_data';
                }
            } else {
                profile.paymentCount = 0;
                profile.avgDaysToPay = 30;
                profile.medianDaysToPay = 30;
                profile.stdDeviation = 15;
                profile.consistencyScore = 50;
                profile.trend = 'no_history';
            }
            profiles.put(acctId, profile);
        }

        return profiles;
    }

    public static AccountPaymentProfile getDefaultProfile() {
        AccountPaymentProfile p = new AccountPaymentProfile();
        p.avgDaysToPay = 30; p.medianDaysToPay = 30; p.stdDeviation = 15;
        p.consistencyScore = 50; p.paymentCount = 0; p.trend = 'no_history';
        return p;
    }

    private static Integer generateWeeklyForecasts(List<ARF_Payment_Prediction__c> predictions) {
        // Delete existing future forecasts
        List<ARF_Cash_Forecast__c> oldForecasts = [
            SELECT Id FROM ARF_Cash_Forecast__c
            WHERE Forecast_Date__c >= TODAY AND Period_Type__c = 'Weekly'
        ];
        if (!oldForecasts.isEmpty()) delete oldForecasts;

        // Group predictions by week
        Map<String, List<ARF_Payment_Prediction__c>> byWeek = new Map<String, List<ARF_Payment_Prediction__c>>();
        for (ARF_Payment_Prediction__c pred : predictions) {
            String bucket = pred.Week_Bucket__c;
            if (!byWeek.containsKey(bucket)) {
                byWeek.put(bucket, new List<ARF_Payment_Prediction__c>());
            }
            byWeek.get(bucket).add(pred);
        }

        List<ARF_Cash_Forecast__c> forecasts = new List<ARF_Cash_Forecast__c>();
        Date weekStart = Date.today().toStartOfWeek().addDays(1); // Monday

        for (Integer w = 1; w <= 12; w++) {
            String bucket = 'Week ' + w;
            List<ARF_Payment_Prediction__c> weekPreds = byWeek.get(bucket);

            ARF_Cash_Forecast__c fc = new ARF_Cash_Forecast__c();
            fc.Forecast_Date__c = weekStart.addDays((w - 1) * 7);
            fc.Period_Type__c = 'Weekly';
            fc.Generated_Date__c = DateTime.now();
            fc.Predicted_Collections__c = 0;
            fc.High_Confidence_Amount__c = 0;
            fc.Medium_Confidence_Amount__c = 0;
            fc.Low_Confidence_Amount__c = 0;
            fc.Invoice_Count__c = 0;

            if (weekPreds != null) {
                fc.Invoice_Count__c = weekPreds.size();
                for (ARF_Payment_Prediction__c pred : weekPreds) {
                    Decimal amt = pred.Predicted_Amount__c != null ? pred.Predicted_Amount__c : 0;
                    fc.Predicted_Collections__c += amt;
                    if (pred.Confidence__c >= 80) fc.High_Confidence_Amount__c += amt;
                    else if (pred.Confidence__c >= 50) fc.Medium_Confidence_Amount__c += amt;
                    else fc.Low_Confidence_Amount__c += amt;
                }
            }
            forecasts.add(fc);
        }

        if (!forecasts.isEmpty()) insert forecasts;
        return forecasts.size();
    }

    @AuraEnabled(cacheable=true)
    public static ForecastDashboard getDashboard(String periodType, Integer periodsAhead) {
        ForecastDashboard dashboard = new ForecastDashboard();
        dashboard.totalForecast = 0;
        dashboard.highConfidenceTotal = 0;
        dashboard.accuracy = 0;

        String pType = String.isNotBlank(periodType) ? periodType : 'Weekly';
        Integer periods = periodsAhead != null ? periodsAhead : 12;

        List<ARF_Cash_Forecast__c> forecasts = [
            SELECT Id, Forecast_Date__c, Predicted_Collections__c,
                   Actual_Collections__c, High_Confidence_Amount__c,
                   Medium_Confidence_Amount__c, Low_Confidence_Amount__c, Invoice_Count__c
            FROM ARF_Cash_Forecast__c
            WHERE Period_Type__c = :pType AND Forecast_Date__c >= TODAY
            ORDER BY Forecast_Date__c ASC
            LIMIT :periods
        ];

        dashboard.periods = new List<ForecastPeriod>();
        for (ARF_Cash_Forecast__c fc : forecasts) {
            ForecastPeriod period = new ForecastPeriod();
            period.startDate = fc.Forecast_Date__c;
            period.endDate = fc.Forecast_Date__c.addDays(pType == 'Weekly' ? 6 : pType == 'Monthly' ? 29 : 0);
            period.label = pType == 'Weekly'
                ? fc.Forecast_Date__c.format() + ' - ' + period.endDate.format()
                : fc.Forecast_Date__c.format();
            period.predicted = fc.Predicted_Collections__c;
            period.highConfidence = fc.High_Confidence_Amount__c;
            period.mediumConfidence = fc.Medium_Confidence_Amount__c;
            period.lowConfidence = fc.Low_Confidence_Amount__c;
            period.invoiceCount = fc.Invoice_Count__c != null ? (Integer) fc.Invoice_Count__c : 0;
            dashboard.periods.add(period);

            dashboard.totalForecast += fc.Predicted_Collections__c;
            dashboard.highConfidenceTotal += fc.High_Confidence_Amount__c;
        }

        // Calculate accuracy from past predictions
        AccuracyMetrics acc = getAccuracyMetrics();
        dashboard.accuracy = acc.overallAccuracy;

        return dashboard;
    }

    @AuraEnabled(cacheable=true)
    public static AccuracyMetrics getAccuracyMetrics() {
        AccuracyMetrics metrics = new AccuracyMetrics();
        metrics.overallAccuracy = 0;
        metrics.avgDaysOff = 0;
        metrics.withinOneWeek = 0;
        metrics.withinTwoWeeks = 0;
        metrics.totalPredictions = 0;

        List<ARF_Payment_Prediction__c> completed = [
            SELECT Id, Predicted_Pay_Date__c, Actual_Pay_Date__c, Accuracy_Days__c
            FROM ARF_Payment_Prediction__c
            WHERE Actual_Pay_Date__c != null
            AND Predicted_Pay_Date__c != null
            LIMIT 1000
        ];

        if (completed.isEmpty()) return metrics;

        metrics.totalPredictions = completed.size();
        Decimal totalDaysOff = 0;
        Integer within7 = 0;
        Integer within14 = 0;

        for (ARF_Payment_Prediction__c pred : completed) {
            Integer daysOff = Math.abs(pred.Predicted_Pay_Date__c.daysBetween(pred.Actual_Pay_Date__c));
            totalDaysOff += daysOff;
            if (daysOff <= 7) within7++;
            if (daysOff <= 14) within14++;
        }

        metrics.avgDaysOff = (totalDaysOff / metrics.totalPredictions).setScale(1);
        metrics.withinOneWeek = (within7 * 100.0 / metrics.totalPredictions).setScale(1);
        metrics.withinTwoWeeks = (within14 * 100.0 / metrics.totalPredictions).setScale(1);
        metrics.overallAccuracy = metrics.withinTwoWeeks;

        return metrics;
    }

    // ─── Batchable Interface ───
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id, Amount__c, Balance__c, Due_Date__c, Days_Past_Due__c, Account__c ' +
            'FROM ARF_Invoice__c WHERE Status__c IN (\'Open\', \'Partially Paid\')'
        );
    }

    public void execute(Database.BatchableContext bc, List<ARF_Invoice__c> invoices) {
        Set<Id> accountIds = new Set<Id>();
        for (ARF_Invoice__c inv : invoices) {
            if (inv.Account__c != null) accountIds.add(inv.Account__c);
        }
        Map<Id, AccountPaymentProfile> profiles = buildProfilesBulk(accountIds);

        List<ARF_Payment_Prediction__c> predictions = new List<ARF_Payment_Prediction__c>();
        for (ARF_Invoice__c inv : invoices) {
            AccountPaymentProfile profile = profiles.containsKey(inv.Account__c) ? profiles.get(inv.Account__c) : getDefaultProfile();
            PaymentPrediction pred = predictInvoice(inv, profile);

            ARF_Payment_Prediction__c record = new ARF_Payment_Prediction__c();
            record.Invoice__c = inv.Id;
            record.Account__c = inv.Account__c;
            record.Predicted_Pay_Date__c = pred.predictedDate;
            record.Predicted_Amount__c = pred.predictedAmount;
            record.Confidence__c = pred.confidence;
            record.Prediction_Method__c = pred.method;
            record.Prediction_Date__c = DateTime.now();
            record.Week_Bucket__c = pred.weekBucket;
            predictions.add(record);
        }

        if (!predictions.isEmpty()) insert predictions;
    }

    public void finish(Database.BatchableContext bc) {
        // Generate aggregate forecasts from all predictions made in this batch run
        List<ARF_Payment_Prediction__c> allPreds = [
            SELECT Id, Week_Bucket__c, Predicted_Amount__c, Confidence__c, Predicted_Pay_Date__c
            FROM ARF_Payment_Prediction__c
            WHERE Actual_Pay_Date__c = null
        ];
        if (!allPreds.isEmpty()) generateWeeklyForecasts(allPreds);
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new ARF_CashForecastEngine(), 200);
    }

    // ─── Inner Classes ───
    public class PaymentPrediction {
        @AuraEnabled public Id invoiceId;
        @AuraEnabled public Date predictedDate;
        @AuraEnabled public Decimal predictedAmount;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String method;
        @AuraEnabled public String weekBucket;
    }

    public class AccountPaymentProfile {
        @AuraEnabled public Decimal avgDaysToPay;
        @AuraEnabled public Decimal medianDaysToPay;
        @AuraEnabled public Decimal stdDeviation;
        @AuraEnabled public Decimal consistencyScore;
        @AuraEnabled public Integer paymentCount;
        @AuraEnabled public String trend;
    }

    public class ForecastDashboard {
        @AuraEnabled public List<ForecastPeriod> periods;
        @AuraEnabled public Decimal totalForecast;
        @AuraEnabled public Decimal highConfidenceTotal;
        @AuraEnabled public Decimal accuracy;
    }

    public class ForecastPeriod {
        @AuraEnabled public String label;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Decimal predicted;
        @AuraEnabled public Decimal highConfidence;
        @AuraEnabled public Decimal mediumConfidence;
        @AuraEnabled public Decimal lowConfidence;
        @AuraEnabled public Integer invoiceCount;
    }

    public class AccuracyMetrics {
        @AuraEnabled public Decimal overallAccuracy;
        @AuraEnabled public Decimal avgDaysOff;
        @AuraEnabled public Decimal withinOneWeek;
        @AuraEnabled public Decimal withinTwoWeeks;
        @AuraEnabled public Integer totalPredictions;
    }

    public class ForecastResult {
        @AuraEnabled public Integer predictionsCreated;
        @AuraEnabled public Integer forecastsCreated;
        @AuraEnabled public Decimal totalForecastedAmount;
    }
}
