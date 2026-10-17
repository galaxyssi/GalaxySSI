# Goal-oriented execution acceptance

## Contract

The existing execution pipeline is extended rather than replaced:

1. Use a local shortcut only when the full request is understood. Missing timer
   parameters must not fall back to opening the Clock page.
2. Route unresolved executable intent to the selected provider and the existing
   structured phone-tool plan. A prose answer is not an executed operation.
3. Keep the latest pending operation and completion contract in a conversation-
   scoped Run Kernel checkpoint. Short follow-ups must not control an unrelated
   recurring schedule or another conversation.
4. Separate dispatch acceptance from an observed business outcome. Structured
   postconditions bind observations to a subject and an optional preceding
   mutation. Newer observations supersede older successful observations.
5. Reuse the effect journal, inspect before retrying, and retain the operation
   across the accessibility permission handoff. Only one window can claim that
   continuation.
6. Constrain final replies with host-owned tool evidence. An unobserved result is
   not reported as complete.

## Timer adapter

The native path requests `ACTION_SET_TIMER` with length, a unique label, and
`EXTRA_SKIP_UI=true`. Samsung Clock observations must match that label, the
requested duration, and the expected controls. Running requires decreasing
remaining time; paused requires a stable remaining time. Pause, resume and
cancel use an observed node, not guessed coordinates. Replacement validates the
new duration before removing the previous timer.

The adapter is intentionally conservative on other Clock implementations. They
use model-directed inspection/recovery instead of inheriting Samsung-specific
claims. An inaccessible UI, missing timer, or uncertain external effect remains
unverified; none permits blind timer recreation.

## Automated coverage

- `AgentDeviceIntentTest`: Chinese/English durations, typos delegated to the
  model, incomplete inputs, short continuations and recurrence separation.
- `AgentTimerObservationTest`: identity, duration, decreasing/stable samples,
  missing observations and impossible changes.
- `AgentObservedOutcomeTest`: subject-bound receipts, fresh observations,
  mutation ordering, persisted postconditions and evidence-constrained replies.
- Existing system-tool, schedule and completion-policy regressions.
- `AgentGoalExecutionDeviceTest`: persisted checkpoints, single continuation
  claim and rejection before any invalid external action.

Live tests are opt-in and use dedicated test conversations and labelled timers:

```text
live_timer=true
  Chinese one-minute request -> start -> repeat without duplication
  -> replace with two minutes -> pause -> resume -> cancel

live_intent_model=true
  User typo -> configured model -> executable phone intent
  -> observed three-minute timer -> fixture cleanup
```

Do not run the live tests on multiple devices implicitly. The current requested
acceptance target is S20U only. The model test uses the App's configuration and
does not hardcode a provider or model.

## Evidence boundaries

Synthetic file and message receipts test the generic postcondition matcher;
they do not establish end-to-end message delivery. Exported workspace artifacts
now carry a host-owned inspection result bound to the exported SHA-256. PDF
inspection opens the document and checks its first page; image inspection
decodes a sampled first frame; Office inspection validates the package and main
document XML. These scopes do not establish semantic correctness, full rendering
of every page/frame, or compatibility with every external application. Unknown
formats only receive byte-stream readability evidence. The current change does
not claim that all tool adapters or providers verify every possible user goal.

Native notification replies and SMS submission now preserve their explicit
`delivery_verified=false` caveat through planner evidence and UI completion
checks. API acceptance does not become recipient delivery. These paths must
inspect a real receipt before retrying; this change neither sends test messages
nor introduces an automatic resend. A delivery flag alone is not promoted to
verified success without an identity-bound completion requirement.

Device tests must report disabled accessibility, skipped live tests and missing
model/transport availability explicitly. A successful build is not device
acceptance.

## 2026-10-16 S20U verification

- Android 1.5.31 (1314) built and installed with data preserved.
- 100 selected JVM regression tests passed; repository checks passed.
- S20U instrumentation: three tests passed (checkpoint reload/single claim,
  invalid-argument rejection, unobserved-dispatch non-duplication). The two
  opt-in live tests were skipped, not passed.
- A dedicated conversation submitted `set timer one minute` through the real
  composer. Samsung Clock showed the labelled timer counting down from 44 to
  23 seconds. This was an external ADB observation, not an App-owned observation.
- With accessibility disabled, the App displayed a truthful unconfirmed
  dispatch and an enable-access entry instead of claiming verified success.
