/** Tests SLAStatusService without the Entitlement Process: classification with in-memory rows. */
@IsTest
private class SLAStatusServiceTest {

    private static final Datetime T0 = Datetime.newInstance(2026, 10, 18, 12, 0, 0);

    private static SLAStatusService.MilestoneRow row(Id caseId, String type, Boolean violated) {
        return new SLAStatusService.MilestoneRow(caseId, type, T0, T0.addMinutes(100), violated);
    }

    private static Id fakeCaseId(Integer n) {
        return Id.valueOf('500000000000' + String.valueOf(1000 + n).leftPad(3, '0').right(3));
    }

    private static SLAStatusService.TypeSummary summary(SLAStatusService.Report r, String type) {
        for (SLAStatusService.TypeSummary s : r.groups) {
            if (s.type == type) {
                return s;
            }
        }
        return null;
    }

    @IsTest
    static void classifiesWithinNearAndBreached() {
        SLAStatusService.MilestoneRow r = row(fakeCaseId(1), 'Network', false);
        System.assertEquals(SLAStatusService.WITHIN, SLAStatusService.classify(r, T0));
        System.assertEquals(SLAStatusService.WITHIN, SLAStatusService.classify(r, T0.addMinutes(74)));
        System.assertEquals(SLAStatusService.NEAR, SLAStatusService.classify(r, T0.addMinutes(75)), 'Exactly 75% already counts as near breach');
        System.assertEquals(SLAStatusService.NEAR, SLAStatusService.classify(r, T0.addMinutes(100)), 'At the exact deadline it has not passed yet');
        System.assertEquals(SLAStatusService.BREACHED, SLAStatusService.classify(r, T0.addMinutes(101)), 'Past the deadline, even with IsViolated=false');
    }

    @IsTest
    static void violatedFlagWinsEvenBeforeTarget() {
        System.assertEquals(SLAStatusService.BREACHED, SLAStatusService.classify(row(fakeCaseId(1), 'Network', true), T0.addMinutes(10)));
    }

    @IsTest
    static void handlesDegenerateDates() {
        Id c = fakeCaseId(1);
        System.assertEquals(SLAStatusService.WITHIN, SLAStatusService.classify(new SLAStatusService.MilestoneRow(c, 'Network', T0, T0, false), T0), 'Zero duration');
        System.assertEquals(SLAStatusService.WITHIN, SLAStatusService.classify(new SLAStatusService.MilestoneRow(c, 'Network', null, T0.addMinutes(5), false), T0));
        System.assertEquals(SLAStatusService.WITHIN, SLAStatusService.classify(new SLAStatusService.MilestoneRow(c, 'Network', T0, null, false), T0));
    }

    @IsTest
    static void alwaysReturnsThreeGroupsWithQueueNames() {
        SLAStatusService.Report r = SLAStatusService.buildReport(new List<SLAStatusService.MilestoneRow>(), null, T0, false);
        System.assertEquals(3, r.groups.size());
        System.assertEquals('Infrastructure_Queue', summary(r, 'Infrastructure').queue);
        System.assertEquals('Network_Queue', summary(r, 'Network').queue);
        System.assertEquals('Security_Queue', summary(r, 'Security').queue);
        System.assertEquals(false, r.truncated);
        System.assertEquals(T0, r.generated_at);
        System.assertEquals(0, summary(r, 'Network').total_open);
    }

    @IsTest
    static void emptyOrUnknownTypeCountsAsInfrastructure() {
        List<SLAStatusService.MilestoneRow> rows = new List<SLAStatusService.MilestoneRow>{
            row(fakeCaseId(1), null, false), row(fakeCaseId(2), '', false), row(fakeCaseId(3), 'Mechanical', false),
            row(fakeCaseId(4), 'Network', false), row(fakeCaseId(5), 'Security', false)
        };
        SLAStatusService.Report r = SLAStatusService.buildReport(rows, null, T0, false);
        System.assertEquals(3, summary(r, 'Infrastructure').total_open);
        System.assertEquals(1, summary(r, 'Network').total_open);
        System.assertEquals(1, summary(r, 'Security').total_open);
    }

    @IsTest
    static void worstStateWinsWhenACaseHasSeveralOpenMilestones() {
        Id c = fakeCaseId(1);
        List<SLAStatusService.MilestoneRow> rows = new List<SLAStatusService.MilestoneRow>{
            row(c, 'Network', false), row(c, 'Network', true)
        };
        SLAStatusService.Report r = SLAStatusService.buildReport(rows, null, T0.addMinutes(10), false);
        SLAStatusService.TypeSummary s = summary(r, 'Network');
        System.assertEquals(1, s.total_open, 'Distinct cases, not Milestones');
        System.assertEquals(1, s.breached);
        System.assertEquals(0, s.within_sla);
    }

