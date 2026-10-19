// Manual test of the Incident_Assign_Owner flow. Requires seed-data.apex to have run.
Id rt = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Incident_IT').getRecordTypeId();
Id acc = [SELECT Id FROM Account WHERE Name = 'Incident Test Account' LIMIT 1].Id;

List<Case> cases = new List<Case>();
for (String t : new List<String>{'Infrastructure', 'Network', 'Security', null}) {
    cases.add(new Case(Subject = '[TEST S2] Type ' + t, Type = t, Priority = 'Normal', RecordTypeId = rt, AccountId = acc));
}
Database.insert(cases);

List<Case> bulkCases = new List<Case>();
List<String> types = new List<String>{'Infrastructure', 'Network', 'Security', null};
for (Integer i = 0; i < 200; i++) {
    bulkCases.add(new Case(Subject = '[TEST S2 BULK] ' + i, Type = types[Math.mod(i, 4)], Priority = 'High', RecordTypeId = rt, AccountId = acc));
}
Integer soqlBefore = Limits.getQueries();
Database.insert(bulkCases);
System.debug('RESULT bulk insert SOQL usadas: ' + (Limits.getQueries() - soqlBefore) + ' | DML rows: ' + Limits.getDmlRows());

for (Case c : [SELECT Subject, Type, Owner.Name, EntitlementId, Routing_Note__c FROM Case WHERE Subject LIKE '[TEST S2] %' ORDER BY Subject]) {
    System.debug('RESULT ' + c.Subject + ' | owner=' + c.Owner.Name + ' | entitlementId=' + c.EntitlementId + ' | note=' + c.Routing_Note__c);
}
for (AggregateResult ar : [SELECT Type t, Owner.Name o, COUNT(Id) n, COUNT(EntitlementId) e FROM Case WHERE Subject LIKE '[TEST S2 BULK]%' GROUP BY Type, Owner.Name]) {
    System.debug('RESULT bulk type=' + ar.get('t') + ' owner=' + ar.get('o') + ' cases=' + ar.get('n') + ' withEntitlement=' + ar.get('e'));
}
