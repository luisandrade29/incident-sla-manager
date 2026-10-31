public with sharing class IncidentDashboardController {

    // shortcut: no paging, the oldest 200 open incidents only; add server-side filtering by team if a queue grows past that.
    @TestVisible static final Integer ROW_LIMIT = 200;

    public class IncidentRow {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String team;
        @AuraEnabled public String priority;
        // Negative when the Milestone is already overdue; null when the incident has no open Milestone.
        @AuraEnabled public Integer minutesRemaining;
    }

    @AuraEnabled(cacheable=true)
    public static List<IncidentRow> getOpenIncidents() {
        Datetime now = Datetime.now();
        List<IncidentRow> rows = new List<IncidentRow>();
        for (Case c : [
            SELECT CaseNumber, Priority, Type,
                (SELECT TargetDate FROM CaseMilestones WHERE IsCompleted = false ORDER BY TargetDate ASC LIMIT 1)
            FROM Case
            WHERE RecordType.DeveloperName = 'Incident_IT' AND IsClosed = false
            WITH USER_MODE
            ORDER BY CreatedDate ASC
            LIMIT :ROW_LIMIT
        ]) {
            IncidentRow row = new IncidentRow();
            row.caseId = c.Id;
            row.caseNumber = c.CaseNumber;
            row.team = SLAStatusService.normalizeType(c.Type);
            row.priority = c.Priority;
            if (!c.CaseMilestones.isEmpty()) {
                Long millis = c.CaseMilestones[0].TargetDate.getTime() - now.getTime();
                row.minutesRemaining = Integer.valueOf(Math.floor(millis / 60000.0));
            }
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static void assignToMe(Id caseId) {
        // Trust boundary: the client sends the Id, so only open incidents may be taken.
        List<Case> open = [
            SELECT Id FROM Case
            WHERE Id = :caseId AND RecordType.DeveloperName = 'Incident_IT' AND IsClosed = false
            WITH USER_MODE
        ];
        if (open.isEmpty()) {
            throw fail('This incident is no longer open.');
        }
        try {
            Database.update(new Case(Id = caseId, OwnerId = UserInfo.getUserId()), AccessLevel.USER_MODE);
        } catch (DmlException e) {
            throw fail(e.getDmlMessage(0));
        }
    }

    // AuraHandledException only exposes its message to the client when it is set explicitly.
    private static AuraHandledException fail(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