    @IsTest
    static void noSlaIsReportedSeparatelyFromTotalOpen() {
        Map<String, Integer> noSla = new Map<String, Integer>{ 'Network' => 4 };
        SLAStatusService.Report r = SLAStatusService.buildReport(new List<SLAStatusService.MilestoneRow>{ row(fakeCaseId(1), 'Network', false) }, noSla, T0, false);
        System.assertEquals(4, summary(r, 'Network').no_sla);
        System.assertEquals(1, summary(r, 'Network').total_open, 'no_sla is not part of total_open');
        System.assertEquals(0, summary(r, 'Security').no_sla);
    }

    @IsTest
    static void aggregates200RowsAndEachStateAddsUpToTotal() {
        List<SLAStatusService.MilestoneRow> rows = new List<SLAStatusService.MilestoneRow>();
        List<String> types = new List<String>{ 'Infrastructure', 'Network', 'Security', null };
        for (Integer i = 0; i < 200; i++) {
            // First 100 within SLA, last 100 already violated.
            rows.add(row(fakeCaseId(i), types[Math.mod(i, 4)], i >= 100));
        }
        SLAStatusService.Report r = SLAStatusService.buildReport(rows, null, T0, false);
        Integer total = 0;
        Integer breached = 0;
        Integer within = 0;
        for (SLAStatusService.TypeSummary s : r.groups) {
            total += s.total_open;
            breached += s.breached;
            within += s.within_sla;
            System.assertEquals(s.total_open, s.within_sla + s.near_breach + s.breached);
        }
        System.assertEquals(200, total);
        System.assertEquals(100, breached);
        System.assertEquals(100, within);
        System.assertEquals(100, summary(r, 'Infrastructure').total_open, 'Infrastructure plus those with an empty Type');
    }

    private static void prepareRequest() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/incidents/v1/sla-status';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    @IsTest
    static void restReturns200WithJsonAndNoSlaForCasesWithoutMilestone() {
        IncidentTestUtil.createManager();
        List<Case> cases = new List<Case>{ new Case(Type = 'Network'), new Case(Type = 'Network'), new Case() };
        System.runAs(IncidentTestUtil.getManager()) {
            insert cases;
            prepareRequest();
            SLAStatusService.getStatus();
        }
        RestResponse res = RestContext.response;
        System.assertEquals(200, res.statusCode);
        System.assertEquals('application/json', res.headers.get('Content-Type'));
        String body = res.responseBody.toString();
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        System.assertEquals(false, parsed.get('truncated'));
        List<Object> groups = (List<Object>) parsed.get('groups');
        System.assertEquals(3, groups.size());
        Map<String, Object> network = (Map<String, Object>) groups[1];
        System.assertEquals('Network', network.get('type'));
        System.assertEquals(2, network.get('no_sla'));
        System.assertEquals(0, network.get('total_open'));
        System.assert(!body.contains('Subject') && !body.contains('@'), 'The response must not contain personal data');
    }

    @IsTest
    static void restReturns403WhenUserCannotReadCases() {
        List<Profile> minimal = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        if (minimal.isEmpty()) {
            return; // Standard profile missing in this org.
        }
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            u = new User(Alias = 'noacc', Email = 'noacc@example.invalid', EmailEncodingKey = 'UTF-8', LastName = 'NoAccessTest',
                LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', TimeZoneSidKey = 'Europe/Lisbon', ProfileId = minimal[0].Id,
                Username = 'noacc' + System.currentTimeMillis() + '@example.invalid');
            insert u;
        }
        System.runAs(u) {
            prepareRequest();
            SLAStatusService.getStatus();
        }
        System.assertEquals(403, RestContext.response.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assertEquals('FORBIDDEN', body.get('code'));
    }

    @IsTest
    static void restReturns500WithGenericJsonOnUnexpectedError() {
        prepareRequest();
        SLAStatusService.failureForTest = new CalloutException('internal detail that must not leak');
        SLAStatusService.getStatus();
        System.assertEquals(500, RestContext.response.statusCode);
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('INTERNAL_ERROR'));
        System.assert(!body.contains('internal detail'), 'Do not expose the exception message');
    }
}
