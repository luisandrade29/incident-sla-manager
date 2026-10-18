# Incident SLA Manager

Salesforce IT incident management with automatic queue assignment, SLA (Entitlements and Milestones) and escalation.
The full README (architecture, components, API docs) is written in the final delivery section; this file currently holds the implementation notes found so far.

## Notes from Section 3 (SLA)

- **SLA engine delay (~1 minute).** Milestone time triggers are processed with a latency of about a minute. In the 4-minute test process (`Incident_SLA_Test_Process`), the 75% warning was scheduled for minute 3 and was applied at ~3m55s; the violation was applied ~47s after the target date. Do not expect second-level precision from warning or violation actions.
- **Entitlement Processes in use cannot be redeployed.** Once an Entitlement points to a process, deploying it again fails with `Cannot update SLA process that is in use`. To change durations, create a new process version. Deploy Apex, triggers and flows separately from `entitlementProcesses/` after the first deploy.
- **Activation.** `EntitlementProcess` metadata deploys fine on a Developer Edition, but the process is only active with `<active>true</active>`. `SlaProcess.IsActive` is not updatable through the API. After deploying, run `scripts/apex/seed-sla-test.apex` to link the Entitlements to their processes.
- **Conflict with the Case Classifier.** The `CaseAiClassifier` trigger (separate project) enqueues a chained Queueable for every new Case that has a Subject or Description. For IT incidents this means unwanted AI callouts, and in Apex tests it fails with `Maximum stack depth has been reached`. Tests here create cases without Subject to avoid it; the Case Classifier should skip the `Incident_IT` record type.
- **Supervisor email is runtime-only.** The recipient of SLA alerts lives in the `Incident_Alert_Setting__mdt` record `Default`, which is excluded in `.forceignore` so a retrieve never pulls a real address into the repository. Set it with `scripts/apex/set-supervisor-email.apex` (edit the value locally, do not commit it).
- **Milestone completion.** `CaseMilestoneTrigger` completes open milestones when a case becomes closed (Closed or Resolved), so no warning or violation fires afterwards.
- **Email delivery: root cause found.** Emails sent by Flow or Apex leave Salesforce with the *running user's* address in the `From` header, in the test org a free Gmail address, and without a valid DKIM signature (`DKIM = none`). Gmail rejects most of them. Excerpt of the rejection from the org's Email Log (addresses removed):

  ```
  550-5.7.30 Authentication results:
  550-5.7.30  DKIM = did not pass
  550-5.7.30 To set up DKIM for your sending domains, visit
  550-5.7.30 https://support.google.com/a?p=turn-on-dkim
  ```

  The `WF_EMAIL_SENT` lines in the debug log only prove that Salesforce *accepted* the email, not that it was delivered. Emails from `noreply@salesforce.com` carry a valid DKIM and arrive. In a real company the fix is to send from a company domain with DKIM configured (Setup > DKIM Keys) and, ideally, an Organization-Wide Email Address on that domain; that is not possible with a personal mailbox in a Developer Edition.
- **Alerts no longer depend on email.** `Incident_SLA_Alert_Email` now notifies through three channels, in this order: a **Task** for the supervisor (related to the case), a **custom notification** (bell, type `Incident_SLA_Alert`) and, last and optional, the **email** (best-effort; skipped when `Supervisor_Email__c` is empty). Each channel has its own fault path, so one failure never blocks the others, and failures are appended to `Routing_Note__c`. Task and notification contain only case number, priority, type and SLA state, no personal data.
- **Configuration is runtime-only.** The recipient (`Supervisor_Username__c` and the optional `Supervisor_Email__c`) lives in the `Default` record of `Incident_Alert_Setting__mdt`, which is excluded in `.forceignore`; set it with `scripts/apex/set-supervisor-email.apex`.
- **Bulk behaviour.** Moving 50 cases to Warning in one update created 50 Tasks, 0 faults, and used 3 SOQL queries and 2 DML statements in total: the supervisor lookup does not run per case.

## Notes from Section 4 (escalation batch)

- **Rule.** `IncidentPriorityEscalationBatch` counts open `Incident_IT` cases with priority Critical or High per queue. Above the limit in `Escalation_Threshold__mdt` (record `DeveloperName` = queue developer name, `Default` for the rest; ships with `Default = 10`), the **oldest** cases are raised from High to Critical, never more than the excess of that queue.
- **No chain escalation.** A case is escalated at most once: `Last_Escalated_At__c` is stamped and cases with a value are skipped forever. Only High becomes Critical; Normal and Low are never touched.
- **Audit.** Every escalated case gets an internal `CaseComment` (`IsPublished = false`) with the queue, count, limit and excess.
- **Priority changes the running Milestone.** Verified in the org: changing a case from High to Critical on the real SLA process recalculated the *same* Milestone from 4 h to 1 h, counted from the original start (target 20:13:40 became 17:13:40 for a case started at 16:13:40). An escalated incident older than 1 h can therefore be violated immediately (inferred from the recalculated target date; not tested with an aged case); this warning is included in the comment text.
- **Security.** All classes are `with sharing`; queries use `WITH USER_MODE` and DML uses `AccessLevel.USER_MODE`, so FLS is enforced. The user who schedules the job needs the `Incident_Manager` permission set (otherwise `Last_Escalated_At__c` is invisible and the batch fails).
- **Side effect of the permission set.** Assigning `Incident_Manager` makes "Incidente de TI" that user's *default* Case record type. Plain cases created by that user (for example in the Case Classifier demo) become incidents. Tests therefore run as a dedicated user with the permission set (`IncidentTestUtil`), not as the admin.
- **Case Classifier guard.** The classifier trigger now skips `Incident_IT` (separate commit in that repository), so neither incidents nor the batch create classifier jobs. The batch tests insert cases *with* Subject and Description and assert that no `CaseClassifierQueueable` job exists.
- **Scale.** Planning reads up to 50 000 open Critical/High incidents in `start()` (one query, no SOQL in loops); `execute()` uses scope 200 with one update and one comment insert per chunk. Above 50 000, replace with an aggregate per queue.
- **Scheduling.** `scripts/apex/schedule-escalation.apex` schedules the batch hourly (`0 0 * * * ?`).
