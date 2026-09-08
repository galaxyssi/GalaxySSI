# Android Durable Startup Recovery

Android 1.1.10 (896) coordinates ordinary task startup recovery through one unique
WorkManager job. This builds on PR #2911's complete encrypted plan checkpoint.

## Ordering And Ownership

Previously the boot receiver started detached restoration work, the evaluation
harness independently paused interrupted tasks on another executor, and the
message service scheduled recovery after Linux bootstrap. Their ordering was not
defined: a delayed pause could run after another path resumed a task. Process death
after a broadcast returned could also interrupt restoration without durable work.

The boot receiver now holds a `goAsync()` result until WorkManager acknowledges
the enqueue. Boot, service startup and process-interruption observation converge
on `galaxyssi-startup-recovery-v1` with `KEEP`. Recovery no longer waits for Linux
runtime pack installation. The worker performs reconciliation before dispatch and
waits for child-work enqueue commits before reporting success. Storage/scheduling
exceptions retry the durable job; they do not fall through into dispatch.

Reconciliation skips current-process sessions, supervisor-owned work, cancellation
requests, terminal sessions and explicit user pauses. It preserves concrete plan
integrity errors. Repeating a wake does not rewrite a session already adopted by
this process. The existing workspace revision check remains in place.

Per-workspace recovery names now use full SHA-256 rather than the Java 32-bit
hash, avoiding deterministic collisions such as `Aa` and `BB`. Existing recovery
claims and the supervisor still arbitrate execution; a new work name does not
authorize replay of uncertain external effects.

Existing boot-only workflow and global wake restoration remains at its original
boot entry point; ordinary service restarts do not acquire new global-agent side
effects. Worker success output records boot count, process identity and reconciled task count,
without task text, tool arguments or credentials, for boot acceptance evidence.

## Boundaries

This is not a new Agent Loop, an exactly-once external side-effect guarantee, or
proof that every provider and long-running task survives a reboot. Model-based
observation/replanning still runs through the existing per-workspace worker.
Android scheduling and user-unlock availability can delay recovery; no sub-five-
second reboot guarantee is claimed. Force-stopping an app prevents Android boot
delivery until the user starts it again. Historical count limits, indexed DAG
scheduling, multi-process fencing and all-path recovery remain separate work.

## Validation

Unit coverage exercises reconciliation-before-dispatch, retry after failed
reconciliation, repeat wakes, current-process/active owners, terminal and cancelled
work, explicit pause, integrity-error preservation and work-name collisions.
Device coverage uses encrypted workspace/session stores with 2,048 actions and
checks the actual production WorkManager request. An opt-in phase checks startup
completion in the current boot without explicitly enqueueing from the test.

### Executed On SM-T575, 2026-09-09

- Android 1.1.10 (896) built and installed in place. No application data was
  cleared or pairing reset. The attached S20U was not operated on.
- All 33 focused JVM tests passed (five suites, zero failures/errors/skips).
- Combined instrumentation passed 16 actual tests, with seven opt-in phases
  skipped (the runner reports 23 total). This includes the 2,048-node encrypted
  reconciliation/reopen test and production startup WorkManager execution.
- Actual reboot changed boot ID from `f4a7eb11-b242-48a2-aea4-101e6116b3c3` to
  `5105769e-ab37-4502-922b-4a4fbef9f4bb`. After dismissing the tablet's swipe lock,
  no activity or test explicitly enqueued work before the automatic completion.
- System logs show the process starting for `BootReceiver` at 02:29:00.613,
  `AgentStartupRecoveryWorker` starting at 02:29:03.552 and succeeding at
  02:29:07.471. The separate current-boot verification phase passed.
- That automatic boot run reconciled **zero pending ordinary tasks**. It proves
  automatic entry/ordering, not a nonempty task continuing to its final answer.
  The 2,048-node coordinator test is separate, not an end-to-end boot task test.
- Repository policy, 72-library 16 KiB alignment and 24-library QNN package
  checks passed. Model, ASR/QNN, transport and Desktop behavior were not changed.

The first boot check failed because it inspected a completed record from the old
boot before the new broadcast had been delivered. A subsequent read of Android's
broadcast queue showed this app's receiver still pending. The test now waits for
completion stamped with the current boot, never accepts an old success, and keeps
a bounded test observation deadline. This does not remove Android's boot delivery
delay or claim a sub-five-second system-startup SLA.

APK SHA-256:
`AEBC1BD71DDB6B365781EDF41338702A7F150005BD71095370E2EDD21ACA3905`.
Logs, APKs and device state remain local and are not committed.
