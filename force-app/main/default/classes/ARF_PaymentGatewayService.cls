/**
 * ARF_PaymentGatewayService
 * Mock payment gateway integration for tokenization, charges, voids, and refunds.
 * In production, replace mock implementations with actual gateway API callouts.
 */
public with sharing class ARF_PaymentGatewayService {

    // Response wrapper for gateway operations
    public class GatewayResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String transactionId;
        @AuraEnabled public String token;
        @AuraEnabled public String message;
        @AuraEnabled public String errorCode;
    }

    // Tokenize a credit card — returns a token for storage (no raw card data stored)
    public static GatewayResponse tokenizeCard(String cardNumber, String expMonth, String expYear, String cvv, String cardholderName) {
        GatewayResponse resp = new GatewayResponse();
        try {
            // Validate inputs
            if (String.isBlank(cardNumber) || cardNumber.length() < 13) {
                resp.success = false;
                resp.message = 'Invalid card number';
                resp.errorCode = 'INVALID_CARD';
                return resp;
            }
            // Mock: Generate a token based on card details
            String token = 'tok_card_' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 24);
            resp.success = true;
            resp.token = token;
            resp.transactionId = 'setup_' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 16);
            resp.message = 'Card tokenized successfully';
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Tokenization failed: ' + e.getMessage();
            resp.errorCode = 'TOKENIZE_ERROR';
        }
        return resp;
    }

    // Tokenize a bank account (ACH) — returns token
    public static GatewayResponse tokenizeBankAccount(String routingNumber, String accountNumber, String accountType, String accountHolderName) {
        GatewayResponse resp = new GatewayResponse();
        try {
            if (String.isBlank(routingNumber) || routingNumber.length() != 9) {
                resp.success = false;
                resp.message = 'Invalid routing number';
                resp.errorCode = 'INVALID_ROUTING';
                return resp;
            }
            if (String.isBlank(accountNumber) || accountNumber.length() < 4) {
                resp.success = false;
                resp.message = 'Invalid account number';
                resp.errorCode = 'INVALID_ACCOUNT';
                return resp;
            }
            String token = 'tok_ach_' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 24);
            resp.success = true;
            resp.token = token;
            resp.transactionId = 'setup_' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 16);
            resp.message = 'Bank account tokenized successfully';
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Tokenization failed: ' + e.getMessage();
            resp.errorCode = 'TOKENIZE_ERROR';
        }
        return resp;
    }

    // Charge a tokenized payment method
    public static GatewayResponse chargePaymentMethod(String token, Decimal amount, String currency_x, String description) {
        GatewayResponse resp = new GatewayResponse();
        try {
            if (String.isBlank(token)) {
                resp.success = false;
                resp.message = 'Payment method token is required';
                resp.errorCode = 'MISSING_TOKEN';
                return resp;
            }
            if (amount == null || amount <= 0) {
                resp.success = false;
                resp.message = 'Amount must be greater than zero';
                resp.errorCode = 'INVALID_AMOUNT';
                return resp;
            }
            // Mock: Simulate successful charge
            resp.success = true;
            resp.transactionId = 'ch_' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 24);
            resp.message = 'Payment of ' + amount + ' processed successfully';
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Charge failed: ' + e.getMessage();
            resp.errorCode = 'CHARGE_ERROR';
        }
        return resp;
    }

    // Void a transaction (before settlement)
    public static GatewayResponse voidTransaction(String transactionId) {
        GatewayResponse resp = new GatewayResponse();
        try {
            if (String.isBlank(transactionId)) {
                resp.success = false;
                resp.message = 'Transaction ID is required';
                resp.errorCode = 'MISSING_TXN_ID';
                return resp;
            }
            resp.success = true;
            resp.transactionId = transactionId;
            resp.message = 'Transaction voided successfully';
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Void failed: ' + e.getMessage();
            resp.errorCode = 'VOID_ERROR';
        }
        return resp;
    }

    // Refund a transaction (after settlement)
    public static GatewayResponse refundTransaction(String transactionId, Decimal amount) {
        GatewayResponse resp = new GatewayResponse();
        try {
            if (String.isBlank(transactionId)) {
                resp.success = false;
                resp.message = 'Transaction ID is required';
                resp.errorCode = 'MISSING_TXN_ID';
                return resp;
            }
            resp.success = true;
            resp.transactionId = 'rf_' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 24);
            resp.message = 'Refund of ' + amount + ' processed successfully';
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Refund failed: ' + e.getMessage();
            resp.errorCode = 'REFUND_ERROR';
        }
        return resp;
    }

    // Validate if a token is still valid
    public static GatewayResponse validateToken(String token) {
        GatewayResponse resp = new GatewayResponse();
        resp.success = String.isNotBlank(token);
        resp.token = token;
        resp.message = resp.success ? 'Token is valid' : 'Token is invalid';
        return resp;
    }
}
