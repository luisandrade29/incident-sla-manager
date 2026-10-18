// Dados de teste fictícios. Idempotente: não duplica se já existirem.
// Executar: sf apex run -f scripts/apex/seed-data.apex -o <org>
String accName = 'Conta Teste Incidentes';
String entName = 'Suporte Incidentes TI';

List<Account> accs = [SELECT Id FROM Account WHERE Name = :accName LIMIT 1];
if (accs.isEmpty()) {
    accs.add(new Account(Name = accName));
    insert accs;
}

List<Entitlement> ents = [SELECT Id FROM Entitlement WHERE Name = :entName AND AccountId = :accs[0].Id LIMIT 1];
if (ents.isEmpty()) {
    insert new Entitlement(Name = entName, AccountId = accs[0].Id, StartDate = Date.today().addDays(-1));
}
System.debug('Seed concluído: ' + accName + ' / ' + entName);

// O utilizador que executa o script passa a ser membro das 3 filas (idempotente).
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
