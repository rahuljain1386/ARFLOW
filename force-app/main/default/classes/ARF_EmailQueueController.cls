public with sharing class ARF_EmailQueueController {

    // ===== FIELD METADATA =====

    private static final List<String> ALLOWED_FIELDS = new List<String>{
        'Subject__c', 'From_Address__c', 'To_Address__c', 'Account__c',
        'Match_Method__c', 'Match_Confidence__c', 'AI_Intent__c',
        'Needs_Review__c', 'Status__c', 'Sent_Date__c', 'Has_Attachment__c'
    };

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getEmailQueueFieldMetadata() {
        List<Map<String, String>> fields = new List<Map<String, String>>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.ARF_Communication__c.fields.getMap();

        for (String fieldName : ALLOWED_FIELDS) {
            Schema.SObjectField sField = fieldMap.get(fieldName.toLowerCase());
            if (sField != null) {
                Schema.DescribeFieldResult dfr = sField.getDescribe();
                String dataType = dfr.getType().name().toLowerCase();
                if (dataType == 'currency' || dataType == 'double' || dataType == 'integer') dataType = 'number';
                if (dataType == 'datetime') dataType = 'date';
                if (dataType == 'reference') dataType = 'text';
                if (dataType == 'textarea') dataType = 'text';
                if (dataType == 'percent') dataType = 'number';

                fields.add(new Map<String, String>{
                    'apiName' => fieldName,
                    'label' => dfr.getLabel(),
                    'dataType' => dataType
                });
            }
        }
        // Add relationship field
        fields.add(new Map<String, String>{
            'apiName' => 'Account__r.Name',
            'label' => 'Account',
            'dataType' => 'text'
        });
        return fields;
    }

    // ===== DYNAMIC EMAIL QUEUE QUERY =====

    @AuraEnabled
    public static List<ARF_Communication__c> getEmailQueueDynamic(
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
        selectFields.add('Subject__c');
        selectFields.add('From_Address__c');
        selectFields.add('To_Address__c');
        selectFields.add('Account__c');
        selectFields.add('Account__r.Name');
        selectFields.add('Contact__c');
        selectFields.add('Match_Method__c');
        selectFields.add('Match_Confidence__c');
        selectFields.add('Needs_Review__c');
        selectFields.add('AI_Intent__c');
        selectFields.add('AI_Drafted__c');
        selectFields.add('Status__c');
        selectFields.add('Sent_Date__c');
        selectFields.add('Has_Attachment__c');
        selectFields.add('Body__c');

        String query = 'SELECT ' + String.join(new List<String>(selectFields), ', ');
        query += ' FROM ARF_Communication__c';
        query += ' WHERE Direction__c = \'Inbound\' AND Channel__c = \'Email\'';

        // Built-in view filters
        if (String.isNotBlank(builtinView)) {
            if (builtinView == 'unmatched') {
                query += ' AND Account__c = null';
            } else if (builtinView == 'needs_review') {
                query += ' AND Needs_Review__c = true';
            } else if (builtinView == 'ai_classified') {
                query += ' AND AI_Intent__c != null';
            }
            // 'all_inbound' — no extra filter
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
                    query += ' AND ' + safeField + ' > ' + safeValue;
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
            query += ' AND (Subject__c LIKE \'%' + safeSearch + '%\'';
            query += ' OR From_Address__c LIKE \'%' + safeSearch + '%\'';
            query += ' OR To_Address__c LIKE \'%' + safeSearch + '%\'';
            query += ' OR Account__r.Name LIKE \'%' + safeSearch + '%\')';
        }

        // Sort
        String safeSortField = String.isNotBlank(sortField) ? String.escapeSingleQuotes(sortField) : 'Sent_Date__c';
        String safeSortDir = sortDirection == 'asc' ? 'ASC' : 'DESC';
        query += ' ORDER BY ' + safeSortField + ' ' + safeSortDir + ' NULLS LAST';
        query += ' LIMIT 500';

        return Database.query(query);
    }

    // ===== ASSIGN ACCOUNT =====

    @AuraEnabled
    public static void assignAccountToCommunication(Id communicationId, Id accountId, Boolean saveSenderMapping) {
        if (communicationId == null || accountId == null) {
            throw new AuraHandledException('Communication ID and Account ID are required');
        }

        ARF_Communication__c comm = [
            SELECT Id, Account__c, From_Address__c, Match_Method__c,
                   Match_Confidence__c, Needs_Review__c
            FROM ARF_Communication__c
            WHERE Id = :communicationId
            LIMIT 1
        ];

        comm.Account__c = accountId;
        comm.Match_Method__c = 'Manual';
        comm.Match_Confidence__c = 100;
        comm.Needs_Review__c = false;
        update comm;

        // Save sender mapping if requested
        if (saveSenderMapping == true && String.isNotBlank(comm.From_Address__c)) {
            upsertSenderMap(comm.From_Address__c, accountId);
        }

        // Re-queue AI classifier now that account is linked
        System.enqueueJob(new ARF_AIEmailClassifier(communicationId));
    }

    // ===== BULK ASSIGN =====

    @AuraEnabled
    public static void bulkAssignAccount(List<Id> communicationIds, Id accountId, Boolean saveSenderMapping) {
        if (communicationIds == null || communicationIds.isEmpty() || accountId == null) {
            throw new AuraHandledException('Communication IDs and Account ID are required');
        }

        List<ARF_Communication__c> comms = [
            SELECT Id, From_Address__c
            FROM ARF_Communication__c
            WHERE Id IN :communicationIds
        ];

        Set<String> senderEmails = new Set<String>();
        for (ARF_Communication__c comm : comms) {
            comm.Account__c = accountId;
            comm.Match_Method__c = 'Manual';
            comm.Match_Confidence__c = 100;
            comm.Needs_Review__c = false;
            if (saveSenderMapping == true && String.isNotBlank(comm.From_Address__c)) {
                senderEmails.add(comm.From_Address__c);
            }
        }
        update comms;

        // Save sender mappings
        if (!senderEmails.isEmpty()) {
            List<ARF_Email_Sender_Map__c> mapsToUpsert = new List<ARF_Email_Sender_Map__c>();
            for (String email : senderEmails) {
                mapsToUpsert.add(new ARF_Email_Sender_Map__c(
                    Sender_Email__c = email.toLowerCase(),
                    Sender_Domain__c = email.substringAfter('@').toLowerCase(),
                    Account__c = accountId,
                    Confidence__c = 90,
                    Match_Count__c = 0,
                    Last_Match_Date__c = Datetime.now()
                ));
            }
            upsert mapsToUpsert Sender_Email__c;
        }

        // Re-queue AI for first comm (can't chain multiple queueables in one transaction)
        if (!comms.isEmpty()) {
            System.enqueueJob(new ARF_AIEmailClassifier(comms[0].Id));
        }
    }

    // ===== MARK AS SPAM =====

    @AuraEnabled
    public static void markAsSpam(List<Id> communicationIds) {
        if (communicationIds == null || communicationIds.isEmpty()) {
            throw new AuraHandledException('No communications selected');
        }

        List<ARF_Communication__c> comms = [
            SELECT Id FROM ARF_Communication__c WHERE Id IN :communicationIds
        ];

        for (ARF_Communication__c comm : comms) {
            comm.Needs_Review__c = false;
            comm.AI_Intent__c = 'Other';
        }
        update comms;
    }

    // ===== SEARCH ACCOUNTS =====

    @AuraEnabled
    public static List<Map<String, Object>> searchAccounts(String searchText) {
        if (String.isBlank(searchText) || searchText.length() < 2) {
            return new List<Map<String, Object>>();
        }

        String safeSearch = '%' + String.escapeSingleQuotes(searchText) + '%';
        List<Account> accounts = [
            SELECT Id, Name, AccountNumber, ARF_Total_AR__c
            FROM Account
            WHERE Name LIKE :safeSearch
            ORDER BY Name ASC
            LIMIT 20
        ];

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (Account acct : accounts) {
            results.add(new Map<String, Object>{
                'Id' => acct.Id,
                'Name' => acct.Name,
                'AccountNumber' => acct.AccountNumber,
                'TotalAR' => acct.ARF_Total_AR__c
            });
        }
        return results;
    }

    // ===== PRIVATE HELPERS =====

    private static void upsertSenderMap(String senderEmail, Id accountId) {
        ARF_Email_Sender_Map__c senderMap = new ARF_Email_Sender_Map__c(
            Sender_Email__c = senderEmail.toLowerCase(),
            Sender_Domain__c = senderEmail.substringAfter('@').toLowerCase(),
            Account__c = accountId,
            Confidence__c = 90,
            Match_Count__c = 0,
            Last_Match_Date__c = Datetime.now()
        );
        upsert senderMap Sender_Email__c;
    }
}
