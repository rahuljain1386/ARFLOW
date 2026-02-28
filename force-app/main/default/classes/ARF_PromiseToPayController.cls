public with sharing class ARF_PromiseToPayController {

    @AuraEnabled(cacheable=true)
    public static List<ARF_Promise_To_Pay__c> getPromises(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        return [
            SELECT Id, Name, Amount__c, Amount_Received__c, Promise_Date__c,
                   Status__c, Broken_Count__c, Installment_Count__c,
                   Invoice__c, Invoice__r.Document_Number__c, Invoice__r.Balance__c,
                   Notes__c, CreatedDate
            FROM ARF_Promise_To_Pay__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
    }

    @AuraEnabled
    public static List<ARF_Promise_To_Pay__c> createInstallmentPlan(
        Id accountId, Id invoiceId, Decimal totalAmount,
        Integer installmentCount, Date firstPaymentDate,
        Integer daysBetweenPayments, String notes
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }
        if (totalAmount == null || totalAmount <= 0) {
            throw new AuraHandledException('Total amount must be greater than 0');
        }
        if (installmentCount == null || installmentCount < 1) {
            throw new AuraHandledException('Installment count must be at least 1');
        }
        if (firstPaymentDate == null) {
            throw new AuraHandledException('First payment date is required');
        }

        Integer daysBetween = daysBetweenPayments != null ? daysBetweenPayments : 30;
        Decimal perInstallment = (totalAmount / installmentCount).setScale(2, RoundingMode.HALF_UP);

        try {
            List<ARF_Promise_To_Pay__c> promises = new List<ARF_Promise_To_Pay__c>();
            Decimal allocated = 0;

            for (Integer i = 0; i < installmentCount; i++) {
                Decimal amount = (i == installmentCount - 1)
                    ? totalAmount - allocated
                    : perInstallment;

                promises.add(new ARF_Promise_To_Pay__c(
                    Account__c = accountId,
                    Invoice__c = invoiceId,
                    Amount__c = amount,
                    Amount_Received__c = 0,
                    Promise_Date__c = firstPaymentDate.addDays(i * daysBetween),
                    Status__c = 'Open',
                    Installment_Count__c = installmentCount,
                    Notes__c = (String.isBlank(notes) ? '' : notes + ' ') +
                        '(Installment ' + (i + 1) + ' of ' + installmentCount + ')'
                ));
                allocated += amount;
            }
            insert promises;

            // Pause any active strategy executions for this account
            List<ARF_Strategy_Execution__c> execs = [
                SELECT Id FROM ARF_Strategy_Execution__c
                WHERE Account__c = :accountId AND Status__c = 'Active'
            ];
            for (ARF_Strategy_Execution__c exec : execs) {
                exec.Status__c = 'Paused';
                exec.Pause_Reason__c = 'Promise Made';
            }
            if (!execs.isEmpty()) update execs;

            return promises;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static ARF_Promise_To_Pay__c cancelPromise(Id promiseId) {
        if (promiseId == null) {
            throw new AuraHandledException('Promise ID is required');
        }
        try {
            ARF_Promise_To_Pay__c ptp = new ARF_Promise_To_Pay__c(
                Id = promiseId, Status__c = 'Cancelled'
            );
            update ptp;
            return ptp;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static ARF_Promise_To_Pay__c recordPaymentReceived(Id promiseId, Decimal amountReceived) {
        if (promiseId == null) {
            throw new AuraHandledException('Promise ID is required');
        }
        if (amountReceived == null || amountReceived <= 0) {
            throw new AuraHandledException('Amount must be greater than 0');
        }
        try {
            ARF_Promise_To_Pay__c ptp = [
                SELECT Id, Amount__c, Amount_Received__c, Status__c
                FROM ARF_Promise_To_Pay__c WHERE Id = :promiseId LIMIT 1
            ];
            Decimal current = ptp.Amount_Received__c != null ? ptp.Amount_Received__c : 0;
            ptp.Amount_Received__c = current + amountReceived;
            if (ptp.Amount_Received__c >= ptp.Amount__c) {
                ptp.Status__c = 'Kept';
            }
            update ptp;
            return ptp;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
