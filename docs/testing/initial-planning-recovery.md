# Pending initial planning recovery

## Scope

An Android task can lose its process before its first executable plan exists.
The session root now retains a compact reference to its initial planning input.
The complete input is stored in encrypted, bounded Run Kernel records using the
existing model-loop journal, not as a large value in the session root.

The input includes the original goal, conversation and turn identifiers, private
mode, transcript, requested members, execution mode, and planner specification.
Supported specifications preserve a guarded model configuration fingerprint,
rule-based planner, selected phone reasoning action, or selected native action.
Custom planners without a recovery specification keep their existing behavior;
this change does not claim recovery for those implementations.

The planning intent lease covers restoration through plan publication. The
inner model-loop journal separately restores committed model responses and tool
observations. Publishing the plan clears the pending reference. Cancellation and
manual pause prevent a late planner result from starting execution.

## Recovery conditions

- The workspace and execution loop must retain the same conversation and turn.
- The session must still be planning, or paused by process interruption.
- Terminal, cancelled, manually paused, or actively owned work is not restarted.
- Missing or changed input and changed guarded-model configuration fail explicitly.
- The ordinary startup recovery worker reconstructs the saved planner instead of
  selecting a new default provider or treating a planless task as screen inspection.

## Verification

`AgentInitialPlanningRecoveryPolicyTest` covers eligibility and scope mismatches.
`AgentInitialPlanningDeviceTest` covers large encrypted input, restoration of a
model observation without repeating its native effect, and pause/cancel races.

The opt-in device case interrupts `MobileNativeAgent.submitGoal` after its
initial input is committed and before a plan is returned. It uses a read-only
phone memory query. A physical reboot is followed by normal `MainActivity`
startup. The production recovery worker must complete the original workspace
without an explicit test call to resume or submit the task.

```powershell
./tools/dev/test-android-initial-planning-recovery.ps1 `
  -Serial R52R90282TY -ExpectedModel SM-T575 -CaseId <new-case>
```

The harness force-stops the prepared app before reboot to prevent sticky service
recovery racing the reboot. Consequently this measures recovery after reboot
and normal app opening, not unattended boot-broadcast recovery. Failed cases
must be retained; resume verification with the same case and `-Phase verify`.
Do not delete user data, resubmit the task, or substitute a new successful case.

## Remaining boundaries

The automatic startup case is a real native read, not a live cloud-provider
failure test. The model observation case uses a controlled adapter. These cases
do not establish all-provider failover, reboot latency percentiles, recovery of
every replanning path, or indefinite unattended execution. A provider request
whose response was never committed may still need reconciliation or another
request; journaled native effects must not be repeated blindly.

## Verified device evidence (2026-09-10)

- Android 1.1.47 (933), installed in place on SM-T575 / R52R90282TY.
- Complete JVM suite: 3,470 tests, zero failures/errors, five skips.
- Related device suite: 12 passes, four opt-in skips, zero failures.
- Repository, QNN package, and 73 AArch64 library 16 KB alignment checks passed.
- Physical reboot case: `20260910-initial-v1147`; PID 17684 became 4585.
- Boot ID changed from `b6103e57-64f7-4b51-8e96-3e0857b4d001` to
  `23d3c257-c841-4f44-8be0-00b0565b7a53`.
- Normal app startup completed the original native memory query without task
  resubmission or production data deletion. The verification test took 26.68 s,
  including startup and instrumentation overhead; this is not a sub-5-second SLA.

Logs are retained locally under `build/initial-planning-*`. The first controlled
model test failed because its requested fixture Agent had not been registered.
Adding that fixture target resolved the test; production availability checks were
not relaxed. The physical reboot case did not require a replacement submission.
