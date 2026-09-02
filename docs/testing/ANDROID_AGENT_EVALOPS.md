# Android Agent EvalOps and Evolution Lab

This document defines the Android-only acceptance boundary for real Agent evaluation, trajectory learning, memory trust, proactive cognition, protocol adapters, AndroidWorld-compatible verification, and shadow release.

## Product Entry

The feature does not change the main conversation UI. Open:

`My Agent > General > Developer options > Personal Agent Lab`

The page is intended for advanced users. It compares registered, currently routable Agent and model identities without renaming or merging them.

## Real Evaluation Contract

Every captured run stores an encrypted start snapshot, outcome contract, execution resource identity, duration, reported cost, battery delta, energy delta, peak thermal status, memory delta, evidence kinds, verdict, and failure reasons.

- `pass@1` is the empirical first-trial success rate for repeated scenario batches.
- `pass^k` passes only when every trial in a repeated batch passes. It is not `pass@k`.
- Recovery counts as successful only when a run has a `RUN_RECOVERED` event and the final recorded run status is completed.
- Doze, reboot, network loss, and process death are retained as an observed condition set. Multiple faults in one run remain visible.
- Failed, cancelled, timed-out, or empty Agent results stay failed. The UI must never synthesize a passing result.
- Memory evaluation supports real 30-day and 90-day horizons. The selected memory timestamps, query digest, answer run, and provenance must all match before a sample is verified.
- Proactive evaluation is finalized only after explicit useful/not-relevant/too-frequent feedback.
- Continuous evaluation may enqueue a bounded real Agent Lab campaign only after a completed, evidence-bearing, non-private run, with at least two currently available Agents and a per-scenario 24-hour cooldown.

Blind campaigns run the same task multiple times against at least two real registered Agent identities. Only online, idle, or busy registered endpoints are eligible. Result review hides provider, connector, and Agent identity behind stable aliases, while the encrypted store retains the real resource for auditing. A selected successful trajectory becomes a disabled proposal in the Skill review queue; review, local signature, installation, and rollback remain separate user-controlled steps.

Trajectory learning keeps a tool step only when it succeeds in at least 60% of the source runs. Every successful source request becomes a distinct regression case, so one passing example cannot silently replace the rest of the learned behavior.

## Reliability Harness

The process session marker and Android boot count distinguish process death from reboot. Startup and `BOOT_COMPLETED` recovery perform the following actions:

1. Mark interrupted real runs with the detected condition and failure evidence.
2. Pause interrupted durable Agent work.
3. Reset running Agent Lab trials to pending while retaining `previous_run_id`.
4. Start replacement runs with recovery lineage and a `RUN_RECOVERED` event.

Default-network callbacks record validated network loss and recovery. `ACTION_DEVICE_IDLE_MODE_CHANGED` records Doze entry and exit. Fault events are attached only to active captured runs.

## AndroidWorld Adapter Boundary

The adapter imports versioned JSON tasks and evaluates four programmatic verifier types against real Android state:

- foreground package
- visible text from the production screen-perception state
- app-scoped file existence or content
- Android system setting value

Matching is explicit by normalized instruction or an `[androidworld:<task_id>]` tag. Files are canonicalized and restricted to SignalASI app storage. This is an AndroidWorld-compatible adapter, not a claim that all upstream AndroidWorld tasks or its complete execution harness are bundled.

## Trust and Protocol Boundaries

- Memory details expose source, evidence, confidence, current/history state, last verification time, usage records, privacy, conflicts, correction, and deprecation.
- Private and superseded memories are excluded from prompt recall and Obsidian projection. Obsidian remains an optional projection, not the source of truth.
- MCP uses the existing permission runtime. Open Agent Skills use review, signature, sandbox, and rollback controls.
- ACP and A2A inbound payloads require JSON-RPC 2.0, the exact supported method, required request/session/message identifiers, an enabled trusted endpoint, a constant-time endpoint fingerprint match, granted capabilities, a valid goal, and the 256 KB payload limit. Host-side task analysis adds inferred capabilities so a sender cannot bypass permission checks by under-declaring them.
- Quality routing starts in shadow recommendation mode. Automatic routing remains separately disabled until evidence thresholds are met.
- High-value unresolved knowledge gaps can enter bounded background research only when Personal ASI and autonomous research are enabled. Private gaps are never queued, and every decision is auditable.
- Self-evolution candidates use `BUILT -> DEVICE_SHADOW -> CANARY -> WAITING_APPROVAL -> RELEASED`. Human approval is unavailable until shadow and canary evidence pass; hard regressions and explicit cancellation roll back the candidate.

## Feature Acceptance Matrix

The numbered Android acceptance cases are intentionally independent and run against production classes on the target device:

