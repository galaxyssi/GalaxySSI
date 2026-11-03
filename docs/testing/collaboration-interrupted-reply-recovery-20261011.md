# Collaboration interrupted reply recovery validation

Date: 2026-10-11

Android: 1.4.154 (1239), debug, Samsung Galaxy S26 Ultra (SM-S9480).
The installed application was updated in place. Existing pairing and conversation
data were retained. No S20 Ultra data or Desktop code was changed.

## Automated results

- APK and instrumentation APK: built successfully.
- 71 focused unit tests: passed, zero failures/errors.
- Six device recovery tests: passed.
- One optional selected-completed-team repair test: skipped because its explicit
  task-selection argument was not supplied.
- Selected-group read-only diagnostics: passed before and after recovery.
- `git diff --check`: passed.

Unit suites: `AgentManagedResponseRetentionPolicyTest`,
`AgentTeamCancellationRaceTest`, `AgentTeamDurableRecoveryTest`,
`AgentTeamLiveGraphIntegrationTest`, `AgentTeamReplyRecoveryTest`,
`CollaborationConnectionRecoveryTest`, `CollaborationCurrentRunSelectionTest`,
`CollaborationOrganizationLifecycleTest`, and `CollaborationResultFinalizerTest`.

Device suites: `AgentTeamReplyRecoveryDeviceTest` and
`AgentTeamDurableRecoveryDeviceTest`. Fixtures use isolated run identifiers and
do not clear user data or dispatch model requests.

## Existing interrupted run

Read-only inspection confirmed that the dispatched child had a persisted wire
identity but no managed receive intent. Its original Desktop task had completed
at 10:50:30, while Android retained RUNNING for that node. The parent remained
user-authorized RUN, with no manual task stop recorded.

After the update and application launch:

1. Recovery rebuilt the missing intent from the original journal and wire identity.
2. The original result was retrieved and committed. Its ledger state became APPLIED.
3. The original child still had exactly one CHILD_RUNNING event; a CHILD_SUCCEEDED
   event was appended without redispatching that assignment.
4. The parent moved from INTERRUPTED to RUNNING and admitted queued successors.
5. Two successors had durable PENDING receive intents. Read-only Desktop status
   inspection confirmed both original successor task identities were running.
6. Instrumentation-induced process restarts retained the applied original result
   and the successor bindings. The application was relaunched after inspection.
7. A screenshot confirmed that the group panel showed the unresolved original
   research/recovery state instead of the latest completed follow-up.

## Boundaries

This validates recovery and scheduling, not achievement of the underlying research
goal. Existing evidence/publication acceptance remains in force. A full physical
device reboot and multi-day soak test were not performed in this validation.
Explicit user pause/stop persistence and duplicate-result behavior were covered by
the isolated device and unit suites.
