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

## Notes from Section 5 (REST API: `SLAStatusService`)

`GET /services/apexrest/incidents/v1/sla-status` returns counts of open IT incidents by SLA state, grouped by `Case.Type`. It never returns Subject, names, emails or owners. Authentication is the standard Salesforce OAuth bearer token; the caller needs the `Incident_Manager` permission set (access to the class and to cases).

```bash
curl -s -H "Authorization: Bearer <ACCESS_TOKEN>" \
     "<ORG_URL>/services/apexrest/incidents/v1/sla-status"
```

Example response (fictional data):

```json
{
  "generated_at": "2026-10-18T17:54:30.982Z",
  "truncated": false,
  "groups": [
    { "type": "Infrastructure", "queue": "Infrastructure_Queue", "within_sla": 12, "near_breach": 3, "breached": 1, "total_open": 16, "no_sla": 2 },
    { "type": "Network",        "queue": "Network_Queue",        "within_sla": 5,  "near_breach": 0, "breached": 0, "total_open": 5,  "no_sla": 0 },
    { "type": "Security",       "queue": "Security_Queue",       "within_sla": 2,  "near_breach": 1, "breached": 2, "total_open": 5,  "no_sla": 1 }
  ]
}
```

- **Why group by Type and not by owner.** When a technician picks up a case its owner changes from the queue to a person, so owner-based counts would move cases out of the queue figures. `Type` is stable for the life of the incident. An empty or unknown Type counts as Infrastructure, the same rule as the `Incident_Assign_Owner` flow, and `queue` shows the queue that Type routes to.
- **States.** `breached`: `IsViolated` is true, or now is past `TargetDate` (this covers the ~1 minute SLA engine delay). `near_breach`: not breached and at least 75% of the time between `StartDate` and `TargetDate` has elapsed. `within_sla`: the rest.
- **`total_open` vs `no_sla`.** `total_open` is open `Incident_IT` cases *with at least one open Milestone* (`within_sla + near_breach + breached`). `no_sla` is open cases with no open Milestone at all (for example no Entitlement); they are not part of `total_open`.
- **Assumptions.** The 75% uses elapsed wall-clock time, which is correct because the Business Hours are 24x7 (it would be wrong for a business-hours calendar). If a case has more than one open Milestone, its worst state is counted, and each case counts once.
- **Limits.** One query to `CaseMilestone` with `LIMIT 10000` (to stay far from the query-row and 6 MB heap limits) plus one aggregate query for `no_sla`, both `WITH USER_MODE`. If the limit is reached, `truncated` is `true` and the counts are partial.
- **Errors.** Body `{"code": "...", "error": "..."}`: `403 FORBIDDEN` when the user cannot read the data (user-mode query failure), `500 INTERNAL_ERROR` for anything unexpected (the exception message is never exposed). Other HTTP methods are rejected by the platform; verified against the org: `POST`, `PUT`, `PATCH` and `DELETE` return **405** with `Allow: GET,HEAD` and the platform's own body `[{"errorCode":"METHOD_NOT_ALLOWED","message":"HTTP Method 'PUT' not allowed. Allowed are GET,HEAD"}]` (a JSON array, not the `{code,error}` shape above).
- **Tests.** `SLAStatusServiceTest` tests classification and aggregation with in-memory rows (no Entitlement Process needed) plus the REST handler (200, 403, 500). `SLAStatusServiceIntegrationTest` creates 200 real cases and moves the clock to check each state; **it depends on the deployed metadata** `Incident_SLA_Test_Process`, the `Incident_Manager` permission set and the `Incident_Assign_Owner` flow.
