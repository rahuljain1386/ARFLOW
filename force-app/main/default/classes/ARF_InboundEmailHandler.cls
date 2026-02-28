public class ARF_InboundEmailHandler implements Messaging.InboundEmailHandler {

    public Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email, Messaging.InboundEnvelope envelope
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        result.success = true;

        try {
            Id accountId = null;
            Id contactId = null;
            String threadId = null;

            // 1. Thread matching — check In-Reply-To header
            if (String.isNotBlank(email.inReplyTo)) {
                List<ARF_Communication__c> threadComms = [
                    SELECT Id, Account__c, Thread_ID__c
                    FROM ARF_Communication__c
                    WHERE Thread_ID__c = :email.inReplyTo
                    ORDER BY Sent_Date__c DESC
                    LIMIT 1
                ];
                if (!threadComms.isEmpty()) {
                    accountId = threadComms[0].Account__c;
                    threadId = threadComms[0].Thread_ID__c;
                }
            }

            // 2. Contact matching — sender email → Contact → Account
            if (accountId == null && String.isNotBlank(email.fromAddress)) {
                List<Contact> contacts = [
                    SELECT Id, AccountId
                    FROM Contact
                    WHERE Email = :email.fromAddress
                    AND AccountId != null
                    LIMIT 1
                ];
                if (!contacts.isEmpty()) {
                    contactId = contacts[0].Id;
                    accountId = contacts[0].AccountId;
                }
            }

            // 3. Domain matching — email domain → Account Website
            if (accountId == null && String.isNotBlank(email.fromAddress)) {
                String domain = email.fromAddress.substringAfter('@');
                if (String.isNotBlank(domain)) {
                    String domainPattern = '%' + domain + '%';
                    List<Account> accounts = [
                        SELECT Id FROM Account
                        WHERE Website LIKE :domainPattern
                        LIMIT 1
                    ];
                    if (!accounts.isEmpty()) {
                        accountId = accounts[0].Id;
                    }
                }
            }

            // 4. Create ARF_Communication__c record
            String bodyText = email.plainTextBody != null ? email.plainTextBody : '';
            String htmlBody = email.htmlBody != null ? email.htmlBody : bodyText;

            ARF_Communication__c comm = new ARF_Communication__c(
                Account__c = accountId,
                Contact__c = contactId,
                Channel__c = 'Email',
                Direction__c = 'Inbound',
                Subject__c = email.subject,
                Body__c = bodyText.left(131072),
                HTML_Body__c = htmlBody.left(131072),
                From_Address__c = email.fromAddress,
                To_Address__c = envelope.toAddress,
                Status__c = 'Received',
                Sent_Date__c = Datetime.now(),
                Thread_ID__c = threadId != null ? threadId : email.messageId,
                Has_Attachment__c = (email.binaryAttachments != null && !email.binaryAttachments.isEmpty()) ||
                                    (email.textAttachments != null && !email.textAttachments.isEmpty())
            );

            // Set CC if available
            if (email.ccAddresses != null && !email.ccAddresses.isEmpty()) {
                comm.CC_Addresses__c = String.join(email.ccAddresses, ';');
            }

            insert comm;

            // 5. Save attachments as ContentVersion/ContentDocumentLink
            saveAttachments(comm.Id, email);

            // 6. Queue AI classification
            if (accountId != null) {
                System.enqueueJob(new ARF_AIEmailClassifier(comm.Id));
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ARF_InboundEmailHandler error: ' + e.getMessage());
            // Still return success to prevent bounce
        }

        return result;
    }

    private void saveAttachments(Id commId, Messaging.InboundEmail email) {
        List<ContentVersion> versions = new List<ContentVersion>();

        if (email.binaryAttachments != null) {
            for (Messaging.InboundEmail.BinaryAttachment att : email.binaryAttachments) {
                versions.add(new ContentVersion(
                    Title = att.fileName,
                    PathOnClient = att.fileName,
                    VersionData = att.body,
                    FirstPublishLocationId = commId
                ));
            }
        }

        if (email.textAttachments != null) {
            for (Messaging.InboundEmail.TextAttachment att : email.textAttachments) {
                versions.add(new ContentVersion(
                    Title = att.fileName,
                    PathOnClient = att.fileName,
                    VersionData = Blob.valueOf(att.body),
                    FirstPublishLocationId = commId
                ));
            }
        }

        if (!versions.isEmpty()) {
            insert versions;
        }
    }
}
