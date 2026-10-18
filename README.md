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
