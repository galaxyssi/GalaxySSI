# Interim milestone dispatch

## Scope

Follow-up to the durable interim publication increment. Android owns the live
team graph; both an Android cloud publication and a remote Desktop publication
enter the same workspace commit and scheduler notification. No UI changes or
new provider defaults are introduced. Android version: 1.4.86 (1171).

The increment enables a coordinator to consume a published version while its
author is still running and append useful follow-up work. It does not establish
that a real model will choose to publish, create a useful plan, improve its
method, or outperform a single agent.

## Contract

- A successful interim publication atomically commits the original, receipt,
  assignment journal and run/turn/round index. Rejected or failed writes cannot
  trigger an accepted-input dispatch.
- A process-local notification wakes only the matching active supervisor.
  Notifications are conflated hints, not a durable queue. Initial reconciliation
  reads committed inputs after a missed notification or process restart.
- An external revision counter handles notifications that arrive while the
  expansion hook is persisting. Expansion remains serial and append-only.
- At most one incremental coordinator is active per run. Its persisted input
  tokens prevent duplicate planning on transport retries. Index admission uses
  pages of 16 milestones; later checkpoints consume the remaining pages rather
  than truncating them.
- `uses_milestones` on a work item names exact host-issued tokens. It grants only
  their immutable workspace versions and explicitly recorded tool observations.
  It does not implicitly expose all author output, later versions, parents, or
  unrelated tasks. Ordinary `depends_on` still waits for whole-task completion.
- Unknown tokens and self-authored independent milestone reviews reject the
  expansion. Existing work cannot change its milestone inputs after admission.
- Scoped evidence bindings and signed goal-contract bindings retain pinned read
  permissions. Remote recall obtains the binding from the phone, not the model.
- Final assessment still waits for all original and newly admitted work. A
  milestone is neither worker completion nor scientific acceptance. Pausing or
  stopping does not dispatch additional milestone work.

## Verification

Targeted tests cover exact-version/evidence isolation, missed wake recovery,
commit failure, index tampering, duplicate receipts, all-page discovery, run/turn/
round isolation, self-review rejection, codec restoration, and a producer held
running while its coordinator and independent peer execute. A separate race
test emits notifications during graph persistence without any child completing.

S26U instrumentation uses synthetic workers and real encrypted storage, with no
provider invocation or original research rerun. It exercises live publication
and publication committed before runtime startup. This is not an OS process-kill,
Doze, network-chaos, or real-model MQTT experiment.

Build/test commands:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests '*Collaboration*Test' --tests '*AgentSubagent*Test' --tests '*AgentTeamLiveGraph*Test' :app:assembleDebug :app:assembleDebugAndroidTest -x :app:buildNativeMemory --console=plain
adb -s $env:S26U_SERIAL shell am instrument -w -r -e class 'com.galaxyssi.chat.CollaborationMilestoneDeviceTest,com.galaxyssi.chat.CollaborationLiveGraphDeviceTest#liveReviewStartsBeforeUnrelatedMemberAndFinalWaits' com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
npm run check
npm run test:core-regressions:contract
```

The native-memory exclusion reuses the existing Rust artifact; it is not a fresh
Rust build verification.

### Results (2026-10-07)

- Android: 1,238 unit tests in 100 suites, zero failures/errors/skips; debug APK
  and instrumentation APK built successfully.
- Repository checks passed; six core-regression contract tests passed.
- S26U: six instrumentation tests passed in 3.979 seconds using real encrypted
  storage and synthetic workers. Version 1.4.86 (1171) was installed in place.
- The first device run had two timeout failures: the new test incorrectly used
  the interrupted-only recovery accessor for a running graph. Diagnostics
  confirmed that both coordinator and peer had started. The fixture now uses
  the live checkpoint accessor and propagates worker assertions immediately;
  production recovery semantics were not relaxed.
- APK SHA-256: `bebc41f27925b0518d8f488a5690ce48533f362222bb4b7c703d9076296c16b0`.

No live model/MQTT trial or Desktop deployment was performed in this increment.

## Remaining evidence

The next scientific trial must distinguish model-chosen early collaboration
from a scripted fixture: publish a candidate before worker termination, inspect
original evidence, choose a peer check, preserve a counterexample, revise the
method, and compare its result under the existing matched-budget protocol.
Typed candidate-cycle admission retains its existing completed-producer contract;
this increment uses new work items for interim checks. Concurrency admission is
unchanged, so no slot means queued work, not unlimited concurrent execution.
