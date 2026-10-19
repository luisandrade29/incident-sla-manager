/** Runs IncidentPriorityEscalationBatch on a schedule (hourly by default). */
public with sharing class IncidentPriorityEscalationScheduler implements Schedulable {

    public static final String JOB_NAME = 'Incident Priority Escalation (hourly)';
    public static final String CRON_HOURLY = '0 0 * * * ?';

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new IncidentPriorityEscalationBatch(), IncidentPriorityEscalationBatch.SCOPE_SIZE);
    }

    public static Id schedule(String cronExpression) {
        return System.schedule(JOB_NAME, cronExpression, new IncidentPriorityEscalationScheduler());
    }
}
