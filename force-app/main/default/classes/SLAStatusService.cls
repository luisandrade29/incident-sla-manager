/**
 * SLA counts for open IT incidents, grouped by Case.Type (not by owner: the owner changes from the queue to a person
 * when a technician picks a case up). Counts only, no personal data.
 * Assumptions: the 75% uses wall-clock time (valid because the Business Hours are 24x7); with several open Milestones
 * on a case, the worst state counts.
 */
@RestResource(urlMapping='/incidents/v1/sla-status')
global with sharing class SLAStatusService {

    @TestVisible static final Integer ROW_LIMIT = 10000;
    @TestVisible static final Decimal NEAR_BREACH_RATIO = 0.75;
    @TestVisible static final List<String> TYPES = new List<String>{ 'Infrastructure', 'Network', 'Security' };
    private static final Map<String, String> QUEUE_BY_TYPE = new Map<String, String>{
        'Infrastructure' => 'Infrastructure_Queue',
        'Network' => 'Network_Queue',
        'Security' => 'Security_Queue'
    };

    @TestVisible static Datetime nowOverride;
    @TestVisible static Exception failureForTest;

    public static final Integer WITHIN = 0;
    public static final Integer NEAR = 1;
    public static final Integer BREACHED = 2;

    public class MilestoneRow {
        public Id caseId;
        public String caseType;
        public Datetime startDate;
        public Datetime targetDate;
        public Boolean isViolated;

        public MilestoneRow(Id caseId, String caseType, Datetime startDate, Datetime targetDate, Boolean isViolated) {
            this.caseId = caseId;
            this.caseType = caseType;
            this.startDate = startDate;
            this.targetDate = targetDate;
            this.isViolated = isViolated;
        }
    }

    public class TypeSummary {
        public String type;
        public String queue;
        public Integer within_sla = 0;
        public Integer near_breach = 0;
        public Integer breached = 0;
        public Integer total_open = 0;
        public Integer no_sla = 0;
    }

    public class Report {
        public Datetime generated_at;
        public Boolean truncated;
        public List<TypeSummary> groups = new List<TypeSummary>();
    }

    @HttpGet
    global static void getStatus() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        try {
            if (failureForTest != null) {
                throw failureForTest;
            }
            Datetime now = nowOverride != null ? nowOverride : Datetime.now();

            List<CaseMilestone> milestones = [
                SELECT CaseId, Case.Type, StartDate, TargetDate, IsViolated
                FROM CaseMilestone
                WHERE IsCompleted = false AND Case.IsClosed = false AND Case.RecordType.DeveloperName = 'Incident_IT'
                WITH USER_MODE
                LIMIT :ROW_LIMIT
            ];
            List<MilestoneRow> rows = new List<MilestoneRow>();
            for (CaseMilestone m : milestones) {
                rows.add(new MilestoneRow(m.CaseId, m.Case.Type, m.StartDate, m.TargetDate, m.IsViolated));
            }

            Map<String, Integer> noSla = new Map<String, Integer>();
            for (AggregateResult ar : [
                SELECT Type t, COUNT(Id) n
                FROM Case
                WHERE RecordType.DeveloperName = 'Incident_IT' AND IsClosed = false
                  AND Id NOT IN (SELECT CaseId FROM CaseMilestone WHERE IsCompleted = false)
                WITH USER_MODE
                GROUP BY Type
            ]) {
                String key = normalizeType((String) ar.get('t'));
                noSla.put(key, (noSla.containsKey(key) ? noSla.get(key) : 0) + (Integer) ar.get('n'));
            }

            Report report = buildReport(rows, noSla, now, rows.size() >= ROW_LIMIT);
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(report));
        } catch (System.QueryException e) {
            // Missing object or field access in USER_MODE.
            error(res, 403, 'FORBIDDEN', 'You do not have permission to read the SLA data.');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'SLAStatusService: ' + e.getMessage());
            error(res, 500, 'INTERNAL_ERROR', 'Internal error while calculating the SLA status.');
        }
    }

    private static void error(RestResponse res, Integer status, String code, String message) {
        res.statusCode = status;
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{ 'code' => code, 'error' => message }));
    }

    /** Empty or unknown Type counts as Infrastructure, like the Incident_Assign_Owner flow. */
    @TestVisible
    static String normalizeType(String caseType) {
        return (caseType == 'Network' || caseType == 'Security') ? caseType : 'Infrastructure';
    }

    @TestVisible
    static Integer classify(MilestoneRow row, Datetime now) {
        if (row.isViolated == true || (row.targetDate != null && now > row.targetDate)) {
            return BREACHED;
        }
        if (row.startDate == null || row.targetDate == null) {
            return WITHIN;
        }
        Long total = row.targetDate.getTime() - row.startDate.getTime();
        if (total <= 0) {
            return WITHIN;
        }
        Decimal elapsedRatio = Decimal.valueOf(now.getTime() - row.startDate.getTime()) / total;
        return elapsedRatio >= NEAR_BREACH_RATIO ? NEAR : WITHIN;
    }

    @TestVisible
    static Report buildReport(List<MilestoneRow> rows, Map<String, Integer> noSlaByType, Datetime now, Boolean truncated) {
        Map<Id, Integer> worstByCase = new Map<Id, Integer>();
        Map<Id, String> typeByCase = new Map<Id, String>();
        for (MilestoneRow row : rows) {
            Integer state = classify(row, now);
            if (!worstByCase.containsKey(row.caseId) || state > worstByCase.get(row.caseId)) {
                worstByCase.put(row.caseId, state);
            }
            typeByCase.put(row.caseId, normalizeType(row.caseType));
        }

        Map<String, TypeSummary> byType = new Map<String, TypeSummary>();
        Report report = new Report();
        report.generated_at = now;
        report.truncated = truncated;
        for (String t : TYPES) {
            TypeSummary s = new TypeSummary();
            s.type = t;
            s.queue = QUEUE_BY_TYPE.get(t);
            s.no_sla = noSlaByType != null && noSlaByType.containsKey(t) ? noSlaByType.get(t) : 0;
            byType.put(t, s);
            report.groups.add(s);
        }
        for (Id caseId : worstByCase.keySet()) {
            TypeSummary s = byType.get(typeByCase.get(caseId));
            Integer state = worstByCase.get(caseId);
            if (state == BREACHED) {
                s.breached++;
            } else if (state == NEAR) {
                s.near_breach++;
            } else {
                s.within_sla++;
            }
            s.total_open++;
        }
        return report;
    }
}
