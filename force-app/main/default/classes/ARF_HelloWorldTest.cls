@isTest
private class ARF_HelloWorldTest {
    @isTest
    static void testGreeting() {
        String result = ARF_HelloWorld.getGreeting();
        System.assertNotEquals(null, result, 'Should return greeting');
        System.assert(result.contains('AR Flow'), 'Should mention AR Flow');
    }
}
