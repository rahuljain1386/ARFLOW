public with sharing class ARF_InvoiceStatementPDFCtrl {

    public Account account { get; private set; }
    public List<ARF_Invoice__c> invoices { get; private set; }
    public Decimal totalAmount { get; private set; }
    public Decimal totalBalance { get; private set; }
    public String generatedDate { get; private set; }

    // Aging buckets
    public Decimal agingCurrent { get; private set; }
    public Decimal aging1to30 { get; private set; }
    public Decimal aging31to60 { get; private set; }
    public Decimal aging61to90 { get; private set; }
    public Decimal agingOver90 { get; private set; }
    public Decimal overdueBalance { get; private set; }
    public Integer openInvoiceCount { get; private set; }

    // Company info (from Org or custom settings)
    public String companyName { get; private set; }
    public String companyStreet { get; private set; }
    public String companyCityStateZip { get; private set; }
    public String companyPhone { get; private set; }
    public String companyEmail { get; private set; }
    public String companyWebsite { get; private set; }
    public String paymentTerms { get; private set; }

    public ARF_InvoiceStatementPDFCtrl() {
        totalAmount = 0;
        totalBalance = 0;
        agingCurrent = 0;
        aging1to30 = 0;
        aging31to60 = 0;
        aging61to90 = 0;
        agingOver90 = 0;
        overdueBalance = 0;
        openInvoiceCount = 0;
        generatedDate = Datetime.now().format('MMMM d, yyyy');

        loadCompanyInfo();

        String accountId = ApexPages.currentPage().getParameters().get('accountId');
        String invoiceIdsParam = ApexPages.currentPage().getParameters().get('invoiceIds');

        if (String.isBlank(accountId)) {
            invoices = new List<ARF_Invoice__c>();
            return;
        }

        account = [
            SELECT Name, AccountNumber, BillingStreet, BillingCity,
                   BillingState, BillingPostalCode, BillingCountry,
                   Phone
            FROM Account WHERE Id = :accountId LIMIT 1
        ];

        // Determine payment terms from account or default
        paymentTerms = 'Net 30';

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

        calculateTotals();
        calculateAging();
    }

    private void calculateTotals() {
        for (ARF_Invoice__c inv : invoices) {
            if (inv.Amount__c != null) totalAmount += inv.Amount__c;
            if (inv.Balance__c != null) totalBalance += inv.Balance__c;
            if (inv.Status__c == 'Open' || inv.Status__c == 'Overdue') {
                openInvoiceCount++;
            }
        }
    }

    private void calculateAging() {
        Date today = Date.today();

        for (ARF_Invoice__c inv : invoices) {
            Decimal balance = inv.Balance__c != null ? inv.Balance__c : 0;
            if (balance == 0) continue;

            if (inv.Due_Date__c == null) {
                agingCurrent += balance;
                continue;
            }

            Integer daysPast = inv.Due_Date__c.daysBetween(today);

            if (daysPast <= 0) {
                // Not yet due
                agingCurrent += balance;
            } else if (daysPast <= 30) {
                aging1to30 += balance;
                overdueBalance += balance;
            } else if (daysPast <= 60) {
                aging31to60 += balance;
                overdueBalance += balance;
            } else if (daysPast <= 90) {
                aging61to90 += balance;
                overdueBalance += balance;
            } else {
                agingOver90 += balance;
                overdueBalance += balance;
            }
        }
    }

    private void loadCompanyInfo() {
        try {
            Organization org = [SELECT Name, Street, City, State, PostalCode, Phone FROM Organization LIMIT 1];
            companyName = org.Name;
            companyStreet = org.Street;
            companyPhone = org.Phone;

            List<String> cityParts = new List<String>();
            if (String.isNotBlank(org.City)) cityParts.add(org.City);
            if (String.isNotBlank(org.State)) cityParts.add(org.State);
            if (String.isNotBlank(org.PostalCode)) cityParts.add(org.PostalCode);
            companyCityStateZip = String.join(cityParts, ', ');
        } catch (Exception e) {
            companyName = 'Your Company Name';
            companyStreet = '';
            companyCityStateZip = '';
            companyPhone = '';
        }
        companyEmail = '';
        companyWebsite = '';
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