- The temporary timer and its dedicated UI conversation were removed. Existing
  user conversations, recurring schedules, contacts and other devices were not
  changed.
- Remaining: enable the S20U GalaxySSI accessibility service, run the complete
  start/repeat/change/pause/resume/cancel test and the configured-model typo
  acceptance. No claim of full goal completion or universal adapter coverage.

### Follow-up regression pass

- Rebuilt and reinstalled Android 1.5.31 on S20U only, preserving App data.
- 110 JVM tests passed, with zero failures, errors or skipped tests. Coverage now
  includes native delivery caveat propagation, persisted-receipt verification,
  ambiguous replacement commands and a label-bound Samsung paused-frame fixture.
- Re-ran S20U instrumentation: three passed, two live tests skipped. Accessibility
  was still disabled; no new live timer/model run or real message send was made.
- Repository checks and whitespace checks passed. The incomplete live acceptance
  above remains open and must not be described as passing.

### Artifact inspection and inspect-before-final pass

- Rebuilt and reinstalled Android 1.5.31 (1314) on S20U only, without clearing data.
- 146 JVM tests passed with zero failures, errors or skipped tests. This includes
  actual UTF-8, ZIP integrity and Office package inspection, hash-bound completion
  evidence, and distinguishing unavailable verification from available inspection.
- S20U instrumentation: four tests passed and two opt-in live tests were skipped.
  The added device test created a real PDF and PNG, verified their openability,
  then confirmed that corrupted replacements could not produce verified evidence.
- No real messages were sent and no other device was operated. Dedicated cache
  files and checkpoint fixtures were removed by the tests.
- The selected phone's accessibility service remained disabled. The continuous
  live timer sequence and configured-model typo acceptance remain unverified.
- A pending outcome with an available inspection path now enters the existing
  repair loop instead of finalizing immediately; an explicitly unavailable
  verification capability still produces an honest unverified result.

### Runtime permission continuation and S20U follow-up

- Built and installed Android 1.5.32 (1315) on S20U only, preserving App data.
- 155 selected JVM tests passed with zero failures, errors or skipped tests.
- Five functional device tests passed. The new test uses a synthetic Android
  permission checker and a local counter tool: it verifies zero dispatches while
  denied, recovery after session reload, rejection of another turn, one dispatch
  after grant, and no dispatch on a repeated callback. It does not grant a real
  permission or open the camera.
- One fixture-cleanup test also passed; this is housekeeping, not an additional
  functional acceptance result. Three opt-in tests were skipped: live timer
  controls, configured-model typo handling, and the foreground permission UI.
- The first separately enabled foreground permission-entry run failed its
  foreground readiness condition. After GalaxySSI was restored to the foreground,
  the same opt-in test passed on S20U (14.172 seconds): another conversation did
  not receive the dialog, the matching conversation did, and repeated offers did
  not duplicate the prompt. This brings functional device acceptance to six
  passes across the class run and separate UI run. The two live timer/model tests
  remain unverified; the UI pass does not substitute for them.
- Direct notification replies now share the same unverified-delivery contract as
  native tools. No real messages were sent.
- Model-planned native actions now persist an Android runtime-permission gate
  before dispatch. Continuation checks session, conversation, turn, plan revision
  and action status, then uses the existing node/effect journals. Denial, cancelled
  work, stale plans and already dispatched actions do not trigger a fresh effect.
  Permission prompts are limited to the matching visible conversation. This is
  not a claim that every special Settings permission or legacy direct-action path
  has the same recovery support.
- Ordinary responses skip permission recovery before constructing another runtime
  snapshot. The rare grant continuation reads only its indexed transcript turn,
  not all historical messages in the conversation.
- Live timer cleanup now retains its checkpoint when cancellation cannot be
  verified. It no longer deletes the only recovery identity for an uncertain timer.
- S20U accessibility remains disabled. The real start/repeat/change/pause/resume/
  cancel sequence and selected-model typo acceptance remain incomplete. No new PR
  was created by this validation pass.

### Final package and Samsung test-lifecycle check

- Rebuilt the final 1.5.32 (1315) package, including the indexed transcript lookup
  and early permission-gate return. Build succeeded; all 155 selected JVM tests
  passed again. Installed the main and test APKs on S20U with data preserved.
- The final class run passed five non-UI functional tests and fixture cleanup;
  two live tests were deliberately skipped. The foreground UI precondition failed
  in this run and in one standalone retry. Its earlier successful run remains
  recorded above, but these retries must not be counted as passes.
