/**
 * Completes open Milestones when a case is closed so they stop warning or violating.
 * One query and one DML for any number of cases; a Flow would update them per case.
 */
public with sharing class IncidentMilestoneCompleter {

    public static void completeOnClose(List<Case> newCases, Map<Id, Case> oldCases) {
        Set<Id> closedIds = new Set<Id>();
        for (Case c : newCases) {
            Case old = oldCases.get(c.Id);
            if (c.IsClosed && old != null && !old.IsClosed) {
                closedIds.add(c.Id);
            }
        }
        if (closedIds.isEmpty()) {
            return;
        }

        List<CaseMilestone> open = [
            SELECT Id FROM CaseMilestone
            WHERE CaseId IN :closedIds AND IsCompleted = false
        ];
        Datetime now = Datetime.now();
        for (CaseMilestone m : open) {
            m.CompletionDate = now;
        }
        update open;
    }
}
