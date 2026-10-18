/**
 * Conclui os Milestones abertos quando um caso passa a fechado (Resolved ou Closed),
 * para que deixem de gerar avisos ou violações.
 * Porquê Apex e não Flow: a atualização de CaseMilestone fica numa única query e num único DML
 * para qualquer volume de casos, sem loops nem um DML por caso.
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
