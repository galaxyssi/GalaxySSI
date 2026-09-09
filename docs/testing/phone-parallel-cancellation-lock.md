# Phone Parallel Cancellation Lock

## Reproduced Failure

On SM-T575 / Android 1.1.34, the real Codex-authored task
`live-observed-final-1788961888809` created a directory and text file, then stalled
at the independent read and SHA-256 actions. JDWP showed:

- The coordinator in synchronized `acceptConnectorResponse` waiting in
  `executeParallelActions` / `runBlocking`.
- Both batch workers waiting at `MobileNativeAgentRuntime.kt:580`, where native
  cancellation registration synchronized on the same Agent instance.

The workers never reached the tool registry. The file was not large and no model
request was outstanding for these two actions. A debugger snapshot was resumed
immediately; no user data or pairing state was cleared.

## Repair

An Agent-owned cancellation group uses its own private lock, independent of the
Agent state monitor. Invocation registration, removal, and cancellation snapshots
do not acquire the coordinator's monitor. Cancellation callbacks run outside the
group lock. Each invocation retains its own reason after removal; subsequent
invocations do not inherit an old cancellation. A throwing listener cannot
prevent sibling invocations from receiving cancellation.

The coordinator still serializes plan-state transitions. Actual independent
native tools remain concurrent under the existing adaptive capacity and resource
locks. This does not work around the defect by reducing parallelism to one.

## Acceptance

Unit regressions cover two workers while the coordinator holds an unrelated
Agent monitor, cancellation of all active workers, per-invocation reasons,
completed/new invocation isolation, callbacks that register from another thread,
throwing listeners, and isolation between Agent instances.

Device acceptance must rerun the normal Chinese model-authored write/read/hash
task and verify both parallel observations and the final model answer. A unit
test of the cancellation group alone is not full Agent Loop acceptance.

## 2026-09-09 Results

- Android 1.1.35 (921): 3,400 unit tests across 491 suites, zero failures/errors,
  five existing skips. Repository, 16 KiB alignment, and QNN package gates passed.
- The same `parallelNativeDispatchDoesNotNeedCoordinatorMonitor` instrumentation
  test failed on 1.1.34 with `TimeoutException` (10.539 seconds), then passed on
  1.1.35 (0.340 seconds). It calls real memory/storage tools while the coordinator
  holds the Agent monitor; it does not only test the cancellation helper.
- Real Chinese task `live-parallel-final-1788963842525` successfully created the
  file and completed both independent read/hash actions. Model observations
  matched an independent ADB SHA-256 check:
  `e1563165f85ed3e09f9b8ed6a294fff0f3777e62bf24458ecd11df9bce204407`.
- The full task still did not close: the existing publication-intent regex
  interpreted the user's explicit negative instruction as a commit requirement.
  The model repeatedly reported correct completion, but the framework rejected
  the marker. The test was cancelled through its own UI to stop this invalid
  loop. This is a separate completion-requirement defect, not a passing complete
  Agent Loop acceptance result.
- Desktop was observed absent during the run and was restarted without
  resending the task. The queued request subsequently arrived. This run is not
  a normal-latency benchmark or full reboot/network matrix acceptance.

Local evidence: `build/phone-parallel-monitor-before.log`,
`build/phone-parallel-monitor-after.log`,
`build/phone-parallel-final-desktop-turns.json`,
`build/phone-parallel-final-file-proof.txt`, and the corresponding screenshots.
