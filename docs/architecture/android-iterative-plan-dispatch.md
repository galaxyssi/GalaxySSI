# Iterative Android Plan Dispatch

Android 1.1.25 replaces recursive next-batch dispatch with an in-process
trampoline. This is part of ordinary Agent Loop long-task integration, not a
replacement for the durable Run Kernel or a claim that the full dynamic DAG
objective is complete.

## Reproduced failure

On SM-T575 with Android 1.1.23, the real native memory tool completed 16 sequential
dependency nodes and persisted all 16 checkpoints and verified observations.
However, the number of `executeFirstPendingAction` frames grew as
`[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]`.
The regression failed its bounded-stack assertion after 4.903 seconds. This is
evidence of linear stack retention, not a deliberately induced tablet crash.

Both serial and parallel action completion requested the next batch by calling
`executeFirstPendingAction` before the preceding call returned. Rolling model
revisions used the same path. Removing action budgets alone therefore could not
make arbitrarily many batches stack-safe.

## Dispatch behavior

- Each `MobileNativeAgent` owns a dispatch loop. Same-thread nested requests mark
  the next dependency-selection pass as requested and return the current snapshot.
- The outer caller runs that pass only after the preceding batch has returned.
  Repeated requests coalesce; they do not enqueue duplicate actions.
- The existing batch selector, resource policy, executor, observation, node
  journal, session checkpoint, model replanning and finalization still execute.
- No lifetime batch-count limit or additional sleep is introduced. A batch that
  waits for an external response returns normally without busy polling.
- A pending continuation stops after a session/turn/plan identity change or an
  explicit paused/terminal phase. A plan revision retaining the same plan ID may
  continue. Exceptions always release the thread-local frame.

The frame contains only one boolean. It is not another persistent work queue or
an execution owner. Existing production worker ownership and durable node logs
remain responsible for cross-thread dispatch and process recovery. This change
does not itself provide cross-worker mutual exclusion or exactly-once effects.

## Verification scope

The rolling regression also exposed a node-identity defect: moving an initially
untagged completed action into history adds `plan_revision` to its parameters,
changing its specification hash. New checkpoints record whether that parameter
was present at dispatch. Identity reconstruction removes only a subsequently
added, matching display revision; original parameters, mismatched revisions,
action scope and checkpoint attempt remain bound. Both inline and paged session
checkpoint codecs retain this flag. Legacy checkpoints without it retain their
previous hashing semantics; this is not a migration of already altered legacy
history. Their conservative lookup behavior remains a separate recovery boundary.

The host suite covers 100,000 continuations, duplicate requests, pause/scope stop,
waiting, exceptional cleanup and independent Agent instances. Device coverage
uses real hardware reads and checks checkpoints and observations in the encrypted
node journal. The rolling-plan device case injects structured model JSON into the
production parser; it does not claim a live Provider generated the plans.

## Executed Validation, 2026-09-09

Integrated against main `c426eb859`, Android 1.1.25 (911):

- 95 focused JVM tests passed, followed by 23 active-plan/result-page persistence
  tests. All 118 passed without failures or skips.
- Five core-regression manifest/runner tests and repository checks passed.
- On SM-T575, 12 ordinary node-journal tests passed in 25.753 seconds. Two
  process-death phases were skipped in this ordinary invocation, not counted
  as passes. The 16-node dependency chain and eight rolling two-node batches
  both reported maximum dispatch depth 1. The rolling test reopened the actual
  encrypted session and found all 16 verified node observations.
- A further 17 ordinary startup, ready-node resume and connector-fallback tests
  passed in 28.747 seconds; four opt-in boot phases were skipped.
- Explicit process-death injection terminated after the first parallel result
  committed. A new process passed recovery verification in 0.271 seconds:
  the committed result survived and the uncertain second attempt could not be
  blindly claimed again. The deliberate process exit is not a passing test.
- Real reboot acceptance initially failed: verification started before observing
  boot delivery, and no current-boot startup record appeared within its deadlines
  (120 seconds for the workspace, then 90 seconds for startup). This failed run
  remains in the local evidence; it is not counted as a pass.
- The same unfinished fixture was retained for another real reboot. After
  dismissing the swipe lock, Android's broadcast queue explicitly showed
  `BootReceiver` pending, then delivered. No instrumentation or activity manually
  enqueued recovery in that interval. Both subsequent verification tests passed
  in 0.743 seconds: current-boot startup completion, automatically completed
  dependent native storage output, an unchanged completed memory fingerprint,
  one checkpoint per node and verified journal results. The 0.743 seconds is
  verification time, not reboot/recovery latency. The first-run failure's exact
  delivery cause and a sub-five-second recovery SLA are not resolved by this fix.
  Explicit cleanup runs only after successful verification and removes this
  fixture's own records, not user sessions or pairing.
- Desktop's existing durable-DAG suite passed 31 tests and five subtests.
  Desktop production code was not changed by this Android fix.
- APK validation passed for 73 aligned AArch64 libraries and all 24 required
  QNN libraries. Installation retained the original first-install timestamp.

APK SHA-256:
`BF9D10AD6F91872605EEB9B34DC144EA12CF5363584218B54CD1FFACEDEEE570`.
Generated logs, diagnostics and APKs remain local, outside the PR.

Real model-authored graph revisions, all execution paths,
external-effect reconciliation, durable long-period scheduling and the remaining
legacy failure-replan count policy still need separate integration and acceptance.
