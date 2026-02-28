public with sharing class ARF_WorklistController {

    // ===== FIELD METADATA =====

    private static final List<String> ALLOWED_FIELDS = new List<String>{
        'Subject', 'Status', 'Priority', 'ActivityDate', 'OwnerId',
        'ARF_Task_Type__c', 'ARF_Channel__c', 'ARF_Template_Name__c', 'CreatedDate'
    };

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getTaskFieldMetadata() {
        List<Map<String, String>> fields = new List<Map<String, String>>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Task.fields.getMap();

        for (String fieldName : ALLOWED_FIELDS) {
            Schema.SObjectField sField = fieldMap.get(fieldName.toLowerCase());
            if (sField != null) {
                Schema.DescribeFieldResult dfr = sField.getDescribe();
                String dataType = dfr.getType().name().toLowerCase();
                if (dataType == 'currency' || dataType == 'double' || dataType == 'integer') dataType = 'number';
                if (dataType == 'datetime') dataType = 'date';
                if (dataType == 'reference') dataType = 'text';
                if (dataType == 'textarea') dataType = 'text';

                fields.add(new Map<String, String>{
                    'apiName' => fieldName,
                    'label' => dfr.getLabel(),
                    'dataType' => dataType
                });
            }
        }
        // Add relationship fields not in fieldMap
        fields.add(new Map<String, String>{
            'apiName' => 'Owner.Name',
            'label' => 'Owner',
            'dataType' => 'text'
        });
        fields.add(new Map<String, String>{
            'apiName' => 'What.Name',
            'label' => 'Account',
            'dataType' => 'text'
        });
        return fields;
    }

    // ===== DYNAMIC TASK QUERY =====

    @AuraEnabled
    public static List<Task> getTasksDynamic(
        List<String> fields, String filterConfigJson, String sortField,
        String sortDirection, String searchText, String builtinView
    ) {
        // Build field list
        Set<String> selectFields = new Set<String>{ 'Id' };
        if (fields != null) {
            for (String f : fields) {
                selectFields.add(f);
            }
        }
        // Always include key fields
        selectFields.add('Subject');
        selectFields.add('Status');
        selectFields.add('Priority');
        selectFields.add('ActivityDate');
        selectFields.add('OwnerId');
        selectFields.add('Owner.Name');
        selectFields.add('WhatId');
        selectFields.add('What.Name');
        selectFields.add('ARF_Task_Type__c');
        selectFields.add('ARF_Channel__c');
        selectFields.add('ARF_Template_Name__c');
        selectFields.add('CreatedDate');

        String query = 'SELECT ' + String.join(new List<String>(selectFields), ', ');
        query += ' FROM Task WHERE What.Type = \'Account\'';

        // Built-in view filters
        if (String.isNotBlank(builtinView)) {
            if (builtinView == 'my_tasks') {
                query += ' AND OwnerId = \'' + String.escapeSingleQuotes(UserInfo.getUserId()) + '\'';
                query += ' AND Status != \'Completed\'';
            } else if (builtinView == 'email_tasks') {
                query += ' AND ARF_Task_Type__c = \'Email\'';
                query += ' AND Status != \'Completed\'';
            } else if (builtinView == 'phone_tasks') {
                query += ' AND ARF_Task_Type__c = \'Phone\'';
                query += ' AND Status != \'Completed\'';
            } else if (builtinView == 'overdue_tasks') {
                query += ' AND ActivityDate < TODAY';
                query += ' AND Status != \'Completed\'';
            } else if (builtinView == 'all_open') {
                query += ' AND Status != \'Completed\'';
            }
        }

        // Custom filters
        if (String.isNotBlank(filterConfigJson)) {
            List<Object> filters = (List<Object>) JSON.deserializeUntyped(filterConfigJson);
            for (Object filterObj : filters) {
                Map<String, Object> filter = (Map<String, Object>) filterObj;
                String field = (String) filter.get('field');
                String operator = (String) filter.get('operator');
                String value = (String) filter.get('value');
                String dataType = (String) filter.get('dataType');

                if (String.isBlank(field) || String.isBlank(operator) || String.isBlank(value)) continue;

                String safeField = String.escapeSingleQuotes(field);
                String safeValue = String.escapeSingleQuotes(value);

                if (operator == 'equals') {
                    if (dataType == 'number') {
                        query += ' AND ' + safeField + ' = ' + safeValue;
                    } else if (dataType == 'boolean') {
                        query += ' AND ' + safeField + ' = ' + safeValue;
                    } else if (dataType == 'date') {
                        query += ' AND ' + safeField + ' = ' + safeValue;
                    } else {
                        query += ' AND ' + safeField + ' = \'' + safeValue + '\'';
                    }
                } else if (operator == 'notEquals') {
                    query += ' AND ' + safeField + ' != \'' + safeValue + '\'';
                } else if (operator == 'contains') {
                    query += ' AND ' + safeField + ' LIKE \'%' + safeValue + '%\'';
                } else if (operator == 'greaterThan') {
                    if (dataType == 'date') {
                        query += ' AND ' + safeField + ' > ' + safeValue;
                    } else {
                        query += ' AND ' + safeField + ' > ' + safeValue;
                    }
                } else if (operator == 'lessThan') {
                    query += ' AND ' + safeField + ' < ' + safeValue;
                } else if (operator == 'greaterOrEqual') {
                    query += ' AND ' + safeField + ' >= ' + safeValue;
                } else if (operator == 'lessOrEqual') {
                    query += ' AND ' + safeField + ' <= ' + safeValue;
                }
            }
        }

        // Search
        if (String.isNotBlank(searchText)) {
            String safeSearch = String.escapeSingleQuotes(searchText);
            query += ' AND (Subject LIKE \'%' + safeSearch + '%\'';
            query += ' OR What.Name LIKE \'%' + safeSearch + '%\'';
            query += ' OR ARF_Template_Name__c LIKE \'%' + safeSearch + '%\')';
        }

        // Sort
        String safeSortField = String.isNotBlank(sortField) ? String.escapeSingleQuotes(sortField) : 'ActivityDate';
        String safeSortDir = sortDirection == 'desc' ? 'DESC' : 'ASC';
        query += ' ORDER BY ' + safeSortField + ' ' + safeSortDir + ' NULLS LAST';
        query += ' LIMIT 500';

        return Database.query(query);
    }

    // ===== MASS CLOSE TASKS =====

    @AuraEnabled
    public static void massCloseTasks(List<Id> taskIds) {
        if (taskIds == null || taskIds.isEmpty()) {
            throw new AuraHandledException('No tasks selected');
        }
        List<Task> tasks = [SELECT Id, Status FROM Task WHERE Id IN :taskIds];
        for (Task t : tasks) {
            t.Status = 'Completed';
        }
        update tasks;
    }

    // ===== COMPLETE PHONE TASK =====

    @AuraEnabled
    public static Id completePhoneTask(Id taskId, String subject, String body, Integer durationSeconds) {
        if (taskId == null) {
            throw new AuraHandledException('Task ID is required');
        }
        Task t = [SELECT Id, WhatId, OwnerId FROM Task WHERE Id = :taskId LIMIT 1];

        // Create communication record for the call
        ARF_Communication__c comm = new ARF_Communication__c(
            Account__c = t.WhatId,
            Channel__c = 'Phone',
            Direction__c = 'Outbound',
            Subject__c = String.isNotBlank(subject) ? subject : 'Phone Call',
            Body__c = body,
            Status__c = 'Sent',
            Sent_Date__c = Datetime.now(),
            Call_Duration_Seconds__c = durationSeconds
        );
        insert comm;

        // Complete the task
        t.Status = 'Completed';
        update t;

        // Update last contact date
        if (t.WhatId != null) {
            update new Account(Id = t.WhatId, ARF_Last_Contact_Date__c = Date.today());
        }

        return comm.Id;
    }

    // ===== MASS EMAIL PREPARATION =====

    public class MassEmailAccountPreview {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String contactEmail;
        @AuraEnabled public String contactName;
        @AuraEnabled public Id contactId;
        @AuraEnabled public Integer invoiceCount;
        @AuraEnabled public Decimal totalBalance;
        @AuraEnabled public String matchedTemplateName;
        @AuraEnabled public Id matchedTemplateId;
        @AuraEnabled public Boolean hasContact;
        @AuraEnabled public Boolean skip;
        @AuraEnabled public List<Id> taskIds;
    }

    public class MassEmailPreview {
        @AuraEnabled public List<MassEmailAccountPreview> accounts;
        @AuraEnabled public Integer totalAccounts;
        @AuraEnabled public Integer accountsWithContact;
        @AuraEnabled public Integer accountsWithoutContact;
    }

    @AuraEnabled
    public static MassEmailPreview prepareMassEmail(List<Id> taskIds) {
        if (taskIds == null || taskIds.isEmpty()) {
            throw new AuraHandledException('No tasks selected');
        }

        // Query tasks with account info
        List<Task> tasks = [
            SELECT Id, Subject, WhatId, What.Name, ARF_Template_Name__c
            FROM Task WHERE Id IN :taskIds AND What.Type = 'Account'
        ];

        // Group tasks by account
        Map<Id, List<Task>> tasksByAccount = new Map<Id, List<Task>>();
        for (Task t : tasks) {
            if (t.WhatId != null) {
                if (!tasksByAccount.containsKey(t.WhatId)) {
                    tasksByAccount.put(t.WhatId, new List<Task>());
                }
                tasksByAccount.get(t.WhatId).add(t);
            }
        }

        Set<Id> accountIds = tasksByAccount.keySet();

        // Bulk-load contacts
        Map<Id, Contact> primaryContacts = new Map<Id, Contact>();
        for (Contact c : [
            SELECT Id, Name, Email, AccountId FROM Contact
            WHERE AccountId IN :accountIds AND Email != null
            ORDER BY ARF_Primary_AR_Contact__c DESC, Name ASC
        ]) {
            if (!primaryContacts.containsKey(c.AccountId)) {
                primaryContacts.put(c.AccountId, c);
            }
        }

        // Bulk-load open invoice counts and balances
        Map<Id, Integer> invoiceCounts = new Map<Id, Integer>();
        Map<Id, Decimal> invoiceBalances = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Account__c acctId, COUNT(Id) cnt, SUM(Balance__c) bal
            FROM ARF_Invoice__c
            WHERE Account__c IN :accountIds
              AND Status__c NOT IN ('Paid', 'Cancelled', 'Written Off')
            GROUP BY Account__c
        ]) {
            Id acctId = (Id) ar.get('acctId');
            invoiceCounts.put(acctId, (Integer) ar.get('cnt'));
            invoiceBalances.put(acctId, (Decimal) ar.get('bal'));
        }

        // Bulk-load email templates for matching
        Map<String, ARF_Email_Template__c> templatesBySubject = new Map<String, ARF_Email_Template__c>();
        for (ARF_Email_Template__c tmpl : [
            SELECT Id, Template_Name__c, Subject__c FROM ARF_Email_Template__c
            WHERE Active__c = true ORDER BY Template_Name__c ASC
        ]) {
            templatesBySubject.put(tmpl.Subject__c, tmpl);
            templatesBySubject.put(tmpl.Template_Name__c, tmpl);
        }

        // Build preview
        MassEmailPreview preview = new MassEmailPreview();
        preview.accounts = new List<MassEmailAccountPreview>();
        preview.totalAccounts = accountIds.size();
        preview.accountsWithContact = 0;
        preview.accountsWithoutContact = 0;

        for (Id acctId : accountIds) {
            MassEmailAccountPreview acctPreview = new MassEmailAccountPreview();
            acctPreview.accountId = acctId;
            acctPreview.taskIds = new List<Id>();

            List<Task> acctTasks = tasksByAccount.get(acctId);
            acctPreview.accountName = acctTasks[0].What.Name;

            for (Task t : acctTasks) {
                acctPreview.taskIds.add(t.Id);
            }

            // Contact
            Contact primaryContact = primaryContacts.get(acctId);
            if (primaryContact != null) {
                acctPreview.contactEmail = primaryContact.Email;
                acctPreview.contactName = primaryContact.Name;
                acctPreview.contactId = primaryContact.Id;
                acctPreview.hasContact = true;
                acctPreview.skip = false;
                preview.accountsWithContact++;
            } else {
                acctPreview.hasContact = false;
                acctPreview.skip = true;
                preview.accountsWithoutContact++;
            }

            // Invoices
            acctPreview.invoiceCount = invoiceCounts.containsKey(acctId) ? invoiceCounts.get(acctId) : 0;
            acctPreview.totalBalance = invoiceBalances.containsKey(acctId) ? invoiceBalances.get(acctId) : 0;

            // Template matching — match task Subject or ARF_Template_Name__c to template
            String templateKey = acctTasks[0].ARF_Template_Name__c;
            if (String.isBlank(templateKey)) templateKey = acctTasks[0].Subject;

            if (String.isNotBlank(templateKey) && templatesBySubject.containsKey(templateKey)) {
                ARF_Email_Template__c matched = templatesBySubject.get(templateKey);
                acctPreview.matchedTemplateName = matched.Template_Name__c;
                acctPreview.matchedTemplateId = matched.Id;
            }

            preview.accounts.add(acctPreview);
        }

        return preview;
    }

    // ===== MASS EMAIL EXECUTION =====

    public class MassEmailResult {
        @AuraEnabled public Integer emailsSent = 0;
        @AuraEnabled public Integer skipped = 0;
        @AuraEnabled public Integer failed = 0;
        @AuraEnabled public List<String> errors = new List<String>();
    }

    @AuraEnabled
    public static MassEmailResult executeMassEmail(String configJson) {
        if (String.isBlank(configJson)) {
            throw new AuraHandledException('Configuration is required');
        }

        Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(configJson);
        List<Object> accountConfigs = (List<Object>) config.get('accounts');
        String attachFormat = config.containsKey('attachmentFormat') ? (String) config.get('attachmentFormat') : 'none';

        MassEmailResult result = new MassEmailResult();
        List<ARF_Communication__c> commsToInsert = new List<ARF_Communication__c>();
        List<Task> tasksToComplete = new List<Task>();
        List<Account> accountsToUpdate = new List<Account>();
        Map<Integer, Map<String, Object>> commIndexToConfig = new Map<Integer, Map<String, Object>>();

        // Collect all template IDs and account IDs for bulk queries
        Set<Id> templateIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Object acctObj : accountConfigs) {
            Map<String, Object> acctConfig = (Map<String, Object>) acctObj;
            Boolean skip = acctConfig.containsKey('skip') && (Boolean) acctConfig.get('skip');
            if (skip) {
                result.skipped++;
                continue;
            }
            if (acctConfig.containsKey('templateId') && acctConfig.get('templateId') != null) {
                templateIds.add((Id) acctConfig.get('templateId'));
            }
            accountIds.add((Id) acctConfig.get('accountId'));
        }

        // Bulk-load templates
        Map<Id, ARF_Email_Template__c> templates = new Map<Id, ARF_Email_Template__c>();
        if (!templateIds.isEmpty()) {
            templates = new Map<Id, ARF_Email_Template__c>([
                SELECT Id, Template_Name__c, Subject__c, Body_HTML__c
                FROM ARF_Email_Template__c WHERE Id IN :templateIds
            ]);
        }

        // Bulk-load accounts
        Map<Id, Account> accounts = new Map<Id, Account>([
            SELECT Id, Name, AccountNumber FROM Account WHERE Id IN :accountIds
        ]);

        // Bulk-load contacts by ID
        Set<Id> contactIds = new Set<Id>();
        for (Object acctObj : accountConfigs) {
            Map<String, Object> acctConfig = (Map<String, Object>) acctObj;
            if (acctConfig.containsKey('contactId') && acctConfig.get('contactId') != null) {
                contactIds.add((Id) acctConfig.get('contactId'));
            }
        }
        Map<Id, Contact> contactsById = new Map<Id, Contact>();
        if (!contactIds.isEmpty()) {
            contactsById = new Map<Id, Contact>([
                SELECT Id, Name, Email FROM Contact WHERE Id IN :contactIds
            ]);
        }

        // Bulk-load invoices per account
        Map<Id, List<ARF_Invoice__c>> invoicesByAccount = new Map<Id, List<ARF_Invoice__c>>();
        for (ARF_Invoice__c inv : [
            SELECT Id, Account__c, Document_Number__c, Invoice_Date__c, Due_Date__c,
                   Amount__c, Balance__c, Days_Past_Due__c, Status__c
            FROM ARF_Invoice__c
            WHERE Account__c IN :accountIds
              AND Status__c NOT IN ('Paid', 'Cancelled', 'Written Off')
            ORDER BY Due_Date__c ASC
        ]) {
            if (!invoicesByAccount.containsKey(inv.Account__c)) {
                invoicesByAccount.put(inv.Account__c, new List<ARF_Invoice__c>());
            }
            invoicesByAccount.get(inv.Account__c).add(inv);
        }

        // Process each account
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        Integer emailIndex = 0;

        for (Object acctObj : accountConfigs) {
            Map<String, Object> acctConfig = (Map<String, Object>) acctObj;
            Boolean skip = acctConfig.containsKey('skip') && (Boolean) acctConfig.get('skip');
            if (skip) continue;

            Id acctId = (Id) acctConfig.get('accountId');
            String toEmail = (String) acctConfig.get('contactEmail');
            Id contactId = acctConfig.containsKey('contactId') ? (Id) acctConfig.get('contactId') : null;
            Id templateId = acctConfig.containsKey('templateId') ? (Id) acctConfig.get('templateId') : null;

            if (String.isBlank(toEmail)) {
                result.skipped++;
                continue;
            }

            // Resolve template
            String emailSubject = 'Collection Notice';
            String emailBody = '';
            String templateName = '';

            if (templateId != null && templates.containsKey(templateId)) {
                ARF_Email_Template__c tmpl = templates.get(templateId);
                templateName = tmpl.Template_Name__c;
                Account acct = accounts.get(acctId);
                List<ARF_Invoice__c> invoices = invoicesByAccount.containsKey(acctId)
                    ? invoicesByAccount.get(acctId) : new List<ARF_Invoice__c>();

                // Resolve contact from bulk-loaded map
                Contact primaryContact = contactId != null ? contactsById.get(contactId) : null;

                String invoiceTable = ARF_TransactionActionController.buildInvoiceHtmlTable(invoices);
                emailSubject = ARF_TransactionActionController.replaceMergeFields(
                    tmpl.Subject__c, acct, primaryContact, invoices, invoiceTable
                );
                emailBody = ARF_TransactionActionController.replaceMergeFields(
                    tmpl.Body_HTML__c, acct, primaryContact, invoices, invoiceTable
                );
            }

            // Build email
            if (emails.size() < 10) {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ toEmail });
                mail.setSubject(emailSubject);
                mail.setHtmlBody(emailBody);
                mail.setWhatId(acctId);
                emails.add(mail);
            }

            // Build communication record
            ARF_Communication__c comm = new ARF_Communication__c(
                Account__c = acctId,
                Contact__c = contactId,
                Channel__c = 'Email',
                Direction__c = 'Outbound',
                Subject__c = emailSubject,
                Body__c = emailBody != null ? emailBody.stripHtmlTags() : '',
                HTML_Body__c = emailBody,
                To_Address__c = toEmail,
                Status__c = 'Sent',
                Sent_Date__c = Datetime.now(),
                Template_Used__c = templateName
            );
            commsToInsert.add(comm);

            // Collect tasks to complete
            if (acctConfig.containsKey('taskIds')) {
                List<Object> taskIdObjs = (List<Object>) acctConfig.get('taskIds');
                for (Object tid : taskIdObjs) {
                    tasksToComplete.add(new Task(Id = (Id) tid, Status = 'Completed'));
                }
            }

            // Update last contact date
            accountsToUpdate.add(new Account(Id = acctId, ARF_Last_Contact_Date__c = Date.today()));
        }

        // Send emails
        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
                result.emailsSent = emails.size();
            } catch (Exception e) {
                result.failed = emails.size();
                result.errors.add(e.getMessage());
            }
        }

        // Insert communications
        if (!commsToInsert.isEmpty()) insert commsToInsert;

        // Complete tasks
        if (!tasksToComplete.isEmpty()) update tasksToComplete;

        // Update accounts
        if (!accountsToUpdate.isEmpty()) update accountsToUpdate;

        return result;
    }

    // ===== MASS SMS PREPARATION =====

    public class MassSmsAccountPreview {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String contactName;
        @AuraEnabled public String contactPhone;
        @AuraEnabled public Id contactId;
        @AuraEnabled public Boolean hasContact;
        @AuraEnabled public Boolean skip;
        @AuraEnabled public List<Id> taskIds;
    }

    public class MassSmsPreview {
        @AuraEnabled public List<MassSmsAccountPreview> accounts;
        @AuraEnabled public Integer totalAccounts;
        @AuraEnabled public Integer accountsWithPhone;
        @AuraEnabled public Integer accountsWithoutPhone;
    }

    @AuraEnabled
    public static MassSmsPreview prepareMassSms(List<Id> taskIds) {
        if (taskIds == null || taskIds.isEmpty()) {
            throw new AuraHandledException('No tasks selected');
        }

        List<Task> tasks = [
            SELECT Id, Subject, WhatId, What.Name
            FROM Task WHERE Id IN :taskIds AND What.Type = 'Account'
        ];

        Map<Id, List<Task>> tasksByAccount = new Map<Id, List<Task>>();
        for (Task t : tasks) {
            if (t.WhatId != null) {
                if (!tasksByAccount.containsKey(t.WhatId)) {
                    tasksByAccount.put(t.WhatId, new List<Task>());
                }
                tasksByAccount.get(t.WhatId).add(t);
            }
        }

        Set<Id> accountIds = tasksByAccount.keySet();

        // Bulk-load contacts with phone
        Map<Id, Contact> primaryContacts = new Map<Id, Contact>();
        for (Contact c : [
            SELECT Id, Name, Phone, MobilePhone, ARF_Phone_Direct__c, AccountId
            FROM Contact
            WHERE AccountId IN :accountIds
            ORDER BY ARF_Primary_AR_Contact__c DESC, Name ASC
        ]) {
            if (!primaryContacts.containsKey(c.AccountId)) {
                primaryContacts.put(c.AccountId, c);
            }
        }

        MassSmsPreview preview = new MassSmsPreview();
        preview.accounts = new List<MassSmsAccountPreview>();
        preview.totalAccounts = accountIds.size();
        preview.accountsWithPhone = 0;
        preview.accountsWithoutPhone = 0;

        for (Id acctId : accountIds) {
            MassSmsAccountPreview acctPreview = new MassSmsAccountPreview();
            acctPreview.accountId = acctId;
            acctPreview.taskIds = new List<Id>();

            List<Task> acctTasks = tasksByAccount.get(acctId);
            acctPreview.accountName = acctTasks[0].What.Name;
            for (Task t : acctTasks) {
                acctPreview.taskIds.add(t.Id);
            }

            Contact c = primaryContacts.get(acctId);
            if (c != null) {
                String phone = c.MobilePhone != null ? c.MobilePhone
                    : (c.ARF_Phone_Direct__c != null ? c.ARF_Phone_Direct__c : c.Phone);
                if (String.isNotBlank(phone)) {
                    acctPreview.contactName = c.Name;
                    acctPreview.contactPhone = phone;
                    acctPreview.contactId = c.Id;
                    acctPreview.hasContact = true;
                    acctPreview.skip = false;
                    preview.accountsWithPhone++;
                } else {
                    acctPreview.hasContact = false;
                    acctPreview.skip = true;
                    preview.accountsWithoutPhone++;
                }
            } else {
                acctPreview.hasContact = false;
                acctPreview.skip = true;
                preview.accountsWithoutPhone++;
            }

            preview.accounts.add(acctPreview);
        }

        return preview;
    }

    // ===== MASS SMS EXECUTION =====

    public class MassSmsResult {
        @AuraEnabled public Integer smsSent = 0;
        @AuraEnabled public Integer skipped = 0;
        @AuraEnabled public Integer failed = 0;
        @AuraEnabled public List<String> errors = new List<String>();
    }

    @AuraEnabled
    public static MassSmsResult executeMassSms(String configJson) {
        if (String.isBlank(configJson)) {
            throw new AuraHandledException('Configuration is required');
        }

        Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(configJson);
        List<Object> accountConfigs = (List<Object>) config.get('accounts');
        String smsMessage = (String) config.get('message');

        MassSmsResult result = new MassSmsResult();
        List<ARF_Communication__c> commsToInsert = new List<ARF_Communication__c>();
        List<Task> tasksToComplete = new List<Task>();
        List<Account> accountsToUpdate = new List<Account>();

        for (Object acctObj : accountConfigs) {
            Map<String, Object> acctConfig = (Map<String, Object>) acctObj;
            Boolean skip = acctConfig.containsKey('skip') && (Boolean) acctConfig.get('skip');
            if (skip) {
                result.skipped++;
                continue;
            }

            Id acctId = (Id) acctConfig.get('accountId');
            Id contactId = acctConfig.containsKey('contactId') ? (Id) acctConfig.get('contactId') : null;
            String phone = (String) acctConfig.get('contactPhone');

            // Send SMS via Twilio if configured, otherwise log only
            String smsStatus = 'Sent';
            String smsSid = null;
            if (ARF_TwilioService.isConfigured() && String.isNotBlank(phone)) {
                try {
                    smsSid = ARF_TwilioService.sendSms(phone, smsMessage);
                } catch (Exception e) {
                    smsStatus = 'Failed';
                    result.failed++;
                    result.errors.add(acctId + ': ' + e.getMessage());
                }
            }

            ARF_Communication__c comm = new ARF_Communication__c(
                Account__c = acctId,
                Contact__c = contactId,
                Channel__c = 'SMS',
                Direction__c = 'Outbound',
                Subject__c = 'SMS: ' + (smsMessage != null && smsMessage.length() > 50 ? smsMessage.substring(0, 50) + '...' : smsMessage),
                Body__c = smsMessage,
                To_Address__c = phone,
                Status__c = smsStatus,
                Sent_Date__c = Datetime.now(),
                Thread_ID__c = smsSid
            );
            commsToInsert.add(comm);
            if (smsStatus == 'Sent') result.smsSent++;

            // Collect tasks to complete
            if (acctConfig.containsKey('taskIds')) {
                List<Object> taskIdObjs = (List<Object>) acctConfig.get('taskIds');
                for (Object tid : taskIdObjs) {
                    tasksToComplete.add(new Task(Id = (Id) tid, Status = 'Completed'));
                }
            }

            accountsToUpdate.add(new Account(Id = acctId, ARF_Last_Contact_Date__c = Date.today()));
        }

        if (!commsToInsert.isEmpty()) insert commsToInsert;
        if (!tasksToComplete.isEmpty()) update tasksToComplete;
        if (!accountsToUpdate.isEmpty()) update accountsToUpdate;

        return result;
    }
}
