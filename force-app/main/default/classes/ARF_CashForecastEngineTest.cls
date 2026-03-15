@isTest
private class ARF_CashForecastEngineTest {

    @TestSetup
    static void setup() {
        // Create 2 accounts with different risk profiles
        Account accLowRisk = new Account(
            Name = 'Low Risk Corp',
            ARF_Risk_Score__c = 20
        );
        Account accHighRisk = new Account(
            Name = 'High Risk Corp',
            ARF_Risk_Score__c = 85
        );
        insert new List<Account>{ accLowRisk, accHighRisk };

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();

        // 5 invoices for Low Risk account - various due dates and amounts
        invoices.add(new ARF_Invoice__c(
            Account__c = accLowRisk.Id, Amount__c = 5000, Balance__c = 5000,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(10),
            Invoice_Date__c = Date.today().addDays(-20),
            Document_Number__c = 'INV-FC-001'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = accLowRisk.Id, Amount__c = 12000, Balance__c = 12000,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(-5),
            Invoice_Date__c = Date.today().addDays(-35),
            Document_Number__c = 'INV-FC-002'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = accLowRisk.Id, Amount__c = 800, Balance__c = 800,
            Status__c = 'Partially Paid', Due_Date__c = Date.today().addDays(-15),
            Invoice_Date__c = Date.today().addDays(-45),
            Document_Number__c = 'INV-FC-003'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = accLowRisk.Id, Amount__c = 55000, Balance__c = 55000,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(30),
            Invoice_Date__c = Date.today().addDays(-10),
            Document_Number__c = 'INV-FC-004'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = accLowRisk.Id, Amount__c = 2500, Balance__c = 2500,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(-45),
            Invoice_Date__c = Date.today().addDays(-75),
            Document_Number__c = 'INV-FC-005'
        ));

        // 5 invoices for High Risk account
        invoices.add(new ARF_Invoice__c(
            Account__c = accHighRisk.Id, Amount__c = 3000, Balance__c = 3000,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(5),
            Invoice_Date__c = Date.today().addDays(-25),
            Document_Number__c = 'INV-FC-006'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = accHighRisk.Id, Amount__c = 75000, Balance__c = 75000,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(-10),
            Invoice_Date__c = Date.today().addDays(-40),
            Document_Number__c = 'INV-FC-007'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = accHighRisk.Id, Amount__c = 1500, Balance__c = 1500,
            Status__c = 'Partially Paid', Due_Date__c = Date.today().addDays(-70),
            Invoice_Date__c = Date.today().addDays(-100),
            Document_Number__c = 'INV-FC-008'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = accHighRisk.Id, Amount__c = 9000, Balance__c = 9000,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(20),
            Invoice_Date__c = Date.today().addDays(-10),
            Document_Number__c = 'INV-FC-009'
        ));
        invoices.add(new ARF_Invoice__c(
            Account__c = accHighRisk.Id, Amount__c = 400, Balance__c = 400,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(-100),
            Invoice_Date__c = Date.today().addDays(-130),
            Document_Number__c = 'INV-FC-010'
        ));
        insert invoices;

        // Create historical paid invoices and payments for Low Risk account to build payment profiles
        List<ARF_Invoice__c> paidInvoices = new List<ARF_Invoice__c>();
        for (Integer i = 1; i <= 6; i++) {
            paidInvoices.add(new ARF_Invoice__c(
                Account__c = accLowRisk.Id,
                Amount__c = 1000 * i,
                Balance__c = 0,
                Status__c = 'Paid',
                Due_Date__c = Date.today().addDays(-30 * i),
                Invoice_Date__c = Date.today().addDays(-60 * i),
                Document_Number__c = 'INV-HIST-' + String.valueOf(i).leftPad(3, '0')
            ));
        }
        insert paidInvoices;

        // Create payments for the paid invoices (Low Risk pays ~5 days after due date)
        List<ARF_Payment__c> payments = new List<ARF_Payment__c>();
        for (Integer i = 0; i < paidInvoices.size(); i++) {
            payments.add(new ARF_Payment__c(
                Account__c = accLowRisk.Id,
                Amount__c = paidInvoices[i].Amount__c,
                Payment_Date__c = paidInvoices[i].Due_Date__c.addDays(3 + Math.mod(i, 5)),
                Status__c = 'Applied',
                Method__c = 'Check'
            ));
        }
        insert payments;

        // Create payment applications linking payments to invoices
        List<ARF_Payment_Application__c> applications = new List<ARF_Payment_Application__c>();
        for (Integer i = 0; i < payments.size(); i++) {
            applications.add(new ARF_Payment_Application__c(
                Payment__c = payments[i].Id,
                Invoice__c = paidInvoices[i].Id,
                Amount_Applied__c = paidInvoices[i].Amount__c
            ));
        }
        insert applications;

        // Create a few payment applications for High Risk account (less history)
        List<ARF_Invoice__c> hrPaidInvoices = new List<ARF_Invoice__c>();
        for (Integer i = 1; i <= 2; i++) {
            hrPaidInvoices.add(new ARF_Invoice__c(
                Account__c = accHighRisk.Id,
                Amount__c = 2000 * i,
                Balance__c = 0,
                Status__c = 'Paid',
                Due_Date__c = Date.today().addDays(-40 * i),
                Invoice_Date__c = Date.today().addDays(-70 * i),
                Document_Number__c = 'INV-HR-HIST-' + String.valueOf(i).leftPad(3, '0')
            ));
        }
        insert hrPaidInvoices;

        List<ARF_Payment__c> hrPayments = new List<ARF_Payment__c>();
        for (Integer i = 0; i < hrPaidInvoices.size(); i++) {
            hrPayments.add(new ARF_Payment__c(
                Account__c = accHighRisk.Id,
                Amount__c = hrPaidInvoices[i].Amount__c,
                Payment_Date__c = hrPaidInvoices[i].Due_Date__c.addDays(15 + i * 5),
                Status__c = 'Applied',
                Method__c = 'ACH'
            ));
        }
        insert hrPayments;

        List<ARF_Payment_Application__c> hrApps = new List<ARF_Payment_Application__c>();
        for (Integer i = 0; i < hrPayments.size(); i++) {
            hrApps.add(new ARF_Payment_Application__c(
                Payment__c = hrPayments[i].Id,
                Invoice__c = hrPaidInvoices[i].Id,
                Amount_Applied__c = hrPaidInvoices[i].Amount__c
            ));
        }
        insert hrApps;
    }

