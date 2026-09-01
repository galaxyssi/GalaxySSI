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
- Memory evaluation supports 30-day and 90-day horizons and requires provenance evidence.
- Proactive evaluation is finalized only after explicit useful/not-relevant/too-frequent feedback.

Blind campaigns run the same task multiple times against at least two real registered Agent identities. Result review hides identity behind stable aliases, while the encrypted store retains the real resource for auditing. A selected successful trajectory can become a disabled `SKILL.md` candidate; review, signature, and installation remain separate user-controlled steps.

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
- ACP and A2A inbound payloads require an enabled trusted endpoint, granted capabilities, supported protocol version, a valid goal, and the 256 KB payload limit.
- Quality routing starts in shadow recommendation mode. Automatic routing remains separately disabled until evidence thresholds are met.
- Self-evolution candidates compare against a baseline, wait for evidence, require human approval, and roll back hard regressions.

## SM-T575 Evidence

Validated on 2026-09-02 against only device `R52R90282TY` (`SM-T575`):

- Debug APK installed with existing app data preserved; main conversation UI remained unchanged.
- Personal Agent Lab rendered without overlap and discovered three registered real Agent/model identities.
- Two 6-trial blind campaigns completed and entered blind review.
- The dashboard retained 31 real run records, including 19 evidence-verified samples at the final checkpoint.
- A real process force-stop produced `process_death` samples and resumed pending campaign work after launch.
- Deep idle reached `mState=IDLE`; exit restored `mState=ACTIVE`.
- Wi-Fi loss produced no default network; recovery restored Wi-Fi and an active default network.
- A real device reboot completed successfully. `BOOT_COMPLETED` started the SignalASI process before the UI was manually opened.
- Three interrupted samples displayed `reboot + doze + network_loss`; separate samples displayed `doze` and `process_death`.
- All tested Agent outcomes remained failed because the selected connectors returned cancellation, empty output, or timeout. Accordingly, `pass@1`, `pass^k`, and recovery rate correctly remained `0.0%`.
- Battery was 100%, reported temperature was 30.0 C before the fault sequence, and the Android crash buffer remained empty after reboot.

## Automated Verification

Run the focused policy suite:

```powershell
cd apps/android
.\gradlew.bat :app:testDebugUnitTest `
  --tests com.signalasi.chat.AgentEvalOpsPolicyTest `
  --tests com.signalasi.chat.AgentAndroidWorldAdapterTest `
  --tests com.signalasi.chat.AgentOpenSkillAndMemoryTrustTest `
  --no-daemon
```

Build the APK with:

```powershell
.\gradlew.bat :app:assembleDebug --no-daemon
```

The focused suite and debug build must pass. The repository-wide Android unit suite currently has two pre-existing assertions whose expectations conflict with the main-branch policy that delegates live-data decisions to the selected model: `AgentDynamicTeamCompilerTest.complexGoalCompilesComplementaryNamedAgentsIntoOneVerifiedDag` and `GlobalAgentCollaborationTest.host assigns specialist roles from the actual task contract`. The production files for those failures are unchanged by this feature.
