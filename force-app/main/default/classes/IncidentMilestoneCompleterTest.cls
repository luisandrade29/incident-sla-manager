@IsTest
private class IncidentMilestoneCompleterTest {

    @TestSetup
    static void setup() {
        IncidentTestUtil.createManager();
        Account acc = new Account(Name = 'Milestones Test Account');
        insert acc;
        SlaProcess proc = [SELECT Id FROM SlaProcess WHERE Name = 'Incident_SLA_Test_Process' AND IsActive = true LIMIT 1];
        insert new Entitlement(Name = 'Test Entitlement', AccountId = acc.Id, SlaProcessId = proc.Id, StartDate = Date.today().addDays(-1));
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
        System.runAs(IncidentTestUtil.getManager()) {
            insert cases;
        }
        System.assertEquals(200, [SELECT COUNT() FROM CaseMilestone WHERE IsCompleted = false], 'Each case must have an open Milestone');

        for (Case c : cases) {
            c.Status = 'Closed';
        }
        User manager = IncidentTestUtil.getManager();
        Integer queriesBefore = Limits.getQueries();
        System.runAs(manager) {
            update cases;
        }
        Integer queries = Limits.getQueries() - queriesBefore;

        System.assertEquals(0, [SELECT COUNT() FROM CaseMilestone WHERE IsCompleted = false], 'All Milestones must be completed');
        System.assert(queries < 20, 'Must be bulkified, SOQL used: ' + queries);
    }

    @IsTest
    static void ignoresCasesThatStayOpen() {
        List<Case> cases = newCases(5);
        System.runAs(IncidentTestUtil.getManager()) {
            insert cases;
            for (Case c : cases) {
                c.Status = 'Working';
            }
            update cases;
        }
        System.assertEquals(5, [SELECT COUNT() FROM CaseMilestone WHERE IsCompleted = false]);
    }
}
