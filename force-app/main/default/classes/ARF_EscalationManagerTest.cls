@isTest
private class ARF_EscalationManagerTest {

    @TestSetup
    static void setupTestData() {
        List<Account> accounts = new List<Account>();
        accounts.add(new Account(Name = 'No Escalation Acct'));    // max 30 DPD
        accounts.add(new Account(Name = 'Senior Escalation Acct')); // max 65 DPD
        accounts.add(new Account(Name = 'Manager Escalation Acct')); // max 95 DPD
        accounts.add(new Account(Name = 'Legal Escalation Acct'));  // max 125 DPD
        insert accounts;

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        // Account A: 30 days past due
        invoices.add(new ARF_Invoice__c(
            Account__c = accounts[0].Id, Document_Number__c = 'ESC-001',
            Amount__c = 5000, Balance__c = 5000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-60),
            Due_Date__c = Date.today().addDays(-30)
        ));
        // Account B: 65 days past due
        invoices.add(new ARF_Invoice__c(
            Account__c = accounts[1].Id, Document_Number__c = 'ESC-002',
            Amount__c = 10000, Balance__c = 10000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-95),
            Due_Date__c = Date.today().addDays(-65)
        ));
        // Account C: 95 days past due
        invoices.add(new ARF_Invoice__c(
            Account__c = accounts[2].Id, Document_Number__c = 'ESC-003',
            Amount__c = 15000, Balance__c = 15000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-125),
            Due_Date__c = Date.today().addDays(-95)
        ));
        // Account D: 125 days past due
        invoices.add(new ARF_Invoice__c(
            Account__c = accounts[3].Id, Document_Number__c = 'ESC-004',
            Amount__c = 20000, Balance__c = 20000, Status__c = 'Open',
            Invoice_Date__c = Date.today().addDays(-155),
            Due_Date__c = Date.today().addDays(-125)
        ));
        insert invoices;
    }

    private static Map<String, Account> getTestAccounts() {
        Map<String, Account> result = new Map<String, Account>();
        for (Account a : [SELECT Id, Name, ARF_Stop_Status__c FROM Account
                          WHERE Name LIKE '%Escalation%' OR Name = 'No Escalation Acct']) {
            result.put(a.Name, a);
        }
        return result;
    }

    @isTest
    static void testNoEscalation() {
        Map<String, Account> accts = getTestAccounts();
        Test.startTest();
        ARF_EscalationManager.escalateAccount(accts.get('No Escalation Acct').Id);
        Test.stopTest();

        Account a = [SELECT ARF_Stop_Status__c FROM Account WHERE Name = 'No Escalation Acct'];
        System.assertEquals(null, a.ARF_Stop_Status__c, 'Should not be escalated');
        List<Task> tasks = [SELECT Id FROM Task WHERE WhatId = :a.Id AND Subject LIKE 'Escalation%'];
        System.assertEquals(0, tasks.size(), 'No escalation task should be created');
    }

    @isTest
    static void testSeniorEscalation() {
        Map<String, Account> accts = getTestAccounts();
        Test.startTest();
        ARF_EscalationManager.escalateAccount(accts.get('Senior Escalation Acct').Id);
        Test.stopTest();

        Id acctId = accts.get('Senior Escalation Acct').Id;
        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :acctId AND Subject LIKE 'Escalation%'];
        System.assertEquals(1, tasks.size(), 'Should create escalation task');
        System.assert(tasks[0].Subject.contains('Senior Collector'), 'Should be senior level');
    }

    @isTest
    static void testManagerEscalation() {
        Map<String, Account> accts = getTestAccounts();
        Test.startTest();
        ARF_EscalationManager.escalateAccount(accts.get('Manager Escalation Acct').Id);
        Test.stopTest();

        Id acctId = accts.get('Manager Escalation Acct').Id;
        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :acctId AND Subject LIKE 'Escalation%'];
        System.assertEquals(1, tasks.size(), 'Should create escalation task');
        System.assert(tasks[0].Subject.contains('Manager'), 'Should be manager level');
    }

    @isTest
    static void testLegalEscalation() {
        Map<String, Account> accts = getTestAccounts();
        Test.startTest();
        ARF_EscalationManager.escalateAccount(accts.get('Legal Escalation Acct').Id);
        Test.stopTest();

        Account a = [SELECT ARF_Stop_Status__c FROM Account WHERE Name = 'Legal Escalation Acct'];
        System.assertEquals('Legal Hold', a.ARF_Stop_Status__c, 'Should be set to Legal Hold');
        List<Task> tasks = [SELECT Subject, Priority FROM Task WHERE WhatId = :a.Id AND Subject LIKE 'Escalation%'];
        System.assertEquals(1, tasks.size(), 'Should create escalation task');
        System.assert(tasks[0].Subject.contains('Legal'), 'Should be legal level');
        System.assertEquals('High', tasks[0].Priority, 'Legal should be high priority');
    }

    @isTest
    static void testGetEscalationLevel() {
        System.assertEquals('None', ARF_EscalationManager.getEscalationLevel(30));
        System.assertEquals('Senior Collector', ARF_EscalationManager.getEscalationLevel(60));
        System.assertEquals('Senior Collector', ARF_EscalationManager.getEscalationLevel(75));
        System.assertEquals('Manager', ARF_EscalationManager.getEscalationLevel(90));
        System.assertEquals('Manager', ARF_EscalationManager.getEscalationLevel(110));
        System.assertEquals('Legal', ARF_EscalationManager.getEscalationLevel(120));
        System.assertEquals('Legal', ARF_EscalationManager.getEscalationLevel(200));
        System.assertEquals('None', ARF_EscalationManager.getEscalationLevel(null));
    }

    @isTest
    static void testBulkEscalation() {
        Map<String, Account> accts = getTestAccounts();
        Set<Id> allIds = new Set<Id>();
        for (Account a : accts.values()) {
            allIds.add(a.Id);
        }
        Test.startTest();
        ARF_EscalationManager.checkAndEscalateAll(allIds);
        Test.stopTest();

        // 3 accounts should have escalation tasks (Senior, Manager, Legal)
        List<Task> tasks = [SELECT Id FROM Task WHERE Subject LIKE 'Escalation%'];
        System.assertEquals(3, tasks.size(), 'Should create 3 escalation tasks');
        // 3 communication notes
        List<ARF_Communication__c> comms = [SELECT Id FROM ARF_Communication__c WHERE Subject__c LIKE 'Auto-Escalation%'];
        System.assertEquals(3, comms.size(), 'Should create 3 escalation notes');
    }
}
