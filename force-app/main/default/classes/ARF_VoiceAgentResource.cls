@RestResource(urlMapping='/arflow/voice/*')
global class ARF_VoiceAgentResource {

    // ===== GET CUSTOMER CONTEXT =====
    // Called by Retell AI / Vapi BEFORE or DURING the call
    // GET /services/apexrest/arflow/voice/context?phone=+14155551234
    // GET /services/apexrest/arflow/voice/context?accountId=001XXXX

    @HttpGet
    global static void getContext() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String phone = RestContext.request.params.get('phone');
            String accountIdParam = RestContext.request.params.get('accountId');

            Id accountId;

            if (String.isNotBlank(accountIdParam)) {
                accountId = Id.valueOf(accountIdParam);
            } else if (String.isNotBlank(phone)) {
                accountId = matchAccountByPhone(phone);
            }

            if (accountId == null) {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                    'error' => 'Account not found for the given phone/accountId'
                }));
                return;
            }

            Map<String, Object> context = buildFullContext(accountId);
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(context));

        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'error' => e.getMessage()
            }));
        }
    }

    // ===== POST ACTIONS (during or after call) =====
    // POST /services/apexrest/arflow/voice/log-promise
    // POST /services/apexrest/arflow/voice/log-dispute
    // POST /services/apexrest/arflow/voice/log-note
    // POST /services/apexrest/arflow/voice/log-call

    @HttpPost
    global static void handleAction() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String uri = req.requestURI;
            String body = req.requestBody != null ? req.requestBody.toString() : '{}';
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);

            Map<String, Object> result;

            if (uri.contains('/log-promise')) {
                result = logPromise(payload);
            } else if (uri.contains('/log-dispute')) {
                result = logDispute(payload);
            } else if (uri.contains('/log-note')) {
                result = logNote(payload);
            } else if (uri.contains('/log-call')) {
                result = logCall(payload);
            } else {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                    'error' => 'Unknown action. Use: log-promise, log-dispute, log-note, log-call'
                }));
                return;
            }

            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(result));

        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'error' => e.getMessage()
            }));
        }
    }

    // ===== CONTEXT BUILDER =====

    @TestVisible
    private static Map<String, Object> buildFullContext(Id accountId) {
        // Account details
        Account acct = [
            SELECT Id, Name, AccountNumber, Phone,
                   ARF_Risk_Score__c, ARF_Collection_Strategy__c, ARF_Last_Contact_Date__c,
                   ARF_Past_Due__c, ARF_Current__c,
                   ARF_1_30_Days__c, ARF_31_60_Days__c, ARF_61_90_Days__c, ARF_Over_90_Days__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        // Primary contact
        List<Contact> contacts = [
            SELECT Id, Name, Email, Phone, MobilePhone, ARF_AR_Role__c
            FROM Contact
            WHERE AccountId = :accountId AND ARF_Primary_AR_Contact__c = true
            LIMIT 1
        ];
        if (contacts.isEmpty()) {
            contacts = [
                SELECT Id, Name, Email, Phone, MobilePhone, ARF_AR_Role__c
                FROM Contact
                WHERE AccountId = :accountId
                ORDER BY Name ASC LIMIT 1
            ];
        }

        // Open invoices (past due first)
        List<ARF_Invoice__c> invoices = [
            SELECT Id, Document_Number__c, Invoice_Date__c, Due_Date__c,
                   Amount__c, Balance__c, Days_Past_Due__c, Status__c,
                   Has_Dispute__c, Has_Promise__c, PO_Number__c
            FROM ARF_Invoice__c
            WHERE Account__c = :accountId
              AND Status__c NOT IN ('Paid', 'Cancelled', 'Written Off')
            ORDER BY Days_Past_Due__c DESC NULLS LAST
            LIMIT 20
        ];

        // Open disputes
        List<ARF_Dispute__c> disputes = [
            SELECT Id, Invoice__r.Document_Number__c, Dispute_Amount__c,
                   Category__c, Status__c, Description__c, CreatedDate
            FROM ARF_Dispute__c
            WHERE Account__c = :accountId AND Status__c NOT IN ('Resolved', 'Rejected')
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];

        // Open promises
        List<ARF_Promise_To_Pay__c> promises = [
            SELECT Id, Invoice__r.Document_Number__c, Amount__c,
                   Promise_Date__c, Status__c, Notes__c
            FROM ARF_Promise_To_Pay__c
            WHERE Account__c = :accountId AND Status__c = 'Open'
            ORDER BY Promise_Date__c ASC
            LIMIT 10
        ];

        // Recent communications (last 5)
        List<ARF_Communication__c> recentComms = [
            SELECT Id, Channel__c, Direction__c, Subject__c, Status__c,
                   Sent_Date__c, AI_Intent__c
            FROM ARF_Communication__c
            WHERE Account__c = :accountId
            ORDER BY Sent_Date__c DESC
            LIMIT 5
        ];

        // Build the context object
        Map<String, Object> context = new Map<String, Object>();

        // Account summary
        Map<String, Object> accountInfo = new Map<String, Object>{
            'id' => acct.Id,
            'name' => acct.Name,
            'accountNumber' => acct.AccountNumber,
            'phone' => acct.Phone,
            'riskScore' => acct.ARF_Risk_Score__c,
            'collectionStrategy' => acct.ARF_Collection_Strategy__c,
            'lastContactDate' => acct.ARF_Last_Contact_Date__c,
            'totalPastDue' => acct.ARF_Past_Due__c,
            'agingCurrent' => acct.ARF_Current__c,
            'aging1to30' => acct.ARF_1_30_Days__c,
            'aging31to60' => acct.ARF_31_60_Days__c,
            'aging61to90' => acct.ARF_61_90_Days__c,
            'agingOver90' => acct.ARF_Over_90_Days__c
        };
        context.put('account', accountInfo);

        // Contact
        if (!contacts.isEmpty()) {
            Contact c = contacts[0];
            context.put('contact', new Map<String, Object>{
                'id' => c.Id,
                'name' => c.Name,
                'email' => c.Email,
                'phone' => c.Phone,
                'mobile' => c.MobilePhone,
                'role' => c.ARF_AR_Role__c
            });
        }

        // Invoices
        List<Map<String, Object>> invoiceList = new List<Map<String, Object>>();
        Decimal totalBalance = 0;
        Integer overdueCount = 0;
        for (ARF_Invoice__c inv : invoices) {
            invoiceList.add(new Map<String, Object>{
                'id' => inv.Id,
                'number' => inv.Document_Number__c,
                'invoiceDate' => inv.Invoice_Date__c,
                'dueDate' => inv.Due_Date__c,
                'amount' => inv.Amount__c,
                'balance' => inv.Balance__c,
                'daysPastDue' => inv.Days_Past_Due__c,
                'status' => inv.Status__c,
                'hasDispute' => inv.Has_Dispute__c,
                'hasPromise' => inv.Has_Promise__c,
                'poNumber' => inv.PO_Number__c
            });
            if (inv.Balance__c != null) totalBalance += inv.Balance__c;
            if (inv.Days_Past_Due__c != null && inv.Days_Past_Due__c > 0) overdueCount++;
        }
        context.put('invoices', invoiceList);
        context.put('invoiceSummary', new Map<String, Object>{
            'totalOpen' => invoices.size(),
            'totalOverdue' => overdueCount,
            'totalBalance' => totalBalance
        });

        // Disputes
        List<Map<String, Object>> disputeList = new List<Map<String, Object>>();
        for (ARF_Dispute__c d : disputes) {
            disputeList.add(new Map<String, Object>{
                'id' => d.Id,
                'invoiceNumber' => d.Invoice__r != null ? d.Invoice__r.Document_Number__c : null,
                'amount' => d.Dispute_Amount__c,
                'category' => d.Category__c,
                'status' => d.Status__c,
                'description' => d.Description__c
            });
        }
        context.put('disputes', disputeList);

        // Promises
        List<Map<String, Object>> promiseList = new List<Map<String, Object>>();
        for (ARF_Promise_To_Pay__c p : promises) {
            promiseList.add(new Map<String, Object>{
                'id' => p.Id,
                'invoiceNumber' => p.Invoice__r != null ? p.Invoice__r.Document_Number__c : null,
                'amount' => p.Amount__c,
                'promiseDate' => p.Promise_Date__c,
                'status' => p.Status__c,
                'notes' => p.Notes__c
            });
        }
        context.put('promises', promiseList);

        // Recent communications
        List<Map<String, Object>> commList = new List<Map<String, Object>>();
        for (ARF_Communication__c comm : recentComms) {
            commList.add(new Map<String, Object>{
                'channel' => comm.Channel__c,
                'direction' => comm.Direction__c,
                'subject' => comm.Subject__c,
                'status' => comm.Status__c,
                'date' => comm.Sent_Date__c,
                'aiIntent' => comm.AI_Intent__c
            });
        }
        context.put('recentCommunications', commList);

        // AI prompt hint — tells the voice agent what to focus on
        context.put('callGuidance', buildCallGuidance(acct, invoices, disputes, promises));

        return context;
    }

    // ===== CALL GUIDANCE (tells AI what to focus on) =====

    @TestVisible
    private static String buildCallGuidance(Account acct, List<ARF_Invoice__c> invoices,
                                             List<ARF_Dispute__c> disputes, List<ARF_Promise_To_Pay__c> promises) {
        String guidance = 'You are calling ' + acct.Name + '. ';

        if (invoices.isEmpty()) {
            return guidance + 'No open invoices found. This may be a follow-up call.';
        }

        // Count overdue
        Integer overdueCount = 0;
        Decimal overdueTotal = 0;
        ARF_Invoice__c oldestOverdue = null;
        for (ARF_Invoice__c inv : invoices) {
            if (inv.Days_Past_Due__c != null && inv.Days_Past_Due__c > 0) {
                overdueCount++;
                overdueTotal += inv.Balance__c != null ? inv.Balance__c : 0;
                if (oldestOverdue == null || inv.Days_Past_Due__c > oldestOverdue.Days_Past_Due__c) {
                    oldestOverdue = inv;
                }
            }
        }

        if (overdueCount > 0) {
            guidance += 'There are ' + overdueCount + ' overdue invoices totaling $' +
                overdueTotal.setScale(2).format() + '. ';
            if (oldestOverdue != null) {
                guidance += 'The oldest is ' + oldestOverdue.Document_Number__c +
                    ' at ' + oldestOverdue.Days_Past_Due__c.intValue() + ' days past due. ';
            }
        }

        if (!disputes.isEmpty()) {
            guidance += 'There are ' + disputes.size() + ' open disputes — acknowledge them and avoid pushing payment on disputed invoices. ';
        }

        if (!promises.isEmpty()) {
            guidance += 'There are ' + promises.size() + ' open promises to pay — follow up on their status. ';
        }

        guidance += 'Goal: Collect payment or get a firm promise-to-pay date. Be professional, empathetic, and solution-oriented.';

        return guidance;
    }

    // ===== ACTION: LOG PROMISE =====

    @TestVisible
    private static Map<String, Object> logPromise(Map<String, Object> payload) {
        Id accountId = Id.valueOf((String) payload.get('accountId'));
        Decimal amount = payload.get('amount') != null
            ? Decimal.valueOf(String.valueOf(payload.get('amount'))) : 0;
        String dateStr = (String) payload.get('promiseDate');
        Date promiseDate = String.isNotBlank(dateStr) ? Date.valueOf(dateStr) : Date.today().addDays(7);
        String notes = (String) payload.get('notes');
        String invoiceNumber = (String) payload.get('invoiceNumber');

        // Try to find the invoice
        Id invoiceId = null;
        if (String.isNotBlank(invoiceNumber)) {
            List<ARF_Invoice__c> invs = [
                SELECT Id FROM ARF_Invoice__c
                WHERE Document_Number__c = :invoiceNumber AND Account__c = :accountId
                LIMIT 1
            ];
            if (!invs.isEmpty()) invoiceId = invs[0].Id;
        }

        ARF_Promise_To_Pay__c promise = new ARF_Promise_To_Pay__c(
            Account__c = accountId,
            Invoice__c = invoiceId,
            Amount__c = amount,
            Promise_Date__c = promiseDate,
            Status__c = 'Open',
            Notes__c = 'Logged via AI Voice Agent. ' + (notes != null ? notes : '')
        );
        insert promise;

        return new Map<String, Object>{
            'success' => true,
            'promiseId' => promise.Id,
            'message' => 'Promise to pay recorded: $' + amount.setScale(2).format() + ' by ' + String.valueOf(promiseDate)
        };
    }

    // ===== ACTION: LOG DISPUTE =====

    @TestVisible
    private static Map<String, Object> logDispute(Map<String, Object> payload) {
        Id accountId = Id.valueOf((String) payload.get('accountId'));
        String category = (String) payload.get('category');
        String description = (String) payload.get('description');
        String invoiceNumber = (String) payload.get('invoiceNumber');
        Decimal amount = payload.get('amount') != null
            ? Decimal.valueOf(String.valueOf(payload.get('amount'))) : 0;

        Id invoiceId = null;
        if (String.isNotBlank(invoiceNumber)) {
            List<ARF_Invoice__c> invs = [
                SELECT Id, Balance__c FROM ARF_Invoice__c
                WHERE Document_Number__c = :invoiceNumber AND Account__c = :accountId
                LIMIT 1
            ];
            if (!invs.isEmpty()) {
                invoiceId = invs[0].Id;
                if (amount == 0 && invs[0].Balance__c != null) amount = invs[0].Balance__c;
            }
        }

        ARF_Dispute__c dispute = new ARF_Dispute__c(
            Account__c = accountId,
            Invoice__c = invoiceId,
            Category__c = String.isNotBlank(category) ? category : 'Other',
            Priority__c = 'Medium',
            Dispute_Amount__c = amount,
            Description__c = 'Logged via AI Voice Agent. ' + (description != null ? description : ''),
            Status__c = 'New'
        );
        insert dispute;

        // Flag invoice
        if (invoiceId != null) {
            update new ARF_Invoice__c(Id = invoiceId, Has_Dispute__c = true);
        }

        return new Map<String, Object>{
            'success' => true,
            'disputeId' => dispute.Id,
            'message' => 'Dispute created' + (invoiceNumber != null ? ' for ' + invoiceNumber : '')
        };
    }

    // ===== ACTION: LOG NOTE =====

    @TestVisible
    private static Map<String, Object> logNote(Map<String, Object> payload) {
        Id accountId = Id.valueOf((String) payload.get('accountId'));
        String title = (String) payload.get('title');
        String noteBody = (String) payload.get('body');

        ARF_Note__c note = new ARF_Note__c(
            Account__c = accountId,
            Title__c = String.isNotBlank(title) ? title : 'AI Voice Agent Note',
            Body__c = noteBody,
            Type__c = 'Call Log'
        );
        insert note;

        return new Map<String, Object>{
            'success' => true,
            'noteId' => note.Id,
            'message' => 'Note saved'
        };
    }

    // ===== ACTION: LOG CALL (after call ends) =====

    @TestVisible
    private static Map<String, Object> logCall(Map<String, Object> payload) {
        Id accountId = Id.valueOf((String) payload.get('accountId'));
        String transcript = (String) payload.get('transcript');
        String summary = (String) payload.get('summary');
        String outcome = (String) payload.get('outcome');
        Integer durationSeconds = payload.get('durationSeconds') != null
            ? Integer.valueOf(String.valueOf(payload.get('durationSeconds'))) : 0;
        String contactPhone = (String) payload.get('contactPhone');

        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = accountId,
            Channel__c = 'Phone',
            Direction__c = 'Outbound',
            Subject__c = 'AI Voice Agent Call — ' + (outcome != null ? outcome : 'Completed'),
            Body__c = (summary != null ? 'Summary: ' + summary + '\n\n' : '') +
                      'Transcript:\n' + (transcript != null ? transcript : 'No transcript available'),
            To_Address__c = contactPhone,
            Status__c = 'Sent',
            Sent_Date__c = Datetime.now(),
            Call_Duration_Seconds__c = durationSeconds,
            AI_Intent__c = outcome,
            AI_Drafted__c = true
        );
        insert comm;

        // Update last contact date
        update new Account(Id = accountId, ARF_Last_Contact_Date__c = Date.today());

        return new Map<String, Object>{
            'success' => true,
            'communicationId' => comm.Id,
            'message' => 'Call logged successfully'
        };
    }

    // ===== PHONE MATCHING =====

    @TestVisible
    private static Id matchAccountByPhone(String phoneNumber) {
        if (String.isBlank(phoneNumber)) return null;
        String digits = phoneNumber.replaceAll('[^0-9]', '');
        String last10 = digits.length() > 10 ? digits.substring(digits.length() - 10) : digits;
        String searchPattern = '%' + last10;

        // Try Contact first
        List<Contact> contacts = [
            SELECT AccountId FROM Contact
            WHERE (Phone LIKE :searchPattern OR MobilePhone LIKE :searchPattern)
              AND AccountId != null
            LIMIT 1
        ];
        if (!contacts.isEmpty()) return contacts[0].AccountId;

        // Try Account phone
        List<Account> accounts = [
            SELECT Id FROM Account WHERE Phone LIKE :searchPattern LIMIT 1
        ];
        if (!accounts.isEmpty()) return accounts[0].Id;

        return null;
    }
}
