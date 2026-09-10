# Preserve normal DAG dependency waits

## Scope

Android 1.1.44 (930). This fixes ordinary `MobileNativeAgent` dependency dispatch,
not the broader model-generated DAG, full reboot, or long-duration acceptance.

When `AgentPlanExecutionBatchPolicy` returned an empty ready set, the existing
`noRunnableActionState` treated any remaining proposed/confirmation-pending action
as a blocked graph. A normal `WAITING_RESPONSE -> PROPOSED` dependency was
therefore changed to `BLOCKED` and its latest observation replaced by a generic
dependency failure. A `RUNNING -> PROPOSED` dependency behaved the same way.

An empty ready set is not sufficient evidence of failure while an existing node
still owns execution or awaits a remote observation. Dispatch now preserves
`EXECUTING` for running nodes, otherwise `WAITING_RESPONSE` for remote waits,
without replacing actions, results or attempts. If neither exists, the existing
missing-dependency blocking behavior remains. No polling, executor retry,
additional model call, lifetime budget or transport change is introduced.

Existing cold-boot recovery still converts interrupted local running nodes with
no durable observation into failed/uncertain nodes for recovery assessment. This
change does not prove worker liveness from a status flag or bypass that process.

## Reproduction

On the installed SM-T575 Android 1.1.43, the new device test reported two failures:
expected `WAITING_RESPONSE` but got `BLOCKED`, and expected `EXECUTING` but got
`BLOCKED`. The missing-dependency negative case passed. ADB's exit code was zero,
but the JUnit failures are the authoritative result.

Evidence: `build/dag-waiting-before-build.log` and
`build/dag-waiting-before-device.log`.

## Verification contract

`AgentDagWaitingDeviceTest` covers normal remote waiting, running dependencies,
missing dependencies, the normal dispatch entry, and a sole waiting node. The
encrypted-session case reopens its own stored graph, checks unchanged node state
and latest upstream observation, and verifies that only a completed upstream
makes its dependent runnable. The fixture executor throws if dispatch occurs
while waiting. Each case owns and clears only its uniquely named test session.

The full JVM suite, APK build, 16 KiB/QNN packaging guards, and real SM-T575
instrumentation must pass before this scoped change is accepted. These tests
provide the graph; they do not prove model decomposition, live provider results,
external write reconciliation, physical reboot or multi-day execution.

## Verified results (2026-09-10)

- Full Android build and JVM suite: 3,438 tests across 497 suites, zero failures
  or errors, five skipped; APK and instrumentation APK built successfully.
- Repository, QNN packaging, and 16 KiB alignment guards passed, including all
  73 AArch64 libraries.
- Android 1.1.44 (930) was installed in place on SM-T575. The original install
  date remained unchanged; no application reset or pairing changes were made.
- The combined DAG-wait, node-journal, startup-recovery, nonempty-recovery and
  continuous-replanning device run finished in 89.994 seconds: 28 passed,
  zero failed, six opt-in physical-reboot/process-death cases skipped. All five
  new DAG-wait tests passed. JUnit reports `OK (34 tests)`, which includes the
  six assumption skips; they are not counted as executed acceptance tests.

Evidence: `build/dag-waiting-verified-build.log`,
`build/dag-waiting-verified-device.log`, `build/dag-waiting-repo.log`,
`build/dag-waiting-16kb.log`, and `build/dag-waiting-qnn.log`.

No real provider, physical reboot, or long-duration run was exercised in this
combined test. Those broader goal requirements remain open. Desktop is unchanged
by this fix; its separately pending broker-capacity deployment is not accepted
by these Android results.
