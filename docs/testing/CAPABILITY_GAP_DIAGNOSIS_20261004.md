# Capability Gap Diagnosis Verification

Date: 2026-10-04

## Versions And Scope

- Android v1.4.41, versionCode 1126, replacement-installed on S26U (SM-S9480).
- Desktop source/package v1.4.9; the running Desktop instance was not restarted.
- Latest main fetched; predecessor PR #3365 merged while testing. The current branch was
  fast-forwarded to main because its file tree was identical to the tested predecessor base.
- No real provider calls, original research restarts, contact messages, door actions or other devices
  were part of these fixtures. Dedicated fixture groups were removed by test cleanup.

## Results

- 664 Android collaboration unit tests across 52 suites passed; no failures, errors or skips.
- 15 Desktop recall bridge tests passed, including bound-phone problem-directory round trip.
- Debug app and instrumentation APK builds passed. Native memory output was reused and the
  embedded runtime requirement was disabled for this debug build.
- Six S26U instrumentation cases passed in 1.824 seconds reported by JUnit:
  - two new capability diagnosis cases;
  - two collaborative evolution regression cases;
  - one scoped cloud/native recall case;
  - one encrypted workspace reopen/replay/fixture-removal case.
- Package query confirmed versionName 1.4.41 and versionCode 1126.
- Kotlin source-size and whitespace checks passed.

The initial full unit run hit the existing connection-recovery test's five-second timeout.
The final full run passed with unchanged timeout and assertions. The initial device run caught
a fixture reusing one assignment ID for diagnosis and a subsequent probe. The fixture now gives
each work item a distinct node ID while retaining the same person ID. Production deduplication
and publication rules were not weakened.

## Covered

Original failure indexing, atomicity, replay without rewriting original hashes, unknown error
codes, forged root-cause metadata, paging, revoked/cross-group/blind-round access, pinned prompt
recovery, source and timestamp checks, original-source read coverage, wrong digests, duplicate
checks, missing/null/typed scalar values, partial results, immutable diagnoses, historical gap
revisions, unchanged outputs versus unchanged error signals, and nested Desktop JSON reports.

The fixtures include twelve different error codes, including an unknown future code. They verify
that the host supplies facts without selecting a hard-coded recovery strategy. They do not test
whether a real model can correctly diagnose those twelve situations.

## Not Established

No claim of improved model intelligence, causal diagnosis accuracy, fewer real retries,
scientific innovation, cross-domain generalization or real-world recovery rate follows from
these tests. Matching a preregistered scalar is not proof that a capability gap is resolved.
No live MQTT path with the updated Desktop bridge, device reboot/Doze campaign or long-term
model-backed evaluation was run. Existing group/workspace recovery mechanisms are reused.

## Commands

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests 'com.galaxyssi.chat.Collaboration*Test' '-Pgalaxyssi.requireEmbeddedRuntime=false' -x :app:buildNativeMemory --max-workers=2 --console=plain
.\gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest '-Pgalaxyssi.requireEmbeddedRuntime=false' -x :app:buildNativeMemory --max-workers=2 --console=plain
python -m unittest test_collaboration_recall_bridge
```

Device classes: `CollaborationCapabilityDiagnosisDeviceTest`, `CollaborationEvolutionDeviceTest`,
`CollaborationScopedRecallDeviceTest`, and
`CollaborationResearchWorkspaceDeviceTest#encryptedVersionsReopenReplayAndDisappearWhenFixtureGroupIsDeleted`.