    @isTest
    static void testPredictInvoiceWithHistory() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Low Risk Corp' LIMIT 1];
        ARF_Invoice__c inv = [
            SELECT Id, Amount__c, Balance__c, Due_Date__c, Days_Past_Due__c, Account__c
            FROM ARF_Invoice__c
            WHERE Document_Number__c = 'INV-FC-001'
            LIMIT 1
        ];

        Set<Id> acctIds = new Set<Id>{ acc.Id };
        Map<Id, ARF_CashForecastEngine.AccountPaymentProfile> profiles =
            ARF_CashForecastEngine.buildProfilesBulk(acctIds);

        Test.startTest();
        ARF_CashForecastEngine.PaymentPrediction pred =
            ARF_CashForecastEngine.predictInvoice(inv, profiles.get(acc.Id));
        Test.stopTest();

        System.assertNotEquals(null, pred, 'Prediction should not be null');
        System.assertNotEquals(null, pred.predictedDate, 'Predicted date should be set');
        System.assertEquals(inv.Balance__c, pred.predictedAmount, 'Predicted amount should equal balance');
        System.assert(pred.confidence > 0, 'Confidence should be positive');
        System.assert(pred.confidence <= 95, 'Confidence should not exceed 95');
        System.assert(String.isNotBlank(pred.method), 'Method should be populated');
        System.assert(String.isNotBlank(pred.weekBucket), 'Week bucket should be populated');
    }

    @isTest
    static void testPredictInvoicePastDue() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'High Risk Corp' LIMIT 1];
        ARF_Invoice__c inv = [
            SELECT Id, Amount__c, Balance__c, Due_Date__c, Days_Past_Due__c, Account__c
            FROM ARF_Invoice__c
            WHERE Document_Number__c = 'INV-FC-008'
            LIMIT 1
        ];

        ARF_CashForecastEngine.AccountPaymentProfile defaultProfile =
            ARF_CashForecastEngine.getDefaultProfile();

        Test.startTest();
        ARF_CashForecastEngine.PaymentPrediction pred =
            ARF_CashForecastEngine.predictInvoice(inv, defaultProfile);
        Test.stopTest();

        System.assertNotEquals(null, pred.predictedDate, 'Should have a predicted date');
        System.assert(pred.predictedDate >= Date.today(), 'Predicted date should be in the future');
        System.assert(pred.confidence <= 50, 'Confidence for very past due high risk should be low');
    }

    @isTest
    static void testPredictInvoiceLargeAmount() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'High Risk Corp' LIMIT 1];
        ARF_Invoice__c inv = [
            SELECT Id, Amount__c, Balance__c, Due_Date__c, Days_Past_Due__c, Account__c
            FROM ARF_Invoice__c
            WHERE Document_Number__c = 'INV-FC-007'
            LIMIT 1
        ];

        ARF_CashForecastEngine.AccountPaymentProfile profile =
            ARF_CashForecastEngine.getDefaultProfile();

        Test.startTest();
        ARF_CashForecastEngine.PaymentPrediction pred =
            ARF_CashForecastEngine.predictInvoice(inv, profile);
        Test.stopTest();

        System.assertEquals(75000, pred.predictedAmount, 'Should predict full balance');
        System.assert(pred.method.contains('risk'), 'Method should reference risk score');
    }

    @isTest
    static void testBuildProfilesBulk() {
        Account accLow = [SELECT Id FROM Account WHERE Name = 'Low Risk Corp' LIMIT 1];
        Account accHigh = [SELECT Id FROM Account WHERE Name = 'High Risk Corp' LIMIT 1];

        Test.startTest();
        Map<Id, ARF_CashForecastEngine.AccountPaymentProfile> profiles =
            ARF_CashForecastEngine.buildProfilesBulk(new Set<Id>{ accLow.Id, accHigh.Id });
        Test.stopTest();

        // Low Risk should have 6 payment history records
        ARF_CashForecastEngine.AccountPaymentProfile lowProfile = profiles.get(accLow.Id);
        System.assertNotEquals(null, lowProfile, 'Low risk profile should exist');
        System.assertEquals(6, lowProfile.paymentCount, 'Should have 6 payment records');
        System.assert(lowProfile.avgDaysToPay > 0, 'Average days to pay should be positive');
        System.assert(lowProfile.medianDaysToPay >= 0, 'Median should be non-negative');
        System.assert(lowProfile.consistencyScore >= 0 && lowProfile.consistencyScore <= 100,
            'Consistency score should be 0-100');

        // High Risk should have 2 payment history records
        ARF_CashForecastEngine.AccountPaymentProfile highProfile = profiles.get(accHigh.Id);
        System.assertNotEquals(null, highProfile, 'High risk profile should exist');
        System.assertEquals(2, highProfile.paymentCount, 'Should have 2 payment records');
        System.assertEquals('insufficient_data', highProfile.trend, 'Should be insufficient data for trend');
    }

    @isTest
    static void testBuildProfilesBulkNoHistory() {
        Account newAcct = new Account(Name = 'New Account No History');
        insert newAcct;

        Test.startTest();
        Map<Id, ARF_CashForecastEngine.AccountPaymentProfile> profiles =
            ARF_CashForecastEngine.buildProfilesBulk(new Set<Id>{ newAcct.Id });
        Test.stopTest();

        ARF_CashForecastEngine.AccountPaymentProfile profile = profiles.get(newAcct.Id);
        System.assertNotEquals(null, profile, 'Profile should exist even with no history');
        System.assertEquals(0, profile.paymentCount, 'Payment count should be 0');
        System.assertEquals(30, profile.avgDaysToPay, 'Default avg days should be 30');
        System.assertEquals('no_history', profile.trend, 'Trend should be no_history');
    }

    @isTest
    static void testGetDefaultProfile() {
        ARF_CashForecastEngine.AccountPaymentProfile profile =
            ARF_CashForecastEngine.getDefaultProfile();

        System.assertEquals(30, profile.avgDaysToPay, 'Default avg should be 30');
        System.assertEquals(30, profile.medianDaysToPay, 'Default median should be 30');
        System.assertEquals(15, profile.stdDeviation, 'Default std dev should be 15');
        System.assertEquals(50, profile.consistencyScore, 'Default consistency should be 50');
        System.assertEquals(0, profile.paymentCount, 'Default payment count should be 0');
        System.assertEquals('no_history', profile.trend, 'Default trend should be no_history');
    }

    @isTest
    static void testGenerateForecasts() {
        Test.startTest();
        ARF_CashForecastEngine.ForecastResult result =
            ARF_CashForecastEngine.generateForecasts();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(10, result.predictionsCreated, 'Should create 10 predictions (5 per account)');
        System.assert(result.forecastsCreated > 0, 'Should create weekly forecasts');
        System.assert(result.totalForecastedAmount > 0, 'Total forecasted amount should be positive');

        // Verify predictions were inserted
        List<ARF_Payment_Prediction__c> predictions = [
            SELECT Id, Invoice__c, Predicted_Pay_Date__c, Confidence__c, Week_Bucket__c
            FROM ARF_Payment_Prediction__c
            WHERE Actual_Pay_Date__c = null
        ];
        System.assertEquals(10, predictions.size(), 'Should have 10 active predictions');

        // Verify forecasts were created
        List<ARF_Cash_Forecast__c> forecasts = [
            SELECT Id, Forecast_Date__c, Period_Type__c, Predicted_Collections__c
            FROM ARF_Cash_Forecast__c
            WHERE Period_Type__c = 'Weekly'
        ];
        System.assertEquals(12, forecasts.size(), 'Should have 12 weekly forecasts');
    }

    @isTest
    static void testGenerateForecastsIdempotent() {
        // Run forecasts twice to test old prediction cleanup
        ARF_CashForecastEngine.generateForecasts();

        Test.startTest();
        ARF_CashForecastEngine.ForecastResult result =
            ARF_CashForecastEngine.generateForecasts();
        Test.stopTest();

        System.assertEquals(10, result.predictionsCreated, 'Should recreate 10 predictions after cleanup');

        // Should not have duplicates
        List<ARF_Payment_Prediction__c> predictions = [
            SELECT Id FROM ARF_Payment_Prediction__c
            WHERE Actual_Pay_Date__c = null
        ];
        System.assertEquals(10, predictions.size(), 'Should have exactly 10 active predictions, no duplicates');
    }

    @isTest
    static void testGetDashboard() {
        // Generate forecasts first
        ARF_CashForecastEngine.generateForecasts();

        Test.startTest();
        ARF_CashForecastEngine.ForecastDashboard dashboard =
            ARF_CashForecastEngine.getDashboard('Weekly', 12);
        Test.stopTest();

        System.assertNotEquals(null, dashboard, 'Dashboard should not be null');
        System.assertNotEquals(null, dashboard.periods, 'Periods list should not be null');
        System.assert(!dashboard.periods.isEmpty(), 'Should have forecast periods');
        System.assert(dashboard.totalForecast >= 0, 'Total forecast should be non-negative');

        // Verify period structure
        ARF_CashForecastEngine.ForecastPeriod firstPeriod = dashboard.periods[0];
        System.assertNotEquals(null, firstPeriod.startDate, 'Period should have start date');
        System.assertNotEquals(null, firstPeriod.endDate, 'Period should have end date');
        System.assert(String.isNotBlank(firstPeriod.label), 'Period should have label');
    }

    @isTest
    static void testGetDashboardDefaults() {
        ARF_CashForecastEngine.generateForecasts();

        Test.startTest();
        ARF_CashForecastEngine.ForecastDashboard dashboard =
            ARF_CashForecastEngine.getDashboard(null, null);
        Test.stopTest();

        System.assertNotEquals(null, dashboard, 'Dashboard with defaults should not be null');
    }

    @isTest
    static void testGetAccuracyMetricsNoData() {
        Test.startTest();
        ARF_CashForecastEngine.AccuracyMetrics metrics =
            ARF_CashForecastEngine.getAccuracyMetrics();
        Test.stopTest();

        System.assertEquals(0, metrics.totalPredictions, 'No completed predictions');
        System.assertEquals(0, metrics.overallAccuracy, 'Accuracy should be 0 with no data');
        System.assertEquals(0, metrics.avgDaysOff, 'Avg days off should be 0');
    }

    @isTest
    static void testGetAccuracyMetricsWithData() {
        // Generate predictions first
        ARF_CashForecastEngine.generateForecasts();

        // Mark some predictions as completed with actual pay dates
        List<ARF_Payment_Prediction__c> predictions = [
            SELECT Id, Predicted_Pay_Date__c
            FROM ARF_Payment_Prediction__c
            WHERE Actual_Pay_Date__c = null
            LIMIT 4
        ];
        for (Integer i = 0; i < predictions.size(); i++) {
            // Set actual date close to predicted (within 1-2 weeks)
            predictions[i].Actual_Pay_Date__c = predictions[i].Predicted_Pay_Date__c.addDays(i * 3);
        }
        update predictions;

        Test.startTest();
        ARF_CashForecastEngine.AccuracyMetrics metrics =
            ARF_CashForecastEngine.getAccuracyMetrics();
        Test.stopTest();

        System.assertEquals(4, metrics.totalPredictions, 'Should have 4 completed predictions');
        System.assert(metrics.avgDaysOff >= 0, 'Avg days off should be non-negative');
        System.assert(metrics.withinOneWeek >= 0, 'Within one week should be non-negative');
        System.assert(metrics.withinTwoWeeks >= 0, 'Within two weeks should be non-negative');
        System.assert(metrics.overallAccuracy >= 0, 'Overall accuracy should be non-negative');
    }

    @isTest
    static void testBatchExecution() {
        Test.startTest();
        ARF_CashForecastEngine batchJob = new ARF_CashForecastEngine();
        Database.executeBatch(batchJob, 200);
        Test.stopTest();

        // Verify predictions were created by the batch
        List<ARF_Payment_Prediction__c> predictions = [
            SELECT Id FROM ARF_Payment_Prediction__c
            WHERE Actual_Pay_Date__c = null
        ];
        System.assert(predictions.size() > 0, 'Batch should have created predictions');

        // Verify weekly forecasts were generated in finish()
        List<ARF_Cash_Forecast__c> forecasts = [
            SELECT Id FROM ARF_Cash_Forecast__c
            WHERE Period_Type__c = 'Weekly'
        ];
        System.assert(forecasts.size() > 0, 'Batch finish should have created weekly forecasts');
    }

    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
        String jobId = System.schedule(
            'Test Cash Forecast',
            '0 0 2 * * ?',
            new ARF_CashForecastEngine()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Scheduled job should have an ID');

        // Verify the job was scheduled
        List<CronTrigger> triggers = [
            SELECT Id, State FROM CronTrigger WHERE Id = :jobId
        ];
        System.assertEquals(1, triggers.size(), 'Should find the scheduled job');
    }

    @isTest
    static void testForecastResultInnerClass() {
        ARF_CashForecastEngine.ForecastResult result = new ARF_CashForecastEngine.ForecastResult();
        result.predictionsCreated = 10;
        result.forecastsCreated = 12;
        result.totalForecastedAmount = 50000.00;

        System.assertEquals(10, result.predictionsCreated);
        System.assertEquals(12, result.forecastsCreated);
        System.assertEquals(50000.00, result.totalForecastedAmount);
    }

    @isTest
    static void testPaymentPredictionInnerClass() {
        ARF_CashForecastEngine.PaymentPrediction pred = new ARF_CashForecastEngine.PaymentPrediction();
        pred.predictedDate = Date.today().addDays(7);
        pred.predictedAmount = 1000;
        pred.confidence = 85.5;
        pred.method = 'Test Method';
        pred.weekBucket = 'Week 1';

        System.assertEquals(Date.today().addDays(7), pred.predictedDate);
        System.assertEquals(1000, pred.predictedAmount);
        System.assertEquals(85.5, pred.confidence);
        System.assertEquals('Test Method', pred.method);
        System.assertEquals('Week 1', pred.weekBucket);
    }

    @isTest
    static void testPredictInvoiceNoAccountHistory() {
        // Test with an account that has zero payment history
        Account newAcct = new Account(Name = 'Brand New Customer', ARF_Risk_Score__c = 50);
        insert newAcct;

        ARF_Invoice__c inv = new ARF_Invoice__c(
            Account__c = newAcct.Id,
            Amount__c = 2000,
            Balance__c = 2000,
            Status__c = 'Open',
            Due_Date__c = Date.today().addDays(15),
            Invoice_Date__c = Date.today(),
            Document_Number__c = 'INV-NEW-001'
        );
        insert inv;

        inv = [
            SELECT Id, Amount__c, Balance__c, Due_Date__c, Days_Past_Due__c, Account__c
            FROM ARF_Invoice__c
            WHERE Id = :inv.Id
        ];

        ARF_CashForecastEngine.AccountPaymentProfile profile =
            ARF_CashForecastEngine.getDefaultProfile();

        Test.startTest();
        ARF_CashForecastEngine.PaymentPrediction pred =
            ARF_CashForecastEngine.predictInvoice(inv, profile);
        Test.stopTest();

        System.assertEquals(2000, pred.predictedAmount, 'Should predict full balance');
        System.assert(pred.confidence >= 5 && pred.confidence <= 95, 'Confidence within bounds');
        System.assert(pred.method.contains('0 hist'), 'Method should show 0 history');
    }

    @isTest
    static void testPredictInvoiceDifferentAgingBuckets() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Low Risk Corp' LIMIT 1];
        Set<Id> acctIds = new Set<Id>{ acc.Id };
        Map<Id, ARF_CashForecastEngine.AccountPaymentProfile> profiles =
            ARF_CashForecastEngine.buildProfilesBulk(acctIds);
        ARF_CashForecastEngine.AccountPaymentProfile profile = profiles.get(acc.Id);

        // Test invoice 31-60 days past due
        ARF_Invoice__c inv60 = [
            SELECT Id, Amount__c, Balance__c, Due_Date__c, Days_Past_Due__c, Account__c
            FROM ARF_Invoice__c
            WHERE Document_Number__c = 'INV-FC-005'
            LIMIT 1
        ];

        Test.startTest();
        ARF_CashForecastEngine.PaymentPrediction pred60 =
            ARF_CashForecastEngine.predictInvoice(inv60, profile);

        // Test not-yet-due invoice
        ARF_Invoice__c invFuture = [
            SELECT Id, Amount__c, Balance__c, Due_Date__c, Days_Past_Due__c, Account__c
            FROM ARF_Invoice__c
            WHERE Document_Number__c = 'INV-FC-004'
            LIMIT 1
        ];
        ARF_CashForecastEngine.PaymentPrediction predFuture =
            ARF_CashForecastEngine.predictInvoice(invFuture, profile);
        Test.stopTest();

        System.assertNotEquals(null, pred60.predictedDate, 'Past due prediction should have date');
        System.assertNotEquals(null, predFuture.predictedDate, 'Future due prediction should have date');
        // Past due invoices generally get lower confidence
        System.assert(predFuture.confidence >= pred60.confidence,
            'Future due should have >= confidence than past due');
    }

    @isTest
    static void testGenerateForecastsNoInvoices() {
        // Delete all open invoices to test empty case
        List<ARF_Invoice__c> openInvoices = [
            SELECT Id FROM ARF_Invoice__c
            WHERE Status__c IN ('Open', 'Partially Paid')
        ];
        delete openInvoices;

        Test.startTest();
        ARF_CashForecastEngine.ForecastResult result =
            ARF_CashForecastEngine.generateForecasts();
        Test.stopTest();

        System.assertEquals(0, result.predictionsCreated, 'No predictions with no invoices');
        System.assertEquals(0, result.forecastsCreated, 'No forecasts with no invoices');
        System.assertEquals(0, result.totalForecastedAmount, 'No amount with no invoices');
    }
}
