@IsTest
private class IncidentDashboardControllerTest {

    @TestSetup
    static void setup() {
        IncidentTestUtil.createManager();
    }

    private static Case newIncident(String type, String priority) {
        return new Case(Type = type, Priority = priority);
    }

    private static List<IncidentDashboardController.IncidentRow> rowsAsManager() {
        List<IncidentDashboardController.IncidentRow> rows;
        System.runAs(IncidentTestUtil.getManager()) {
            rows = IncidentDashboardController.getOpenIncidents();
        }
        return rows;
    }

    @IsTest
    static void listsOpenIncidentsWithTeamAndPriorityAndSkipsClosedOnes() {
        List<Case> cases = new List<Case>{
            newIncident('Network', 'High'), newIncident('Security', 'Normal'),
            newIncident(null, 'Low'), newIncident('Network', 'Critical')
        };
        System.runAs(IncidentTestUtil.getManager()) {
            insert cases;
            cases[3].Status = 'Closed';
            update cases[3];
        }

        Map<String, IncidentDashboardController.IncidentRow> byPriority = new Map<String, IncidentDashboardController.IncidentRow>();
        for (IncidentDashboardController.IncidentRow r : rowsAsManager()) {
            byPriority.put(r.priority, r);
        }

        System.assertEquals(3, byPriority.size(), 'The closed incident must not be listed');
        System.assertEquals('Network', byPriority.get('High').team);
        System.assertEquals('Security', byPriority.get('Normal').team);
        System.assertEquals('Infrastructure', byPriority.get('Low').team, 'Empty Type counts as Infrastructure');
        System.assertEquals(null, byPriority.get('High').minutesRemaining, 'No Entitlement, so no Milestone');
        System.assertNotEquals(null, byPriority.get('High').caseNumber);
    }

    // Depends on the deployed Incident_SLA_Test_Process (4-minute Milestone).
    @IsTest
    static void minutesRemainingComesFromTheOpenMilestone() {
        Account acc = new Account(Name = 'Dashboard Test Account');
        insert acc;
        SlaProcess proc = [SELECT Id FROM SlaProcess WHERE Name = 'Incident_SLA_Test_Process' AND IsActive = true LIMIT 1];
        Entitlement ent = new Entitlement(Name = 'Dashboard Test Entitlement', AccountId = acc.Id, SlaProcessId = proc.Id, StartDate = Date.today().addDays(-1));
        insert ent;
        Case c = newIncident('Network', 'Normal');
        c.AccountId = acc.Id;
        c.EntitlementId = ent.Id;
        System.runAs(IncidentTestUtil.getManager()) {
            insert c;
        }

        List<IncidentDashboardController.IncidentRow> rows = rowsAsManager();

        System.assertEquals(1, rows.size());
        System.assert(rows[0].minutesRemaining >= 3 && rows[0].minutesRemaining <= 4, 'A fresh 4-minute Milestone has 3 to 4 minutes left, got ' + rows[0].minutesRemaining);
    }

    @IsTest
    static void assignToMeMakesTheRunningUserTheOwner() {
        User manager = IncidentTestUtil.getManager();
        Case c = newIncident('Network', 'High');
        System.runAs(manager) {
            insert c;
            IncidentDashboardController.assignToMe(c.Id);
            System.assertEquals(manager.Id, [SELECT OwnerId FROM Case WHERE Id = :c.Id].OwnerId);
        }
    }

    @IsTest
    static void assignToMeRejectsAClosedIncidentWithAReadableMessage() {
        Case c = newIncident('Network', 'High');
        System.runAs(IncidentTestUtil.getManager()) {
            insert c;
            c.Status = 'Closed';
            update c;
            try {
                IncidentDashboardController.assignToMe(c.Id);
                System.assert(false, 'Expected an AuraHandledException');
            } catch (AuraHandledException e) {
                System.assertEquals('This incident is no longer open.', e.getMessage());
            }
        }
    }
}
