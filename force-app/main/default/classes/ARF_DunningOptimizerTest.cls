@isTest
private class ARF_DunningOptimizerTest {

    @TestSetup
    static void setupData() {
        Account acct = new Account(Name = 'Test Dunning Account');
        insert acct;

        // Create channel performance records for the account
        String period = String.valueOf(Date.today().year()) + '-' + String.valueOf(Date.today().month()).leftPad(2, '0');

        List<ARF_Channel_Performance__c> perfRecords = new List<ARF_Channel_Performance__c>();

        ARF_Channel_Performance__c emailPerf = new ARF_Channel_Performance__c();
        emailPerf.Account__c = acct.Id;
        emailPerf.Channel__c = 'Email';
        emailPerf.Period__c = period;
        emailPerf.Attempts__c = 20;
        emailPerf.Responses__c = 12;
        emailPerf.Response_Rate__c = 60;
        emailPerf.Avg_Response_Time_Hours__c = 18;
        emailPerf.Payments_Generated__c = 4;
        emailPerf.Amount_Collected__c = 5000;
        emailPerf.Best_Day_Of_Week__c = 'Tuesday';
        emailPerf.Best_Time_Of_Day__c = 'Morning';
        emailPerf.Last_Attempt_Date__c = DateTime.now();
        emailPerf.Last_Response_Date__c = DateTime.now();
        perfRecords.add(emailPerf);

        ARF_Channel_Performance__c smsPerf = new ARF_Channel_Performance__c();
        smsPerf.Account__c = acct.Id;
        smsPerf.Channel__c = 'SMS';
        smsPerf.Period__c = period;
        smsPerf.Attempts__c = 15;
        smsPerf.Responses__c = 6;
        smsPerf.Response_Rate__c = 40;
        smsPerf.Avg_Response_Time_Hours__c = 48;
        smsPerf.Payments_Generated__c = 2;
        smsPerf.Amount_Collected__c = 2000;
        smsPerf.Best_Day_Of_Week__c = 'Wednesday';
        smsPerf.Best_Time_Of_Day__c = 'Afternoon';
        perfRecords.add(smsPerf);

        ARF_Channel_Performance__c phonePerf = new ARF_Channel_Performance__c();
        phonePerf.Account__c = acct.Id;
        phonePerf.Channel__c = 'Phone';
        phonePerf.Period__c = period;
        phonePerf.Attempts__c = 10;
        phonePerf.Responses__c = 3;
        phonePerf.Response_Rate__c = 30;
        phonePerf.Avg_Response_Time_Hours__c = 200;
        phonePerf.Payments_Generated__c = 1;
        phonePerf.Amount_Collected__c = 1000;
        perfRecords.add(phonePerf);

        insert perfRecords;
    }

    @isTest
    static void testRecommendChannelWithHistory() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Dunning Account' LIMIT 1];

        Test.startTest();
        ARF_DunningOptimizer.ChannelRecommendation rec = ARF_DunningOptimizer.recommendChannel(acct.Id);
        Test.stopTest();

