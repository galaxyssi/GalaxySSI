# Durable Android replanning recovery

## Problem

A task can be interrupted while the model is revising an existing plan. Previously
the startup path restored only the old graph and could perform a new liveness
assessment, change the original reason, or treat completed old actions as the
end of the task. Committed model observations existed but lacked a durable entry
point retaining the exact replanning revision.

## Contract

- The shared encrypted planning journal now supports initial planning and
  replanning. Each replanning reference binds the conversation, turn, base plan
  identifier and revision, original reason, planner configuration and input hash.
- The exact base graph is saved before the model runs. Its fingerprint includes
  executable arguments, history, evidence and checkpoints using the durable plan
  codec. Recovery must not normalize or dispatch that graph before the model
  completes the saved replanning operation.
- A fresh plan still passes plan validation and current safety review. Publishing
  it clears the pending reference together with the new graph.
- Startup recovery selects pending replanning ahead of generic action recovery.
  Model responses and tool observations reuse the existing scoped model journal.
- Changed base input or planner configuration fails explicitly. Active owners,
  terminal tasks and manual pause/cancellation do not trigger automatic recovery.
- A late planner result must not replace pause/cancellation at its callers.

## Tests

`AgentReplanningRecoveryPolicyTest` covers completed and running base graphs,
scope/revision mismatch, manual pause, active owners and terminal states.
`AgentReplanningDeviceTest` exercises the actual MobileNativeAgent replanning and
resume entry points with encrypted storage, a controlled model adapter, and a
native tool that appends to a test-owned file and fsyncs it. Recovery must continue
at model round two and leave exactly one tool append, preserve prior history and
advance the original plan from revision seven to eight. A real phone memory query
then supplies the next observation; a separate model planning round produces the
completion action in revision nine. The test must not mark an unfinished batch
as the completed goal.

Additional cases retain large evidence and arguments, reject modified base
graphs/configuration, and exercise pause/cancel during the model call.

The opt-in physical reboot harness preserves failed cases:

```powershell
./tools/dev/test-android-replanning-recovery.ps1 `
  -Serial R52R90282TY -ExpectedModel SM-T575 -CaseId <new-case>
```

Use the same case with `-Phase verify` after diagnosing a failure. Do not resubmit
the original task or remove user data. This harness explicitly resumes the saved
runtime with its controlled adapter after reboot. It does not claim live-provider
failure coverage or unattended production-worker completion; those remain separate
acceptance requirements. Initial planning's normal startup worker test remains a
separate regression case.

## Boundaries

The supervised project-specific recovery branch retains its existing behavior.
Custom planners without a recovery specification are not automatically restorable.
These tests do not establish a sub-five-second reboot SLA, all-provider failover,
or indefinite unattended execution. A provider request lost before its response
was committed may still need to be repeated; committed native effects must not be
blindly retried.

## Verified evidence (2026-09-10)

Android 1.1.48 (934) was installed in place on SM-T575. Existing production data
was not reset. The full debug build and JVM test run completed with 3,476 tests,
zero failures/errors and five skips. Repository, QNN packaging and 16 KiB native
alignment checks passed; the alignment audit covered 73 AArch64 libraries.

The related instrumentation batch plus the additional durable continuous case
completed with 23 actual passes and six opt-in skips. The added continuous case
performed 32 replanning revisions with durable storage and encrypted reopen,
finishing in 44.721 seconds. This is a correctness test, not a latency SLA.

- Physical replanning case `20260910-replan-v1148` passed after reboot. The process
  changed from PID 18491 to 5260. The controlled adapter resumed the committed
  observation, performed one native append in total, and advanced revisions seven
  through nine. Explicit post-reboot verification took 7.448 seconds. Automatic
  production startup recovery and a live provider were not used in this case.
- Initial-planning regression `20260910-initial-v1148` passed using normal app
  startup and the production recovery worker. The process changed from PID 13515
  to 4943, with a verified boot-ID change. It completed the native `memory_status`
  read without resubmitting the task or clearing production data.

Local evidence is retained under `build/replanning-20260910-replan-v1148/`,
`build/initial-planning-20260910-initial-v1148/` and the corresponding build/device
logs. These results do not establish the full cross-provider chaos matrix or
unattended long-running task acceptance.
