# Experience Transfer Verification 20261004

## Scope

Collaborative-evolution increment 4, Android v1.4.44 (1129), based on main after PR #3368. Desktop code and its running instance are unchanged. Only S26U (`SM-S9480`) was upgraded and tested, preserving app data. This increment changes no UI and adds no new polling or model-execution loop.

## Results

- Final Android regression: 806 tests across 64 collaboration, team and subagent suites passed, with zero failures, errors or skips. The final test-only run completed in 1m 18s.
- All 18 new transfer tests passed.
- All 15 Desktop scoped-recall bridge tests passed in 0.188s.
- Debug and instrumentation APKs assembled and installed successfully. Package inspection confirmed v1.4.44 / 1129.
- Eight S26U instrumentation tests passed: `OK (8 tests)`, JUnit time 6.782 seconds.
- Kotlin source-size and whitespace checks passed.

The initial focused run exposed three fixture identity collisions: distinct lesson reviews reused a dispatch ID. The fixtures now use independent review identities; production deduplication was not weakened. The first broad run passed 805 of 806 tests and hit an existing 5-second offline-recovery timeout while the build was compiling the instrumentation APK. The unchanged recovery class then passed all five tests on its own (1.422s), followed by a clean 806-test run without concurrent compilation. This did not establish the root cause of that isolated timing failure; no timeout or recovery policy was relaxed.

## Coverage

The new unit tests cover source/domain integrity, missing domain declarations, exact parent linkage, broken-assumption mappings, same-domain task transfer, failure-derived hypotheses, calibration/evaluation identity separation, source-regression and held-out partitions, report dataset/domain binding, incomplete measurements, negative transfer, exact tested-method retention, independent review, source/dataset changes, multi-generation source lineage, cross-group isolation, durable reuse in a later task, and unchanged original-domain retention for generic experiments.

The existing encrypted-evidence device test now continues into `CollaborationTransferDeviceFixture`. It registers calibration, held-out and source-regression artifacts, adapts a retained method, preregisters a comparison, and actually counts parsing operations while checking identical sums on synthetic rows. The successful candidate parses the held-out rows once rather than once per value. A separate negative report deliberately uses repeated parsing for the transfer case; the host records `transfer_not_demonstrated` and refuses retention eligibility. The successful report is independently reviewed, retained and published as a new target-domain procedure. Reopened encrypted storage preserves both results, exact source lineage and scoped cloud recall. An unrelated group cannot read the procedure. Temporary fixture groups and test databases are cleaned up.

Device classes: `CollaborationLearningDeviceTest` (2), `CollaborationEvolutionDeviceTest` (2), `CollaborationCapabilityDiagnosisDeviceTest` (2), `CollaborationScopedRecallDeviceTest` (1), and `CollaborationResearchWorkspaceDeviceTest#encryptedVersionsReopenReplayAndDisappearWhenFixtureGroupIsDeleted` (1).

## Commands

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests 'com.galaxyssi.chat.Collaboration*Test' --tests 'com.galaxyssi.chat.AgentTeam*Test' --tests 'com.galaxyssi.chat.AgentSubagent*Test' :app:assembleDebug :app:assembleDebugAndroidTest '-Pgalaxyssi.requireEmbeddedRuntime=false' -x :app:buildNativeMemory --max-workers=2 --console=plain
```

After the timing failure, the recovery class and instrumentation packaging were run with `--max-workers=1`, then the full selected unit test set was run by itself with the same flag. No source or test assertion changed between the broad failure and successful reruns. The established local build excludes the native-memory rebuild; no native implementation changed. Desktop verification ran `python -m unittest test_collaboration_recall_bridge` in the backend directory. ADB operations targeted only the approved S26U serial.

## Limits

No real providers, original protein research, door actions, contact messages or other devices were invoked by these tests. The device checks reopen encrypted persistence; they are not a physical reboot, prolonged Doze or long-duration network-failure campaign. No packaged Desktop smoke test was performed because Desktop code did not change.

These results prove contract validation, original-report comparison, scoped data integrity and persistence under synthetic fixtures. They do not prove general-purpose model learning, scientific novelty, semantic domain correctness, statistical generalization, or team superiority. Dataset identity separation does not prove independent unseen contents. A real, equal-budget, multi-domain evaluation remains necessary.

The full repository `npm run check` was not repeated. The preceding incremental verification records existing unrelated i18n/local-runtime-file violations; this change does not modify unrelated files to bypass them.
