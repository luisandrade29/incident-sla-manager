// Schedules the escalation batch hourly; pass another cron expression for a different frequency.
// Executar: sf apex run -f scripts/apex/schedule-escalation.apex -o <org>
System.debug('Job scheduled: ' + IncidentPriorityEscalationScheduler.schedule(IncidentPriorityEscalationScheduler.CRON_HOURLY));
