# Android planner workspace identity

The ordinary planner previously generated a fresh UUID and used it as turn,
task and file-workspace identity for every model-native planning call. Native
tools could create a file in one planning loop and then search a different
workspace in the next. That differs from the existing conversation-scoped file
and phone-Linux execution paths.

## Ownership

`AgentPlannerToolLoopRequest.create` is the production request factory:

| Field | Source |
| --- | --- |
| session | Current runtime session |
| conversation | Current conversation, with the runtime-session legacy fallback |
| turn | Task execution turn, with the same fallback as `startExecutionLoop` |
| task | The execution-loop task identity, currently its bound turn |
| workspace | Existing `AgentWorkspaceScope.id(conversation, session)` |

Initial planning now receives the active execution turn. Replanning already
recovers the original task turn from persisted actions. A different runtime
instance or later user turn in the same conversation therefore keeps the same
file workspace. A different conversation receives a different workspace. The
existing tool-input binding still prevents a model from substituting another
conversation's workspace ID.

## Per-loop identity

Stable task ownership does not mean that separate planning loops are the same
execution attempt. Each planning-loop request has its own `loopId`. Copies used
to resume that request preserve it. Model round numbers and provider tool-call
IDs can restart in another loop, so timeline keys include this identity. Retries
inside one loop still update one timeline entry. Native invocation attributes
and emitted events retain the identity without changing user-visible wording.

The loop identity is opt-in, supplied by the planner request factory. Existing
callers without it retain their original replay-key format and timeline keys;
in particular, this patch does not reset the local-model web runner's keys.
Existing workspace directories are not moved or deleted. Incorrectly named
legacy directories require ownership-aware recovery, not a blind cross-session
file migration.

Derived idempotency keys distinguish separate loops while preserving a replay
of the same request. This is not proof of exactly-once external side effects:
reconstructing an interrupted loop still requires its persisted identity and
external-effect reconciliation. The task's conversation/turn/workspace cannot
serve as a replacement for an individual invocation key.

## Verification scope

Host tests cover ownership, repeated planning, runtime replacement, conversation
isolation, request copying, loop-scoped timeline keys and native replay behavior.
Device tests run real production workspace file definitions through the model
tool loop. The registry is recreated between calls, so a cached tool response
cannot stand in for reading the file. Only uniquely named test directories are
created and removed. Plans are scripted test responses; no live Provider or
phone-Linux compiler acceptance is claimed by these tests.

The remaining unified-kernel/DAG goal includes durable loop-request replay,
external-effect reconciliation, all execution paths and long-period scheduling.
This patch does not alter ASR/QNN model loading or user pairing/configuration.

## Executed verification (2026-09-09)

- Android 1.1.28 (914), based on main `89bf8c3c2`; both debug APKs built.
- Focused JVM selection: 93 passed and one skipped. Core regression selection:
  186 passed, no failures or skips. These selections overlap and are not additive.
- The first implementation failed the existing non-idempotent restart test:
  defaulting every loop to a new UUID executed one effect twice. The correction
  makes the nonce planner-only and preserves the original replay-key format for
  unscoped callers. The existing test and a legacy-key regression now pass.
- SM-T575: all three production file-tool tests passed in 0.492 seconds. The
  journal/fallback/startup suite passed 29 tests in 57.858 seconds; six opt-in
  lifecycle tests were skipped. This run did not reboot the tablet.
- Repository checks and all six core-runner contract tests passed. The APK
  passed the 73-library 16 KB alignment audit and 24-library QNN package audit.
- The app and instrumentation APKs were installed with `adb install -r` only on
  SM-T575. First installation time remained 2026-09-07 07:17:23; the installed
  version is 1.1.28 (914). No user data or pairing reset was performed.
- App APK SHA-256:
  `C0CADBBDD30C4EE9B9DE39E3DA83641CF409465FEF8F7A59C07ECD10924C1FE7`.
- One cold activity launch reported 2,701 ms; the crash buffer was empty.
  This is neither a P95 measurement nor evidence of a performance improvement.

Local logs are under `build/planner-workspace-{final-build,core-unit,device,
recovery-device}.log`. No live-Provider, multi-day execution, Linux compilation
or complete external-side-effect recovery acceptance is claimed.
