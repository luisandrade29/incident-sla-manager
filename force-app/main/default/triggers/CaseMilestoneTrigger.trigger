trigger CaseMilestoneTrigger on Case (after update) {
    IncidentMilestoneCompleter.completeOnClose(Trigger.new, Trigger.oldMap);
}
