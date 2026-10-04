# Workflow Learning Validation, 2026-10-05

## Scope

Android 1.4.49 / 1134, capability 9, based on merged PR #3373. No UI changes, real-model calls,
development subagents, original protein research, contact/door actions or Desktop restart.
Only S26U (SM-S9480) is authorized for local synthetic device fixtures; app data is preserved.

The new method graph enters both existing live and next-round schedulers. Test coverage targets
immutable versions, full graph admission, identity/dependency/reviewer protection, exact inputs,
replay, partial completion, negative outcomes and registered same-dataset comparisons.

## Build And Test Commands

Use the existing local SDK and Python environment, then:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests 'com.galaxyssi.chat.Collaboration*Test' --tests 'com.galaxyssi.chat.AgentTeam*Test' --tests 'com.galaxyssi.chat.AgentSubagent*Test' --tests 'com.galaxyssi.chat.AgentOnDeviceRuntime*Test' --tests 'com.galaxyssi.chat.AgentSkillRuntimeTest' :app:assembleDebug :app:assembleDebugAndroidTest '-Pgalaxyssi.requireEmbeddedRuntime=false' -x :app:buildNativeMemory --max-workers=1 --console=plain
```

Embedded runtime validation is opted out and unchanged native-memory compilation is excluded,
as in the previous increment. This does not rebuild native memory libraries or download models.

## Results

- Initial restricted build could not access the Gradle file-hash lock in the actual worktree;
  rerun with project build-cache access. No source failure was reported by that attempt.
- First focused run: 14 tests, one fixture failure. The new comparison fixture omitted the
  existing innovation opportunity parent relation, which was correctly rejected. The fixture
  now preserves that relation; production validation was not relaxed.
- First broad JVM regression: **915 tests across 71 suites**, zero failures/errors/skips.
- Initial workflow suite: **16 tests**, all passed in **0.861 seconds**. Includes 1000 planned
  steps, both scheduler paths, partial-completion replay, exact dataset/version comparison,
  actual local parse-count reduction and a faster-but-incorrect negative control.
- Desktop scoped recall: **15 tests passed in 0.167 seconds**. The three unavailable-task
  logs are expected denial fixtures, not failing tests.
- Kotlin source-size policy (153600-byte default) and whitespace validation passed.
- Initial main/instrumentation build passed in 5 minutes 36 seconds; S26U cover-install confirmed
  1.4.49 / 1134. First seven device fixtures: six passed, workflow encrypted-context replay failed.
  The existing member-context allowlist omitted the new workflow key and the prior prediction key.
  Added those two exact internal keys only, plus a negative allowlist regression; no broad prefix
  permission expansion.
- Final frozen-source build passed in **7 minutes 31 seconds** (104 tasks; 17 executed).
- Final JVM regression: **916 tests across 71 suites**, zero failures/errors/skips. The workflow
  suite has **17 passing tests** (0.187 seconds in this run).
- Final S26U cover-install succeeded, retaining app data. **Seven device fixtures passed in
  4.52 seconds**, including exact workflow/prediction member bindings and request-context
  claims/outcomes reopened from the encrypted execution store. Only disposable fixture data was
  removed. No real providers or original research tasks were executed by these tests.

## Limits

Local fixture computations are not model quality tests. Workflow result status and wall time
are not scientific validation or isolated tool/model latency. Original measurement reports bind
versions and datasets but still require trustworthy harnesses and independent review. A record
reopen is not a physical phone reboot/Doze/network recovery test. Existing recovery regressions
remain relevant, but no new long-duration real-model acceptance is claimed here.
