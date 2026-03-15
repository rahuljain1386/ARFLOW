public with sharing class ARF_BulkImportController {

    @AuraEnabled
    public static ImportPreview parseCSV(String csvContent, String importType) {
        ImportPreview preview = new ImportPreview();
        preview.rows = new List<Map<String, String>>();
        preview.errors = new List<String>();
        preview.warnings = new List<String>();
        preview.importType = importType;

        if (String.isBlank(csvContent)) {
            preview.errors.add('CSV content is empty');
            return preview;
        }

        List<String> lines = csvContent.split('\n');
        if (lines.size() < 2) {
            preview.errors.add('CSV must have a header row and at least one data row');
            return preview;
        }

        // Parse header
        String headerLine = lines[0].trim();
        List<String> headers = parseCSVLine(headerLine);
        preview.columns = headers;

        // Validate required columns based on import type
        if (importType == 'Invoice') {
            List<String> required = new List<String>{'Account_Name', 'Document_Number', 'Amount', 'Due_Date'};
            for (String req : required) {
                Boolean found = false;
                for (String h : headers) {
                    if (h.trim().equalsIgnoreCase(req)) { found = true; break; }
                }
                if (!found) preview.errors.add('Missing required column: ' + req);
            }
        } else if (importType == 'Payment') {
            List<String> required = new List<String>{'Account_Name', 'Amount', 'Payment_Date'};
            for (String req : required) {
                Boolean found = false;
                for (String h : headers) {
                    if (h.trim().equalsIgnoreCase(req)) { found = true; break; }
                }
                if (!found) preview.errors.add('Missing required column: ' + req);
            }
        }

        if (!preview.errors.isEmpty()) return preview;

        // Parse data rows (limit preview to 100 rows)
        Integer maxPreview = Math.min(lines.size(), 101);
        for (Integer i = 1; i < maxPreview; i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) continue;

            List<String> values = parseCSVLine(line);
            Map<String, String> row = new Map<String, String>();
            for (Integer j = 0; j < Math.min(headers.size(), values.size()); j++) {
                row.put(headers[j].trim(), values[j].trim());
            }

            // Validate row
            if (importType == 'Invoice') {
                if (String.isBlank(row.get('Amount')) || !isNumeric(row.get('Amount'))) {
                    preview.warnings.add('Row ' + i + ': Invalid amount "' + row.get('Amount') + '"');
                }
            }

            preview.rows.add(row);
        }

        preview.totalRows = lines.size() - 1;
        preview.previewRows = preview.rows.size();

        return preview;
    }

    @AuraEnabled
    public static ImportResult executeImport(String csvContent, String importType) {
        ImportResult result = new ImportResult();
        result.successCount = 0;
        result.errorCount = 0;
        result.errors = new List<String>();

        List<String> lines = csvContent.split('\n');
        List<String> headers = parseCSVLine(lines[0].trim());

        // Build account name to ID map
        Set<String> accountNames = new Set<String>();
        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) continue;
            List<String> values = parseCSVLine(line);
            Map<String, String> row = buildRowMap(headers, values);
            String acctName = row.get('Account_Name');
            if (String.isNotBlank(acctName)) accountNames.add(acctName);
        }

        Map<String, Id> accountMap = new Map<String, Id>();
        for (Account a : [SELECT Id, Name FROM Account WHERE Name IN :accountNames]) {
            accountMap.put(a.Name, a.Id);
        }

        if (importType == 'Invoice') {
            result = importInvoices(lines, headers, accountMap);
        } else if (importType == 'Payment') {
            result = importPayments(lines, headers, accountMap);
        }

        return result;
    }

    private static ImportResult importInvoices(List<String> lines, List<String> headers, Map<String, Id> accountMap) {
        ImportResult result = new ImportResult();
        result.successCount = 0;
        result.errorCount = 0;
        result.errors = new List<String>();

        List<ARF_Invoice__c> invoices = new List<ARF_Invoice__c>();

        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) continue;

            List<String> values = parseCSVLine(line);
            Map<String, String> row = buildRowMap(headers, values);

            try {
                ARF_Invoice__c inv = new ARF_Invoice__c();

                String acctName = row.get('Account_Name');
                if (!accountMap.containsKey(acctName)) {
                    result.errors.add('Row ' + i + ': Account "' + acctName + '" not found');
                    result.errorCount++;
                    continue;
                }
                inv.Account__c = accountMap.get(acctName);
                inv.Document_Number__c = row.get('Document_Number');
                inv.Amount__c = Decimal.valueOf(row.get('Amount').replaceAll('[^\\d.\\-]', ''));
                inv.Balance__c = inv.Amount__c;
                inv.Due_Date__c = Date.valueOf(row.get('Due_Date'));
                inv.Status__c = 'Open';

                if (row.containsKey('PO_Number')) inv.PO_Number__c = row.get('PO_Number');
                if (row.containsKey('Reference')) inv.Reference__c = row.get('Reference');

                invoices.add(inv);
            } catch (Exception e) {
                result.errors.add('Row ' + i + ': ' + e.getMessage());
                result.errorCount++;
            }
        }

        if (!invoices.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.insert(invoices, false);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    result.successCount++;
                } else {
                    result.errorCount++;
                    result.errors.add('Insert error: ' + saveResults[i].getErrors()[0].getMessage());
                }
            }
        }

        return result;
    }

    private static ImportResult importPayments(List<String> lines, List<String> headers, Map<String, Id> accountMap) {
        ImportResult result = new ImportResult();
        result.successCount = 0;
        result.errorCount = 0;
        result.errors = new List<String>();

        List<ARF_Payment__c> payments = new List<ARF_Payment__c>();

        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) continue;

            List<String> values = parseCSVLine(line);
            Map<String, String> row = buildRowMap(headers, values);

            try {
                ARF_Payment__c pmt = new ARF_Payment__c();

                String acctName = row.get('Account_Name');
                if (!accountMap.containsKey(acctName)) {
                    result.errors.add('Row ' + i + ': Account "' + acctName + '" not found');
                    result.errorCount++;
                    continue;
                }
                pmt.Account__c = accountMap.get(acctName);
                pmt.Amount__c = Decimal.valueOf(row.get('Amount').replaceAll('[^\\d.\\-]', ''));
                pmt.Applied_Amount__c = 0;
                pmt.Unapplied_Amount__c = pmt.Amount__c;
                pmt.Payment_Date__c = Date.valueOf(row.get('Payment_Date'));
                pmt.Status__c = 'Received';

                if (row.containsKey('Method')) pmt.Method__c = row.get('Method');
                if (row.containsKey('Reference')) pmt.Reference__c = row.get('Reference');
                if (row.containsKey('ERP_ID')) pmt.ERP_ID__c = row.get('ERP_ID');

                payments.add(pmt);
            } catch (Exception e) {
                result.errors.add('Row ' + i + ': ' + e.getMessage());
                result.errorCount++;
            }
        }

        if (!payments.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.insert(payments, false);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    result.successCount++;
                } else {
                    result.errorCount++;
                    result.errors.add('Insert error: ' + saveResults[i].getErrors()[0].getMessage());
                }
            }
        }

        return result;
    }

    @AuraEnabled
    public static String getCSVTemplate(String importType) {
        if (importType == 'Invoice') {
            return 'Account_Name,Document_Number,Amount,Due_Date,PO_Number,Reference\n"Acme Corp","INV-1001","5000.00","2026-04-15","PO-123","Net 30 terms"';
        } else {
            return 'Account_Name,Amount,Payment_Date,Method,Reference,ERP_ID\n"Acme Corp","5000.00","2026-03-15","ACH","Wire Ref 12345","ERP-PMT-001"';
        }
    }

    // CSV parsing helpers
    private static List<String> parseCSVLine(String line) {
        List<String> result = new List<String>();
        Boolean inQuotes = false;
        String current = '';

        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);
            if (ch == '"') {
                inQuotes = !inQuotes;
            } else if (ch == ',' && !inQuotes) {
                result.add(current.trim());
                current = '';
            } else {
                current += ch;
            }
        }
        result.add(current.trim());
        return result;
    }

    private static Map<String, String> buildRowMap(List<String> headers, List<String> values) {
        Map<String, String> row = new Map<String, String>();
        for (Integer j = 0; j < Math.min(headers.size(), values.size()); j++) {
            row.put(headers[j].trim(), values[j].trim());
        }
        return row;
    }

    private static Boolean isNumeric(String s) {
        if (String.isBlank(s)) return false;
        try {
            Decimal.valueOf(s.replaceAll('[^\\d.\\-]', ''));
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    // Inner classes
    public class ImportPreview {
        @AuraEnabled public String importType;
        @AuraEnabled public List<String> columns;
        @AuraEnabled public List<Map<String, String>> rows;
        @AuraEnabled public Integer totalRows;
        @AuraEnabled public Integer previewRows;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public List<String> warnings;
    }

    public class ImportResult {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer errorCount;
        @AuraEnabled public List<String> errors;
    }
}
