# Background Recovery Result Projection

## Scope

This extends the shared Context transcript projection into the production
`AgentLongTaskRecoveryWorker`. It is part of multi-broker/background correctness,
not completion of the whole transport specification or the ordinary connector
inbox's all-Activities-destroyed consumer.

## Changes

- Recovery invokes the runtime's own resume/assessment dispatch once. It no
  longer repeatedly invokes `approveNextAction` after the runtime yields. Pending
  permission and response states belong to the existing runtime state machine.
- The worker uses the App's configured language and writes audit/output/approval
  content into the original conversation and turn before committing the workspace
  result. It neither changes window selection nor creates a fallback conversation.
- A small checkpoint in the existing workspace ledger binds a pending result
  commit to workspace, conversation, turn, runtime session, persisted session
  timestamp, phase and loop revision. No second execution ledger is introduced.
- A saved terminal session with the original loop task ID can repair the crash
  gap before the pending checkpoint. A matching pending checkpoint also supports
  retry of nonterminal output, including an approval card.
- Projection-only recovery adapts the saved session into a read-only display
  state. It does not construct MobileNativeAgent, discover tools, query memories,
  resume the model or call a tool. Model/action completion is not inferred from
  transcript presence.
- A failed result commit leaves the workspace paused and makes WorkManager retry;
  the saved session remains unchanged. A replay after transcript write but before
  workspace completion uses the existing canonical output deduplication.
- The worker directly looks up its workspace rather than enumerating every
  recoverable workspace to locate one ID.

## Verification Plan

Focused JVM coverage includes pending-checkpoint identity, terminal-session
recovery, active/cancelled/finished workspace exclusions, commit ordering and
write failures. Existing initial/replanning/interrupted recovery policies remain
in the selection.

The isolated S26U suite runs the real production CoroutineWorker, supervisor,
encrypted workspace/session stores and transcript databases without an Activity.
It starts ten saved-result workers concurrently, repeats each completed worker,
checks pending approval preservation, and repairs a deliberately missing user
turn before retrying the same saved result. Its synthetic saved results do not
exercise real models, public MQTT, ten Activity windows, Doze or Android process
death. WorkManager uses its test runtime and foreground promotion may be rejected
by that fixture; this is not foreground-service lifecycle acceptance.

## Verified Results

- `build/mqtt-recovery-projection-isolated-v1.log`: isolated production Kotlin,
  test Kotlin and both verification APKs built successfully in 9m 43s. All **28
  selected JVM tests** across four recovery suites passed, with zero failures,
  errors or skips.
- `build/mqtt-recovery-projection-s26u-v1.log`: **28 instrumented tests passed
  in 6.322s**, explicit `OK (28 tests)` and `INSTRUMENTATION_CODE: -1`, no failure
  or crash status. This includes four new real-worker cases and the prior 24
  shared projection/window/storage cases. They are not 52 distinct tests.
- `build/mqtt-recovery-projection-s26u-v2.log`: the four real-worker cases
  independently passed again in **1.368s**. These are repeat samples, not four
  additional distinct cases.
- The ten-task case invokes ten production Worker instances concurrently using
  the process supervisor's bounded execution capacity, then reruns each completed
  worker. Every conversation has exactly one matching final reply and the saved
  runtime sessions remain unchanged. It is not ten real model executions.
- A prewritten reply retains its entry ID after recovery commits completion.
- A pending approval is projected as an approval card and remains waiting, with
  no successful tool call. Missing user-turn ownership causes retry and a paused
  workspace; after restoring that evidence, the same saved result commits once.

Verification APKs are retained under
`build/artifacts/mqtt-recovery-projection-v1/`:

- `verification-app.apk`: SHA-256 `B4EF1B88815C7B1B4866FB2EE31DDFB66D8ACB936A4F35CD164190F49B074CF4`
- `verification-test.apk`: SHA-256 `65F74C980237B30978F76387AE795CED343C607EBA5EA6E468F774ADA15984C7`

Only S26U `R5GL546G3LZ` was used. Both disposable packages were successfully
uninstalled afterward. Production readback is still 1.2.0 (1002), last updated
2026-09-13 11:34:31. No production installation, data clearing, UI navigation or
Desktop restart occurred. The normal full-runtime build is verified separately.

## Normal Build

`build/mqtt-recovery-projection-full-v1.log` passed in **7m 38s**, without the
isolated init script or runtime exclusions. Embedded-runtime verification,
instrumentation Kotlin compilation and full APK packaging passed. All **129 JVM
tests** across 17 suites passed, with zero failures/errors/skips, including the
recovery policies, task supervisor, dispatch loop, startup recovery, connector
identity/commit/usage and knowledge read-pool regressions. Whitespace and Kotlin
source-size checks passed.

The full `com.galaxyssi.chat` APK is **1.2.0 (1005)**, **418,778,958 bytes**,
SHA-256 `07AC21C0759330A4F7DD31FB7BB444F9139ECEF1022979C775986DC889A53538`.
An identical copy is retained at
`build/artifacts/mqtt-recovery-projection-v1/GalaxySSI-1.2.0-1005.apk`.
This APK is built but not installed. The old isolated test APK and its metadata
were removed from the normal Android-test APK output directory after exact hash,
application ID and resolved workspace boundary checks; archived copies remain.

## Remaining Boundaries

- The ordinary authenticated connector response inbox still requires a
  process-owned runtime consumer and shared run/learning/handoff finalization.
- A process dying before a nonterminal result's pending checkpoint is written
  still relies on the existing runtime recovery mechanisms; this patch does not
  claim arbitrary cross-store atomicity.
- A deleted/mismatched conversation is never recreated by recovery. Persistently
  invalid ownership needs explicit cancellation/repair, not invented routing.
- Real ten-window task completion and all-window-closed behavior, public small
  smokes, owned-network fault/performance matrices and battery measurements remain
  separate acceptance requirements.
