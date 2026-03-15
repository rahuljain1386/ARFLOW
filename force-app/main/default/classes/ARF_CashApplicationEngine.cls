public with sharing class ARF_CashApplicationEngine {

    private static final Pattern INV_PATTERN = Pattern.compile('(?i)(?:INV[\\-#]?\\s*)(\\d{3,10})');
    private static final Pattern PO_PATTERN = Pattern.compile('(?i)(?:PO[\\-#]?\\s*)(\\d{3,10})');

    @AuraEnabled
    public static List<MatchResult> processPayments(List<Id> paymentIds) {
        List<ARF_Payment__c> payments = [
            SELECT Id, Name, Amount__c, Applied_Amount__c, Unapplied_Amount__c,
                   Reference__c, ERP_ID__c, Account__c, Account__r.Name
            FROM ARF_Payment__c
            WHERE Id IN :paymentIds AND Unapplied_Amount__c > 0
        ];

        if (payments.isEmpty()) {
            return new List<MatchResult>();
        }

        Set<Id> accountIds = new Set<Id>();
        for (ARF_Payment__c p : payments) {
            if (p.Account__c != null) accountIds.add(p.Account__c);
        }

        List<ARF_Invoice__c> openInvoices = [
            SELECT Id, Name, Document_Number__c, Amount__c, Balance__c,
                   Due_Date__c, Days_Past_Due__c, PO_Number__c, Reference__c,
                   Account__c, Account__r.Name
            FROM ARF_Invoice__c
            WHERE (Status__c = 'Open' OR Status__c = 'Partially Paid')
            AND Account__c IN :accountIds
            ORDER BY Due_Date__c ASC
        ];

        Map<Id, List<ARF_Invoice__c>> invoicesByAccount = new Map<Id, List<ARF_Invoice__c>>();
        for (ARF_Invoice__c inv : openInvoices) {
            if (!invoicesByAccount.containsKey(inv.Account__c)) {
                invoicesByAccount.put(inv.Account__c, new List<ARF_Invoice__c>());
            }
            invoicesByAccount.get(inv.Account__c).add(inv);
        }

        List<MatchResult> allResults = new List<MatchResult>();
        for (ARF_Payment__c payment : payments) {
            List<ARF_Invoice__c> acctInvoices = invoicesByAccount.get(payment.Account__c);
            if (acctInvoices != null && !acctInvoices.isEmpty()) {
                allResults.addAll(matchPayment(payment, acctInvoices));
            }
        }

        if (!allResults.isEmpty()) {
            saveResults(allResults);
        }

        return allResults;
    }

    public static List<MatchResult> matchPayment(ARF_Payment__c payment, List<ARF_Invoice__c> openInvoices) {
        List<MatchResult> results = new List<MatchResult>();
        Decimal unapplied = payment.Unapplied_Amount__c;
        String reference = (payment.Reference__c != null ? payment.Reference__c : '') +
                          ' ' + (payment.ERP_ID__c != null ? payment.ERP_ID__c : '');
        reference = reference.trim();

        // Rule 1: Exact Invoice Number Match
        if (String.isNotBlank(reference)) {
            Matcher invMatcher = INV_PATTERN.matcher(reference);
            while (invMatcher.find()) {
                String invNum = invMatcher.group(1);
                for (ARF_Invoice__c inv : openInvoices) {
                    String docNum = inv.Document_Number__c != null ? inv.Document_Number__c : '';
                    if (docNum.contains(invNum)) {
                        Decimal confidence = (unapplied == inv.Balance__c) ? 100.0 : 90.0;
                        Decimal suggestedAmt = Math.min(unapplied, inv.Balance__c);
                        String details = '{"rule":"Invoice Number Match","parsed_number":"' + invNum +
                            '","matched_doc":"' + docNum + '","exact_amount_match":' +
                            (unapplied == inv.Balance__c) + '}';
                        results.add(createResult(payment.Id, inv.Id, 'Invoice Number', confidence, suggestedAmt, details));
                        break;
                    }
                }
            }
        }

        // Rule 2: PO Number Match
        if (String.isNotBlank(reference)) {
            Matcher poMatcher = PO_PATTERN.matcher(reference);
            while (poMatcher.find()) {
                String poNum = poMatcher.group(1);
                for (ARF_Invoice__c inv : openInvoices) {
                    if (inv.PO_Number__c != null && inv.PO_Number__c.contains(poNum)) {
                        Decimal suggestedAmt = Math.min(unapplied, inv.Balance__c);
                        String details = '{"rule":"PO Number Match","parsed_po":"' + poNum +
                            '","matched_po":"' + inv.PO_Number__c + '"}';
                        results.add(createResult(payment.Id, inv.Id, 'PO Number', 95.0, suggestedAmt, details));
                    }
                }
            }
        }

        // Rule 3: Exact Amount Match
        List<ARF_Invoice__c> exactAmountMatches = new List<ARF_Invoice__c>();
        for (ARF_Invoice__c inv : openInvoices) {
            if (inv.Balance__c == unapplied) {
                exactAmountMatches.add(inv);
            }
        }
        if (exactAmountMatches.size() == 1 && !hasMatchForInvoice(results, exactAmountMatches[0].Id)) {
            String details = '{"rule":"Exact Amount Match","payment_amount":' + unapplied +
                ',"invoice_balance":' + exactAmountMatches[0].Balance__c + ',"single_match":true}';
            results.add(createResult(payment.Id, exactAmountMatches[0].Id, 'Exact Amount', 85.0, unapplied, details));
        } else if (exactAmountMatches.size() > 1) {
            for (ARF_Invoice__c inv : exactAmountMatches) {
                if (!hasMatchForInvoice(results, inv.Id)) {
                    String details = '{"rule":"Exact Amount Match","payment_amount":' + unapplied +
                        ',"invoice_balance":' + inv.Balance__c + ',"multiple_matches":' + exactAmountMatches.size() + '}';
                    results.add(createResult(payment.Id, inv.Id, 'Exact Amount (Multi)', 60.0, unapplied, details));
                }
            }
        }

        // Rule 4: Sum Match (2-3 invoice combinations)
        if (results.isEmpty() || !hasHighConfidence(results, 85)) {
            List<List<ARF_Invoice__c>> combos = findSumCombinations(openInvoices, unapplied, 3);
            for (List<ARF_Invoice__c> combo : combos) {
                List<String> invIds = new List<String>();
                for (ARF_Invoice__c inv : combo) { invIds.add(inv.Document_Number__c); }
                String details = '{"rule":"Sum Match","payment_amount":' + unapplied +
                    ',"invoice_count":' + combo.size() + ',"invoices":"' + String.join(invIds, ',') + '"}';
                for (ARF_Invoice__c inv : combo) {
                    if (!hasMatchForInvoice(results, inv.Id)) {
                        results.add(createResult(payment.Id, inv.Id, 'Sum Match', 80.0, inv.Balance__c, details));
                    }
                }
            }
        }

        // Rule 5: Reference / Memo Match
        if (String.isNotBlank(reference) && (results.isEmpty() || !hasHighConfidence(results, 80))) {
            String refLower = reference.toLowerCase();
            for (ARF_Invoice__c inv : openInvoices) {
                if (hasMatchForInvoice(results, inv.Id)) continue;
                String invRef = inv.Reference__c != null ? inv.Reference__c.toLowerCase() : '';
                String invDoc = inv.Document_Number__c != null ? inv.Document_Number__c.toLowerCase() : '';
                if ((String.isNotBlank(invRef) && refLower.contains(invRef)) ||
                    (String.isNotBlank(invDoc) && refLower.contains(invDoc))) {
                    Decimal suggestedAmt = Math.min(unapplied, inv.Balance__c);
                    String details = '{"rule":"Reference Match","payment_ref":"' + reference.abbreviate(100) +
                        '","invoice_ref":"' + (inv.Reference__c != null ? inv.Reference__c : inv.Document_Number__c) + '"}';
                    results.add(createResult(payment.Id, inv.Id, 'Reference Match', 75.0, suggestedAmt, details));
                }
            }
        }

        // Rule 6: Amount + Account Proximity Match (within 5%)
        if (results.isEmpty()) {
            for (ARF_Invoice__c inv : openInvoices) {
                if (hasMatchForInvoice(results, inv.Id)) continue;
                Decimal diff = Math.abs(unapplied - inv.Balance__c);
                Decimal tolerance = inv.Balance__c * 0.05;
                if (diff <= tolerance && diff > 0) {
                    Decimal suggestedAmt = Math.min(unapplied, inv.Balance__c);
                    String details = '{"rule":"Amount Proximity","payment_amount":' + unapplied +
                        ',"invoice_balance":' + inv.Balance__c + ',"difference":' + diff +
                        ',"tolerance_pct":5}';
                    results.add(createResult(payment.Id, inv.Id, 'Amount Proximity', 70.0, suggestedAmt, details));
                }
            }
        }

        return results;
    }

    @AuraEnabled
    public static ApplyResult autoApplyMatches(List<Id> resultIds) {
        ApplyResult result = new ApplyResult();
        result.successCount = 0;
        result.failCount = 0;
        result.totalApplied = 0;
        result.errors = new List<String>();

        List<ARF_Cash_App_Result__c> results = [
            SELECT Id, Payment__c, Invoice__c, Confidence__c, Applied_Amount__c, Status__c
            FROM ARF_Cash_App_Result__c
            WHERE Id IN :resultIds AND Status__c = 'Pending_Review'
            ORDER BY Confidence__c DESC
        ];

        Set<Id> processedInvoices = new Set<Id>();
        List<ARF_Payment_Application__c> appsToInsert = new List<ARF_Payment_Application__c>();
        List<ARF_Cash_App_Result__c> resultsToUpdate = new List<ARF_Cash_App_Result__c>();
        Map<Id, Decimal> paymentAppliedAmounts = new Map<Id, Decimal>();
        Map<Id, Decimal> invoiceAppliedAmounts = new Map<Id, Decimal>();

        for (ARF_Cash_App_Result__c car : results) {
            if (processedInvoices.contains(car.Invoice__c)) {
                continue;
            }

            ARF_Payment_Application__c pa = new ARF_Payment_Application__c();
            pa.Payment__c = car.Payment__c;
            pa.Invoice__c = car.Invoice__c;
            pa.Amount_Applied__c = car.Applied_Amount__c;
            pa.Application_Date__c = Date.today();
            appsToInsert.add(pa);

            car.Status__c = 'Auto_Applied';
            car.Review_Date__c = DateTime.now();
            resultsToUpdate.add(car);

            processedInvoices.add(car.Invoice__c);
            result.successCount++;
            result.totalApplied += car.Applied_Amount__c;

            Decimal pAmt = paymentAppliedAmounts.containsKey(car.Payment__c) ? paymentAppliedAmounts.get(car.Payment__c) : 0;
            paymentAppliedAmounts.put(car.Payment__c, pAmt + car.Applied_Amount__c);

            Decimal iAmt = invoiceAppliedAmounts.containsKey(car.Invoice__c) ? invoiceAppliedAmounts.get(car.Invoice__c) : 0;
            invoiceAppliedAmounts.put(car.Invoice__c, iAmt + car.Applied_Amount__c);
        }

        Savepoint sp = Database.setSavepoint();
        try {
            if (!appsToInsert.isEmpty()) insert appsToInsert;
            if (!resultsToUpdate.isEmpty()) update resultsToUpdate;

            // Update payment applied/unapplied amounts
            List<ARF_Payment__c> paymentsToUpdate = [
                SELECT Id, Applied_Amount__c, Unapplied_Amount__c, Amount__c
                FROM ARF_Payment__c WHERE Id IN :paymentAppliedAmounts.keySet()
            ];
            for (ARF_Payment__c p : paymentsToUpdate) {
                Decimal addl = paymentAppliedAmounts.get(p.Id);
                p.Applied_Amount__c = (p.Applied_Amount__c != null ? p.Applied_Amount__c : 0) + addl;
                p.Unapplied_Amount__c = p.Amount__c - p.Applied_Amount__c;
                if (p.Unapplied_Amount__c <= 0) p.Status__c = 'Applied';
            }
            if (!paymentsToUpdate.isEmpty()) update paymentsToUpdate;

            // Update invoice balances
            List<ARF_Invoice__c> invoicesToUpdate = [
                SELECT Id, Balance__c, Amount__c, Status__c
                FROM ARF_Invoice__c WHERE Id IN :invoiceAppliedAmounts.keySet()
            ];
            for (ARF_Invoice__c inv : invoicesToUpdate) {
                Decimal applied = invoiceAppliedAmounts.get(inv.Id);
                inv.Balance__c = inv.Balance__c - applied;
                if (inv.Balance__c <= 0) {
                    inv.Balance__c = 0;
                    inv.Status__c = 'Paid';
                } else {
                    inv.Status__c = 'Partially Paid';
                }
            }
            if (!invoicesToUpdate.isEmpty()) update invoicesToUpdate;

        } catch (Exception e) {
            Database.rollback(sp);
            result.errors.add(e.getMessage());
            result.failCount = result.successCount;
            result.successCount = 0;
            result.totalApplied = 0;
        }

        return result;
    }

    @AuraEnabled
    public static void reviewMatch(Id resultId, String action, Decimal overrideAmount) {
        ARF_Cash_App_Result__c car = [
            SELECT Id, Payment__c, Invoice__c, Applied_Amount__c, Status__c
            FROM ARF_Cash_App_Result__c WHERE Id = :resultId
        ];

        if (action == 'approve') {
            Decimal amount = overrideAmount != null ? overrideAmount : car.Applied_Amount__c;
            ARF_Payment_Application__c pa = new ARF_Payment_Application__c();
            pa.Payment__c = car.Payment__c;
            pa.Invoice__c = car.Invoice__c;
            pa.Amount_Applied__c = amount;
            pa.Application_Date__c = Date.today();

            Savepoint sp = Database.setSavepoint();
            try {
                insert pa;
                car.Status__c = 'Manual';
                car.Applied_Amount__c = amount;
                car.Reviewed_By__c = UserInfo.getUserId();
                car.Review_Date__c = DateTime.now();
                update car;

                ARF_Payment__c payment = [SELECT Id, Applied_Amount__c, Unapplied_Amount__c, Amount__c, Status__c FROM ARF_Payment__c WHERE Id = :car.Payment__c];
                payment.Applied_Amount__c = (payment.Applied_Amount__c != null ? payment.Applied_Amount__c : 0) + amount;
                payment.Unapplied_Amount__c = payment.Amount__c - payment.Applied_Amount__c;
                if (payment.Unapplied_Amount__c <= 0) payment.Status__c = 'Applied';
                update payment;

                ARF_Invoice__c invoice = [SELECT Id, Balance__c, Status__c FROM ARF_Invoice__c WHERE Id = :car.Invoice__c];
                invoice.Balance__c = invoice.Balance__c - amount;
                if (invoice.Balance__c <= 0) { invoice.Balance__c = 0; invoice.Status__c = 'Paid'; }
                else { invoice.Status__c = 'Partially Paid'; }
                update invoice;
            } catch (Exception e) {
                Database.rollback(sp);
                throw new AuraHandledException(e.getMessage());
            }
        } else {
            car.Status__c = 'Rejected';
            car.Reviewed_By__c = UserInfo.getUserId();
            car.Review_Date__c = DateTime.now();
            update car;
        }
    }

    @AuraEnabled(cacheable=true)
    public static CashAppStats getStats() {
        CashAppStats stats = new CashAppStats();
        stats.totalProcessed = 0; stats.autoAppliedCount = 0; stats.autoAppliedAmount = 0;
        stats.pendingReviewCount = 0; stats.pendingReviewAmount = 0;
        stats.matchRate = 0; stats.avgConfidence = 0;

        List<AggregateResult> agg = [
            SELECT Status__c, COUNT(Id) cnt, SUM(Applied_Amount__c) total, AVG(Confidence__c) avgConf
            FROM ARF_Cash_App_Result__c
            WHERE CreatedDate = LAST_N_DAYS:30
            GROUP BY Status__c
        ];
        Decimal totalCount = 0;
        Decimal matchedCount = 0;
        Decimal totalConf = 0;
        for (AggregateResult ar : agg) {
            String status = (String) ar.get('Status__c');
            Integer cnt = (Integer) ar.get('cnt');
            Decimal total = ar.get('total') != null ? (Decimal) ar.get('total') : 0;
            Decimal avgC = ar.get('avgConf') != null ? (Decimal) ar.get('avgConf') : 0;
            totalCount += cnt;
            totalConf += avgC * cnt;

            if (status == 'Auto_Applied') {
                stats.autoAppliedCount = cnt;
                stats.autoAppliedAmount = total;
                matchedCount += cnt;
            } else if (status == 'Pending_Review') {
                stats.pendingReviewCount = cnt;
                stats.pendingReviewAmount = total;
                matchedCount += cnt;
            } else if (status == 'Manual') {
                matchedCount += cnt;
            }
        }
        stats.totalProcessed = (Integer) totalCount;
        stats.matchRate = totalCount > 0 ? (matchedCount / totalCount * 100).setScale(1) : 0;
        stats.avgConfidence = totalCount > 0 ? (totalConf / totalCount).setScale(1) : 0;

        return stats;
    }

    // ─── Helper Methods ───

    private static MatchResult createResult(Id paymentId, Id invoiceId, String rule, Decimal confidence, Decimal amount, String details) {
        MatchResult mr = new MatchResult();
        mr.paymentId = paymentId;
        mr.invoiceId = invoiceId;
        mr.ruleName = rule;
        mr.confidence = confidence;
        mr.suggestedAmount = amount;
        mr.matchDetails = details;
        return mr;
    }

    private static Boolean hasMatchForInvoice(List<MatchResult> results, Id invoiceId) {
        for (MatchResult mr : results) {
            if (mr.invoiceId == invoiceId) return true;
        }
        return false;
    }

    private static Boolean hasHighConfidence(List<MatchResult> results, Decimal threshold) {
        for (MatchResult mr : results) {
            if (mr.confidence >= threshold) return true;
        }
        return false;
    }

    private static List<List<ARF_Invoice__c>> findSumCombinations(List<ARF_Invoice__c> invoices, Decimal target, Integer maxSize) {
        List<List<ARF_Invoice__c>> matches = new List<List<ARF_Invoice__c>>();
        Integer size = Math.min(invoices.size(), 10); // limit search space

        // Try pairs
        for (Integer i = 0; i < size; i++) {
            for (Integer j = i + 1; j < size; j++) {
                Decimal sum2 = invoices[i].Balance__c + invoices[j].Balance__c;
                if (sum2 == target) {
                    matches.add(new List<ARF_Invoice__c>{ invoices[i], invoices[j] });
                    if (matches.size() >= 3) return matches;
                }
            }
        }

        // Try triples if maxSize >= 3
        if (maxSize >= 3) {
            for (Integer i = 0; i < size; i++) {
                for (Integer j = i + 1; j < size; j++) {
                    for (Integer k = j + 1; k < size; k++) {
                        Decimal sum3 = invoices[i].Balance__c + invoices[j].Balance__c + invoices[k].Balance__c;
                        if (sum3 == target) {
                            matches.add(new List<ARF_Invoice__c>{ invoices[i], invoices[j], invoices[k] });
                            if (matches.size() >= 3) return matches;
                        }
                    }
                }
            }
        }

        return matches;
    }

    private static void saveResults(List<MatchResult> matchResults) {
        List<ARF_Cash_App_Result__c> records = new List<ARF_Cash_App_Result__c>();
        for (MatchResult mr : matchResults) {
            ARF_Cash_App_Result__c car = new ARF_Cash_App_Result__c();
            car.Payment__c = mr.paymentId;
            car.Invoice__c = mr.invoiceId;
            car.Rule_Used__c = mr.ruleName;
            car.Confidence__c = mr.confidence;
            car.Applied_Amount__c = mr.suggestedAmount;
            car.Match_Details__c = mr.matchDetails;
            car.Status__c = mr.confidence >= 90 ? 'Auto_Applied' : 'Pending_Review';
            records.add(car);
        }
        if (!records.isEmpty()) insert records;
    }

    // ─── Inner Classes ───

    public class MatchResult {
        @AuraEnabled public Id paymentId;
        @AuraEnabled public Id invoiceId;
        @AuraEnabled public String ruleName;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public Decimal suggestedAmount;
        @AuraEnabled public String matchDetails;
    }

    public class ApplyResult {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer failCount;
        @AuraEnabled public Decimal totalApplied;
        @AuraEnabled public List<String> errors;
    }

    public class CashAppStats {
        @AuraEnabled public Integer totalProcessed;
        @AuraEnabled public Integer autoAppliedCount;
        @AuraEnabled public Decimal autoAppliedAmount;
        @AuraEnabled public Integer pendingReviewCount;
        @AuraEnabled public Decimal pendingReviewAmount;
        @AuraEnabled public Decimal matchRate;
        @AuraEnabled public Decimal avgConfidence;
    }
}
