@IsTest
private class IncidentMilestoneCompleterTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Conta Teste Milestones');
        insert acc;
        SlaProcess proc = [SELECT Id FROM SlaProcess WHERE Name = 'Incident_SLA_Test_Process' AND IsActive = true LIMIT 1];
        insert new Entitlement(Name = 'Entitlement Teste', AccountId = acc.Id, SlaProcessId = proc.Id, StartDate = Date.today().addDays(-1));
    }

    private static List<Case> newCases(Integer n) {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Entitlement ent = [SELECT Id FROM Entitlement LIMIT 1];
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < n; i++) {
            cases.add(new Case(AccountId = acc.Id, EntitlementId = ent.Id, Status = 'New'));
        }
        return cases;
    }

    @IsTest
    static void completesOpenMilestonesWhenCaseIsClosed() {
        List<Case> cases = newCases(200);
        insert cases;
        System.assertEquals(200, [SELECT COUNT() FROM CaseMilestone WHERE IsCompleted = false], 'Cada caso deve ter um Milestone aberto');

        for (Case c : cases) {
            c.Status = 'Closed';
        }
        // Casos sem Subject: o trigger do Case Classifier ignora-os e não enfileira jobs encadeados (ver README).
        update cases;
        Integer queries = Limits.getQueries();

        System.assertEquals(0, [SELECT COUNT() FROM CaseMilestone WHERE IsCompleted = false], 'Todos os Milestones devem ficar concluídos');
        System.assert(queries < 10, 'Deve estar bulkificado, SOQL usadas: ' + queries);
    }

    @IsTest
    static void ignoresCasesThatStayOpen() {
        List<Case> cases = newCases(5);
        insert cases;
        for (Case c : cases) {
            c.Status = 'Working';
        }
        update cases;
        System.assertEquals(5, [SELECT COUNT() FROM CaseMilestone WHERE IsCompleted = false]);
    }
}
