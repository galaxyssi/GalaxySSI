# Cross-task capability reuse trials

The adaptive pilot can retain one **test-owned** collaboration group across
separately frozen phases. This closes a measurement gap: the default pilot
deletes its group and its research archive when a run ends, so it cannot test
later autonomous use of the group's experience.

This is test infrastructure, not a new model policy, a task-specific solver or
evidence that the system has learned. Production prompts, group recall and
execution remain unchanged. No research inputs or results are bundled.

## Opt-in protocol

The existing protocol optionally accepts:

```json
"continuity": {
  "study_id": "unique-study",
  "phase": 1,
  "previous_report_sha256": "",
  "retain_history": true
}
```

The next phase has a new `pilot_id`, phase number 2 and the SHA-256 of the
completed predecessor report. Each phase still freezes its own goal, device,
App-selected model, resource envelope and protocol hash before dispatch.
The model, effort, target, exact device and original roster remain fixed within
this trial. Changing them requires a separately registered study.

The journal creates its own group in phase 1. Callers cannot pass a conversation
ID or adopt an existing user group. It reserves a phase before creation or
dispatch, checks that the previous phase has no pending remote owners and has
archived its checkpoint, and rejects duplicate, concurrent or out-of-order
phases. A missing group is not silently reconstructed. An interrupted reservation
remains unavailable for automatic replay; inspect its original evidence first.

Every phase uses a fresh run, turn and execution database. `retain_history=true`
keeps the group, ordinary product memory/archive and execution records after
bounded task cleanup. A terminal negative result may still provide experience;
its failed verdict is never changed to success. An unconfirmed remote stop or
incomplete archive blocks the next phase. Set `retain_history=false` on the final
phase to use the normal group cleanup after archiving. The ownership tombstone
remains so the same study cannot accidentally run again.

## Initial Execution Identity

An optional top-level `initial_identity_policy` accepts `production` (the
unchanged default) or `run_scoped`. The latter deterministically namespaces each
initial execution node using the pilot, group, run and original node ID, before
admission. Stable roster IDs, roles, assignments, group access, normal history
retrieval and later production graph expansion are not replaced. Resuming the
same frozen run yields the same node IDs; a new phase yields distinct IDs.

This addresses one concrete confound: Desktop can key a native conversation by
App conversation and execution-member identity, so changing only run and turn
IDs may resume an initial coordinator's previous provider conversation. This
option does not delete provider history or disable ordinary product memory.
It also does not prove a fresh provider thread, skills-only transfer or process
isolation. Audit actual provider thread IDs and injected context separately.

Each phase freezes this option in its protocol hash. It is not part of the
stable-roster signature, so a predeclared phase may change identity policy while
retaining its own group. Report such a change as an experimental condition;
do not silently mix conditions or change a protocol after dispatch.

## Interpretation

The test harness does not add previous answers to the new goal. The **product's**
normal history and capability retrieval remain enabled. Therefore this condition
tests ordinary persistent group experience, not skills-only transfer. It must not
be reported as a cleared-history learning condition.

Distinguish:

1. An original method exists and is available in the new task.
2. A directory entry or prompt excerpt was exposed.
3. An Agent retrieved the original and checked its applicability.
4. A subsequent action actually used, revised or rejected it.
5. Independent future-task measurements improved relative to a strong control.

The continuity report sets autonomous-retrieval and learning claims to false.
Before and after each phase, separate hashed observer snapshots retain the
visible workspace revisions. They are not injected into the task. These files
do not contain every tool receipt or research-archive record; preserve the
ordinary experiment evidence as well before releasing the final group.
Fresh run/turn IDs do not prove a fresh provider thread: Desktop may resume a
native member conversation. `fresh_provider_thread_verified` remains false;
audit provider thread IDs and context before claiming a cleared-context study.
Observer reads and a passing instrumentation test cannot prove steps 3-5.
Real trials need separate analysis of tool receipts, method bindings, outcomes,
failed cases and resource use. Cost, useful work and quality are separate metrics.

## Local device check

`CollaborationPilotContinuityDeviceTest#retainedMethodAcrossFreshTaskAndProcess`
accepts `continuityPhase=seed` and then `continuityPhase=recover`, with the same
fresh `continuityToken` (lowercase letters, digits and hyphens, max 32). Launch
these as two separate instrumentation processes on the explicitly selected
device. The fixture saves an unverified synthetic workflow, checks retrieval
and its failure condition under a fresh run/turn after process restart, then
cleans only its dedicated test group. It also checks that run-scoped initial IDs
change while stable people remain the same. It makes no model calls and cannot
verify provider-thread identity or autonomous use of the saved method.

## Verification (2026-10-09)

- Android 1.4.123 / 1208: main and instrumentation APKs built.
- 67 focused JVM tests passed with no failures or skips.
- S20U: seed and recover passed in two distinct App processes; original method
  content and its contraindication survived a fresh run/turn.
- Two existing device regressions passed: scoped cloud/native recall and
  encrypted workspace reopen/replay/deletion.
- Source-size policy and whitespace checks passed.

No real model was called for this increment. A real longitudinal trial, provider
context audit, controlled quality comparison and long-term retention remain open.
