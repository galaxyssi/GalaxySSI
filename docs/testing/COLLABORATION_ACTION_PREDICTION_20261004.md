# Action Prediction Verification 20261004

## Scope

Collaborative-evolution increment 7, based on merged PR #3371. Android version is 1.4.47
(1132). No Desktop or Watch version changes. No UI changes, real provider calls, original
research reruns, contacts or door actions. Only S26U is authorized for device testing.

## Acceptance Matrix

| Requirement | Evidence to verify |
| --- | --- |
| State/assumption distinction | Observed state requires original read evidence; assumed/unknown labels preserved |
| Alternatives before action | Common events for every action, explicit defer option, valid probability ranges |
| Program-owned arithmetic | Expected utility and binary Brier errors recomputed from exact records and original fields |
| Real dispatch | Live and next-round work carries immutable goal/criterion/run/turn/member/work/action binding |
| No new blocking loop | Ordinary no-I/O path; unrelated live tasks continue; no fixed retry or research step count |
| Recovery | Claims, original evidence, failure scores and correction lineage reopen without replaying execution |
| Missingness | Missing fields, failed tools and absent checks are unobserved, not negative event labels |
| Temporal/identity guards | Reject pre-forecast evidence, wrong source/run/executor, changed report IDs and stale new admission |
| No inflated confidence | Unchosen actions stay untested; duplicate forecast snapshots cannot inflate aggregates |
| Correction | Changed assumptions name exact previous model and observed feedback; new future test still required |
| Isolation | Cross-group denial and original evidence full-read checks remain enforced |

The synthetic unit fixture actually parses a JSON input once and reuses the parsed values;
the original result is recorded in the production evidence ledger before host scoring. Another
fixture deliberately predicts the wrong sort direction. These are developer-authored algorithms
and forecasts, not autonomous model inventions or calibrated real-world predictions.

The device fixture creates and cleans an isolated group, admits bound work, executes a local sort,
preserves a wrong 0.8-confidence prediction and its 0.64 Brier error, then saves a model correction
and reopens encrypted records and claims. It does not run a model or external side effect.

## Test History

- Initial focused run: 16 tests, one test-fixture failure. Cross-run access correctly returned no
  evidence, but the negative test tried to force-read it and threw a null pointer. The fixture now
  asserts publication rejection without attempting an unauthorized read. Production isolation
  and validation were not relaxed.
- Added live-dispatch, stale-input/history and wrapped JSON/null-versus-missing coverage.
- First broad run: 863 tests, one new test-fixture failure. Publication receipts intentionally
  compact detailed checks into a count; the test incorrectly treated that receipt as the full
  original. It now reads the exact saved workspace revision before asserting the null outcome.
  Production report evaluation and compact paging were unchanged. Added a wholly-unobserved
  aggregate check to prevent missing measurements becoming a fabricated perfect score.
- Desktop scoped-recall bridge: 15 tests passed in 0.210 seconds. Expected access-denial tracebacks
  are negative test assertions, not test failures.

## Final Results

- Android regression: 864 tests across 67 suites, zero failures, errors or skips. The 20 new
  action-prediction tests passed in 0.965 seconds.
- Desktop scoped-recall bridge: all 15 tests passed (0.210 seconds).
- Kotlin source-size (153600-byte policy) and whitespace checks passed.
- Final debug APK and instrumentation APK builds passed in the 5m 24s regression/build invocation.
- S26U cover installation succeeded without uninstall/data reset; package inspection confirms
  versionName 1.4.47 and versionCode 1132.
- S26U instrumentation: 5 selected tests passed in 3.601 seconds: action prediction, team invention,
  innovation, scoped recall and encrypted workspace reopen/replay/fixture deletion.
- Only isolated synthetic fixture groups and local computation were used. No original research,
  model evaluation, contact, door, other device or running Desktop instance was operated.

## Reproduction

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests 'com.galaxyssi.chat.Collaboration*Test' --tests 'com.galaxyssi.chat.AgentTeam*Test' --tests 'com.galaxyssi.chat.AgentSubagent*Test' :app:assembleDebug :app:assembleDebugAndroidTest '-Pgalaxyssi.requireEmbeddedRuntime=false' -x :app:buildNativeMemory --max-workers=1 --console=plain
```

The established local workflow excludes the unchanged native-memory rebuild. Full repository
`npm run check` is not claimed; previously documented unrelated findings are not part of this
increment. Device storage reopening is not physical reboot, Doze or long-duration outage testing.
No synthetic score proves general calibration, causal validity or improved real-model choices.
