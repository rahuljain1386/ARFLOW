@isTest
private class ARF_PaymentGatewayServiceTest {

    @isTest
    static void testTokenizeCard() {
        ARF_PaymentGatewayService.GatewayResponse resp = ARF_PaymentGatewayService.tokenizeCard(
            '4111111111111111', '12', '2028', '123', 'John Doe'
        );
        System.assert(resp.success, 'Card tokenization should succeed');
        System.assert(resp.token.startsWith('tok_card_'), 'Token should have card prefix');
        System.assertNotEquals(null, resp.transactionId);
    }

    @isTest
    static void testTokenizeCardInvalid() {
        ARF_PaymentGatewayService.GatewayResponse resp = ARF_PaymentGatewayService.tokenizeCard(
            '123', '12', '2028', '123', 'John Doe'
        );
        System.assert(!resp.success, 'Should fail for invalid card');
        System.assertEquals('INVALID_CARD', resp.errorCode);
    }

    @isTest
    static void testTokenizeBankAccount() {
        ARF_PaymentGatewayService.GatewayResponse resp = ARF_PaymentGatewayService.tokenizeBankAccount(
            '021000021', '1234567890', 'Checking', 'Jane Doe'
        );
        System.assert(resp.success, 'ACH tokenization should succeed');
        System.assert(resp.token.startsWith('tok_ach_'), 'Token should have ACH prefix');
    }

    @isTest
    static void testTokenizeBankAccountInvalidRouting() {
        ARF_PaymentGatewayService.GatewayResponse resp = ARF_PaymentGatewayService.tokenizeBankAccount(
            '123', '1234567890', 'Checking', 'Jane Doe'
        );
        System.assert(!resp.success, 'Should fail for invalid routing');
        System.assertEquals('INVALID_ROUTING', resp.errorCode);
    }

    @isTest
    static void testTokenizeBankAccountInvalidAccount() {
        ARF_PaymentGatewayService.GatewayResponse resp = ARF_PaymentGatewayService.tokenizeBankAccount(
            '021000021', '12', 'Checking', 'Jane Doe'
        );
        System.assert(!resp.success, 'Should fail for invalid account');
        System.assertEquals('INVALID_ACCOUNT', resp.errorCode);
    }

    @isTest
    static void testChargePaymentMethod() {
        ARF_PaymentGatewayService.GatewayResponse resp = ARF_PaymentGatewayService.chargePaymentMethod(
            'tok_card_test123', 150.00, 'USD', 'Test payment'
        );
        System.assert(resp.success, 'Charge should succeed');
        System.assert(resp.transactionId.startsWith('ch_'), 'Transaction ID should have charge prefix');
    }

    @isTest
    static void testChargeInvalidAmount() {
        ARF_PaymentGatewayService.GatewayResponse resp = ARF_PaymentGatewayService.chargePaymentMethod(
            'tok_card_test123', 0, 'USD', 'Test payment'
        );
        System.assert(!resp.success, 'Should fail for zero amount');
        System.assertEquals('INVALID_AMOUNT', resp.errorCode);
    }

    @isTest
    static void testChargeMissingToken() {
        ARF_PaymentGatewayService.GatewayResponse resp = ARF_PaymentGatewayService.chargePaymentMethod(
            '', 100.00, 'USD', 'Test'
        );
        System.assert(!resp.success, 'Should fail for missing token');
        System.assertEquals('MISSING_TOKEN', resp.errorCode);
    }

    @isTest
    static void testVoidTransaction() {
        ARF_PaymentGatewayService.GatewayResponse resp = ARF_PaymentGatewayService.voidTransaction('ch_test123');
        System.assert(resp.success, 'Void should succeed');
    }

    @isTest
    static void testVoidMissingId() {
        ARF_PaymentGatewayService.GatewayResponse resp = ARF_PaymentGatewayService.voidTransaction('');
        System.assert(!resp.success, 'Should fail for missing ID');
    }

    @isTest
    static void testRefundTransaction() {
        ARF_PaymentGatewayService.GatewayResponse resp = ARF_PaymentGatewayService.refundTransaction('ch_test123', 50.00);
        System.assert(resp.success, 'Refund should succeed');
        System.assert(resp.transactionId.startsWith('rf_'), 'Should have refund prefix');
    }

    @isTest
    static void testRefundMissingId() {
        ARF_PaymentGatewayService.GatewayResponse resp = ARF_PaymentGatewayService.refundTransaction('', 50.00);
        System.assert(!resp.success, 'Should fail for missing ID');
    }

    @isTest
    static void testValidateToken() {
        ARF_PaymentGatewayService.GatewayResponse resp = ARF_PaymentGatewayService.validateToken('tok_card_test');
        System.assert(resp.success, 'Valid token should pass');

        ARF_PaymentGatewayService.GatewayResponse resp2 = ARF_PaymentGatewayService.validateToken('');
        System.assert(!resp2.success, 'Empty token should fail');
    }
}
