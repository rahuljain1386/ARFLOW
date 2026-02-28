public with sharing class ARF_Account360Controller {

    // ===== READ METHODS =====

    @AuraEnabled(cacheable=true)
    public static Account getAccountSummary(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        List<Account> accounts = [
            SELECT Id, Name,
                ARF_Total_AR__c, ARF_Past_Due__c, ARF_In_Dispute__c,
                ARF_Promised_Amount__c, ARF_Credit_Limit__c, ARF_Risk_Score__c,
                ARF_Available_Credit__c, ARF_DSO__c,
                ARF_Open_Invoice_Count__c, ARF_Overdue_Invoice_Count__c,
                ARF_Open_Dispute_Count__c, ARF_Assigned_Collector__c,
                ARF_Assigned_Collector__r.Name, ARF_Last_Contact_Date__c,
                ARF_Last_Payment_Date__c, ARF_Stop_Status__c,
                ARF_Collection_Strategy__c, ARF_Avg_Days_To_Pay__c,
                ARF_Sticky_Note__c, ARF_Template_Locale__c,
                ARF_Current__c, ARF_1_30_Days__c, ARF_31_60_Days__c,
                ARF_61_90_Days__c, ARF_Over_90_Days__c,
                ARF_Last_Contact_Method__c, ARF_Total_Disputed__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new AuraHandledException('Account not found');
        }
        return accounts[0];
    }

    @AuraEnabled(cacheable=true)
    public static List<Contact> getARContacts(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        return [
            SELECT Id, Name, Email, Phone,
                ARF_AR_Role__c, ARF_Primary_AR_Contact__c,
                ARF_Preferred_Channel__c, ARF_Phone_Direct__c,
                ARF_SMS_Opt_In__c
            FROM Contact
            WHERE AccountId = :accountId
            ORDER BY ARF_Primary_AR_Contact__c DESC, Name ASC
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<ARF_Invoice__c> getInvoices(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        return [
            SELECT Id, Name, Document_Number__c, Invoice_Date__c, Due_Date__c,
                Amount__c, Balance__c, Status__c, Days_Past_Due__c,
                Is_Overdue__c, Has_Dispute__c, Has_Promise__c, Promise_Status__c, PO_Number__c, Reference__c
            FROM ARF_Invoice__c
            WHERE Account__c = :accountId
                AND Status__c NOT IN ('Paid', 'Cancelled', 'Written Off')
            ORDER BY Due_Date__c ASC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<ARF_Invoice__c> getInvoicesFiltered(
        Id accountId, String viewFilter, String agingBucket, String searchText
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        String query = 'SELECT Id, Name, Document_Number__c, Invoice_Date__c, Due_Date__c, ' +
            'Amount__c, Balance__c, Status__c, Days_Past_Due__c, ' +
            'Is_Overdue__c, Has_Dispute__c, Has_Promise__c, Promise_Status__c, PO_Number__c, Reference__c ' +
            'FROM ARF_Invoice__c WHERE Account__c = :accountId ' +
            'AND Status__c NOT IN (\'Paid\', \'Cancelled\', \'Written Off\')';

        // View filter
        if (viewFilter == 'pastDue') {
            query += ' AND Is_Overdue__c = true';
        } else if (viewFilter == 'inDispute') {
            query += ' AND Has_Dispute__c = true';
        }

        // Aging bucket
        if (agingBucket == 'current') {
            query += ' AND Days_Past_Due__c = 0';
        } else if (agingBucket == '1-30') {
            query += ' AND Days_Past_Due__c >= 1 AND Days_Past_Due__c <= 30';
        } else if (agingBucket == '31-60') {
            query += ' AND Days_Past_Due__c >= 31 AND Days_Past_Due__c <= 60';
        } else if (agingBucket == '61-90') {
            query += ' AND Days_Past_Due__c >= 61 AND Days_Past_Due__c <= 90';
        } else if (agingBucket == '90+') {
            query += ' AND Days_Past_Due__c > 90';
        }

        // Search text
        if (String.isNotBlank(searchText)) {
            String searchWild = '%' + String.escapeSingleQuotes(searchText) + '%';
            query += ' AND (Document_Number__c LIKE \'' + searchWild + '\'' +
                     ' OR PO_Number__c LIKE \'' + searchWild + '\'' +
                     ' OR Reference__c LIKE \'' + searchWild + '\')';
        }

        query += ' ORDER BY Due_Date__c ASC LIMIT 500';
        return Database.query(query);
    }

    @AuraEnabled(cacheable=true)
    public static List<ARF_Dispute__c> getDisputes(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        return [
            SELECT Id, Name, Dispute_Amount__c, Status__c, Category__c,
                Priority__c, Invoice__c, Invoice__r.Document_Number__c,
                Assigned_To__c, Assigned_To__r.Name, SLA_Date__c,
                SLA_Days_Remaining__c, Root_Cause__c, CreatedDate
            FROM ARF_Dispute__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<ARF_Deduction__c> getDeductions(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        return [
            SELECT Id, Name, Amount__c, Category__c, Status__c, Type__c,
                Invoice__c, Invoice__r.Document_Number__c,
                Payment__c, Payment__r.Name, Validity_Score__c,
                Recovery_Amount__c, Recovery_Status__c,
                Customer_Reference__c, CreatedDate
            FROM ARF_Deduction__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<ARF_Communication__c> getCommunications(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        return [
            SELECT Id, Name, Channel__c, Subject__c, Direction__c,
                Sent_Date__c, Status__c, Contact__c, Contact__r.Name,
                From_Address__c, To_Address__c, Related_Invoice__c,
                Related_Invoice__r.Document_Number__c, Related_Dispute__c,
                HTML_Body__c, Body__c, CC_Addresses__c, BCC_Addresses__c,
                Has_Attachment__c, Thread_ID__c
            FROM ARF_Communication__c
            WHERE Account__c = :accountId
            ORDER BY Sent_Date__c DESC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<ARF_Payment__c> getPayments(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        return [
            SELECT Id, Name, Amount__c, Payment_Date__c, Method__c, Status__c,
                Applied_Amount__c, Unapplied_Amount__c, Reference__c,
                Has_Short_Pay__c, ERP_ID__c
            FROM ARF_Payment__c
            WHERE Account__c = :accountId
            ORDER BY Payment_Date__c DESC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<ARF_Note__c> getNotes(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        return [
            SELECT Id, Name, Title__c, Body__c, Type__c, Is_Pinned__c,
                Invoice__c, Invoice__r.Document_Number__c,
                Dispute__c, CreatedDate, CreatedById, CreatedBy.Name
            FROM ARF_Note__c
            WHERE Account__c = :accountId
            ORDER BY Is_Pinned__c DESC, CreatedDate DESC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<ARF_Promise_To_Pay__c> getPromisesToPay(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        return [
            SELECT Id, Name, Amount__c, Promise_Date__c, Status__c,
                Amount_Received__c, Broken_Count__c, Invoice__c,
                Invoice__r.Document_Number__c, Notes__c, CreatedDate
            FROM ARF_Promise_To_Pay__c
            WHERE Account__c = :accountId
            ORDER BY Promise_Date__c DESC
            LIMIT 100
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<ARF_Strategy_Execution__c> getStrategyExecutions(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        return [
            SELECT Id, Name, Strategy__c, Strategy__r.Strategy_Name__c,
                Status__c, Current_Step__c, Next_Action_Date__c,
                Last_Action_Date__c, Last_Action_Result__c
            FROM ARF_Strategy_Execution__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getAgingSummary(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        Map<String, Decimal> aging = new Map<String, Decimal>{
            'current' => 0, '1-30' => 0, '31-60' => 0, '61-90' => 0, '90+' => 0
        };
        for (ARF_Invoice__c inv : [
            SELECT Balance__c, Days_Past_Due__c
            FROM ARF_Invoice__c
            WHERE Account__c = :accountId
                AND Status__c NOT IN ('Paid', 'Cancelled', 'Written Off')
        ]) {
            Decimal bal = inv.Balance__c != null ? inv.Balance__c : 0;
            Decimal dpd = inv.Days_Past_Due__c != null ? inv.Days_Past_Due__c : 0;
            if (dpd <= 0) {
                aging.put('current', aging.get('current') + bal);
            } else if (dpd <= 30) {
                aging.put('1-30', aging.get('1-30') + bal);
            } else if (dpd <= 60) {
                aging.put('31-60', aging.get('31-60') + bal);
            } else if (dpd <= 90) {
                aging.put('61-90', aging.get('61-90') + bal);
            } else {
                aging.put('90+', aging.get('90+') + bal);
            }
        }
        return aging;
    }

    // ===== DISPUTE BULK ACTIONS =====

    @AuraEnabled
    public static void updateDisputeStatuses(List<Id> disputeIds, String newStatus) {
        if (disputeIds == null || disputeIds.isEmpty()) {
            throw new AuraHandledException('No disputes selected');
        }
        if (String.isBlank(newStatus)) {
            throw new AuraHandledException('New status is required');
        }

        List<ARF_Dispute__c> disputes = [
            SELECT Id, Status__c, Resolution_Type__c
            FROM ARF_Dispute__c
            WHERE Id IN :disputeIds
        ];

        for (ARF_Dispute__c d : disputes) {
            d.Status__c = newStatus;
            if (newStatus == 'Closed' && String.isBlank(d.Resolution_Type__c)) {
                d.Resolution_Type__c = 'Full Credit';
            }
        }

        try {
            update disputes;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ===== WRITE METHODS =====

    @AuraEnabled
    public static ARF_Communication__c createCommunication(ARF_Communication__c comm) {
        try {
            insert comm;
            return comm;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static ARF_Note__c createNote(ARF_Note__c note) {
        try {
            insert note;
            return note;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static ARF_Dispute__c createDispute(ARF_Dispute__c dispute) {
        try {
            insert dispute;
            return dispute;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static ARF_Promise_To_Pay__c createPromiseToPay(ARF_Promise_To_Pay__c promise) {
        try {
            insert promise;
            return promise;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Integer> getTabCounts(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        Map<String, Integer> counts = new Map<String, Integer>();

        counts.put('disputes', [
            SELECT COUNT() FROM ARF_Dispute__c WHERE Account__c = :accountId
        ]);
        counts.put('deductions', [
            SELECT COUNT() FROM ARF_Deduction__c WHERE Account__c = :accountId
        ]);
        counts.put('emails', [
            SELECT COUNT() FROM ARF_Communication__c WHERE Account__c = :accountId
        ]);
        counts.put('payments', [
            SELECT COUNT() FROM ARF_Payment__c WHERE Account__c = :accountId
        ]);
        counts.put('promises', [
            SELECT COUNT() FROM ARF_Promise_To_Pay__c WHERE Account__c = :accountId
        ]);
        counts.put('notes', [
            SELECT COUNT() FROM ARF_Note__c WHERE Account__c = :accountId
        ]);

        return counts;
    }

    @AuraEnabled
    public static ARF_Communication__c createReplyForward(
        Id accountId, Id originalCommId, String replyType,
        String fromAddressId, String toAddress, String ccAddresses,
        String bccAddresses, String subject, String htmlBody, Id contactId
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        try {
            ARF_Communication__c comm = new ARF_Communication__c(
                Account__c = accountId,
                Channel__c = 'Email',
                Subject__c = subject,
                HTML_Body__c = htmlBody,
                Body__c = htmlBody != null ? htmlBody.replaceAll('<[^>]+>', ' ').trim() : '',
                Direction__c = 'Outbound',
                Status__c = 'Sent',
                Sent_Date__c = Datetime.now(),
                From_Address__c = fromAddressId,
                To_Address__c = toAddress,
                CC_Addresses__c = ccAddresses,
                BCC_Addresses__c = bccAddresses,
                Contact__c = contactId
            );

            // Link thread to original communication
            if (originalCommId != null) {
                List<ARF_Communication__c> originals = [
                    SELECT Id, Thread_ID__c FROM ARF_Communication__c
                    WHERE Id = :originalCommId LIMIT 1
                ];
                if (!originals.isEmpty()) {
                    String threadId = originals[0].Thread_ID__c;
                    if (String.isBlank(threadId)) {
                        threadId = String.valueOf(originalCommId);
                    }
                    comm.Thread_ID__c = threadId;
                }
            }

            insert comm;
            return comm;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
