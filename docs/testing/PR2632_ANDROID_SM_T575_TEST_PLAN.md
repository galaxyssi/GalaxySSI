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
collects every failure before reporting. It has a hard device guard for Samsung SM-T575
(`Build.MODEL=SM-T575`, `Build.DEVICE=gtactive3`) and refuses to run elsewhere.

Every scenario is persisted as one real App conversation after execution. The result is
exactly 1,000 visible conversations and 2,000 visible user/assistant messages:

- Titles use `真机验收 0001 · <functional area>` through `真机验收 1000 · <functional area>`.
- The user message records the module, verification target, and SM-T575 device boundary.
- The assistant message records `PASS` or `FAIL` and the exact matrix case identifier.
- A failed scenario remains visible before the test reports failure.
- Previous conversations with the test prefix are batch-deleted before replacement; unrelated conversations are untouched.
- Test conversations are private from their first persisted message, so they remain visible without entering core memory, global cognition, or Obsidian projection.
- A JSON receipt is written to `files/acceptance-reports/sm-t575-visible-architecture-matrix.json`.

Repeating one assertion does not count as coverage; each group varies inputs, privacy
state, lifecycle state, or policy branch. Only eight core-memory cases perform a real
cross-session A-write/B-read flow; the remaining cases cover the broader architecture.

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
| Obsidian notes, reading records, Skills, plans, insights, projection privacy | 40 |
| **Total** | **1,000** |

The 40 Obsidian cases are displayed as eight conversations each for knowledge notes,
reading records, Skills, plans, and insights. They validate projection eligibility and
privacy policy; they do not claim a physical SAF Vault write unless a user-selected Vault
is separately configured.

## Commands

Run the focused JVM regressions, then build the App and instrumentation APK:

```powershell
cd apps/android
.\gradlew.bat :app:testDebugUnitTest --tests "com.galaxyssi.chat.AndroidCoreMemoryExtractorTest" --tests "com.galaxyssi.chat.AgentModelPlanningPromptGlobalContextTest" --tests "com.galaxyssi.chat.GlobalMemoryEvolutionTest" --tests "com.galaxyssi.chat.GlobalAgentKnowledgeGraphTest" --tests "com.galaxyssi.chat.GlobalProactiveDiscoveryTest"
.\gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest
```

Install both APKs and run only on SM-T575:

```powershell
adb -s R52R90282TY install -r -t app\build\outputs\apk\debug\app-debug.apk
adb -s R52R90282TY install -r -t app\build\outputs\apk\androidTest\debug\app-debug-androidTest.apk
adb -s R52R90282TY shell am instrument -w -r -e class com.galaxyssi.chat.Pr2632AndroidCognitionDeviceTest com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
adb -s R52R90282TY shell am instrument -w -r -e class com.galaxyssi.chat.Pr2632AndroidArchitectureMatrixTest com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

Read the durable receipt without touching another connected device:

```powershell
adb -s R52R90282TY exec-out run-as com.galaxyssi.chat cat files/acceptance-reports/sm-t575-visible-architecture-matrix.json
```

After the matrix completes, launch GalaxySSI and open the conversation center. The first
page should contain `真机验收 1000`, `真机验收 0999`, and earlier PASS/FAIL records; normal
pagination continues through all 1,000 conversations.
