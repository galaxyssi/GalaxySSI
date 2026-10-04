# Team Invention Verification 20261004

## Scope

Collaborative-evolution increment 6, based on merged PR #3370. Android version is 1.4.46
(1131). Desktop code and its running instance are unchanged. The user first deferred phone
testing, then reconnected S26U; only that device is authorized. Real model calls remain excluded.

## Acceptance Matrix

| Requirement | Check |
| --- | --- |
| Useful peer interaction | Exact idea, non-contributor challenge, matching contributor response and discriminating test |
| Substantive combination | At least two authors, retained/changed mechanisms, response effect and interaction hypothesis |
| Actual task integration | Existing goal DAG dispatches challenge/respond/combine with immutable identities and refs |
| Original conditions preserved | Same opportunity/criterion and exact datasets, controls, cases, source, method and budget |
| Meaningful controls | Every source idea plus a separate single-author method, all preregistered before any trial |
| Full reported costs | Preparation, coordination and execution; per-trial coverage and cumulative campaign ceiling |
| Independent retention | No idea/critic/response/plan/control/result/trial contributor may independently retain |
| Negative findings preserved | Missing, regressed, non-improving or over-budget evidence cannot become retained team capability |
| Durable provenance | Reopen workspace and work claims; reject changed parents, datasets or removed/null synthesis links |
| Existing behavior | Ordinary task fast path, generic experiments, innovation assessment, procedural memory and recall regression |

The local execution test combines normalization and deduplication, comparing the resulting
algorithm with each parent and an unchanged single-method control. The algorithms and inputs
are developer-designed synthetic fixtures. The result is not evidence that a model invented
the method, or that a real team outperformed a same-budget real single Agent.

## Device Scope

`CollaborationTeamInventionDeviceTest` creates an isolated collaboration group, publishes two
ideas, independent challenges, contributor responses, synthesis and a combined innovation.
It admits a response task through production work binding, reopens encrypted workspace storage
and verifies pinned identities and preserved contributors. The fixture group is cleaned up.

The nine previously pending innovation/evolution/learning/recall checks passed in the same
device run. The innovation fixture runs an actual local parsing worker, measures four
baseline parses versus one candidate parse at equal answer correctness, rejects a deliberately
regressed variant and reopens its task/evidence state without repeating completed work.

No original research conversation, contact, door, other phone or watch is operated. Storage
reopening is not a physical reboot, Doze or prolonged network recovery campaign. This increment
does not establish global novelty, cognitive independence, scientific truth or general team gains.

## Test History

- Initial focused run exposed a duplicate opportunity reference in the synthesis ancestry path.
  The host already pins that reference separately; removing the redundant basis entry fixed
  the rejection without weakening the kind or hash checks. The next 57 focused tests passed.
- The first broad run completed 844 tests with one timeout in the existing
  `CollaborationConnectionRecoveryTest.dispatchedOfflineMemberReleasesCapacityForIndependentWork`.
  Its 5-second timeout is unchanged; the failure is not excluded from final regression.
- The focused retry reproduced that timeout. Inspection found the fixture could schedule its
  healthy member first and emit the simulated completion before the disconnected member subscribed.
  The fixture now waits for the observed outage while yielding its execution permit. This tests
  actual capacity release regardless of launch order; no production scheduler code or timeout changed.
- Desktop scoped-recall bridge: 15 tests passed in 0.178s; expected negative-access logs were
  assertions. Kotlin source-size and whitespace checks passed.

## Final Results

- Android regression: 844 tests across 66 suites, zero failures, errors or skips. This includes
  19 new team-invention tests (3.167s) and all five connection-recovery tests (1.404s).
- Desktop scoped-recall bridge: 15 tests passed (0.178s); no real provider or running Desktop change.
- Kotlin source-size policy (153600 bytes) and whitespace checks passed.
- Final debug APK and instrumentation APK builds passed in the 5m 35s regression/build invocation.
- Both APKs installed successfully on S26U (SM-S9480). Package inspection confirms Android
  v1.4.46 / 1131. This was an in-place update, not an uninstall or data reset.
- S26U instrumentation: all 10 selected tests passed in 35.006s. This includes the new team
  invention fixture and the nine tests deferred during increment 5. Only local synthetic
  execution was used; no real-model evaluation or original research task was requested.

The selected device classes were `CollaborationTeamInventionDeviceTest`,
`CollaborationInnovationDeviceTest`, `CollaborationLearningDeviceTest`,
`CollaborationEvolutionDeviceTest`, `CollaborationCapabilityDiagnosisDeviceTest`,
`CollaborationScopedRecallDeviceTest`, and
`CollaborationResearchWorkspaceDeviceTest#encryptedVersionsReopenReplayAndDisappearWhenFixtureGroupIsDeleted`.

## Reproduction

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests 'com.galaxyssi.chat.Collaboration*Test' --tests 'com.galaxyssi.chat.AgentTeam*Test' --tests 'com.galaxyssi.chat.AgentSubagent*Test' :app:assembleDebug :app:assembleDebugAndroidTest '-Pgalaxyssi.requireEmbeddedRuntime=false' -x :app:buildNativeMemory --max-workers=1 --console=plain
```

The established local build excludes the unchanged native-memory rebuild. The full repository
`npm run check` is not claimed; earlier increments document unrelated i18n/local-runtime findings.
No timeout, resource gate or acceptance standard is relaxed to obtain a pass.