| Feature | Device acceptance |
| --- | --- |
| 4 | Encrypted 90-day memory provenance is attached only to the matching query/run; AndroidWorld verifies an actually installed package. |
| 5 | Trajectory compilation retains stable majority steps and generates one regression case per successful request. |
| 6 | Open `SKILL.md` is reviewed, signed with the local device identity before installation, and can roll back to the previous enabled version. |
| 7 | Private and superseded memories are excluded from recall; current memory remains correctable and deprecatable. |
| 8 | Automatic quality routing requires the configured count of verified evidence samples before switching. |
| 9 | Partial or missing evidence never counts as pass; `pass^k` remains false when any repeated trial fails. |
| 10 | Attention budgeting separates high-value immediate insight from low-value noise. |
| 11 | Only authorized, high-value, non-private knowledge gaps can queue background research. |
| 12 | ACP/A2A reject a wrong method, protocol version, endpoint fingerprint, or undeclared capability boundary. |
| 13 | Interrupted Agent Lab trials retain recovery lineage and blind review redacts provider identity. |
| 14 | Shadow release must pass device shadow and canary before approval; a hard regression rolls back. |

## SM-T575 Evidence

Validated on 2026-09-02 against only device `R52R90282TY` (`SM-T575`, Android 13, `1200 x 1920`):

- Production debug APK and test APK installed with existing app data preserved. The production APK SHA-256 was `3C4D3D540E87FFD9A66BB888F2DFA3B473925D43466921E6290A35DB305950F5`; the test APK SHA-256 was `F14615FAE47DCBC1C3AF9B71D2FACDE31D7E4400F949055EB282E03A350F1503`.
- Installed package was `0.5.96` (`versionCode=832`). Cold launch completed in 937 ms and resumed `MainActivity`.
- Main conversation UI remained unchanged and nonblank. Personal Agent Lab rendered without overlap or clipped controls and discovered two currently available real Agent identities.
- Device instrumentation executed one acceptance case for every feature 4-14 and completed `OK (11 tests)` in 0.388 seconds. Each test asserts `Build.MODEL == SM-T575` before running.
- Eval results, memory trust, knowledge gaps, attention decisions, ACP boundary details, Skill export, AndroidWorld rows, and shadow release all opened or rendered correctly. Existing empty states remained explicit.
- Two 6-trial blind campaigns completed and entered blind review.
- The dashboard retained 31 real run records, including 19 evidence-verified samples at the final checkpoint.
- A real process force-stop produced `process_death` samples and resumed pending campaign work after launch.
- Deep idle reached `mState=IDLE`; exit restored `mState=ACTIVE`.
- Wi-Fi loss produced no default network; recovery restored Wi-Fi and an active default network.
- A real device reboot completed successfully. `BOOT_COMPLETED` started the SignalASI process before the UI was manually opened.
- Three interrupted samples displayed `reboot + doze + network_loss`; separate samples displayed `doze` and `process_death`.
- All tested Agent outcomes remained failed because the selected connectors returned cancellation, empty output, or timeout. Accordingly, `pass@1`, `pass^k`, and recovery rate correctly remained `0.0%`.
- Battery was 100%, reported temperature was 29.1 C during the final run, the Android crash buffer remained empty, and `dumpsys activity lastanr` reported no ANR since boot.

## Automated Verification

Run the focused policy suite:

```powershell
cd apps/android
.\gradlew.bat :app:testDebugUnitTest `
  --tests com.signalasi.chat.AgentEvalOpsPolicyTest `
  --tests com.signalasi.chat.AgentAndroidWorldAdapterTest `
  --tests com.signalasi.chat.AgentConversationSkillLifecycleTest `
  --tests com.signalasi.chat.AgentLearningEngineTest `
  --tests com.signalasi.chat.AgentOpenSkillAndMemoryTrustTest `
  --tests com.signalasi.chat.AgentSelfEvolutionTest `
  --no-daemon
```

Build the APK with:

```powershell
.\gradlew.bat :app:assembleDebug --no-daemon
.\gradlew.bat :app:assembleDebugAndroidTest --no-daemon
```

Install and execute the device suite only on the designated device:

```powershell
adb -s R52R90282TY install -r -t app\build\outputs\apk\debug\app-debug.apk
adb -s R52R90282TY install -r -t app\build\outputs\apk\androidTest\debug\app-debug-androidTest.apk
adb -s R52R90282TY shell am instrument -w -r `
  -e class com.signalasi.chat.Pr2670AndroidAgentLabAcceptanceTest `
  com.signalasi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The focused suite, both APK builds, and all 11 device cases must pass. The repository-wide Android unit suite currently has two pre-existing assertions whose expectations conflict with the main-branch policy that delegates live-data decisions to the selected model: `AgentDynamicTeamCompilerTest.complexGoalCompilesComplementaryNamedAgentsIntoOneVerifiedDag` and `GlobalAgentCollaborationTest.host assigns specialist roles from the actual task contract`. The production files for those failures are unchanged by this feature.
