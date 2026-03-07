public with sharing class ARF_HelloWorld {
    @AuraEnabled(cacheable=true)
    public static String getGreeting() {
        return 'Inqulo is live!';
    }
}
