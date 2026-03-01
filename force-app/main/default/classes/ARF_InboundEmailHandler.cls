public class ARF_InboundEmailHandler implements Messaging.InboundEmailHandler {

    // Inner class to hold match results through the pipeline
    @TestVisible
    private class MatchResult {
        public Id accountId;
        public Id contactId;
        public String matchMethod;
        public Decimal confidence;
        public Boolean needsReview;
        public String threadId;

        public MatchResult() {
            this.confidence = 0;
            this.needsReview = false;
            this.matchMethod = 'Unmatched';
        }
    }

    public Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email, Messaging.InboundEnvelope envelope
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        result.success = true;

        try {
            // Run matching pipeline in priority order
            MatchResult match = runMatchingPipeline(email);

            // Create ARF_Communication__c record
            String bodyText = email.plainTextBody != null ? email.plainTextBody : '';
            String htmlBody = email.htmlBody != null ? email.htmlBody : bodyText;

            ARF_Communication__c comm = new ARF_Communication__c(
                Channel__c = 'Email',
                Direction__c = 'Inbound',
                Subject__c = email.subject,
                Body__c = bodyText.left(131072),
                HTML_Body__c = htmlBody.left(131072),
                From_Address__c = email.fromAddress,
                To_Address__c = envelope.toAddress,
                Status__c = 'Received',
                Sent_Date__c = Datetime.now(),
                Thread_ID__c = match.threadId != null ? match.threadId : email.messageId,
                Has_Attachment__c = (email.binaryAttachments != null && !email.binaryAttachments.isEmpty()) ||
                                    (email.textAttachments != null && !email.textAttachments.isEmpty())
            );

            // Apply match results and confidence routing
            applyConfidenceRouting(comm, match);

            // Set CC if available
            if (email.ccAddresses != null && !email.ccAddresses.isEmpty()) {
                comm.CC_Addresses__c = String.join(email.ccAddresses, ';');
            }

            insert comm;

            // Save attachments
            saveAttachments(comm.Id, email);

            // Always queue AI classification (no longer gated on account match)
            System.enqueueJob(new ARF_AIEmailClassifier(comm.Id));

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ARF_InboundEmailHandler error: ' + e.getMessage());
            // Still return success to prevent bounce
        }

        return result;
    }

    // ===== MATCHING PIPELINE =====

    @TestVisible
    private MatchResult runMatchingPipeline(Messaging.InboundEmail email) {
        MatchResult match;

        // Step 1: Thread match (100% confidence)
        match = matchByThread(email);
        if (match.accountId != null) return match;

        // Step 2: Contact match (100% confidence — 1 Contact = 1 Account)
        match = matchByContact(email.fromAddress);
        if (match.accountId != null) return match;

        // Step 3: Sender Map match (90%+ confidence — learned from previous manual assignments)
        match = matchBySenderMap(email.fromAddress);
        if (match.accountId != null) return match;

        // Step 4: Body Scan match (85% single / 50% multiple — invoice/PO refs in body)
        match = matchByBodyScan(email.subject, email.plainTextBody);
        if (match.accountId != null) return match;

        // Step 5: Domain match (60% single / 40% multiple)
        match = matchByDomain(email.fromAddress);
        if (match.accountId != null) return match;

        // Step 6: No match
        match = new MatchResult();
        match.matchMethod = 'Unmatched';
        match.confidence = 0;
        match.needsReview = false;
        return match;
    }

    @TestVisible
    private MatchResult matchByThread(Messaging.InboundEmail email) {
        MatchResult match = new MatchResult();

        if (String.isNotBlank(email.inReplyTo)) {
            List<ARF_Communication__c> threadComms = [
                SELECT Id, Account__c, Thread_ID__c
                FROM ARF_Communication__c
                WHERE Thread_ID__c = :email.inReplyTo
                ORDER BY Sent_Date__c DESC
                LIMIT 1
            ];
            if (!threadComms.isEmpty() && threadComms[0].Account__c != null) {
                match.accountId = threadComms[0].Account__c;
                match.threadId = threadComms[0].Thread_ID__c;
                match.matchMethod = 'Thread';
                match.confidence = 100;
                match.needsReview = false;
            }
        }
        return match;
    }

    @TestVisible
    private MatchResult matchByContact(String fromAddress) {
        MatchResult match = new MatchResult();

        if (String.isNotBlank(fromAddress)) {
            List<Contact> contacts = [
                SELECT Id, AccountId
                FROM Contact
                WHERE Email = :fromAddress
                AND AccountId != null
                LIMIT 1
            ];
            if (!contacts.isEmpty()) {
                match.contactId = contacts[0].Id;
                match.accountId = contacts[0].AccountId;
                match.matchMethod = 'Contact';
                match.confidence = 100;
                match.needsReview = false;
            }
        }
        return match;
    }

    @TestVisible
    private MatchResult matchBySenderMap(String fromAddress) {
        MatchResult match = new MatchResult();

        if (String.isNotBlank(fromAddress)) {
            List<ARF_Email_Sender_Map__c> maps = [
                SELECT Id, Account__c, Confidence__c, Match_Count__c
                FROM ARF_Email_Sender_Map__c
                WHERE Sender_Email__c = :fromAddress.toLowerCase()
                AND Account__c != null
                LIMIT 1
            ];
            if (!maps.isEmpty()) {
                ARF_Email_Sender_Map__c senderMap = maps[0];
                match.accountId = senderMap.Account__c;
                match.matchMethod = 'Sender Map';
                match.confidence = senderMap.Confidence__c != null ? senderMap.Confidence__c : 90;
                match.needsReview = false;

                // Increment match count and grow confidence (cap at 99%)
                senderMap.Match_Count__c = (senderMap.Match_Count__c != null ? senderMap.Match_Count__c : 0) + 1;
                Decimal newConfidence = match.confidence + 1;
                senderMap.Confidence__c = Math.min(newConfidence, 99);
                senderMap.Last_Match_Date__c = Datetime.now();
                update senderMap;
            }
        }
        return match;
    }

    @TestVisible
    private MatchResult matchByBodyScan(String subject, String body) {
        MatchResult match = new MatchResult();

        String textToScan = '';
        if (String.isNotBlank(subject)) textToScan += subject + ' ';
        if (String.isNotBlank(body)) textToScan += body;

        if (String.isBlank(textToScan)) return match;

        // Extract candidate references: INV-XXXX, PO-XXXX, or standalone numbers
        Set<String> candidates = new Set<String>();

        // Invoice patterns: INV-XXXX, INV_XXXX, Invoice #XXXX
        Pattern invPattern = Pattern.compile('(?i)(?:INV[-_]?\\s*)(\\d{2,10})');
        Matcher invMatcher = invPattern.matcher(textToScan);
        while (invMatcher.find()) {
            candidates.add('INV-' + invMatcher.group(1));
        }

        // PO patterns: PO-XXXX, PO#XXXX, PO XXXX
        Pattern poPattern = Pattern.compile('(?i)(?:PO[-#]?\\s*)(\\d{2,10})');
        Matcher poMatcher = poPattern.matcher(textToScan);
        while (poMatcher.find()) {
            candidates.add('PO-' + poMatcher.group(1));
        }

        // Full document number patterns like INV-2025-10051
        Pattern fullInvPattern = Pattern.compile('(?i)(INV-\\d{4}-\\d+)');
        Matcher fullInvMatcher = fullInvPattern.matcher(textToScan);
        while (fullInvMatcher.find()) {
            candidates.add(fullInvMatcher.group(1).toUpperCase());
        }

        if (candidates.isEmpty()) return match;

        // Query invoices by Document_Number__c or PO_Number__c
        Set<Id> matchedAccountIds = new Set<Id>();
        Id firstAccountId = null;

        List<ARF_Invoice__c> invoices = [
            SELECT Id, Account__c, Document_Number__c, PO_Number__c
            FROM ARF_Invoice__c
            WHERE Document_Number__c IN :candidates
            OR PO_Number__c IN :candidates
        ];

        for (ARF_Invoice__c inv : invoices) {
            if (inv.Account__c != null) {
                matchedAccountIds.add(inv.Account__c);
                if (firstAccountId == null) {
                    firstAccountId = inv.Account__c;
                }
            }
        }

        if (matchedAccountIds.size() == 1) {
            match.accountId = firstAccountId;
            match.matchMethod = 'Body Scan';
            match.confidence = 85;
            match.needsReview = false;
        } else if (matchedAccountIds.size() > 1) {
            // Multiple accounts referenced — pick first but flag for review
            match.accountId = firstAccountId;
            match.matchMethod = 'Body Scan';
            match.confidence = 50;
            match.needsReview = true;
        }

        return match;
    }

    @TestVisible
    private MatchResult matchByDomain(String fromAddress) {
        MatchResult match = new MatchResult();

        if (String.isNotBlank(fromAddress)) {
            String domain = fromAddress.substringAfter('@');
            if (String.isNotBlank(domain)) {
                String domainPattern = '%' + domain + '%';
                List<Account> accounts = [
                    SELECT Id FROM Account
                    WHERE Website LIKE :domainPattern
                    LIMIT 5
                ];
                if (accounts.size() == 1) {
                    match.accountId = accounts[0].Id;
                    match.matchMethod = 'Domain';
                    match.confidence = 60;
                    match.needsReview = false;
                } else if (accounts.size() > 1) {
                    // Multiple domain matches — lower confidence, flag review
                    match.accountId = accounts[0].Id;
                    match.matchMethod = 'Domain';
                    match.confidence = 40;
                    match.needsReview = true;
                }
            }
        }
        return match;
    }

    // ===== CONFIDENCE ROUTING =====

    private void applyConfidenceRouting(ARF_Communication__c comm, MatchResult match) {
        comm.Match_Method__c = match.matchMethod;
        comm.Match_Confidence__c = match.confidence;
        comm.Contact__c = match.contactId;

        if (match.confidence >= 80) {
            // High confidence — auto-link, no review needed
            comm.Account__c = match.accountId;
            comm.Needs_Review__c = false;
        } else if (match.confidence >= 40) {
            // Medium confidence — link but flag for review
            comm.Account__c = match.accountId;
            comm.Needs_Review__c = true;
        } else {
            // Low confidence or no match — no link, goes to unmatched queue
            comm.Account__c = null;
            comm.Needs_Review__c = false;
        }

        // Override: if match explicitly set needsReview, respect it
        if (match.needsReview) {
            comm.Needs_Review__c = true;
        }
    }

    // ===== ATTACHMENTS =====

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
