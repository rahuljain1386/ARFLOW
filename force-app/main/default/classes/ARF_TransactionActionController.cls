public with sharing class ARF_TransactionActionController {

    // ===== EMAIL TEMPLATE METHODS =====

    @AuraEnabled(cacheable=true)
    public static List<ARF_Email_Template__c> getEmailTemplates(String locale, String category) {
        String query = 'SELECT Id, Template_Name__c, Subject__c, Body_HTML__c, Locale__c, Category__c, Active__c FROM ARF_Email_Template__c WHERE Active__c = true';
        if (String.isNotBlank(locale)) {
            query += ' AND Locale__c = :locale';
        }
        if (String.isNotBlank(category)) {
            query += ' AND Category__c = :category';
        }
        query += ' ORDER BY Template_Name__c ASC LIMIT 200';
        return Database.query(query);
    }

    @AuraEnabled
    public static Map<String, String> resolveTemplate(Id templateId, Id accountId, List<Id> invoiceIds) {
        if (templateId == null || accountId == null) {
            throw new AuraHandledException('Template ID and Account ID are required');
        }
        ARF_Email_Template__c template = [
            SELECT Subject__c, Body_HTML__c FROM ARF_Email_Template__c
            WHERE Id = :templateId LIMIT 1
        ];

        Account acct = [
            SELECT Name, AccountNumber FROM Account WHERE Id = :accountId LIMIT 1
        ];

        Contact primaryContact = getPrimaryContact(accountId);

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();
        if (invoiceIds != null && !invoiceIds.isEmpty()) {
            invoices = [
                SELECT Document_Number__c, Invoice_Date__c, Due_Date__c,
                       Amount__c, Balance__c, Days_Past_Due__c, Status__c
                FROM ARF_Invoice__c
                WHERE Id IN :invoiceIds
                ORDER BY Due_Date__c ASC
            ];
        }

        String invoiceTableHtml = buildInvoiceHtmlTable(invoices);
        String resolvedSubject = replaceMergeFields(
            template.Subject__c, acct, primaryContact, invoices, invoiceTableHtml
        );
        String resolvedBody = replaceMergeFields(
            template.Body_HTML__c, acct, primaryContact, invoices, invoiceTableHtml
        );

        return new Map<String, String>{
            'subject' => resolvedSubject,
            'body' => resolvedBody
        };
    }

    // ===== ORG-WIDE EMAIL =====

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getOrgWideEmailAddresses() {
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (OrgWideEmailAddress owa : [
            SELECT Id, DisplayName, Address FROM OrgWideEmailAddress
            WHERE IsAllowAllProfiles = true ORDER BY DisplayName ASC
        ]) {
            result.add(new Map<String, String>{
                'id' => owa.Id,
                'displayName' => owa.DisplayName,
                'address' => owa.Address
            });
        }
        return result;
    }

    // ===== CURRENT USER EMAIL =====

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getCurrentUserEmail() {
        return new Map<String, String>{
            'email' => UserInfo.getUserEmail(),
            'name' => UserInfo.getName()
        };
    }

    // ===== CONTACT EMAIL HELPERS =====

    @AuraEnabled
    public static Map<String, Object> getContactsForEmail(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        List<Contact> allContacts = [
            SELECT Id, Name, Email, ARF_Primary_AR_Contact__c, ARF_AR_Role__c
            FROM Contact
            WHERE AccountId = :accountId AND Email != null
            ORDER BY ARF_Primary_AR_Contact__c DESC, Name ASC
            LIMIT 50
        ];
        List<Map<String, String>> toContacts = new List<Map<String, String>>();
        List<Map<String, String>> ccContacts = new List<Map<String, String>>();
        for (Contact c : allContacts) {
            Map<String, String> contactMap = new Map<String, String>{
                'id' => c.Id,
                'name' => c.Name,
                'email' => c.Email,
                'role' => c.ARF_AR_Role__c != null ? c.ARF_AR_Role__c : ''
            };
            if (c.ARF_Primary_AR_Contact__c == true) {
                toContacts.add(contactMap);
            } else {
                ccContacts.add(contactMap);
            }
        }
        return new Map<String, Object>{
            'toContacts' => toContacts,
            'ccContacts' => ccContacts
        };
    }

    // ===== CONTACT CUSTOMER =====

    @AuraEnabled
    public static Id executeContactCustomer(
        Id accountId, List<Id> invoiceIds, String channel,
        String fromAddressId, String toAddress, String ccAddresses, String bccAddresses,
        String subject, String htmlBody, Boolean attachStatement, Id contactId,
        String templateName, String noteCategory, String noteTitle, String noteBody,
        Boolean createFollowUp, Integer followUpDays, String followUpSubject, String followUpBody
    ) {
        return executeContactCustomerWithFormat(
            accountId, invoiceIds, channel, fromAddressId, toAddress, ccAddresses, bccAddresses,
            subject, htmlBody, attachStatement, contactId, templateName,
            noteCategory, noteTitle, noteBody, createFollowUp, followUpDays, followUpSubject, followUpBody, 'csv'
        );
    }

    @AuraEnabled
    public static Id executeContactCustomerWithFormat(
        Id accountId, List<Id> invoiceIds, String channel,
        String fromAddressId, String toAddress, String ccAddresses, String bccAddresses,
        String subject, String htmlBody, Boolean attachStatement, Id contactId,
        String templateName, String noteCategory, String noteTitle, String noteBody,
        Boolean createFollowUp, Integer followUpDays, String followUpSubject, String followUpBody,
        String attachmentFormat
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        if (invoiceIds == null || invoiceIds.isEmpty()) {
            throw new AuraHandledException('At least one invoice must be selected');
        }

        // Query invoices for totals
        List<ARF_Invoice__c> invoices = [
            SELECT Id, Balance__c FROM ARF_Invoice__c WHERE Id IN :invoiceIds
        ];
        Decimal totalBalance = 0;
        for (ARF_Invoice__c inv : invoices) {
            if (inv.Balance__c != null) totalBalance += inv.Balance__c;
        }

        // 1. Create Communication record
        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = accountId,
            Channel__c = channel == 'Print' ? 'Letter' : channel,
            Direction__c = 'Outbound',
            Subject__c = subject,
            Body__c = htmlBody != null ? htmlBody.stripHtmlTags() : '',
            HTML_Body__c = htmlBody,
            To_Address__c = toAddress,
            CC_Addresses__c = ccAddresses,
            BCC_Addresses__c = bccAddresses,
            Contact__c = contactId,
            Status__c = 'Draft',
            Sent_Date__c = Datetime.now(),
            Template_Used__c = templateName,
            Has_Attachment__c = attachStatement == true,
            Invoice_Count__c = invoiceIds.size(),
            Total_Balance__c = totalBalance
        );
        if (String.isNotBlank(fromAddressId)) {
            comm.From_Address__c = fromAddressId;
        }
        insert comm;

        // 2. Create junction records
        List<ARF_Communication_Invoice__c> junctions = new List<ARF_Communication_Invoice__c>();
        for (Id invId : invoiceIds) {
            junctions.add(new ARF_Communication_Invoice__c(
                Communication__c = comm.Id,
                Invoice__c = invId
            ));
        }
        insert junctions;

        // 3. If email channel and sending enabled, send actual email
        String format = String.isNotBlank(attachmentFormat) ? attachmentFormat : 'csv';
        if (channel == 'Email' && String.isNotBlank(toAddress)) {
            try {
                sendEmail(comm, fromAddressId, toAddress, ccAddresses, bccAddresses,
                         subject, htmlBody, attachStatement, accountId, invoiceIds, format);
                comm.Status__c = 'Sent';
                update comm;
            } catch (Exception e) {
                comm.Status__c = 'Failed';
                update comm;
            }
        }

        // 4. Create Note if populated
        if (String.isNotBlank(noteTitle)) {
            ARF_Note__c note = new ARF_Note__c(
                Account__c = accountId,
                Title__c = noteTitle,
                Body__c = noteBody,
                Type__c = String.isNotBlank(noteCategory) ? noteCategory : 'General'
            );
            insert note;
        }

        // 5. Create follow-up Task
        if (createFollowUp == true && followUpDays != null && followUpDays > 0) {
            Task followUp = new Task(
                WhatId = accountId,
                Subject = String.isNotBlank(followUpSubject) ? followUpSubject : 'Follow up on collection email',
                Description = followUpBody,
                ActivityDate = Date.today().addDays(followUpDays),
                Priority = 'Normal',
                Status = 'Not Started'
            );
            insert followUp;
        }

        // 6. Update last contact date
        update new Account(Id = accountId, ARF_Last_Contact_Date__c = Date.today());

        return comm.Id;
    }

    // ===== CSV GENERATION =====

    @AuraEnabled
    public static String generateInvoiceCsv(Id accountId, List<Id> invoiceIds) {
        if (accountId == null || invoiceIds == null || invoiceIds.isEmpty()) {
            throw new AuraHandledException('Account ID and invoice IDs are required');
        }
        List<ARF_Invoice__c> invoices = [
            SELECT Document_Number__c, Invoice_Date__c, Due_Date__c,
                   Amount__c, Balance__c, Status__c, Days_Past_Due__c,
                   PO_Number__c, Reference__c
            FROM ARF_Invoice__c
            WHERE Id IN :invoiceIds AND Account__c = :accountId
            ORDER BY Due_Date__c ASC
        ];

        String csv = 'Document Number,Invoice Date,Due Date,Amount,Balance,Status,Days Past Due,PO Number,Reference\n';
        for (ARF_Invoice__c inv : invoices) {
            csv += '"' + safe(inv.Document_Number__c) + '",';
            csv += safe(String.valueOf(inv.Invoice_Date__c)) + ',';
            csv += safe(String.valueOf(inv.Due_Date__c)) + ',';
            csv += safe(String.valueOf(inv.Amount__c)) + ',';
            csv += safe(String.valueOf(inv.Balance__c)) + ',';
            csv += '"' + safe(inv.Status__c) + '",';
            csv += safe(String.valueOf(inv.Days_Past_Due__c)) + ',';
            csv += '"' + safe(inv.PO_Number__c) + '",';
            csv += '"' + safe(inv.Reference__c) + '"\n';
        }
        return EncodingUtil.base64Encode(Blob.valueOf(csv));
    }

    // ===== BULK NOTES =====

    @AuraEnabled
    public static List<ARF_Note__c> createBulkNotes(
        Id accountId, List<Id> invoiceIds, String noteTitle, String noteBody, String noteType
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        if (invoiceIds == null || invoiceIds.isEmpty()) {
            throw new AuraHandledException('At least one invoice must be selected');
        }
        List<ARF_Note__c> notes = new List<ARF_Note__c>();
        for (Id invId : invoiceIds) {
            notes.add(new ARF_Note__c(
                Account__c = accountId,
                Invoice__c = invId,
                Title__c = noteTitle,
                Body__c = noteBody,
                Type__c = String.isNotBlank(noteType) ? noteType : 'General'
            ));
        }
        insert notes;
        return notes;
    }

    // ===== BULK DISPUTES =====

    @AuraEnabled
    public static List<ARF_Dispute__c> createBulkDisputes(
        Id accountId, List<Id> invoiceIds, String category, String priority, String description
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        if (invoiceIds == null || invoiceIds.isEmpty()) {
            throw new AuraHandledException('At least one invoice must be selected');
        }
        // Query invoice balances for dispute amounts
        Map<Id, ARF_Invoice__c> invoiceMap = new Map<Id, ARF_Invoice__c>([
            SELECT Id, Balance__c FROM ARF_Invoice__c WHERE Id IN :invoiceIds
        ]);
        List<ARF_Dispute__c> disputes = new List<ARF_Dispute__c>();
        for (Id invId : invoiceIds) {
            ARF_Invoice__c inv = invoiceMap.get(invId);
            disputes.add(new ARF_Dispute__c(
                Account__c = accountId,
                Invoice__c = invId,
                Dispute_Amount__c = inv != null && inv.Balance__c != null ? inv.Balance__c : 0,
                Category__c = category,
                Priority__c = String.isNotBlank(priority) ? priority : 'Medium',
                Description__c = description,
                Status__c = 'New'
            ));
        }
        insert disputes;
        return disputes;
    }

    // ===== BULK PROMISES =====

    @AuraEnabled
    public static List<ARF_Promise_To_Pay__c> createBulkPromises(
        Id accountId, List<Id> invoiceIds, Decimal totalAmount, Date promiseDate, String notes
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        if (invoiceIds == null || invoiceIds.isEmpty()) {
            throw new AuraHandledException('At least one invoice must be selected');
        }
        if (totalAmount == null || totalAmount <= 0) {
            throw new AuraHandledException('Total amount must be greater than 0');
        }
        if (promiseDate == null) {
            throw new AuraHandledException('Promise date is required');
        }

        // Proportional allocation based on balance
        List<ARF_Invoice__c> invoices = [
            SELECT Id, Balance__c FROM ARF_Invoice__c WHERE Id IN :invoiceIds
        ];
        Decimal sumBalance = 0;
        for (ARF_Invoice__c inv : invoices) {
            if (inv.Balance__c != null && inv.Balance__c > 0) sumBalance += inv.Balance__c;
        }

        List<ARF_Promise_To_Pay__c> promises = new List<ARF_Promise_To_Pay__c>();
        Decimal allocated = 0;
        for (Integer i = 0; i < invoices.size(); i++) {
            ARF_Invoice__c inv = invoices[i];
            Decimal invBalance = inv.Balance__c != null && inv.Balance__c > 0 ? inv.Balance__c : 0;
            Decimal amount;
            if (i == invoices.size() - 1) {
                amount = totalAmount - allocated;
            } else if (sumBalance > 0) {
                amount = (totalAmount * invBalance / sumBalance).setScale(2, RoundingMode.HALF_UP);
            } else {
                amount = (totalAmount / invoices.size()).setScale(2, RoundingMode.HALF_UP);
            }
            allocated += amount;
            promises.add(new ARF_Promise_To_Pay__c(
                Account__c = accountId,
                Invoice__c = inv.Id,
                Amount__c = amount,
                Amount_Received__c = 0,
                Promise_Date__c = promiseDate,
                Status__c = 'Open',
                Notes__c = notes
            ));
        }
        insert promises;
        return promises;
    }

    // ===== ENHANCED BULK METHODS =====

    @AuraEnabled
    public static List<ARF_Dispute__c> createBulkDisputesEnhanced(Id accountId, String disputeConfigJson) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        if (String.isBlank(disputeConfigJson)) {
            throw new AuraHandledException('Dispute configuration is required');
        }

        List<Object> configs = (List<Object>) JSON.deserializeUntyped(disputeConfigJson);
        if (configs.isEmpty()) {
            throw new AuraHandledException('At least one dispute configuration is required');
        }

        List<ARF_Dispute__c> disputes = new List<ARF_Dispute__c>();
        Set<Id> invoiceIds = new Set<Id>();

        for (Object configObj : configs) {
            Map<String, Object> config = (Map<String, Object>) configObj;
            Id invoiceId = Id.valueOf((String) config.get('invoiceId'));
            invoiceIds.add(invoiceId);

            Decimal amount = config.get('amount') != null ? Decimal.valueOf(String.valueOf(config.get('amount'))) : 0;
            disputes.add(new ARF_Dispute__c(
                Account__c = accountId,
                Invoice__c = invoiceId,
                Category__c = (String) config.get('category'),
                Root_Cause__c = (String) config.get('rootCause'),
                Priority__c = String.isNotBlank((String) config.get('priority')) ? (String) config.get('priority') : 'Medium',
                Dispute_Amount__c = amount,
                Description__c = (String) config.get('description'),
                Status__c = 'New'
            ));
        }

        insert disputes;

        // Set Has_Dispute__c flag on affected invoices
        List<ARF_Invoice__c> invoicesToUpdate = [
            SELECT Id, Has_Dispute__c FROM ARF_Invoice__c WHERE Id IN :invoiceIds
        ];
        for (ARF_Invoice__c inv : invoicesToUpdate) {
            inv.Has_Dispute__c = true;
        }
        update invoicesToUpdate;

        return disputes;
    }

    @AuraEnabled
    public static List<ARF_Promise_To_Pay__c> createBulkPromisesEnhanced(Id accountId, String promiseConfigJson) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        if (String.isBlank(promiseConfigJson)) {
            throw new AuraHandledException('Promise configuration is required');
        }

        List<Object> configs = (List<Object>) JSON.deserializeUntyped(promiseConfigJson);
        if (configs.isEmpty()) {
            throw new AuraHandledException('At least one promise configuration is required');
        }

        List<ARF_Promise_To_Pay__c> promises = new List<ARF_Promise_To_Pay__c>();
        Set<Id> invoiceIds = new Set<Id>();

        for (Object configObj : configs) {
            Map<String, Object> config = (Map<String, Object>) configObj;
            Id invoiceId = Id.valueOf((String) config.get('invoiceId'));
            invoiceIds.add(invoiceId);

            Decimal amount = config.get('amount') != null ? Decimal.valueOf(String.valueOf(config.get('amount'))) : 0;
            Date promiseDate = config.get('promiseDate') != null ? Date.valueOf((String) config.get('promiseDate')) : Date.today().addDays(7);
            String notes = (String) config.get('notes');

            promises.add(new ARF_Promise_To_Pay__c(
                Account__c = accountId,
                Invoice__c = invoiceId,
                Amount__c = amount,
                Amount_Received__c = 0,
                Promise_Date__c = promiseDate,
                Status__c = 'Open',
                Notes__c = notes
            ));
        }

        insert promises;

        // Set Has_Promise__c flag on affected invoices
        List<ARF_Invoice__c> invoicesToUpdate = [
            SELECT Id, Has_Promise__c FROM ARF_Invoice__c WHERE Id IN :invoiceIds
        ];
        for (ARF_Invoice__c inv : invoicesToUpdate) {
            inv.Has_Promise__c = true;
        }
        update invoicesToUpdate;

        return promises;
    }

    // ===== PRIVATE HELPERS =====

    private static Contact getPrimaryContact(Id accountId) {
        List<Contact> contacts = [
            SELECT Name, Email FROM Contact
            WHERE AccountId = :accountId AND ARF_Primary_AR_Contact__c = true
            LIMIT 1
        ];
        if (contacts.isEmpty()) {
            contacts = [
                SELECT Name, Email FROM Contact
                WHERE AccountId = :accountId
                ORDER BY Name ASC LIMIT 1
            ];
        }
        return contacts.isEmpty() ? null : contacts[0];
    }

    @TestVisible
    private static String buildInvoiceHtmlTable(List<ARF_Invoice__c> invoices) {
        if (invoices == null || invoices.isEmpty()) return '';
        String html = '<table style="border-collapse:collapse;width:100%;font-family:Arial,sans-serif;font-size:12px;">';
        html += '<tr style="background-color:#f2f2f2;">';
        html += '<th style="border:1px solid #ddd;padding:8px;text-align:left;">Document #</th>';
        html += '<th style="border:1px solid #ddd;padding:8px;text-align:left;">Invoice Date</th>';
        html += '<th style="border:1px solid #ddd;padding:8px;text-align:left;">Due Date</th>';
        html += '<th style="border:1px solid #ddd;padding:8px;text-align:right;">Amount</th>';
        html += '<th style="border:1px solid #ddd;padding:8px;text-align:right;">Balance</th>';
        html += '<th style="border:1px solid #ddd;padding:8px;text-align:right;">Days Past Due</th>';
        html += '</tr>';

        Decimal totalBalance = 0;
        for (ARF_Invoice__c inv : invoices) {
            html += '<tr>';
            html += '<td style="border:1px solid #ddd;padding:8px;">' + safe(inv.Document_Number__c) + '</td>';
            html += '<td style="border:1px solid #ddd;padding:8px;">' + safe(String.valueOf(inv.Invoice_Date__c)) + '</td>';
            html += '<td style="border:1px solid #ddd;padding:8px;">' + safe(String.valueOf(inv.Due_Date__c)) + '</td>';
            html += '<td style="border:1px solid #ddd;padding:8px;text-align:right;">$' + (inv.Amount__c != null ? inv.Amount__c.setScale(2).format() : '0.00') + '</td>';
            html += '<td style="border:1px solid #ddd;padding:8px;text-align:right;">$' + (inv.Balance__c != null ? inv.Balance__c.setScale(2).format() : '0.00') + '</td>';
            html += '<td style="border:1px solid #ddd;padding:8px;text-align:right;">' + (inv.Days_Past_Due__c != null ? String.valueOf(inv.Days_Past_Due__c.intValue()) : '0') + '</td>';
            html += '</tr>';
            if (inv.Balance__c != null) totalBalance += inv.Balance__c;
        }

        html += '<tr style="font-weight:bold;background-color:#f2f2f2;">';
        html += '<td style="border:1px solid #ddd;padding:8px;" colspan="4">Total</td>';
        html += '<td style="border:1px solid #ddd;padding:8px;text-align:right;">$' + totalBalance.setScale(2).format() + '</td>';
        html += '<td style="border:1px solid #ddd;padding:8px;"></td>';
        html += '</tr></table>';
        return html;
    }

    @TestVisible
    private static String replaceMergeFields(
        String template, Account acct, Contact primaryContact,
        List<ARF_Invoice__c> invoices, String invoiceTableHtml
    ) {
        if (String.isBlank(template)) return '';
        String result = template;
        result = result.replace('{account_name}', acct.Name != null ? acct.Name : '');
        result = result.replace('{account_number}', acct.AccountNumber != null ? acct.AccountNumber : '');
        result = result.replace('{contact_name}', primaryContact != null && primaryContact.Name != null ? primaryContact.Name : '');
        result = result.replace('{collector_name}', UserInfo.getName());
        result = result.replace('{invoice_count}', String.valueOf(invoices != null ? invoices.size() : 0));

        Decimal totalBalance = 0;
        Decimal pastDueAmount = 0;
        if (invoices != null) {
            for (ARF_Invoice__c inv : invoices) {
                if (inv.Balance__c != null) totalBalance += inv.Balance__c;
                if (inv.Days_Past_Due__c != null && inv.Days_Past_Due__c > 0 && inv.Balance__c != null) {
                    pastDueAmount += inv.Balance__c;
                }
            }
        }
        result = result.replace('{total_balance}', '$' + totalBalance.setScale(2).format());
        result = result.replace('{past_due_amount}', '$' + pastDueAmount.setScale(2).format());
        result = result.replace('{invoice_table}', invoiceTableHtml != null ? invoiceTableHtml : '');
        return result;
    }

    private static void sendEmail(
        ARF_Communication__c comm, String fromAddressId, String toAddress,
        String ccAddresses, String bccAddresses, String subject, String htmlBody,
        Boolean attachStatement, Id accountId, List<Id> invoiceIds, String attachmentFormat
    ) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ toAddress });
        if (String.isNotBlank(ccAddresses)) {
            mail.setCcAddresses(ccAddresses.split(';'));
        }
        if (String.isNotBlank(bccAddresses)) {
            mail.setBccAddresses(bccAddresses.split(';'));
        }
        if (String.isNotBlank(fromAddressId)) {
            try {
                mail.setOrgWideEmailAddressId(fromAddressId);
            } catch (Exception e) {
                // Fallback to default sender
            }
        }
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        mail.setWhatId(accountId);

        if (attachStatement == true) {
            String format = String.isNotBlank(attachmentFormat) ? attachmentFormat : 'csv';
            if (format == 'pdf') {
                String pdfBase64 = ARF_InvoiceStatementPDFCtrl.generatePdf(accountId, invoiceIds);
                Messaging.EmailFileAttachment pdfAttach = new Messaging.EmailFileAttachment();
                pdfAttach.setFileName('Invoice_Statement.pdf');
                pdfAttach.setBody(EncodingUtil.base64Decode(pdfBase64));
                pdfAttach.setContentType('application/pdf');
                mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ pdfAttach });
            } else {
                String csvBase64 = generateInvoiceCsv(accountId, invoiceIds);
                Messaging.EmailFileAttachment csvAttach = new Messaging.EmailFileAttachment();
                csvAttach.setFileName('Invoice_Statement.csv');
                csvAttach.setBody(EncodingUtil.base64Decode(csvBase64));
                csvAttach.setContentType('text/csv');
                mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ csvAttach });
            }
        }

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    }

    private static String safe(String val) {
        return val != null ? val.replace('"', '""') : '';
    }
}
