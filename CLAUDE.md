# AR Flow — Project Instructions

## Overview
AR Flow is a Salesforce-native ITC (Invoice-to-Cash) suite.
All Salesforce code lives in force-app/main/default/.

## Naming Conventions
- Apex classes: ARF_ModuleName (e.g., ARF_CollectionWorklist)
- LWC components: arfComponentName (e.g., arfAccount360)
- Custom Objects: ARF_ObjectName__c (e.g., ARF_Invoice__c)
- Custom Fields: Field_Name__c (e.g., Risk_Score__c)
- Test classes: ARF_ModuleNameTest

## Salesforce Org
- Dev alias: ar-flow-dev
- Deploy: sf project deploy start --source-dir force-app --target-org ar-flow-dev
- Test: sf apex run test --target-org ar-flow-dev --code-coverage

## Git Workflow
- Work on main branch (single developer for now)
- Commit frequently with descriptive messages
- Push to main triggers auto-deploy via GitHub Actions

## Architecture Rules
- All custom objects prefixed with ARF_
- All Apex classes must have test class with 75%+ coverage
- Use Lightning Web Components (LWC), NOT Aura
- Use @AuraEnabled for methods called from LWC
- No SOQL in loops, bulkify all triggers
