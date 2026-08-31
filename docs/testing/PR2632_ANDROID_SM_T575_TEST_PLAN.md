# PR #2632 Android Test Plan (SM-T575)

## Scope

This plan validates the complete Android cognition architecture affected by PR #2632.
Device execution is locked to Samsung SM-T575 with ADB serial `R52R90282TY`. Do not
use Gradle's connected-device task when other phones are attached; build both APKs,
then install and invoke instrumentation with `adb -s R52R90282TY`.

## Automated functional cases

| ID | Case | Expected evidence |
| --- | --- | --- |
| P2632-MEM-01 | Extract an explicit name, device, project, and preference | Deterministic candidates use the correct core keys |
| P2632-MEM-02 | Submit text containing an API key or access token | No immediate core memory candidate is created |
| P2632-MEM-03 | Persist a core memory and recreate the coordinator | The compiled prompt contains the encrypted stored value |
| P2632-MEM-04 | Update an existing core state | The new value is active and the old value is superseded |
| P2632-MEM-05 | Compile a prompt with no core state | No empty memory header is injected |
| P2632-MEM-06 | Start a fresh session after encrypted core-memory capture | Planner and Agent transport both receive the compiled memory |
| P2632-WORK-01 | Register delayed scheduled cognition | Unique WorkManager work remains durably enqueued |
| P2632-WORK-02 | Register repeated event work | ExistingWorkPolicy.KEEP prevents duplicate active work |
| P2632-WORK-03 | Run event cognition | It processes a bounded event batch without research or projection |
| P2632-WORK-04 | Run explicit cognition | A foreground worker is used and the run resumes from durable state |
| P2632-WORK-05 | Restart the app process | Startup restores immediate and scheduled cognition work |
| P2632-SCHED-01 | Pending work exists | The next exploration delay is 10 minutes |
| P2632-SCHED-02 | Only pending insights exist | The next exploration delay is 30 minutes |
| P2632-SCHED-03 | The system is idle | The next exploration delay is 4 hours |
| P2632-OBS-01 | Save and recreate Obsidian settings | Settings round-trip and plaintext is absent from preferences |
| P2632-OBS-02 | Project ordinary Agent knowledge | A managed Markdown note is eligible for projection |
| P2632-OBS-03 | Project credentials or identity material | Sensitive content is rejected or redacted |
| P2632-OBS-04 | Edit a generated note | A candidate update is created instead of overwriting formal memory |
| P2632-OBS-05 | Reject a candidate update | The candidate is rejected and formal memory remains unchanged |
| P2632-PRIV-01 | Inspect person-to-person contact chats | They are absent from Agent transcript projection inputs |
| P2632-PRIV-02 | Inspect Agent chats in private or paused mode | They are excluded from projection and Agent transport |

## 1,000-scenario device matrix

`Pr2632AndroidArchitectureMatrixTest` runs production Android code on the device and
collects every failure before reporting. Repeating one assertion does not count as
coverage; each group varies inputs, privacy state, lifecycle state, or policy branch.

| Functional area | Scenarios |
| --- | ---: |
| Core memory: identity, preference, device, project, secret rejection | 100 |
| Current context, Prompt Compiler, private/paused context boundaries | 100 |
| Event/scheduled/explicit/projection work plans and dynamic delay | 80 |
| Memory Evolution: merge, review, private blocking, idempotency | 160 |
| Topic/project and entity Graph Memory, relation integrity, idempotency | 120 |
| Knowledge indexing, ranking, excerpts, query snapshots | 100 |
| Skill commands, validation, automatic matching, negative examples | 100 |
| Knowledge-gap detection and quick/continuous research planning | 80 |
| Proactive risk/opportunity discovery, selection, task creation | 80 |
| Memory Critic: expiry, low-confidence reuse, Skill candidate, completed goal | 40 |
| Obsidian knowledge acceptance, redaction, metadata rejection | 40 |
| **Total** | **1,000** |

## Commands

Run the focused JVM regressions, then build the App and instrumentation APK:

```powershell
cd apps/android
.\gradlew.bat :app:testDebugUnitTest --tests "com.signalasi.chat.AndroidCoreMemoryExtractorTest" --tests "com.signalasi.chat.AgentModelPlanningPromptGlobalContextTest" --tests "com.signalasi.chat.GlobalMemoryEvolutionTest" --tests "com.signalasi.chat.GlobalAgentKnowledgeGraphTest" --tests "com.signalasi.chat.GlobalProactiveDiscoveryTest"
.\gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest
```

Install both APKs and run only on SM-T575:

```powershell
adb -s R52R90282TY install -r -t app\build\outputs\apk\debug\app-debug.apk
adb -s R52R90282TY install -r -t app\build\outputs\apk\androidTest\debug\app-debug-androidTest.apk
adb -s R52R90282TY shell am instrument -w -r -e class com.signalasi.chat.Pr2632AndroidCognitionDeviceTest com.signalasi.chat.test/androidx.test.runner.AndroidJUnitRunner
adb -s R52R90282TY shell am instrument -w -r -e class com.signalasi.chat.Pr2632AndroidArchitectureMatrixTest com.signalasi.chat.test/androidx.test.runner.AndroidJUnitRunner
```