- Samsung's accessibility manager records clearing GalaxySSI's enabled service
  on an App force-stop at 16:40:47. Instrumentation startup and completion both
  force-stop the target App, so live accessibility acceptance must not assume
  that a service enabled before instrumentation remains enabled afterwards.
- At the final check, S20U's enabled and bound accessibility-service sets were
  empty. Opened the GalaxySSI screen-Agent system settings page without toggling
  permissions. Continue live acceptance without restarting the App, using the
  existing debug native-tool entry or normal UI; verify service binding first.
- No live timer was created by this pass. No claim of complete end-to-end timer
  or selected-model typo acceptance is made.

### Non-restarting S20U acceptance (1.5.33)

- Confirmed the user-enabled accessibility service was both enabled and bound.
  Installed Android 1.5.33 (1316) with data preserved; the service stayed bound.
- All 156 selected JVM tests passed, with zero failures, errors or skips. The
  repository and whitespace checks passed.
- Real native acceptance exposed two faults: overlapping SET_TIMER/SHOW_TIMERS
  intents, and reading a transitional frame 250 ms after removal. Creation now
  waits for its own observed timer before opening the timer list; cancellation
  requires consecutive complete, recognizable frames without the target label.
- The final non-instrumented run passed all six steps: start 60 seconds, repeat
  start with the same operation ID, replace with 120 seconds and a new ID, pause,
  resume and cancel. Cancellation was verified. The debug audit uses isolated
  scopes and never force-stops the App or grants permissions.
- Local evidence: `%TEMP%/galaxyssi-timer-acceptance/` contains
  `timer-29afe01762694b84a359b765ec03bc52.json` (pass) and the preceding
  `timer-eee7f55fb24e4665bebf966d833aa761.json` (replacement failure). Preserve
  both; the first failed cleanup was not retrospectively counted as passing.
- The normal composer typo trial was interpreted correctly by the selected Codex
  provider, but its ActionPlan was rejected repeatedly before execution. It did
  not pass end-to-end acceptance. On the user's request to stop timer testing,
  the dedicated conversation was cancelled; its runtime reported CANCELLED.
- Follow-up acceptance now moves to representative file, data, application and
  failure-recovery tasks. Plan-validation feedback remains a separate open issue;
  native timer success is not evidence that all model-driven goals succeed.

## Current representative acceptance scope

The user's later instruction replaces further countdown testing with varied
representative tasks. Do not resume the opt-in timer examples above. They remain
historical evidence, not the current test plan. Current per-version results and
known failures are recorded in `REPRESENTATIVE_AGENT_ACCEPTANCE.md`.

| Contract | Current evidence | Remaining acceptance |
| --- | --- | --- |
| Complete request understanding | Exact whole-command parsing for flashlight, volume, camera and recording; unique installed-app resolution; native intent regression tests; real phone-qualified app launch and device-status requests | More selected-model typo/ambiguous-request examples outside timers; remaining legacy shortcut families |
| Executable intent | Real App-selected Codex plans created, exported and modified CSV documents | Additional document/attachment types and broader routes |
| Scoped context and pending work | Real expense and original-subdirectory follow-ups preserved unaffected rows; operation-checkpoint recovery tests; real composer Stop persisted cancellation and a separate task then started | Real cancellation followed by process/device restart; broader document types |
| Observed business outcome | Independently checked source/export/download digests and CSV values; corrupt-artifact rejection; audio inspect/mutate/readback regression tests and S20U read-only state check | Actual volume/mute mutation acceptance, torch observation, recipient delivery and other external adapters |
| Inspect before repair | Stale-patch rejection, missing-file recovery, permission-continuation and effect-journal tests; real model corrected a rejected duplicate-path batch without user intervention | Native scripted repair is not itself proof of model-directed repair in every failure case |
| Evidence-constrained reply | Real log analysis ignored embedded tool instructions; artifact completion checks rejected invalid evidence pointers; unverified device receipts cannot become confirmed UI replies; real history UI includes paged-out earlier work in duration | Unverified direct-shortcut escalation into model-directed recovery; broader rejection/repair examples and provider routes |

Keep synthetic/native, real-model and rendered-UI results separate. A stop test
must check runtime, durable workspace and late-response/recovery behavior, not
only the text shown in the conversation. Do not operate another foreground app
to make these tests pass.
