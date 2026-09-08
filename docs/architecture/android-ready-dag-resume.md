# Android Ready DAG Resume

Android 1.1.11 (897) dispatches ready proposed actions when resuming an ordinary
task or continuing an already-planning task. It uses the existing dependency,
execution, verification and observation path, not a separate recovery executor.
This change builds on PR #2912's durable startup coordination.

## Reproduced Failure

On SM-T575 running 1.1.10, a persisted task contained a completed native memory
query and a proposed storage query depending on that completed node. Calling the
production resume entry returned `Task resumed` with phase `PLANNING`, without
executing storage. The real-device regression failed with expected `COMPLETED`
but actual `PLANNING`.

The resume entry only returned a snapshot. A snapshot's `pendingAction` exposes
confirmation-pending actions, not proposed actions, so the recovery worker's
confirmation loop did not dispatch the ready node. The continue entry had the
same missing proposed-action branch.

## Change

Resume now calls `executeFirstPendingAction()` when its existing recovery logic
selects `PLANNING`, then reconciles the execution loop. Continue does the same
for proposed actions while planning. Existing cancellation, explicit pause,
uncertain-result assessment and dependency checks remain in force. Completed
nodes are not made proposed again. No model, ASR, transport or Desktop behavior
is changed.

## Executed Validation, 2026-09-09

- 57 focused JVM tests passed in seven suites, without failures or skips.
- Three normal SM-T575 instrumentation cases passed: resume a dependency,
  continue a proposed node, and do not dispatch a cancelled session. Three
  opt-in boot phases were skipped in the ordinary run, not counted as passes.
- The combined active-plan, node-journal, startup and ready-resume regression
  passed 19 actual device tests, with ten opt-in phases skipped (29 reported by
  the runner). Repository checks also passed. Final cold activity launch was
  2,752 ms; this is a single observation, not a percentile performance gate.
- For the actual reboot, the test ran a real native memory query, committed its
  checkpoint and a dependent storage query, then deliberately killed its own
  process. The preparation runner's `Process crashed` is the injected boundary,
  not a passing test result.
- The tablet rebooted from boot ID
  `5105769e-ab37-4502-922b-4a4fbef9f4bb` to
  `7835e60f-19b6-49bd-ac1a-359171ee7e90`. After dismissing its swipe lock, no
  activity, test or manual resume enqueued recovery before automatic completion.
- Android started the app for `BootReceiver` at 02:52:12.072. Startup recovery
  began at 02:52:14.802 and succeeded at 02:52:19.929. Long-task recovery workers
  finished by 02:52:25.757. Worker success alone was not the acceptance oracle.
- A separate verification phase passed: the nonempty workspace and session were
  completed, native storage output was real, its checkpoint was created after
  this boot, the completed memory action fingerprint was unchanged, each node
  had one checkpoint, both durable observations were verified, and the workspace
  contained a successful storage tool call, a process-restart event and a result.
- Only after verification, explicit cleanup removed this test's own task,
  workspace, session and journal evidence. Existing user data and pairing were
  not cleared. No operation was performed on the attached S20U.
- The APK passed 72-library 16 KiB alignment and 24-library QNN package checks.

APK SHA-256:
`B6EB66A3F359C425908FBC1FDC88D10E94601B8AC2788E59A24AEAAA35FED2F2`.
Device logs and generated APKs remain local rather than in Git.

## Acceptance Boundaries

The test provides the DAG; the production agent, hardware registry, executor,
stores, boot receiver and recovery workers execute it. It does not validate model
decomposition or model-generated replanning. It verifies read-only native tools,
not exactly-once external writes, every execution path, final chat rendering,
multi-day tasks or a sub-five-second full-device reboot SLA. Those remain part of
the larger unfinished Run Kernel and long-task acceptance matrix.
