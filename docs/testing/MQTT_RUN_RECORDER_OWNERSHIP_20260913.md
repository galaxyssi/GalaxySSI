# Shared Run Recorder Ownership

## Observed Prerequisite

While connecting ordinary connector replies to an application-owned consumer,
inspection found that every Activity and several background/evaluation paths
constructed their own `AgentRunRecorder`. Each instance cached run IDs, task
contexts and run rows while synchronizing only on itself. A warmed window could
therefore miss another owner's records or retain an old RUNNING state. Concurrent
begins could build replacement indexes from different cached inputs.

`update()` also selected the updated run as the conversation's active run,
regardless of whether a later turn or a new task thread had already begun.
Completing an older run could redirect later feedback and parent-run selection.

These are shared-task ownership problems, not Broker availability. Adding a
background reply owner before correcting them would add another inconsistent
cache. This prerequisite does not itself finish the headless response consumer.

## Changes

- `AgentRunRecorder.get(context)` is the only construction entry point. Its
  private constructor retains application Context, never an Activity. All callers
  in production and device tests use it; the existing encrypted store/schema and
  run identifiers remain unchanged.
- One process owns one cache and the existing synchronized recorder methods now
  serialize callers from all windows/background jobs, including read-modify-write
  index changes and task-parent assignment.
- Updating a run changes only that run. Beginning a new run remains responsible
  for selecting the conversation's active run. Feedback, completion, cancellation
  or interruption of an old run cannot select it again.
- Private-data destruction also clears the shared recorder and its actual v2
  storage before the existing legacy/global data cleanup, avoiding retained cache
  entries after reset. Tests do not invoke whole-App private-data destruction.

## Verification Plan

The isolated Android suite uses the real encrypted recorder and application
Context without Activity construction. It covers shared identity/fresh indexes,
late completion and persisted current-run pointers, old failure/cancellation,
old interruption after a new task thread, ten concurrent starts in one
conversation, ten concurrent conversations/completions, and cache visibility
after merge/clear. Concurrent tasks start behind a latch and use ten threads;
the recorder intentionally serializes mutations. These are not ten live model
tasks or a multiprocess database test.

Only the disposable verification package may run these cases, since they clear
that package's run recorder between cases. Synthetic conversation IDs suppress
personal-learning side effects. Production data and other phones remain untouched.

## Remaining Boundaries

The ordinary connector inbox's application-owned runtime continuation,
run/learning/handoff finalization and all-Activities-closed delivery still need
integration. This process-level cache unification is not a claim of cross-process
transactions, cross-store atomicity, idempotence of every learning callback, or
finished multi-broker performance/chaos/long-idle acceptance.

## Device Results

- First isolated build: `build/mqtt-run-recorder-isolated-v1.log`, successful in
  5m 56s. Because the private-data cleanup hook and test teardown guard were
  finalized during that build, it was not used as the final-source test claim.
- Final-source rebuild: `build/mqtt-run-recorder-isolated-v2.log`, successful in
  3m 52s, including production and instrumentation Kotlin and both APKs.
- S26U `R5GL546G3LZ` (`SM-S9480`): **35 instrumented tests passed in 7.367s**,
  explicit `OK (35 tests)` and `INSTRUMENTATION_CODE: -1`, no failure/crash status.
  `build/mqtt-run-recorder-s26u-v1.log` contains seven new recorder cases plus
  the prior 28 recovery/transcript/window/storage cases, not 63 distinct cases.
- Independent repeat: **7 recorder cases passed in 0.549s** in
  `build/mqtt-run-recorder-s26u-v2.log`. These are repeated, not additional cases.
- The tests inspect both the current-run API and the encrypted persisted context
  row, and verify the next run's parent/revision after an older completion. Ten
  same-conversation starts produce a single ordered revision chain; ten distinct
  conversations retain all run/context index entries after concurrent updates.

Exact isolated artifacts are retained under `build/artifacts/mqtt-run-recorder-v1/`:

- `verification-app.apk`: SHA-256 `9C592E0FDCB957B0A97142D0D4A288D55F079F01C856A5DBD36E65AD053279B7`
- `verification-test.apk`: SHA-256 `582DA25DFADF652EBA176983004BCE4D0D97A400BB2A77F7043089CB5A1F27BF`

Both disposable packages were uninstalled successfully. Production S26U remains
1.2.0 (1002), last updated 2026-09-13 11:34:31. No production installation,
private-data reset, UI navigation, other-phone operation or Desktop restart was
performed. The normal full-runtime build is recorded separately after completion.

## Normal Build Results

`build/mqtt-run-recorder-full-v1.log` passed in **4m 39s** without isolated init
or runtime exclusions. Native/default embedded-runtime verification, Android-test
Kotlin compilation and full APK packaging passed. All **154 selected JVM tests**
across 19 suites passed, zero failures/errors/skips, including the previous 129
selection plus eight conversation/Skill lifecycle and 17 learning-engine cases.
Whitespace and Kotlin source-size checks also passed.

The full APK is `com.galaxyssi.chat`, **1.2.0 (1005)**, **418,778,594 bytes**,
SHA-256 `12F3DBE95F63D4CB09978C91EC6B64BF0088A59D25C96345D80AACB965608860`.
The exact copy is retained at
`build/artifacts/mqtt-run-recorder-v1/GalaxySSI-1.2.0-1005.apk`.
It is built, not installed. Isolated test APK/metadata were removed from normal
Android-test outputs after hash, application ID and resolved workspace-boundary
checks. Archived verification copies remain.
