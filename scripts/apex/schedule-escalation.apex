// Schedules the escalation batch hourly; pass another cron expression for a different frequency.
System.debug('Job scheduled: ' + IncidentPriorityEscalationScheduler.schedule(IncidentPriorityEscalationScheduler.CRON_HOURLY));
