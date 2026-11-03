# Executable Tool Validation, 2026-10-05

## Scope

Android `1.4.48` / `1133`, increment 8 of collaborative evolution. Based on merged PR #3372.
No real models, original protein research, contacts, door actions, other devices or Desktop restart.
No development subagents. No UI changes or destructive app-data reset.

The implementation saves immutable Python source/input contracts, preregistered tests and independently
reviewed releases. Runtime execution reuses the existing native tool and authority, not a new executor.
Correctness checks cover real tiny local Python programs and synthetic failure/security conditions.
Device fixtures validate encrypted persistence and exact dispatch authorization using synthetic outputs;
they do not claim to execute Python inside the phone Linux guest.

## Commands

```powershell
$env:ANDROID_HOME='C:\Users\agent\AppData\Local\Android\Sdk'
$env:GALAXYSSI_TEST_PYTHON='C:\Users\agent\AppData\Local\Programs\Python\Python312\python.exe'
.\gradlew.bat :app:testDebugUnitTest --tests 'com.galaxyssi.chat.Collaboration*Test' --tests 'com.galaxyssi.chat.AgentTeam*Test' --tests 'com.galaxyssi.chat.AgentSubagent*Test' --tests 'com.galaxyssi.chat.AgentOnDeviceRuntime*Test' --tests 'com.galaxyssi.chat.AgentSkillRuntimeTest' :app:assembleDebug :app:assembleDebugAndroidTest '-Pgalaxyssi.requireEmbeddedRuntime=false' -x :app:buildNativeMemory --max-workers=1 --console=plain
```

The existing embedded-runtime opt-out and unchanged native-memory-build exclusion were retained.
This is not a fresh build of native-memory libraries or a download/install of model/runtime packs.

Desktop shared-contract regression: `python -m unittest test_collaboration_recall_bridge -q`.
The three expected unavailable-task error logs are negative tests, not failures.

## Results

- Initial 23 focused tests passed, including two real local Python process tests (1.596 seconds).
- First expanded run: 898 tests, one assertion failure. Replayed JSON objects had identical content but
  different field serialization order; corrected the test to compare canonical content digests.
- Second expanded run: 899 tests, one failure from an incremental build snapshot taken before the final
  pre-execution environment guard. The newly added test required `environment_matches`; a frozen-source
  rebuild was required. Do not use that stale result as final verification.
- Desktop scoped recall: 15 tests passed in 0.176 seconds.
- Final frozen-source regression: **899 tests across 70 suites**, zero failures/errors/skips.
  The new tool suites contain **27 tests**: 24 contract tests in 0.091 seconds and three real local
  Python process tests in 2.624 seconds.
- Main and instrumentation APK builds passed in **7 minutes 40 seconds** (104 tasks; 19 executed).
- Kotlin source-size policy (153600-byte default) and whitespace validation passed.
- S26U (`SM-S9480`) cover-install succeeded; package manager confirmed `1.4.48` / `1133`.
- **Six device tests passed in 3.686 seconds**: executable-tool persistence/dispatch, action prediction,
  team invention, innovation, scoped recall and encrypted workspace reopen/replay/delete.
  Only disposable fixture groups were created and cleaned up. Existing user records were not cleared.

## Covered Behaviors

- Define/test/review/reopen/reuse exact source in a later authorized task.
- Fresh Python namespaces, JSON-safe base64 transport and no expected answers in tool inputs.
- Actual incorrect code, exceptions, missing/duplicate outputs, explicit null and nonzero/truncated output.
- Prevent reuse before source execution when Python version/implementation/machine changes.
- Input-schema validation, source/argument override rejection, wrong version/hash/harness rejection.
- Independent release review, full original evidence read, no unresolved blockers, source/time/dispatch binding.
- Cross-group and blind-branch denial, missing dispatch/revoked group denial, persistence and replay.
- Ordinary runtime calls do not read collaboration workspace records.

## Not Proven

No real-model autonomous tool invention, meaningful novelty, general tool safety/correctness or quality
improvement is asserted. Phone Linux execution, cross-provider delegation and long-lived real workloads
remain empirical validation work. Global Skill installation and additional language adapters are not added.
