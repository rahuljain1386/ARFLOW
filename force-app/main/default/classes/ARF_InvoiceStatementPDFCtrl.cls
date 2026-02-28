public with sharing class ARF_InvoiceStatementPDFCtrl {

    public Account account { get; private set; }
    public List<ARF_Invoice__c> invoices { get; private set; }
    public Decimal totalAmount { get; private set; }
    public Decimal totalBalance { get; private set; }
    public String generatedDate { get; private set; }

    public ARF_InvoiceStatementPDFCtrl() {
        totalAmount = 0;
        totalBalance = 0;
        generatedDate = Datetime.now().format('MMMM d, yyyy');

        String accountId = ApexPages.currentPage().getParameters().get('accountId');
        String invoiceIdsParam = ApexPages.currentPage().getParameters().get('invoiceIds');

        if (String.isBlank(accountId)) {
            invoices = new List<ARF_Invoice__c>();
            return;
        }

        account = [
            SELECT Name, AccountNumber, BillingStreet, BillingCity,
                   BillingState, BillingPostalCode, BillingCountry
            FROM Account WHERE Id = :accountId LIMIT 1
        ];

        if (String.isNotBlank(invoiceIdsParam)) {
            List<String> idStrings = invoiceIdsParam.split(',');
            List<Id> invoiceIds = new List<Id>();
            for (String idStr : idStrings) {
                try {
                    invoiceIds.add(Id.valueOf(idStr.trim()));
                } catch (Exception e) {
                    // Skip invalid IDs
                }
            }
            invoices = [
                SELECT Document_Number__c, Invoice_Date__c, Due_Date__c,
                       Amount__c, Balance__c, Status__c, Days_Past_Due__c,
                       PO_Number__c, Reference__c
                FROM ARF_Invoice__c
                WHERE Id IN :invoiceIds AND Account__c = :accountId
                ORDER BY Due_Date__c ASC
            ];
        } else {
            invoices = new List<ARF_Invoice__c>();
        }

        for (ARF_Invoice__c inv : invoices) {
            if (inv.Amount__c != null) totalAmount += inv.Amount__c;
            if (inv.Balance__c != null) totalBalance += inv.Balance__c;
        }
    }

    @AuraEnabled
    public static String generatePdf(Id accountId, List<Id> invoiceIds) {
        if (accountId == null || invoiceIds == null || invoiceIds.isEmpty()) {
            throw new AuraHandledException('Account ID and invoice IDs are required');
        }
        PageReference pageRef = Page.ARF_InvoiceStatementPDF;
        pageRef.getParameters().put('accountId', accountId);
        pageRef.getParameters().put('invoiceIds', String.join(invoiceIds, ','));

        Blob pdfBlob;
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('Test PDF Content');
        } else {
            pdfBlob = pageRef.getContentAsPDF();
        }
        return EncodingUtil.base64Encode(pdfBlob);
    }
}
