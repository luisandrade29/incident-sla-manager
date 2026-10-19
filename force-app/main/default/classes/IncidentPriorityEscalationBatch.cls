/**
 * Raises the oldest High incidents to Critical when a queue has more open Critical + High incidents than its limit
 * (Escalation_Threshold__mdt). Each case is escalated at most once, and the reason goes in an internal CaseComment.
 * The plan is built in start() with one query; execute() only updates the chosen cases.
 * shortcut: reads up to 50,000 open incidents in start(); above that, aggregate per queue.
 */
public with sharing class IncidentPriorityEscalationBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer SCOPE_SIZE = 200;
    private static final String DEFAULT_KEY = 'Default';
    private static final String QUEUE_PREFIX = '00G';

    // Test-only: limits by queue DeveloperName (and 'Default') instead of the Custom Metadata.
    @TestVisible private static Map<String, Integer> thresholdOverride;

    // Reason per case, built in start() and used in execute() (Stateful).
    private Map<Id, String> reasons = new Map<Id, String>();
    private Integer escalated = 0;
    private Integer failed = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Set<Id> selected = planEscalation();
        return Database.getQueryLocator([
            SELECT Id, Priority, Last_Escalated_At__c
            FROM Case
            WHERE Id IN :selected
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Case> scope) {
        Datetime now = Datetime.now();
        List<Case> toUpdate = new List<Case>();
        for (Case c : scope) {
            // Re-check: the case may have changed between start() and execute().
            if (c.Priority == 'High' && c.Last_Escalated_At__c == null) {
                c.Priority = 'Critical';
                c.Last_Escalated_At__c = now;
                toUpdate.add(c);
            }
        }
        if (toUpdate.isEmpty()) {
            return;
        }

        List<Database.SaveResult> results = Database.update(toUpdate, false, AccessLevel.USER_MODE);
        List<CaseComment> comments = new List<CaseComment>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                escalated++;
                comments.add(new CaseComment(
                    ParentId = toUpdate[i].Id,
                    CommentBody = reasons.get(toUpdate[i].Id),
                    IsPublished = false
                ));
            } else {
                failed++;
            }
        }
        Database.insert(comments, false, AccessLevel.USER_MODE);
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('IncidentPriorityEscalationBatch: escalated=' + escalated + ', failed=' + failed);
    }

    /** Returns the Ids to escalate and fills the reasons. */
    private Set<Id> planEscalation() {
        List<Case> open = [
            SELECT Id, OwnerId, Priority, Last_Escalated_At__c
            FROM Case
            WHERE RecordType.DeveloperName = 'Incident_IT'
              AND IsClosed = false
              AND Priority IN ('Critical', 'High')
            WITH USER_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT 50000
        ];

        Map<Id, List<Case>> byQueue = new Map<Id, List<Case>>();
        for (Case c : open) {
            if (String.valueOf(c.OwnerId).startsWith(QUEUE_PREFIX)) {
                if (!byQueue.containsKey(c.OwnerId)) {
                    byQueue.put(c.OwnerId, new List<Case>());
                }
                byQueue.get(c.OwnerId).add(c);
            }
        }
        if (byQueue.isEmpty()) {
            return new Set<Id>();
        }

        Map<Id, Group> queues = new Map<Id, Group>([
            SELECT Id, Name, DeveloperName FROM Group WHERE Id IN :byQueue.keySet() WITH USER_MODE
        ]);
        Map<String, Integer> thresholds = loadThresholds();

        Set<Id> selected = new Set<Id>();
        for (Id queueId : byQueue.keySet()) {
            Group q = queues.get(queueId);
            if (q == null) {
                continue;
            }
            Integer limitForQueue = thresholds.containsKey(q.DeveloperName) ? thresholds.get(q.DeveloperName) : thresholds.get(DEFAULT_KEY);
            if (limitForQueue == null) {
                continue;
            }
            List<Case> cases = byQueue.get(queueId);
            Integer excess = cases.size() - limitForQueue;
            Integer picked = 0;
            for (Case c : cases) {
                if (picked >= excess) {
                    break;
                }
                if (c.Priority == 'High' && c.Last_Escalated_At__c == null) {
                    selected.add(c.Id);
                    reasons.put(c.Id, buildReason(q.Name, cases.size(), limitForQueue, excess));
                    picked++;
                }
            }
        }
        return selected;
    }

    private static Map<String, Integer> loadThresholds() {
        if (thresholdOverride != null) {
            return thresholdOverride;
        }
        Map<String, Integer> result = new Map<String, Integer>();
        for (Escalation_Threshold__mdt t : Escalation_Threshold__mdt.getAll().values()) {
            result.put(t.DeveloperName, Integer.valueOf(t.Max_Open_Critical_High__c));
        }
        return result;
    }

    private static String buildReason(String queueName, Integer open, Integer maxAllowed, Integer excess) {
        return 'Priority raised from High to Critical by the automatic escalation: queue "' + queueName + '" had '
            + open + ' open Critical/High incidents (limit ' + maxAllowed + ', excess ' + excess + '); this one is among the oldest. '
            + 'Note: changing the Priority recalculates the running Milestone deadline (from 4 h to 1 h, counted from the SLA start); '
            + 'an incident older than 1 h may immediately have its Milestone violated.';
    }
}
