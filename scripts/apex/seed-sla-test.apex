// Dados fictícios para testar o SLA rápido (processo [TESTE] de 4 minutos) e ligar o Entitlement de produção ao processo real.
// Idempotente. Executar depois do deploy: sf apex run -f scripts/apex/seed-sla-test.apex -o <org>
SlaProcess prod = [SELECT Id FROM SlaProcess WHERE Name = 'Incident_SLA_Process' AND IsActive = true LIMIT 1];
SlaProcess fast = [SELECT Id FROM SlaProcess WHERE Name = 'Incident_SLA_Test_Process' AND IsActive = true LIMIT 1];

Entitlement main = [SELECT Id FROM Entitlement WHERE Name = 'Suporte Incidentes TI' LIMIT 1];
main.SlaProcessId = prod.Id;
update main;

String accName = 'Conta Teste SLA Rápido';
List<Account> accs = [SELECT Id FROM Account WHERE Name = :accName LIMIT 1];
if (accs.isEmpty()) {
    accs.add(new Account(Name = accName));
    insert accs;
}
if ([SELECT COUNT() FROM Entitlement WHERE AccountId = :accs[0].Id] == 0) {
    insert new Entitlement(Name = '[TESTE] SLA rápido 4 min', AccountId = accs[0].Id, SlaProcessId = fast.Id, StartDate = Date.today().addDays(-1));
}
