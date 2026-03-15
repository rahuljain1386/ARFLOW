@isTest
private class ARF_CashApplicationEngineTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Cash App Test Account');
        insert acc;

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();

        // INV-1001: $500, for invoice number match
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 500, Balance__c = 500,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(-20),
            Invoice_Date__c = Date.today().addDays(-50),
            Document_Number__c = 'INV-1001', PO_Number__c = 'PO-5001',
            Reference__c = 'REF-ALPHA'
        ));

        // INV-1002: $300, for PO number match
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 300, Balance__c = 300,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(-10),
            Invoice_Date__c = Date.today().addDays(-40),
            Document_Number__c = 'INV-1002', PO_Number__c = 'PO-5002',
            Reference__c = 'REF-BETA'
        ));

        // INV-1003: $200, unique amount for exact amount match
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 200, Balance__c = 200,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(10),
            Invoice_Date__c = Date.today().addDays(-20),
            Document_Number__c = 'INV-1003', PO_Number__c = 'PO-5003',
            Reference__c = 'REF-GAMMA'
        ));

        // INV-1004: $150, for sum match (150 + 350 = 500)
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 150, Balance__c = 150,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(15),
            Invoice_Date__c = Date.today().addDays(-15),
            Document_Number__c = 'INV-1004'
        ));

        // INV-1005: $350, for sum match (150 + 350 = 500)
        invoices.add(new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 350, Balance__c = 350,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(5),
            Invoice_Date__c = Date.today().addDays(-25),
            Document_Number__c = 'INV-1005'
        ));

        insert invoices;

        // Create Cash App Rules
        List<ARF_Cash_App_Rule__c> rules = new List<ARF_Cash_App_Rule__c>();
        rules.add(new ARF_Cash_App_Rule__c(
            Name = 'Invoice Number Rule', Rule_Type__c = 'Invoice_Number',
            Priority__c = 1, Is_Active__c = true, Match_Threshold__c = 90
        ));
        rules.add(new ARF_Cash_App_Rule__c(
            Name = 'PO Number Rule', Rule_Type__c = 'PO_Number',
            Priority__c = 2, Is_Active__c = true, Match_Threshold__c = 90
        ));
        rules.add(new ARF_Cash_App_Rule__c(
            Name = 'Amount Match Rule', Rule_Type__c = 'Amount_Match',
            Priority__c = 3, Is_Active__c = true, Match_Threshold__c = 80
        ));
        insert rules;
    }

    // ── Rule 1: Invoice Number Match (exact amount) ──

    @isTest
    static void testInvoiceNumberMatch() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 500, Applied_Amount__c = 0,
            Unapplied_Amount__c = 500, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'Check',
            Reference__c = 'Payment for INV-1001'
        );
        insert pmt;

        Test.startTest();
        List<ARF_CashApplicationEngine.MatchResult> results =
            ARF_CashApplicationEngine.processPayments(new List<Id>{ pmt.Id });
        Test.stopTest();

        Boolean foundInvMatch = false;
        for (ARF_CashApplicationEngine.MatchResult mr : results) {
            if (mr.ruleName == 'Invoice Number') {
                foundInvMatch = true;
                System.assertEquals(100, mr.confidence, 'Exact amount + invoice number should be 100%');
                System.assertEquals(500, mr.suggestedAmount);
            }
        }
        System.assert(foundInvMatch, 'Should find an Invoice Number Match');

        // Verify result record was created
        List<ARF_Cash_App_Result__c> recs = [
            SELECT Id, Rule_Used__c, Confidence__c, Status__c
            FROM ARF_Cash_App_Result__c WHERE Payment__c = :pmt.Id
        ];
        System.assert(!recs.isEmpty(), 'Should have created result records');
    }

    // ── Rule 1b: Invoice Number Match (partial amount) ──

    @isTest
    static void testInvoiceNumberMatchPartial() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 250, Applied_Amount__c = 0,
            Unapplied_Amount__c = 250, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'Wire',
            Reference__c = 'Partial INV-1001'
        );
        insert pmt;

        Test.startTest();
        List<ARF_CashApplicationEngine.MatchResult> results =
            ARF_CashApplicationEngine.processPayments(new List<Id>{ pmt.Id });
        Test.stopTest();

        Boolean found = false;
        for (ARF_CashApplicationEngine.MatchResult mr : results) {
            if (mr.ruleName == 'Invoice Number') {
                found = true;
                System.assertEquals(90, mr.confidence, 'Partial amount should be 90%');
                System.assertEquals(250, mr.suggestedAmount);
            }
        }
        System.assert(found, 'Should find partial Invoice Number Match');
    }

    // ── Rule 2: PO Number Match ──

    @isTest
    static void testPONumberMatch() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 300, Applied_Amount__c = 0,
            Unapplied_Amount__c = 300, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'ACH',
            Reference__c = 'PO-5002 payment'
        );
        insert pmt;

        Test.startTest();
        List<ARF_CashApplicationEngine.MatchResult> results =
            ARF_CashApplicationEngine.processPayments(new List<Id>{ pmt.Id });
        Test.stopTest();

        Boolean found = false;
        for (ARF_CashApplicationEngine.MatchResult mr : results) {
            if (mr.ruleName == 'PO Number') {
                found = true;
                System.assertEquals(95, mr.confidence);
            }
        }
        System.assert(found, 'Should find PO Number Match');
    }

    // ── Rule 3: Exact Amount Match (single unique match) ──

    @isTest
    static void testExactAmountMatchUnique() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];
        // $150 matches only INV-1004
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 150, Applied_Amount__c = 0,
            Unapplied_Amount__c = 150, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'Check',
            Reference__c = 'Generic payment'
        );
        insert pmt;

        Test.startTest();
        List<ARF_CashApplicationEngine.MatchResult> results =
            ARF_CashApplicationEngine.processPayments(new List<Id>{ pmt.Id });
        Test.stopTest();

        Boolean found = false;
        for (ARF_CashApplicationEngine.MatchResult mr : results) {
            if (mr.ruleName == 'Exact Amount') {
                found = true;
                System.assertEquals(85, mr.confidence);
                System.assertEquals(150, mr.suggestedAmount);
            }
        }
        System.assert(found, 'Should find unique Exact Amount Match');
    }

    // ── Rule 3b: Exact Amount Match (multiple / ambiguous) ──

    @isTest
    static void testExactAmountMatchAmbiguous() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];

        // Create a second $200 invoice to make it ambiguous with INV-1003
        ARF_Invoice__c dup = new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 200, Balance__c = 200,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(20),
            Invoice_Date__c = Date.today().addDays(-10),
            Document_Number__c = 'INV-1006'
        );
        insert dup;

        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 200, Applied_Amount__c = 0,
            Unapplied_Amount__c = 200, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'Wire',
            Reference__c = 'Batch deposit'
        );
        insert pmt;

        Test.startTest();
        List<ARF_CashApplicationEngine.MatchResult> results =
            ARF_CashApplicationEngine.processPayments(new List<Id>{ pmt.Id });
        Test.stopTest();

        Integer multiCount = 0;
        for (ARF_CashApplicationEngine.MatchResult mr : results) {
            if (mr.ruleName == 'Exact Amount (Multi)') {
                multiCount++;
                System.assertEquals(60, mr.confidence);
            }
        }
        System.assert(multiCount >= 2, 'Should find multiple ambiguous matches');
    }

    // ── Rule 4: Sum Match (2 invoices) ──

    @isTest
    static void testSumMatch() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];
        // $450 = INV-1004 ($150) + INV-1002 ($300)
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 450, Applied_Amount__c = 0,
            Unapplied_Amount__c = 450, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'ACH',
            Reference__c = 'Consolidated remit'
        );
        insert pmt;

        Test.startTest();
        List<ARF_CashApplicationEngine.MatchResult> results =
            ARF_CashApplicationEngine.processPayments(new List<Id>{ pmt.Id });
        Test.stopTest();

        // Should find some match (sum or other)
        System.assert(!results.isEmpty(), 'Should find matches for $450 payment');
    }

    // ── Rule 5: Reference Match ──

    @isTest
    static void testReferenceMatch() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 999, Applied_Amount__c = 0,
            Unapplied_Amount__c = 999, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'Wire',
            Reference__c = 'REF-ALPHA remittance'
        );
        insert pmt;

        Test.startTest();
        List<ARF_CashApplicationEngine.MatchResult> results =
            ARF_CashApplicationEngine.processPayments(new List<Id>{ pmt.Id });
        Test.stopTest();

        Boolean found = false;
        for (ARF_CashApplicationEngine.MatchResult mr : results) {
            if (mr.ruleName == 'Reference Match') {
                found = true;
                System.assertEquals(75, mr.confidence);
            }
        }
        System.assert(found, 'Should find Reference Match for REF-ALPHA');
    }

    // ── Rule 6: Amount Proximity Match (within 5%) ──

    @isTest
    static void testAmountProximityMatch() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];

        // Create a $105 invoice for proximity testing
        ARF_Invoice__c proxInv = new ARF_Invoice__c(
            Account__c = acc.Id, Amount__c = 105, Balance__c = 105,
            Status__c = 'Open', Due_Date__c = Date.today().addDays(25),
            Invoice_Date__c = Date.today().addDays(-5),
            Document_Number__c = 'INV-1007'
        );
        insert proxInv;

        // $100 is within 5% of $105: diff=5, tolerance=5.25
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 100, Applied_Amount__c = 0,
            Unapplied_Amount__c = 100, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'Check',
            Reference__c = 'Miscellaneous'
        );
        insert pmt;

        Test.startTest();
        List<ARF_CashApplicationEngine.MatchResult> results =
            ARF_CashApplicationEngine.processPayments(new List<Id>{ pmt.Id });
        Test.stopTest();

        Boolean found = false;
        for (ARF_CashApplicationEngine.MatchResult mr : results) {
            if (mr.ruleName == 'Amount Proximity') {
                found = true;
                System.assertEquals(70, mr.confidence);
            }
        }
        System.assert(found, 'Should find Amount Proximity Match within 5% tolerance');
    }

    // ── Auto-Apply Matches ──

    @isTest
    static void testAutoApplyMatches() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-1003' LIMIT 1];
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 200, Applied_Amount__c = 0,
            Unapplied_Amount__c = 200, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'Wire'
        );
        insert pmt;

        // Create a pending result manually
        ARF_Cash_App_Result__c cr = new ARF_Cash_App_Result__c(
            Payment__c = pmt.Id, Invoice__c = inv.Id,
            Rule_Used__c = 'Exact Amount', Confidence__c = 85,
            Applied_Amount__c = 200, Status__c = 'Pending_Review'
        );
        insert cr;

        Test.startTest();
        ARF_CashApplicationEngine.ApplyResult applyRes =
            ARF_CashApplicationEngine.autoApplyMatches(new List<Id>{ cr.Id });
        Test.stopTest();

        System.assert(applyRes.successCount > 0, 'Should have successful applications');
        System.assert(applyRes.totalApplied > 0, 'Should have applied amount > 0');

        // Verify payment application record created
        List<ARF_Payment_Application__c> apps = [
            SELECT Id, Amount_Applied__c FROM ARF_Payment_Application__c WHERE Payment__c = :pmt.Id
        ];
        System.assert(!apps.isEmpty(), 'Payment Application record should exist');

        // Verify invoice balance updated
        ARF_Invoice__c updInv = [SELECT Balance__c, Status__c FROM ARF_Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(0, updInv.Balance__c, 'Invoice balance should be 0');
        System.assertEquals('Paid', updInv.Status__c, 'Invoice status should be Paid');
    }

    // ── Manual Review: Approve ──

    @isTest
    static void testReviewMatchApprove() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-1003' LIMIT 1];
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 200, Applied_Amount__c = 0,
            Unapplied_Amount__c = 200, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'ACH'
        );
        insert pmt;

        ARF_Cash_App_Result__c cr = new ARF_Cash_App_Result__c(
            Payment__c = pmt.Id, Invoice__c = inv.Id,
            Rule_Used__c = 'Manual Test', Confidence__c = 75,
            Applied_Amount__c = 200, Status__c = 'Pending_Review'
        );
        insert cr;

        Test.startTest();
        ARF_CashApplicationEngine.reviewMatch(cr.Id, 'approve', null);
        Test.stopTest();

        ARF_Cash_App_Result__c updated = [SELECT Status__c, Reviewed_By__c FROM ARF_Cash_App_Result__c WHERE Id = :cr.Id];
        System.assertEquals('Manual', updated.Status__c);
        System.assertNotEquals(null, updated.Reviewed_By__c);

        ARF_Invoice__c updInv = [SELECT Balance__c, Status__c FROM ARF_Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(0, updInv.Balance__c);
        System.assertEquals('Paid', updInv.Status__c);
    }

    // ── Manual Review: Approve with Override Amount ──

    @isTest
    static void testReviewWithOverride() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-1002' LIMIT 1];
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 300, Applied_Amount__c = 0,
            Unapplied_Amount__c = 300, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'Check'
        );
        insert pmt;

        ARF_Cash_App_Result__c cr = new ARF_Cash_App_Result__c(
            Payment__c = pmt.Id, Invoice__c = inv.Id,
            Rule_Used__c = 'Override Test', Confidence__c = 75,
            Applied_Amount__c = 300, Status__c = 'Pending_Review'
        );
        insert cr;

        Test.startTest();
        ARF_CashApplicationEngine.reviewMatch(cr.Id, 'approve', 150);
        Test.stopTest();

        ARF_Cash_App_Result__c updated = [SELECT Applied_Amount__c, Status__c FROM ARF_Cash_App_Result__c WHERE Id = :cr.Id];
        System.assertEquals('Manual', updated.Status__c);
        System.assertEquals(150, updated.Applied_Amount__c);

        ARF_Invoice__c updInv = [SELECT Balance__c FROM ARF_Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(150, updInv.Balance__c);
    }

    // ── Manual Review: Reject ──

    @isTest
    static void testReviewMatchReject() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-1003' LIMIT 1];
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 200, Applied_Amount__c = 0,
            Unapplied_Amount__c = 200, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'ACH'
        );
        insert pmt;

        ARF_Cash_App_Result__c cr = new ARF_Cash_App_Result__c(
            Payment__c = pmt.Id, Invoice__c = inv.Id,
            Rule_Used__c = 'Test', Confidence__c = 60,
            Applied_Amount__c = 200, Status__c = 'Pending_Review'
        );
        insert cr;

        Test.startTest();
        ARF_CashApplicationEngine.reviewMatch(cr.Id, 'reject', null);
        Test.stopTest();

        ARF_Cash_App_Result__c updated = [SELECT Status__c FROM ARF_Cash_App_Result__c WHERE Id = :cr.Id];
        System.assertEquals('Rejected', updated.Status__c);
    }

    // ── Stats ──

    @isTest
    static void testGetStats() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];
        ARF_Invoice__c inv = [SELECT Id FROM ARF_Invoice__c WHERE Document_Number__c = 'INV-1003' LIMIT 1];
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 200, Applied_Amount__c = 0,
            Unapplied_Amount__c = 200, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'ACH'
        );
        insert pmt;

        // Create some result records for stats
        List<ARF_Cash_App_Result__c> results = new List<ARF_Cash_App_Result__c>();
        results.add(new ARF_Cash_App_Result__c(
            Payment__c = pmt.Id, Invoice__c = inv.Id,
            Rule_Used__c = 'Invoice Number', Confidence__c = 100,
            Applied_Amount__c = 200, Status__c = 'Auto_Applied'
        ));
        results.add(new ARF_Cash_App_Result__c(
            Payment__c = pmt.Id, Invoice__c = inv.Id,
            Rule_Used__c = 'Amount Match', Confidence__c = 70,
            Applied_Amount__c = 150, Status__c = 'Pending_Review'
        ));
        results.add(new ARF_Cash_App_Result__c(
            Payment__c = pmt.Id, Invoice__c = inv.Id,
            Rule_Used__c = 'Manual', Confidence__c = 80,
            Applied_Amount__c = 100, Status__c = 'Manual'
        ));
        insert results;

        Test.startTest();
        ARF_CashApplicationEngine.CashAppStats stats = ARF_CashApplicationEngine.getStats();
        Test.stopTest();

        System.assertEquals(3, stats.totalProcessed);
        System.assertEquals(1, stats.autoAppliedCount);
        System.assertEquals(200, stats.autoAppliedAmount);
        System.assertEquals(1, stats.pendingReviewCount);
        System.assert(stats.matchRate > 0, 'Match rate should be > 0');
        System.assert(stats.avgConfidence > 0, 'Avg confidence should be > 0');
    }

    // ── No matches found (empty account) ──

    @isTest
    static void testNoMatchesFound() {
        Account acc2 = new Account(Name = 'Empty Account');
        insert acc2;

        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc2.Id, Amount__c = 999999, Applied_Amount__c = 0,
            Unapplied_Amount__c = 999999, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'Wire',
            Reference__c = 'XYZ'
        );
        insert pmt;

        Test.startTest();
        List<ARF_CashApplicationEngine.MatchResult> results =
            ARF_CashApplicationEngine.processPayments(new List<Id>{ pmt.Id });
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should find no matches for account with no invoices');
    }

    // ── Empty payment list ──

    @isTest
    static void testProcessPaymentsEmpty() {
        Test.startTest();
        List<ARF_CashApplicationEngine.MatchResult> results =
            ARF_CashApplicationEngine.processPayments(new List<Id>());
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Empty payment list should return empty results');
    }

    // ── matchPayment direct call ──

    @isTest
    static void testMatchPaymentDirect() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 500, Applied_Amount__c = 0,
            Unapplied_Amount__c = 500, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'ACH',
            Reference__c = 'INV-1001', ERP_ID__c = 'ERP123'
        );
        insert pmt;

        List<ARF_Invoice__c> invs = [
            SELECT Id, Name, Document_Number__c, Amount__c, Balance__c, Status__c,
                   Due_Date__c, Days_Past_Due__c, PO_Number__c, Reference__c, Account__c
            FROM ARF_Invoice__c WHERE Account__c = :acc.Id AND Balance__c > 0
            ORDER BY Due_Date__c ASC
        ];

        Test.startTest();
        List<ARF_CashApplicationEngine.MatchResult> results =
            ARF_CashApplicationEngine.matchPayment(pmt, invs);
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Direct matchPayment should return results');
    }

    // ── ERP_ID reference matching ──

    @isTest
    static void testERPIdInReference() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cash App Test Account' LIMIT 1];
        ARF_Payment__c pmt = new ARF_Payment__c(
            Account__c = acc.Id, Amount__c = 300, Applied_Amount__c = 0,
            Unapplied_Amount__c = 300, Status__c = 'Received',
            Payment_Date__c = Date.today(), Method__c = 'Wire',
            ERP_ID__c = 'INV-1002'
        );
        insert pmt;

        Test.startTest();
        List<ARF_CashApplicationEngine.MatchResult> results =
            ARF_CashApplicationEngine.processPayments(new List<Id>{ pmt.Id });
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Should match via ERP_ID containing invoice number');
    }
}
