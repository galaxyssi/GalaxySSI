# Capability Retention Verification - 2026-10-05

## Scope

- Android v1.4.50, versionCode 1135; base is merged workflow-learning PR #3374.
- No UI changes, Desktop runtime restart, real model calls or original research execution.
- Local synthetic evidence only. S26U (SM-S9480) is the only device used.
- Fixture workspaces/groups and isolated checkpoint databases are removed after testing.
- Installed application data and configuration are preserved with replacement installation.

## Local Results

The final JVM regression run passed **933 tests across 72 suites**, with zero failures, errors or
skips. This includes **17 retention tests** and the existing collaboration, team/subagent,
on-device runtime and Skill-runtime suites.

Coverage includes fixed measured anchors, all-case preservation, dataset identity, environment
changes, repetition/tolerance weakening, missing trials, cumulative drift, original feasibility
thresholds, bank extension, active-baseline promotion, stale CAS, wrong-author changes, failed
storage commits, same-channel rollback, repeated rollback, stale lineage, pinned procedure and
workflow bindings, cross-group denial and compact directory/publication receipts.

The executable-tool selection adapter retains the existing source, parameter schema and tested
runtime guard. It is a local adapter test, not a real model-authored tool campaign.

The existing Desktop scoped-recall suite passed **15 tests**. Its three negative-case tracebacks
are expected assertions for unavailable task access, not failed tests.

Kotlin source-size policy (153600 bytes) and staged whitespace checks passed.

## Device Results

The initial S26U run passed all **8 local instrumentation tests** in 14.355 seconds. After the
final build with compact receipts and preserved feasibility thresholds was installed, all eight
passed again in **17.586 seconds**. The final APK build completed successfully in 6m 51s.

The new retention test creates independently reviewed synthetic versions, rejects a degraded
candidate, promotes then rolls back a selection, reopens the encrypted workspace and restores an
interrupted fixture checkpoint. It verifies the old task keeps its exact implementation while new
work must use the current channel revision. The newest protection bank and failed evidence survive.

The companion tests cover workflow, executable tool, prediction, team invention, innovation,
scoped recall and immutable workspace recovery. They do not manipulate contacts, door controls,
the protein-research task or other devices.

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

Unchanged native-memory compilation is excluded; the development embedded-runtime requirement
is disabled explicitly. No large models are downloaded. These flags do not constitute a release
build or revalidation of unchanged native components.

## Findings During Verification

The first fixture run attempted a same-round read from another node. Existing isolation correctly
rejected it; the fixture timing was corrected, not the production isolation rule. One subsequent
existing transfer test detected changed error wording; validation order now preserves the prior
dataset/domain diagnostic. Review also added repeated-rollback warnings, stale-lineage rejection,
immutable feasibility thresholds and compact bank receipts before final verification.

## Not Established

These results do not prove sustained real-model improvement, long-term forgetting rates, full
production coverage, autonomous scientific innovation or superiority over a single agent. Agent
selection quality, original measurement-harness correctness, long-duration workloads and held-out
real-model evaluation remain separate acceptance work. Rollback does not undo external effects,
globally install Skills, deploy app code or grant permissions.
