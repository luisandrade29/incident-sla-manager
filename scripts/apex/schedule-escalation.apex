// Agenda o batch de escalonamento de hora a hora. Para outra frequência, passar outra expressão cron.
// Executar: sf apex run -f scripts/apex/schedule-escalation.apex -o <org>
System.debug('Job agendado: ' + IncidentPriorityEscalationScheduler.schedule(IncidentPriorityEscalationScheduler.CRON_HOURLY));
