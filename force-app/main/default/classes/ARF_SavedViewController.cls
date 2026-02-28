public with sharing class ARF_SavedViewController {

    // Allowlisted fields that can be queried dynamically
    private static final Set<String> ALLOWED_FIELDS = new Set<String>{
        'Id', 'Name', 'Document_Number__c', 'Invoice_Date__c', 'Due_Date__c',
        'Amount__c', 'Balance__c', 'Status__c', 'Days_Past_Due__c',
        'Is_Overdue__c', 'Has_Dispute__c', 'Has_Promise__c', 'PO_Number__c', 'Reference__c',
        'Bill_To__c', 'Ship_To__c', 'ERP_ID__c', 'ERP_Source__c'
    };

    // Field type mapping for filter building
    private static final Map<String, String> FIELD_TYPES = new Map<String, String>{
        'Document_Number__c' => 'text',
        'Invoice_Date__c' => 'date',
        'Due_Date__c' => 'date',
        'Amount__c' => 'currency',
        'Balance__c' => 'currency',
        'Status__c' => 'picklist',
        'Days_Past_Due__c' => 'number',
        'Is_Overdue__c' => 'boolean',
        'Has_Dispute__c' => 'boolean',
        'Has_Promise__c' => 'boolean',
        'PO_Number__c' => 'text',
        'Reference__c' => 'text',
        'Bill_To__c' => 'text',
        'Ship_To__c' => 'text',
        'ERP_ID__c' => 'text',
        'ERP_Source__c' => 'text'
    };

    // Text fields eligible for search LIKE matching
    private static final Set<String> SEARCHABLE_FIELDS = new Set<String>{
        'Document_Number__c', 'PO_Number__c', 'Reference__c',
        'Bill_To__c', 'Ship_To__c', 'ERP_ID__c'
    };

    // ===== FIELD METADATA =====

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getInvoiceFieldMetadata() {
        List<Map<String, String>> fields = new List<Map<String, String>>();

        fields.add(buildFieldMeta('Document_Number__c', 'Invoice #', 'text'));
        fields.add(buildFieldMeta('Invoice_Date__c', 'Invoice Date', 'date'));
        fields.add(buildFieldMeta('Due_Date__c', 'Due Date', 'date'));
        fields.add(buildFieldMeta('Amount__c', 'Amount', 'currency'));
        fields.add(buildFieldMeta('Balance__c', 'Balance', 'currency'));
        fields.add(buildFieldMeta('Status__c', 'Status', 'picklist'));
        fields.add(buildFieldMeta('Days_Past_Due__c', 'Days Past Due', 'number'));
        fields.add(buildFieldMeta('Is_Overdue__c', 'Is Overdue', 'boolean'));
        fields.add(buildFieldMeta('Has_Dispute__c', 'Has Dispute', 'boolean'));
        fields.add(buildFieldMeta('Has_Promise__c', 'Has Promise', 'boolean'));
        fields.add(buildFieldMeta('PO_Number__c', 'PO Number', 'text'));
        fields.add(buildFieldMeta('Reference__c', 'Reference', 'text'));
        fields.add(buildFieldMeta('Bill_To__c', 'Bill To', 'text'));
        fields.add(buildFieldMeta('Ship_To__c', 'Ship To', 'text'));
        fields.add(buildFieldMeta('ERP_ID__c', 'ERP ID', 'text'));
        fields.add(buildFieldMeta('ERP_Source__c', 'ERP Source', 'text'));

        return fields;
    }

    private static Map<String, String> buildFieldMeta(String apiName, String label, String dataType) {
        Map<String, String> field = new Map<String, String>();
        field.put('apiName', apiName);
        field.put('label', label);
        field.put('dataType', dataType);
        return field;
    }

    // ===== VIEW CRUD =====

    @AuraEnabled
    public static List<ARF_Saved_View__c> getMyViews(String objectName) {
        if (String.isBlank(objectName)) {
            throw new AuraHandledException('Object name is required');
        }
        return [
            SELECT Id, Name, View_Name__c, Object_Name__c, Column_Config__c,
                Filter_Config__c, Sort_Field__c, Sort_Direction__c, Is_Default__c
            FROM ARF_Saved_View__c
            WHERE OwnerId = :UserInfo.getUserId()
                AND Object_Name__c = :objectName
            ORDER BY Is_Default__c DESC, View_Name__c ASC
            LIMIT 50
        ];
    }

    @AuraEnabled
    public static ARF_Saved_View__c saveView(ARF_Saved_View__c view) {
        if (view == null) {
            throw new AuraHandledException('View data is required');
        }
        try {
            // If marking as default, clear existing defaults
            if (view.Is_Default__c == true) {
                clearDefaultViews(view.Object_Name__c, view.Id);
            }
            upsert view;
            return view;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteView(Id viewId) {
        if (viewId == null) {
            throw new AuraHandledException('View ID is required');
        }
        List<ARF_Saved_View__c> views = [
            SELECT Id, OwnerId FROM ARF_Saved_View__c
            WHERE Id = :viewId LIMIT 1
        ];
        if (views.isEmpty()) {
            throw new AuraHandledException('View not found');
        }
        if (views[0].OwnerId != UserInfo.getUserId()) {
            throw new AuraHandledException('You can only delete your own views');
        }
        try {
            delete views[0];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void setDefaultView(Id viewId) {
        if (viewId == null) {
            throw new AuraHandledException('View ID is required');
        }
        List<ARF_Saved_View__c> views = [
            SELECT Id, Object_Name__c, Is_Default__c FROM ARF_Saved_View__c
            WHERE Id = :viewId AND OwnerId = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (views.isEmpty()) {
            throw new AuraHandledException('View not found');
        }
        clearDefaultViews(views[0].Object_Name__c, viewId);
        views[0].Is_Default__c = true;
        update views[0];
    }

    private static void clearDefaultViews(String objectName, Id excludeId) {
        List<ARF_Saved_View__c> defaults = [
            SELECT Id, Is_Default__c FROM ARF_Saved_View__c
            WHERE OwnerId = :UserInfo.getUserId()
                AND Object_Name__c = :objectName
                AND Is_Default__c = true
                AND Id != :excludeId
        ];
        for (ARF_Saved_View__c v : defaults) {
            v.Is_Default__c = false;
        }
        if (!defaults.isEmpty()) {
            update defaults;
        }
    }

    // ===== DYNAMIC INVOICE QUERY =====

    @AuraEnabled
    public static List<ARF_Invoice__c> getInvoicesDynamic(
        Id accountId,
        List<String> fields,
        String filterConfigJson,
        String sortField,
        String sortDirection,
        String searchText
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        // Validate and build SELECT fields
        Set<String> selectFields = new Set<String>{ 'Id' };
        if (fields != null) {
            for (String f : fields) {
                if (!ALLOWED_FIELDS.contains(f)) {
                    throw new AuraHandledException('Invalid field: ' + f);
                }
                selectFields.add(f);
            }
        }

        String query = 'SELECT ' + String.join(new List<String>(selectFields), ', ') +
            ' FROM ARF_Invoice__c WHERE Account__c = :accountId' +
            ' AND Status__c NOT IN (\'Paid\', \'Cancelled\', \'Written Off\')';

        // Parse and apply filter criteria
        if (String.isNotBlank(filterConfigJson)) {
            List<Object> filters = (List<Object>) JSON.deserializeUntyped(filterConfigJson);
            for (Object filterObj : filters) {
                Map<String, Object> criterion = (Map<String, Object>) filterObj;
                String clause = buildFilterClause(criterion);
                if (String.isNotBlank(clause)) {
                    query += ' AND ' + clause;
                }
            }
        }

        // Search text across text fields
        if (String.isNotBlank(searchText)) {
            String searchWild = '%' + String.escapeSingleQuotes(searchText) + '%';
            List<String> likeClauses = new List<String>();
            for (String sf : SEARCHABLE_FIELDS) {
                if (selectFields.contains(sf) || fields == null) {
                    likeClauses.add(sf + ' LIKE \'' + searchWild + '\'');
                }
            }
            if (!likeClauses.isEmpty()) {
                query += ' AND (' + String.join(likeClauses, ' OR ') + ')';
            }
        }

        // Sort
        String validSortField = 'Due_Date__c';
        if (String.isNotBlank(sortField) && ALLOWED_FIELDS.contains(sortField)) {
            validSortField = sortField;
        }
        String validSortDir = 'ASC';
        if (String.isNotBlank(sortDirection) && sortDirection.equalsIgnoreCase('desc')) {
            validSortDir = 'DESC';
        }
        query += ' ORDER BY ' + validSortField + ' ' + validSortDir + ' NULLS LAST LIMIT 500';

        return Database.query(query);
    }

    private static String buildFilterClause(Map<String, Object> criterion) {
        String field = (String) criterion.get('field');
        String operator = (String) criterion.get('operator');
        String value = (String) criterion.get('value');
        String dataType = (String) criterion.get('dataType');

        if (String.isBlank(field) || String.isBlank(operator) || String.isBlank(value)) {
            return null;
        }

        // Validate field name against allowlist
        if (!ALLOWED_FIELDS.contains(field)) {
            throw new AuraHandledException('Invalid filter field: ' + field);
        }

        String escapedValue = String.escapeSingleQuotes(value);

        if (dataType == 'text' || dataType == 'picklist') {
            if (operator == 'equals') {
                return field + ' = \'' + escapedValue + '\'';
            } else if (operator == 'notEquals') {
                return field + ' != \'' + escapedValue + '\'';
            } else if (operator == 'contains') {
                return field + ' LIKE \'%' + escapedValue + '%\'';
            }
        } else if (dataType == 'currency' || dataType == 'number') {
            Decimal numVal;
            try {
                numVal = Decimal.valueOf(value);
            } catch (Exception e) {
                return null;
            }
            if (operator == 'equals') {
                return field + ' = ' + numVal;
            } else if (operator == 'notEquals') {
                return field + ' != ' + numVal;
            } else if (operator == 'greaterThan') {
                return field + ' > ' + numVal;
            } else if (operator == 'lessThan') {
                return field + ' < ' + numVal;
            } else if (operator == 'greaterOrEqual') {
                return field + ' >= ' + numVal;
            } else if (operator == 'lessOrEqual') {
                return field + ' <= ' + numVal;
            }
        } else if (dataType == 'date') {
            // Validate date format
            try {
                Date.valueOf(value);
            } catch (Exception e) {
                return null;
            }
            if (operator == 'equals') {
                return field + ' = ' + escapedValue;
            } else if (operator == 'notEquals') {
                return field + ' != ' + escapedValue;
            } else if (operator == 'greaterThan') {
                return field + ' > ' + escapedValue;
            } else if (operator == 'lessThan') {
                return field + ' < ' + escapedValue;
            } else if (operator == 'greaterOrEqual') {
                return field + ' >= ' + escapedValue;
            } else if (operator == 'lessOrEqual') {
                return field + ' <= ' + escapedValue;
            }
        } else if (dataType == 'boolean') {
            if (operator == 'equals') {
                Boolean boolVal = Boolean.valueOf(value);
                return field + ' = ' + boolVal;
            }
        }

        return null;
    }
}
