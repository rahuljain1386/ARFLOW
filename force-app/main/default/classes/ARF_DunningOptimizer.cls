public with sharing class ARF_DunningOptimizer {

    // Recommend the best channel for contacting an account
    @AuraEnabled
    public static ChannelRecommendation recommendChannel(Id accountId) {
        ChannelRecommendation rec = new ChannelRecommendation();

        // Get channel performance history for this account
        List<ARF_Channel_Performance__c> performances = [
            SELECT Channel__c, Response_Rate__c, Avg_Response_Time_Hours__c,
                   Payments_Generated__c, Amount_Collected__c, Attempts__c, Responses__c,
                   Best_Day_Of_Week__c, Best_Time_Of_Day__c
            FROM ARF_Channel_Performance__c
            WHERE Account__c = :accountId
            ORDER BY Response_Rate__c DESC
        ];

        if (performances.isEmpty()) {
            // No history - use default: Email first, then SMS, then Voice
            rec.recommendedChannel = 'Email';
            rec.confidence = 50;
            rec.reason = 'No contact history - starting with email as default first touch.';
            rec.fallbackChannel = 'SMS';
            rec.suggestedDayOfWeek = 'Tuesday';
            rec.suggestedTimeOfDay = '10:00 AM';
            rec.channelScores = getDefaultScores();
            return rec;
        }

        // Score each channel
        rec.channelScores = new List<ChannelScore>();
        ChannelScore bestScore = null;
        ChannelScore secondBest = null;

        for (ARF_Channel_Performance__c perf : performances) {
            ChannelScore cs = new ChannelScore();
            cs.channel = perf.Channel__c;
            cs.responseRate = perf.Response_Rate__c != null ? perf.Response_Rate__c : 0;
            cs.avgResponseHours = perf.Avg_Response_Time_Hours__c != null ? perf.Avg_Response_Time_Hours__c : 999;
            cs.paymentsGenerated = perf.Payments_Generated__c != null ? (Integer) perf.Payments_Generated__c : 0;
            cs.amountCollected = perf.Amount_Collected__c != null ? perf.Amount_Collected__c : 0;

            // Composite score: 40% response rate + 25% payment generation + 20% speed + 15% amount
            Decimal responseScore = cs.responseRate; // 0-100
            Decimal paymentScore = Math.min(100, cs.paymentsGenerated * 20); // 0-100
            Decimal speedScore = cs.avgResponseHours < 24 ? 100 : cs.avgResponseHours < 72 ? 70 : cs.avgResponseHours < 168 ? 40 : 10;
            Decimal amountScore = Math.min(100, (cs.amountCollected / 10000) * 100); // scale to $10K

            cs.compositeScore = (responseScore * 0.40) + (paymentScore * 0.25) + (speedScore * 0.20) + (amountScore * 0.15);
            cs.compositeScore = cs.compositeScore.setScale(1);

            rec.channelScores.add(cs);

            if (bestScore == null || cs.compositeScore > bestScore.compositeScore) {
                secondBest = bestScore;
                bestScore = cs;
            } else if (secondBest == null || cs.compositeScore > secondBest.compositeScore) {
                secondBest = cs;
            }
        }

        rec.recommendedChannel = bestScore.channel;
        rec.confidence = Math.min(95, bestScore.compositeScore).setScale(0);
        rec.fallbackChannel = secondBest != null ? secondBest.channel : 'Email';

        // Best timing
        for (ARF_Channel_Performance__c perf : performances) {
            if (perf.Channel__c == bestScore.channel) {
                rec.suggestedDayOfWeek = String.isNotBlank(perf.Best_Day_Of_Week__c) ? perf.Best_Day_Of_Week__c : 'Tuesday';
                rec.suggestedTimeOfDay = String.isNotBlank(perf.Best_Time_Of_Day__c) ? perf.Best_Time_Of_Day__c : '10:00 AM';
                break;
            }
        }

        rec.reason = 'Based on ' + (Integer) bestScore.compositeScore + ' composite score. ' +
            bestScore.channel + ' has ' + bestScore.responseRate.setScale(0) + '% response rate with ' +
            bestScore.paymentsGenerated + ' payments generated.';

        return rec;
    }

    // Record a channel interaction outcome
    @AuraEnabled
    public static void recordInteraction(Id accountId, String channel, Boolean gotResponse, Decimal responseTimeHours, Boolean generatedPayment, Decimal amountCollected) {
        // Find or create performance record for this account + channel + current month
        String period = String.valueOf(Date.today().year()) + '-' + String.valueOf(Date.today().month()).leftPad(2, '0');

        List<ARF_Channel_Performance__c> existing = [
            SELECT Id, Attempts__c, Responses__c, Avg_Response_Time_Hours__c,
                   Payments_Generated__c, Amount_Collected__c
            FROM ARF_Channel_Performance__c
            WHERE Account__c = :accountId AND Channel__c = :channel AND Period__c = :period
            LIMIT 1
        ];

        ARF_Channel_Performance__c perf;
        if (!existing.isEmpty()) {
            perf = existing[0];
        } else {
            perf = new ARF_Channel_Performance__c();
            perf.Account__c = accountId;
            perf.Channel__c = channel;
            perf.Period__c = period;
            perf.Attempts__c = 0;
            perf.Responses__c = 0;
            perf.Payments_Generated__c = 0;
            perf.Amount_Collected__c = 0;
            perf.Avg_Response_Time_Hours__c = 0;
        }

        perf.Attempts__c = (perf.Attempts__c != null ? perf.Attempts__c : 0) + 1;
        perf.Last_Attempt_Date__c = DateTime.now();

        if (gotResponse) {
            Decimal oldResponses = perf.Responses__c != null ? perf.Responses__c : 0;
            perf.Responses__c = oldResponses + 1;
            perf.Last_Response_Date__c = DateTime.now();

            // Update rolling average response time
            if (responseTimeHours != null) {
                Decimal oldAvg = perf.Avg_Response_Time_Hours__c != null ? perf.Avg_Response_Time_Hours__c : 0;
                perf.Avg_Response_Time_Hours__c = ((oldAvg * oldResponses) + responseTimeHours) / (oldResponses + 1);
            }

            // Track best day/time
            perf.Best_Day_Of_Week__c = getDayOfWeek(Date.today());
            perf.Best_Time_Of_Day__c = DateTime.now().hour() < 12 ? 'Morning' : DateTime.now().hour() < 17 ? 'Afternoon' : 'Evening';
        }

        perf.Response_Rate__c = perf.Attempts__c > 0 ? (perf.Responses__c / perf.Attempts__c * 100).setScale(1) : 0;

        if (generatedPayment) {
            perf.Payments_Generated__c = (perf.Payments_Generated__c != null ? perf.Payments_Generated__c : 0) + 1;
        }
        if (amountCollected != null && amountCollected > 0) {
            perf.Amount_Collected__c = (perf.Amount_Collected__c != null ? perf.Amount_Collected__c : 0) + amountCollected;
        }

        upsert perf;
    }

    // Get optimization dashboard data
    @AuraEnabled(cacheable=true)
    public static DunningDashboard getDashboard() {
        DunningDashboard dash = new DunningDashboard();

        // Aggregate channel performance across all accounts
        List<AggregateResult> channelAgg = [
            SELECT Channel__c, SUM(Attempts__c) totalAttempts, SUM(Responses__c) totalResponses,
                   AVG(Response_Rate__c) avgResponseRate, SUM(Payments_Generated__c) totalPayments,
                   SUM(Amount_Collected__c) totalCollected
            FROM ARF_Channel_Performance__c
            WHERE Period__c >= :getThreeMonthsAgo()
            GROUP BY Channel__c
        ];

        dash.channelSummaries = new List<ChannelSummary>();
        for (AggregateResult ar : channelAgg) {
            ChannelSummary cs = new ChannelSummary();
            cs.channel = (String) ar.get('Channel__c');
            cs.totalAttempts = ar.get('totalAttempts') != null ? (Integer) ((Decimal) ar.get('totalAttempts')).intValue() : 0;
            cs.totalResponses = ar.get('totalResponses') != null ? (Integer) ((Decimal) ar.get('totalResponses')).intValue() : 0;
            cs.avgResponseRate = ar.get('avgResponseRate') != null ? (Decimal) ar.get('avgResponseRate') : 0;
            cs.totalPayments = ar.get('totalPayments') != null ? (Integer) ((Decimal) ar.get('totalPayments')).intValue() : 0;
            cs.totalCollected = ar.get('totalCollected') != null ? (Decimal) ar.get('totalCollected') : 0;
            dash.channelSummaries.add(cs);
        }

        // Overall metrics
        dash.totalAttempts = 0;
        dash.totalResponses = 0;
        dash.totalCollected = 0;
        for (ChannelSummary cs : dash.channelSummaries) {
            dash.totalAttempts += cs.totalAttempts;
            dash.totalResponses += cs.totalResponses;
            dash.totalCollected += cs.totalCollected;
        }
        dash.overallResponseRate = dash.totalAttempts > 0 ? (Decimal)(dash.totalResponses * 100.0 / dash.totalAttempts).setScale(1) : 0;

        return dash;
    }

    private static String getDayOfWeek(Date d) {
        Integer dow = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(d), 7);
        List<String> days = new List<String>{'Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'};
        return days[dow];
    }

    private static String getThreeMonthsAgo() {
        Date d = Date.today().addMonths(-3);
        return String.valueOf(d.year()) + '-' + String.valueOf(d.month()).leftPad(2, '0');
    }

    private static List<ChannelScore> getDefaultScores() {
        List<ChannelScore> scores = new List<ChannelScore>();
        ChannelScore email = new ChannelScore();
        email.channel = 'Email'; email.compositeScore = 50; email.responseRate = 0;
        scores.add(email);
        ChannelScore sms = new ChannelScore();
        sms.channel = 'SMS'; sms.compositeScore = 40; sms.responseRate = 0;
        scores.add(sms);
        ChannelScore voice = new ChannelScore();
        voice.channel = 'AI_Voice'; voice.compositeScore = 30; voice.responseRate = 0;
        scores.add(voice);
        ChannelScore phone = new ChannelScore();
        phone.channel = 'Phone'; phone.compositeScore = 20; phone.responseRate = 0;
        scores.add(phone);
        return scores;
    }

    // Inner classes
    public class ChannelRecommendation {
        @AuraEnabled public String recommendedChannel;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String reason;
        @AuraEnabled public String fallbackChannel;
        @AuraEnabled public String suggestedDayOfWeek;
        @AuraEnabled public String suggestedTimeOfDay;
        @AuraEnabled public List<ChannelScore> channelScores;
    }

    public class ChannelScore {
        @AuraEnabled public String channel;
        @AuraEnabled public Decimal responseRate;
        @AuraEnabled public Decimal avgResponseHours;
        @AuraEnabled public Integer paymentsGenerated;
        @AuraEnabled public Decimal amountCollected;
        @AuraEnabled public Decimal compositeScore;
    }

    public class ChannelSummary {
        @AuraEnabled public String channel;
        @AuraEnabled public Integer totalAttempts;
        @AuraEnabled public Integer totalResponses;
        @AuraEnabled public Decimal avgResponseRate;
        @AuraEnabled public Integer totalPayments;
        @AuraEnabled public Decimal totalCollected;
    }

    public class DunningDashboard {
        @AuraEnabled public List<ChannelSummary> channelSummaries;
        @AuraEnabled public Integer totalAttempts;
        @AuraEnabled public Integer totalResponses;
        @AuraEnabled public Decimal overallResponseRate;
        @AuraEnabled public Decimal totalCollected;
    }
}
