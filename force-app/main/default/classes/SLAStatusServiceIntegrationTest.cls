/**
 * Teste de integração do endpoint com Milestones reais.
 * DEPENDE dos metadados: processo Incident_SLA_Test_Process (Milestone de 4 minutos), o Permission Set Incident_Manager
 * e o flow Incident_Assign_Owner. Não corre numa org onde isso não esteja deployado.
 */
@IsTest
private class SLAStatusServiceIntegrationTest {

    @TestSetup
    static void setup() {
        IncidentTestUtil.createManager();
        Account acc = new Account(Name = 'Conta Teste Integração SLA');
        insert acc;
        SlaProcess proc = [SELECT Id FROM SlaProcess WHERE Name = 'Incident_SLA_Test_Process' AND IsActive = true LIMIT 1];
        insert new Entitlement(Name = 'Entitlement Teste SLA', AccountId = acc.Id, SlaProcessId = proc.Id, StartDate = Date.today().addDays(-1));

        Account a = [SELECT Id FROM Account LIMIT 1];
        Entitlement e = [SELECT Id FROM Entitlement LIMIT 1];
        List<String> types = new List<String>{ 'Infrastructure', 'Network', 'Security', null };
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 200; i++) {
            cases.add(new Case(AccountId = a.Id, EntitlementId = e.Id, Type = types[Math.mod(i, 4)]));
        }
        System.runAs(IncidentTestUtil.getManager()) {
            insert cases;
        }
    }

    private static Map<String, Integer> totalsAt(Datetime now) {
        SLAStatusService.nowOverride = now;
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/incidents/v1/sla-status';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();
        System.runAs(IncidentTestUtil.getManager()) {
            SLAStatusService.getStatus();
        }
        System.assertEquals(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        Map<String, Integer> totals = new Map<String, Integer>{ 'within_sla' => 0, 'near_breach' => 0, 'breached' => 0, 'total_open' => 0, 'no_sla' => 0 };
        for (Object g : (List<Object>) parsed.get('groups')) {
            Map<String, Object> entry = (Map<String, Object>) g;
            for (String k : totals.keySet()) {
                totals.put(k, totals.get(k) + (Integer) entry.get(k));
            }
        }
        return totals;
    }

    private static Datetime milestoneStart() {
        return [SELECT StartDate FROM CaseMilestone ORDER BY StartDate ASC LIMIT 1].StartDate;
    }

    @IsTest
    static void all200CasesHaveAnOpenMilestone() {
        System.assertEquals(200, [SELECT COUNT() FROM CaseMilestone WHERE IsCompleted = false]);
    }

    @IsTest
    static void reports200WithinSlaRightAfterCreation() {
        Map<String, Integer> t = totalsAt(milestoneStart());
        System.assertEquals(200, t.get('total_open'));
        System.assertEquals(200, t.get('within_sla'));
        System.assertEquals(0, t.get('no_sla'));
    }

    @IsTest
    static void reports200NearBreachAt3AndAHalfMinutesOfFour() {
        Map<String, Integer> t = totalsAt(milestoneStart().addSeconds(210));
        System.assertEquals(200, t.get('near_breach'));
        System.assertEquals(0, t.get('breached'));
    }

    @IsTest
    static void reports200BreachedAfterTheDeadline() {
        Map<String, Integer> t = totalsAt(milestoneStart().addMinutes(5));
        System.assertEquals(200, t.get('breached'));
        System.assertEquals(200, t.get('total_open'));
    }
}
