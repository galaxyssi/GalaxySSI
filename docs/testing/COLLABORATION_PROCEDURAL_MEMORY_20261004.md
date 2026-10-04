# Procedural-memory verification, 2026-10-04

## Scope

Collaborative-evolution increment 3, Android v1.4.43 (1128), based on main after PR #3367. Desktop code and its running instance are unchanged. Only S26U (`SM-S9480`) was installed and tested; existing app data was preserved. No UI redesign, model calls, original research restart, door action, contact message, or other-device operation was performed.

## Results

- 788 Android unit tests across 63 collaboration/team/subagent suites passed, including 13 new procedure tests. Zero failures, errors or skips in the final run.
- 15 Desktop scoped-recall bridge tests passed. Expected unavailable-task exceptions are negative test cases.
- Debug and instrumentation APKs assembled successfully; final Gradle build completed in 6m 28s.
- Both APKs were installed on S26U. Package inspection confirmed v1.4.43 / 1128.
- Eight S26U instrumentation tests passed (`OK (8 tests)`, JUnit 3.22 seconds).
- Kotlin source-size and whitespace policies passed.

The first focused run had nine passing tests and one fixture isolation failure: a different node attempted to reuse a failure experience in the same independent round. The fixture now explicitly verifies that rejection, then uses a later round. Production isolation was not relaxed. Subsequent review corrected false/empty error classification and added explicit negative/recovery tests before the final rebuild and installation.

## Coverage

The unit suite exercises retained-lesson eligibility, immutable reviewed methods, rejected lesson handling, exact versions and hashes, changed-target invalidation, cross-group/blind-round isolation, strict input declarations, host-only bindings, atomic mixed-batch rejection, stable work identity, different-task reuse, reordered JSON recovery, missing storage, ordinary-work fast paths, live and next-round admission, unchanged unrelated work, terminal feedback and no invented learning gain.

Failure tests cover required original observations and page-read coverage, proposed remedies versus host facts, transient failure reconsideration, false/empty errors, explicit false-success outcomes, and legacy falsely failed envelopes. Historical observations are preserved rather than rewritten.

The encrypted-evidence device fixture now continues beyond independent retention: it publishes a `procedure_skill`, starts a new task, admits the procedure through the real goal controller, reopens the encrypted team store, invokes a local synthetic worker through `AgentTeamExecutionRuntime`, checks the pinned method and new inputs, captures exactly one execution, advances the next round, and verifies durable outcome plus scoped cloud recall. Temporary fixture groups and database rows are cleaned afterward.

Device regression classes: `CollaborationLearningDeviceTest` (2), `CollaborationEvolutionDeviceTest` (2), `CollaborationCapabilityDiagnosisDeviceTest` (2), `CollaborationScopedRecallDeviceTest` (1), and `CollaborationResearchWorkspaceDeviceTest#encryptedVersionsReopenReplayAndDisappearWhenFixtureGroupIsDeleted` (1).

## Commands

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests 'com.galaxyssi.chat.Collaboration*Test' --tests 'com.galaxyssi.chat.AgentTeam*Test' --tests 'com.galaxyssi.chat.AgentSubagent*Test' :app:assembleDebug :app:assembleDebugAndroidTest '-Pgalaxyssi.requireEmbeddedRuntime=false' -x :app:buildNativeMemory --max-workers=2 --console=plain
```

The native-memory build was excluded using the established local build path; no native/embedded-runtime code changed. Python ran `-m unittest test_collaboration_recall_bridge` from the Desktop backend directory. Device instrumentation used the explicit S26U serial and the classes above.

## Limits

These are local synthetic tests of integrity, invocation/context delivery and persistence. They do not demonstrate real-model learning quality, generalized transfer, scientific novelty, optimal automatic retrieval, or superiority over single-Agent work. The current skill is cognitive task guidance, not an installed executable `.gskill` package.

No full device reboot, prolonged Doze or provider/network-failure campaign was run here. General UI/contact/background and packaged Desktop smoke tests were not run because the authorized scope is synthetic local verification without user-task side effects. The full repository check was not repeated: the immediately preceding main increment's recorded run fails on existing unrelated i18n violations and local runtime files. No unrelated files were changed to bypass those checks.
