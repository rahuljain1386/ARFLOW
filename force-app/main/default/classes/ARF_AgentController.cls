public with sharing class ARF_AgentController {

    private static final Integer MAX_TOOL_ITERATIONS = 5;
    private static final String CLAUDE_ENDPOINT = 'https://api.anthropic.com/v1/messages';
    private static final String CLAUDE_MODEL = 'claude-sonnet-4-20250514';
    private static final Integer MAX_TOKENS = 2048;
    private static final Integer CALLOUT_TIMEOUT = 30000;

    // ─── Response Wrappers ──────────────────────────────────────────────

    public class AgentResponse {
        @AuraEnabled public String message;
        @AuraEnabled public List<ActionCard> actions;
        @AuraEnabled public String chatSessionId;
        @AuraEnabled public Boolean escalated;

        public AgentResponse() {
            this.actions = new List<ActionCard>();
            this.escalated = false;
        }
    }

    public class ActionCard {
        @AuraEnabled public String cardType; // action, draft_email, escalation
        @AuraEnabled public String title;
        @AuraEnabled public String dataJson;

        public ActionCard(String cardType, String title, String dataJson) {
            this.cardType = cardType;
            this.title = title;
            this.dataJson = dataJson;
        }
    }

    // ─── Main Entry Point ───────────────────────────────────────────────

    @AuraEnabled
    public static AgentResponse sendMessage(Id accountId, String userMessage, String conversationJson, String userType, String chatSessionId) {
        AgentResponse response = new AgentResponse();

        try {
            // Parse user type
            ARF_AgentService.AgentUserType uType = userType == 'customer'
                ? ARF_AgentService.AgentUserType.CUSTOMER
                : ARF_AgentService.AgentUserType.COLLECTOR;

            // Generate session ID if needed
            if (String.isBlank(chatSessionId)) {
                chatSessionId = generateSessionId();
            }
            response.chatSessionId = chatSessionId;

            // Build system prompt
            String systemPrompt = buildSystemPrompt(accountId, uType);

            // Get tool definitions
            List<Map<String, Object>> tools = ARF_AgentService.getToolsForUserType(uType);

            // Reconstruct conversation history
            List<Map<String, Object>> messages = new List<Map<String, Object>>();
            if (String.isNotBlank(conversationJson) && conversationJson != '[]') {
                List<Object> rawList = (List<Object>) JSON.deserializeUntyped(conversationJson);
                for (Object item : rawList) {
                    messages.add((Map<String, Object>) item);
                }
            }

            // Append new user message
            messages.add(new Map<String, Object>{
                'role' => 'user',
                'content' => userMessage
            });

            // Tool-calling loop
            List<ARF_AgentService.ToolResult> toolResults = new List<ARF_AgentService.ToolResult>();
            String finalText = '';
            Boolean didDML = false;

            for (Integer i = 0; i < MAX_TOOL_ITERATIONS; i++) {
                // After DML, we can't make more callouts — break and use tool results
                Map<String, Object> apiResponse;
                if (didDML) {
                    break;
                }
                apiResponse = callClaudeAPI(systemPrompt, messages, tools);

                String stopReason = (String) apiResponse.get('stop_reason');
                List<Object> contentBlocks = (List<Object>) apiResponse.get('content');

                // Build assistant message content for history
                List<Map<String, Object>> assistantContent = new List<Map<String, Object>>();
                List<Map<String, Object>> toolUseBlocks = new List<Map<String, Object>>();

                for (Object block : contentBlocks) {
                    Map<String, Object> blockMap = (Map<String, Object>) block;
                    String blockType = (String) blockMap.get('type');

                    if (blockType == 'text') {
                        finalText = (String) blockMap.get('text');
                        assistantContent.add(blockMap);
                    } else if (blockType == 'tool_use') {
                        assistantContent.add(blockMap);
                        toolUseBlocks.add(blockMap);
                    }
                }

                // Add assistant message to conversation
                messages.add(new Map<String, Object>{
                    'role' => 'assistant',
                    'content' => assistantContent
                });

                // If no tool calls, we're done
                if (stopReason != 'tool_use' || toolUseBlocks.isEmpty()) {
                    break;
                }

                // Execute tool calls and build tool_result messages
                List<Map<String, Object>> toolResultContent = new List<Map<String, Object>>();

                for (Map<String, Object> toolBlock : toolUseBlocks) {
                    String toolId = (String) toolBlock.get('id');
                    String toolName = (String) toolBlock.get('name');
                    Map<String, Object> toolArgs = (Map<String, Object>) toolBlock.get('input');

                    // Handle escalation specially
                    if (toolName == 'escalate_to_human') {
                        String reason = (String) toolArgs.get('reason');
                        escalateToHuman(accountId, chatSessionId, reason, conversationJson);
                        response.escalated = true;
                        response.actions.add(new ActionCard('escalation', 'Escalated to Human Agent', JSON.serialize(new Map<String, String>{ 'reason' => reason })));
                        didDML = true;
                    }

                    ARF_AgentService.ToolResult result = ARF_AgentService.executeTool(toolName, toolArgs, accountId, uType);
                    toolResults.add(result);

                    // Track DML-causing tools so we don't attempt another callout
                    if (result.actionType == 'action' || result.actionType == 'escalation') {
                        didDML = true;
                    }

                    // Build action cards for non-data results
                    if (result.actionType == 'action' && result.displayMessage != null) {
                        response.actions.add(new ActionCard('action', result.displayMessage, result.resultJson));
                    } else if (result.actionType == 'draft_email') {
                        response.actions.add(new ActionCard('draft_email', result.displayMessage, result.resultJson));
                    }

                    // Build tool_result for next API call
                    String resultContent = result.success
                        ? (result.resultJson != null ? result.resultJson : result.displayMessage)
                        : ('Error: ' + result.displayMessage);

                    toolResultContent.add(new Map<String, Object>{
                        'type' => 'tool_result',
                        'tool_use_id' => toolId,
                        'content' => resultContent
                    });
                }

                // Add tool results to conversation
                messages.add(new Map<String, Object>{
                    'role' => 'user',
                    'content' => toolResultContent
                });
            }

            // If DML happened and we couldn't get a final text from Claude, build from tool results
            if (String.isBlank(finalText) && !toolResults.isEmpty()) {
                List<String> summaries = new List<String>();
                for (ARF_AgentService.ToolResult tr : toolResults) {
                    if (String.isNotBlank(tr.displayMessage)) {
                        summaries.add(tr.displayMessage);
                    }
                }
                finalText = summaries.isEmpty() ? 'Done.' : String.join(summaries, '\n');
            }

            response.message = finalText;

        } catch (Exception e) {
            response.message = 'I encountered an error processing your request. Please try again or type "escalate" to connect with a human agent.';
            System.debug(LoggingLevel.ERROR, 'ARF_AgentController.sendMessage error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        return response;
    }

    // ─── Save Chat Transcript ───────────────────────────────────────────

    @AuraEnabled
    public static Id saveChatTranscript(Id accountId, String chatSessionId, String transcriptText, String status) {
        ARF_Communication__c comm = new ARF_Communication__c();
        comm.Account__c = accountId;
        comm.Channel__c = 'Chat';
        comm.Subject__c = 'AI Agent Chat — ' + chatSessionId;
        comm.Body__c = transcriptText;
        comm.Status__c = String.isNotBlank(status) ? status : 'Completed';
        comm.Direction__c = 'Inbound';
        insert comm;
        return comm.Id;
    }

    // ─── Escalation Handler ─────────────────────────────────────────────

    public static void escalateToHuman(Id accountId, String chatSessionId, String reason, String transcript) {
        // Create Communication record
        ARF_Communication__c comm = new ARF_Communication__c();
        comm.Account__c = accountId;
        comm.Channel__c = 'Chat';
        comm.Subject__c = 'Chat Escalation — ' + chatSessionId;
        comm.Body__c = 'Escalation Reason: ' + reason + '\n\n--- Chat Transcript ---\n' + (String.isNotBlank(transcript) ? transcript : 'No transcript available.');
        comm.Status__c = 'Escalated';
        comm.Direction__c = 'Inbound';
        insert comm;

        // Create Task for collector
        Task t = new Task();
        t.Subject = 'Chat Escalation: ' + reason;
        t.Description = 'AI Agent chat escalated to human.\n\nReason: ' + reason + '\nSession: ' + chatSessionId;
        t.WhatId = accountId;
        t.Priority = 'High';
        t.Status = 'Not Started';
        t.ActivityDate = Date.today();
        t.ARF_Task_Type__c = 'Chat Escalation';

        // Assign to account owner (collector)
        List<Account> accts = [SELECT OwnerId FROM Account WHERE Id = :accountId LIMIT 1];
        if (!accts.isEmpty()) {
            t.OwnerId = accts[0].OwnerId;
        }

        insert t;
    }

    // ─── Claude API Call ────────────────────────────────────────────────

    @TestVisible
    private static Map<String, Object> callClaudeAPI(String systemPrompt, List<Map<String, Object>> messages, List<Map<String, Object>> tools) {
        String apiKey = getAPIKey();
        if (String.isBlank(apiKey)) {
            throw new AuraHandledException('AI configuration not found. Please set up ARF_AI_Config__c.');
        }

        Map<String, Object> requestBody = new Map<String, Object>{
            'model' => CLAUDE_MODEL,
            'max_tokens' => MAX_TOKENS,
            'system' => systemPrompt,
            'messages' => messages
        };

        if (tools != null && !tools.isEmpty()) {
            requestBody.put('tools', tools);
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(CLAUDE_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('anthropic-version', '2023-06-01');
        req.setHeader('x-api-key', apiKey);
        req.setTimeout(CALLOUT_TIMEOUT);
        req.setBody(JSON.serialize(requestBody));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new AuraHandledException('AI service returned status ' + res.getStatusCode() + ': ' + res.getBody());
        }

        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    // ─── System Prompts ─────────────────────────────────────────────────

    private static String buildSystemPrompt(Id accountId, ARF_AgentService.AgentUserType userType) {
        String base;

        if (userType == ARF_AgentService.AgentUserType.COLLECTOR) {
            base = 'You are an AI assistant for Inqulo, an accounts receivable collections platform. '
                + 'You are helping a COLLECTOR manage their accounts. You have access to tools for querying account data, '
                + 'creating disputes, logging promises to pay, drafting emails, and more.\n\n'
                + 'Guidelines:\n'
                + '- Always use the account_id parameter: ' + accountId + '\n'
                + '- When the user references an invoice by number (e.g., INV-001), use that as the invoice_document_number.\n'
                + '- For email drafts, ALWAYS use templates: (1) call get_email_templates to list available templates, (2) call draft_email with template_id and invoice_document_numbers — the template is auto-resolved with merge fields. Only 2 tool calls needed. Never compose email body from scratch.\n'
                + '- If you cannot help with a request, offer to escalate to a human.\n'
                + '- Be concise and professional. Format currency amounts and dates clearly.\n'
                + '- When showing data, summarize key points rather than dumping raw JSON.\n'
                + '- Do NOT use markdown formatting (no **bold**, *italic*, or ### headers). Use plain text only.\n'
                + '- Answer only what the user asked. Do not repeat information you already provided in earlier messages.';
        } else {
            base = 'You are an AI assistant for a customer payment portal. '
                + 'You are helping a CUSTOMER understand their invoices and make payments.\n\n'
                + 'Guidelines:\n'
                + '- Always use the account_id parameter: ' + accountId + '\n'
                + '- Never reveal internal data like risk scores, collection strategies, or internal notes.\n'
                + '- You can help customers view invoices, check payment history, file disputes, and set up payment promises.\n'
                + '- If you cannot help, escalate to a human agent.\n'
                + '- Be friendly, helpful, and concise. Format currency amounts and dates clearly.\n'
                + '- Do NOT use markdown formatting (no **bold**, *italic*, or ### headers). Use plain text only.\n'
                + '- Answer only what the user asked. Do not repeat information you already provided in earlier messages.';
        }

        return base;
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    private static String getAPIKey() {
        ARF_AI_Config__c config = ARF_AI_Config__c.getInstance();
        return config != null ? config.API_Key__c : null;
    }

    private static String generateSessionId() {
        return 'CHAT-' + String.valueOf(Datetime.now().getTime()) + '-' + String.valueOf(Math.round(Math.random() * 9999)).leftPad(4, '0');
    }
}
