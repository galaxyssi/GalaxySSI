# Android continuous replanning

## Removed lifetime gate

`MobileNativeAgent.replanFromCurrentState` previously compared the plan's total
`replanCount` with three different ceilings: the ordinary planner preference
(default 3, up to 5), specialized adapters (8), and phone-development repair (2).
The total survived checkpoints and included unrelated earlier revisions. A
later recoverable failure could consequently prevent the model from seeing its
observation at all. Successful rolling batches bypassed the gate with `force`,
but later failures did not, so more progress could exhaust future recovery.

The total is now diagnostic only. Existing plans keep their revision and replan
counts; neither counter is reset to make recovery work. New revisions retain
the task identity, scoped history, verification results and checkpoints.

Both planner settings surfaces and their click handlers no longer offer a
maximum-replans control. The overview no longer promises a 1/3/5-revision cap.
The old serialized preference remains readable for existing backups and loop
snapshot metadata, but the ordinary execution-loop budget already disables
count enforcement and planner admission no longer reads this value.

## What still governs execution

- The existing planner-enabled and dynamic-replanning switches still govern
  ordinary automatic planning. Explicit continuation and existing specialized
  repair routes retain their existing admission rules.
- Conversation/turn ownership validation runs before model disclosure.
- Missing or invalid planner proposals do not count as a successful new plan.
- User cancellation, pause handling, native tool policies, observation,
  no-progress handling and tool-result validation are unchanged.
- The model receives the existing scoped failed-action observations. This does
  not introduce a fixed error-substring router or a new lifetime retry cap.

Removing a lifetime ceiling does not prove that every repeated failure is
recoverable. A durable no-progress strategy across model-loop reconstruction,
external-effect reconciliation, and real-Provider long-period tests remain
separate acceptance work. The global self-evolution scheduler is not changed by
this ordinary Android planner patch.

## Test contract

`AgentContinuousReplanningDeviceTest` exercises the production replan method
with explicit test-owned settings and isolated encrypted session persistence.
It never edits the user's planner settings and never executes external effects.

- Ordinary planning starts at 8,192 historical replans, then accepts 64 further
  revisions while reopening encrypted session state every eight iterations.
- Specialized planning accepts another 24 revisions above the old limit.
- Phone development repair reaches the planner beyond the previous two-repair
  ceiling, even when the ordinary planner switch is off, as before.
- Disabled ordinary planning and conflicting conversation identity still
  prevent the planner from being called.

Failure results and planner proposals are scripted fixtures. This verifies
admission, observation propagation and persistence, not actual repeated network
failures, model judgment, Linux execution, or a multi-day autonomous task.

## Executed validation (2026-09-09)

- Based on fetched main `4f8f7878e`, which includes PR #2947. Android version is
  1.1.29 (915); Desktop is unchanged.
- Debug app and instrumentation APK build passed in 5m31s. Core JVM regression
  selection: 186 passed, zero failures or skips.
- SM-T575: all five new tests passed in 45.748 seconds. The workspace,
  node-journal, fallback and startup suite passed 32 tests in 56.191 seconds;
  six opt-in lifecycle tests skipped. No reboot was performed in this run.
- Repository checks, 73-library 16 KB alignment audit and 24-library QNN package
  audit passed. No ASR/QNN model settings were changed.
- Installed via `adb install -r`, preserving user data and pairing. The first
  installation time remains 2026-09-07 07:17:23. The other connected phone was
  not modified.
- App APK SHA-256:
  `DE0830423BDAC9E29B980D9A5277214FC5D18B06AE1E30AF4352FED24B48777B`.
- Cold activity launch: 2,691 ms (one sample, not a P95 gate); crash buffer empty.

Local logs: `build/continuous-replanning-build.log`,
`build/continuous-replanning-device.log`, and
`build/continuous-replanning-recovery-device.log`.
