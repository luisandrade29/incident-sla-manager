// Fictional test data. Idempotent.
String accName = 'Incident Test Account';
String entName = 'IT Incident Support';

List<Account> accs = [SELECT Id FROM Account WHERE Name = :accName LIMIT 1];
if (accs.isEmpty()) {
    accs.add(new Account(Name = accName));
    insert accs;
}

List<Entitlement> ents = [SELECT Id FROM Entitlement WHERE Name = :entName AND AccountId = :accs[0].Id LIMIT 1];
if (ents.isEmpty()) {
    insert new Entitlement(Name = entName, AccountId = accs[0].Id, StartDate = Date.today().addDays(-1));
}
System.debug('Seed done: ' + accName + ' / ' + entName);

// The running user becomes a member of the 3 queues (idempotent).
Id me = UserInfo.getUserId();
Set<Id> already = new Set<Id>();
for (GroupMember gm : [SELECT GroupId FROM GroupMember WHERE UserOrGroupId = :me]) {
    already.add(gm.GroupId);
}
List<GroupMember> members = new List<GroupMember>();
for (Group q : [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName IN ('Infrastructure_Queue', 'Network_Queue', 'Security_Queue')]) {
    if (!already.contains(q.Id)) {
        members.add(new GroupMember(GroupId = q.Id, UserOrGroupId = me));
    }
}
insert members;
