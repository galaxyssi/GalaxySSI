# Self-Improvement Research Verification - 2026-10-05

## Scope

- Android v1.4.51 / versionCode 1136, based on merged capability-retention PR #3375.
- No UI changes, real model calls, Desktop restart, original research, contacts or door actions.
- S26U (SM-S9480) is the only authorized device. Replacement installation preserves app data.
- Evidence is explicitly synthetic; it must not be reported as autonomous model improvement.

## Local Results

The initial 12 focused tests passed. After adding stale-bottleneck, malformed-binding
and multiple-candidate checks, the frozen-source regression passed **948 tests across
73 suites**, with zero failures, errors or skips. The new self-research suite contains
**15 passing tests** (0.799 seconds in this run).

Coverage includes diagnosis/agenda/opportunity binding, deferred-learning rejection,
independent read coverage, retained capability adoption, multiple selected candidates,
negative regression preservation, next-cycle linkage, observed waits, cross-cycle and
cross-group denial, old action pinning, renamed-action deduplication, malformed work,
changed bottleneck rejection, immutable innovation lineage, atomic mixed-batch failure,
actual goal/live DAG admission, terminal outcome idempotence and ordinary-task no-I/O.

The existing Desktop scoped-recall bridge passed **15 tests** in 0.266 seconds. The
three unavailable-task tracebacks are expected denial fixtures, not failed tests.
Kotlin source-size policy (153600 bytes) and whitespace checks passed.

## Device Results

The frozen-source main and instrumentation APK build passed in **7m 48s** (104 tasks,
19 executed). Both APKs replacement-installed successfully on S26U, preserving data.
Package inspection confirmed **v1.4.51 / 1136**.

All **9 local device tests passed** in **21.391 seconds**. The new self-research test
registers an observed synthetic bottleneck and learning selection, runs through the
controlled-result and independent-retention contracts, records protected adoption,
opens a next cycle and admits actual goal-DAG work. Reopening the encrypted workspace
and interrupted team checkpoint preserves the exact review, result, action and worker
context; renaming the action cannot cause duplicate execution. Dedicated fixture
groups and checkpoint databases are removed afterward.

Companion tests cover capability retention/rollback, workflow, executable tools,
action prediction, team invention, innovation, scoped recall and immutable encrypted
workspace replay/delete. No real provider or original research task is invoked.

## Reproduction

Run from `apps/android` with the configured Android SDK and local Python test runtime:

```powershell
./gradlew.bat :app:testDebugUnitTest `
  --tests 'com.galaxyssi.chat.Collaboration*Test' `
  --tests 'com.galaxyssi.chat.AgentTeam*Test' `
  --tests 'com.galaxyssi.chat.AgentSubagent*Test' `
  --tests 'com.galaxyssi.chat.AgentOnDeviceRuntime*Test' `
  --tests 'com.galaxyssi.chat.AgentSkillRuntimeTest' `
  :app:assembleDebug :app:assembleDebugAndroidTest `
  '-Pgalaxyssi.requireEmbeddedRuntime=false' -x :app:buildNativeMemory --max-workers=1 --console=plain
```

Unchanged native-memory compilation is excluded and the development embedded-runtime
requirement is explicitly disabled. No large models are downloaded. This is not a
release build or renewed validation of unchanged native components.

## Not Established

No real-model autonomous research, long-duration self-improvement, scientific novelty,
general intelligence, equal-budget team superiority, global deployment safety or
long-term retention is claimed. These fixtures also do not substitute for physical
reboot, prolonged Doze or live-provider network-failure campaigns. See the
[eleven-increment acceptance audit](COLLABORATIVE_EVOLUTION_ACCEPTANCE_SCOPE.md).