        System.assertNotEquals(null, rec, 'Recommendation should not be null');
        System.assertNotEquals(null, rec.recommendedChannel, 'Recommended channel should not be null');
        System.assert(rec.confidence > 0, 'Confidence should be greater than 0');
        System.assertNotEquals(null, rec.fallbackChannel, 'Fallback channel should not be null');
        System.assertNotEquals(null, rec.channelScores, 'Channel scores should not be null');
        System.assertEquals(3, rec.channelScores.size(), 'Should have 3 channel scores');
        System.assertNotEquals(null, rec.reason, 'Reason should not be null');
        System.assertNotEquals(null, rec.suggestedDayOfWeek, 'Suggested day should not be null');
        System.assertNotEquals(null, rec.suggestedTimeOfDay, 'Suggested time should not be null');
    }

    @isTest
    static void testRecommendChannelNoHistory() {
        Account acct = new Account(Name = 'New Account No History');
        insert acct;

        Test.startTest();
        ARF_DunningOptimizer.ChannelRecommendation rec = ARF_DunningOptimizer.recommendChannel(acct.Id);
        Test.stopTest();

        System.assertEquals('Email', rec.recommendedChannel, 'Default should be Email');
        System.assertEquals(50, rec.confidence, 'Default confidence should be 50');
        System.assertEquals('SMS', rec.fallbackChannel, 'Default fallback should be SMS');
        System.assertEquals(4, rec.channelScores.size(), 'Should have 4 default channel scores');
    }

    @isTest
    static void testRecordInteractionNewRecord() {
        Account acct = new Account(Name = 'Interaction Test Account');
        insert acct;

        Test.startTest();
        ARF_DunningOptimizer.recordInteraction(acct.Id, 'Email', true, 12.5, true, 1500);
        Test.stopTest();

        String period = String.valueOf(Date.today().year()) + '-' + String.valueOf(Date.today().month()).leftPad(2, '0');
        List<ARF_Channel_Performance__c> perfs = [
            SELECT Attempts__c, Responses__c, Response_Rate__c, Avg_Response_Time_Hours__c,
                   Payments_Generated__c, Amount_Collected__c, Best_Day_Of_Week__c, Best_Time_Of_Day__c
            FROM ARF_Channel_Performance__c
            WHERE Account__c = :acct.Id AND Channel__c = 'Email' AND Period__c = :period
        ];

        System.assertEquals(1, perfs.size(), 'Should create one performance record');
        System.assertEquals(1, perfs[0].Attempts__c, 'Should have 1 attempt');
        System.assertEquals(1, perfs[0].Responses__c, 'Should have 1 response');
        System.assertEquals(100.0, perfs[0].Response_Rate__c, 'Response rate should be 100%');
        System.assertEquals(12.5, perfs[0].Avg_Response_Time_Hours__c, 'Avg response time should be 12.5');
        System.assertEquals(1, perfs[0].Payments_Generated__c, 'Should have 1 payment');
        System.assertEquals(1500, perfs[0].Amount_Collected__c, 'Amount should be 1500');
        System.assertNotEquals(null, perfs[0].Best_Day_Of_Week__c, 'Best day should be set');
        System.assertNotEquals(null, perfs[0].Best_Time_Of_Day__c, 'Best time should be set');
    }

    @isTest
    static void testRecordInteractionExistingRecord() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Dunning Account' LIMIT 1];

        Test.startTest();
        ARF_DunningOptimizer.recordInteraction(acct.Id, 'Email', true, 6.0, false, 0);
        Test.stopTest();

        String period = String.valueOf(Date.today().year()) + '-' + String.valueOf(Date.today().month()).leftPad(2, '0');
        ARF_Channel_Performance__c perf = [
            SELECT Attempts__c, Responses__c
            FROM ARF_Channel_Performance__c
            WHERE Account__c = :acct.Id AND Channel__c = 'Email' AND Period__c = :period
            LIMIT 1
        ];

        System.assertEquals(21, perf.Attempts__c, 'Attempts should be incremented to 21');
        System.assertEquals(13, perf.Responses__c, 'Responses should be incremented to 13');
    }

    @isTest
    static void testRecordInteractionNoResponse() {
        Account acct = new Account(Name = 'No Response Account');
        insert acct;

        Test.startTest();
        ARF_DunningOptimizer.recordInteraction(acct.Id, 'SMS', false, null, false, null);
        Test.stopTest();

        String period = String.valueOf(Date.today().year()) + '-' + String.valueOf(Date.today().month()).leftPad(2, '0');
        ARF_Channel_Performance__c perf = [
            SELECT Attempts__c, Responses__c, Payments_Generated__c
            FROM ARF_Channel_Performance__c
            WHERE Account__c = :acct.Id AND Channel__c = 'SMS' AND Period__c = :period
            LIMIT 1
        ];

        System.assertEquals(1, perf.Attempts__c, 'Should have 1 attempt');
        System.assertEquals(0, perf.Responses__c, 'Should have 0 responses');
        System.assertEquals(0, perf.Payments_Generated__c, 'Should have 0 payments');
    }

    @isTest
    static void testGetDashboard() {
        Test.startTest();
        ARF_DunningOptimizer.DunningDashboard dash = ARF_DunningOptimizer.getDashboard();
        Test.stopTest();

        System.assertNotEquals(null, dash, 'Dashboard should not be null');
        System.assertNotEquals(null, dash.channelSummaries, 'Channel summaries should not be null');
        System.assert(dash.channelSummaries.size() > 0, 'Should have channel summaries');
        System.assert(dash.totalAttempts > 0, 'Should have total attempts');
        System.assert(dash.totalResponses > 0, 'Should have total responses');
        System.assert(dash.overallResponseRate > 0, 'Should have overall response rate');
        System.assert(dash.totalCollected > 0, 'Should have total collected');
    }

    @isTest
    static void testGetDashboardEmpty() {
        // Delete all performance records
        delete [SELECT Id FROM ARF_Channel_Performance__c];

        Test.startTest();
        ARF_DunningOptimizer.DunningDashboard dash = ARF_DunningOptimizer.getDashboard();
        Test.stopTest();

        System.assertNotEquals(null, dash, 'Dashboard should not be null');
        System.assertEquals(0, dash.totalAttempts, 'Total attempts should be 0');
        System.assertEquals(0, dash.overallResponseRate, 'Overall response rate should be 0');
    }

    @isTest
    static void testChannelScoreProperties() {
        // Test that inner class properties are accessible
        ARF_DunningOptimizer.ChannelScore cs = new ARF_DunningOptimizer.ChannelScore();
        cs.channel = 'Email';
        cs.responseRate = 75.0;
        cs.avgResponseHours = 24.0;
        cs.paymentsGenerated = 5;
        cs.amountCollected = 3000.00;
        cs.compositeScore = 82.5;

        System.assertEquals('Email', cs.channel);
        System.assertEquals(75.0, cs.responseRate);
        System.assertEquals(24.0, cs.avgResponseHours);
        System.assertEquals(5, cs.paymentsGenerated);
        System.assertEquals(3000.00, cs.amountCollected);
        System.assertEquals(82.5, cs.compositeScore);
    }

    @isTest
    static void testChannelSummaryProperties() {
        ARF_DunningOptimizer.ChannelSummary cs = new ARF_DunningOptimizer.ChannelSummary();
        cs.channel = 'SMS';
        cs.totalAttempts = 100;
        cs.totalResponses = 45;
        cs.avgResponseRate = 45.0;
        cs.totalPayments = 10;
        cs.totalCollected = 15000.00;

        System.assertEquals('SMS', cs.channel);
        System.assertEquals(100, cs.totalAttempts);
        System.assertEquals(45, cs.totalResponses);
    }

    @isTest
    static void testDunningDashboardProperties() {
        ARF_DunningOptimizer.DunningDashboard dash = new ARF_DunningOptimizer.DunningDashboard();
        dash.channelSummaries = new List<ARF_DunningOptimizer.ChannelSummary>();
        dash.totalAttempts = 200;
        dash.totalResponses = 80;
        dash.overallResponseRate = 40.0;
        dash.totalCollected = 50000.00;

        System.assertEquals(200, dash.totalAttempts);
        System.assertEquals(80, dash.totalResponses);
        System.assertEquals(40.0, dash.overallResponseRate);
        System.assertEquals(50000.00, dash.totalCollected);
    }
}
