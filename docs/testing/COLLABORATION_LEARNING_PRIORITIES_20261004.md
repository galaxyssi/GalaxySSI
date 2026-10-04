# Learning-priority verification, 2026-10-04

## Scope

Android v1.4.42 (1127), based on main after PR #3366. No UI changes, Desktop restart, real provider call, protein research restart, door action or contact message. Only S26U (`SM-S9480`) was installed and tested. Existing app data was preserved.

## Results

- 775 Android unit tests across 62 collaboration, team-runtime and subagent suites: zero failures, errors or skips. This includes 13 new learning-priority tests.
- 15 existing Desktop scoped-recall bridge tests passed. Expected unavailable-task exceptions are negative test cases, not test failures.
- Debug APK and instrumentation APK assembled successfully.
- Eight S26U instrumentation tests passed (`OK (8 tests)`, 2.171 seconds reported by JUnit).
- Kotlin source-size policy and whitespace checks passed.

Commands used from `apps/android`:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests 'com.galaxyssi.chat.Collaboration*Test' --tests 'com.galaxyssi.chat.AgentTeam*Test' --tests 'com.galaxyssi.chat.AgentSubagent*Test' :app:assembleDebug :app:assembleDebugAndroidTest '-Pgalaxyssi.requireEmbeddedRuntime=false' -x :app:buildNativeMemory --max-workers=2 --console=plain
```

The first development test compile referenced a nonexistent codec helper; the fixture was corrected to exercise the existing encrypted-store codec through the same reflection pattern used by integration tests. The final source compiled and the full selected suite passed. No production assertion or timeout was relaxed.

Review also found that runtime normalization sorted children by ID after graph-plan priority projection. Learning plans now opt into preserving host-selected admission order, including dynamic expansion. Ordinary plans retain deterministic ID ordering. The final unit/device regression includes both modes, and both APKs were rebuilt and reinstalled after this correction.

## Coverage

The new unit tests verify selected/deferred alternatives, exact gap and agenda versions, resource-estimate uncertainty, invalid ranks, stale-gap admission, group/blind-round isolation, duplicate selection claims, persistence through the actual store codec, no extra workspace reads for ordinary work, atomic rejection, live graph admission, next-round admission, priority projection through runtime normalization, dependency preservation, elapsed-time feedback, and no invented learning/cost claims.

The new device fixture saves a capability gap and learning agenda to the encrypted workspace, admits one selected task through the actual goal controller, reopens the encrypted team store, executes a synthetic local worker through `AgentTeamExecutionRuntime`, advances the next round, reads its measured execution feedback, rejects a renamed duplicate and verifies scoped recall. Its unique group and database rows are cleared afterward.

A second local device fixture compares default ID order with host-selected admission order using one runtime worker slot. It does not invoke a provider or modify any user research.

Device regression classes:

- `CollaborationLearningDeviceTest` (2)
- `CollaborationEvolutionDeviceTest` (2)
- `CollaborationCapabilityDiagnosisDeviceTest` (2)
- `CollaborationScopedRecallDeviceTest` (1)
- `CollaborationResearchWorkspaceDeviceTest#encryptedVersionsReopenReplayAndDisappearWhenFixtureGroupIsDeleted` (1)

## Not Proven

These fixtures do not establish optimal autonomous learning choices, real-model quality improvements, cost reduction, scientific novelty or team superiority. Cross-provider actual token/monetary accounting remains unavailable in this common result contract; those fields are null, not zero. Priority projection is not preemption or a wall-clock ordering guarantee. Full device reboot, extended Doze and real-provider network-failure campaigns were not run in this increment.
